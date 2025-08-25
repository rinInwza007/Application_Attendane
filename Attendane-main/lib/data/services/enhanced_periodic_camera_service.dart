// lib/data/services/enhanced_periodic_camera_service.dart
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/services/enhanced_attendance_service.dart';

enum CameraServiceStatus {
  notInitialized,
  initializing,
  ready,
  capturing,
  error,
  stopped
}

class EnhancedPeriodicCameraService {
  // Camera controller
  CameraController? _cameraController;
  CameraController? get controller => _cameraController;
  
  // Service state
  bool _isInitialized = false;
  bool _isRunning = false;
  CameraServiceStatus _status = CameraServiceStatus.notInitialized;
  
  // Session and capture data
  String? _sessionId;
  Timer? _captureTimer;
  int _captureCount = 0;
  
  // Callbacks
  Function(String imagePath, DateTime captureTime)? onImageCaptured;
  Function(Map<String, dynamic> result)? onAttendanceProcessed;
  Function(String error)? onError;
  Function(CameraServiceStatus status)? onStatusChanged;
  Function(Map<String, dynamic> stats)? onStatsUpdated;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isRunning => _isRunning;
  bool get isReady => _isInitialized && _cameraController != null && _cameraController!.value.isInitialized;
  CameraServiceStatus get status => _status;
  int get captureCount => _captureCount;

  // Initialize camera
  Future<bool> initialize() async {
    try {
      _setStatus(CameraServiceStatus.initializing);
      
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Use front camera if available, otherwise use the first camera
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      
      _isInitialized = true;
      _setStatus(CameraServiceStatus.ready);
      
      print('✅ Enhanced Periodic Camera Service initialized successfully');
      return true;
      
    } catch (e) {
      print('❌ Error initializing enhanced periodic camera service: $e');
      _setStatus(CameraServiceStatus.error);
      _notifyError('Camera initialization failed: $e');
      return false;
    }
  }

  // Start periodic capture
  Future<void> startPeriodicCapture({
    required AttendanceSessionModel session,
    required Duration interval,
  }) async {
    if (!isReady) {
      throw Exception('Camera not ready. Please initialize first.');
    }

    if (_isRunning) {
      print('⚠️ Periodic capture already running');
      return;
    }

    _isRunning = true;
    _sessionId = session.id;
    _captureCount = 0;
    
    print('🔄 Starting periodic capture every ${interval.inMinutes} minutes for session: ${session.id}');

    // Start periodic timer
    _captureTimer = Timer.periodic(interval, (timer) async {
      if (!_isRunning || !isReady) {
        timer.cancel();
        return;
      }

      try {
        _setStatus(CameraServiceStatus.capturing);
        
        final imagePath = await captureSingleImage();
        if (imagePath != null && _sessionId != null) {
          _captureCount++;
          
          // Notify that image was captured
          _notifyImageCaptured(imagePath, DateTime.now());
          
          // Process with session ID
          await _processPeriodicImage(imagePath, _sessionId!);
          
          // Update stats
          _updateStats();
        }
        
        _setStatus(CameraServiceStatus.ready);
        
      } catch (e) {
        print('❌ Error in periodic capture: $e');
        _setStatus(CameraServiceStatus.error);
        _notifyError('Capture error: $e');
      }
    });

    _setStatus(CameraServiceStatus.capturing);
    print('🎯 Periodic capture started successfully');
  }

  // Stop periodic capture
  Future<void> stopPeriodicCapture() async {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    
    _setStatus(CameraServiceStatus.ready);
    print('⏹️ Periodic capture stopped');
  }

