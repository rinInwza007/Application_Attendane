# Enhanced Face Recognition Server with Periodic Attendance Support
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
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
import asyncio
import uuid
from concurrent.futures import ThreadPoolExecutor
import threading
import time

# Load environment variables
load_dotenv()

# Configuration
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", 8000))
DEBUG = os.getenv("DEBUG", "false").lower() == "true"
FACE_THRESHOLD = float(os.getenv("FACE_VERIFICATION_THRESHOLD", 0.7))

# Supabase setup
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("SUPABASE_URL and SUPABASE_ANON_KEY must be set")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Enhanced Attendance Plus Face Recognition API",
    description="Face Recognition Server with Periodic Attendance Support",
    version="3.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Thread pool for processing
executor = ThreadPoolExecutor(max_workers=4)

# In-memory cache for face embeddings (for performance)
face_cache = {}
cache_lock = threading.Lock()

# Pydantic models
class PeriodicAttendanceRequest(BaseModel):
    session_id: str
    capture_time: str
    image_path: Optional[str] = None

class AttendanceSessionRequest(BaseModel):
    class_id: str
    teacher_email: str
    duration_hours: int = 2
    capture_interval_minutes: int = 5
    on_time_limit_minutes: int = 30

class FaceEnrollmentRequest(BaseModel):
    student_id: str
    student_email: str

# Enhanced helper functions
def get_face_embedding_cached(student_id: str) -> Optional[np.ndarray]:
    """Get face embedding with caching"""
    with cache_lock:
        if student_id in face_cache:
            return face_cache[student_id]
    
    try:
        result = supabase.table('student_face_embeddings').select('face_embedding_json').eq('student_id', student_id).eq('is_active', True).single().execute()
        
        if result.data:
            embedding_json = json.loads(result.data['face_embedding_json'])
            embedding = np.array(embedding_json, dtype=np.float64)
            
            # Cache the embedding
            with cache_lock:
                face_cache[student_id] = embedding
            
            return embedding
    except Exception as e:
        logger.error(f"Error getting face embedding for {student_id}: {e}")

    return None

def process_multiple_faces(image_array: np.ndarray, enrolled_students: List[str]) -> List[Dict]:
    """Process multiple faces in an image and identify students"""
    try:
        if image_array is None or image_array.size == 0:
            logger.warning("Empty image array provided")
            return []
        
        if not enrolled_students:
            logger.warning("No enrolled students provided")
            return []
        
        # Detect all faces
        face_locations = face_recognition.face_locations(image_array, model="hog")
        
        if not face_locations:
            logger.info("No faces detected in image")
            return []
        
        logger.info(f"Detected {len(face_locations)} faces")
        
        # Get encodings for all detected faces
        try:
            face_encodings = face_recognition.face_encodings(image_array, face_locations, num_jitters=1)
        except Exception as e:
            logger.error(f"Error getting face encodings: {e}")
            return []
        
        if len(face_encodings) != len(face_locations):
            logger.warning(f"Encoding count ({len(face_encodings)}) doesn't match location count ({len(face_locations)})")
        
        detected_faces = []
        
        for i, (encoding, location) in enumerate(zip(face_encodings, face_locations)):
            try:
                best_match = None
                best_similarity = 0.0
                
                # Compare with all enrolled students
                for student_id in enrolled_students:
                    try:
                        stored_embedding = get_face_embedding_cached(student_id)
                        if stored_embedding is None:
                            continue
                        
                        # Calculate similarity
                        similarity = calculate_enhanced_similarity(stored_embedding, encoding)
                        
                        if similarity > FACE_THRESHOLD and similarity > best_similarity:
                            best_similarity = similarity
                            best_match = student_id
                            
                    except Exception as e:
                        logger.error(f"Error comparing with student {student_id}: {e}")
                        continue
                
                # Calculate face quality metrics
                try:
                    quality = calculate_face_quality(image_array, location)
                except Exception as e:
                    logger.error(f"Error calculating face quality: {e}")
                    quality = {"overall_score": 0.0}
                
                face_info = {
                    'face_index': i,
                    'student_id': best_match,
                    'confidence': float(best_similarity),
                    'verified': best_match is not None,
                    'bounding_box': {
                        'top': int(location[0]),
                        'right': int(location[1]),
                        'bottom': int(location[2]),
                        'left': int(location[3])
                    },
                    'quality': quality
                }
                
                detected_faces.append(face_info)
                
            except Exception as e:
                logger.error(f"Error processing face {i}: {e}")
                continue
        
        logger.info(f"Successfully processed {len(detected_faces)} faces")
        return detected_faces
        
    except Exception as e:
        logger.error(f"Error processing multiple faces: {e}")
        return []

