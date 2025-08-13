# Face Recognition Server with FastAPI
# Requirements: fastapi, uvicorn, opencv-python, face-recognition, pillow, python-multipart

from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
import cv2
import face_recognition
import numpy as np
import io
import base64
from PIL import Image
import sqlite3
import json
from typing import Optional, Dict, Any
import requests
from datetime import datetime
import logging
from dotenv import load_dotenv
import os

# Load environment variables
load_dotenv()

# Get configuration
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", 8000))
DEBUG = os.getenv("DEBUG", "false").lower() == "true"
FACE_THRESHOLD = float(os.getenv("FACE_VERIFICATION_THRESHOLD", 0.6))

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Face Recognition API", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database setup
def init_database():
    conn = sqlite3.connect('face_recognition.db')
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS face_embeddings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT UNIQUE NOT NULL,
            student_email TEXT NOT NULL,
            embedding BLOB NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()

# Initialize database on startup
@app.on_event("startup")
async def startup_event():
    init_database()
    logger.info("Face Recognition Server started successfully")

# Health check endpoint
@app.get("/")
async def root():
    return {
        "message": "Face Recognition Server",
        "version": "1.0.0",
        "status": "running",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

# Helper functions
def process_image(image_file: UploadFile) -> tuple:
    """Process uploaded image and extract face encoding"""
    try:
        # Read image
        image_data = image_file.file.read()
        image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB if needed
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # Convert to numpy array
        image_array = np.array(image)
        
        # Find face locations
        face_locations = face_recognition.face_locations(image_array)
        
        if len(face_locations) == 0:
            raise HTTPException(status_code=400, detail="No face detected in the image")
        
        if len(face_locations) > 1:
            raise HTTPException(status_code=400, detail="Multiple faces detected. Please ensure only one face is visible")
        
        # Get face encoding
        face_encodings = face_recognition.face_encodings(image_array, face_locations)
        
        if len(face_encodings) == 0:
            raise HTTPException(status_code=400, detail="Could not encode face from the image")
        
        return face_encodings[0], face_locations[0]
        
    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")

def save_face_embedding(student_id: str, student_email: str, encoding: np.ndarray) -> bool:
    """Save face embedding to database"""
    try:
        conn = sqlite3.connect('face_recognition.db')
        cursor = conn.cursor()
        
        # Convert encoding to bytes
        encoding_bytes = encoding.tobytes()
        
        # Insert or update face embedding
        cursor.execute('''
            INSERT OR REPLACE INTO face_embeddings 
            (student_id, student_email, embedding, updated_at)
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''', (student_id, student_email, encoding_bytes))
        
        conn.commit()
        conn.close()
        
        return True
        
    except Exception as e:
        logger.error(f"Error saving face embedding: {str(e)}")
        return False

def get_face_embedding(student_id: str) -> Optional[np.ndarray]:
    """Retrieve face embedding from database"""
    try:
        conn = sqlite3.connect('face_recognition.db')
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT embedding FROM face_embeddings WHERE student_id = ?',
            (student_id,)
        )
        
        result = cursor.fetchone()
        conn.close()
        
        if result:
            # Convert bytes back to numpy array
            encoding = np.frombuffer(result[0], dtype=np.float64)
            return encoding
        
        return None
        
    except Exception as e:
        logger.error(f"Error retrieving face embedding: {str(e)}")
        return None

