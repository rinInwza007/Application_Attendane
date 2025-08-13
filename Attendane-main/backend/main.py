# main.py
from fastapi import FastAPI, File, UploadFile, HTTPException, Depends, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
import uvicorn
from typing import Optional, List, Dict
import aiohttp
import cv2  
import numpy as np
from datetime import datetime, timedelta
import face_recognition
import io
import base64
from PIL import Image
import json
import os
from dotenv import load_dotenv
from supabase import create_client, Client
import logging
from pydantic import BaseModel

# Load environment variables
load_dotenv()

# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(title="Face Recognition Attendance API", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Supabase configuration
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://cykbwnxcvdszxlypzucy.supabase.co")
SUPABASE_KEY = os.getenv("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5a2J3bnhjdmRzenhseXB6dWN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzIwMDEwMDMsImV4cCI6MjA0NzU3NzAwM30.t51vDsflnqzKVic9tZ_uFpiaS_6RO3J3gOeMJdm0lvo")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Models
class WebcamConfig(BaseModel):
    ip_address: str
    port: int = 8080
    username: Optional[str] = None
    password: Optional[str] = None

class AttendanceCheckIn(BaseModel):
    session_id: str
    student_email: str
    webcam_config: WebcamConfig

class CreateSessionRequest(BaseModel):
    class_id: str
    teacher_email: str
    duration_hours: int = 2
    on_time_limit_minutes: int = 30

class FaceRegistrationRequest(BaseModel):
    student_id: str
    student_email: str

# Helper functions
def encode_face(face_image):
    """Encode face to 128-dimensional vector"""
    try:
        # Convert image to RGB if needed
        if len(face_image.shape) == 2:
            face_image = cv2.cvtColor(face_image, cv2.COLOR_GRAY2RGB)
        elif face_image.shape[2] == 4:
            face_image = cv2.cvtColor(face_image, cv2.COLOR_BGRA2RGB)
        elif face_image.shape[2] == 3:
            face_image = cv2.cvtColor(face_image, cv2.COLOR_BGR2RGB)
        
        # Get face encodings
        face_locations = face_recognition.face_locations(face_image)
        if not face_locations:
            return None
        
        face_encodings = face_recognition.face_encodings(face_image, face_locations)
        if face_encodings:
            return face_encodings[0].tolist()  # Return first face encoding as list
        return None
    except Exception as e:
        logger.error(f"Error encoding face: {e}")
        return None

async def capture_from_ip_webcam(config: WebcamConfig) -> bytes:
    """Capture image from IP Webcam"""
    try:
        url = f"http://{config.ip_address}:{config.port}/photo.jpg"
        
        async with aiohttp.ClientSession() as session:
            # Add basic auth if provided
            auth = None
            if config.username and config.password:
                auth = aiohttp.BasicAuth(config.username, config.password)
            
            async with session.get(url, auth=auth, timeout=10) as response:
                if response.status == 200:
                    return await response.read()
                else:
                    raise HTTPException(status_code=400, detail=f"Failed to capture from webcam: {response.status}")
    except Exception as e:
        logger.error(f"Error capturing from IP webcam: {e}")
        raise HTTPException(status_code=500, detail=str(e))

def process_face_image(image_bytes: bytes) -> Dict:
    """Process face detection and extract features"""
    try:
        # Convert bytes to numpy array
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            raise ValueError("Failed to decode image")
        
        # Detect faces
        face_locations = face_recognition.face_locations(image)
        
        if not face_locations:
            return {
                "success": False,
                "message": "No face detected in image",
                "face_count": 0
            }
        
        if len(face_locations) > 1:
            return {
                "success": False,
                "message": "Multiple faces detected. Please ensure only one person is in frame",
                "face_count": len(face_locations)
            }
        
        # Get face encoding
        face_encoding = encode_face(image)
        
        if face_encoding is None:
            return {
                "success": False,
                "message": "Failed to extract face features"
            }
        
        # Calculate quality score (simple version)
        quality_score = calculate_face_quality(image, face_locations[0])
        
        return {
            "success": True,
            "face_encoding": face_encoding,
            "face_location": face_locations[0],
            "quality_score": quality_score,
            "message": "Face processed successfully"
        }
    
    except Exception as e:
        logger.error(f"Error processing face: {e}")
        return {
            "success": False,
            "message": f"Error processing image: {str(e)}"
        }