def calculate_face_quality(image_array: np.ndarray, face_location: tuple) -> Dict[str, float]:
    """Calculate comprehensive face quality metrics"""
    try:
        top, right, bottom, left = face_location
        face_image = image_array[top:bottom, left:right]
        
        if face_image.size == 0:
            return {"overall_score": 0.0}
        
        # Convert to grayscale for analysis
        gray_face = cv2.cvtColor(face_image, cv2.COLOR_RGB2GRAY)
        
        # Brightness (mean intensity)
        brightness = np.mean(gray_face) / 255.0
        
        # Contrast (standard deviation)
        contrast = np.std(gray_face) / 255.0
        
        # Sharpness (Laplacian variance)
        laplacian = cv2.Laplacian(gray_face, cv2.CV_64F)
        sharpness = np.var(laplacian) / 10000.0  # Normalize
        
        # Size score (larger faces are generally better)
        face_area = (right - left) * (bottom - top)
        image_area = image_array.shape[0] * image_array.shape[1]
        size_ratio = face_area / image_area
        size_score = min(size_ratio * 10, 1.0)  # Cap at 1.0
        
        # Overall quality score (weighted average)
        overall_score = (
            brightness * 0.2 +
            contrast * 0.3 +
            min(sharpness, 1.0) * 0.3 +
            size_score * 0.2
        )
        
        return {
            'brightness': float(brightness),
            'contrast': float(contrast),
            'sharpness': float(min(sharpness, 1.0)),
            'size_score': float(size_score),
            'overall_score': float(overall_score)
        }
        
    except Exception as e:
        logger.error(f"Error calculating face quality: {e}")
        return {"overall_score": 0.0}

def calculate_enhanced_similarity(embedding1: np.ndarray, embedding2: np.ndarray) -> float:
    """Enhanced similarity calculation with multiple metrics"""
    try:
        # Euclidean distance
        euclidean_distance = np.linalg.norm(embedding1 - embedding2)
        euclidean_score = max(0, 1 - euclidean_distance)
        
        # Cosine similarity
        dot_product = np.dot(embedding1, embedding2)
        norm_a = np.linalg.norm(embedding1)
        norm_b = np.linalg.norm(embedding2)
        
        if norm_a == 0 or norm_b == 0:
            cosine_similarity = 0
        else:
            cosine_similarity = dot_product / (norm_a * norm_b)
        
        # Manhattan distance
        manhattan_distance = np.sum(np.abs(embedding1 - embedding2))
        manhattan_score = max(0, 1 - manhattan_distance / len(embedding1))
        
        # Weighted combination
        final_score = (
            euclidean_score * 0.5 +
            cosine_similarity * 0.3 +
            manhattan_score * 0.2
        )
        
        return float(np.clip(final_score, 0, 1))
        
    except Exception as e:
        logger.error(f"Error calculating similarity: {e}")
        return 0.0

async def get_enrolled_students_for_class(class_id: str) -> List[str]:
    """Get list of enrolled students for a class"""
    try:
        result = supabase.table('class_students').select('users(school_id)').eq('class_id', class_id).execute()
        
        if not result.data:
            logger.warning(f"No enrolled students found for class {class_id}")
            return []
        
        student_ids = []
        for record in result.data:
            if record and record.get('users') and record['users'].get('school_id'):
                student_ids.append(record['users']['school_id'])
        
        logger.info(f"Found {len(student_ids)} enrolled students for class {class_id}")
        return student_ids
        
    except Exception as e:
        logger.error(f"Error getting enrolled students for class {class_id}: {e}")
        return []

# Enhanced API Endpoints
@app.on_event("startup")
async def startup_event():
    """Validate configuration on startup"""
    logger.info("🚀 Starting Face Recognition Server...")
    
    # Validate environment variables
    required_env_vars = ["SUPABASE_URL", "SUPABASE_ANON_KEY"]
    missing_vars = [var for var in required_env_vars if not os.getenv(var)]
    
    if missing_vars:
        logger.error(f"❌ Missing required environment variables: {missing_vars}")
        raise ValueError(f"Missing environment variables: {missing_vars}")
    
    # Test face_recognition
    try:
        test_array = np.zeros((50, 50, 3), dtype=np.uint8)
        face_recognition.face_locations(test_array)
        logger.info("✅ Face recognition library working")
    except Exception as e:
        logger.error(f"❌ Face recognition test failed: {e}")
    
    # Test Supabase connection
    try:
        supabase.table('users').select("count", count='exact').limit(1).execute()
        logger.info("✅ Supabase connection working")
    except Exception as e:
        logger.error(f"❌ Supabase connection test failed: {e}")
    
    logger.info(f"✅ Server startup complete. Face threshold: {FACE_THRESHOLD}")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("🛑 Shutting down Face Recognition Server...")
    
    # Clear cache
    with cache_lock:
        face_cache.clear()
    
    # Shutdown thread pool
    executor.shutdown(wait=True)
    
    logger.info("✅ Server shutdown complete")

