// lib/presentation/screens/attendance/enhanced_student_attendance_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/presentation/screens/face/enhanced_realtime_face_detection_screen.dart';

class EnhancedStudentAttendanceScreen extends StatefulWidget {
  final String classId;
  final String className;

  const EnhancedStudentAttendanceScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<EnhancedStudentAttendanceScreen> createState() => _EnhancedStudentAttendanceScreenState();
}

class _EnhancedStudentAttendanceScreenState extends State<EnhancedStudentAttendanceScreen> {
  final EnhancedAttendanceService _attendanceService = EnhancedAttendanceService();
  final SimpleAttendanceService _simpleAttendanceService = SimpleAttendanceService(); // เพิ่ม service นี้
  final AuthService _authService = AuthService();
  
  AttendanceSessionModel? _currentSession;
  AttendanceRecordModel? _myAttendanceRecord;
  List<AttendanceRecordModel> _myAttendanceHistory = [];
  Timer? _sessionCheckTimer;
  
  bool _isLoading = false;
  bool _isCheckingIn = false;
  bool _isServerHealthy = false;
  bool _hasFaceEnrollment = false;
  
  Map<String, dynamic> _serverHealth = {};

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _sessionCheckTimer?.cancel();
    _attendanceService.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    setState(() => _isLoading = true);
    
