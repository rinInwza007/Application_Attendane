// lib/core/constants/app_constants.dart
import 'package:flutter/foundation.dart';

class AppConstants {
  // ==================== App Information ====================
  static const String appName = 'Attendance Plus';
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '1';
  
  // ==================== Environment ====================
  static bool get isDevelopment => kDebugMode;
  static bool get isProduction => kReleaseMode;
  
  // ==================== API Configuration ====================
  
  // Supabase Configuration
  static const String supabaseUrl = 'https://cykbwnxcvdszxlypzucy.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5a2J3bnhjdmRzenhseXB6dWN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzIwMDEwMDMsImV4cCI6MjA0NzU3NzAwM30.t51vDsflnqzKVic9tZ_uFpiaS_6RO3J3gOeMJdm0lvo';
  
  // Backend API (for future use)
  static String get apiBaseUrl {
    if (isDevelopment) {
      return 'http://192.168.1.100:8000'; // Local development
    } else {
      return 'https://api.attendance-plus.com'; // Production
    }
  }
  
  // ==================== Database Configuration ====================
  
  // Table Names
  static const String usersTable = 'users';
  static const String classesTable = 'classes';
  static const String classStudentsTable = 'class_students';
  static const String attendanceSessionsTable = 'attendance_sessions';
  static const String attendanceRecordsTable = 'attendance_records';
  static const String faceEmbeddingsTable = 'student_face_embeddings';
  
  // ==================== Shared Preferences Keys ====================
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'student_id';
  static const String userEmailKey = 'user_email';
  static const String userTypeKey = 'user_type';
  static const String themeKey = 'app_theme';
  static const String languageKey = 'app_language';
  