def calculate_face_similarity(encoding1: np.ndarray, encoding2: np.ndarray) -> float:
    """Calculate similarity between two face encodings"""
    try:
        # Calculate Euclidean distance
        distance = np.linalg.norm(encoding1 - encoding2)
        
        # Convert distance to similarity (lower distance = higher similarity)
        similarity = max(0, 1 - distance)
        
        return similarity
        
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
    """Register a new face for a student"""
    try:
        logger.info(f"Registering face for student: {student_id}")
        
        # Validate file type
        if not file.content_type.startswith('image/'):
            raise HTTPException(status_code=400, detail="File must be an image")
        
        # Process image and extract face encoding
        face_encoding, face_location = process_image(file)
        
        # Save to database
        success = save_face_embedding(student_id, student_email, face_encoding)
        
        if not success:
            raise HTTPException(status_code=500, detail="Failed to save face data")
        
        logger.info(f"Face registered successfully for student: {student_id}")
        
        return {
            "success": True,
            "message": "Face registered successfully",
            "student_id": student_id,
            "face_location": {
                "top": int(face_location[0]),
                "right": int(face_location[1]),
                "bottom": int(face_location[2]),
                "left": int(face_location[3])
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in register_face: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")

@app.post("/api/face/verify")
async def verify_face(
    file: UploadFile = File(...),
    student_id: str = Form(...)
):
    """Verify a face against registered data"""
    try:
        logger.info(f"Verifying face for student: {student_id}")
        
        # Validate file type
        if not file.content_type.startswith('image/'):
            raise HTTPException(status_code=400, detail="File must be an image")
        
        # Get stored face encoding
        stored_encoding = get_face_embedding(student_id)
        
        if stored_encoding is None:
            raise HTTPException(status_code=404, detail="No face data found for this student")
        
        # Process uploaded image
        current_encoding, face_location = process_image(file)
        
        # Calculate similarity
        similarity = calculate_face_similarity(stored_encoding, current_encoding)
        
        # Determine if verification passed (threshold: 0.6)
        threshold = 0.6
        verified = similarity >= threshold
        
        logger.info(f"Face verification for {student_id}: similarity={similarity:.3f}, verified={verified}")
        
        return {
            "success": True,
            "verified": verified,
            "similarity": float(similarity),
            "threshold": threshold,
            "student_id": student_id,
            "message": "Face verified successfully" if verified else "Face verification failed"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in verify_face: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Verification failed: {str(e)}")

@app.post("/api/webcam/capture")
async def capture_from_webcam(request: Dict[str, Any]):
    """Capture image from IP webcam"""
    try:
        ip_address = request.get('ip_address')
        port = request.get('port', 8080)
        username = request.get('username', '')
        password = request.get('password', '')
        
        if not ip_address:
            raise HTTPException(status_code=400, detail="IP address is required")
        
        # Construct webcam URL
        webcam_url = f"http://{ip_address}:{port}/photo.jpg"
        
        # Add authentication if provided
        auth = None
        if username and password:
            auth = (username, password)
        
        # Capture image from webcam
        response = requests.get(webcam_url, auth=auth, timeout=10)
        
        if response.status_code != 200:
            raise HTTPException(status_code=400, detail="Failed to capture image from webcam")
        
        return StreamingResponse(
            io.BytesIO(response.content),
            media_type="image/jpeg"
        )
        
    except requests.RequestException as e:
        logger.error(f"Webcam capture error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Webcam connection failed: {str(e)}")
    except Exception as e:
        logger.error(f"Error in capture_from_webcam: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Capture failed: {str(e)}")

@app.post("/api/attendance/checkin")
async def checkin_with_face_recognition(request: Dict[str, Any]):
    """Check in attendance using face recognition"""
    try:
        session_id = request.get('session_id')
        student_email = request.get('student_email')
        webcam_config = request.get('webcam_config', {})
        
        if not session_id or not student_email:
            raise HTTPException(status_code=400, detail="Session ID and student email are required")
        
        # Extract student ID from email (you might want to modify this logic)
        student_id = student_email.split('@')[0]
        
        # Capture image from webcam
        ip_address = webcam_config.get('ip_address')
        port = webcam_config.get('port', 8080)
        
        if not ip_address:
            raise HTTPException(status_code=400, detail="Webcam IP address is required")
        
        webcam_url = f"http://{ip_address}:{port}/photo.jpg"
        
        # Capture image
        response = requests.get(webcam_url, timeout=10)
        if response.status_code != 200:
            raise HTTPException(status_code=400, detail="Failed to capture image from webcam")
        
        # Process captured image
        image = Image.open(io.BytesIO(response.content))
        image_array = np.array(image)
        
        # Find face in captured image
        face_locations = face_recognition.face_locations(image_array)
        if len(face_locations) == 0:
            raise HTTPException(status_code=400, detail="No face detected in captured image")
        
        face_encodings = face_recognition.face_encodings(image_array, face_locations)
        if len(face_encodings) == 0:
            raise HTTPException(status_code=400, detail="Could not encode face from captured image")
        
        # Get stored face encoding
        stored_encoding = get_face_embedding(student_id)
        if stored_encoding is None:
            raise HTTPException(status_code=404, detail="No face data found for this student")
        
        # Verify face
        similarity = calculate_face_similarity(stored_encoding, face_encodings[0])
        verified = similarity >= 0.6
        
        if not verified:
            raise HTTPException(status_code=400, detail="Face verification failed")
        
        # Here you would typically save the attendance record to your database
        # For now, we'll just return success
        
        logger.info(f"Attendance check-in successful for {student_email}, similarity: {similarity:.3f}")
        
        return {
            "success": True,
            "message": "Attendance recorded successfully",
            "student_email": student_email,
            "session_id": session_id,
            "face_match_score": float(similarity),
            "check_in_time": datetime.now().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in attendance check-in: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Check-in failed: {str(e)}")

# Additional utility endpoints

@app.get("/api/face/students")
async def list_registered_students():
    """List all students with registered faces"""
    try:
        conn = sqlite3.connect('face_recognition.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT student_id, student_email, created_at, updated_at 
            FROM face_embeddings 
            ORDER BY created_at DESC
        ''')
        
        results = cursor.fetchall()
        conn.close()
        
        students = []
        for row in results:
            students.append({
                "student_id": row[0],
                "student_email": row[1],
                "created_at": row[2],
                "updated_at": row[3]
            })
        
        return {
            "success": True,
            "count": len(students),
            "students": students
        }
        
    except Exception as e:
        logger.error(f"Error listing students: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to list students: {str(e)}")

@app.delete("/api/face/student/{student_id}")
async def delete_student_face(student_id: str):
    """Delete face data for a student"""
    try:
        conn = sqlite3.connect('face_recognition.db')
        cursor = conn.cursor()
        
        cursor.execute('DELETE FROM face_embeddings WHERE student_id = ?', (student_id,))
        
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Student face data not found")
        
        conn.commit()
        conn.close()
        
        logger.info(f"Face data deleted for student: {student_id}")
        
        return {
            "success": True,
            "message": f"Face data deleted for student {student_id}"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting student face: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to delete face data: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)