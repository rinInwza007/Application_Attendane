// lib/core/service_locator.dart
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/attendance_service.dart'; // ไม่ต้อง hide แล้วเพราะไม่มี AuthService ซ้ำ
import 'package:myproject2/data/services/face_recognition_service.dart';
import 'package:myproject2/core/constants/app_constants.dart';

final GetIt serviceLocator = GetIt.instance;

/// Initialize all services and dependencies
Future<void> setupServiceLocator() async {
  try {
    print('🔧 Setting up service locator...');
    
    // Register external dependencies first
    await _registerExternalDependencies();
    
    // Register core services
    _registerCoreServices();
    
    // Register business services
    _registerBusinessServices();
    
    // Register utility services
    _registerUtilityServices();
    
    // Verify all services are registered
    _verifyServiceRegistration();
    
    print('✅ Service locator setup completed');
  } catch (e) {
    print('❌ Service locator setup failed: $e');
    rethrow;
  }
}

/// Register external dependencies that need async initialization
Future<void> _registerExternalDependencies() async {
  // SharedPreferences
  final sharedPreferences = await SharedPreferences.getInstance();
  serviceLocator.registerSingleton<SharedPreferences>(sharedPreferences);
  
  // Add other external dependencies here
  // e.g., Firebase, Analytics, Crash Reporting, etc.
}

/// Register core application services
void _registerCoreServices() {
  // Authentication Service (หลัก)
  serviceLocator.registerLazySingleton<AuthService>(
    () => AuthService(),
  );
  
  // Face Recognition Service (ML/AI)
  serviceLocator.registerLazySingleton<FaceRecognitionService>(
    () => FaceRecognitionService(),
  );
  
  // Simple Attendance Service (ใช้สำหรับฟีเจอร์พื้นฐาน)
  serviceLocator.registerLazySingleton<SimpleAttendanceService>(
    () => SimpleAttendanceService(),
  );
  
  // Full Attendance Service (ใช้สำหรับฟีเจอร์ขั้นสูง)
  serviceLocator.registerLazySingleton<AttendanceService>(
    () => AttendanceService(),
  );
}

/// Register business logic services
void _registerBusinessServices() {
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
  
  // Analytics Service (conditional)
  if (AppConstants.enableAnalytics) {
    serviceLocator.registerLazySingleton<AnalyticsService>(
      () => AnalyticsService(),
    );
  }
  
  // Crash Reporting Service (conditional)
  if (AppConstants.enableCrashReporting) {
    serviceLocator.registerLazySingleton<CrashReportingService>(
      () => CrashReportingService(),
    );
  }
}

/// Register utility services
void _registerUtilityServices() {
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
}

/// Verify that all critical services are properly registered
void _verifyServiceRegistration() {
  final criticalServices = [
    AuthService,
    FaceRecognitionService,
    SimpleAttendanceService,
    AttendanceService,
    NavigationService,
    StorageService,
    LoggerService,
  ];
  
  for (final serviceType in criticalServices) {
    if (!serviceLocator.isRegistered(instance: serviceType)) {
      throw ServiceLocatorException('Critical service $serviceType is not registered');
    }
  }
  
  print('✅ All critical services verified');
}

/// Clean up all services (call this when app is terminated)
Future<void> disposeServiceLocator() async {
  try {
    print('🧹 Disposing service locator...');
    
    // Manually dispose services that need cleanup
    await _disposeServicesManually();
    
    // Reset GetIt instance
    await serviceLocator.reset();
    
    print('✅ Service locator disposed');
  } catch (e) {
    print('❌ Error disposing service locator: $e');
  }
}

/// Manually dispose services that need cleanup
Future<void> _disposeServicesManually() async {
  try {
    // Dispose FaceRecognitionService
    if (serviceLocator.isRegistered<FaceRecognitionService>()) {
      final faceService = serviceLocator<FaceRecognitionService>();
      await faceService.dispose();
    }
    
    // Dispose other services as needed
    if (serviceLocator.isRegistered<NetworkService>()) {
      final networkService = serviceLocator<NetworkService>();
      networkService.dispose();
    }
    
    if (serviceLocator.isRegistered<NotificationService>()) {
      final notificationService = serviceLocator<NotificationService>();
      notificationService.dispose();
    }
    
  } catch (e) {
    print('⚠️ Error in manual service disposal: $e');
  }
}

// ==================== Service Implementations ====================

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

// ==================== Convenience Methods ====================

/// Get auth service instance
AuthService get authService => serviceLocator<AuthService>();

/// Get face recognition service instance
FaceRecognitionService get faceRecognitionService => serviceLocator<FaceRecognitionService>();

/// Get simple attendance service instance
SimpleAttendanceService get simpleAttendanceService => serviceLocator<SimpleAttendanceService>();

/// Get full attendance service instance
AttendanceService get attendanceService => serviceLocator<AttendanceService>();

/// Get storage service instance
StorageService get storageService => serviceLocator<StorageService>();

/// Get logger service instance
LoggerService get loggerService => serviceLocator<LoggerService>();

/// Get validation service instance
ValidationService get validationService => serviceLocator<ValidationService>();