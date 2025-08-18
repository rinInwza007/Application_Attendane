// lib/data/services/periodic_attendance_api_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';

class PeriodicAttendanceApiService {
  static const String BASE_URL = 'http://192.168.1.100:8000'; // Update with your server IP
  
  final http.Client _client = http.Client();

  // Headers for JSON requests
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ==================== Health Check ====================
  
  Future<Map<String, dynamic>> checkServerHealth() async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/health'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return {
          'healthy': true,
          'data': json.decode(response.body),
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

  // ==================== Face Enrollment ====================
  
  Future<Map<String, dynamic>> enrollFaceMultipleImages({
    required List<String> imagePaths,
    required String studentId,
    required String studentEmail,
  }) async {
    try {
      print('🔄 Enrolling face with ${imagePaths.length} images for $studentId');
      
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
        const Duration(seconds: 60), // Longer timeout for multiple images
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Face enrollment successful: ${result['message']}');
        return {
          'success': true,
          'data': result,
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Face enrollment failed');
      }
      
    } catch (e) {
      print('❌ Face enrollment error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
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
          'has_face_data': result['has_face_data'],
          'student_id': result['student_id'],
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

  // ==================== Session Management ====================
  
  Future<Map<String, dynamic>> createPeriodicSession({
    required String classId,
    required String teacherEmail,
    int durationHours = 2,
    int captureIntervalMinutes = 5,
    int onTimeLimitMinutes = 30,
  }) async {
    try {
      print('🔄 Creating periodic session for class: $classId');
      
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
        print('✅ Periodic session created: ${result['session_id']}');
        
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

  Future<Map<String, dynamic>> endPeriodicSession(String sessionId) async {
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

  // ==================== Periodic Attendance ====================
  
  Future<Map<String, dynamic>> processPeriodicAttendance({
    required String imagePath,
    required String sessionId,
    required DateTime captureTime,
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
        const Duration(seconds: 45),
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Periodic attendance processed successfully');
        print('   Faces detected: ${result['faces_detected']}');
        print('   New records: ${result['new_attendance_records']}');
        
        return {
          'success': true,
          'faces_detected': result['faces_detected'],
          'new_attendance_records': result['new_attendance_records'],
          'attendance_records': result['attendance_records'],
          'session_id': result['session_id'],
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

  // ==================== Attendance Records ====================
  
  Future<Map<String, dynamic>> getSessionAttendanceRecords(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/api/session/$sessionId/records'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final records = data['records'] as List;
        
        final attendanceRecords = records.map((record) {
          return AttendanceRecordModel(
            id: record['id'].toString(),
            sessionId: record['session_id'] ?? sessionId,
            studentEmail: record['student_email'],
            studentId: record['student_id'],
            checkInTime: DateTime.parse(record['check_in_time']),
            status: record['status'],
            faceMatchScore: record['face_match_score']?.toDouble(),
            webcamImageUrl: null, // Not used in periodic mode
            createdAt: DateTime.parse(record['check_in_time']), // Use check_in_time as created_at
          );
        }).toList();
        
        return {
          'success': true,
          'records': attendanceRecords,
          'count': data['count'],
          'session_id': sessionId,
        };
      } else {
        throw Exception('Failed to get attendance records');
      }
      
    } catch (e) {
      print('❌ Error getting attendance records: $e');
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
  }) async {
    try {
      if (imagePaths.length != captureTimes.length) {
        throw Exception('Image paths and capture times must have the same length');
      }
      
      print('🔄 Processing ${imagePaths.length} images for session: $sessionId');
      
      final List<Map<String, dynamic>> results = [];
      int successCount = 0;
      int totalFacesDetected = 0;
      int totalNewRecords = 0;
      
      for (int i = 0; i < imagePaths.length; i++) {
        try {
          final result = await processPeriodicAttendance(
            imagePath: imagePaths[i],
            sessionId: sessionId,
            captureTime: captureTimes[i],
          );
          
          results.add(result);
          
          if (result['success']) {
            successCount++;
            totalFacesDetected += (result['faces_detected'] as int? ?? 0);
            totalNewRecords += (result['new_attendance_records'] as int? ?? 0);
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
      
      return {
        'success': successCount > 0,
        'total_images': imagePaths.length,
        'successful_images': successCount,
        'total_faces_detected': totalFacesDetected,
        'total_new_records': totalNewRecords,
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

  // ==================== Statistics ====================
  
  Future<Map<String, dynamic>> getSessionStatistics(String sessionId) async {
    try {
      // Get session info and records
      final recordsResult = await getSessionAttendanceRecords(sessionId);
      
      if (!recordsResult['success']) {
        throw Exception(recordsResult['error']);
      }
      
      final records = recordsResult['records'] as List<AttendanceRecordModel>;
      
      // Calculate statistics
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
      print('❌ Error getting session statistics: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ==================== Utility Methods ====================
  
  Future<Map<String, dynamic>> uploadImageBytes({
    required Uint8List imageBytes,
    required String endpoint,
    Map<String, String>? additionalFields,
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
          filename: 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
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

  Future<bool> testServerConnection() async {
    try {
      final result = await checkServerHealth();
      return result['healthy'] == true;
    } catch (e) {
      print('❌ Server connection test failed: $e');
      return false;
    }
  }

  // Clean up
  void dispose() {
    _client.close();
  }
}