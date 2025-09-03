// lib/presentation/screens/attendance/updated_student_attendance_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/unified_attendance_service.dart';
import 'package:myproject2/presentation/screens/face/multi_step_face_capture_screen.dart';

class UpdatedStudentAttendanceScreen extends StatefulWidget {
  final String classId;
  final String className;

  const UpdatedStudentAttendanceScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<UpdatedStudentAttendanceScreen> createState() => _UpdatedStudentAttendanceScreenState();
}

class _UpdatedStudentAttendanceScreenState extends State<UpdatedStudentAttendanceScreen> {
  final UnifiedAttendanceService _attendanceService = UnifiedAttendanceService();
  final AuthService _authService = AuthService();
  
  AttendanceSessionModel? _currentSession;
  AttendanceRecordModel? _myAttendanceRecord;
  List<AttendanceRecordModel> _myAttendanceHistory = [];
  Timer? _sessionCheckTimer;
  
  bool _isLoading = false;
  bool _isCheckingIn = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSession();
    _loadAttendanceHistory();
    _startSessionMonitoring();
  }

  @override
  void dispose() {
    _sessionCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentSession() async {
    setState(() => _isLoading = true);
    
    try {
      final session = await _attendanceService.getActiveSession(widget.classId);
      
      if (mounted) {
        setState(() => _currentSession = session);
        
        if (session != null) {
          await _checkMyAttendanceRecord();
        }
      }
    } catch (e) {
      print('Error loading session: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkMyAttendanceRecord() async {
    if (_currentSession == null) return;

    try {
      final userEmail = _authService.getCurrentUserEmail();
      if (userEmail == null) return;

      final records = await _attendanceService.getSessionRecords(_currentSession!.id);
      final myRecord = records.where((r) => r.studentEmail == userEmail).firstOrNull;
      
      if (mounted) {
        setState(() => _myAttendanceRecord = myRecord);
      }
    } catch (e) {
      print('Error checking attendance record: $e');
    }
  }

  Future<void> _loadAttendanceHistory() async {
    try {
      final userEmail = _authService.getCurrentUserEmail();
      if (userEmail == null) return;

      final history = await _attendanceService.getStudentHistory(userEmail);
      
      if (mounted) {
        setState(() => _myAttendanceHistory = history);
      }
    } catch (e) {
      print('Error loading attendance history: $e');
    }
  }

  void _startSessionMonitoring() {
    _sessionCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _loadCurrentSession();
    });
  }

  // เช็คชื่อด้วย Multi-Step Face Capture
  Future<void> _checkInWithMultiStepFaceCapture() async {
    if (_currentSession == null || _myAttendanceRecord != null) return;

    // ตรวจสอบว่ามีข้อมูลใบหน้าแล้วหรือยัง
    final hasFaceData = await _authService.hasFaceEmbedding();
    if (!hasFaceData) {
      _showNoFaceDataDialog();
      return;
    }

    setState(() => _isCheckingIn = true);

    try {
      // เปิดหน้าจอ Multi-Step Face Capture สำหรับ Face Recognition
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => MultiStepFaceCaptureScreen(
            studentEmail: _authService.getCurrentUserEmail(),
            isUpdate: false, // ไม่ใช่การอัพเดต แต่เป็นการใช้งาน Face Recognition
            onAllImagesCapture: (imagePaths) async {
              // Process face recognition for attendance
              await _processFaceRecognitionForAttendance(imagePaths);
            },
          ),
        ),
      );

      if (result == true && mounted) {
        // รีเฟรชข้อมูลหลังเช็คชื่อสำเร็จ
        await _checkMyAttendanceRecord();
        await _loadAttendanceHistory();
        
        _showSnackBar(
          'เช็คชื่อสำเร็จด้วย Multi-Step Face Recognition!', 
          Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('เช็คชื่อล้มเหลว', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingIn = false);
      }
    }
  }

  // ประมวลผล Face Recognition สำหรับการเช็คชื่อ
  Future<void> _processFaceRecognitionForAttendance(List<String> imagePaths) async {
    try {
      final userEmail = _authService.getCurrentUserEmail();
      if (userEmail == null || _currentSession == null) return;

      // ใช้ภาพแรกสำหรับ Face Recognition (หรืออาจใช้หลายภาพเพื่อความแม่นยำ)
      final primaryImagePath = imagePaths.first;
      
      // เรียกใช้ service เพื่อทำ Face Recognition และบันทึกการเข้าเรียน
      await _attendanceService.checkInWithFaceRecognition(
        sessionId: _currentSession!.id,
        studentEmail: userEmail,
        imagePath: primaryImagePath,
      );

      print('✅ Face recognition attendance successful');
    } catch (e) {
      print('❌ Error processing face recognition for attendance: $e');
      throw e;
    }
  }

  void _showNoFaceDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.face_retouching_off, color: Colors.orange),
            SizedBox(width: 12),
            Text('ยังไม่ได้ตั้งค่า Face Recognition'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คุณต้องตั้งค่า Face Recognition ก่อนใช้งานการเช็คชื่อ',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text('ประโยชน์ของ Multi-Step Face Recognition:'),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('เช็คชื่อรวดเร็วและแม่นยำสูง')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('ป้องกันการโกงด้วยการถ่ายหลายมุม')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('ระบบความปลอดภัยระดับสูง')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('ตรวจจับใบหน้าได้แม่นยำในทุกสภาพแสง')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ข้ามไปก่อน'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _setupMultiStepFaceRecognition();
            },
            icon: const Icon(Icons.face),
            label: const Text('ตั้งค่าเลย'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade400,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ตั้งค่า Multi-Step Face Recognition สำหรับครั้งแรก
  Future<void> _setupMultiStepFaceRecognition() async {
    setState(() => _isCheckingIn = true);

    try {
      final userEmail = _authService.getCurrentUserEmail();
      if (userEmail == null) {
        throw Exception('ไม่พบข้อมูลผู้ใช้');
      }

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => MultiStepFaceCaptureScreen(
            studentEmail: userEmail,
            isUpdate: false, // ตั้งค่าใหม่
            onAllImagesCapture: (imagePaths) async {
              // บันทึกข้อมูล Face Embedding จากภาพหลายมุม
              await _saveFaceEmbeddingFromImages(imagePaths, userEmail);
            },
          ),
        ),
      );

      if (result == true && mounted) {
        _showSnackBar(
          'ตั้งค่า Multi-Step Face Recognition สำเร็จ!', 
          Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('ตั้งค่า Face Recognition ล้มเหลว', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingIn = false);
      }
    }
  }

  // บันทึก Face Embedding จากภาพหลายมุม
  Future<void> _saveFaceEmbeddingFromImages(List<String> imagePaths, String userEmail) async {
    try {
      // ใช้ AuthService เพื่อบันทึก Face Embedding จากภาพหลายมุม
      await _authService.saveFaceEmbeddingFromMultipleImages(imagePaths, userEmail);
      
      print('✅ Multi-step face embedding saved successfully');
    } catch (e) {
      print('❌ Error saving face embedding: $e');
      throw e;
    }
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
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance - ${widget.className}'),
        centerTitle: true,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                'Wait for your teacher to start an attendance session.',
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
                            : 'Attendance Session Active',
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
              // Time info for students who haven't checked in
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
              
              // Check-in button with Multi-Step Face Recognition
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingIn || !session.isActive 
                      ? null 
                      : _checkInWithMultiStepFaceCapture,
                  icon: _isCheckingIn 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.face_6),
                  label: Text(
                    _isCheckingIn 
                        ? 'Processing...' 
                        : session.isActive 
                            ? 'Check In with Multi-Step Face Recognition' 
                            : 'Session Ended',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: session.isActive 
                        ? (isOnTimePeriod ? Colors.green : Colors.orange)
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
            const Row(
              children: [
                Icon(Icons.face_6, color: Colors.blue, size: 24),
                SizedBox(width: 8),
                Text(
                  'Multi-Step Face Recognition Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            FutureBuilder<bool>(
              future: _authService.hasFaceEmbedding(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Checking Multi-Step Face Recognition status...'),
                    ],
                  );
                }
                
                final hasFace = snapshot.data ?? false;
                
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: hasFace ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasFace ? Colors.green.shade200 : Colors.orange.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: hasFace ? Colors.green.shade100 : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              hasFace ? Icons.verified_user : Icons.face_retouching_off,
                              color: hasFace ? Colors.green.shade700 : Colors.orange.shade700,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasFace ? 'Multi-Step Face Recognition Ready' : 'Multi-Step Face Recognition Not Set Up',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: hasFace ? Colors.green.shade700 : Colors.orange.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasFace 
                                      ? 'You can use advanced multi-step face recognition for secure attendance'
                                      : 'Set up multi-step face recognition for ultra-secure attendance',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: hasFace ? Colors.green.shade600 : Colors.orange.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      if (hasFace) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                '🔥 Multi-Step Features Enabled:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Row(
                                children: [
                                  Icon(Icons.check_circle, size: 16, color: Colors.green),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('6-step pose verification', style: TextStyle(fontSize: 12))),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Row(
                                children: [
                                  Icon(Icons.check_circle, size: 16, color: Colors.green),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('Advanced anti-spoofing protection', style: TextStyle(fontSize: 12))),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Row(
                                children: [
                                  Icon(Icons.check_circle, size: 16, color: Colors.green),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('Real-time quality assessment', style: TextStyle(fontSize: 12))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isCheckingIn ? null : _setupMultiStepFaceRecognition,
                            icon: const Icon(Icons.face_6, size: 20),
                            label: const Text('Setup Multi-Step Face Recognition'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade400,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.face_6, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Verified with Multi-Step Face Recognition',
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
                Icon(Icons.face_6, size: 12, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Text(
                  'Multi-Step Face Recognition',
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