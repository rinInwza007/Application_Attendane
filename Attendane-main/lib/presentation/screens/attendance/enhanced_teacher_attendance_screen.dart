// lib/presentation/screens/attendance/enhanced_teacher_attendance_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/services/enhanced_attendance_service.dart';
import 'package:myproject2/data/services/enhanced_periodic_camera_service.dart';
import 'package:myproject2/data/services/attendance_service.dart'; // เพิ่ม import นี้
import 'package:myproject2/data/services/auth_service.dart';
import 'package:camera/camera.dart';

class EnhancedTeacherAttendanceScreen extends StatefulWidget {
  final String classId;
  final String className;

  const EnhancedTeacherAttendanceScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<EnhancedTeacherAttendanceScreen> createState() => _EnhancedTeacherAttendanceScreenState();
}

class _EnhancedTeacherAttendanceScreenState extends State<EnhancedTeacherAttendanceScreen> {
  final EnhancedAttendanceService _attendanceService = EnhancedAttendanceService();
  final EnhancedPeriodicCameraService _cameraService = EnhancedPeriodicCameraService();
  final SimpleAttendanceService _simpleAttendanceService = SimpleAttendanceService(); // เพิ่ม service นี้
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
    _cameraService.onImageCaptured = (imagePath, captureTime) {
      print('📸 Image captured: $imagePath at $captureTime');
      _showSnackBar('Image captured for attendance processing', Colors.blue);
    };

    _cameraService.onAttendanceProcessed = (result) {
      print('✅ Attendance processed: $result');
      final facesDetected = result['faces_detected'] as int? ?? 0;
      if (facesDetected > 0) {
        _showSnackBar('Detected $facesDetected face(s)', Colors.green);
        _loadAttendanceRecords(); // Refresh records
      }
    };

    _cameraService.onError = (error) {
      print('❌ Camera error: $error');
      _addError('Camera: $error');
      _showSnackBar('Camera error: $error', Colors.red);
    };

    _cameraService.onStatusChanged = (status) {
      print('📸 Camera status: $status');
      setState(() {
        _isCameraReady = status == CameraServiceStatus.ready || 
                        status == CameraServiceStatus.capturing;
      });
    };

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
      // ใช้ SimpleAttendanceService แทน AuthService
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
      // ใช้ SimpleAttendanceService แทน AuthService
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

  // ========== Enhanced Session Management ==========
  
