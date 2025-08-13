// lib/data/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/models/webcam_config_model.dart';

class ApiService {
  // แก้ BASE_URL เป็น IP ของเครื่องที่รัน server
  static const String BASE_URL = 'http://192.168.1.100:8000'; // เปลี่ยนเป็น IP ของ server
  
  final http.Client _client = http.Client();

  // Headers สำหรับ JSON requests
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ==================== Face Recognition APIs ====================
  
  /// ลงทะเบียนใบหน้านักเรียน
  Future<Map<String, dynamic>> registerFace({
    required String imagePath,
    required String studentId,
    required String studentEmail,
  }) async {
    try {
      final uri = Uri.parse('$BASE_URL/api/face/register');
      final request = http.MultipartRequest('POST', uri);
      
      // Add form fields
      request.fields['student_id'] = studentId;
      request.fields['student_email'] = studentEmail;
      
      // Add image file
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found');
      }
      
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      
      final multipartFile = http.MultipartFile(
        'file',
        stream,
        length,
        filename: 'face_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      
      request.files.add(multipartFile);
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to register face');
      }
    } catch (e) {
      print('❌ Error registering face: $e');
      throw Exception('Failed to register face: $e');
    }
  }

  /// ตรวจสอบใบหน้านักเรียน
  Future<Map<String, dynamic>> verifyFace({
    required String imagePath,
    required String studentId,
  }) async {
    try {
      final uri = Uri.parse('$BASE_URL/api/face/verify');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['student_id'] = studentId;
      
      final file = File(imagePath);
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      
      final multipartFile = http.MultipartFile(
        'file',
        stream,
        length,
        filename: 'verify_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      
      request.files.add(multipartFile);
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to verify face');
      }
    } catch (e) {
      print('❌ Error verifying face: $e');
      throw Exception('Failed to verify face: $e');
    }
  }

  // ==================== Webcam APIs ====================
  
  /// จับภาพจาก IP Webcam
  Future<Uint8List> captureFromWebcam(WebcamConfigModel config) async {
    try {
      final response = await _client.post(
        Uri.parse('$BASE_URL/api/webcam/capture'),
        headers: _headers,
        body: json.encode({
          'ip_address': config.ipAddress,
          'port': config.port,
          'username': config.username,
          'password': config.password,
        }),
      );
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Failed to capture image: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error capturing from webcam: $e');
      throw Exception('Failed to capture from webcam: $e');
    }
  }

  // ==================== Attendance APIs ====================
  
  /// เช็คชื่อด้วย Face Recognition
  Future<Map<String, dynamic>> checkInWithFaceRecognition({
    required String sessionId,
    required String studentEmail,
    required WebcamConfigModel webcamConfig,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$BASE_URL/api/attendance/checkin'),
        headers: _headers,
        body: json.encode({
          'session_id': sessionId,
          'student_email': studentEmail,
          'webcam_config': {
            'ip_address': webcamConfig.ipAddress,
            'port': webcamConfig.port,
            'username': webcamConfig.username,
            'password': webcamConfig.password,
          },
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to check in');
      }
    } catch (e) {
      print('❌ Error checking in: $e');
      throw Exception('Failed to check in: $e');
    }
  }

  /// สร้าง Session การเช็คชื่อใหม่
  Future<AttendanceSessionModel> createAttendanceSession({
    required String classId,
    required String teacherEmail,
    int durationHours = 2,
    int onTimeLimitMinutes = 30,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$BASE_URL/api/attendance/session/create'),
        headers: _headers,
        body: json.encode({
          'class_id': classId,
          'teacher_email': teacherEmail,
          'duration_hours': durationHours,
          'on_time_limit_minutes': onTimeLimitMinutes,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // ดึงข้อมูล session ที่สร้างใหม่
        return AttendanceSessionModel(
          id: data['session_id'],
          classId: classId,
          teacherEmail: teacherEmail,
          startTime: DateTime.now(),
          endTime: DateTime.now().add(Duration(hours: durationHours)),
          onTimeLimitMinutes: onTimeLimitMinutes,
          status: 'active',
          createdAt: DateTime.now(),
        );
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to create session');
      }
    } catch (e) {
      print('❌ Error creating session: $e');
      throw Exception('Failed to create session: $e');
    }
  }

  /// จบ Session การเช็คชื่อ
  Future<Map<String, dynamic>> endAttendanceSession(String sessionId) async {
    try {
      final response = await _client.put(
        Uri.parse('$BASE_URL/api/attendance/session/$sessionId/end'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to end session');
      }
    } catch (e) {
      print('❌ Error ending session: $e');
      throw Exception('Failed to end session: $e');
    }
  }

  /// ดึงรายการเช็คชื่อของ Session
  Future<List<AttendanceRecordModel>> getSessionAttendanceRecords(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/api/attendance/session/$sessionId/records'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final records = data['records'] as List;
        
        return records.map((record) {
          // Extract student info from joined data
          final userInfo = record['users'] ?? {};
          
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
      } else {
        throw Exception('Failed to get attendance records');
      }
    } catch (e) {
      print('❌ Error getting attendance records: $e');
      throw Exception('Failed to get attendance records: $e');
    }
  }

  // ==================== Health Check ====================
  
  /// ตรวจสอบสถานะ Server
  Future<bool> checkServerHealth() async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/health'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Server health check failed: $e');
      return false;
    }
  }

  /// Get server info
  Future<Map<String, dynamic>> getServerInfo() async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get server info');
      }
    } catch (e) {
      print('❌ Error getting server info: $e');
      throw Exception('Failed to get server info: $e');
    }
  }

  // ==================== Utility Methods ====================
  
  /// Upload image as bytes
  Future<Map<String, dynamic>> uploadImageBytes({
    required Uint8List imageBytes,
    required String endpoint,
    Map<String, String>? additionalFields,
  }) async {
    try {
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
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Upload failed');
      }
    } catch (e) {
      print('❌ Error uploading image: $e');
      throw Exception('Failed to upload image: $e');
    }
  }

  // Clean up
  void dispose() {
    _client.close();
  }
}