  // ==================== Default Values ====================
  static const int defaultPageSize = 20;
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);
  static const Duration splashDuration = Duration(seconds: 2);
  static const Duration sessionTimeout = Duration(hours: 24);
  
  // Attendance Session Defaults
  static const int defaultSessionDurationHours = 2;
  static const int defaultOnTimeLimitMinutes = 30;
  static const int maxSessionDurationHours = 8;
  static const int maxOnTimeLimitMinutes = 60;
  
  // ==================== Validation Patterns ====================
  static final RegExp emailPattern = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  static final RegExp passwordPattern = RegExp(r'^.{6,}$');
  static final RegExp classIdPattern = RegExp(r'^[A-Z0-9]{2,10}$');
  static final RegExp schoolIdPattern = RegExp(r'^[A-Za-z0-9]{5,20}$');
  static final RegExp inviteCodePattern = RegExp(r'^[A-Z0-9]{6}$');
  
  // ==================== Face Recognition Configuration ====================
  static const int faceModelInputSize = 112;
  static const int faceEmbeddingSize = 128;
  static const double faceMatchThreshold = 0.7;
  static const double faceQualityThreshold = 0.6;
  static const int faceDetectionTimeoutSeconds = 30;
  static const int maxFaceRegistrationAttempts = 3;
  
  // Face Detection Quality Thresholds
  static const double minFaceSize = 0.15;
  static const double maxHeadRotationDegrees = 30.0;
  static const double maxHeadTiltDegrees = 20.0;
  static const double minEyeOpenProbability = 0.5;
  
  // ==================== File and Storage Limits ====================
  static const int maxImageSizeBytes = 10 * 1024 * 1024; // 10MB
  static const int maxImageWidthPixels = 1024;
  static const int maxImageHeightPixels = 1024;
  static const int imageQuality = 85; // JPEG quality (0-100)
  
  static const List<String> supportedImageFormats = ['.jpg', '.jpeg', '.png'];
  
  // ==================== Network Configuration ====================
  static const Duration networkTimeout = Duration(seconds: 30);
  static const Duration shortTimeout = Duration(seconds: 10);
  static const Duration longTimeout = Duration(minutes: 2);
  
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  
  // ==================== UI Configuration ====================
  
  // Animation Durations
  static const Duration fastAnimation = Duration(milliseconds: 150);
  static const Duration normalAnimation = Duration(milliseconds: 300);
  static const Duration slowAnimation = Duration(milliseconds: 500);
  
  // Debounce Durations
  static const Duration searchDebounce = Duration(milliseconds: 500);
  static const Duration buttonDebounce = Duration(milliseconds: 1000);
  
  // Pagination
  static const int defaultItemsPerPage = 20;
  static const int maxItemsPerPage = 100;
  
  // ==================== Error Messages ====================
  
  // Generic Errors
  static const String defaultErrorMessage = 'Something went wrong. Please try again.';
  static const String networkErrorMessage = 'Network connection error. Please check your internet connection.';
  static const String timeoutErrorMessage = 'Request timed out. Please try again.';
  static const String serverErrorMessage = 'Server error. Please try again later.';
  
  // Authentication Errors
  static const String authErrorMessage = 'Authentication failed. Please check your credentials.';
  static const String sessionExpiredMessage = 'Your session has expired. Please log in again.';
  static const String unauthorizedMessage = 'You are not authorized to perform this action.';
  
  // Face Recognition Errors
  static const String noFaceDetectedMessage = 'No face detected. Please ensure your face is visible.';
  static const String multipleFacesMessage = 'Multiple faces detected. Please ensure only your face is visible.';
  static const String lowQualityFaceMessage = 'Face quality is too low. Please try again in better lighting.';
  static const String faceVerificationFailedMessage = 'Face verification failed. Please try again.';
  
  // Class Management Errors
  static const String classNotFoundMessage = 'Class not found. Please check the class code.';
  static const String alreadyJoinedMessage = 'You have already joined this class.';
  static const String sessionNotActiveMessage = 'Attendance session is not active.';
  static const String alreadyCheckedInMessage = 'You have already checked in for this session.';
  
  // ==================== Success Messages ====================
  static const String loginSuccessMessage = 'Login successful';
  static const String registerSuccessMessage = 'Registration successful';
  static const String profileUpdateSuccessMessage = 'Profile updated successfully';
  static const String classCreatedSuccessMessage = 'Class created successfully';
  static const String classJoinedSuccessMessage = 'Successfully joined the class';
  static const String attendanceRecordedMessage = 'Attendance recorded successfully';
  static const String faceRegisteredMessage = 'Face recognition setup completed';
  
  // ==================== Feature Flags ====================
  
  // Enable/disable features based on environment or configuration
  static bool get enableOfflineMode => isDevelopment || true;
  static bool get enablePushNotifications => true;
  static bool get enableAnalytics => isProduction;
  static bool get enableCrashReporting => isProduction;
  static bool get enableDebugLogging => isDevelopment;
  static bool get enableFaceAntiSpoofing => true;
  
  // Experimental Features
  static bool get enableBiometricAuth => false;
  static bool get enableQRCodeAttendance => false;
  static bool get enableGeofenceAttendance => false;
  static bool get enableVoiceRecognition => false;
  
  // ==================== URLs and Links ====================
  static const String privacyPolicyUrl = 'https://attendance-plus.com/privacy';
  static const String termsOfServiceUrl = 'https://attendance-plus.com/terms';
  static const String supportUrl = 'https://attendance-plus.com/support';
  static const String feedbackUrl = 'https://attendance-plus.com/feedback';
  
  // App Store Links
  static const String appStoreUrl = 'https://apps.apple.com/app/attendance-plus';
  static const String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.attendanceplus.app';
  
  // ==================== Development Configuration ====================
  
  static bool get enableVerboseLogging => isDevelopment;
  static bool get showDebugInfo => isDevelopment;
  static bool get mockNetworkDelay => isDevelopment && false;
  static Duration get mockDelay => const Duration(seconds: 2);
  
  // Test Data
  static bool get useTestData => isDevelopment && false;
  static String get testUserEmail => 'test@example.com';
  static String get testUserPassword => 'password123';
  
  // ==================== Helper Methods ====================
  
  /// Check if an email is valid
  static bool isValidEmail(String email) {
    return emailPattern.hasMatch(email);
  }
  
  /// Check if a password meets requirements
  static bool isValidPassword(String password) {
    return passwordPattern.hasMatch(password);
  }
  
  /// Check if a class ID is valid
  static bool isValidClassId(String classId) {
    return classIdPattern.hasMatch(classId);
  }
  
  /// Check if a school ID is valid
  static bool isValidSchoolId(String schoolId) {
    return schoolIdPattern.hasMatch(schoolId);
  }
  
  /// Check if an invite code is valid
  static bool isValidInviteCode(String inviteCode) {
    return inviteCodePattern.hasMatch(inviteCode);
  }
  
  /// Get environment-specific configuration
  static Map<String, dynamic> getEnvironmentConfig() {
    return {
      'isDevelopment': isDevelopment,
      'isProduction': isProduction,
      'apiBaseUrl': apiBaseUrl,
      'enableDebugLogging': enableDebugLogging,
      'enableAnalytics': enableAnalytics,
      'appVersion': appVersion,
    };
  }
}