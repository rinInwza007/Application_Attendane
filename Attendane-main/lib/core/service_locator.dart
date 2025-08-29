// lib/core/service_locator.dart
// อัปเดตให้ใช้กับ Unified Service Architecture

import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/unified_attendance_service.dart';
import 'package:myproject2/data/services/unified_camera_service.dart';
import 'package:myproject2/data/services/unified_face_service.dart';
import 'package:myproject2/core/constants/app_constants.dart';

final GetIt serviceLocator = GetIt.instance;

/// Initialize all services and dependencies using Unified Architecture
Future<void> setupServiceLocator() async {
  try {
    print('🔧 Setting up service locator with unified services...');
    
    // Method 1: Use ServiceManager (Recommended)
    await _setupWithServiceManager();
    
    // Method 2: Direct registration (Alternative)
    // await _setupDirectRegistration();
    
    // Register additional utility services
    await _registerExternalDependencies();
    _registerUtilityServices();
    
    // Verify all services are registered
    _verifyServiceRegistration();
    
    print('✅ Service locator setup completed with unified architecture');
  } catch (e) {
    print('❌ Service locator setup failed: $e');
    rethrow;
  }
}

/// Setup using ServiceManager (Recommended approach)
Future<void> _setupWithServiceManager() async {
  // Initialize the global services instance
  await services.initialize();
  
  // Register ServiceManager instance
  serviceLocator.registerSingleton<ServiceManager>(services);
  
  // Register individual services through ServiceManager
  serviceLocator.registerLazySingleton<AuthService>(() => services.auth);
  serviceLocator.registerLazySingleton<UnifiedAttendanceService>(() => services.attendance);
  serviceLocator.registerLazySingleton<UnifiedCameraService>(() => services.camera);
  serviceLocator.registerLazySingleton<UnifiedFaceService>(() => services.face);
}

/// Alternative: Direct registration of unified services
Future<void> _setupDirectRegistration() async {
  // Register Auth Service
  serviceLocator.registerLazySingleton<AuthService>(() => AuthService());
  
  // Register Unified Services
  serviceLocator.registerLazySingleton<UnifiedAttendanceService>(
    () => UnifiedAttendanceService(),
  );
  
  serviceLocator.registerLazySingleton<UnifiedCameraService>(
    () => UnifiedCameraService(),
  );
  
  serviceLocator.registerLazySingleton<UnifiedFaceService>(
    () => UnifiedFaceService(),
  );
  
  // Initialize face service
  final faceService = serviceLocator<UnifiedFaceService>();
  await faceService.initialize();
}

/// Register external dependencies that need async initialization
Future<void> _registerExternalDependencies() async {
  // SharedPreferences
  final sharedPreferences = await SharedPreferences.getInstance();
  serviceLocator.registerSingleton<SharedPreferences>(sharedPreferences);
  
  // Add other external dependencies here
  // e.g., Firebase, Analytics, Crash Reporting, etc.
}

/// Register utility services (enhanced for unified architecture)
void _registerUtilityServices() {
  // Navigation Service
  serviceLocator.registerLazySingleton<NavigationService>(
    () => NavigationService(),
  );
  
  // Storage Service
  serviceLocator.registerLazySingleton<StorageService>(
    () => StorageService(serviceLocator<SharedPreferences>()),
  );
  
  // Notification Service
  serviceLocator.registerLazySingleton<NotificationService>(
    () => NotificationService(),
  );
  
  // Logger Service
  serviceLocator.registerLazySingleton<LoggerService>(
    () => LoggerService(),
  );
  
  // Validation Service
  serviceLocator.registerLazySingleton<ValidationService>(
    () => ValidationService(),
  );
  
  // File Service
  serviceLocator.registerLazySingleton<FileService>(
    () => FileService(),
  );
  
  // Network Service
  serviceLocator.registerLazySingleton<NetworkService>(
    () => NetworkService(),
  );
  
  // Permission Service
  serviceLocator.registerLazySingleton<PermissionService>(
    () => PermissionService(),
  );
  
  // Conditional services
  if (AppConstants.enableAnalytics) {
    serviceLocator.registerLazySingleton<AnalyticsService>(
      () => AnalyticsService(),
    );
  }
  
  if (AppConstants.enableCrashReporting) {
    serviceLocator.registerLazySingleton<CrashReportingService>(
      () => CrashReportingService(),
    );
  }
}

