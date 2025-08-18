// lib/data/services/webrtc_camera_service.dart
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

class WebRTCCameraService {
  // WebRTC Components
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCVideoRenderer? _localRenderer;
  
  // WebSocket for signaling
  WebSocketChannel? _signalingChannel;
  
  // Configuration
  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };
  
  // State Management
  bool _isInitialized = false;
  bool _isConnected = false;
  bool _isCameraOn = false;
  String? _sessionId;
  String? _deviceId;
  
  // Callbacks
  Function(Uint8List imageData)? onFrameCaptured;
  Function(String error)? onError;
  Function(bool connected)? onConnectionChanged;
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;
  bool get isCameraOn => _isCameraOn;
  RTCVideoRenderer? get localRenderer => _localRenderer;
  String? get sessionId => _sessionId;

  // Initialize WebRTC Camera Service
  Future<bool> initialize() async {
    try {
      print('🔄 Initializing WebRTC Camera Service...');
      
      // Request permissions
      if (!await _requestPermissions()) {
        throw Exception('Camera permissions denied');
      }
      
      // Generate session ID
      _sessionId = const Uuid().v4();
      _deviceId = await _getDeviceId();
      
      // Initialize video renderer
      _localRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();
      
      // Setup peer connection
      await _setupPeerConnection();
      
      _isInitialized = true;
      print('✅ WebRTC Camera Service initialized');
      return true;
      
    } catch (e) {
      print('❌ Error initializing WebRTC: $e');
      onError?.call('Failed to initialize camera: $e');
      return false;
    }
  }

  // Request necessary permissions
  Future<bool> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();
    
    return cameraStatus.isGranted && microphoneStatus.isGranted;
  }

  // Get device ID for identification
  Future<String> _getDeviceId() async {
    try {
      // You can use device_info_plus to get actual device ID
      return Platform.isAndroid ? 'android_device' : 'ios_device';
    } catch (e) {
      return 'unknown_device';
    }
  }

  // Setup WebRTC Peer Connection
  Future<void> _setupPeerConnection() async {
    try {
      _peerConnection = await createPeerConnection(_iceServers);
      
      // Set up event handlers
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _sendSignalingMessage({
          'type': 'ice-candidate',
          'candidate': candidate.toMap(),
          'sessionId': _sessionId,
        });
      };
      
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('📡 Connection state: $state');
        
        final connected = state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        if (_isConnected != connected) {
          _isConnected = connected;
          onConnectionChanged?.call(connected);
        }
      };
      
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        print('📺 Received track: ${event.track.kind}');
      };
      
    } catch (e) {
      print('❌ Error setting up peer connection: $e');
      throw Exception('Failed to setup peer connection: $e');
    }
  }

  // Start camera and begin streaming
  Future<bool> startCamera({CameraPosition position = CameraPosition.front}) async {
    try {
      if (!_isInitialized) {
        throw Exception('Service not initialized');
      }
      
      print('📱 Starting camera...');
      
      // Get user media (camera)
      final Map<String, dynamic> constraints = {
        'audio': false, // No audio for face recognition
        'video': {
          'facingMode': position == CameraPosition.front ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30, 'max': 30},
        }
      };
      
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      
      if (_localStream != null) {
        // Add stream to peer connection
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
        
        // Set stream to renderer
        _localRenderer!.srcObject = _localStream;
        
        // Start frame capture for face recognition
        _startFrameCapture();
        
        _isCameraOn = true;
        print('✅ Camera started successfully');
        return true;
      }
      
      return false;
      
    } catch (e) {
      print('❌ Error starting camera: $e');
      onError?.call('Failed to start camera: $e');
      return false;
    }
  }

  // Start capturing frames for face recognition
  void _startFrameCapture() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isCameraOn || _localRenderer == null) {
        timer.cancel();
        return;
      }
      
      try {
        // Capture frame from video renderer
        final imageData = await _captureFrame();
        if (imageData != null) {
          onFrameCaptured?.call(imageData);
        }
      } catch (e) {
        print('⚠️ Error capturing frame: $e');
      }
    });
  }

  // Capture frame from video renderer
  Future<Uint8List?> _captureFrame() async {
    try {
      if (_localRenderer == null || _localRenderer!.srcObject == null) {
        return null;
      }
      
      // This is a simplified implementation
      // In real implementation, you'd capture actual video frame
      // For now, we'll use a placeholder approach
      
      return null; // Will be implemented with actual frame capture
      
    } catch (e) {
      print('❌ Error capturing frame: $e');
      return null;
    }
  }

  // Stop camera
  Future<void> stopCamera() async {
    try {
      print('📱 Stopping camera...');
      
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          track.stop();
        });
        _localStream = null;
      }
      
      _isCameraOn = false;
      print('✅ Camera stopped');
      
    } catch (e) {
      print('❌ Error stopping camera: $e');
    }
  }

  // Switch camera (front/back)
  Future<bool> switchCamera() async {
    try {
      if (!_isCameraOn) return false;
      
      print('🔄 Switching camera...');
      
      await stopCamera();
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Switch to opposite camera
      final newPosition = _getCurrentCameraPosition() == CameraPosition.front 
          ? CameraPosition.back 
          : CameraPosition.front;
      
      return await startCamera(position: newPosition);
      
    } catch (e) {
      print('❌ Error switching camera: $e');
      return false;
    }
  }

  // Get current camera position
  CameraPosition _getCurrentCameraPosition() {
    // This would be tracked in actual implementation
    return CameraPosition.front;
  }

  // Connect to signaling server
  Future<bool> connectToSignalingServer(String serverUrl) async {
    try {
      print('🔌 Connecting to signaling server: $serverUrl');
      
      _signalingChannel = WebSocketChannel.connect(Uri.parse(serverUrl));
      
      // Listen for signaling messages
      _signalingChannel!.stream.listen(
        (message) => _handleSignalingMessage(message),
        onError: (error) {
          print('❌ Signaling error: $error');
          onError?.call('Signaling connection failed: $error');
        },
        onDone: () {
          print('📡 Signaling connection closed');
          _isConnected = false;
          onConnectionChanged?.call(false);
        },
      );
      
      // Send initial connection message
      _sendSignalingMessage({
        'type': 'join',
        'sessionId': _sessionId,
        'deviceId': _deviceId,
        'role': 'camera', // This device acts as camera
      });
      
      return true;
      
    } catch (e) {
      print('❌ Error connecting to signaling server: $e');
      return false;
    }
  }

  // Handle incoming signaling messages
  void _handleSignalingMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];
      
      switch (type) {
        case 'offer':
          _handleOffer(data);
          break;
        case 'answer':
          _handleAnswer(data);
          break;
        case 'ice-candidate':
          _handleIceCandidate(data);
          break;
        case 'joined':
          print('✅ Successfully joined session');
          _isConnected = true;
          onConnectionChanged?.call(true);
          break;
        default:
          print('📨 Unknown signaling message: $type');
      }
      
    } catch (e) {
      print('❌ Error handling signaling message: $e');
    }
  }

  // Handle WebRTC offer
  Future<void> _handleOffer(Map<String, dynamic> data) async {
    try {
      final offer = RTCSessionDescription(data['sdp'], data['type']);
      await _peerConnection!.setRemoteDescription(offer);
      
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      
      _sendSignalingMessage({
        'type': 'answer',
        'sdp': answer.sdp,
        'sessionId': _sessionId,
      });
      
    } catch (e) {
      print('❌ Error handling offer: $e');
    }
  }

  // Handle WebRTC answer
  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    try {
      final answer = RTCSessionDescription(data['sdp'], data['type']);
      await _peerConnection!.setRemoteDescription(answer);
      
    } catch (e) {
      print('❌ Error handling answer: $e');
    }
  }

  // Handle ICE candidate
  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    try {
      final candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      
      await _peerConnection!.addCandidate(candidate);
      
    } catch (e) {
      print('❌ Error handling ICE candidate: $e');
    }
  }

  // Send signaling message
  void _sendSignalingMessage(Map<String, dynamic> message) {
    try {
      if (_signalingChannel != null) {
        _signalingChannel!.sink.add(jsonEncode(message));
      }
    } catch (e) {
      print('❌ Error sending signaling message: $e');
    }
  }

  // Create offer for peer connection
  Future<void> createOffer() async {
    try {
      if (_peerConnection == null) return;
      
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      
      _sendSignalingMessage({
        'type': 'offer',
        'sdp': offer.sdp,
        'sessionId': _sessionId,
      });
      
    } catch (e) {
      print('❌ Error creating offer: $e');
    }
  }

  // Capture high-quality image for face recognition
  Future<Uint8List?> captureHighQualityImage() async {
    try {
      if (!_isCameraOn || _localRenderer == null) {
        throw Exception('Camera not active');
      }
      
      print('📷 Capturing high-quality image...');
      
      // In actual implementation, this would capture frame from video stream
      // For now, returning null - this needs platform-specific implementation
      
      return null;
      
    } catch (e) {
      print('❌ Error capturing image: $e');
      return null;
    }
  }

  // Get camera capabilities
  Map<String, dynamic> getCameraCapabilities() {
    return {
      'isInitialized': _isInitialized,
      'isConnected': _isConnected,
      'isCameraOn': _isCameraOn,
      'sessionId': _sessionId,
      'deviceId': _deviceId,
      'hasLocalRenderer': _localRenderer != null,
    };
  }

  // Dispose resources
  Future<void> dispose() async {
    try {
      print('🧹 Disposing WebRTC Camera Service...');
      
      await stopCamera();
      
      _signalingChannel?.sink.close();
      _signalingChannel = null;
      
      await _peerConnection?.close();
      _peerConnection = null;
      
      await _localRenderer?.dispose();
      _localRenderer = null;
      
      _isInitialized = false;
      _isConnected = false;
      _isCameraOn = false;
      
      print('✅ WebRTC Camera Service disposed');
      
    } catch (e) {
      print('❌ Error disposing WebRTC service: $e');
    }
  }
}

// Camera position enum
enum CameraPosition {
  front,
  back,
}

// WebRTC Camera Exception
class WebRTCCameraException implements Exception {
  final String message;
  final String? code;
  
  WebRTCCameraException(this.message, {this.code});
  
  @override
  String toString() => 'WebRTCCameraException: $message';
}