@app.post("/api/face/enroll")
async def enroll_face_multiple_images(
    images: List[UploadFile] = File(...),
    student_id: str = Form(...),
    student_email: str = Form(...)
):
    """Enroll face using multiple images for better accuracy"""
    try:
        if not images or len(images) == 0:
            raise HTTPException(status_code=400, detail="At least one image is required")
        
        if len(images) > 5:
            raise HTTPException(status_code=400, detail="Maximum 5 images allowed")
        
        logger.info(f"Enrolling face for {student_id} with {len(images)} images")
        
        all_encodings = []
        
        # Process each image
        for idx, image_file in enumerate(images):
            try:
                # Validate and process image
                image_data = await image_file.read()
                image = Image.open(io.BytesIO(image_data))
                
                if image.mode != 'RGB':
                    image = image.convert('RGB')
                
                image_array = np.array(image)
                
                # Detect face
                face_locations = face_recognition.face_locations(image_array, model="hog")
                
                if len(face_locations) == 0:
                    logger.warning(f"No face detected in image {idx + 1}")
                    continue
                
                if len(face_locations) > 1:
                    logger.warning(f"Multiple faces detected in image {idx + 1}, using the first one")
                
                # Get face encoding
                face_encodings = face_recognition.face_encodings(image_array, face_locations[:1], num_jitters=2)
                
                if face_encodings:
                    all_encodings.append(face_encodings[0])
                    logger.info(f"Successfully processed image {idx + 1}")
                
            except Exception as e:
                logger.error(f"Error processing image {idx + 1}: {e}")
                continue
        
        if not all_encodings:
            raise HTTPException(status_code=400, detail="No valid face encodings could be extracted from the images")
        
        if len(all_encodings) < len(images) * 0.6:  # At least 60% success rate
            logger.warning(f"Only {len(all_encodings)}/{len(images)} images processed successfully")
        
        # Calculate average encoding
        average_encoding = np.mean(all_encodings, axis=0)
        
        # Calculate quality score
        quality_score = len(all_encodings) / len(images)  # Success rate as quality indicator
        
        # Save to database
        success = await save_face_embedding_to_db(student_id, student_email, average_encoding, quality_score)
        
        if not success:
            raise HTTPException(status_code=500, detail="Failed to save face data")
        
        # Clear cache for this student
        with cache_lock:
            if student_id in face_cache:
                del face_cache[student_id]
        
        return {
            "success": True,
            "message": f"Face enrolled successfully using {len(all_encodings)} images",
            "student_id": student_id,
            "images_processed": len(all_encodings),
            "total_images": len(images),
            "quality_score": quality_score,
            "timestamp": datetime.now().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Face enrollment error: {e}")
        raise HTTPException(status_code=500, detail=f"Enrollment failed: {str(e)}")

@app.post("/api/attendance/periodic")
async def process_periodic_attendance(
    background_tasks: BackgroundTasks,
    image: UploadFile = File(...),
    session_id: str = Form(...),
    capture_time: str = Form(...)
):
    """Process periodic attendance capture"""
    try:
        # Validate session
        session_result = supabase.table('attendance_sessions').select('*').eq('id', session_id).eq('status', 'active').single().execute()
        
        if not session_result.data:
            raise HTTPException(status_code=404, detail="Active session not found")
        
        session_data = session_result.data
        class_id = session_data['class_id']
        
        # Get enrolled students for this class
        enrolled_students = await get_enrolled_students_for_class(class_id)
        
        if not enrolled_students:
            return {
                "success": True,
                "faces_detected": 0,
                "new_attendance_records": 0,
                "message": "No enrolled students found for this class"
            }
        
        # Process image
        image_data = await image.read()
        image_pil = Image.open(io.BytesIO(image_data))
        
        if image_pil.mode != 'RGB':
            image_pil = image_pil.convert('RGB')
        
        image_array = np.array(image_pil)
        
        # Process faces in background
        background_tasks.add_task(
            process_periodic_attendance_background,
            image_array,
            enrolled_students,
            session_id,
            session_data,
            capture_time
        )
        
        # Quick face detection for immediate response
        face_locations = face_recognition.face_locations(image_array, model="hog")
        
        return {
            "success": True,
            "faces_detected": len(face_locations),
            "message": f"Processing {len(face_locations)} faces in background",
            "session_id": session_id,
            "capture_time": capture_time,
            "enrolled_students": len(enrolled_students)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Periodic attendance error: {e}")
        raise HTTPException(status_code=500, detail=f"Processing failed: {str(e)}")

async def process_periodic_attendance_background(
    image_array: np.ndarray,
    enrolled_students: List[str],
    session_id: str,
    session_data: Dict,
    capture_time: str
):
    """Background task for processing periodic attendance"""
    try:
        logger.info(f"Processing periodic attendance for session {session_id}")
        
        # Process all faces
        detected_faces = process_multiple_faces(image_array, enrolled_students)
        
        new_records = 0
        
        for face_info in detected_faces:
            if not face_info['verified']:
                continue
            
            student_id = face_info['student_id']
            confidence = face_info['confidence']
            
            # Get student email
            student_result = supabase.table('users').select('email').eq('school_id', student_id).single().execute()
            
            if not student_result.data:
                continue
            
            student_email = student_result.data['email']
            
            # Check if already recorded
            existing_record = supabase.table('attendance_records').select('id').eq('session_id', session_id).eq('student_email', student_email).execute()
            
            if existing_record.data:
                continue  # Already recorded
            
            # Determine status based on timing
            capture_dt = datetime.fromisoformat(capture_time.replace('Z', '+00:00'))
            session_start = datetime.fromisoformat(session_data['start_time'].replace('Z', '+00:00'))
            on_time_limit = session_start + timedelta(minutes=session_data['on_time_limit_minutes'])
            
            status = 'present' if capture_dt <= on_time_limit else 'late'
            
            # Save attendance record
            record_data = {
                'session_id': session_id,
                'student_email': student_email,
                'student_id': student_id,
                'check_in_time': capture_dt.isoformat(),
                'status': status,
                'face_match_score': confidence,
                'created_at': datetime.now().isoformat()
            }
            
            try:
                supabase.table('attendance_records').insert(record_data).execute()
                new_records += 1
                logger.info(f"Recorded attendance for {student_id}: {status}")
            except Exception as e:
                logger.error(f"Error saving attendance record for {student_id}: {e}")
        
        logger.info(f"Processed {len(detected_faces)} faces, created {new_records} new records")
        
    except Exception as e:
        logger.error(f"Background processing error: {e}")

@app.post("/api/session/create")
async def create_enhanced_session(request: AttendanceSessionRequest):
    """Create enhanced attendance session with periodic capture support"""
    try:
        start_time = datetime.now()
        end_time = start_time + timedelta(hours=request.duration_hours)
        
        session_data = {
            'class_id': request.class_id,
            'teacher_email': request.teacher_email,
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'on_time_limit_minutes': request.on_time_limit_minutes,
            'capture_interval_minutes': request.capture_interval_minutes,
            'status': 'active',
            'created_at': start_time.isoformat()
        }
        
        result = supabase.table('attendance_sessions').insert(session_data).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to create session")
        
        session_id = result.data[0]['id']
        logger.info(f"Created enhanced session: {session_id}")
        
        return {
            "success": True,
            "session_id": session_id,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "capture_interval_minutes": request.capture_interval_minutes,
            "on_time_limit_minutes": request.on_time_limit_minutes
        }
        
    except Exception as e:
        logger.error(f"Enhanced session creation error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create session: {str(e)}")

@app.put("/api/session/{session_id}/end")
async def end_session(session_id: str):
    """End attendance session"""
    try:
        result = supabase.table('attendance_sessions').update({
            'status': 'ended',
            'updated_at': datetime.now().isoformat()
        }).eq('id', session_id).execute()
        
        if not result.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        logger.info(f"Session ended: {session_id}")
        
        return {
            "success": True,
            "message": "Session ended successfully",
            "session_id": session_id
        }
        
    except Exception as e:
        logger.error(f"Error ending session: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to end session: {str(e)}")

async def save_face_embedding_to_db(student_id: str, student_email: str, encoding: np.ndarray, quality: float) -> bool:
    """Save face embedding to database"""
    try:
        if encoding is None or encoding.size == 0:
            logger.error("Empty encoding provided")
            return False
        
        if not student_id or not student_email:
            logger.error("Missing student_id or student_email")
            return False
        
        # Validate encoding
        if not isinstance(encoding, np.ndarray):
            logger.error("Encoding must be numpy array")
            return False
        
        if encoding.ndim != 1:
            logger.error(f"Encoding must be 1D array, got {encoding.ndim}D")
            return False
        
        embedding_json = encoding.tolist()
        
        # Validate quality
        quality = max(0.0, min(1.0, float(quality)))
        
        face_data = {
            'student_id': student_id,
            'face_embedding_json': json.dumps(embedding_json),
            'face_quality': quality,
            'is_active': True,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat()
        }
        
        # Check if student exists
        student_check = supabase.table('users').select('school_id').eq('school_id', student_id).execute()
        
        if not student_check.data:
            logger.error(f"Student {student_id} not found in users table")
            return False
        
        # Deactivate old embeddings
        supabase.table('student_face_embeddings').update({
            'is_active': False,
            'updated_at': datetime.now().isoformat()
        }).eq('student_id', student_id).execute()
        
        # Insert new embedding
        result = supabase.table('student_face_embeddings').insert(face_data).execute()
        
        if result.data:
            logger.info(f"Face data saved for student: {student_id} (quality: {quality:.2f})")
            return True
        else:
            logger.error(f"Failed to save face data for student: {student_id}")
            return False
        
    except Exception as e:
        logger.error(f"Error saving to database: {e}")
        return Fals

# Health and management endpoints
@app.get("/health")
async def enhanced_health_check():
    """Enhanced health check with database table validation"""
    try:
        # Test face_recognition
        test_array = np.zeros((100, 100, 3), dtype=np.uint8)
        face_recognition.face_locations(test_array)
        
        # Test required database tables
        required_tables = [
            'users',
            'classes',
            'class_students', 
            'attendance_sessions',
            'attendance_records',
            'student_face_embeddings'
        ]
        
        table_status = {}
        for table in required_tables:
            try:
                result = supabase.table(table).select("count", count='exact').limit(1).execute()
                table_status[table] = "ok"
            except Exception as e:
                logger.error(f"Table {table} check failed: {e}")
                table_status[table] = f"error: {str(e)}"
        
        # Test periodic_captures table (optional)
        try:
            supabase.table('periodic_captures').select("count", count='exact').limit(1).execute()
            table_status['periodic_captures'] = "ok"
        except Exception:
            table_status['periodic_captures'] = "missing (will create automatically)"
        
        # Cache statistics
        with cache_lock:
            cache_size = len(face_cache)
        
        # Overall health status
        all_tables_ok = all(status == "ok" for table, status in table_status.items() 
                           if table != 'periodic_captures')
        
        overall_status = "healthy" if all_tables_ok else "degraded"
        
        return {
            "status": overall_status,
            "timestamp": datetime.now().isoformat(),
            "services": {
                "face_recognition": "ok",
                "supabase": "ok",
                "thread_pool": "ok"
            },
            "database_tables": table_status,
            "cache": {
                "size": cache_size,
                "max_workers": executor._max_workers
            },
            "configuration": {
                "face_threshold": FACE_THRESHOLD,
                "debug": DEBUG,
                "version": "3.0.1"
            }
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            "status": "unhealthy",
            "timestamp": datetime.now().isoformat(),
            "error": str(e)
        }

@app.post("/api/admin/create-tables")
async def create_missing_tables():
    """Create missing database tables (admin only)"""
    try:
        # SQL สำหรับสร้าง periodic_captures table
        create_periodic_captures_sql = """
        CREATE TABLE IF NOT EXISTS periodic_captures (
            id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
            session_id uuid REFERENCES attendance_sessions(id) ON DELETE CASCADE,
            capture_time timestamptz NOT NULL,
            faces_detected integer DEFAULT 0,
            faces_recognized integer DEFAULT 0,
            processing_time_ms integer DEFAULT 0,
            created_at timestamptz DEFAULT now(),
            updated_at timestamptz DEFAULT now()
        );
        
        CREATE INDEX IF NOT EXISTS idx_periodic_captures_session_id ON periodic_captures(session_id);
        CREATE INDEX IF NOT EXISTS idx_periodic_captures_capture_time ON periodic_captures(capture_time);
        """
        
        # Execute SQL (requires database admin access)
        # supabase.rpc('execute_sql', {'sql': create_periodic_captures_sql}).execute()
        
        return {
            "success": True,
            "message": "Database tables creation initiated",
            "sql": create_periodic_captures_sql,
            "note": "Please execute this SQL manually in your Supabase dashboard"
        }
        
    except Exception as e:
        logger.error(f"Error creating tables: {e}")
        raise HTTPException(status_code=500, detail=f"Table creation failed: {str(e)}")
    from fastapi import Request

@app.middleware("http")
async def validation_middleware(request: Request, call_next):
    """Add request validation middleware"""
    try:
        # Log request
        if DEBUG:
            logger.info(f"Request: {request.method} {request.url}")
        
        response = await call_next(request)
        
        # Log response status
        if DEBUG:
            logger.info(f"Response: {response.status_code}")
        
        return response
        
    except Exception as e:
        logger.error(f"Request processing error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": "Internal server error", "detail": str(e)}
        )
    

@app.delete("/api/cache/clear")
async def clear_face_cache():
    """Clear face embedding cache"""
    with cache_lock:
        cache_size = len(face_cache)
        face_cache.clear()
    
    return {
        "success": True,
        "message": f"Cleared {cache_size} cached embeddings",
        "timestamp": datetime.now().isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    print(f"🚀 Starting Enhanced Face Recognition Server on {HOST}:{PORT}")
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
# เพิ่มใน main.py

@app.post("/api/class/start-session")
async def start_class_session(
    background_tasks: BackgroundTasks,
    class_id: str = Form(...),
    teacher_email: str = Form(...),
    duration_hours: int = Form(2),
    capture_interval_minutes: int = Form(5),
    on_time_limit_minutes: int = Form(30),
    initial_image: UploadFile = File(...)
):
    """Start class session with initial attendance snapshot"""
    try:
        logger.info(f"Starting class session for {class_id} by {teacher_email}")
        
        # 1. Validate class and teacher
        class_result = supabase.table('classes').select('*').eq('class_id', class_id).eq('teacher_email', teacher_email).single().execute()
        
        if not class_result.data:
            raise HTTPException(status_code=404, detail="Class not found or you are not the teacher")
        
        # 2. Check if there's already an active session
        existing_session = supabase.table('attendance_sessions').select('id').eq('class_id', class_id).eq('status', 'active').execute()
        
        if existing_session.data:
            raise HTTPException(status_code=400, detail="There is already an active session for this class")
        
        # 3. Create new session
        start_time = datetime.now()
        end_time = start_time + timedelta(hours=duration_hours)
        on_time_deadline = start_time + timedelta(minutes=on_time_limit_minutes)
        
        session_data = {
            'class_id': class_id,
            'teacher_email': teacher_email,
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'on_time_limit_minutes': on_time_limit_minutes,
            'capture_interval_minutes': capture_interval_minutes,
            'status': 'active',
            'created_at': start_time.isoformat()
        }
        
        session_result = supabase.table('attendance_sessions').insert(session_data).execute()
        
        if not session_result.data:
            raise HTTPException(status_code=500, detail="Failed to create session")
        
        session_id = session_result.data[0]['id']
        
        # 4. Process initial image in background
        if initial_image:
            image_data = await initial_image.read()
            image_pil = Image.open(io.BytesIO(image_data))
            
            if image_pil.mode != 'RGB':
                image_pil = image_pil.convert('RGB')
            
            image_array = np.array(image_pil)
            
            # Get enrolled students
            enrolled_students = await get_enrolled_students_for_class(class_id)
            
            # Process initial attendance in background
            background_tasks.add_task(
                process_start_class_attendance,
                image_array,
                enrolled_students,
                session_id,
                session_data,
                start_time.isoformat()
            )
        
        # 5. Log capture event
        capture_log = {
            'session_id': session_id,
            'capture_time': start_time.isoformat(),
            'faces_detected': 0,  # Will be updated by background task
            'faces_recognized': 0,
            'created_at': start_time.isoformat()
        }
        
        supabase.table('periodic_captures').insert(capture_log).execute()
        
        logger.info(f"✅ Class session started: {session_id}")
        
        return {
            "success": True,
            "message": "Class session started successfully",
            "session_id": session_id,
            "class_id": class_id,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "on_time_deadline": on_time_deadline.isoformat(),
            "capture_interval_minutes": capture_interval_minutes,
            "enrolled_students_count": len(enrolled_students) if 'enrolled_students' in locals() else 0
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error starting class session: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to start class session: {str(e)}")

async def process_start_class_attendance(
    image_array: np.ndarray,
    enrolled_students: List[str], 
    session_id: str,
    session_data: Dict,
    capture_time: str
):
    """Background processing for start-of-class attendance"""
    try:
        logger.info(f"📸 Processing start-of-class image for session {session_id}")
        
        # Detect faces
        face_locations = face_recognition.face_locations(image_array, model="hog")
        faces_detected = len(face_locations)
        
        # Process faces for recognition
        detected_faces = process_multiple_faces(image_array, enrolled_students)
        faces_recognized = len([f for f in detected_faces if f['verified']])
        
        # Record attendance for recognized students
        new_records = 0
        for face_info in detected_faces:
            if not face_info['verified']:
                continue
            
            student_id = face_info['student_id']
            confidence = face_info['confidence']
            
            # Get student email
            student_result = supabase.table('users').select('email').eq('school_id', student_id).single().execute()
            
            if not student_result.data:
                continue
            
            student_email = student_result.data['email']
            
            # Since this is start of class, everyone should be "present"
            record_data = {
                'session_id': session_id,
                'student_email': student_email,
                'student_id': student_id,
                'check_in_time': capture_time,
                'status': 'present',  # Start of class = present
                'face_match_score': confidence,
                'detection_method': 'start_class',
                'face_quality': face_info.get('quality', {}),
                'created_at': datetime.now().isoformat()
            }
            
            try:
                supabase.table('attendance_records').insert(record_data).execute()
                new_records += 1
                logger.info(f"✅ Recorded start-class attendance for {student_id}")
            except Exception as e:
                logger.error(f"❌ Error saving start-class record for {student_id}: {e}")
        
        # Update capture log
        supabase.table('periodic_captures').update({
            'faces_detected': faces_detected,
            'faces_recognized': faces_recognized,
            'processing_time_ms': int(time.time() * 1000) % 1000000
        }).eq('session_id', session_id).eq('capture_time', capture_time).execute()
        
        logger.info(f"📊 Start-class processing complete: {faces_detected} faces detected, {new_records} students recorded")
        
    except Exception as e:
        logger.error(f"❌ Error processing start-class attendance: {e}")

@app.post("/api/class/manual-capture")
async def manual_attendance_capture(
    background_tasks: BackgroundTasks,
    session_id: str = Form(...),
    image: UploadFile = File(...)
):
    """Manual attendance capture during class"""
    try:
        # Validate session
        session_result = supabase.table('attendance_sessions').select('*').eq('id', session_id).eq('status', 'active').single().execute()
        
        if not session_result.data:
            raise HTTPException(status_code=404, detail="Active session not found")
        
        session_data = session_result.data
        class_id = session_data['class_id']
        
        # Process image
        image_data = await image.read()
        image_pil = Image.open(io.BytesIO(image_data))
        
        if image_pil.mode != 'RGB':
            image_pil = image_pil.convert('RGB')
        
        image_array = np.array(image_pil)
        
        # Quick face count
        face_locations = face_recognition.face_locations(image_array, model="hog")
        faces_detected = len(face_locations)
        
        # Get enrolled students
        enrolled_students = await get_enrolled_students_for_class(class_id)
        
        # Process in background
        capture_time = datetime.now().isoformat()
        background_tasks.add_task(
            process_manual_attendance_background,
            image_array,
            enrolled_students,
            session_id,
            session_data,
            capture_time
        )
        
        # Log capture
        capture_log = {
            'session_id': session_id,
            'capture_time': capture_time,
            'faces_detected': faces_detected,
            'faces_recognized': 0,  # Will be updated by background task
            'created_at': capture_time
        }
        
        supabase.table('periodic_captures').insert(capture_log).execute()
        
        return {
            "success": True,
            "message": f"Manual capture processed - {faces_detected} faces detected",
            "session_id": session_id,
            "faces_detected": faces_detected,
            "capture_time": capture_time
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Manual capture error: {e}")
        raise HTTPException(status_code=500, detail=f"Manual capture failed: {str(e)}")

async def process_manual_attendance_background(
    image_array: np.ndarray,
    enrolled_students: List[str],
    session_id: str,
    session_data: Dict,
    capture_time: str
):
    """Background processing for manual attendance capture"""
    try:
        # Process faces similar to periodic attendance
        detected_faces = process_multiple_faces(image_array, enrolled_students)
        faces_recognized = len([f for f in detected_faces if f['verified']])
        
        new_records = 0
        
        for face_info in detected_faces:
            if not face_info['verified']:
                continue
            
            student_id = face_info['student_id']
            confidence = face_info['confidence']
            
            # Get student email
            student_result = supabase.table('users').select('email').eq('school_id', student_id).single().execute()
            
            if not student_result.data:
                continue
            
            student_email = student_result.data['email']
            
            # Check if already recorded
            existing_record = supabase.table('attendance_records').select('id').eq('session_id', session_id).eq('student_email', student_email).execute()
            
            if existing_record.data:
                continue  # Skip if already recorded
            
            # Determine status based on timing
            capture_dt = datetime.fromisoformat(capture_time.replace('Z', '+00:00'))
            session_start = datetime.fromisoformat(session_data['start_time'].replace('Z', '+00:00'))
            on_time_limit = session_start + timedelta(minutes=session_data['on_time_limit_minutes'])
            
            status = 'present' if capture_dt <= on_time_limit else 'late'
            
            # Save record
            record_data = {
                'session_id': session_id,
                'student_email': student_email,
                'student_id': student_id,
                'check_in_time': capture_time,
                'status': status,
                'face_match_score': confidence,
                'detection_method': 'manual',
                'face_quality': face_info.get('quality', {}),
                'created_at': datetime.now().isoformat()
            }
            
            try:
                supabase.table('attendance_records').insert(record_data).execute()
                new_records += 1
                logger.info(f"✅ Manual attendance recorded for {student_id}: {status}")
            except Exception as e:
                logger.error(f"❌ Error saving manual record for {student_id}: {e}")
        
        # Update capture log
        supabase.table('periodic_captures').update({
            'faces_recognized': faces_recognized
        }).eq('session_id', session_id).eq('capture_time', capture_time).execute()
        
        logger.info(f"📊 Manual capture complete: {faces_recognized} faces recognized, {new_records} new records")
        
    except Exception as e:
        logger.error(f"❌ Error processing manual capture: {e}")

@app.get("/api/session/{session_id}/statistics")
async def get_session_statistics(session_id: str):
    """Get detailed session statistics"""
    try:
        # Get session info
        session_result = supabase.table('attendance_sessions').select('*').eq('id', session_id).single().execute()
        
        if not session_result.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        session_data = session_result.data
        
        # Get attendance records
        records_result = supabase.table('attendance_records').select('*').eq('session_id', session_id).execute()
        records = records_result.data or []
        
        # Get capture logs
        captures_result = supabase.table('periodic_captures').select('*').eq('session_id', session_id).order('capture_time').execute()
        captures = captures_result.data or []
        
        # Get total enrolled students
        enrolled_students = await get_enrolled_students_for_class(session_data['class_id'])
        total_students = len(enrolled_students)
        
        # Calculate statistics
        present_count = len([r for r in records if r['status'] == 'present'])
        late_count = len([r for r in records if r['status'] == 'late'])
        absent_count = total_students - len(records)
        attendance_rate = len(records) / total_students if total_students > 0 else 0
        
        # Face recognition stats
        face_verified_count = len([r for r in records if r['face_match_score'] and r['face_match_score'] > FACE_THRESHOLD])
        avg_confidence = np.mean([r['face_match_score'] for r in records if r['face_match_score']]) if records else 0
        
        # Capture statistics
        total_captures = len(captures)
        total_faces_detected = sum([c['faces_detected'] or 0 for c in captures])
        total_faces_recognized = sum([c['faces_recognized'] or 0 for c in captures])
        
        return {
            "success": True,
            "session_id": session_id,
            "session_info": session_data,
            "statistics": {
                "total_students": total_students,
                "present_count": present_count,
                "late_count": late_count,
                "absent_count": absent_count,
                "attendance_rate": round(attendance_rate, 3),
                "face_verification_rate": round(face_verified_count / len(records), 3) if records else 0,
                "average_confidence": round(float(avg_confidence), 3)
            },
            "capture_statistics": {
                "total_captures": total_captures,
                "total_faces_detected": total_faces_detected,
                "total_faces_recognized": total_faces_recognized,
                "detection_rate": round(total_faces_recognized / total_faces_detected, 3) if total_faces_detected > 0 else 0
            },
            "attendance_records": records,
            "capture_logs": captures
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting session statistics: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get statistics: {str(e)}")

@app.get("/api/session/{session_id}/verify-enrollment/{student_id}")
async def verify_student_enrollment(session_id: str, student_id: str):
    """Verify if student has face enrollment for attendance"""
    try:
        # Check if student has active face embedding
        embedding_result = supabase.table('student_face_embeddings').select('face_quality, created_at').eq('student_id', student_id).eq('is_active', True).single().execute()
        
        has_face_data = bool(embedding_result.data)
        
        return {
            "success": True,
            "student_id": student_id,
            "has_face_data": has_face_data,
            "face_quality": embedding_result.data.get('face_quality', 0) if has_face_data else 0,
            "enrolled_date": embedding_result.data.get('created_at') if has_face_data else None
        }
        
    except Exception as e:
        logger.error(f"❌ Error verifying enrollment for {student_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to verify enrollment: {str(e)}")
    
# main.py - Enhanced with phase-aware processing
class AdaptiveProcessor:
    def __init__(self):
        self.phase_stats = {}
        self.processing_priority = {
            '0-10': 1,    # Highest priority
            '10-20': 2,   # High priority  
            '20-30': 3,   # Medium priority
            '30-60': 4,   # Normal priority
            '60-90': 5,   # Low priority
            '90+': 6      # Lowest priority
        }
    
    def get_processing_config(self, phase: str) -> Dict:
        """Get processing configuration based on phase"""
        configs = {
            '0-10': {
                'model_accuracy': 'high',      # ใช้ model ที่แม่นยำ
                'face_threshold': 0.75,        # Threshold สูง
                'max_processing_time': 3,      # 3 วินาที
                'parallel_workers': 4,         # Worker เยอะ
                'cache_results': True,         # Cache ผลลัพธ์
                'priority': 1
            },
            '10-20': {
                'model_accuracy': 'high',
                'face_threshold': 0.7,
                'max_processing_time': 4,
                'parallel_workers': 3,
                'cache_results': True,
                'priority': 2
            },
            '20-30': {
                'model_accuracy': 'medium',
                'face_threshold': 0.7,
                'max_processing_time': 5,
                'parallel_workers': 2,
                'cache_results': True,
                'priority': 3
            },
            '30-60': {
                'model_accuracy': 'medium',
                'face_threshold': 0.65,
                'max_processing_time': 6,
                'parallel_workers': 2,
                'cache_results': False,
                'priority': 4
            },
            '60-90': {
                'model_accuracy': 'standard',
                'face_threshold': 0.65,
                'max_processing_time': 8,
                'parallel_workers': 1,
                'cache_results': False,
                'priority': 5
            },
            '90+': {
                'model_accuracy': 'standard',
                'face_threshold': 0.6,
                'max_processing_time': 10,
                'parallel_workers': 1,
                'cache_results': False,
                'priority': 6
            }
        }
        return configs.get(phase, configs['30-60'])

# Enhanced periodic attendance with phase awareness
@app.post("/api/attendance/adaptive")
async def process_adaptive_attendance(
    background_tasks: BackgroundTasks,
    image: UploadFile = File(...),
    session_id: str = Form(...),
    capture_time: str = Form(...),
    phase: str = Form(...),  # Phase information from client
    elapsed_minutes: int = Form(...)
):
    try:
        # Validate session
        session_result = supabase.table('attendance_sessions').select('*').eq('id', session_id).eq('status', 'active').single().execute()
        if not session_result.data:
            raise HTTPException(status_code=404, detail="Active session not found")
        
        session_data = session_result.data
        processor = AdaptiveProcessor()
        config = processor.get_processing_config(phase)
        
        # Priority queue based on phase
        priority = config['priority']
        
        # Add to appropriate processing queue
        await adaptive_queue.put({
            "priority": priority,
            "image_data": await image.read(),
            "session_id": session_id,
            "capture_time": capture_time,
            "phase": phase,
            "config": config,
            "session_data": session_data
        })
        
        # Start background processing
        background_tasks.add_task(process_adaptive_queue)
        
        # Quick response
        face_locations = face_recognition.face_locations(np.array(Image.open(io.BytesIO(await image.read()))), model="hog")
        
        return {
            "success": True,
            "phase": phase,
            "elapsed_minutes": elapsed_minutes,
            "faces_detected": len(face_locations),
            "processing_priority": priority,
            "queue_size": adaptive_queue.qsize(),
            "config": config
        }
        
    except Exception as e:
        logger.error(f"Adaptive processing error: {e}")
        raise HTTPException(status_code=500, detail=f"Processing failed: {str(e)}")

# Priority queue for adaptive processing
import heapq
import asyncio

class AdaptivePriorityQueue:
    def __init__(self):
        self.queue = []
        self.index = 0
        self.lock = asyncio.Lock()
    
    async def put(self, item):
        async with self.lock:
            priority = item['priority']
            heapq.heappush(self.queue, (priority, self.index, item))
            self.index += 1
    
    async def get(self):
        async with self.lock:
            if self.queue:
                priority, index, item = heapq.heappop(self.queue)
                return item
            return None
    
    def qsize(self):
        return len(self.queue)

adaptive_queue = AdaptivePriorityQueue()

async def process_adaptive_queue():
    """Process adaptive queue with priority"""
    while True:
        item = await adaptive_queue.get()
        if not item:
            break
            
        try:
            await process_adaptive_item(item)
        except Exception as e:
            logger.error(f"Adaptive queue processing error: {e}")

async def process_adaptive_item(item: Dict):
    """Process single adaptive item"""
    config = item['config']
    phase = item['phase']
    
    start_time = time.time()
    
    # Process with phase-specific configuration
    image_pil = Image.open(io.BytesIO(item['image_data']))
    if image_pil.mode != 'RGB':
        image_pil = image_pil.convert('RGB')
    
    image_array = np.array(image_pil)
    
    # Get enrolled students (cached for efficiency)
    class_id = item['session_data']['class_id']
    enrolled_students = enhanced_cache.get_enrolled_students_cached(class_id)
    
    # Process faces with adaptive threshold
    detected_faces = process_multiple_faces_adaptive(
        image_array, 
        enrolled_students,
        threshold=config['face_threshold']
    )
    
    processing_time = time.time() - start_time
    
    # Save results based on phase importance
    if phase in ['0-10', '10-20'] or len(detected_faces) > 0:
        # Always save for critical phases or when faces detected
        await save_adaptive_results(item, detected_faces, processing_time)
    elif phase in ['20-30', '30-60'] and processing_time < config['max_processing_time']:
        # Save for medium phases if processed quickly
        await save_adaptive_results(item, detected_faces, processing_time)
    # For low-priority phases, only save if significant results
    
    logger.info(f"Adaptive processing [{phase}]: {processing_time:.2f}s, {len(detected_faces)} faces")