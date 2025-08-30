// lib/presentation/screens/attendance/enhanced_teacher_attendance_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/unified_attendance_service.dart';
import 'package:myproject2/data/services/unified_camera_service.dart';
import 'package:myproject2/core/service_locator.dart'; // เพิ่ม import

class EnhancedTeacherAttendanceScreen extends StatefulWidget {
  final String classId;
  final String className;

  const EnhancedTeacherAttendanceScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<EnhancedTeacherAttendanceScreen> createState() => 
      _EnhancedTeacherAttendanceScreenState();
}

class _EnhancedTeacherAttendanceScreenState 
    extends State<EnhancedTeacherAttendanceScreen> {
  
  // ใช้ service locator แทนการสร้าง instance ใหม่
  late final UnifiedAttendanceService _attendanceService;
  late final UnifiedCameraService _cameraService;
  late final AuthService _authService;
  
  // Session state
  AttendanceSessionModel? _currentSession;
  List<AttendanceRecordModel> _attendanceRecords = [];
  Timer? _refreshTimer;
  
  // UI state
  bool _isLoading = false;
  bool _isSessionActive = false;
  bool _isCameraReady = false;
  bool _isServerHealthy = false;
  bool _isPeriodicCaptureActive = false;
  
  // Session configuration
  int _sessionDurationHours = 2;
  int _captureIntervalMinutes = 5;
  int _onTimeLimitMinutes = 30;
  
  // Statistics
  Map<String, dynamic> _sessionStats = {};
  Map<String, dynamic> _cameraStats = {};
  Map<String, dynamic> _serverHealth = {};
  
  // Error handling
  String? _lastError;
  List<String> _errorHistory = [];
  int _totalSnapshots = 0;
  int _successfulCaptures = 0;
  int _facesDetected = 0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stopPeriodicCapture();
    _clearCameraCallbacks();
    super.dispose();
  }

  void _initializeServices() {
    // ใช้ service locator
    _attendanceService = serviceLocator<UnifiedAttendanceService>();
    _cameraService = serviceLocator<UnifiedCameraService>();
    _authService = serviceLocator<AuthService>();
    
    _setupCameraCallbacks();
    _initializeSystem();
  }

  void _setupCameraCallbacks() {
    // Callback เมื่อถ่ายรูปสำเร็จ
    _cameraService.onImageCaptured = (imagePath, captureTime) {
      print('📸 Snapshot captured: ${imagePath.split('/').last} at $captureTime');
      setState(() {
        _totalSnapshots++;
      });
      _showSnackBar('📸 Snapshot captured - processing...', Colors.blue);
      
      // Process the captured image for attendance
      _processCapture(imagePath, captureTime);
    };

    // Callback เมื่อเกิดข้อผิดพลาด
    _cameraService.onError = (error) {
      print('❌ Camera error: $error');
      _addError('Camera: $error');
      _showSnackBar('❌ Camera error: $error', Colors.red);
    };

    // Callback เมื่อสถานะกล้องเปลี่ยน (แก้ไขจาก onStatusChanged)
    _cameraService.onStateChanged = (state) {
      print('📸 Camera state: $state');
      setState(() {
        _isCameraReady = state == CameraState.ready;
      });
    };

    // Callback เมื่อสถิติอัปเดต
    _cameraService.onStatsUpdated = (stats) {
      setState(() {
        _cameraStats = stats;
      });
    };
  }

  void _clearCameraCallbacks() {
    _cameraService.onImageCaptured = null;
    _cameraService.onError = null;
    _cameraService.onStateChanged = null;
    _cameraService.onStatsUpdated = null;
  }

  // Method สำหรับประมวลผล capture
  Future<void> _processCapture(String imagePath, DateTime captureTime) async {
    try {
      if (_currentSession == null) {
        print('⚠️ No active session for processing capture');
        return;
      }

      // ส่งรูปไปประมวลผลที่ server (แก้ไขจาก processPeriodicAttendance)
      final result = await _attendanceService.processPeriodicCapture(
        imagePath: imagePath,
        sessionId: _currentSession!.id,
        captureTime: captureTime,
        deleteImageAfter: true,
      );

      if (result['success']) {
        final data = result['data'];
        final facesDetected = data['faces_detected'] as int? ?? 0;
        final newRecords = data['new_attendance_records'] as int? ?? 0;
        
        setState(() {
          _successfulCaptures++;
          _facesDetected += facesDetected;
        });
        
        print('✅ Attendance processed: $result');
        
        if (facesDetected > 0) {
          _showSnackBar('✅ Detected $facesDetected face(s), $newRecords new records', Colors.green);
          await _loadSessionRecords(); // แก้ไขจาก _loadAttendanceRecords
        } else {
          _showSnackBar('📷 No faces detected in snapshot', Colors.orange);
        }
      } else {
        print('❌ Failed to process attendance: ${result['error']}');
        _showSnackBar('❌ Processing failed: ${result['error']}', Colors.red);
      }

    } catch (e) {
      print('❌ Error processing capture: $e');
      _showSnackBar('❌ Processing error: $e', Colors.red);
    }
  }

  Future<void> _initializeSystem() async {
    setState(() => _isLoading = true);
    
    try {
      // Check server health first
      await _checkServerHealth();
      
      // Initialize camera
      final cameraInitialized = await _cameraService.initialize();
      if (!cameraInitialized) {
        throw Exception('Failed to initialize camera');
      }
      
      // Load current session
      await _loadCurrentSession();
      
      _showSnackBar('🎯 System ready for attendance tracking', Colors.green);
      
    } catch (e) {
      _addError('Initialization: $e');
      _showErrorDialog('Initialization Failed', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkServerHealth() async {
    try {
      final health = await _attendanceService.checkServerHealth();
      setState(() {
        _serverHealth = health;
        _isServerHealthy = health['healthy'] == true;
      });
      
      if (!_isServerHealthy) {
        throw Exception('Face recognition server is not available');
      }
      
      print('✅ Server health check passed');
    } catch (e) {
      setState(() => _isServerHealthy = false);
      throw Exception('Server health check failed: $e');
    }
  }

  Future<void> _loadCurrentSession() async {
    try {
      // แก้ไขจาก getActiveSessionForClass เป็น getActiveSession
      final session = await _attendanceService.getActiveSession(widget.classId);
      
      setState(() {
        _currentSession = session;
        _isSessionActive = session?.isActive ?? false;
      });

      if (session != null) {
        await _loadSessionRecords();
        await _loadSessionStatistics();
        _startAutoRefresh();
        
        // If session is active and camera is ready, start capture
        if (_isSessionActive && _isCameraReady) {
          await _resumePeriodicCapture();
        }
      }
    } catch (e) {
      _addError('Load session: $e');
      print('❌ Error loading current session: $e');
    }
  }

  // แก้ไขจาก _loadAttendanceRecords เป็น _loadSessionRecords
  Future<void> _loadSessionRecords() async {
    if (_currentSession == null) return;

    try {
      // แก้ไขจาก getAttendanceRecords เป็น getSessionRecords
      final records = await _attendanceService.getSessionRecords(_currentSession!.id);
      setState(() => _attendanceRecords = records);
    } catch (e) {
      _addError('Load records: $e');
      print('❌ Error loading attendance records: $e');
    }
  }

  Future<void> _loadSessionStatistics() async {
    if (_currentSession == null) return;

    try {
      // ลบ getSessionStatistics method ที่ไม่มีใน UnifiedAttendanceService
      // แทนที่ด้วยการคำนวณ stats เอง
      final stats = _calculateSessionStatistics();
      setState(() => _sessionStats = stats);
    } catch (e) {
      print('⚠️ Error loading session statistics: $e');
    }
  }

  Map<String, dynamic> _calculateSessionStatistics() {
    if (_attendanceRecords.isEmpty) {
      return {'statistics': {'total_students': 0, 'present_count': 0, 'late_count': 0, 'attendance_rate': 0.0}};
    }

    final presentCount = _attendanceRecords.where((r) => r.status == 'present').length;
    final lateCount = _attendanceRecords.where((r) => r.status == 'late').length;
    final totalStudents = _attendanceRecords.length;
    final attendanceRate = totalStudents > 0 ? (presentCount + lateCount) / totalStudents : 0.0;

    return {
      'statistics': {
        'total_students': totalStudents,
        'present_count': presentCount,
        'late_count': lateCount,
        'attendance_rate': attendanceRate,
      }
    };
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isSessionActive && _currentSession != null) {
        _loadSessionRecords(); // แก้ไขจาก _loadAttendanceRecords
        _loadSessionStatistics();
      } else {
        timer.cancel();
      }
    });
  }

  // ========== 📍 Start Class Workflow ==========
  
  Future<void> _startAttendanceSession() async {
    if (!_isCameraReady || !_isServerHealthy) {
      _showSnackBar('Camera or server not ready', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('🚀 Starting enhanced attendance session...');
      
      // 📸 ถ่ายรูปเริ่มคาบเรียนก่อน (แก้ไขจาก captureSingleImage)
      final imagePath = await _cameraService.captureImage();
      if (imagePath == null) {
        throw Exception('Failed to capture initial image');
      }
      
      // 🎯 เริ่มคาบเรียนพร้อมส่งรูปไป FastAPI
      final result = await _attendanceService.startClassSession(
        classId: widget.classId,
        teacherEmail: _authService.getCurrentUserEmail()!,
        initialImagePath: imagePath,
        durationHours: _sessionDurationHours,
        captureIntervalMinutes: _captureIntervalMinutes,
        onTimeLimitMinutes: _onTimeLimitMinutes,
      );

      if (!result['success']) {
        throw Exception(result['error'] ?? 'Failed to start session');
      }

      // 📊 สร้าง session ใน Supabase (แก้ไขจาก createAttendanceSession เป็น createSession)
      final supabaseSession = await _attendanceService.createSession(
        classId: widget.classId,
        durationHours: _sessionDurationHours,
        onTimeLimitMinutes: _onTimeLimitMinutes,
      );

      setState(() {
        _currentSession = supabaseSession;
        _isSessionActive = true;
        _attendanceRecords = [];
        _sessionStats = {};
        _totalSnapshots = 1; // เริ่มต้นด้วย initial snapshot
        _successfulCaptures = 1;
        _facesDetected = result['data']?['faces_detected'] ?? 0;
      });

      // 🔄 เริ่ม periodic capture
      await _startPeriodicCapture();
      
      _startAutoRefresh();
      _showSnackBar('🎯 Class started! Initial attendance captured automatically', Colors.green);
      
      // ลบรูปชั่วคราว
      try {
        await File(imagePath).delete();
      } catch (e) {
        print('Warning: Could not delete temporary image: $e');
      }
      
    } catch (e) {
      _addError('Start session: $e');
      _showErrorDialog('Failed to Start Session', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _takeStartClassSnapshot() async {
    try {
      print('📸 Taking start-of-class snapshot...');
      final imagePath = await _cameraService.captureImage(); // แก้ไขจาก captureSingleImage
      
      if (imagePath != null && _currentSession != null) {
        final result = await _attendanceService.processPeriodicCapture( // แก้ไข method name
          imagePath: imagePath,
          sessionId: _currentSession!.id,
          captureTime: DateTime.now(),
        );
        
        if (result['success']) {
          final facesDetected = result['data']?['faces_detected'] ?? 0;
          _showSnackBar('🎯 Start snapshot: $facesDetected face(s) detected', Colors.blue);
        }
      }
    } catch (e) {
      print('⚠️ Error in start snapshot: $e');
    }
  }

  // ========== 📍 During Class - Periodic Capture ==========
  
  Future<void> _startPeriodicCapture() async {
    if (_currentSession == null || !_isCameraReady) return;

    try {
      // แก้ไข method call ให้ตรงกับ UnifiedCameraService
      await _cameraService.startPeriodicCapture(
        sessionId: _currentSession!.id, // แก้ไขจาก session: เป็น sessionId:
        interval: Duration(minutes: _captureIntervalMinutes),
        onCapture: (imagePath, captureTime) async {
          await _handlePeriodicCapture(imagePath, captureTime);
        },
      );
      
      setState(() {
        _isPeriodicCaptureActive = true;
      });
      
      print('📸 Periodic capture started - every $_captureIntervalMinutes minutes');
      _showSnackBar('📷 Auto-capture started every $_captureIntervalMinutes minutes', Colors.blue);
    } catch (e) {
      _addError('Start capture: $e');
      _showSnackBar('Failed to start periodic capture: $e', Colors.red);
    }
  }

  Future<void> _handlePeriodicCapture(String imagePath, DateTime captureTime) async {
    try {
      print('📷 Processing periodic capture: ${imagePath.split('/').last}');
      
      setState(() {
        _totalSnapshots++;
      });
      
      // Process attendance
      await _processCapture(imagePath, captureTime);
      
    } catch (e) {
      print('❌ Error in periodic capture handler: $e');
    }
  }

  Future<void> _resumePeriodicCapture() async {
    if (_currentSession == null || !_isSessionActive) return;

    try {
      if (!_cameraService.isCapturing) { // แก้ไขจาก isRunning
        await _startPeriodicCapture();
        print('📸 Resumed periodic capture for existing session');
      }
    } catch (e) {
      print('⚠️ Error resuming capture: $e');
    }
  }

  void _stopPeriodicCapture() {
    _cameraService.stopPeriodicCapture();
    
    setState(() {
      _isPeriodicCaptureActive = false;
    });
    
    print('⏹️ Stopped periodic capture');
  }

  // ========== 📍 End Class Workflow ==========
  
  Future<void> _endAttendanceSession() async {
    if (_currentSession == null) return;

    final confirm = await _showConfirmDialog(
      'End Class Session',
      'Are you sure you want to end the class?\n\n'
      'This will:\n'
      '• Take a final attendance snapshot\n'
      '• Stop automatic face detection\n'
      '• Finalize attendance records\n'
      '• Generate session summary',
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // Stop periodic capture first
      _stopPeriodicCapture();
      
      // 📍 Take final snapshot when ending class
      await _takeFinalClassSnapshot();
      
      // End session (แก้ไขจาก endAttendanceSession เป็น endSession)
      await _attendanceService.endSession(_currentSession!.id);
      
      // Final statistics load
      await _loadSessionStatistics();
      
      setState(() {
        _currentSession = null;
        _isSessionActive = false;
      });

      _refreshTimer?.cancel();
      
      // Show session summary
      _showSessionSummaryDialog();
      
    } catch (e) {
      _addError('End session: $e');
      _showErrorDialog('Failed to End Session', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _takeFinalClassSnapshot() async {
    try {
      print('📸 Taking final class snapshot...');
      _showSnackBar('📸 Taking final attendance snapshot...', Colors.blue);
      
      final imagePath = await _cameraService.captureImage(); // แก้ไขจาก captureSingleImage
      
      if (imagePath != null && _currentSession != null) {
        final result = await _attendanceService.processPeriodicCapture( // แก้ไข method name
          imagePath: imagePath,
          sessionId: _currentSession!.id,
          captureTime: DateTime.now(),
        );
        
        if (result['success']) {
          final facesDetected = result['data']?['faces_detected'] ?? 0;
          print('✅ Final snapshot processed: $facesDetected faces');
          _showSnackBar('🎯 Final snapshot: $facesDetected face(s) detected', Colors.green);
        }
      }
    } catch (e) {
      print('⚠️ Error in final capture: $e');
    }
  }

  // ========== Manual Actions ==========
  
  Future<void> _captureManualSnapshot() async {
    if (!_isCameraReady || _currentSession == null) return;

    try {
      setState(() => _isLoading = true);
      
      _showSnackBar('📸 Taking manual snapshot...', Colors.blue);
      
      final imagePath = await _cameraService.captureImage(); // แก้ไขจาก captureSingleImage
      if (imagePath == null) return;

      // ประมวลผลรูป
      await _processCapture(imagePath, DateTime.now());

      // ลบรูปชั่วคราว
      try {
        await File(imagePath).delete();
      } catch (e) {
        print('Warning: Could not delete temporary image: $e');
      }

    } catch (e) {
      _addError('Manual capture: $e');
      _showSnackBar('❌ Manual snapshot error: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ========== Session Summary ==========
  
  void _showSessionSummaryDialog() {
    final stats = _sessionStats['statistics'] as Map<String, dynamic>? ?? {};
    final totalStudents = stats['total_students'] ?? 0;
    final presentCount = stats['present_count'] ?? 0;
    final lateCount = stats['late_count'] ?? 0;
    final attendanceRate = stats['attendance_rate'] ?? 0.0;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.summarize, color: Colors.green),
            SizedBox(width: 12),
            Text('Class Session Summary'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Class: ${widget.className}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              _buildSummaryRow('Total Students', '$totalStudents'),
              _buildSummaryRow('Present', '$presentCount'),
              _buildSummaryRow('Late', '$lateCount'),
              _buildSummaryRow('Attendance Rate', '${(attendanceRate * 100).toStringAsFixed(1)}%'),
              
              const Divider(height: 24),
              
              _buildSummaryRow('Total Snapshots', '$_totalSnapshots'),
              _buildSummaryRow('Successful Captures', '$_successfulCaptures'),
              _buildSummaryRow('Faces Detected', '$_facesDetected'),
              _buildSummaryRow('Face Detection Rate', 
                _successfulCaptures > 0 
                  ? '${(_facesDetected / _successfulCaptures).toStringAsFixed(1)} faces/snapshot'
                  : '0 faces/snapshot'),
              
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Class session completed successfully!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ========== Error Handling ==========
  
  void _addError(String error) {
    setState(() {
      _lastError = error;
      _errorHistory.insert(0, '${DateTime.now().toIso8601String()}: $error');
      if (_errorHistory.length > 10) {
        _errorHistory = _errorHistory.take(10).toList();
      }
    });
  }

  // ========== UI Helpers ==========
  
  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              backgroundColor == Colors.green ? Icons.check_circle :
              backgroundColor == Colors.red ? Icons.error :
              backgroundColor == Colors.orange ? Icons.warning :
              Icons.info,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ========== UI Build Methods ==========
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance Tracking - ${widget.className}'),
        centerTitle: true,
        backgroundColor: _isSessionActive ? Colors.green.shade400 : null,
        foregroundColor: _isSessionActive ? Colors.white : null,
        actions: [
          IconButton(
            icon: Icon(
              _isServerHealthy ? Icons.cloud_done : Icons.cloud_off,
              color: _isServerHealthy ? Colors.green : Colors.red,
            ),
            onPressed: _showSystemStatus,
            tooltip: 'System Status',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSessionSettings,
            tooltip: 'Session Settings',
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSystemStatusBar(),
                _buildCameraPreview(),
                _buildSessionControl(),
                _buildSessionStatus(),
                Expanded(child: _buildAttendanceList()),
              ],
            ),
    );
  }

  Widget _buildSystemStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _isServerHealthy && _isCameraReady 
          ? Colors.green.shade50 
          : Colors.red.shade50,
      child: Row(
        children: [
          Icon(
            _isServerHealthy ? Icons.check_circle : Icons.error,
            color: _isServerHealthy ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            _isServerHealthy ? 'Server Online' : 'Server Offline',
            style: TextStyle(
              fontSize: 12,
              color: _isServerHealthy ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Icon(
            _isCameraReady ? Icons.camera_alt : Icons.camera_alt_outlined,
            color: _isCameraReady ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            _isCameraReady ? 'Camera Ready' : 'Camera Not Ready',
            style: TextStyle(
              fontSize: 12,
              color: _isCameraReady ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (_isSessionActive) ...[
            Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
            const SizedBox(width: 4),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Container(
        height: 200,
        child: _isCameraReady && _cameraService.controller != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    CameraPreview(_cameraService.controller!),
                    
                    // Status overlay
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isPeriodicCaptureActive 
                                  ? Icons.fiber_manual_record 
                                  : Icons.pause_circle,
                              color: _isPeriodicCaptureActive ? Colors.red : Colors.orange,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isPeriodicCaptureActive ? 'AUTO-CAPTURE' : 'PAUSED',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Snapshot counter
                    if (_isSessionActive)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Snapshots: $_totalSnapshots',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.camera_alt,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isCameraReady ? 'Camera Ready' : 'Initializing camera...',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSessionControl() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Class Session Control',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (!_isSessionActive)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCameraReady && _isServerHealthy && !_isLoading
                      ? _startAttendanceSession
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('🎯 Start Class & Begin Tracking'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _captureManualSnapshot,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('📸 Manual Snapshot'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _endAttendanceSession,
                      icon: const Icon(Icons.stop),
                      label: const Text('🏁 End Class'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionStatus() {
    if (_currentSession == null) return const SizedBox();

    final session = _currentSession!;
    final now = DateTime.now();
    final timeRemaining = session.endTime.difference(now);

    return Card(
      margin: const EdgeInsets.all(16),
      color: _isSessionActive ? Colors.green.shade50 : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isSessionActive ? Icons.radio_button_checked : Icons.stop_circle,
                  color: _isSessionActive ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _isSessionActive ? 'Session Active - Auto Tracking' : 'Session Ended',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Time and capture info
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    'Time Remaining',
                    timeRemaining.isNegative ? 'Ended' : 
                    '${timeRemaining.inHours}h ${timeRemaining.inMinutes % 60}m',
                    timeRemaining.isNegative ? Colors.red : Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    'Auto Interval',
                    '${_captureIntervalMinutes}min',
                    Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Detection and processing info
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    'Snapshots',
                    '$_successfulCaptures/$_totalSnapshots',
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    'Faces Detected',
                    '$_facesDetected',
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Attendance statistics
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    'Students Present',
                    '${_attendanceRecords.length}',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    'Attendance Rate',
                    '${((_sessionStats['statistics']?['attendance_rate'] ?? 0.0) * 100).toStringAsFixed(1)}%',
                    Colors.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.people, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Live Attendance Records',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_attendanceRecords.length} checked in',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadSessionRecords,
                  tooltip: 'Refresh records',
                ),
              ],
            ),
          ),
          Expanded(
            child: _attendanceRecords.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No attendance records yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Records will appear automatically when faces are detected',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _attendanceRecords.length,
                    itemBuilder: (context, index) {
                      final record = _attendanceRecords[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: record.status == 'present' 
                              ? Colors.green.shade100 
                              : record.status == 'late' 
                                  ? Colors.orange.shade100 
                                  : Colors.red.shade100,
                          child: Icon(
                            record.status == 'present' ? Icons.check : 
                            record.status == 'late' ? Icons.access_time : Icons.close,
                            color: record.status == 'present' 
                                ? Colors.green 
                                : record.status == 'late' 
                                    ? Colors.orange 
                                    : Colors.red,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              record.studentId ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            if (record.faceMatchScore != null && record.faceMatchScore! > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_user, size: 12, color: Colors.blue.shade700),
                                    const SizedBox(width: 2),
                                    Text(
                                      'AI',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${record.checkInTime.toLocal().toString().split(' ')[1].substring(0, 5)} - ${record.status.toUpperCase()}'),
                            if (record.faceMatchScore != null && record.faceMatchScore! > 0)
                              Text(
                                'Auto-detected (${(record.faceMatchScore! * 100).toStringAsFixed(1)}% match)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: record.status == 'present' 
                                ? Colors.green 
                                : record.status == 'late' 
                                    ? Colors.orange 
                                    : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            record.status.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showSystemStatus() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info, color: Colors.blue),
            SizedBox(width: 12),
            Text('System Status'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatusSection('🖥️ Server Health', _serverHealth),
              const SizedBox(height: 16),
              _buildStatusSection('📸 Camera Statistics', _cameraStats),
              if (_sessionStats.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildStatusSection('📊 Session Statistics', _sessionStats),
              ],
              if (_errorHistory.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildStatusSection('⚠️ Recent Errors', 
                  {'errors': _errorHistory.take(3).toList()}),
              ],
            ],
          ),
        ),
        actions: [
          if (_errorHistory.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _errorHistory.clear());
                Navigator.of(context).pop();
              },
              child: const Text('Clear Errors'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(String title, Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            data.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\n'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  void _showSessionSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.purple),
            SizedBox(width: 12),
            Text('Session Settings'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Settings can only be changed before starting a session',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              ListTile(
                title: const Text('Session Duration'),
                subtitle: Text('$_sessionDurationHours hours'),
                trailing: DropdownButton<int>(
                  value: _sessionDurationHours,
                  items: [1, 2, 3, 4, 6, 8].map((hours) => 
                    DropdownMenuItem(value: hours, child: Text('$hours hours'))
                  ).toList(),
                  onChanged: _isSessionActive ? null : (value) {
                    if (value != null) {
                      setState(() => _sessionDurationHours = value);
                    }
                  },
                ),
              ),
              ListTile(
                title: const Text('Auto-Capture Interval'),
                subtitle: Text('Every $_captureIntervalMinutes minutes'),
                trailing: DropdownButton<int>(
                  value: _captureIntervalMinutes,
                  items: [3, 5, 10, 15, 20].map((minutes) => 
                    DropdownMenuItem(value: minutes, child: Text('$minutes min'))
                  ).toList(),
                  onChanged: _isSessionActive ? null : (value) {
                    if (value != null) {
                      setState(() => _captureIntervalMinutes = value);
                    }
                  },
                ),
              ),
              ListTile(
                title: const Text('On-time Limit'),
                subtitle: Text('$_onTimeLimitMinutes minutes after start'),
                trailing: DropdownButton<int>(
                  value: _onTimeLimitMinutes,
                  items: [15, 30, 45, 60].map((minutes) => 
                    DropdownMenuItem(value: minutes, child: Text('$minutes min'))
                  ).toList(),
                  onChanged: _isSessionActive ? null : (value) {
                    if (value != null) {
                      setState(() => _onTimeLimitMinutes = value);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}