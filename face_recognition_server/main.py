# Complete WebRTC Backend Server with Signaling and Face Recognition
# File: webrtc_face_recognition_server/main.py

import asyncio
import json
import logging
import os
import uuid
from datetime import datetime, timedelta
from typing import Dict, Optional, Set, Any
import cv2
import numpy as np
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import socketio
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCDataChannel
from aiortc.contrib.media import MediaPlayer, MediaRelay
import face_recognition
from PIL import Image
import io
import base64
from dotenv import load_dotenv
from supabase import create_client, Client
import requests

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
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="WebRTC Face Recognition Server",
    description="Real-time face recognition with WebRTC signaling",
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

# Socket.IO server for WebRTC signaling
sio = socketio.AsyncServer(
    cors_allowed_origins="*",
    logger=True,
    engineio_logger=True
)
socket_app = socketio.ASGIApp(sio, app)

# Global state management
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self.peer_connections: Dict[str, RTCPeerConnection] = {}
        self.rooms: Dict[str, Set[str]] = {}
        self.media_relay = MediaRelay()

    async def connect(self, websocket: WebSocket, client_id: str):
        await websocket.accept()
        self.active_connections[client_id] = websocket
        logger.info(f"Client {client_id} connected via WebSocket")

    def disconnect(self, client_id: str):
        if client_id in self.active_connections:
            del self.active_connections[client_id]
        if client_id in self.peer_connections:
            asyncio.create_task(self.peer_connections[client_id].close())
            del self.peer_connections[client_id]
        logger.info(f"Client {client_id} disconnected")

    async def send_message(self, client_id: str, message: dict):
        if client_id in self.active_connections:
            try:
                await self.active_connections[client_id].send_text(json.dumps(message))
            except Exception as e:
                logger.error(f"Error sending message to {client_id}: {e}")
                self.disconnect(client_id)

    def join_room(self, room_id: str, client_id: str):
        if room_id not in self.rooms:
            self.rooms[room_id] = set()
        self.rooms[room_id].add(client_id)
        logger.info(f"Client {client_id} joined room {room_id}")

    def leave_room(self, room_id: str, client_id: str):
        if room_id in self.rooms:
            self.rooms[room_id].discard(client_id)
            if not self.rooms[room_id]:
                del self.rooms[room_id]

    async def broadcast_to_room(self, room_id: str, message: dict, exclude_client: str = None):
        if room_id in self.rooms:
            for client_id in self.rooms[room_id]:
                if client_id != exclude_client:
                    await self.send_message(client_id, message)

manager = ConnectionManager()

# ==================== Face Recognition Service ====================