/// Verify that all critical services are properly registered
void _verifyServiceRegistration() {
  final criticalServices = [
    AuthService,
    UnifiedAttendanceService,
    UnifiedCameraService,
    UnifiedFaceService,
    NavigationService,
    StorageService,
    LoggerService,
  ];
  
  for (final serviceType in criticalServices) {
    if (!serviceLocator.isRegistered(instance: serviceType)) {
      throw ServiceLocatorException('Critical service $serviceType is not registered');
    }
  }
  
  // Verify ServiceManager if using that approach
  if (serviceLocator.isRegistered<ServiceManager>()) {
    final serviceManager = serviceLocator<ServiceManager>();
    if (!serviceManager.isReady) {
      throw ServiceLocatorException('ServiceManager is not ready');
    }
  }
  
  print('✅ All critical unified services verified');
}

/// Clean up all services (call this when app is terminated)
Future<void> disposeServiceLocator() async {
  try {
    print('🧹 Disposing service locator...');
    
    // Dispose unified services properly
    await _disposeUnifiedServices();
    
    // Dispose utility services
    await _disposeUtilityServices();
    
    // Reset GetIt instance
    await serviceLocator.reset();
    
    print('✅ Service locator disposed');
  } catch (e) {
    print('❌ Error disposing service locator: $e');
  }
}

/// Dispose unified services properly
Future<void> _disposeUnifiedServices() async {
  try {
    // If using ServiceManager, dispose it
    if (serviceLocator.isRegistered<ServiceManager>()) {
      final serviceManager = serviceLocator<ServiceManager>();
      await serviceManager.dispose();
    } else {
      // Dispose individual services
      if (serviceLocator.isRegistered<UnifiedFaceService>()) {
        final faceService = serviceLocator<UnifiedFaceService>();
        await faceService.dispose();
      }
      
      if (serviceLocator.isRegistered<UnifiedCameraService>()) {
        final cameraService = serviceLocator<UnifiedCameraService>();
        await cameraService.dispose();
      }
      
      if (serviceLocator.isRegistered<UnifiedAttendanceService>()) {
        final attendanceService = serviceLocator<UnifiedAttendanceService>();
        attendanceService.dispose();
      }
    }
    
  } catch (e) {
    print('⚠️ Error disposing unified services: $e');
  }
}

/// Dispose utility services
Future<void> _disposeUtilityServices() async {
  try {
    if (serviceLocator.isRegistered<NetworkService>()) {
      final networkService = serviceLocator<NetworkService>();
      networkService.dispose();
    }
    
    if (serviceLocator.isRegistered<NotificationService>()) {
      final notificationService = serviceLocator<NotificationService>();
      notificationService.dispose();
    }
    
    if (serviceLocator.isRegistered<FileService>()) {
      final fileService = serviceLocator<FileService>();
      fileService.dispose();
    }
    
  } catch (e) {
    print('⚠️ Error disposing utility services: $e');
  }
}

// ==================== Enhanced Service Health Check ====================

