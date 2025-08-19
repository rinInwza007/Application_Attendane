// lib/data/services/enhanced_periodic_camera_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:myproject2/data/services/enhanced_attendance_service.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';

enum CameraServiceStatus {
  idle,
  initializing,
  ready,
  capturing,
  processing,
  error
}

class EnhancedPeriodicCameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  Timer? _periodicTimer;
  Timer? _sessionTimer;
  
  final EnhancedAttendanceService _attendanceService = EnhancedAttendanceService();
  
  // Current state
  CameraServiceStatus _status = CameraServiceStatus.idle;
  AttendanceSessionModel? _currentSession;
  
  // Configuration
  Duration _captureInterval = const Duration(minutes: 5);
  bool _isRunning = false;
  bool _isInitialized = false;
  
  // Statistics
  int _totalCaptures = 0;
  int _successfulCaptures = 0;
  int _processedImages = 0;
  int _detectedFaces = 0;
  DateTime? _lastCaptureTime;
  DateTime? _sessionStartTime;
  
  // Error handling
  String? _lastError;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  
  // Callbacks
  Function(String imagePath, DateTime captureTime)? onImageCaptured;
  Function(Map<String, dynamic> result)? onAttendanceProcessed;
  Function(String error)? onError;
  Function(CameraServiceStatus status)? onStatusChanged;
  Function(Map<String, dynamic> stats)? onStatsUpdated;

  // Getters
  bool get isRunning => _isRunning;
  bool get isInitialized => _isInitialized;
  CameraServiceStatus get status => _status;
  CameraController? get controller => _controller;
  Map<String, dynamic> get statistics => _getStatistics();
  AttendanceSessionModel? get currentSession => _currentSession;
  
  /// Initialize camera service with enhanced error handling
  Future<bool> initialize() async {
    try {
      _updateStatus(CameraServiceStatus.initializing);
      print('🔄 Initializing enhanced periodic camera service...');
      
      // Test server connection first
      final serverHealthy = await _attendanceService.testServerConnection();
      if (!serverHealthy) {
        throw Exception('Face recognition server is not available');
      }
      
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras available on this device');
      }
      
      // Prefer front camera for attendance
      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      
      _controller = CameraController(
        frontCamera,
        ResolutionPreset.high, // Higher quality for better face recognition
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      await _controller!.initialize();
      
      _isInitialized = true;
      _consecutiveErrors = 0;
      _lastError = null;
      
      _updateStatus(CameraServiceStatus.ready);
      print('✅ Enhanced periodic camera service initialized');
      return true;
      
    } catch (e) {
      _lastError = e.toString();
      _updateStatus(CameraServiceStatus.error);
      print('❌ Error initializing camera: $e');
      onError?.call('Failed to initialize camera: $e');
      return false;
    }
  }

  /// Start periodic capture with session management
  Future<void> startPeriodicCapture({
    required AttendanceSessionModel session,
    Duration? interval,
  }) async {
    if (!_isInitialized || _isRunning) return;
    
    try {
      _currentSession = session;
      _captureInterval = interval ?? Duration(minutes: session.captureIntervalMinutes ?? 5);
      
      _isRunning = true;
      _sessionStartTime = DateTime.now();
      _totalCaptures = 0;
      _successfulCaptures = 0;
      _processedImages = 0;
      _detectedFaces = 0;
      
      _updateStatus(CameraServiceStatus.capturing);
      print('📸 Starting periodic capture for session: ${session.id}');
      print('   Interval: ${_captureInterval.inMinutes} minutes');
      print('   Session duration: ${session.durationText}');
      
      // Start session monitoring
      _startSessionMonitoring();
      
      // Capture first image immediately
      await _captureAndProcess();
      
      // Set up periodic timer
      _periodicTimer = Timer.periodic(_captureInterval, (timer) async {
        if (_isRunning && _isInitialized && _currentSession != null) {
          // Check if session is still active
          if (_currentSession!.isActive) {
            await _captureAndProcess();
          } else {
            print('⏰ Session ended, stopping periodic capture');
            await stopPeriodicCapture();
          }
        } else {
          timer.cancel();
        }
      });
      
      _updateStats();
      
    } catch (e) {
      print('❌ Error starting periodic capture: $e');
      onError?.call('Failed to start periodic capture: $e');
      await stopPeriodicCapture();
    }
  }

  /// Stop periodic capture
  Future<void> stopPeriodicCapture() async {
    if (!_isRunning) return;
    
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _sessionTimer?.cancel();
    _sessionTimer = null;
    
    _isRunning = false;
    _currentSession = null;
    
    _updateStatus(CameraServiceStatus.ready);
    print('⏹️ Periodic capture stopped');
    
    // Final statistics update
    _updateStats();
    
    // Cleanup old images
    await _cleanupOldImages();
  }

  /// Session monitoring
  void _startSessionMonitoring() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_currentSession != null) {
        if (_currentSession!.isActive) {
          _updateStats();
        } else {
          print('⏰ Session expired, stopping monitoring');
          timer.cancel();
          stopPeriodicCapture();
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// Capture and process image with enhanced error handling
  Future<void> _captureAndProcess() async {
    if (!_isInitialized || _controller == null || !_controller!.value.isInitialized) {
      return;
    }
    
    final captureTime = DateTime.now();
    String? imagePath;
    
    try {
      _updateStatus(CameraServiceStatus.capturing);
      _totalCaptures++;
      
      print('📷 Capturing image ${_totalCaptures} at ${_formatTime(captureTime)}');
      
      // Capture image
      final XFile imageFile = await _controller!.takePicture();
      
      // Save to permanent location
      imagePath = await _saveImagePermanently(imageFile);
      
      // Delete temporary file
      await File(imageFile.path).delete();
      
      _successfulCaptures++;
      _lastCaptureTime = captureTime;
      
      // Notify about image capture
      onImageCaptured?.call(imagePath, captureTime);
      
      // Process with FastAPI in background
      _processAttendanceInBackground(imagePath, captureTime);
      
      // Reset error counter on success
      _consecutiveErrors = 0;
      _lastError = null;
      
      _updateStatus(CameraServiceStatus.ready);
      
    } catch (e) {
      _consecutiveErrors++;
      _lastError = e.toString();
      
      print('❌ Error in capture ${_totalCaptures}: $e');
      print('   Consecutive errors: $_consecutiveErrors/$_maxConsecutiveErrors');
      
      // Clean up partial image if exists
      if (imagePath != null) {
        try {
          await File(imagePath).delete();
        } catch (deleteError) {
          print('⚠️ Failed to delete failed capture: $deleteError');
        }
      }
      
      // Stop if too many consecutive errors
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        print('💥 Too many consecutive errors, stopping periodic capture');
        await stopPeriodicCapture();
        onError?.call('Stopped due to repeated capture failures: $e');
      } else {
        onError?.call('Capture failed (${_consecutiveErrors}/$_maxConsecutiveErrors): $e');
      }
      
      _updateStatus(CameraServiceStatus.error);
    } finally {
      _updateStats();
    }
  }

  /// Process attendance in background
  void _processAttendanceInBackground(String imagePath, DateTime captureTime) async {
    if (_currentSession == null) return;
    
    try {
      _updateStatus(CameraServiceStatus.processing);
      _processedImages++;
      
      print('🔄 Processing attendance for image: ${path.basename(imagePath)}');
      
      // Send to FastAPI for processing
      final result = await _attendanceService.processPeriodicAttendance(
        imagePath: imagePath,
        sessionId: _currentSession!.id,
        captureTime: captureTime,
        deleteImageAfter: true, // Clean up after processing
      );
      
      if (result['success']) {
        final facesDetected = result['faces_detected'] as int? ?? 0;
        _detectedFaces += facesDetected;
        
        print('✅ Attendance processed successfully');
        print('   Faces detected: $facesDetected');
        print('   Total faces so far: $_detectedFaces');
        
        onAttendanceProcessed?.call(result);
      } else {
        print('❌ Attendance processing failed: ${result['error']}');
        onError?.call('Attendance processing failed: ${result['error']}');
      }
      
    } catch (e) {
      print('❌ Error in background processing: $e');
      onError?.call('Background processing error: $e');
    } finally {
      _updateStatus(CameraServiceStatus.ready);
      _updateStats();
    }
  }

  /// Save captured image to permanent location
  Future<String> _saveImagePermanently(XFile imageFile) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String fileName = 'attendance_$timestamp.jpg';
    final String savedPath = path.join(appDir.path, 'attendance_images', fileName);
    
    // Ensure directory exists
    final Directory imageDir = Directory(path.dirname(savedPath));
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    
    // Copy to permanent location
    final File permanentFile = await File(imageFile.path).copy(savedPath);
    
    print('💾 Image saved: $savedPath (${await _getFileSize(permanentFile)})');
    
    return savedPath;
  }

  /// Capture single image manually
  Future<String?> captureSingleImage() async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Camera not initialized');
    }
    
    try {
      print('📸 Capturing single image manually');
      
      final XFile imageFile = await _controller!.takePicture();
      final String savedPath = await _saveImagePermanently(imageFile);
      
      // Delete temporary file
      await File(imageFile.path).delete();
      
      return savedPath;
      
    } catch (e) {
      print('❌ Error capturing single image: $e');
      onError?.call('Failed to capture image: $e');
      return null;
    }
  }

  /// Switch camera (front/back)
  Future<bool> switchCamera() async {
    if (!_isInitialized || _cameras.length < 2) return false;
    
    try {
      final currentCamera = _controller!.description;
      final newCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection != currentCamera.lensDirection,
        orElse: () => _cameras.first,
      );
      
      if (newCamera == currentCamera) return false;
      
      await _controller!.dispose();
      
      _controller = CameraController(
        newCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      await _controller!.initialize();
      
      print('🔄 Camera switched to: ${newCamera.lensDirection}');
      return true;
      
    } catch (e) {
      print('❌ Error switching camera: $e');
      onError?.call('Failed to switch camera: $e');
      return false;
    }
  }

  /// Update status and notify listeners
  void _updateStatus(CameraServiceStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      onStatusChanged?.call(newStatus);
    }
  }

  /// Update statistics and notify listeners
  void _updateStats() {
    onStatsUpdated?.call(_getStatistics());
  }

  /// Get comprehensive statistics
  Map<String, dynamic> _getStatistics() {
    final sessionDuration = _sessionStartTime != null 
        ? DateTime.now().difference(_sessionStartTime!)
        : Duration.zero;
    
    return {
      'status': _status.toString().split('.').last,
      'isInitialized': _isInitialized,
      'isRunning': _isRunning,
      'currentSession': _currentSession?.id,
      'captureInterval': _captureInterval.inMinutes,
      'totalCaptures': _totalCaptures,
      'successfulCaptures': _successfulCaptures,
      'processedImages': _processedImages,
      'detectedFaces': _detectedFaces,
      'consecutiveErrors': _consecutiveErrors,
      'lastError': _lastError,
      'lastCaptureTime': _lastCaptureTime?.toIso8601String(),
      'sessionDuration': sessionDuration.inMinutes,
      'captureSuccessRate': _totalCaptures > 0 ? _successfulCaptures / _totalCaptures : 0.0,
      'facesPerCapture': _successfulCaptures > 0 ? _detectedFaces / _successfulCaptures : 0.0,
      'availableCameras': _cameras.length,
      'currentCamera': _controller?.description.lensDirection.toString(),
    };
  }

  /// Clean up old images
  Future<void> _cleanupOldImages({int maxAgeHours = 24}) async {
    try {
      await _attendanceService.cleanupOldImages(maxAgeHours: maxAgeHours);
    } catch (e) {
      print('⚠️ Error during image cleanup: $e');
    }
  }

  /// Utility methods
  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}:'
           '${dateTime.second.toString().padLeft(2, '0')}';
  }

  Future<String> _getFileSize(File file) async {
    try {
      final bytes = await file.length();
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Test capture functionality
  Future<Map<String, dynamic>> testCapture() async {
    try {
      if (!_isInitialized) {
        throw Exception('Camera not initialized');
      }
      
      print('🧪 Testing capture functionality...');
      
      final startTime = DateTime.now();
      final imagePath = await captureSingleImage();
      final endTime = DateTime.now();
      
      if (imagePath == null) {
        throw Exception('Failed to capture test image');
      }
      
      final file = File(imagePath);
      final fileSize = await file.length();
      
      // Clean up test image
      await file.delete();
      
      final duration = endTime.difference(startTime);
      
      return {
        'success': true,
        'capture_time_ms': duration.inMilliseconds,
        'file_size_bytes': fileSize,
        'message': 'Capture test successful'
      };
      
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Capture test failed'
      };
    }
  }

  /// Get camera information
  Map<String, dynamic> getCameraInfo() {
    if (!_isInitialized || _controller == null) {
      return {'initialized': false};
    }
    
    final cameraValue = _controller!.value;
    
    return {
      'initialized': _isInitialized,
      'isRecording': cameraValue.isRecordingVideo,
      'previewSize': {
        'width': cameraValue.previewSize?.width,
        'height': cameraValue.previewSize?.height,
      },
      'aspectRatio': cameraValue.aspectRatio,
      'flashMode': cameraValue.flashMode.toString(),
      'exposureMode': cameraValue.exposureMode.toString(),
      'focusMode': cameraValue.focusMode.toString(),
      'currentCamera': {
        'name': _controller!.description.name,
        'lensDirection': _controller!.description.lensDirection.toString(),
        'sensorOrientation': _controller!.description.sensorOrientation,
      },
      'availableCameras': _cameras.map((camera) => {
        'name': camera.name,
        'lensDirection': camera.lensDirection.toString(),
        'sensorOrientation': camera.sensorOrientation,
      }).toList(),
    };
  }

  /// Reset error state
  void resetErrorState() {
    _consecutiveErrors = 0;
    _lastError = null;
    if (_status == CameraServiceStatus.error) {
      _updateStatus(CameraServiceStatus.ready);
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    try {
      print('🧹 Disposing enhanced periodic camera service...');
      
      await stopPeriodicCapture();
      
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }
      
      _attendanceService.dispose();
      
      _isInitialized = false;
      _updateStatus(CameraServiceStatus.idle);
      
      print('✅ Enhanced periodic camera service disposed');
      
    } catch (e) {
      print('❌ Error disposing camera service: $e');
    }
  }
}