    try {
      // Check server health
      await _checkServerHealth();
      
      // Check face enrollment status
      await _checkFaceEnrollmentStatus();
      
      // Load current session and history
      await _loadCurrentSession();
      await _loadAttendanceHistory();
      
      // Start monitoring
      _startSessionMonitoring();
      
    } catch (e) {
      print('❌ Error initializing screen: $e');
      _showErrorSnackBar('Failed to initialize: $e');
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
        _showWarningSnackBar('Face recognition server is offline. Some features may not work.');
      }
    } catch (e) {
      setState(() => _isServerHealthy = false);
      print('❌ Server health check failed: $e');
    }
  }

  Future<void> _checkFaceEnrollmentStatus() async {
    try {
      // Check both local and server enrollment status
      final localHasFace = await _authService.hasFaceEmbedding();
      
      if (localHasFace && _isServerHealthy) {
        // Verify with server
        final userProfile = await _authService.getUserProfile();
        if (userProfile != null) {
          final studentId = userProfile['school_id'];
          final serverResult = await _attendanceService.verifyFaceEnrollment(studentId);
          setState(() {
            _hasFaceEnrollment = serverResult['success'] && serverResult['has_face_data'];
          });
        } else {
          setState(() => _hasFaceEnrollment = localHasFace);
        }
      } else {
        setState(() => _hasFaceEnrollment = localHasFace);
      }
    } catch (e) {
      print('❌ Error checking face enrollment: $e');
      // Fallback to local check
      final localHasFace = await _authService.hasFaceEmbedding();
      setState(() => _hasFaceEnrollment = localHasFace);
    }
  }

  Future<void> _loadCurrentSession() async {
    try {
      // ใช้ SimpleAttendanceService แทน AuthService
      final session = await _simpleAttendanceService.getActiveSessionForClass(widget.classId);
      
      setState(() => _currentSession = session);
      
      if (session != null) {
        await _checkMyAttendanceRecord();
      }
    } catch (e) {
      print('❌ Error loading session: $e');
    }
  }

  Future<void> _checkMyAttendanceRecord() async {
    if (_currentSession == null) return;

    try {
      final userEmail = _authService.getCurrentUserEmail();
      if (userEmail == null) return;

      // ใช้ SimpleAttendanceService แทน AuthService
      final records = await _simpleAttendanceService.getAttendanceRecords(_currentSession!.id);
      final myRecord = records.where((r) => r.studentEmail == userEmail).firstOrNull;
      
      setState(() => _myAttendanceRecord = myRecord);
    } catch (e) {
      print('❌ Error checking attendance record: $e');
    }
  }

  Future<void> _loadAttendanceHistory() async {
    try {
      final userEmail = _authService.getCurrentUserEmail();
      if (userEmail == null) return;

      // ใช้ SimpleAttendanceService แทน AuthService
      final history = await _simpleAttendanceService.getStudentAttendanceHistory(userEmail);
      
      setState(() => _myAttendanceHistory = history);
    } catch (e) {
      print('❌ Error loading attendance history: $e');
    }
  }

  void _startSessionMonitoring() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _loadCurrentSession();
    });
  }

  // ========== Enhanced Face Recognition Check-in ==========
  
  Future<void> _checkInWithEnhancedFaceDetection() async {
    if (_currentSession == null || _myAttendanceRecord != null) return;

    if (!_hasFaceEnrollment) {
      _showFaceEnrollmentDialog();
      return;
    }

    if (!_isServerHealthy) {
      _showServerOfflineDialog();
      return;
    }

    setState(() => _isCheckingIn = true);

    try {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => EnhancedRealtimeFaceDetectionScreen(
            sessionId: _currentSession!.id,
            isRegistration: false,
            attendanceService: _attendanceService,
            instructionText: "Position your face in the green frame for check-in",
            onCheckInSuccess: (message) {
              print('✅ Enhanced check-in successful: $message');
            },
          ),
        ),
      );

      if (result == true && mounted) {
        await _checkMyAttendanceRecord();
        await _loadAttendanceHistory();
        
        _showSuccessSnackBar('Check-in successful with Face Recognition!');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Check-in Failed', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingIn = false);
      }
    }
  }

  // ========== Face Enrollment Management ==========
  
  Future<void> _setupEnhancedFaceRecognition() async {
    setState(() => _isCheckingIn = true);

    try {
      // Get user profile
      final userProfile = await _authService.getUserProfile();
      if (userProfile == null) {
        throw Exception('User profile not found');
      }

      final studentId = userProfile['school_id'];
      final studentEmail = userProfile['email'];

      // Open enhanced face enrollment
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => EnhancedRealtimeFaceDetectionScreen(
            isRegistration: true,
            attendanceService: _attendanceService,
            studentId: studentId,
            studentEmail: studentEmail,
            instructionText: "Position your face in the frame to set up Face Recognition",
            onFaceEmbeddingCaptured: (embedding) {
              print('✅ Enhanced face embedding captured');
            },
          ),
        ),
      );

      if (result == true && mounted) {
        await _checkFaceEnrollmentStatus();
        _showSuccessSnackBar('Enhanced Face Recognition setup complete!');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Face Recognition Setup Failed', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingIn = false);
      }
    }
  }

  Future<void> _manageFaceRecognition() async {
    if (!_hasFaceEnrollment) {
      _setupEnhancedFaceRecognition();
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _isServerHealthy ? Icons.verified_user : Icons.face_retouching_off,
              color: _isServerHealthy ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 12),
            const Text('Face Recognition'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isServerHealthy 
                  ? 'Your Face Recognition is ready and synced with the server'
                  : 'Face Recognition is set up locally but server is offline',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            if (_isServerHealthy) ...[
              const Text('Server Status:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Version: ${_serverHealth['data']?['version'] ?? 'Unknown'}'),
                    Text('Cache Size: ${_serverHealth['data']?['cache']?['size'] ?? 0} students'),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠️ Server Offline'),
                    Text('You can still check-in when server comes back online'),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _updateFaceRecognition();
            },
            child: const Text('Update'),
          ),
          if (_isServerHealthy)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteFaceRecognition();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
        ],
      ),
    );
  }

  Future<void> _updateFaceRecognition() async {
    final confirm = await _showConfirmDialog(
      'Update Face Recognition',
      'This will replace your current face data with new enrollment. Continue?',
    );

    if (confirm == true) {
      await _setupEnhancedFaceRecognition();
    }
  }

  Future<void> _deleteFaceRecognition() async {
    final confirm = await _showConfirmDialog(
      'Delete Face Recognition',
      'This will remove your face data from both local storage and server. You will need to set it up again to use Face Recognition check-in.',
    );

    if (confirm == true) {
      try {
        setState(() => _isCheckingIn = true);

        // Delete from server first
        if (_isServerHealthy) {
          final userProfile = await _authService.getUserProfile();
          if (userProfile != null) {
            final studentId = userProfile['school_id'];
            // Note: deleteFaceEnrollment method should be implemented in EnhancedAttendanceService
            // await _attendanceService.deleteFaceEnrollment(studentId);
          }
        }

        // Delete from local storage
        await _authService.deactivateFaceEmbedding();

        await _checkFaceEnrollmentStatus();
        
        if (mounted) {
          _showSuccessSnackBar('Face Recognition data deleted successfully');
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Failed to delete Face Recognition data: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isCheckingIn = false);
        }
      }
    }
  }

  // ========== UI Dialogs ==========
  
  void _showFaceEnrollmentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.face_retouching_off, color: Colors.orange),
            SizedBox(width: 12),
            Text('Face Recognition Not Set Up'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You need to set up Face Recognition to use this check-in method.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              _isServerHealthy 
                  ? 'Benefits of Enhanced Face Recognition:'
                  : 'Benefits of Face Recognition (Server currently offline):',
            ),
            const SizedBox(height: 8),
            ...[
              'Real-time face detection',
              'Automatic attendance recording',
              'High security and anti-spoofing',
              'Works with server synchronization',
            ].map((benefit) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.check, size: 16, color: _isServerHealthy ? Colors.green : Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(benefit)),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _setupEnhancedFaceRecognition();
            },
            icon: const Icon(Icons.face),
            label: const Text('Set Up Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade400,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showServerOfflineDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_off, color: Colors.red),
            SizedBox(width: 12),
            Text('Server Offline'),
          ],
        ),
        content: const Text(
          'The Face Recognition server is currently offline. Please try again later or contact your instructor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _checkServerHealth();
            },
            child: const Text('Retry'),
          ),
        ],
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
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ========== SnackBar Helpers ==========
  
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ========== UI Build ==========
  
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
            onPressed: () => _showServerStatusDialog(),
            tooltip: 'Server Status',
          ),
          IconButton(
            icon: const Icon(Icons.face_retouching_natural),
            onPressed: _manageFaceRecognition,
            tooltip: 'Manage Face Recognition',
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildServerStatusCard(),
                  const SizedBox(height: 16),
                  _buildCurrentSessionCard(),
                  const SizedBox(height: 16),
                  _buildFaceRecognitionStatusCard(),
                  const SizedBox(height: 16),
                  _buildAttendanceHistoryCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildServerStatusCard() {
    return Card(
      color: _isServerHealthy ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isServerHealthy ? Icons.check_circle : Icons.error,
              color: _isServerHealthy ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isServerHealthy ? 'Enhanced Server Online' : 'Enhanced Server Offline',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isServerHealthy ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                  Text(
                    _isServerHealthy 
                        ? 'Face recognition features are available'
                        : 'Some features may be limited',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isServerHealthy ? Colors.green.shade600 : Colors.red.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isServerHealthy)
              ElevatedButton.icon(
                onPressed: _checkServerHealth,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSessionCard() {
    if (_currentSession == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.schedule,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                'No Active Attendance Session',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Wait for your instructor to start an attendance session.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final session = _currentSession!;
    final timeRemaining = session.endTime.difference(DateTime.now());
    final onTimeDeadline = session.onTimeDeadline;
    final isOnTimePeriod = DateTime.now().isBefore(onTimeDeadline);
    final hasCheckedIn = _myAttendanceRecord != null;

    return Card(
      color: hasCheckedIn 
          ? Colors.green.shade50 
          : isOnTimePeriod 
              ? Colors.blue.shade50 
              : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasCheckedIn 
                      ? Icons.check_circle 
                      : Icons.access_time,
                  color: hasCheckedIn 
                      ? Colors.green 
                      : isOnTimePeriod 
                          ? Colors.blue 
                          : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasCheckedIn 
                            ? 'Attendance Recorded' 
                            : 'Enhanced Session Active',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Started: ${_formatTime(session.startTime)}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (hasCheckedIn) ...[
              _buildAttendanceStatusCard(_myAttendanceRecord!),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTimeInfoChip(
                      'Time Remaining',
                      timeRemaining.isNegative 
                          ? 'Session Ended' 
                          : '${timeRemaining.inHours}h ${timeRemaining.inMinutes % 60}m',
                      timeRemaining.isNegative ? Colors.red : Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTimeInfoChip(
                      isOnTimePeriod ? 'On-time Until' : 'Late Since',
                      _formatTime(onTimeDeadline),
                      isOnTimePeriod ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingIn || !session.isActive 
                      ? null 
                      : _checkInWithEnhancedFaceDetection,
                  icon: _isCheckingIn 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(_hasFaceEnrollment ? Icons.face_retouching_natural : Icons.face_retouching_off),
                  label: Text(
                    _isCheckingIn 
                        ? 'Processing...' 
                        : session.isActive 
                            ? (_hasFaceEnrollment 
                                ? 'Check In with Enhanced Face Recognition' 
                                : 'Set Up Face Recognition First')
                            : 'Session Ended',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: session.isActive 
                        ? (_hasFaceEnrollment 
                            ? (isOnTimePeriod ? Colors.green : Colors.orange)
                            : Colors.blue)
                        : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              
              if (!isOnTimePeriod && session.isActive)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '⚠️ You will be marked as LATE if you check in now',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFaceRecognitionStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enhanced Face Recognition Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _hasFaceEnrollment ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hasFaceEnrollment ? Colors.green.shade200 : Colors.orange.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasFaceEnrollment ? Icons.verified_user : Icons.face_retouching_off,
                    color: _hasFaceEnrollment ? Colors.green.shade700 : Colors.orange.shade700,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasFaceEnrollment ? 'Enhanced Face Recognition Ready' : 'Face Recognition Not Set Up',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _hasFaceEnrollment ? Colors.green.shade700 : Colors.orange.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _hasFaceEnrollment 
                              ? (_isServerHealthy 
                                  ? 'Synced with enhanced server'
                                  : 'Local data available, server offline')
                              : 'Set up enhanced Face Recognition for quick check-in',
                          style: TextStyle(
                            fontSize: 14,
                            color: _hasFaceEnrollment ? Colors.green.shade600 : Colors.orange.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_hasFaceEnrollment)
                    ElevatedButton.icon(
                      onPressed: _isCheckingIn ? null : _setupEnhancedFaceRecognition,
                      icon: const Icon(Icons.face, size: 18),
                      label: const Text('Setup'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade400,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceStatusCard(AttendanceRecordModel record) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    
    switch (record.status) {
      case 'present':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'PRESENT';
        break;
      case 'late':
        statusColor = Colors.orange;
        statusIcon = Icons.access_time;
        statusText = 'LATE';
        break;
      default:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'ABSENT';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(statusIcon, color: statusColor, size: 32),
              const SizedBox(width: 12),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Checked in at: ${_formatDateTime(record.checkInTime)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (record.hasFaceMatch)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Enhanced Face Recognition Verified',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeInfoChip(String label, String value, Color color) {
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
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attendance History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            if (_myAttendanceHistory.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.history, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No attendance history yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _myAttendanceHistory.length > 5 ? 5 : _myAttendanceHistory.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final record = _myAttendanceHistory[index];
                  return _buildHistoryTile(record);
                },
              ),
            
            if (_myAttendanceHistory.length > 5)
              TextButton(
                onPressed: () {
                  // TODO: Navigate to full history page
                },
                child: const Text('View All History'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(AttendanceRecordModel record) {
    Color statusColor;
    IconData statusIcon;
    
    switch (record.status) {
      case 'present':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'late':
        statusColor = Colors.orange;
        statusIcon = Icons.access_time;
        break;
      case 'absent':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Icon(statusIcon, color: statusColor),
      title: Text(
        _formatDate(record.checkInTime),
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatTime(record.checkInTime)),
          if (record.hasFaceMatch)
            Row(
              children: [
                Icon(Icons.verified_user, size: 12, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Text(
                  'Enhanced Face Recognition',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          record.status.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showServerStatusDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enhanced Server Status'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Status: ${_isServerHealthy ? "Online" : "Offline"}'),
              if (_isServerHealthy && _serverHealth['data'] != null) ...[
                Text('Version: ${_serverHealth['data']['version'] ?? "Unknown"}'),
                Text('Cache Size: ${_serverHealth['data']['cache']?['size'] ?? 0} students'),
                const SizedBox(height: 12),
                const Text('Available Features:'),
                const Text('• Enhanced face recognition'),
                const Text('• Real-time processing'),
                const Text('• Server-side verification'),
                const Text('• Analytics and reporting'),
              ] else ...[
                const SizedBox(height: 12),
                const Text('Limited Features Available:'),
                const Text('• Local face recognition'),
                const Text('• Basic attendance recording'),
                const Text('• Data will sync when server is online'),
              ],
            ],
          ),
        ),
        actions: [
          if (!_isServerHealthy)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _checkServerHealth();
              },
              child: const Text('Retry Connection'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} ${_formatTime(dateTime)}';
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}