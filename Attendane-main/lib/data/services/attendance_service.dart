// lib/data/services/attendance_service.dart
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/models/webcam_config_model.dart';
import 'package:myproject2/data/services/auth_service.dart'; // Import AuthService จากไฟล์ที่ถูกต้อง
import 'dart:math' as Math;

// ==================== Simple Attendance Service ====================

class SimpleAttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService(); // ใช้ AuthService จากไฟล์อื่น

  // ==================== Session Management ====================
  
  Future<AttendanceSessionModel> createAttendanceSession({
    required String classId,
    required int durationHours,
    required int onTimeLimitMinutes,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Teacher not authenticated');
      }

      final now = DateTime.now();
      final sessionData = {
        'class_id': classId,
        'teacher_email': user.email,
        'start_time': now.toIso8601String(),
        'end_time': now.add(Duration(hours: durationHours)).toIso8601String(),
        'on_time_limit_minutes': onTimeLimitMinutes,
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

  Future<AttendanceSessionModel?> getActiveSessionForClass(String classId) async {
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
        await endAttendanceSession(session.id);
        return null;
      }
      
      return session;
    } catch (e) {
      throw Exception('Failed to get active session: $e');
    }
  }

  Future<void> endAttendanceSession(String sessionId) async {
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

  Future<List<AttendanceRecordModel>> getAttendanceRecords(String sessionId) async {
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

  Future<List<AttendanceSessionModel>> getClassAttendanceSessions(String classId) async {
    try {
      final response = await _supabase
          .from('attendance_sessions')
          .select()
          .eq('class_id', classId)
          .order('start_time', ascending: false);

      return response.map((session) => AttendanceSessionModel.fromJson(session)).toList();
    } catch (e) {
      throw Exception('Failed to get attendance sessions: $e');
    }
  }

  Future<List<AttendanceRecordModel>> getStudentAttendanceHistory(String studentEmail) async {
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

  Future<AttendanceRecordModel> simpleCheckIn({
    required String sessionId,
    required WebcamConfigModel webcamConfig,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

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

  // เพิ่ม method สำหรับ Face Recognition Check-in
  Future<AttendanceRecordModel> faceRecognitionCheckIn({
    required String sessionId,
    required List<double> faceEmbedding,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

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
      if (userProfile == null) {
        throw Exception('User profile not found');
      }

      final studentId = userProfile['school_id'];

      // Verify face using AuthService
      final isVerified = await _authService.verifyFace(studentId, faceEmbedding);
      if (!isVerified) {
        throw Exception('Face verification failed');
      }

      // Determine status
      final checkInTime = DateTime.now();
      final status = session.isOnTime(checkInTime) ? 'present' : 'late';

      // Calculate face match score (simplified)
      final faceMatchScore = 0.95; // This should come from actual face comparison

      // Save record with face verification
      final recordData = {
        'session_id': sessionId,
        'student_email': user.email,
        'student_id': studentId,
        'check_in_time': checkInTime.toIso8601String(),
        'status': status,
        'face_match_score': faceMatchScore,
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
}

// ==================== Full Attendance Service (ถ้าต้องการใช้ในอนาคต) ====================

class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();

  // TODO: Implement advanced attendance features here
  // เช่น bulk import, advanced reporting, analytics, etc.

  Future<void> bulkCreateSessions() async {
    // TODO: Implement bulk session creation
    throw UnimplementedError('Bulk session creation not implemented yet');
  }

  Future<Map<String, dynamic>> getAttendanceAnalytics(String classId) async {
    // TODO: Implement attendance analytics
    throw UnimplementedError('Attendance analytics not implemented yet');
  }

  Future<void> exportAttendanceReport(String classId) async {
    // TODO: Implement attendance report export
    throw UnimplementedError('Attendance report export not implemented yet');
  }
}