def calculate_face_quality(image, face_location):
    """Calculate face quality score"""
    try:
        top, right, bottom, left = face_location
        face_img = image[top:bottom, left:right]
        
        # Simple quality metrics
        # 1. Size check
        face_area = (right - left) * (bottom - top)
        image_area = image.shape[0] * image.shape[1]
        size_ratio = face_area / image_area
        
        # 2. Blur detection (Laplacian)
        gray = cv2.cvtColor(face_img, cv2.COLOR_BGR2GRAY)
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        
        # 3. Brightness check
        brightness = np.mean(gray)
        
        # Calculate quality score (0.0 to 1.0)
        size_score = min(size_ratio * 10, 1.0)  # Face should be at least 10% of image
        blur_score = min(laplacian_var / 500, 1.0)  # Higher variance = less blur
        brightness_score = 1.0 - abs(brightness - 128) / 128  # Best around 128
        
        quality_score = (size_score + blur_score + brightness_score) / 3
        
        return round(quality_score, 3)
    except:
        return 0.5

def compare_faces(encoding1: List[float], encoding2: List[float], threshold: float = 0.6) -> Dict:
    """Compare two face encodings"""
    try:
        # Convert to numpy arrays
        enc1 = np.array(encoding1)
        enc2 = np.array(encoding2)
        
        # Calculate distance
        distance = face_recognition.face_distance([enc1], enc2)[0]
        similarity = 1 - distance
        is_match = distance <= threshold
        
        return {
            "is_match": is_match,
            "similarity": float(similarity),
            "distance": float(distance),
            "threshold": threshold
        }
    except Exception as e:
        logger.error(f"Error comparing faces: {e}")
        return {
            "is_match": False,
            "similarity": 0.0,
            "distance": 1.0,
            "error": str(e)
        }

# API Endpoints
@app.get("/")
async def root():
    return {
        "message": "Face Recognition Attendance API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "register_face": "/api/face/register",
            "verify_face": "/api/face/verify",
            "capture_webcam": "/api/webcam/capture",
            "check_in": "/api/attendance/checkin",
            "create_session": "/api/attendance/session/create",
            "end_session": "/api/attendance/session/{session_id}/end"
        }
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat()
    }

@app.post("/api/face/register")
async def register_face(
    file: UploadFile = File(...),
    student_id: str = Form(...),
    student_email: str = Form(...)
):
    """Register a student's face"""
    try:
        # Read and process image
        contents = await file.read()
        result = process_face_image(contents)
        
        if not result["success"]:
            raise HTTPException(status_code=400, detail=result["message"])
        
        # Save face encoding to Supabase
        face_data = {
            "student_id": student_id,
            "face_embedding_json": json.dumps(result["face_encoding"]),
            "face_quality": result["quality_score"],
            "is_active": True,
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat()
        }
        
        # Check if student already has face data
        existing = supabase.table("student_face_embeddings").select("*").eq("student_id", student_id).execute()
        
        if existing.data:
            # Update existing record
            response = supabase.table("student_face_embeddings").update(face_data).eq("student_id", student_id).execute()
        else:
            # Insert new record
            response = supabase.table("student_face_embeddings").insert(face_data).execute()
        
        return {
            "success": True,
            "message": "Face registered successfully",
            "student_id": student_id,
            "quality_score": result["quality_score"]
        }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error registering face: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/face/verify")
async def verify_face(
    file: UploadFile = File(...),
    student_id: str = Form(...)
):
    """Verify a student's face against stored encoding"""
    try:
        # Get stored face encoding
        response = supabase.table("student_face_embeddings").select("face_embedding_json").eq("student_id", student_id).eq("is_active", True).execute()
        
        if not response.data:
            raise HTTPException(status_code=404, detail="No face data found for student")
        
        stored_encoding = json.loads(response.data[0]["face_embedding_json"])
        
        # Process uploaded image
        contents = await file.read()
        result = process_face_image(contents)
        
        if not result["success"]:
            raise HTTPException(status_code=400, detail=result["message"])
        
        # Compare faces
        comparison = compare_faces(stored_encoding, result["face_encoding"])
        
        return {
            "success": True,
            "verified": comparison["is_match"],
            "similarity": comparison["similarity"],
            "quality_score": result["quality_score"]
        }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error verifying face: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/webcam/capture")
