# Improved Face Recognition Server with Supabase Integration
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.security import HTTPBearer
from pydantic import BaseModel
import cv2
import face_recognition
import numpy as np
import io
import base64
from PIL import Image
import json
from typing import Optional, Dict, Any, List
import requests
from datetime import datetime, timedelta
import logging
from dotenv import load_dotenv
import os
from supabase import create_client, Client

# Load environment variables
load_dotenv()

# Configuration
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", 8000))
DEBUG = os.getenv("DEBUG", "false").lower() == "true"
FACE_THRESHOLD = float(os.getenv("FACE_VERIFICATION_THRESHOLD", 0.7))
SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key")

# Supabase setup
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("SUPABASE_URL and SUPABASE_ANON_KEY must be set in environment variables")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Attendance Plus Face Recognition API",
    description="Face Recognition Server for Attendance System",
    version="2.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer(auto_error=False)

# Pydantic models
class AttendanceCheckInRequest(BaseModel):
    session_id: str
    student_email: str
    webcam_config: Optional[Dict[str, Any]] = None

class AttendanceSessionRequest(BaseModel):
    class_id: str
    teacher_email: str
    duration_hours: int = 2
    on_time_limit_minutes: int = 30

class WebcamCaptureRequest(BaseModel):
    ip_address: str
    port: int = 8080
    username: Optional[str] = ""
    password: Optional[str] = ""

# Custom exceptions
class FaceRecognitionException(Exception):
    def __init__(self, message: str, error_code: str = None):
        self.message = message
        self.error_code = error_code
        super().__init__(self.message)

@app.exception_handler(FaceRecognitionException)
async def face_recognition_exception_handler(request, exc):
    return JSONResponse(
        status_code=400,
        content={"detail": exc.message, "error_code": exc.error_code}
    )

@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail}
    )

# Startup event
@app.on_event("startup")
async def startup_event():
    logger.info("🚀 Face Recognition Server starting...")
    
    # Test Supabase connection
    try:
        result = supabase.table('users').select("count", count='exact').execute()
        logger.info("✅ Supabase connection successful")
    except Exception as e:
        logger.warning(f"⚠️ Supabase connection warning: {e}")
    
    logger.info("✅ Server started successfully")

# Health endpoints
@app.get("/")
async def root():
    return {
        "message": "Attendance Plus Face Recognition API",
        "version": "2.0.0",
        "status": "running",
        "timestamp": datetime.now().isoformat(),
        "endpoints": {
            "health": "/health",
            "face_register": "/api/face/register",
            "face_verify": "/api/face/verify",
            "webcam_capture": "/api/webcam/capture",
            "attendance_checkin": "/api/attendance/checkin",
            "session_create": "/api/attendance/session/create"
        }
    }

@app.get("/health")
async def health_check():
    try:
        # Test face_recognition library
        test_array = np.zeros((100, 100, 3), dtype=np.uint8)
        face_recognition.face_locations(test_array)
        
        # Test Supabase
        supabase.table('users').select("count", count='exact').execute()
        
        return {
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "services": {
                "face_recognition": "ok",
                "supabase": "ok"
            }
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "timestamp": datetime.now().isoformat(),
            "error": str(e)
        }

# Helper functions
def validate_image(image_file: UploadFile) -> None:
    """Validate uploaded image file"""
    if not image_file.content_type.startswith('image/'):
        raise FaceRecognitionException("File must be an image", "INVALID_FILE_TYPE")
    
    # Check file size (10MB limit)
    if hasattr(image_file, 'size') and image_file.size > 10 * 1024 * 1024:
        raise FaceRecognitionException("Image file too large (max 10MB)", "FILE_TOO_LARGE")

def process_face_image(image_file: UploadFile) -> tuple:
    """Process uploaded image and extract face encoding"""
    try:
        validate_image(image_file)
        
        # Read and convert image
        image_data = image_file.file.read()
        image = Image.open(io.BytesIO(image_data))
        
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        image_array = np.array(image)
        
        # Resize if too large
        height, width = image_array.shape[:2]
        if width > 1024 or height > 1024:
            scale = min(1024/width, 1024/height)
            new_width = int(width * scale)
            new_height = int(height * scale)
            image_array = cv2.resize(image_array, (new_width, new_height))
        
        # Detect faces
        face_locations = face_recognition.face_locations(image_array, model="hog")
        
        if len(face_locations) == 0:
            raise FaceRecognitionException("No face detected in image", "NO_FACE_DETECTED")
        
        if len(face_locations) > 1:
            raise FaceRecognitionException("Multiple faces detected", "MULTIPLE_FACES")
        
        # Get face encoding
        face_encodings = face_recognition.face_encodings(image_array, face_locations, num_jitters=2)
        
        if len(face_encodings) == 0:
            raise FaceRecognitionException("Could not encode face", "ENCODING_FAILED")
        
        return face_encodings[0], face_locations[0]
        
    except FaceRecognitionException:
        raise
    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        raise FaceRecognitionException(f"Image processing failed: {str(e)}", "PROCESSING_ERROR")