/// Comprehensive health check for all services
Future<Map<String, bool>> checkAllServicesHealth() async {
  final healthResults = <String, bool>{};
  
  try {
    // Check ServiceManager health (if using it)
    if (serviceLocator.isRegistered<ServiceManager>()) {
      final serviceManager = serviceLocator<ServiceManager>();
      final unifiedHealth = await serviceManager.healthCheck();
      healthResults.addAll(unifiedHealth);
    } else {
      // Check individual unified services
      healthResults['auth'] = serviceLocator.isRegistered<AuthService>();
      healthResults['attendance'] = serviceLocator.isRegistered<UnifiedAttendanceService>();
      healthResults['camera'] = serviceLocator.isRegistered<UnifiedCameraService>() && 
                               serviceLocator<UnifiedCameraService>().isHealthy();
      healthResults['face'] = serviceLocator.isRegistered<UnifiedFaceService>() && 
                             serviceLocator<UnifiedFaceService>().isInitialized;
    }
    
    // Check utility services
    healthResults['storage'] = serviceLocator.isRegistered<StorageService>();
    healthResults['logger'] = serviceLocator.isRegistered<LoggerService>();
    healthResults['validation'] = serviceLocator.isRegistered<ValidationService>();
    
  } catch (e) {
    print('❌ Error in health check: $e');
    healthResults['health_check_error'] = false;
  }
  
  return healthResults;
}

/// Restart services if needed
Future<bool> restartUnhealthyServices() async {
  try {
    final health = await checkAllServicesHealth();
    final unhealthyServices = health.entries.where((e) => !e.value).map((e) => e.key).toList();
    
    if (unhealthyServices.isNotEmpty) {
      print('🔧 Restarting unhealthy services: ${unhealthyServices.join(", ")}');
      
      // If using ServiceManager, use its restart functionality
      if (serviceLocator.isRegistered<ServiceManager>()) {
        final serviceManager = serviceLocator<ServiceManager>();
        
        for (final serviceName in unhealthyServices) {
          await serviceManager.restartService(serviceName);
        }
      }
      
      return true;
    }
    
    return false;
  } catch (e) {
    print('❌ Error restarting services: $e');
    return false;
  }
}

// ==================== Service Implementations (Updated) ====================

class NavigationService {
  void dispose() {
    // TODO: Implement navigation cleanup if needed
  }
}

class StorageService {
  final SharedPreferences _prefs;
  
  StorageService(this._prefs);
  
  // User Preferences
  Future<void> setUserEmail(String email) async {
    await _prefs.setString(AppConstants.userEmailKey, email);
  }
  
  String? getUserEmail() {
    return _prefs.getString(AppConstants.userEmailKey);
  }
  
  Future<void> setUserId(String userId) async {
    await _prefs.setString(AppConstants.userIdKey, userId);
  }
  
  String? getUserId() {
    return _prefs.getString(AppConstants.userIdKey);
  }
  
  Future<void> setUserType(String userType) async {
    await _prefs.setString(AppConstants.userTypeKey, userType);
  }
  
  String? getUserType() {
    return _prefs.getString(AppConstants.userTypeKey);
  }
  
  Future<void> setAuthToken(String token) async {
    await _prefs.setString(AppConstants.tokenKey, token);
  }
  
  String? getAuthToken() {
    return _prefs.getString(AppConstants.tokenKey);
  }
  
  // Enhanced: Service-specific settings
  Future<void> setCameraResolution(String resolution) async {
    await _prefs.setString('camera_resolution', resolution);
  }
  
  String getCameraResolution() {
    return _prefs.getString('camera_resolution') ?? 'high';
  }
  
  Future<void> setFaceThreshold(double threshold) async {
    await _prefs.setDouble('face_threshold', threshold);
  }
  
  double getFaceThreshold() {
    return _prefs.getDouble('face_threshold') ?? 0.7;
  }
  
  Future<void> setPeriodicCaptureInterval(int minutes) async {
    await _prefs.setInt('periodic_capture_interval', minutes);
  }
  
  int getPeriodicCaptureInterval() {
    return _prefs.getInt('periodic_capture_interval') ?? 5;
  }
  
  // App Settings
  Future<void> setThemeMode(String theme) async {
    await _prefs.setString(AppConstants.themeKey, theme);
  }
  
  String getThemeMode() {
    return _prefs.getString(AppConstants.themeKey) ?? 'system';
  }
  
  Future<void> setLanguage(String language) async {
    await _prefs.setString(AppConstants.languageKey, language);
  }
  
  String getLanguage() {
    return _prefs.getString(AppConstants.languageKey) ?? 'en';
  }
  
  // Clear all data
  Future<void> clearAll() async {
    await _prefs.clear();
  }
  
