// lib/data/services/periodic_camera_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PeriodicCameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  Timer? _periodicTimer;
  
  // Callbacks
  Function(String imagePath)? onImageCaptured;
  Function(String error)? onError;
  Function(bool isActive)? onStatusChanged;
  
  // Configuration
  Duration captureInterval = const Duration(minutes: 5);
  bool _isRunning = false;
  bool _isInitialized = false;
  
  // Getters
  bool get isRunning => _isRunning;
  bool get isInitialized => _isInitialized;
  CameraController? get controller => _controller;

  /// Initialize camera service
  Future<bool> initialize() async {
    try {
      print('🔄 Initializing periodic camera service...');
      
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras available');
      }
      
      // Use front camera if available
      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      
      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      await _controller!.initialize();
      
      _isInitialized = true;
      print('✅ Periodic camera service initialized');
      return true;
      
    } catch (e) {
      print('❌ Error initializing camera: $e');
      onError?.call('Failed to initialize camera: $e');
      return false;
    }
  }

  /// Start periodic capture
  Future<void> startPeriodicCapture({Duration? interval}) async {
    if (!_isInitialized || _isRunning) return;
    
    try {
      if (interval != null) captureInterval = interval;
      
      _isRunning = true;
      onStatusChanged?.call(true);
      
      print('📸 Starting periodic capture every ${captureInterval.inMinutes} minutes');
      
      // Capture first image immediately
      await _captureAndSave();
      
      // Set up periodic timer
      _periodicTimer = Timer.periodic(captureInterval, (timer) async {
        if (_isRunning && _isInitialized) {
          await _captureAndSave();
        } else {
          timer.cancel();
        }
      });
      
    } catch (e) {
      print('❌ Error starting periodic capture: $e');
      onError?.call('Failed to start periodic capture: $e');
    }
  }

  /// Stop periodic capture
  void stopPeriodicCapture() {
    if (!_isRunning) return;
    
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _isRunning = false;
    onStatusChanged?.call(false);
    
    print('⏹️ Periodic capture stopped');
  }

  /// Capture single image manually
  Future<String?> captureSingleImage() async {
    if (!_isInitialized) {
      throw Exception('Camera not initialized');
    }
    
    try {
      return await _captureAndSave();
    } catch (e) {
      print('❌ Error capturing single image: $e');
      onError?.call('Failed to capture image: $e');
      return null;
    }
  }

  /// Internal method to capture and save image
  Future<String?> _captureAndSave() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        throw Exception('Camera controller not ready');
      }
      
      // Capture image
      final XFile imageFile = await _controller!.takePicture();
      
      // Get app directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'attendance_$timestamp.jpg';
      final String savedPath = path.join(appDir.path, 'attendance_images', fileName);
      
      // Ensure directory exists
      final Directory imageDir = Directory(path.dirname(savedPath));
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }
      
      // Copy image to permanent location
      final File permanentFile = await File(imageFile.path).copy(savedPath);
      
      // Delete temporary file
      await File(imageFile.path).delete();
      
      print('📷 Image captured and saved: $savedPath');
      
      // Notify callback
      onImageCaptured?.call(savedPath);
      
      return savedPath;
      
    } catch (e) {
      print('❌ Error in _captureAndSave: $e');
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
      );
      
      await _controller!.dispose();
      
      _controller = CameraController(
        newCamera,
        ResolutionPreset.medium,
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

  /// Get capture statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isRunning': _isRunning,
      'captureInterval': captureInterval.inMinutes,
      'currentCamera': _controller?.description.lensDirection.toString(),
      'availableCameras': _cameras.length,
    };
  }

  /// Clean up resources
  Future<void> dispose() async {
    try {
      print('🧹 Disposing periodic camera service...');
      
      stopPeriodicCapture();
      
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }
      
      _isInitialized = false;
      print('✅ Periodic camera service disposed');
      
    } catch (e) {
      print('❌ Error disposing camera service: $e');
    }
  }
}

// Configuration class for attendance session
class AttendanceSessionConfig {
  final String sessionId;
  final String classId;
  final Duration sessionDuration;
  final Duration captureInterval;
  final bool autoStart;
  final bool autoEnd;

  const AttendanceSessionConfig({
    required this.sessionId,
    required this.classId,
    this.sessionDuration = const Duration(hours: 2),
    this.captureInterval = const Duration(minutes: 5),
    this.autoStart = true,
    this.autoEnd = true,
  });
}