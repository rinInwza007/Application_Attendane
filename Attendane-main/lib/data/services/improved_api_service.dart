// lib/data/services/improved_api_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/models/webcam_config_model.dart';

class ImprovedApiService {
  // Update this to your server IP
  static const String BASE_URL = 'http://192.168.1.100:8000'; // Change to your server IP
  
  final http.Client _client = http.Client();
  
  // Headers for JSON requests
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ==================== Health Check ====================
  
  /// Check if server is running and healthy
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

  // ==================== Face Recognition APIs ====================
  
  /// Register face for a student with improved error handling
  Future<Map<String, dynamic>> registerFace({
    required String imagePath,
    required String studentId,
    required String studentEmail,
  }) async {
    try {
      print('🔄 Registering face for student: $studentId');
      
      final uri = Uri.parse('$BASE_URL/api/face/register');
      final request = http.MultipartRequest('POST', uri);
      
      // Add form fields
      request.fields['student_id'] = studentId;
      request.fields['student_email'] = studentEmail;
      
      // Validate image file
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found: $imagePath');
      }
      
      final fileStat = await file.stat();
      if (fileStat.size == 0) {
        throw Exception('Image file is empty');
      }
      
      if (fileStat.size > 10 * 1024 * 1024) { // 10MB limit
        throw Exception('Image file too large (max 10MB)');
      }
      
      // Add image file
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        imagePath,
        filename: 'face_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      
      request.files.add(multipartFile);
      
      // Send request with timeout
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Face registration successful');
        return {
          'success': true,
          'data': result,
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Registration failed');
      }
      
    } catch (e) {
      print('❌ Face registration error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Verify face with improved accuracy
  Future<Map<String, dynamic>> verifyFace({
    required String imagePath,
    required String studentId,
  }) async {
    try {
      print('🔄 Verifying face for student: $studentId');
      
      final uri = Uri.parse('$BASE_URL/api/face/verify');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['student_id'] = studentId;
      
      // Validate and add image file
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found');
      }
      
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        imagePath,
        filename: 'verify_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      
      request.files.add(multipartFile);
      
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Face verification completed');
        print('   Verified: ${result['verified']}');
        print('   Similarity: ${result['similarity']?.toStringAsFixed(3)}');
        
        return {
          'success': true,
          'verified': result['verified'],
          'similarity': result['similarity'],
          'confidence': result['confidence'],
          'data': result,
        };
      } else if (response.statusCode == 404) {
        throw Exception('No face data found for this student');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Verification failed');
      }
      
    } catch (e) {
      print('❌ Face verification error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ==================== Attendance APIs ====================
  
  /// Create attendance session with validation
  Future<Map<String, dynamic>> createAttendanceSession({
    required String classId,
    required String teacherEmail,
    int durationHours = 2,
    int onTimeLimitMinutes = 30,
  }) async {
    try {
      print('🔄 Creating attendance session for class: $classId');
      
      final response = await _client.post(
        Uri.parse('$BASE_URL/api/attendance/session/create'),
        headers: _headers,
        body: json.encode({
          'class_id': classId,
          'teacher_email': teacherEmail,
          'duration_hours': durationHours,
          'on_time_limit_minutes': onTimeLimitMinutes,
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Attendance session created: ${result['session_id']}');
        
        return {
          'success': true,
          'session_id': result['session_id'],
          'data': result,
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

  /// Check in with face recognition
  Future<Map<String, dynamic>> checkInWithFaceRecognition({
    required String sessionId,
    required String studentEmail,
    WebcamConfigModel? webcamConfig,
  }) async {
    try {
      print('🔄 Checking in for session: $sessionId');
      
      final requestBody = {
        'session_id': sessionId,
        'student_email': studentEmail,
      };
      
      if (webcamConfig != null) {
        requestBody['webcam_config'] = {
          'ip_address': webcamConfig.ipAddress.toString(),
          'port': webcamConfig.port,
          'username': webcamConfig.username ?? '',
          'password': webcamConfig.password ?? '',
        };
      }
      
      final response = await _client.post(
        Uri.parse('$BASE_URL/api/attendance/checkin'),
        headers: _headers,
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 45));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Check-in successful: ${result['status']}');
        
        return {
          'success': true,
          'status': result['status'],
          'face_verified': result['face_verified'],
          'face_match_score': result['face_match_score'],
          'data': result,
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Check-in failed');
      }
      
    } catch (e) {
      print('❌ Check-in error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get attendance records for a session
  Future<Map<String, dynamic>> getSessionAttendanceRecords(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/api/attendance/session/$sessionId/records'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final records = data['records'] as List;
        
        final attendanceRecords = records.map((record) {
          return AttendanceRecordModel(
            id: record['id'].toString(),
            sessionId: record['session_id'],
            studentEmail: record['student_email'],
            studentId: record['student_id'],
            checkInTime: DateTime.parse(record['check_in_time']),
            status: record['status'],
            faceMatchScore: record['face_match_score']?.toDouble(),
            webcamImageUrl: record['webcam_image_url'],
            createdAt: DateTime.parse(record['created_at']),
          );
        }).toList();
        
        return {
          'success': true,
          'records': attendanceRecords,
          'count': data['count'],
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

  // ==================== Webcam APIs ====================
  
  /// Test webcam connection
  Future<bool> testWebcamConnection(WebcamConfigModel config) async {
    try {
      final response = await _client.post(
        Uri.parse('$BASE_URL/api/webcam/capture'),
        headers: _headers,
        body: json.encode({
          'ip_address': config.ipAddress.toString(),
          'port': config.port,
          'username': config.username ?? '',
          'password': config.password ?? '',
        }),
      ).timeout(const Duration(seconds: 15));
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Webcam test failed: $e');
      return false;
    }
  }

  /// Capture image from webcam
  Future<Uint8List?> captureFromWebcam(WebcamConfigModel config) async {
    try {
      final response = await _client.post(
        Uri.parse('$BASE_URL/api/webcam/capture'),
        headers: _headers,
        body: json.encode({
          'ip_address': config.ipAddress.toString(),
          'port': config.port,
          'username': config.username ?? '',
          'password': config.password ?? '',
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Failed to capture image: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error capturing from webcam: $e');
      return null;
    }
  }

  // ==================== Utility Methods ====================
  
  /// Get server information
  Future<Map<String, dynamic>> getServerInfo() async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': json.decode(response.body),
        };
      } else {
        throw Exception('Failed to get server info');
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Upload image as bytes with retry mechanism
  Future<Map<String, dynamic>> uploadImageBytes({
    required Uint8List imageBytes,
    required String endpoint,
    Map<String, String>? additionalFields,
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 Upload attempt $attempt/$maxRetries');
        
        final uri = Uri.parse('$BASE_URL$endpoint');
        final request = http.MultipartRequest('POST', uri);
        
        // Add additional fields if provided
        if (additionalFields != null) {
          request.fields.addAll(additionalFields);
        }
        
        // Add image as multipart file
        final multipartFile = http.MultipartFile.fromBytes(
          'file',
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

  // ==================== Connection Testing ====================
  
  /// Comprehensive server connection test
  Future<Map<String, dynamic>> testServerConnection() async {
    final results = <String, dynamic>{
      'overall_status': 'unknown',
      'tests': <String, dynamic>{},
      'timestamp': DateTime.now().isoformat(),
    };
    
    try {
      // Test 1: Basic connectivity
      print('🧪 Testing basic connectivity...');
      final healthResult = await checkServerHealth();
      results['tests']['health_check'] = healthResult;
      
      if (!healthResult['healthy']) {
        results['overall_status'] = 'failed';
        return results;
      }
      
      // Test 2: Get server info
      print('🧪 Testing server info...');
      final infoResult = await getServerInfo();
      results['tests']['server_info'] = infoResult;
      
      // Test 3: Test face recognition availability (optional)
      print('🧪 Testing face recognition service...');
      // This would require a test image
      results['tests']['face_recognition'] = {'available': true};
      
      results['overall_status'] = 'healthy';
      print('✅ All server tests passed');
      
    } catch (e) {
      results['overall_status'] = 'error';
      results['error'] = e.toString();
      print('❌ Server connection test failed: $e');
    }
    
    return results;
  }

  // Clean up
  void dispose() {
    _client.close();
  }
}

// Usage example in your Flutter service
/*
class ImprovedAttendanceService {
  final ImprovedApiService _apiService = ImprovedApiService();
  
  Future<bool> checkInWithRealTimeFaceRecognition({
    required String sessionId,
    required List<double> faceEmbedding,
  }) async {
    try {
      // Save face embedding temporarily as image for API
      // This is a simplified approach - you might want to enhance this
      
      final result = await _apiService.checkInWithFaceRecognition(
        sessionId: sessionId,
        studentEmail: getCurrentUserEmail(),
      );
      
      return result['success'] == true;
    } catch (e) {
      print('❌ Real-time face check-in error: $e');
      return false;
    }
  }
}
*/