  // Clear user data only
  Future<void> clearUserData() async {
    final keys = [
      AppConstants.tokenKey,
      AppConstants.userIdKey,
      AppConstants.userEmailKey,
      AppConstants.userTypeKey,
    ];
    
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
  
  void dispose() {
    // SharedPreferences doesn't need manual disposal
  }
}

class NotificationService {
  void dispose() {
    // TODO: Implement push notification cleanup
  }
  
  Future<void> initialize() async {
    // TODO: Initialize push notifications
  }
  
  Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    // TODO: Show local notification
  }
  
  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    // TODO: Schedule notification
  }
  
  // Enhanced: Attendance-specific notifications
  Future<void> notifySessionStarted(String className) async {
    await showLocalNotification(
      title: 'Attendance Session Started',
      body: 'Session for $className has started',
    );
  }
  
  Future<void> notifyCheckInSuccess(String className) async {
    await showLocalNotification(
      title: 'Check-in Successful',
      body: 'You have been marked present for $className',
    );
  }
  
  Future<void> notifySessionEnding(String className, int minutesLeft) async {
    await showLocalNotification(
      title: 'Session Ending Soon',
      body: '$className session will end in $minutesLeft minutes',
    );
  }
}

class AnalyticsService {
  void dispose() {
    // TODO: Implement analytics cleanup
  }
  
  void trackEvent(String eventName, {Map<String, dynamic>? parameters}) {
    if (AppConstants.enableAnalytics) {
      // TODO: Track analytics event
      print('📊 Analytics: $eventName ${parameters ?? ''}');
    }
  }
  
  void setUserId(String userId) {
    if (AppConstants.enableAnalytics) {
      // TODO: Set analytics user ID
      print('📊 Analytics: Set user ID $userId');
    }
  }
  
  void setUserProperty(String name, String value) {
    if (AppConstants.enableAnalytics) {
      // TODO: Set analytics user property
      print('📊 Analytics: Set user property $name = $value');
    }
  }
  
  // Enhanced: Attendance-specific analytics
  void trackSessionCreated(String classId, int duration) {
    trackEvent('session_created', {
      'class_id': classId,
      'duration_hours': duration,
    });
  }
  
  void trackCheckIn(String method, bool success) {
    trackEvent('check_in_attempt', {
      'method': method, // 'simple' or 'face'
      'success': success,
    });
  }
  
  void trackFaceEnrollment(bool success) {
    trackEvent('face_enrollment', {
      'success': success,
    });
  }
  
  void trackPeriodicCapture(int facesDetected) {
    trackEvent('periodic_capture', {
      'faces_detected': facesDetected,
    });
  }
}

class CrashReportingService {
  void logError(String message, dynamic error, StackTrace? stackTrace) {
    if (AppConstants.enableCrashReporting) {
      // TODO: Send to crash reporting service
      print('💥 Crash Report: $message');
      if (error != null) print('Error: $error');
      if (stackTrace != null) print('StackTrace: $stackTrace');
    }
  }
  
  void setUserId(String userId) {
    if (AppConstants.enableCrashReporting) {
      // TODO: Set crash reporting user ID
      print('💥 Crash Report: Set user ID $userId');
    }
  }
  
  void setCustomKey(String key, String value) {
    if (AppConstants.enableCrashReporting) {
      // TODO: Set custom key for crash reporting
      print('💥 Crash Report: Set custom key $key = $value');
    }
  }
}

class LoggerService {
  void logInfo(String message, {Map<String, dynamic>? extra}) {
    if (AppConstants.enableDebugLogging) {
      print('ℹ️ INFO: $message');
      if (extra != null) print('Extra: $extra');
    }
  }
  
  void logWarning(String message, {Map<String, dynamic>? extra}) {
    if (AppConstants.enableDebugLogging) {
      print('⚠️ WARNING: $message');
      if (extra != null) print('Extra: $extra');
    }
  }
  
