// lib/data/services/unified_camera_service.dart
// รวม PeriodicCameraService และ EnhancedPeriodicCameraService เป็นตัวเดียว

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

enum CameraState { 
  notInitialized, 
  initializing, 
  ready, 
  capturing, 
  error 
}

class UnifiedCameraService {
  CameraController? _controller;
  Timer? _periodicTimer;
  
  CameraState _state = CameraState.notInitialized;
  bool _isCapturing = false;
  int _captureCount = 0;
  String? _currentSessionId;
  
  // Available cameras
  List<CameraDescription> _availableCameras = [];
  
  // Callbacks
  Function(String imagePath, DateTime captureTime)? onImageCaptured;
  Function(String error)? onError;
  Function(CameraState state)? onStateChanged;
  Function(Map<String, dynamic> stats)? onStatsUpdated;

  // Getters
  CameraState get state => _state;
  bool get isReady => _state == CameraState.ready;
  bool get isCapturing => _isCapturing;
  int get captureCount => _captureCount;
  String? get currentSessionId => _currentSessionId;
  CameraController? get controller => _controller;

  // ==================== Initialization ====================

  Future<bool> initialize() async {
    try {
      _setState(CameraState.initializing);
      print('🔄 Initializing unified camera service...');
      
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        throw Exception('No cameras available on this device');
      }

      // Prefer front camera, fallback to any available camera
      final frontCamera = _availableCameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _availableCameras.first,
      );

      await _initializeController(frontCamera);
      
      _setState(CameraState.ready);
      print('✅ Unified camera service initialized successfully');
      print('📷 Using camera: ${frontCamera.name} (${frontCamera.lensDirection})');
      