  // Capture single image
  Future<String?> captureSingleImage() async {
    if (!isReady) {
      throw Exception('Camera not ready');
    }

    try {
      // Take picture
      final XFile imageFile = await _cameraController!.takePicture();
      
      // Save to permanent location
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'attendance_capture_$timestamp.jpg';
      final String savedPath = path.join(appDir.path, 'attendance_captures', fileName);
      
      // Ensure directory exists
      final Directory captureDir = Directory(path.dirname(savedPath));
      if (!await captureDir.exists()) {
        await captureDir.create(recursive: true);
      }
      
      // Copy to permanent location
      await File(imageFile.path).copy(savedPath);
      
      // Delete temporary file
      try {
        await File(imageFile.path).delete();
      } catch (e) {
        print('Warning: Could not delete temporary file: $e');
      }

      print('📸 Image captured: ${path.basename(savedPath)}');
      return savedPath;
      
    } catch (e) {
      print('❌ Error capturing image: $e');
      throw Exception('Failed to capture image: $e');
    }
  }

  // Process periodic image with FastAPI
  Future<void> _processPeriodicImage(String imagePath, String sessionId) async {
    try {
      print('📤 Sending periodic image to FastAPI server...');
      
      final attendanceService = EnhancedAttendanceService();
      
      // Send to FastAPI periodic endpoint
      final result = await attendanceService.processPeriodicAttendance(
        imagePath: imagePath,
        sessionId: sessionId,
        captureTime: DateTime.now(),
      );
      
      if (result['success']) {
        final facesDetected = result['faces_detected'] as int? ?? 0;
        print('✅ Periodic attendance processed: $facesDetected faces detected');
        
        // Notify Flutter UI
        _notifyAttendanceProcessed(result);
      } else {
        print('❌ Periodic attendance processing failed: ${result['message'] ?? 'Unknown error'}');
        _notifyError('Processing failed: ${result['message'] ?? 'Unknown error'}');
      }
      
      // Clean up image file after processing
      try {
        await File(imagePath).delete();
        print('🗑️ Temporary image deleted: ${path.basename(imagePath)}');
      } catch (e) {
        print('⚠️ Could not delete image file: $e');
      }
      
    } catch (e) {
      print('❌ Error processing periodic image: $e');
      _notifyError('Network error: $e');
    }
  }

  // Status management
  void _setStatus(CameraServiceStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      onStatusChanged?.call(newStatus);
    }
  }

  // Notification helpers
  void _notifyImageCaptured(String imagePath, DateTime captureTime) {
    onImageCaptured?.call(imagePath, captureTime);
  }

  void _notifyAttendanceProcessed(Map<String, dynamic> result) {
    onAttendanceProcessed?.call(result);
  }

  void _notifyError(String error) {
    onError?.call(error);
  }

  void _updateStats() {
    final stats = {
      'total_captures': _captureCount,
      'session_id': _sessionId,
      'is_running': _isRunning,
      'status': _status.toString(),
      'last_capture_time': DateTime.now().toIso8601String(),
    };
    
    onStatsUpdated?.call(stats);
  }

  // Dispose resources
  Future<void> dispose() async {
    try {
      await stopPeriodicCapture();
      await _cameraController?.dispose();
      _cameraController = null;
      _isInitialized = false;
      _setStatus(CameraServiceStatus.stopped);
      
      print('🧹 Enhanced Periodic Camera Service disposed');
    } catch (e) {
      print('❌ Error disposing camera service: $e');
    }
  }

  // Get service information
  Map<String, dynamic> getServiceInfo() {
    return {
      'is_initialized': _isInitialized,
      'is_running': _isRunning,
      'is_ready': isReady,
      'status': _status.toString(),
      'session_id': _sessionId,
      'capture_count': _captureCount,
      'camera_description': _cameraController?.description.name,
      'resolution_preset': _cameraController?.resolutionPreset.toString(),
    };
  }

  // Health check
  bool isHealthy() {
    return _isInitialized && 
           _cameraController != null && 
           _cameraController!.value.isInitialized &&
           !_cameraController!.value.hasError;
  }

  // Get current session ID
  String? getCurrentSessionId() => _sessionId;

  // Reset service
  Future<void> reset() async {
    await stopPeriodicCapture();
    _captureCount = 0;
    _sessionId = null;
    _setStatus(CameraServiceStatus.ready);
    print('🔄 Enhanced Periodic Camera Service reset');
  }
}