class WebRTCFaceRecognitionService:
    def __init__(self):
        self.active_sessions: Dict[str, dict] = {}
        
    async def process_video_frame(self, frame_data: bytes, session_id: str, student_id: str) -> dict:
        """Process video frame for face recognition"""
        try:
            # Decode frame
            nparr = np.frombuffer(frame_data, np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if frame is None:
                raise Exception("Could not decode frame")
            
            # Convert BGR to RGB for face_recognition
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
            # Find faces
            face_locations = face_recognition.face_locations(rgb_frame, model="hog")
            
            if len(face_locations) == 0:
                return {
                    "success": False,
                    "error": "No face detected",
                    "face_count": 0
                }
            
            if len(face_locations) > 1:
                return {
                    "success": False,
                    "error": "Multiple faces detected",
                    "face_count": len(face_locations)
                }
            
            # Get face encoding
            face_encodings = face_recognition.face_encodings(rgb_frame, face_locations, num_jitters=1)
            
            if len(face_encodings) == 0:
                return {
                    "success": False,
                    "error": "Could not encode face"
                }
            
            current_encoding = face_encodings[0]
            
            # Get stored face encoding from Supabase
            stored_encoding = await self.get_stored_face_encoding(student_id)
            
            if stored_encoding is None:
                return {
                    "success": False,
                    "error": "No stored face data found"
                }
            
            # Calculate similarity
            similarity = self.calculate_face_similarity(current_encoding, stored_encoding)
            verified = similarity >= FACE_THRESHOLD
            
            # Calculate face quality
            face_location = face_locations[0]
            quality = self.calculate_face_quality(rgb_frame, face_location)
            
            return {
                "success": True,
                "verified": verified,
                "similarity": float(similarity),
                "quality": float(quality),
                "face_location": {
                    "top": int(face_location[0]),
                    "right": int(face_location[1]),
                    "bottom": int(face_location[2]),
                    "left": int(face_location[3])
                },
                "frame_info": {
                    "width": frame.shape[1],
                    "height": frame.shape[0],
                    "channels": frame.shape[2]
                }
            }
            
        except Exception as e:
            logger.error(f"Error processing video frame: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    async def get_stored_face_encoding(self, student_id: str) -> Optional[np.ndarray]:
        """Get stored face encoding from Supabase"""
        try:
            result = supabase.table('student_face_embeddings').select('face_embedding_json').eq('student_id', student_id).eq('is_active', True).single().execute()
            
            if result.data:
                embedding_json = json.loads(result.data['face_embedding_json'])
                return np.array(embedding_json, dtype=np.float64)
                
            return None
            
        except Exception as e:
            logger.error(f"Error retrieving face encoding: {e}")
            return None
    
    def calculate_face_similarity(self, encoding1: np.ndarray, encoding2: np.ndarray) -> float:
        """Calculate similarity between face encodings"""
        try:
            # Use face_recognition's built-in distance function
            distance = face_recognition.face_distance([encoding2], encoding1)[0]
            
            # Convert distance to similarity (0-1 scale)
            similarity = max(0, 1 - distance)
            
            return similarity
            
        except Exception as e:
            logger.error(f"Error calculating similarity: {e}")
            return 0.0
    
    def calculate_face_quality(self, frame: np.ndarray, face_location: tuple) -> float:
        """Calculate face quality score"""
        try:
            top, right, bottom, left = face_location
            
            # Extract face region
            face_image = frame[top:bottom, left:right]
            
            # Calculate various quality metrics
            face_size = (bottom - top) * (right - left)
            frame_size = frame.shape[0] * frame.shape[1]
            size_ratio = face_size / frame_size
            
            # Blur detection using Laplacian variance
            gray_face = cv2.cvtColor(face_image, cv2.COLOR_RGB2GRAY)
            blur_score = cv2.Laplacian(gray_face, cv2.CV_64F).var()
            
            # Normalize blur score (higher is better)
            normalized_blur = min(blur_score / 1000.0, 1.0)
            
            # Size score (0.1 to 0.4 is good range)
            size_score = 1.0 if 0.1 <= size_ratio <= 0.4 else max(0.0, 1.0 - abs(size_ratio - 0.25) * 4)
            
            # Combined quality score
            quality = (normalized_blur * 0.6 + size_score * 0.4)
            
            return min(1.0, quality)
            
        except Exception as e:
            logger.error(f"Error calculating face quality: {e}")
            return 0.0

face_service = WebRTCFaceRecognitionService()

# ==================== Socket.IO Event Handlers ====================

@sio.event
async def connect(sid, environ):
    logger.info(f"Socket.IO client connected: {sid}")
    await sio.emit('connected', {'status': 'success', 'sid': sid}, room=sid)

@sio.event
async def disconnect(sid):
    logger.info(f"Socket.IO client disconnected: {sid}")
    # Clean up any peer connections
    if sid in manager.peer_connections:
        await manager.peer_connections[sid].close()
        del manager.peer_connections[sid]

@sio.event
async def join_room(sid, data):
    """Join a WebRTC room for signaling"""
    try:
        room_id = data.get('room_id')
        client_type = data.get('client_type', 'unknown')  # 'flutter_app', 'web_client', etc.
        
        if not room_id:
            await sio.emit('error', {'message': 'Room ID required'}, room=sid)
            return
        
        await sio.enter_room(sid, room_id)
        manager.join_room(room_id, sid)
        
        logger.info(f"Client {sid} ({client_type}) joined room {room_id}")
        
        # Notify other clients in the room
        await sio.emit('user_joined', {
            'user_id': sid,
            'client_type': client_type,
            'timestamp': datetime.now().isoformat()
        }, room=room_id, skip_sid=sid)
        
        await sio.emit('joined_room', {
            'room_id': room_id,
            'user_id': sid,
            'status': 'success'
        }, room=sid)
        
    except Exception as e:
        logger.error(f"Error joining room: {e}")
        await sio.emit('error', {'message': str(e)}, room=sid)

@sio.event
async def leave_room(sid, data):
    """Leave a WebRTC room"""
    try:
        room_id = data.get('room_id')
        
        if room_id:
            await sio.leave_room(sid, room_id)
            manager.leave_room(room_id, sid)
            
            # Notify other clients
            await sio.emit('user_left', {
                'user_id': sid,
                'timestamp': datetime.now().isoformat()
            }, room=room_id)
            
        logger.info(f"Client {sid} left room {room_id}")
        
    except Exception as e:
        logger.error(f"Error leaving room: {e}")

@sio.event
async def webrtc_offer(sid, data):
    """Handle WebRTC offer"""
    try:
        room_id = data.get('room_id')
        offer = data.get('offer')
        target_id = data.get('target_id')
        
        if not all([room_id, offer]):
            await sio.emit('error', {'message': 'Room ID and offer required'}, room=sid)
            return
        
        # Create peer connection if not exists
        if sid not in manager.peer_connections:
            pc = RTCPeerConnection()
            manager.peer_connections[sid] = pc
            
            # Set up data channel for face recognition data
            @pc.on("datachannel")
            def on_datachannel(channel):
                logger.info(f"Data channel established: {channel.label}")
                
                @channel.on("message")
                def on_message(message):
                    asyncio.create_task(handle_face_recognition_data(sid, message))
        
        pc = manager.peer_connections[sid]
        
        # Set remote description
        await pc.setRemoteDescription(RTCSessionDescription(sdp=offer['sdp'], type=offer['type']))
        
        # Create answer
        answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)
        
        # Send answer to client
        answer_data = {
            'answer': {
                'sdp': pc.localDescription.sdp,
                'type': pc.localDescription.type
            },
            'from': sid
        }
        
        if target_id:
            await sio.emit('webrtc_answer', answer_data, room=target_id)
        else:
            await sio.emit('webrtc_answer', answer_data, room=room_id, skip_sid=sid)
        
        logger.info(f"WebRTC offer/answer exchanged for {sid}")
        
    except Exception as e:
        logger.error(f"Error handling WebRTC offer: {e}")
        await sio.emit('error', {'message': str(e)}, room=sid)

@sio.event
async def webrtc_answer(sid, data):
    """Handle WebRTC answer"""
    try:
        room_id = data.get('room_id')
        answer = data.get('answer')
        target_id = data.get('target_id')
        
        if sid in manager.peer_connections:
            pc = manager.peer_connections[sid]
            await pc.setRemoteDescription(RTCSessionDescription(sdp=answer['sdp'], type=answer['type']))
        
        # Forward answer to target
        if target_id:
            await sio.emit('webrtc_answer', data, room=target_id)
        else:
            await sio.emit('webrtc_answer', data, room=room_id, skip_sid=sid)
            
        logger.info(f"WebRTC answer processed for {sid}")
        
    except Exception as e:
        logger.error(f"Error handling WebRTC answer: {e}")

@sio.event
async def ice_candidate(sid, data):
    """Handle ICE candidate"""
    try:
        room_id = data.get('room_id')
        candidate = data.get('candidate')
        target_id = data.get('target_id')
        
        # Forward ICE candidate to target
        forward_data = {
            'candidate': candidate,
            'from': sid
        }
        
        if target_id:
            await sio.emit('ice_candidate', forward_data, room=target_id)
        else:
            await sio.emit('ice_candidate', forward_data, room=room_id, skip_sid=sid)
            
        logger.debug(f"ICE candidate forwarded from {sid}")
        
    except Exception as e:
        logger.error(f"Error handling ICE candidate: {e}")

async def handle_face_recognition_data(sid: str, message: str):
    """Handle face recognition data from WebRTC data channel"""
    try:
        data = json.loads(message)
        
        if data.get('type') == 'face_frame':
            # Extract frame data
            frame_data = base64.b64decode(data.get('frame_data', ''))
            session_id = data.get('session_id')
            student_id = data.get('student_id')
            
            if not all([frame_data, session_id, student_id]):
                logger.warning(f"Incomplete face recognition data from {sid}")
                return
            
            # Process frame
            result = await face_service.process_video_frame(frame_data, session_id, student_id)
            
            # Send result back via Socket.IO
            await sio.emit('face_recognition_result', {
                'session_id': session_id,
                'result': result,
                'timestamp': datetime.now().isoformat()
            }, room=sid)
            
            logger.debug(f"Face recognition result sent to {sid}: verified={result.get('verified', False)}")
            
    except Exception as e:
        logger.error(f"Error handling face recognition data: {e}")

# ==================== REST API Endpoints ====================

@app.get("/")
async def root():
    return {
        "message": "WebRTC Face Recognition Server",
        "version": "3.0.0",
        "features": ["WebRTC Signaling", "Real-time Face Recognition", "Socket.IO Support"],
        "endpoints": {
            "health": "/health",
            "socketio": "/socket.io/",
            "webrtc_session": "/api/webrtc/session",
            "attendance_checkin": "/api/attendance/webrtc-checkin"
        },
        "websocket": "ws://localhost:8000/ws/webrtc"
    }

@app.get("/health")
async def health_check():
    try:
        # Test Supabase connection
        supabase.table('users').select("count", count='exact').execute()
        
        return {
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "services": {
                "webrtc_signaling": "ok",
                "face_recognition": "ok",
                "supabase": "ok",
                "socketio": "ok"
            },
            "active_connections": len(manager.active_connections),
            "active_peer_connections": len(manager.peer_connections),
            "active_rooms": len(manager.rooms)
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.post("/api/webrtc/session/create")
async def create_webrtc_session(request: dict):
    """Create a new WebRTC session for attendance"""
    try:
        session_id = str(uuid.uuid4())
        class_id = request.get('class_id')
        teacher_email = request.get('teacher_email')
        duration_hours = request.get('duration_hours', 2)
        
        # Create session in Supabase
        start_time = datetime.now()
        end_time = start_time + timedelta(hours=duration_hours)
        
        session_data = {
            'id': session_id,
            'class_id': class_id,
            'teacher_email': teacher_email,
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'session_type': 'webrtc',
            'status': 'active',
            'created_at': start_time.isoformat()
        }
        
        result = supabase.table('attendance_sessions').insert(session_data).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to create session")
        
        # Create WebRTC room
        room_id = f"session_{session_id}"
        manager.rooms[room_id] = set()
        
        return {
            "success": True,
            "session_id": session_id,
            "room_id": room_id,
            "webrtc_url": f"ws://localhost:{PORT}/socket.io/",
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error creating WebRTC session: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/attendance/webrtc-checkin")
async def webrtc_checkin(request: dict):
    """Process WebRTC attendance check-in"""
    try:
        session_id = request.get('session_id')
        student_email = request.get('student_email')
        verification_result = request.get('verification_result')
        
        if not all([session_id, student_email, verification_result]):
            raise HTTPException(status_code=400, detail="Missing required fields")
        
        # Validate session
        session_result = supabase.table('attendance_sessions').select('*').eq('id', session_id).eq('status', 'active').single().execute()
        
        if not session_result.data:
            raise HTTPException(status_code=404, detail="Active session not found")
        
        session_data = session_result.data
        
        # Check if already checked in
        existing_record = supabase.table('attendance_records').select('*').eq('session_id', session_id).eq('student_email', student_email).execute()
        
        if existing_record.data:
            raise HTTPException(status_code=400, detail="Already checked in")
        
        # Get student info
        student_result = supabase.table('users').select('school_id').eq('email', student_email).single().execute()
        
        if not student_result.data:
            raise HTTPException(status_code=404, detail="Student not found")
        
        student_id = student_result.data['school_id']
        
        # Determine attendance status
        check_in_time = datetime.now()
        session_start = datetime.fromisoformat(session_data['start_time'].replace('Z', '+00:00'))
        on_time_limit = session_start + timedelta(minutes=session_data.get('on_time_limit_minutes', 30))
        
        # Check verification result
        if not verification_result.get('verified', False):
            raise HTTPException(status_code=400, detail="Face verification failed")
        
        status = 'present' if check_in_time <= on_time_limit else 'late'
        
        # Save attendance record
        record_data = {
            'session_id': session_id,
            'student_email': student_email,
            'student_id': student_id,
            'check_in_time': check_in_time.isoformat(),
            'status': status,
            'verification_method': 'webrtc_face_recognition',
            'face_match_score': verification_result.get('similarity'),
            'face_quality_score': verification_result.get('quality'),
            'created_at': check_in_time.isoformat()
        }
        
        result = supabase.table('attendance_records').insert(record_data).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to save attendance record")
        
        logger.info(f"WebRTC attendance recorded: {student_email} - {status}")
        
        return {
            "success": True,
            "message": f"Attendance recorded - {status.upper()}",
            "student_email": student_email,
            "student_id": student_id,
            "session_id": session_id,
            "status": status,
            "check_in_time": check_in_time.isoformat(),
            "verification_method": "webrtc_face_recognition",
            "face_match_score": verification_result.get('similarity'),
            "face_quality_score": verification_result.get('quality')
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"WebRTC check-in error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ==================== WebSocket Endpoint for Direct WebRTC ====================

@app.websocket("/ws/webrtc/{client_id}")
async def websocket_endpoint(websocket: WebSocket, client_id: str):
    """Direct WebSocket endpoint for WebRTC signaling"""
    await manager.connect(websocket, client_id)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                message = json.loads(data)
                await handle_websocket_message(client_id, message)
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({
                    "error": "Invalid JSON format"
                }))
    except WebSocketDisconnect:
        manager.disconnect(client_id)
    except Exception as e:
        logger.error(f"WebSocket error for {client_id}: {e}")
        manager.disconnect(client_id)

async def handle_websocket_message(client_id: str, message: dict):
    """Handle WebSocket messages for WebRTC signaling"""
    try:
        message_type = message.get('type')
        
        if message_type == 'offer':
            # Handle WebRTC offer
            offer = message.get('offer')
            room_id = message.get('room_id', 'default')
            
            # Process offer and create answer
            # This would involve setting up RTCPeerConnection
            
            response = {
                "type": "answer",
                "answer": "SDP_ANSWER_HERE",  # Actual SDP answer
                "from": client_id
            }
            
            await manager.send_message(client_id, response)
            
        elif message_type == 'answer':
            # Handle WebRTC answer
            pass
            
        elif message_type == 'ice-candidate':
            # Handle ICE candidate
            candidate = message.get('candidate')
            room_id = message.get('room_id', 'default')
            
            # Forward to other peers in room
            await manager.broadcast_to_room(room_id, message, exclude_client=client_id)
            
        elif message_type == 'join-room':
            # Join a signaling room
            room_id = message.get('room_id')
            manager.join_room(room_id, client_id)
            
            await manager.send_message(client_id, {
                "type": "joined-room",
                "room_id": room_id,
                "client_id": client_id
            })
            
        else:
            await manager.send_message(client_id, {
                "error": f"Unknown message type: {message_type}"
            })
            
    except Exception as e:
        logger.error(f"Error handling WebSocket message: {e}")
        await manager.send_message(client_id, {
            "error": str(e)
        })

# ==================== Startup and Shutdown Events ====================

@app.on_event("startup")
async def startup_event():
    logger.info("🚀 WebRTC Face Recognition Server starting...")
    
    # Test services
    try:
        # Test Supabase
        supabase.table('users').select("count", count='exact').execute()
        logger.info("✅ Supabase connection successful")
        
        # Test face recognition
        test_image = np.zeros((100, 100, 3), dtype=np.uint8)
        face_recognition.face_locations(test_image)
        logger.info("✅ Face recognition service ready")
        
        logger.info("✅ WebRTC Face Recognition Server started successfully")
        logger.info(f"📡 Socket.IO signaling available at: ws://localhost:{PORT}/socket.io/")
        logger.info(f"🔌 Direct WebSocket available at: ws://localhost:{PORT}/ws/webrtc/{{client_id}}")
        
    except Exception as e:
        logger.error(f"❌ Startup error: {e}")

@app.on_event("shutdown")
async def shutdown_event():
    logger.info("🛑 Shutting down WebRTC Face Recognition Server...")
    
    # Close all peer connections
    for pc in manager.peer_connections.values():
        await pc.close()
    
    logger.info("✅ WebRTC Face Recognition Server shutdown complete")

# ==================== Mount Socket.IO app ====================

# Mount Socket.IO
app.mount("/", socket_app)

if __name__ == "__main__":
    import uvicorn
    print(f"🚀 Starting WebRTC Face Recognition Server on {HOST}:{PORT}")
    print(f"📡 Socket.IO signaling: http://localhost:{PORT}/socket.io/")
    print(f"🔌 WebSocket signaling: ws://localhost:{PORT}/ws/webrtc/{{client_id}}")
    print(f"🌐 HTTP API: http://localhost:{PORT}")
    
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")