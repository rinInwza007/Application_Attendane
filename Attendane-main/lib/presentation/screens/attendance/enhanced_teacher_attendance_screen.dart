// lib/presentation/screens/attendance/enhanced_teacher_attendance_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/services/enhanced_attendance_service.dart';
import 'package:myproject2/data/services/enhanced_periodic_camera_service.dart';
import 'package:myproject2/data/services/attendance_service.dart';
import 'package:myproject2/data/services/auth_service.dart';


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
  
  final EnhancedAttendanceService _attendanceService = EnhancedAttendanceService();
  final EnhancedPeriodicCameraService _cameraService = EnhancedPeriodicCameraService();
  final SimpleAttendanceService _simpleAttendanceService = SimpleAttendanceService();
  final AuthService _authService = AuthService();
  
  // Session state
  AttendanceSessionModel? _currentSession;
  List<AttendanceRecordModel> _attendanceRecords = [];
  Timer? _refreshTimer;
  
  // UI state
  bool _isLoading = false;
  bool _isSessionActive = false;
  bool _isCameraReady = false;
  bool _isServerHealthy = false;
  
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
  _setupCameraCallbacks();
  _initializeServices();
}

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _cameraService.dispose();
    _attendanceService.dispose();
    super.dispose();
  }

  void _setupCameraCallbacks() {
  // Callback เมื่อถ่ายรูปสำเร็จ
  _cameraService.onImageCaptured = (imagePath, captureTime) {
    print('📸 Snapshot captured: ${imagePath.split('/').last} at $captureTime');
    setState(() {
      _totalSnapshots++;
    });
    _showSnackBar('📸 Snapshot captured - processing...', Colors.blue);
  };

  _cameraService.onAttendanceProcessed = (result) {
    final facesDetected = result['faces_detected'] as int? ?? 0;
    setState(() => _facesDetected += facesDetected);
    _showSnackBar('✅ Auto-processed: $facesDetected faces', Colors.green);
  };

  _cameraService.onError = (error) {
    _showSnackBar('❌ Camera error: $error', Colors.red);
  };

  _cameraService.onStatusChanged = (status) {
    setState(() => _isCameraReady = status == CameraServiceStatus.ready);
  };

    // Callback เมื่อประมวลผล attendance สำเร็จ
    _cameraService.onAttendanceProcessed = (result) {
    print('✅ Attendance processed: $result');
    final facesDetected = result['faces_detected'] as int? ?? 0;
    final newRecords = result['new_attendance_records'] as int? ?? 0;
    
    setState(() {
      _successfulCaptures++;
      _facesDetected += facesDetected;
    });
    
    if (facesDetected > 0) {
      _showSnackBar('✅ Detected $facesDetected face(s), $newRecords new records', Colors.green);
      _loadAttendanceRecords(); // Refresh records
    } else {
      _showSnackBar('📷 No faces detected in snapshot', Colors.orange);
    }
  };

    // Callback เมื่อเกิดข้อผิดพลาด
    _cameraService.onError = (error) {
    print('❌ Camera error: $error');
    _addError('Camera: $error');
    _showSnackBar('❌ Camera error: $error', Colors.red);
  };

    // Callback เมื่อสถานะกล้องเปลี่ยน
    _cameraService.onStatusChanged = (status) {
    print('📸 Camera status: $status');
    setState(() {
      _isCameraReady = status == CameraServiceStatus.ready || 
                      status == CameraServiceStatus.capturing;
    });
  };

    // Callback เมื่อสถิติอัปเดต
    _cameraService.onStatsUpdated = (stats) {
    setState(() {
      _cameraStats = stats;
    });
  };
}

  Future<void> _initializeServices() async {
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
      final session = await _simpleAttendanceService.getActiveSessionForClass(widget.classId);
      
      setState(() {
        _currentSession = session;
        _isSessionActive = session?.isActive ?? false;
      });

      if (session != null) {
        await _loadAttendanceRecords();
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

  Future<void> _loadAttendanceRecords() async {
    if (_currentSession == null) return;

    try {
      final records = await _simpleAttendanceService.getAttendanceRecords(_currentSession!.id);
      setState(() => _attendanceRecords = records);
    } catch (e) {
      _addError('Load records: $e');
      print('❌ Error loading attendance records: $e');
    }
  }

  Future<void> _loadSessionStatistics() async {
    if (_currentSession == null) return;

    try {
      final stats = await _attendanceService.getSessionStatistics(_currentSession!.id);
      setState(() => _sessionStats = stats);
    } catch (e) {
      print('⚠️ Error loading session statistics: $e');
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isSessionActive && _currentSession != null) {
        _loadAttendanceRecords();
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
    
    // 📸 ถ่ายรูปเริ่มคาบเรียนก่อน
    final imagePath = await _cameraService.captureSingleImage();
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

    // 📊 สร้าง session ใน Supabase (เพื่อใช้กับ Flutter UI)
    final supabaseSession = await _simpleAttendanceService.createAttendanceSession(
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
      _facesDetected = result['faces_detected'] ?? 0;
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
      final imagePath = await _cameraService.captureSingleImage();
      
      if (imagePath != null && _currentSession != null) {
        final result = await _attendanceService.processPeriodicAttendance(
          imagePath: imagePath,
          sessionId: _currentSession!.id,
          captureTime: DateTime.now(),
        );
        
        if (result['success']) {
          final facesDetected = result['faces_detected'] as int? ?? 0;
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
      await _cameraService.startPeriodicCapture(
        session: _currentSession!,
        interval: Duration(minutes: _captureIntervalMinutes),
      );
      
      print('📸 Periodic capture started - every $_captureIntervalMinutes minutes');
      _showSnackBar('📷 Auto-capture started every $_captureIntervalMinutes minutes', Colors.blue);
    } catch (e) {
      _addError('Start capture: $e');
      _showSnackBar('Failed to start periodic capture: $e', Colors.red);
    }
  }

  Future<void> _resumePeriodicCapture() async {
    if (_currentSession == null || !_isSessionActive) return;

    try {
      if (!_cameraService.isRunning) {
        await _startPeriodicCapture();
        print('📸 Resumed periodic capture for existing session');
      }
    } catch (e) {
      print('⚠️ Error resuming capture: $e');
    }
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
      await _cameraService.stopPeriodicCapture();
      
      // 📍 Take final snapshot when ending class
      await _takeFinalClassSnapshot();
      
      // End session in FastAPI
      await _attendanceService.endSession(_currentSession!.id);
      
      // End session in Supabase
      await _simpleAttendanceService.endAttendanceSession(_currentSession!.id);
      
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
      
      final imagePath = await _cameraService.captureSingleImage();
      
      if (imagePath != null && _currentSession != null) {
        final result = await _attendanceService.processPeriodicAttendance(
          imagePath: imagePath,
          sessionId: _currentSession!.id,
          captureTime: DateTime.now(),
        );
        
        if (result['success']) {
          final facesDetected = result['faces_detected'] as int? ?? 0;
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
    
    final imagePath = await _cameraService.captureSingleImage();
    if (imagePath == null) return;

    // ส่งไป FastAPI แทนที่จะใช้ mock data
    final result = await _attendanceService.captureManualAttendance(
      sessionId: _currentSession!.id,
      imagePath: imagePath,
    );

    if (result['success']) {
      final facesDetected = result['faces_detected'] as int? ?? 0;
      _showSnackBar('📷 Manual snapshot: $facesDetected face(s) detected, processing...', Colors.green);
      
      setState(() {
        _totalSnapshots++;
        _successfulCaptures++;
        _facesDetected += facesDetected;
      });
      
      await _loadAttendanceRecords();
      await _loadSessionStatistics();
    } else {
      _showSnackBar('❌ Manual snapshot failed: ${result['error'] ?? 'Unknown error'}', Colors.red);
    }

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
                              _cameraService.isRunning 
                                  ? Icons.fiber_manual_record 
                                  : Icons.pause_circle,
                              color: _cameraService.isRunning ? Colors.red : Colors.orange,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _cameraService.isRunning ? 'AUTO-CAPTURE' : 'PAUSED',
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
    final captureStats = _cameraStats;

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
                  onPressed: _loadAttendanceRecords,
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
                          backgroundColor: record.isPresent 
                              ? Colors.green.shade100 
                              : record.isLate 
                                  ? Colors.orange.shade100 
                                  : Colors.red.shade100,
                          child: Icon(
                            record.isPresent ? Icons.check : 
                            record.isLate ? Icons.access_time : Icons.close,
                            color: record.isPresent 
                                ? Colors.green 
                                : record.isLate 
                                    ? Colors.orange 
                                    : Colors.red,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              record.studentId,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            if (record.hasFaceMatch)
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
                            Text('${record.timeOnly} - ${record.statusInThai}'),
                            if (record.hasFaceMatch)
                              Text(
                                'Auto-detected (${record.faceMatchPercentage.toStringAsFixed(1)}% match)',
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
                            color: record.isPresent 
                                ? Colors.green 
                                : record.isLate 
                                    ? Colors.orange 
                                    : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            record.statusDisplayText,
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
                      