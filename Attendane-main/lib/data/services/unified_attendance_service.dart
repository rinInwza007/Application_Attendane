// lib/data/services/unified_attendance_service.dart
// รวม AttendanceService และ EnhancedAttendanceService เป็นตัวเดียว

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/models/webcam_config_model.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class UnifiedAttendanceService {
  static const String BASE_URL = 'http://192.168.1.100:8000';
  
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();
  final http.Client _client = http.Client();

  // Headers for requests
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ==================== Session Management ====================
  
  Future<AttendanceSessionModel> createSession({
    required String classId,
    required int durationHours,
    required int onTimeLimitMinutes,
    int captureIntervalMinutes = 5,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Teacher not authenticated');

      final now = DateTime.now();
      final sessionData = {
        'class_id': classId,
        'teacher_email': user.email,
        'start_time': now.toIso8601String(),
        'end_time': now.add(Duration(hours: durationHours)).toIso8601String(),
        'on_time_limit_minutes': onTimeLimitMinutes,
        'capture_interval_minutes': captureIntervalMinutes,
        'status': 'active',
        'created_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('attendance_sessions')
          .insert(sessionData)
          .select()
          .single();

      return AttendanceSessionModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create session: $e');
    }
  }

  Future<AttendanceSessionModel?> getActiveSession(String classId) async {
    try {
      final response = await _supabase
          .from('attendance_sessions')
          .select()
          .eq('class_id', classId)
          .eq('status', 'active')
          .maybeSingle();

      if (response == null) return null;
      
      final session = AttendanceSessionModel.fromJson(response);
      
      // Auto-end expired sessions
      if (session.isEnded && session.status == 'active') {
        await endSession(session.id);
        return null;
      }
      
      return session;
    } catch (e) {
      throw Exception('Failed to get active session: $e');
    }
  }

  Future<void> endSession(String sessionId) async {
    try {
      await _supabase
          .from('attendance_sessions')
          .update({
            'status': 'ended',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', sessionId);
    } catch (e) {
      throw Exception('Failed to end session: $e');
    }
  }

  // ==================== Simple Check-in ====================
  
  Future<AttendanceRecordModel> simpleCheckIn({
    required String sessionId,
    WebcamConfigModel? webcamConfig,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Validate session
      final sessionResponse = await _supabase
          .from('attendance_sessions')
          .select()
          .eq('id', sessionId)
          .single();
      
      final session = AttendanceSessionModel.fromJson(sessionResponse);
      if (!session.isActive) {
        throw Exception('Attendance session is not active');
      }

      // Check for existing record
      final existingRecord = await _supabase
          .from('attendance_records')
          .select()
          .eq('session_id', sessionId)
          .eq('student_email', user.email!)
          .maybeSingle();

      if (existingRecord != null) {
        throw Exception('Already checked in for this session');
      }

      // Get user profile
      final userProfile = await _supabase
          .from('users')
          .select()
          .eq('email', user.email!)
          .single();
      
      // Determine status
      final checkInTime = DateTime.now();
      final status = session.isOnTime(checkInTime) ? 'present' : 'late';

      // Save record
      final recordData = {
        'session_id': sessionId,
        'student_email': user.email,
        'student_id': userProfile['school_id'],
        'check_in_time': checkInTime.toIso8601String(),
        'status': status,
        'created_at': checkInTime.toIso8601String(),
      };

      final recordResponse = await _supabase
          .from('attendance_records')
          .insert(recordData)
          .select()
          .single();

      return AttendanceRecordModel.fromJson(recordResponse);
    } catch (e) {
      throw Exception('Check-in failed: $e');
    }
  }

  // ==================== Face Recognition Check-in ====================
  
  Future<AttendanceRecordModel> faceCheckIn({
    required String sessionId,
    required List<double> faceEmbedding,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Validate session
      final sessionResponse = await _supabase
          .from('attendance_sessions')
          .select()
          .eq('id', sessionId)
          .single();
      
      final session = AttendanceSessionModel.fromJson(sessionResponse);
      if (!session.isActive) {
        throw Exception('Attendance session is not active');
      }

      // Check for existing record
      final existingRecord = await _supabase
          .from('attendance_records')
          .select()
          .eq('session_id', sessionId)
          .eq('student_email', user.email!)
          .maybeSingle();

      if (existingRecord != null) {
        throw Exception('Already checked in for this session');
      }

      // Get user profile
      final userProfile = await _authService.getUserProfile();
      if (userProfile == null) throw Exception('User profile not found');

      final studentId = userProfile['school_id'];

      // Verify face
      final isVerified = await _authService.verifyFace(studentId, faceEmbedding);
      if (!isVerified) {
        throw Exception('Face verification failed');
      }

      // Determine status
      final checkInTime = DateTime.now();
      final status = session.isOnTime(checkInTime) ? 'present' : 'late';

      // Save record with face verification
      final recordData = {
        'session_id': sessionId,
        'student_email': user.email,
        'student_id': studentId,
        'check_in_time': checkInTime.toIso8601String(),
        'status': status,
        'face_match_score': 0.95, // Mock score - replace with actual score
        'created_at': checkInTime.toIso8601String(),
      };

      final recordResponse = await _supabase
          .from('attendance_records')
          .insert(recordData)
          .select()
          .single();

      return AttendanceRecordModel.fromJson(recordResponse);
    } catch (e) {
      throw Exception('Face recognition check-in failed: $e');
    }
  }

  // ==================== Periodic Attendance (API Integration) ====================
  
  Future<Map<String, dynamic>> enrollFaceMultiple({
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
        
        request.fields['student_id'] = studentId;
        request.fields['student_email'] = studentEmail;
        
        for (int i = 0; i < imagePaths.length; i++) {
          final file = await http.MultipartFile.fromPath('images', imagePaths[i]);
          request.files.add(file);
        }
        
        final streamedResponse = await request.send().timeout(
          Duration(seconds: 30 + (imagePaths.length * 10)),
        );
        
        final response = await http.Response.fromStream(streamedResponse);
        
        if (response.statusCode == 200) {
          final result = json.decode(response.body);
          print('✅ Face enrollment successful: ${result['message']}');
          return {'success': true, 'data': result};
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
          return {'success': false, 'error': e.toString()};
        }
        print('⚠️ Enrollment attempt $attempt error: $e, retrying...');
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return {'success': false, 'error': 'Max retries exceeded'};
  }

  Future<Map<String, dynamic>> processPeriodicCapture({
    required String imagePath,
    required String sessionId,
    required DateTime captureTime,
    bool deleteImageAfter = true,
  }) async {
    try {
      print('📸 Processing periodic attendance for session: $sessionId');
      
      final uri = Uri.parse('$BASE_URL/api/attendance/periodic');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['session_id'] = sessionId;
      request.fields['capture_time'] = captureTime.toIso8601String();
      
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found: $imagePath');
      }
      
      final multipartFile = await http.MultipartFile.fromPath('image', imagePath);
      request.files.add(multipartFile);
      
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
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
        return {'success': true, 'data': result};
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to process attendance');
      }
    } catch (e) {
      print('❌ Periodic attendance processing error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> startClassSession({
    required String classId,
    required String teacherEmail,
    required String initialImagePath,
    int durationHours = 2,
    int captureIntervalMinutes = 5,
    int onTimeLimitMinutes = 30,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$BASE_URL/api/class/start-session'));
      
      request.fields['class_id'] = classId;
      request.fields['teacher_email'] = teacherEmail;
      request.fields['duration_hours'] = durationHours.toString();
      request.fields['capture_interval_minutes'] = captureIntervalMinutes.toString();
      request.fields['on_time_limit_minutes'] = onTimeLimitMinutes.toString();
      
      final file = await http.MultipartFile.fromPath('initial_image', initialImagePath);
      request.files.add(file);
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final result = json.decode(responseBody);
        print('✅ Class session started successfully');
        return {'success': true, 'data': result};
      } else {
        final error = json.decode(responseBody);
        throw Exception(error['detail'] ?? 'Failed to start class session');
      }
    } catch (e) {
      print('❌ Error starting class session: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==================== Data Retrieval ====================
  
  Future<List<AttendanceRecordModel>> getSessionRecords(String sessionId) async {
    try {
      final response = await _supabase
          .from('attendance_records')
          .select('''
            *,
            users!attendance_records_student_email_fkey(full_name, school_id)
          ''')
          .eq('session_id', sessionId)
          .order('check_in_time');

      return response.map((record) => AttendanceRecordModel.fromJson(record)).toList();
    } catch (e) {
      throw Exception('Failed to get attendance records: $e');
    }
  }

  Future<List<AttendanceSessionModel>> getClassSessions(String classId) async {
    try {
      final response = await _supabase
          .from('attendance_sessions')
          .select()
          .eq('class_id', classId)
          .order('start_time', ascending: false);

      return response.map((session) => AttendanceSessionModel.fromJson(session)).toList();
    } catch (e) {
      throw Exception('Failed to get sessions: $e');
    }
  }

  Future<List<AttendanceRecordModel>> getStudentHistory(String studentEmail) async {
    try {
      final response = await _supabase
          .from('attendance_records')
          .select('''
            *,
            attendance_sessions!inner(
              class_id,
              start_time,
              end_time,
              classes!inner(class_name)
            )
          ''')
          .eq('student_email', studentEmail)
          .order('check_in_time', ascending: false);

      return response.map((record) => AttendanceRecordModel.fromJson(record)).toList();
    } catch (e) {
      throw Exception('Failed to get attendance history: $e');
    }
  }

  // ==================== Utilities ====================
  
  Future<Map<String, dynamic>> checkServerHealth() async {
    try {
      final response = await _client.get(
        Uri.parse('$BASE_URL/health'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return {'healthy': true, 'data': json.decode(response.body)};
      } else {
        return {'healthy': false, 'error': 'Server returned ${response.statusCode}'};
      }
    } catch (e) {
      return {'healthy': false, 'error': e.toString()};
    }
  }

  Future<bool> testServerConnection() async {
    try {
      final result = await checkServerHealth();
      return result['healthy'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> testWebcamConnection(WebcamConfigModel config) async {
    try {
      final response = await http.get(
        Uri.parse(config.captureUrl),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<String> saveImageToAppDirectory(Uint8List imageBytes, {String? filename}) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = filename ?? 'attendance_$timestamp.jpg';
      final String savedPath = path.join(appDir.path, 'attendance_images', fileName);
      
      final Directory imageDir = Directory(path.dirname(savedPath));
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }
      
      final File imageFile = File(savedPath);
      await imageFile.writeAsBytes(imageBytes);
      
      print('💾 Image saved: $savedPath');
      return savedPath;
    } catch (e) {
      print('❌ Error saving image: $e');
      throw Exception('Failed to save image: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}