      return true;
    } catch (e) {
      print('❌ Error initializing camera: $e');
      _setState(CameraState.error);
      _notifyError('Camera initialization failed: $e');
      return false;
    }
  }

  Future<void> _initializeController(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    
    if (!_controller!.value.isInitialized) {
      throw Exception('Camera controller failed to initialize');
    }
  }

  // ==================== Single Image Capture ====================

  Future<String?> captureImage() async {
    if (!isReady) {
      throw Exception('Camera not ready. Please initialize first.');
    }

    try {
      _setState(CameraState.capturing);
      print('📸 Capturing single image...');
      
      final imagePath = await _captureAndSave();
      
      if (imagePath != null) {
        _captureCount++;
        final captureTime = DateTime.now();
        
        // Notify callbacks
        _notifyImageCaptured(imagePath, captureTime);
        _updateStats();
      }
      
      _setState(CameraState.ready);
      return imagePath;
      
    } catch (e) {
      print('❌ Error capturing single image: $e');
      _setState(CameraState.error);
      _notifyError('Failed to capture image: $e');
      return null;
    }
  }

  // ==================== Periodic Capture ====================

  Future<void> startPeriodicCapture({
    required String sessionId,
    Duration interval = const Duration(minutes: 5),
    required Function(String imagePath, DateTime captureTime) onCapture,
  }) async {
    if (!isReady) {
      throw Exception('Camera not ready. Please initialize first.');
    }

    if (_isCapturing) {
      print('⚠️ Periodic capture already running for session: $_currentSessionId');
      return;
    }

    try {
      _isCapturing = true;
      _currentSessionId = sessionId;
      _captureCount = 0;
      
      print('🔄 Starting periodic capture every ${interval.inMinutes} minutes for session: $sessionId');

      // Start periodic timer
      _periodicTimer = Timer.periodic(interval, (timer) async {
        if (!_isCapturing || !isReady) {
          timer.cancel();
          return;
        }

        try {
          _setState(CameraState.capturing);
          
          final imagePath = await _captureAndSave();
          if (imagePath != null) {
            _captureCount++;
            final captureTime = DateTime.now();
            
            // Notify that image was captured
            _notifyImageCaptured(imagePath, captureTime);
            onCapture(imagePath, captureTime);
            
            // Update stats
            _updateStats();
          }
          
          _setState(CameraState.ready);
          
        } catch (e) {
          print('❌ Error in periodic capture: $e');
          _setState(CameraState.error);
          _notifyError('Periodic capture error: $e');
        }
      });

      print('🎯 Periodic capture started successfully');
      
    } catch (e) {
      print('❌ Error starting periodic capture: $e');
      _notifyError('Failed to start periodic capture: $e');
      _isCapturing = false;
      _currentSessionId = null;
    }
  }

  void stopPeriodicCapture() {
    if (!_isCapturing) {
      print('⚠️ No periodic capture is running');
      return;
    }

    _periodicTimer?.cancel();
    _periodicTimer = null;
    _isCapturing = false;
    
    print('⏹️ Periodic capture stopped for session: $_currentSessionId');
    _currentSessionId = null;
    
    _setState(CameraState.ready);
  }

  // ==================== Internal Methods ====================

  Future<String?> _captureAndSave() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        throw Exception('Camera controller not ready');
      }
      
      // Take picture
      final XFile imageFile = await _controller!.takePicture();
      
      // Save to permanent location
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'capture_${timestamp}.jpg';
      final String savedPath = path.join(appDir.path, 'captures', fileName);
      
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
        print('⚠️ Warning: Could not delete temporary file: $e');
      }

      print('📷 Image captured and saved: ${path.basename(savedPath)}');
      return savedPath;
      
    } catch (e) {
      print('❌ Error in _captureAndSave: $e');
      throw Exception('Failed to capture and save image: $e');
    }
  }

  // ==================== Camera Controls ====================

  Future<bool> switchCamera() async {
    if (!isReady || _availableCameras.length < 2) {
      print('⚠️ Cannot switch camera: ${_availableCameras.length} cameras available');
      return false;
    }
    
    try {
      _setState(CameraState.initializing);
      
      final currentCamera = _controller!.description;
      final newCamera = _availableCameras.firstWhere(
        (camera) => camera.lensDirection != currentCamera.lensDirection,
        orElse: () => _availableCameras.firstWhere(
          (camera) => camera != currentCamera,
        ),
      );
      
      // Dispose current controller
      await _controller!.dispose();
      
      // Initialize new controller
      await _initializeController(newCamera);
      
      _setState(CameraState.ready);
      print('🔄 Camera switched to: ${newCamera.name} (${newCamera.lensDirection})');
      
      return true;
      
    } catch (e) {
      print('❌ Error switching camera: $e');
      _setState(CameraState.error);
      _notifyError('Failed to switch camera: $e');
      return false;
    }
  }

  Future<void> setFlashMode(FlashMode flashMode) async {
    if (!isReady) return;
    
    try {
      await _controller!.setFlashMode(flashMode);
      print('💡 Flash mode set to: $flashMode');
    } catch (e) {
      print('❌ Error setting flash mode: $e');
    }
  }

  Future<void> setZoomLevel(double zoomLevel) async {
    if (!isReady) return;
    
    try {
      final maxZoom = await _controller!.getMaxZoomLevel();
      final minZoom = await _controller!.getMinZoomLevel();
      final clampedZoom = zoomLevel.clamp(minZoom, maxZoom);
      
      await _controller!.setZoomLevel(clampedZoom);
      print('🔍 Zoom level set to: $clampedZoom');
    } catch (e) {
      print('❌ Error setting zoom level: $e');
    }
  }

  // ==================== State Management ====================

  void _setState(CameraState newState) {
    if (_state != newState) {
      _state = newState;
      print('🔄 Camera state changed: $newState');
      onStateChanged?.call(newState);
    }
  }

  void _notifyImageCaptured(String imagePath, DateTime captureTime) {
    onImageCaptured?.call(imagePath, captureTime);
  }

  void _notifyError(String error) {
    onError?.call(error);
  }

  void _updateStats() {
    final stats = {
      'total_captures': _captureCount,
      'session_id': _currentSessionId,
      'is_capturing': _isCapturing,
      'state': _state.toString(),
      'last_capture_time': DateTime.now().toIso8601String(),
      'available_cameras': _availableCameras.length,
      'current_camera': _controller?.description.name,
    };
    
    onStatsUpdated?.call(stats);
  }

  // ==================== Information & Utilities ====================

  Map<String, dynamic> getServiceInfo() {
    return {
      'state': _state.toString(),
      'is_ready': isReady,
      'is_capturing': _isCapturing,
      'capture_count': _captureCount,
      'session_id': _currentSessionId,
      'available_cameras': _availableCameras.map((c) => {
        'name': c.name,
        'lens_direction': c.lensDirection.toString(),
        'sensor_orientation': c.sensorOrientation,
      }).toList(),
      'current_camera': _controller?.description.name,
      'resolution': _controller?.resolutionPreset.toString(),
      'has_flash': _availableCameras.isNotEmpty ? _availableCameras.first.lensDirection != null : false,
    };
  }

  bool isHealthy() {
    return _state != CameraState.error && 
           _controller != null && 
           _controller!.value.isInitialized &&
           !_controller!.value.hasError;
  }

  List<String> getAvailableCameraNames() {
    return _availableCameras.map((camera) => camera.name).toList();
  }

  Future<List<double>> getZoomLevels() async {
    if (!isReady) return [1.0];
    
    try {
      final minZoom = await _controller!.getMinZoomLevel();
      final maxZoom = await _controller!.getMaxZoomLevel();
      
      return [minZoom, 1.0, maxZoom];
    } catch (e) {
      print('❌ Error getting zoom levels: $e');
      return [1.0];
    }
  }

  // ==================== Batch Operations ====================

  Future<List<String>> captureMultipleImages({
    required int count,
    Duration interval = const Duration(seconds: 2),
    Function(int current, int total)? onProgress,
  }) async {
    if (!isReady) {
      throw Exception('Camera not ready');
    }

    final List<String> imagePaths = [];
    
    try {
      print('📸 Capturing $count images with ${interval.inSeconds}s intervals...');
      
      for (int i = 0; i < count; i++) {
        onProgress?.call(i + 1, count);
        
        final imagePath = await captureImage();
        if (imagePath != null) {
          imagePaths.add(imagePath);
          print('✅ Captured image ${i + 1}/$count');
        } else {
          print('❌ Failed to capture image ${i + 1}/$count');
        }
        
        // Wait before next capture (except for last image)
        if (i < count - 1) {
          await Future.delayed(interval);
        }
      }
      
      print('📸 Batch capture completed: ${imagePaths.length}/$count images captured');
      return imagePaths;
      
    } catch (e) {
      print('❌ Error in batch capture: $e');
      return imagePaths; // Return what we got so far
    }
  }

  // ==================== Cleanup & Maintenance ====================

  Future<void> cleanupOldImages({int maxAgeHours = 24}) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory captureDir = Directory(path.join(appDir.path, 'captures'));
      
      if (!await captureDir.exists()) {
        print('📁 Capture directory does not exist');
        return;
      }
      
      final cutoffTime = DateTime.now().subtract(Duration(hours: maxAgeHours));
      final files = captureDir.listSync();
      
      int deletedCount = 0;
      int totalSize = 0;
      
      for (final file in files) {
        if (file is File) {
          try {
            final fileStat = await file.stat();
            totalSize += fileStat.size;
            
            if (fileStat.modified.isBefore(cutoffTime)) {
              await file.delete();
              deletedCount++;
              print('🗑️ Deleted old image: ${path.basename(file.path)}');
            }
          } catch (e) {
            print('⚠️ Failed to delete old image: ${file.path} - $e');
          }
        }
      }
      
      final remainingFiles = files.length - deletedCount;
      print('🧹 Cleanup completed:');
      print('   Deleted: $deletedCount files');
      print('   Remaining: $remainingFiles files');
      print('   Total size processed: ${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
    } catch (e) {
      print('❌ Error during image cleanup: $e');
    }
  }

  Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory captureDir = Directory(path.join(appDir.path, 'captures'));
      
      if (!await captureDir.exists()) {
        return {
          'directory_exists': false,
          'file_count': 0,
          'total_size_mb': 0.0,
        };
      }
      
      final files = captureDir.listSync();
      int totalSize = 0;
      
      for (final file in files) {
        if (file is File) {
          final fileStat = await file.stat();
          totalSize += fileStat.size;
        }
      }
      
      return {
        'directory_exists': true,
        'directory_path': captureDir.path,
        'file_count': files.length,
        'total_size_mb': (totalSize / 1024 / 1024),
        'files': files.map((f) => path.basename(f.path)).toList(),
      };
      
    } catch (e) {
      print('❌ Error getting storage info: $e');
      return {'error': e.toString()};
    }
  }

  Future<void> reset() async {
    try {
      print('🔄 Resetting camera service...');
      
      stopPeriodicCapture();
      _captureCount = 0;
      _currentSessionId = null;
      
      if (isReady) {
        _setState(CameraState.ready);
      }
      
      print('✅ Camera service reset completed');
    } catch (e) {
      print('❌ Error resetting camera service: $e');
    }
  }

  // ==================== Advanced Features ====================

  Future<void> enableTorch(bool enable) async {
    if (!isReady) return;
    
    try {
      await _controller!.setFlashMode(enable ? FlashMode.torch : FlashMode.off);
      print('🔦 Torch ${enable ? "enabled" : "disabled"}');
    } catch (e) {
      print('❌ Error controlling torch: $e');
    }
  }

  Future<bool> hasFlash() async {
    if (!isReady) return false;
    
    try {
      // Try to set flash mode to test if flash is available
      await _controller!.setFlashMode(FlashMode.off);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> lockExposure() async {
    if (!isReady) return;
    
    try {
      await _controller!.setExposureMode(ExposureMode.locked);
      print('📸 Exposure locked');
    } catch (e) {
      print('❌ Error locking exposure: $e');
    }
  }

  Future<void> unlockExposure() async {
    if (!isReady) return;
    
    try {
      await _controller!.setExposureMode(ExposureMode.auto);
      print('📸 Exposure unlocked');
    } catch (e) {
      print('❌ Error unlocking exposure: $e');
    }
  }

  // ==================== Cleanup ====================

  Future<void> dispose() async {
    try {
      print('🧹 Disposing unified camera service...');
      
      stopPeriodicCapture();
      
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }
      
      _setState(CameraState.notInitialized);
      _availableCameras.clear();
      
      // Clear callbacks
      onImageCaptured = null;
      onError = null;
      onStateChanged = null;
      onStatsUpdated = null;
      
      print('✅ Unified camera service disposed successfully');
    } catch (e) {
      print('❌ Error disposing camera service: $e');
    }
  }
}