  void logError(String message, {dynamic error, StackTrace? stackTrace, Map<String, dynamic>? extra}) {
    if (AppConstants.enableDebugLogging) {
      print('❌ ERROR: $message');
      if (error != null) print('Error details: $error');
      if (stackTrace != null) print('Stack trace: $stackTrace');
      if (extra != null) print('Extra: $extra');
    }
    
    // Send to crash reporting in production
    if (AppConstants.enableCrashReporting && serviceLocator.isRegistered<CrashReportingService>()) {
      serviceLocator<CrashReportingService>().logError(message, error, stackTrace);
    }
  }
  
  void logDebug(String message, {Map<String, dynamic>? extra}) {
    if (AppConstants.enableDebugLogging && AppConstants.isDevelopment) {
      print('🐛 DEBUG: $message');
      if (extra != null) print('Extra: $extra');
    }
  }
  
  // Enhanced: Service-specific logging
  void logServiceEvent(String service, String event, {Map<String, dynamic>? data}) {
    logInfo('$service: $event', extra: data);
  }
  
  void logPerformance(String operation, Duration duration) {
    logDebug('Performance: $operation took ${duration.inMilliseconds}ms');
  }
  
  void dispose() {
    // Logger doesn't need manual disposal
  }
}

class ValidationService {
  bool isValidEmail(String email) {
    return AppConstants.isValidEmail(email);
  }
  
  bool isValidPassword(String password) {
    return AppConstants.isValidPassword(password);
  }
  
  bool isValidClassId(String classId) {
    return AppConstants.isValidClassId(classId);
  }
  
  bool isValidSchoolId(String schoolId) {
    return AppConstants.isValidSchoolId(schoolId);
  }
  
  bool isValidInviteCode(String inviteCode) {
    return AppConstants.isValidInviteCode(inviteCode);
  }
  
  String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }
  
  String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    if (!isValidEmail(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }
  
  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (!isValidPassword(value)) {
      return 'Password must be at least 6 characters long';
    }
    return null;
  }
  
  String? validateConfirmPassword(String? value, String? originalPassword) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != originalPassword) {
      return 'Passwords do not match';
    }
    return null;
  }
  
  String? validateClassId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Class ID is required';
    }
    if (!isValidClassId(value.trim())) {
      return 'Invalid class ID format';
    }
    return null;
  }
  
  String? validateSchoolId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'School ID is required';
    }
    if (!isValidSchoolId(value.trim())) {
      return 'Invalid school ID format';
    }
    return null;
  }
  
  // Enhanced: Service-specific validations
  String? validateSessionDuration(int? hours) {
    if (hours == null || hours < 1 || hours > 8) {
      return 'Session duration must be between 1 and 8 hours';
    }
    return null;
  }
  
  String? validateCaptureInterval(int? minutes) {
    if (minutes == null || minutes < 1 || minutes > 30) {
      return 'Capture interval must be between 1 and 30 minutes';
    }
    return null;
  }
  
  String? validateFaceThreshold(double? threshold) {
    if (threshold == null || threshold < 0.1 || threshold > 1.0) {
      return 'Face threshold must be between 0.1 and 1.0';
    }
    return null;
  }
  
  void dispose() {
    // Validation service doesn't need disposal
  }
}

class FileService {
  void dispose() {
    // TODO: Cleanup file operations if needed
  }
  
  Future<String> getTemporaryDirectoryPath() async {
    // TODO: Implement using path_provider
    throw UnimplementedError('getTemporaryDirectoryPath not implemented');
  }
  
  Future<String> getApplicationDocumentsDirectoryPath() async {
    // TODO: Implement using path_provider
    throw UnimplementedError('getApplicationDocumentsDirectoryPath not implemented');
  }
  
  Future<bool> deleteFile(String filePath) async {
    // TODO: Implement file deletion
    throw UnimplementedError('deleteFile not implemented');
  }
  
  Future<bool> fileExists(String filePath) async {
    // TODO: Implement file existence check
    throw UnimplementedError('fileExists not implemented');
  }
  
