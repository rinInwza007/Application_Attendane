// lib/data/services/enhanced_attendance_service.dart - แก้ไข error
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:myproject2/core/service_locator.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/models/webcam_config_model.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/attendance_service.dart'; // เพิ่ม import
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class EnhancedAttendanceService {
  static const String BASE_URL = 'http://192.168.1.100:8000'; // Update with your server IP
  
  final http.Client _client = http.Client();
  final AuthService _authService = AuthService();
  // เพิ่มตัวแปรสำหรับ attendance service
  late final SimpleAttendanceService _simpleAttendanceService;

  // Constructor - เพิ่มการ initialize attendance service
  EnhancedAttendanceService() {
    _simpleAttendanceService = SimpleAttendanceService();
  }

  // Headers for JSON requests
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ==================== Enhanced Health Check ====================
  
  Future<Map<String, dynamic>> checkServerHealth() async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/health'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'healthy': true,
          'data': data,
          'cache_size': data['cache']?['size'] ?? 0,
          'version': data['version'] ?? 'unknown',
        };
      } else {
        return {
          'healthy': false,
          'error': 'Server returned ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'healthy': false,
        'error': e.toString(),
      };
    }
  }

  // ==================== Enhanced Face Enrollment ====================
  
  Future<Map<String, dynamic>> enrollFaceMultipleImages({
    required List<String> imagePaths,
    required String studentId,
    required String studentEmail,
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 Enrolling face attempt $attempt/$maxRetries for $studentId');
        
        final uri = Uri.parse('$BASE_URL/api/face/enroll');
        final request = http.MultipartRequest('POST', uri);
        
        // Add form fields
        request.fields['student_id'] = studentId;
        request.fields['student_email'] = studentEmail;
        
        // Add image files
        for (int i = 0; i < imagePaths.length; i++) {
          final imagePath = imagePaths[i];
          final file = File(imagePath);
          
          if (!await file.exists()) {
            throw Exception('Image file not found: $imagePath');
          }
          
          final multipartFile = await http.MultipartFile.fromPath(
            'images',
            imagePath,
            filename: 'face_image_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          
          request.files.add(multipartFile);
        }
        
        // Send request with timeout
        final streamedResponse = await request.send().timeout(
          Duration(seconds: 30 + (imagePaths.length * 10)), // Dynamic timeout
        );
        
        final response = await http.Response.fromStream(streamedResponse);
        
        if (response.statusCode == 200) {
          final result = json.decode(response.body);
          print('✅ Face enrollment successful: ${result['message']}');
          
          // Clear server cache after enrollment
          await _clearServerCache();
          
          return {
            'success': true,
            'data': result,
            'images_processed': result['images_processed'],
            'quality_score': result['quality_score'],
          };
        } else {
          final error = json.decode(response.body);
          if (attempt == maxRetries) {
            throw Exception(error['detail'] ?? 'Face enrollment failed');
          }
          print('⚠️ Enrollment attempt $attempt failed, retrying...');
          await Future.delayed(Duration(seconds: attempt * 2));
        }
        
      } catch (e) {
        if (attempt == maxRetries) {
          print('❌ Face enrollment failed after $maxRetries attempts: $e');
          return {
            'success': false,
            'error': e.toString(),
            'attempts': attempt,
          };
        }
        print('⚠️ Enrollment attempt $attempt error: $e, retrying...');
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    
    return {
      'success': false,
      'error': 'Max retries exceeded',
      'attempts': maxRetries,
    };
  }

  Future<Map<String, dynamic>> verifyFaceEnrollment(String studentId) async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/api/face/verify/$studentId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return {
          'success': true,
          'has_face_data': result['has_face_data'] ?? false,
          'student_id': result['student_id'],
          'quality_score': result['quality_score'],
        };
      } else {
        throw Exception('Failed to verify face enrollment');
      }
      
    } catch (e) {
      print('❌ Error verifying face enrollment: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> deleteFaceEnrollment(String studentId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$BASE_URL/api/face/$studentId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return {
          'success': true,
          'message': result['message'],
        };
      } else {
        throw Exception('Failed to delete face enrollment');
      }
      
    } catch (e) {
      print('❌ Error deleting face enrollment: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ==================== Enhanced Session Management ====================
  
  Future<Map<String, dynamic>> createEnhancedSession({
    required String classId,
    required String teacherEmail,
    int durationHours = 2,
    int captureIntervalMinutes = 5,
    int onTimeLimitMinutes = 30,
  }) async {
    try {
      print('🔄 Creating enhanced session for class: $classId');
      
      final response = await _client.post(
        Uri.parse('$BASE_URL/api/session/create'),
        headers: _headers,
        body: json.encode({
          'class_id': classId,
          'teacher_email': teacherEmail,
          'duration_hours': durationHours,
          'capture_interval_minutes': captureIntervalMinutes,
          'on_time_limit_minutes': onTimeLimitMinutes,
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Enhanced session created: ${result['session_id']}');
        
        return {
          'success': true,
          'session_id': result['session_id'],
          'start_time': result['start_time'],
          'end_time': result['end_time'],
          'capture_interval_minutes': result['capture_interval_minutes'],
          'on_time_limit_minutes': result['on_time_limit_minutes'],
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to create session');
      }
      
    } catch (e) {
      print('❌ Session creation error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> endSession(String sessionId) async {
    try {
      final response = await _client.put(
        Uri.parse('$BASE_URL/api/session/$sessionId/end'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return {
          'success': true,
          'message': result['message'],
          'session_id': sessionId,
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to end session');
      }
      
    } catch (e) {
      print('❌ Error ending session: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ==================== Periodic Attendance Processing ====================
  
  Future<Map<String, dynamic>> processPeriodicAttendance({
    required String imagePath,
    required String sessionId,
    required DateTime captureTime,
    bool deleteImageAfter = true,
  }) async {
    try {
      print('📸 Processing periodic attendance for session: $sessionId');
      
      final uri = Uri.parse('$BASE_URL/api/attendance/periodic');
      final request = http.MultipartRequest('POST', uri);
      
      // Add form fields
      request.fields['session_id'] = sessionId;
      request.fields['capture_time'] = captureTime.toIso8601String();
      
      // Add image file
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found: $imagePath');
      }
      
      final multipartFile = await http.MultipartFile.fromPath(
        'image',
        imagePath,
        filename: 'attendance_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      
      request.files.add(multipartFile);
      
      // Send request with timeout
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60), // Longer timeout for processing
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      
      // Clean up image file if requested
      if (deleteImageAfter) {
        try {
          await file.delete();
          print('🗑️ Cleaned up image file: $imagePath');
        } catch (e) {
          print('⚠️ Failed to delete image file: $e');
        }
      }
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Periodic attendance processed successfully');
        print('   Faces detected: ${result['faces_detected']}');
        print('   Message: ${result['message']}');
        
        return {
          'success': true,
          'faces_detected': result['faces_detected'],
          'message': result['message'],
          'session_id': result['session_id'],
          'capture_time': result['capture_time'],
          'enrolled_students': result['enrolled_students'],
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to process attendance');
      }
      
    } catch (e) {
      print('❌ Periodic attendance processing error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ==================== Batch Processing ====================
  
  Future<Map<String, dynamic>> processMultipleImages({
    required List<String> imagePaths,
    required String sessionId,
    required List<DateTime> captureTimes,
    bool deleteImagesAfter = true,
    Function(int processed, int total)? onProgress,
  }) async {
    try {
      if (imagePaths.length != captureTimes.length) {
        throw Exception('Image paths and capture times must have the same length');
      }
      
      print('🔄 Batch processing ${imagePaths.length} images for session: $sessionId');
      
      final List<Map<String, dynamic>> results = [];
      int successCount = 0;
      int totalFacesDetected = 0;
      
      for (int i = 0; i < imagePaths.length; i++) {
        try {
          onProgress?.call(i, imagePaths.length);
          
          final result = await processPeriodicAttendance(
            imagePath: imagePaths[i],
            sessionId: sessionId,
            captureTime: captureTimes[i],
            deleteImageAfter: deleteImagesAfter,
          );
          
          results.add(result);
          
          if (result['success']) {
            successCount++;
            totalFacesDetected += (result['faces_detected'] as int? ?? 0);
          }
          
          // Small delay between requests to avoid overwhelming the server
          await Future.delayed(const Duration(milliseconds: 500));
          
        } catch (e) {
          print('❌ Error processing image ${i + 1}: $e');
          results.add({
            'success': false,
            'error': e.toString(),
            'image_index': i,
          });
        }
      }
      
      onProgress?.call(imagePaths.length, imagePaths.length);
      
      return {
        'success': successCount > 0,
        'total_images': imagePaths.length,
        'successful_images': successCount,
        'total_faces_detected': totalFacesDetected,
        'results': results,
      };
      
    } catch (e) {
      print('❌ Batch processing error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ==================== Enhanced Analytics ====================
  
  Future<Map<String, dynamic>> getSessionStatistics(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/api/session/$sessionId/statistics'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return {
          'success': true,
          'session_id': sessionId,
          'statistics': result['statistics'],
          'student_details': result['student_details'],
          'hourly_breakdown': result['hourly_breakdown'],
        };
      } else {
        // Fallback to basic statistics
        return await _calculateBasicStatistics(sessionId);
      }
      
    } catch (e) {
      print('❌ Error getting session statistics: $e');
      return await _calculateBasicStatistics(sessionId);
    }
  }

  Future<Map<String, dynamic>> _calculateBasicStatistics(String sessionId) async {
    try {
      // แก้ไข: ใช้ _simpleAttendanceService แทน _authService.attendanceService
      final records = await _getAttendanceRecordsFromSupabase(sessionId);
      
      final totalStudents = records.length;
      final presentCount = records.where((r) => r.status == 'present').length;
      final lateCount = records.where((r) => r.status == 'late').length;
      final absentCount = records.where((r) => r.status == 'absent').length;
      
      final faceVerifiedCount = records.where((r) => r.hasFaceMatch).length;
      final averageFaceScore = records
          .where((r) => r.faceMatchScore != null)
          .map((r) => r.faceMatchScore!)
          .fold(0.0, (sum, score) => sum + score) / 
          (records.where((r) => r.faceMatchScore != null).length.clamp(1, double.infinity));
      
      return {
        'success': true,
        'session_id': sessionId,
        'statistics': {
          'total_students': totalStudents,
          'present_count': presentCount,
          'late_count': lateCount,
          'absent_count': absentCount,
          'attendance_rate': totalStudents > 0 ? (presentCount + lateCount) / totalStudents : 0.0,
          'face_verified_count': faceVerifiedCount,
          'face_verification_rate': totalStudents > 0 ? faceVerifiedCount / totalStudents : 0.0,
          'average_face_score': averageFaceScore.isNaN ? 0.0 : averageFaceScore,
        },
      };
      
    } catch (e) {
      print('❌ Error calculating basic statistics: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<List<AttendanceRecordModel>> _getAttendanceRecordsFromSupabase(String sessionId) async {
    try {
      // แก้ไข: ใช้ _simpleAttendanceService โดยตรง
      final response = await _simpleAttendanceService.getAttendanceRecords(sessionId);
      return response;
    } catch (e) {
      print('❌ Error getting records from Supabase: $e');
      return [];
    }
  }

  // ==================== Cache Management ====================
  
  Future<Map<String, dynamic>> _clearServerCache() async {
    try {
      final response = await _client.delete(
        Uri.parse('$BASE_URL/api/cache/clear'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Server cache cleared: ${result['message']}');
        return result;
      }
    } catch (e) {
      print('⚠️ Failed to clear server cache: $e');
    }
    
    return {'success': false};
  }

  // ==================== Image Management ====================
  
  Future<String> saveImageToAppDirectory(Uint8List imageBytes, {String? filename}) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = filename ?? 'attendance_$timestamp.jpg';
      final String savedPath = path.join(appDir.path, 'attendance_images', fileName);
      
      // Ensure directory exists
      final Directory imageDir = Directory(path.dirname(savedPath));
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }
      
      // Write image bytes to file
      final File imageFile = File(savedPath);
      await imageFile.writeAsBytes(imageBytes);
      
      print('💾 Image saved: $savedPath');
      return savedPath;
      
    } catch (e) {
      print('❌ Error saving image: $e');
      throw Exception('Failed to save image: $e');
    }
  }

  Future<void> cleanupOldImages({int maxAgeHours = 24}) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory imageDir = Directory(path.join(appDir.path, 'attendance_images'));
      
      if (!await imageDir.exists()) return;
      
      final cutoffTime = DateTime.now().subtract(Duration(hours: maxAgeHours));
      final files = imageDir.listSync();
      
      int deletedCount = 0;
      
      for (final file in files) {
        if (file is File) {
          final fileStat = await file.stat();
          if (fileStat.modified.isBefore(cutoffTime)) {
            try {
              await file.delete();
              deletedCount++;
            } catch (e) {
              print('⚠️ Failed to delete old image: ${file.path}');
            }
          }
        }
      }
      
      print('🧹 Cleaned up $deletedCount old image files');
      
    } catch (e) {
      print('❌ Error during image cleanup: $e');
    }
  }

  // ==================== Connection Testing ====================
  
  Future<bool> testServerConnection({int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await checkServerHealth();
        if (result['healthy'] == true) {
          print('✅ Server connection test successful on attempt $attempt');
          return true;
        }
      } catch (e) {
        print('⚠️ Server connection test attempt $attempt failed: $e');
      }
      
      if (attempt < maxRetries) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    
    print('❌ Server connection test failed after $maxRetries attempts');
    return false;
  }

  // ==================== Utility Methods ====================
  
  Future<Map<String, dynamic>> uploadImageBytes({
    required Uint8List imageBytes,
    required String endpoint,
    Map<String, String>? additionalFields,
    String filename = 'image.jpg',
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 Upload attempt $attempt/$maxRetries to $endpoint');
        
        final uri = Uri.parse('$BASE_URL$endpoint');
        final request = http.MultipartRequest('POST', uri);
        
        // Add additional fields if provided
        if (additionalFields != null) {
          request.fields.addAll(additionalFields);
        }
        
        // Add image as multipart file
        final multipartFile = http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: filename,
        );
        
        request.files.add(multipartFile);
        
        final streamedResponse = await request.send().timeout(
          Duration(seconds: 30 * attempt), // Increase timeout with retries
        );
        
        final response = await http.Response.fromStream(streamedResponse);
        
        if (response.statusCode == 200) {
          print('✅ Upload successful on attempt $attempt');
          return {
            'success': true,
            'data': json.decode(response.body),
          };
        } else {
          final error = json.decode(response.body);
          if (attempt == maxRetries) {
            throw Exception(error['detail'] ?? 'Upload failed');
          }
          print('⚠️ Upload attempt $attempt failed, retrying...');
          await Future.delayed(Duration(seconds: attempt * 2));
        }
        
      } catch (e) {
        if (attempt == maxRetries) {
          print('❌ Upload failed after $maxRetries attempts: $e');
          return {
            'success': false,
            'error': e.toString(),
          };
        }
        print('⚠️ Upload attempt $attempt error: $e, retrying...');
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    
    return {
      'success': false,
      'error': 'Max retries exceeded',
    };
  }

  // Clean up
  void dispose() {
    _client.close();
  }
}