  Future<void> _startAttendanceSession() async {
    if (!_isCameraReady || !_isServerHealthy) {
      _showSnackBar('Camera or server not ready', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('🚀 Starting enhanced attendance session...');
      
      // Create session using FastAPI
      final result = await _attendanceService.createEnhancedSession(
        classId: widget.classId,
        teacherEmail: _authService.getCurrentUserEmail()!,
        durationHours: _sessionDurationHours,
        captureIntervalMinutes: _captureIntervalMinutes,
        onTimeLimitMinutes: _onTimeLimitMinutes,
      );

      if (!result['success']) {
        throw Exception(result['error'] ?? 'Failed to create session');
      }

      // Create corresponding Supabase session using SimpleAttendanceService
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
      });

      // Start periodic capture
      await _startPeriodicCapture();
      
      _startAutoRefresh();
      _showSnackBar('Enhanced attendance session started', Colors.green);
      
    } catch (e) {
      _addError('Start session: $e');
      _showErrorDialog('Failed to Start Session', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startPeriodicCapture() async {
    if (_currentSession == null || !_isCameraReady) return;

    try {
      await _cameraService.startPeriodicCapture(
        session: _currentSession!,
        interval: Duration(minutes: _captureIntervalMinutes),
      );
      
      print('📸 Periodic capture started');
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

  Future<void> _endAttendanceSession() async {
    if (_currentSession == null) return;

    final confirm = await _showConfirmDialog(
      'End Attendance Session',
      'Are you sure you want to end the attendance session?\n\nThis will:\n• Stop automatic face detection\n• Finalize attendance records\n• Generate session report',
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // Stop periodic capture first
      await _cameraService.stopPeriodicCapture();
      
      // Take final attendance snapshot
      await _captureFinalAttendance();
      
      // End session in FastAPI
      await _attendanceService.endSession(_currentSession!.id);
      
      // End session in Supabase using SimpleAttendanceService
      await _simpleAttendanceService.endAttendanceSession(_currentSession!.id);
      
      // Final statistics load
      await _loadSessionStatistics();
      
      setState(() {
        _currentSession = null;
        _isSessionActive = false;
      });

      _refreshTimer?.cancel();
      _showSuccessDialog('Session Ended Successfully', _generateSessionSummary());
      
    } catch (e) {
      _addError('End session: $e');
      _showErrorDialog('Failed to End Session', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _captureFinalAttendance() async {
    try {
      print('📸 Taking final attendance snapshot...');
      final imagePath = await _cameraService.captureSingleImage();
      
      if (imagePath != null && _currentSession != null) {
        // Process final image
        final result = await _attendanceService.processPeriodicAttendance(
          imagePath: imagePath,
          sessionId: _currentSession!.id,
          captureTime: DateTime.now(),
        );
        
        if (result['success']) {
          print('✅ Final attendance processed: ${result['faces_detected']} faces');
        }
      }
    } catch (e) {
      print('⚠️ Error in final capture: $e');
    }
  }

  String _generateSessionSummary() {
    final stats = _sessionStats['statistics'] as Map<String, dynamic>? ?? {};
    final totalStudents = stats['total_students'] ?? 0;
    final presentCount = stats['present_count'] ?? 0;
    final lateCount = stats['late_count'] ?? 0;
    final attendanceRate = stats['attendance_rate'] ?? 0.0;
    
    return '''Session Summary:
• Total Students: $totalStudents
• Present: $presentCount
• Late: $lateCount  
• Attendance Rate: ${(attendanceRate * 100).toStringAsFixed(1)}%
• Face Verification: ${stats['face_verification_rate'] != null ? (stats['face_verification_rate'] * 100).toStringAsFixed(1) : 0}%''';
  }

  // ========== Manual Actions ==========
  
  Future<void> _captureManualAttendance() async {
    if (!_isCameraReady || _currentSession == null) return;

    try {
      setState(() => _isLoading = true);
      
      final imagePath = await _cameraService.captureSingleImage();
      if (imagePath == null) return;

      final result = await _attendanceService.processPeriodicAttendance(
        imagePath: imagePath,
        sessionId: _currentSession!.id,
        captureTime: DateTime.now(),
      );

      if (result['success']) {
        final facesDetected = result['faces_detected'] as int? ?? 0;
        _showSnackBar('Manual capture: $facesDetected face(s) detected', Colors.blue);
        await _loadAttendanceRecords();
      } else {
        _showSnackBar('Manual capture failed: ${result['error']}', Colors.red);
      }

    } catch (e) {
      _addError('Manual capture: $e');
      _showSnackBar('Manual capture error: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
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
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        action: backgroundColor == Colors.red
            ? SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: _showErrorHistory,
              )
            : null,
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
          if (_errorHistory.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showErrorHistory();
              },
              child: const Text('View Errors'),
            ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error History'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _errorHistory.isEmpty
              ? const Center(child: Text('No errors recorded'))
              : ListView.builder(
                  itemCount: _errorHistory.length,
                  itemBuilder: (context, index) {
                    final error = _errorHistory[index];
                    final parts = error.split(': ');
                    final timestamp = parts.isNotEmpty ? parts[0] : '';
                    final message = parts.length > 1 ? parts.sublist(1).join(': ') : error;
                    
                    return ListTile(
                      dense: true,
                      title: Text(
                        message,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        timestamp,
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _errorHistory.clear());
              Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
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
        title: Text('Enhanced Attendance - ${widget.className}'),
        centerTitle: true,
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
          if (_lastError != null)
            GestureDetector(
              onTap: _showErrorHistory,
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange.shade700, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'View Errors',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
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
                              _cameraService.isRunning ? 'RECORDING' : 'PAUSED',
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
              'Enhanced Session Management',
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
                  label: const Text('Start Enhanced Session'),
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
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _captureManualAttendance,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Manual Capture'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _endAttendanceSession,
                      icon: const Icon(Icons.stop),
                      label: const Text('End Session'),
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
                  _isSessionActive ? 'Enhanced Session Active' : 'Session Ended',
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
                    'Captures',
                    '${captureStats['successfulCaptures'] ?? 0}/${captureStats['totalCaptures'] ?? 0}',
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
                    'Faces Detected',
                    '${captureStats['detectedFaces'] ?? 0}',
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    'Attendance Rate',
                    '${((_sessionStats['statistics']?['attendance_rate'] ?? 0.0) * 100).toStringAsFixed(1)}%',
                    Colors.green,
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
                const Text(
                  'Attendance Records',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text('${_attendanceRecords.length} checked in'),
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
                          style: TextStyle(color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Records will appear when faces are detected',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
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
                        title: Text(record.studentId),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${record.timeOnly} - ${record.statusInThai}'),
                            if (record.hasFaceMatch)
                              Text(
                                'Face verified (${record.faceMatchPercentage.toStringAsFixed(1)}%)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                          ],
                        ),
                        trailing: record.hasFaceMatch 
                            ? Icon(Icons.verified_user, color: Colors.blue.shade600)
                            : null,
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
        title: const Text('System Status'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatusSection('Server Health', _serverHealth),
              const SizedBox(height: 16),
              _buildStatusSection('Camera Statistics', _cameraStats),
              if (_sessionStats.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildStatusSection('Session Statistics', _sessionStats),
              ],
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

  Widget _buildStatusSection(String title, Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
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
              fontSize: 12,
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
        title: const Text('Session Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                title: const Text('Capture Interval'),
                subtitle: Text('Every $_captureIntervalMinutes minutes'),
                trailing: DropdownButton<int>(
                  value: _captureIntervalMinutes,
                  items: [1, 3, 5, 10, 15].map((minutes) => 
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
                subtitle: Text('$_onTimeLimitMinutes minutes'),
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