def save_face_to_supabase(student_id: str, student_email: str, encoding: np.ndarray) -> bool:
    """Save face embedding to Supabase"""
    try:
        # Convert encoding to JSON-serializable format
        embedding_json = encoding.tolist()
        
        # Calculate quality score (simplified)
        quality_score = np.linalg.norm(encoding)
        
        face_data = {
            'student_id': student_id,
            'face_embedding_json': json.dumps(embedding_json),
            'face_quality': float(quality_score),
            'is_active': True,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat()
        }
        
        # Upsert face embedding
        result = supabase.table('student_face_embeddings').upsert(face_data).execute()
        
        logger.info(f"Face data saved for student: {student_id}")
        return True
        
    except Exception as e:
        logger.error(f"Error saving to Supabase: {str(e)}")
        return False

def get_face_from_supabase(student_id: str) -> Optional[np.ndarray]:
    """Retrieve face embedding from Supabase"""
    try:
        result = supabase.table('student_face_embeddings').select('face_embedding_json').eq('student_id', student_id).eq('is_active', True).single().execute()
        
        if result.data:
            embedding_json = json.loads(result.data['face_embedding_json'])
            return np.array(embedding_json, dtype=np.float64)
        
        return None
        
    except Exception as e:
        logger.error(f"Error retrieving from Supabase: {str(e)}")
        return None

def calculate_similarity(encoding1: np.ndarray, encoding2: np.ndarray) -> float:
    """Calculate face similarity using multiple metrics"""
    try:
        # Euclidean distance
        euclidean_distance = np.linalg.norm(encoding1 - encoding2)
        
        # Cosine similarity
        dot_product = np.dot(encoding1, encoding2)
        norm_a = np.linalg.norm(encoding1)
        norm_b = np.linalg.norm(encoding2)
        
        if norm_a == 0 or norm_b == 0:
            cosine_similarity = 0
        else:
            cosine_similarity = dot_product / (norm_a * norm_b)
        
        # Combined score (weighted average)
        distance_score = max(0, 1 - euclidean_distance)
        final_score = (distance_score * 0.7) + (cosine_similarity * 0.3)
        
        return float(np.clip(final_score, 0, 1))
        
    except Exception as e:
        logger.error(f"Error calculating similarity: {str(e)}")
        return 0.0

# API Endpoints

@app.post("/api/face/register")
async def register_face(
    file: UploadFile = File(...),
    student_id: str = Form(...),
    student_email: str = Form(...)
):
    """Register face for a student"""
    try:
        logger.info(f"Registering face for student: {student_id}")
        
        # Process image
        face_encoding, face_location = process_face_image(file)
        
        # Save to Supabase
        success = save_face_to_supabase(student_id, student_email, face_encoding)
        
        if not success:
            raise HTTPException(status_code=500, detail="Failed to save face data")
        
        return {
            "success": True,
            "message": "Face registered successfully",
            "student_id": student_id,
            "student_email": student_email,
            "face_location": {
                "top": int(face_location[0]),
                "right": int(face_location[1]),
                "bottom": int(face_location[2]),
                "left": int(face_location[3])
            },
            "timestamp": datetime.now().isoformat()
        }
        
    except FaceRecognitionException as e:
        raise HTTPException(status_code=400, detail=e.message)
    except Exception as e:
        logger.error(f"Registration error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")

@app.post("/api/face/verify")
async def verify_face(
    file: UploadFile = File(...),
    student_id: str = Form(...)
):
    """Verify face against stored data"""
    try:
        logger.info(f"Verifying face for student: {student_id}")
        
        # Get stored encoding
        stored_encoding = get_face_from_supabase(student_id)
        if stored_encoding is None:
            raise HTTPException(status_code=404, detail="No face data found for student")
        
        # Process current image
        current_encoding, face_location = process_face_image(file)
        
        # Calculate similarity
        similarity = calculate_similarity(stored_encoding, current_encoding)
        verified = similarity >= FACE_THRESHOLD
        
        logger.info(f"Verification result: similarity={similarity:.3f}, verified={verified}")
        
        return {
            "success": True,
            "verified": verified,
            "similarity": similarity,
            "threshold": FACE_THRESHOLD,
            "student_id": student_id,
            "confidence": "high" if similarity > 0.8 else "medium" if similarity > 0.6 else "low",
            "timestamp": datetime.now().isoformat()
        }
        
    except FaceRecognitionException as e:
        raise HTTPException(status_code=400, detail=e.message)
    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Verification failed: {str(e)}")

@app.post("/api/webcam/capture")
async def capture_from_webcam(request: WebcamCaptureRequest):
    """Capture image from IP webcam"""
    try:
        webcam_url = f"http://{request.ip_address}:{request.port}/photo.jpg"
        
        auth = None
        if request.username and request.password:
            auth = (request.username, request.password)
        
        response = requests.get(webcam_url, auth=auth, timeout=10)
        
        if response.status_code != 200:
            raise HTTPException(status_code=400, detail="Failed to capture from webcam")
        
        return StreamingResponse(
            io.BytesIO(response.content),
            media_type="image/jpeg",
            headers={"Content-Disposition": "attachment; filename=capture.jpg"}
        )
        
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Webcam connection failed: {str(e)}")