async def capture_webcam_image(config: WebcamConfig):
    """Capture image from IP webcam"""
    try:
        image_bytes = await capture_from_ip_webcam(config)
        
        # Return image as response
        return StreamingResponse(
            io.BytesIO(image_bytes),
            media_type="image/jpeg",
            headers={"Content-Disposition": "attachment; filename=capture.jpg"}
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error capturing webcam: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/attendance/checkin")
async def check_in_attendance(request: AttendanceCheckIn):
    """Check in student attendance with face recognition"""
    try:
        # Verify session is active
        session_response = supabase.table("attendance_sessions").select("*").eq("id", request.session_id).eq("status", "active").execute()
        
        if not session_response.data:
            raise HTTPException(status_code=404, detail="Active session not found")
        
        session = session_response.data[0]
        
        # Check if already checked in
        existing = supabase.table("attendance_records").select("*").eq("session_id", request.session_id).eq("student_email", request.student_email).execute()
        
        if existing.data:
            raise HTTPException(status_code=400, detail="Already checked in for this session")
        
        # Capture image from webcam
        image_bytes = await capture_from_ip_webcam(request.webcam_config)
        
        # Process face
        face_result = process_face_image(image_bytes)
        
        if not face_result["success"]:
            raise HTTPException(status_code=400, detail=face_result["message"])
        
        # Get student info and face encoding
        student_response = supabase.table("users").select("school_id").eq("email", request.student_email).execute()
        
        if not student_response.data:
            raise HTTPException(status_code=404, detail="Student not found")
        
        student_id = student_response.data[0]["school_id"]
        
        # Get stored face encoding
        face_response = supabase.table("student_face_embeddings").select("face_embedding_json").eq("student_id", student_id).eq("is_active", True).execute()
        
        if not face_response.data:
            # No face data, just record attendance without verification
            face_match_score = None
        else:
            # Verify face
            stored_encoding = json.loads(face_response.data[0]["face_embedding_json"])
            comparison = compare_faces(stored_encoding, face_result["face_encoding"])
            
            if not comparison["is_match"]:
                raise HTTPException(status_code=403, detail="Face verification failed")
            
            face_match_score = comparison["similarity"]
        
        # Determine attendance status
        check_in_time = datetime.now()
        on_time_deadline = datetime.fromisoformat(session["start_time"]) + timedelta(minutes=session["on_time_limit_minutes"])
        
        status = "present" if check_in_time <= on_time_deadline else "late"
        
        # Save attendance record
        attendance_data = {
            "session_id": request.session_id,
            "student_email": request.student_email,
            "student_id": student_id,
            "check_in_time": check_in_time.isoformat(),
            "status": status,
            "face_match_score": face_match_score,
            "created_at": check_in_time.isoformat()
        }
        
        response = supabase.table("attendance_records").insert(attendance_data).execute()
        
        return {
            "success": True,
            "message": f"Check-in successful - {status.upper()}",
            "status": status,
            "check_in_time": check_in_time.isoformat(),
            "face_match_score": face_match_score
        }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in check-in: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/attendance/session/create")
async def create_attendance_session(request: CreateSessionRequest):
    """Create new attendance session"""
    try:
        # Check for existing active session
        existing = supabase.table("attendance_sessions").select("*").eq("class_id", request.class_id).eq("status", "active").execute()
        
        if existing.data:
            raise HTTPException(status_code=400, detail="Active session already exists for this class")
        
        # Create session
        start_time = datetime.now()
        end_time = start_time + timedelta(hours=request.duration_hours)
        
        session_data = {
            "class_id": request.class_id,
            "teacher_email": request.teacher_email,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "on_time_limit_minutes": request.on_time_limit_minutes,
            "status": "active",
            "created_at": start_time.isoformat()
        }
        
        response = supabase.table("attendance_sessions").insert(session_data).execute()
        
        return {
            "success": True,
            "session_id": response.data[0]["id"],
            "message": "Attendance session created successfully"
        }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating session: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/api/attendance/session/{session_id}/end")
async def end_attendance_session(session_id: str):
    """End attendance session"""
    try:
        # Update session status
        response = supabase.table("attendance_sessions").update({
            "status": "ended",
            "updated_at": datetime.now().isoformat()
        }).eq("id", session_id).execute()
        
        if not response.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Mark absent students
        # Get class students
        session = response.data[0]
        students_response = supabase.table("class_students").select("student_email, users!inner(school_id)").eq("class_id", session["class_id"]).execute()
        
        # Get checked-in students
        attended_response = supabase.table("attendance_records").select("student_email").eq("session_id", session_id).execute()
        attended_emails = {record["student_email"] for record in attended_response.data}
        
        # Create absent records
        absent_records = []
        for student in students_response.data:
            if student["student_email"] not in attended_emails:
                absent_records.append({
                    "session_id": session_id,
                    "student_email": student["student_email"],
                    "student_id": student["users"]["school_id"],
                    "check_in_time": datetime.now().isoformat(),
                    "status": "absent",
                    "created_at": datetime.now().isoformat()
                })
        
        if absent_records:
            supabase.table("attendance_records").insert(absent_records).execute()
        
        return {
            "success": True,
            "message": "Session ended successfully",
            "absent_count": len(absent_records)
        }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error ending session: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/attendance/session/{session_id}/records")
async def get_session_attendance_records(session_id: str):
    """Get attendance records for a session"""
    try:
        response = supabase.table("attendance_records").select("*, users!attendance_records_student_email_fkey(full_name, school_id)").eq("session_id", session_id).order("check_in_time").execute()
        
        return {
            "success": True,
            "records": response.data,
            "total": len(response.data)
        }
    
    except Exception as e:
        logger.error(f"Error getting records: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)