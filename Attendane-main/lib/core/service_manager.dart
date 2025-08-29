// lib/core/service_manager.dart
// ServiceManager สำหรับจัดการ Unified Services

import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/unified_attendance_service.dart';
import 'package:myproject2/data/services/unified_camera_service.dart';
import 'package:myproject2/data/services/unified_face_service.dart';

class ServiceManager {
  static ServiceManager? _instance;
  static ServiceManager get instance => _instance ??= ServiceManager._();
  
  ServiceManager._();

  // Service instances
  late final AuthService _auth;
  late final UnifiedAttendanceService _attendance;
  late final UnifiedCameraService _camera;
  late final UnifiedFaceService _face;

  bool _isInitialized = false;
  bool _isReady = false;

  // Getters for services
  AuthService get auth => _auth;
  UnifiedAttendanceService get attendance => _attendance;
  UnifiedCameraService get camera => _camera;
  UnifiedFaceService get face => _face;

  // Status getters
  bool get isInitialized => _isInitialized;
  bool get isReady => _isReady;

  /// Initialize all unified services
  Future<void> initialize() async {
    if (_isInitialized) {
      print('✅ ServiceManager already initialized');
      return;
    }

    try {
      print('🔧 Initializing ServiceManager with unified services...');

      // Initialize services
      _auth = AuthService();
      _attendance = UnifiedAttendanceService();
      _camera = UnifiedCameraService();
      _face = UnifiedFaceService();

      // Initialize services that require async setup
      await _face.initialize();
      await _camera.initialize();

      _isInitialized = true;
      _isReady = true;

      print('✅ ServiceManager initialized successfully');
    } catch (e) {
      print('❌ ServiceManager initialization failed: $e');
      _isInitialized = false;
      _isReady = false;
      rethrow;
    }
  }

  /// Health check for all services
  Future<Map<String, bool>> healthCheck() async {
    final results = <String, bool>{};

    try {
      results['auth'] = true; // AuthService doesn't have health check
      results['attendance'] = await _attendance.testServerConnection();
      results['camera'] = _camera.isHealthy();
      results['face'] = _face.isInitialized;

      print('🏥 Health check completed: $results');
      return results;
    } catch (e) {
      print('❌ Health check error: $e');
      results['health_check_error'] = false;
      return results;
    }
  }

  /// Restart a specific service by name
  Future<void> restartService(String serviceName) async {
    try {
      print('🔄 Restarting service: $serviceName');

      switch (serviceName.toLowerCase()) {
        case 'camera':
          await _camera.dispose();
          await _camera.initialize();
          print('✅ Camera service restarted');
          break;
        
        case 'face':
          await _face.dispose();
          await _face.initialize();
          print('✅ Face service restarted');
          break;
        
        case 'attendance':
          // UnifiedAttendanceService doesn't need restart
          print('⚠️ Attendance service restart not needed');
          break;
        
        case 'auth':
          // AuthService doesn't need restart
          print('⚠️ Auth service restart not needed');
          break;
        
        default:
          print('⚠️ Unknown service: $serviceName');
      }
    } catch (e) {
      print('❌ Error restarting service $serviceName: $e');
      throw Exception('Failed to restart $serviceName: $e');
    }
  }

  /// Get service information
  Map<String, dynamic> getServiceInfo() {
    return {
      'is_initialized': _isInitialized,
      'is_ready': _isReady,
      'services': {
        'auth': true,
        'attendance': true,
        'camera': _camera.isHealthy(),
        'face': _face.isInitialized,
      },
      'service_details': {
        'camera': _camera.getServiceInfo(),
        'face': _face.getServiceInfo(),
      },
    };
  }

  /// Dispose all services
  Future<void> dispose() async {
    try {
      print('🧹 Disposing ServiceManager...');

      if (_isInitialized) {
        await _face.dispose();
        await _camera.dispose();
        _attendance.dispose();
        // AuthService doesn't need disposal
      }

      _isInitialized = false;
      _isReady = false;

      print('✅ ServiceManager disposed successfully');
    } catch (e) {
      print('❌ Error disposing ServiceManager: $e');
    }
  }
}

// Global instance สำหรับใช้งาน
final ServiceManager services = ServiceManager.instance;