  // Enhanced: Image and attendance file management
  Future<List<String>> getOldCaptureFiles(int maxAgeHours) async {
    // TODO: Get old capture files for cleanup
    throw UnimplementedError('getOldCaptureFiles not implemented');
  }
  
  Future<void> cleanupCaptureFiles(int maxAgeHours) async {
    // TODO: Cleanup old capture files
    throw UnimplementedError('cleanupCaptureFiles not implemented');
  }
}

class NetworkService {
  void dispose() {
    // TODO: Cleanup network connections if needed
  }
  
  Future<bool> hasInternetConnection() async {
    // TODO: Implement internet connectivity check
    throw UnimplementedError('hasInternetConnection not implemented');
  }
  
  Stream<bool> get connectivityStream {
    // TODO: Implement connectivity stream
    throw UnimplementedError('connectivityStream not implemented');
  }
  
  // Enhanced: API server connectivity
  Future<bool> canReachAttendanceServer() async {
    // TODO: Check if attendance API server is reachable
    throw UnimplementedError('canReachAttendanceServer not implemented');
  }
}

class PermissionService {
  void dispose() {
    // Permission service doesn't need disposal
  }
  
  Future<bool> requestCameraPermission() async {
    // TODO: Implement camera permission request
    throw UnimplementedError('requestCameraPermission not implemented');
  }
  
  Future<bool> requestStoragePermission() async {
    // TODO: Implement storage permission request
    throw UnimplementedError('requestStoragePermission not implemented');
  }
  
  Future<bool> requestNotificationPermission() async {
    // TODO: Implement notification permission request
    throw UnimplementedError('requestNotificationPermission not implemented');
  }
  
  Future<bool> hasPermission(String permission) async {
    // TODO: Implement permission check
    throw UnimplementedError('hasPermission not implemented');
  }
  
  // Enhanced: Attendance-specific permissions
  Future<bool> requestAllAttendancePermissions() async {
    final cameraGranted = await requestCameraPermission();
    final storageGranted = await requestStoragePermission();
    final notificationGranted = await requestNotificationPermission();
    
    return cameraGranted && storageGranted && notificationGranted;
  }
}

// ==================== Helper Extensions ====================

extension ServiceLocatorExtensions on GetIt {
  /// Check if a service is registered without throwing an exception
  bool isRegistered<T extends Object>({Object? instance, String? instanceName}) {
    try {
      get<T>(instanceName: instanceName);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Get service safely (returns null if not registered)
  T? getSafe<T extends Object>({String? instanceName}) {
    try {
      return get<T>(instanceName: instanceName);
    } catch (e) {
      return null;
    }
  }
}

// ==================== Custom Exceptions ====================

class ServiceLocatorException implements Exception {
  final String message;
  
  ServiceLocatorException(this.message);
  
  @override
  String toString() => 'ServiceLocatorException: $message';
}

// ==================== Convenience Methods (Updated) ====================

/// Get auth service instance
AuthService get authService => serviceLocator<AuthService>();

/// Get unified attendance service instance
UnifiedAttendanceService get unifiedAttendanceService => serviceLocator<UnifiedAttendanceService>();

/// Get unified camera service instance
UnifiedCameraService get unifiedCameraService => serviceLocator<UnifiedCameraService>();

/// Get unified face service instance
UnifiedFaceService get unifiedFaceService => serviceLocator<UnifiedFaceService>();

/// Get service manager instance (if using ServiceManager approach)
ServiceManager get serviceManager => serviceLocator<ServiceManager>();

/// Get storage service instance
StorageService get storageService => serviceLocator<StorageService>();

/// Get logger service instance
LoggerService get loggerService => serviceLocator<LoggerService>();

/// Get validation service instance
ValidationService get validationService => serviceLocator<ValidationService>();

/// Get notification service instance
NotificationService get notificationService => serviceLocator<NotificationService>();

/// Get analytics service instance (if enabled)
AnalyticsService? get analyticsService => serviceLocator.getSafe<AnalyticsService>();

/// Get crash reporting service instance (if enabled)
CrashReportingService? get crashReportingService => serviceLocator.getSafe<CrashReportingService>();