@app.post("/api/attendance/session/create")
async def create_attendance_session(request: AttendanceSessionRequest):
    """Create new attendance session"""
    try:
        start_time = datetime.now()
        end_time = start_time + timedelta(hours=request.duration_hours)
        
        session_data = {
            'class_id': request.class_id,
            'teacher_email': request.teacher_email,
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'on_time_limit_minutes': request.on_time_limit_minutes,
            'status': 'active',
            'created_at': start_time.isoformat()
        }
        
        result = supabase.table('attendance_sessions').insert(session_data).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to create session")
        
        session_id = result.data[0]['id']
        logger.info(f"Created attendance session: {session_id}")
        
        return {
            "success": True,
            "session_id": session_id,
            "message": "Attendance session created successfully",
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat()
        }
        
    except Exception as e:
        logger.error(f"Session creation error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to create session: {str(e)}")

@app.post("/api/attendance/checkin")
async def checkin_with_face_recognition(request: AttendanceCheckInRequest):
    """Check in attendance with face recognition"""
    try:
        # Validate session
        session_result = supabase.table('attendance_sessions').select('*').eq('id', request.session_id).eq('status', 'active').single().execute()
        
        if not session_result.data:
            raise HTTPException(status_code=404, detail="Active session not found")
        
        session_data = session_result.data
        session_end = datetime.fromisoformat(session_data['end_time'].replace('Z', '+00:00'))
        
        if datetime.now() > session_end:
            raise HTTPException(status_code=400, detail="Session has ended")
        
        # Check if already checked in
        existing_record = supabase.table('attendance_records').select('*').eq('session_id', request.session_id).eq('student_email', request.student_email).execute()
        
        if existing_record.data:
            raise HTTPException(status_code=400, detail="Already checked in for this session")
        
        # Get student info
        student_result = supabase.table('users').select('school_id').eq('email', request.student_email).single().execute()
        
        if not student_result.data:
            raise HTTPException(status_code=404, detail="Student not found")
        
        student_id = student_result.data['school_id']
        
        # For webcam-based check-in, capture and verify face
        if request.webcam_config:
            # Capture from webcam
            webcam_url = f"http://{request.webcam_config['ip_address']}:{request.webcam_config.get('port', 8080)}/photo.jpg"
            response = requests.get(webcam_url, timeout=10)
            
            if response.status_code != 200:
                raise HTTPException(status_code=400, detail="Failed to capture from webcam")
            
            # Process captured image
            image = Image.open(io.BytesIO(response.content))
            image_array = np.array(image)
            
            face_locations = face_recognition.face_locations(image_array)
            if not face_locations:
                raise HTTPException(status_code=400, detail="No face detected in captured image")
            
            face_encodings = face_recognition.face_encodings(image_array, face_locations)
            if not face_encodings:
                raise HTTPException(status_code=400, detail="Could not encode face")
            
            # Verify against stored face
            stored_encoding = get_face_from_supabase(student_id)
            if stored_encoding is None:
                raise HTTPException(status_code=404, detail="No face data found for student")
            
            similarity = calculate_similarity(stored_encoding, face_encodings[0])
            
            if similarity < FACE_THRESHOLD:
                raise HTTPException(status_code=400, detail="Face verification failed")
        else:
            similarity = None
        
        # Determine attendance status
        check_in_time = datetime.now()
        session_start = datetime.fromisoformat(session_data['start_time'].replace('Z', '+00:00'))
        on_time_limit = session_start + timedelta(minutes=session_data['on_time_limit_minutes'])
        
        status = 'present' if check_in_time <= on_time_limit else 'late'
        
        # Save attendance record
        record_data = {
            'session_id': request.session_id,
            'student_email': request.student_email,
            'student_id': student_id,
            'check_in_time': check_in_time.isoformat(),
            'status': status,
            'face_match_score': similarity,
            'created_at': check_in_time.isoformat()
        }
        
        result = supabase.table('attendance_records').insert(record_data).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to save attendance record")
        
        logger.info(f"Attendance recorded: {request.student_email} - {status}")
        
        return {
            "success": True,
            "message": f"Attendance recorded - {status.upper()}",
            "student_email": request.student_email,
            "student_id": student_id,
            "session_id": request.session_id,
            "status": status,
            "check_in_time": check_in_time.isoformat(),
            "face_match_score": similarity,
            "face_verified": similarity is not None and similarity >= FACE_THRESHOLD if similarity else False
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Check-in error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Check-in failed: {str(e)}")

@app.get("/api/attendance/session/{session_id}/records")
async def get_session_records(session_id: str):
    """Get attendance records for a session"""
    try:
        result = supabase.table('attendance_records').select('*, users(full_name, school_id)').eq('session_id', session_id).order('check_in_time').execute()
        
        return {
            "success": True,
            "session_id": session_id,
            "records": result.data,
            "count": len(result.data)
        }
        
    except Exception as e:
        logger.error(f"Error getting records: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to get records: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    print(f"🚀 Starting Face Recognition Server on {HOST}:{PORT}")
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")