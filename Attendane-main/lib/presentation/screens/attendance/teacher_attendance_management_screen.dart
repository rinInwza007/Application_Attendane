// lib/presentation/screens/attendance/teacher_attendance_management_screen.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/services/unified_attendance_service.dart';
import 'package:myproject2/data/services/unified_camera_service.dart';
import 'package:myproject2/core/service_locator.dart'; // เพิ่ม import

class TeacherAttendanceManagementScreen extends StatefulWidget {
  final String classId;
  final String className;

  const TeacherAttendanceManagementScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<TeacherAttendanceManagementScreen> createState() => _TeacherAttendanceManagementScreenState();
}

class _TeacherAttendanceManagementScreenState extends State<TeacherAttendanceManagementScreen> {
  // ใช้ service locator แทนการสร้าง instance ใหม่
  late final UnifiedAttendanceService _attendanceService;
  late final UnifiedCameraService _cameraService;
  
  AttendanceSessionModel? _currentSession;
  List<AttendanceRecordModel> _attendanceRecords = [];
  Timer? _refreshTimer;
  
  bool _isLoading = false;
  bool _isSessionActive = false;
  bool _isCameraReady = false;
  bool _isPeriodicCaptureActive = false;
  
  // Session configuration
  int _sessionDurationHours = 2;
  int _captureIntervalMinutes = 5;
  int _onTimeLimitMinutes = 30;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stopPeriodicCapture();
    _clearCallbacks();
    super.dispose();
  }

  void _initializeServices() {
    // ใช้ service locator
    _attendanceService = serviceLocator<UnifiedAttendanceService>();
    _cameraService = serviceLocator<UnifiedCameraService>();
    
    _initializeCamera();
    _loadCurrentSession();
  }

  void _clearCallbacks() {
    _cameraService.onImageCaptured = null;
    _cameraService.onError = null;
    _cameraService.onStateChanged = null;
  }

  Future<void> _initializeCamera() async {
    try {
      // Setup camera callbacks (แก้ไข callback names)
      _cameraService.onImageCaptured = (imagePath, captureTime) {
        _handlePeriodicImage(imagePath, captureTime);
      };
      _cameraService.onError = _handleCameraError;
      _cameraService.onStateChanged = (state) {
        _handleCameraStatusChanged(state == CameraState.ready);
      };
      
      final initialized = await _cameraService.initialize();
      
      if (mounted) {
        setState(() {
          _isCameraReady = initialized;
        });
        
        if (initialized) {
          _showSnackBar('กล้องพร้อมใช้งาน', Colors.green);
        } else {
          _showSnackBar('ไม่สามารถเริ่มกล้องได้', Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('เกิดข้อผิดพลาดในการเริ่มกล้อง: $e', Colors.red);
      }
    }
  }

  Future<void> _loadCurrentSession() async {
    try {
      // แก้ไขจาก getActiveSessionForClass เป็น getActiveSession
      final session = await _attendanceService.getActiveSession(widget.classId);
      
      if (mounted) {
        setState(() {
          _currentSession = session;
          _isSessionActive = session?.isActive ?? false;
        });

        if (session != null) {
          await _loadSessionRecords();
          _startAutoRefresh();
          
          // If session is active and camera is ready, start capture
          if (_isSessionActive && _isCameraReady) {
            await _resumePeriodicCapture();
          }
        }
      }
    } catch (e) {
      print('❌ Error loading current session: $e');
    }
  }

  Future<void> _loadSessionRecords() async {
    if (_currentSession == null) return;
    
    try {
      // แก้ไขจาก getAttendanceRecords เป็น getSessionRecords
      final records = await _attendanceService.getSessionRecords(_currentSession!.id);
      
      if (mounted) {
        setState(() {
          _attendanceRecords = records;
        });
      }
      
    } catch (e) {
      print('❌ Error loading session records: $e');
      if (mounted) {
        _showSnackBar('ไม่สามารถโหลดข้อมูลการเข้าเรียนได้: $e', Colors.red);
      }
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isSessionActive) {
        _loadSessionRecords(); // แก้ไขจาก _loadAttendanceRecords
      } else {
        timer.cancel();
      }
    });
  }

  // ========== Session Management ==========
  
  Future<void> _startAttendanceSession() async {
    if (!_isCameraReady) {
      _showSnackBar('กล้องยังไม่พร้อม กรุณารอสักครู่', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Create new attendance session (แก้ไขจาก createAttendanceSession เป็น createSession)
      final session = await _attendanceService.createSession(
        classId: widget.classId,
        durationHours: _sessionDurationHours,
        onTimeLimitMinutes: _onTimeLimitMinutes,
      );

      if (mounted) {
        setState(() {
          _currentSession = session;
          _isSessionActive = true;
          _attendanceRecords = [];
        });

        _startAutoRefresh();
        await _startPeriodicCapture(); // แก้ไข method call
        
        _showSnackBar('เริ่มคาบเรียนและการเช็คชื่ออัตโนมัติแล้ว', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('ไม่สามารถเริ่มคาบเรียนได้: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _endAttendanceSession() async {
    if (_currentSession == null) return;

    final confirm = await _showConfirmDialog(
      'จบคาบเรียน',
      'คุณต้องการจบคาบเรียนนี้หรือไม่? ระบบจะหยุดการเช็คชื่ออัตโนมัติ',
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // Stop periodic capture first
      _stopPeriodicCapture();
      
      // Take final attendance snapshot
      await _captureFinalAttendance();
      
      // End session in database (แก้ไขจาก endAttendanceSession เป็น endSession)
      await _attendanceService.endSession(_currentSession!.id);
      
      if (mounted) {
        setState(() {
          _currentSession = null;
          _isSessionActive = false;
        });

        _refreshTimer?.cancel();
        _showSnackBar('จบคาบเรียนสำเร็จ', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('ไม่สามารถจบคาบเรียนได้: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ========== Camera Management ==========
  
  Future<void> _startPeriodicCapture() async {
    if (_currentSession == null || !_isCameraReady) return;

    try {
      // แก้ไข method call ให้ตรงกับ UnifiedCameraService
      await _cameraService.startPeriodicCapture(
        sessionId: _currentSession!.id,
        interval: Duration(minutes: _captureIntervalMinutes),
        onCapture: (imagePath, captureTime) async {
          await _handlePeriodicCapture(imagePath, captureTime);
        },
      );
      
      setState(() {
        _isPeriodicCaptureActive = true;
      });
      
      print('📸 Periodic capture started - every $_captureIntervalMinutes minutes');
    } catch (e) {
      print('❌ Failed to start periodic capture: $e');
      _showSnackBar('ไม่สามารถเริ่มการเช็คชื่ออัตโนมัติได้: $e', Colors.red);
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

  Future<void> _captureFinalAttendance() async {
    try {
      print('📸 Taking final attendance snapshot...');
      final imagePath = await _cameraService.captureImage(); // แก้ไขจาก captureSingleImage
      
      if (imagePath != null) {
        await _processAttendanceImage(imagePath, isFinalCapture: true);
        print('✅ Final attendance snapshot processed');
      }
    } catch (e) {
      print('❌ Error in final capture: $e');
    }
  }

  // ========== Camera Event Handlers ==========
  
  void _handlePeriodicImage(String imagePath, DateTime captureTime) {
    print('📷 Periodic image captured: $imagePath at $captureTime');
    _processAttendanceImage(imagePath);
  }

  Future<void> _handlePeriodicCapture(String imagePath, DateTime captureTime) async {
    try {
      print('📷 Processing periodic capture: ${imagePath.split('/').last}');
      await _processAttendanceImage(imagePath, captureTime: captureTime);
    } catch (e) {
      print('❌ Error in periodic capture handler: $e');
    }
  }

  void _handleCameraError(String error) {
    print('❌ Camera error: $error');
    if (mounted) {
      _showSnackBar('เกิดข้อผิดพลาดกับกล้อง: $error', Colors.red);
    }
  }

  void _handleCameraStatusChanged(bool isReady) {
    print('📸 Camera status changed: $isReady');
    if (mounted) {
      setState(() {
        _isCameraReady = isReady;
      });
      
      _showSnackBar(
        isReady ? 'กล้องพร้อมใช้งาน' : 'กล้องไม่พร้อมใช้งาน',
        isReady ? Colors.green : Colors.orange,
      );
    }
  }

  Future<void> _processAttendanceImage(String imagePath, {bool isFinalCapture = false, DateTime? captureTime}) async {
    try {
      if (_currentSession == null) {
        print('⚠️ No active session for processing image');
        return;
      }

      print('🔄 Processing attendance image: $imagePath');
      print('   Session ID: ${_currentSession!.id}');
      print('   Is final capture: $isFinalCapture');
      
      // ส่งรูปไป process ด้วย UnifiedAttendanceService
      final result = await _attendanceService.processPeriodicCapture(
        imagePath: imagePath,
        sessionId: _currentSession!.id,
        captureTime: captureTime ?? DateTime.now(),
        deleteImageAfter: true,
      );

      if (result['success']) {
        final data = result['data'];
        final facesDetected = data['faces_detected'] as int? ?? 0;
        final newRecords = data['new_attendance_records'] as int? ?? 0;
        
        print('✅ Attendance processed successfully');
        print('   Faces detected: $facesDetected');
        print('   New records: $newRecords');
        
        if (facesDetected > 0) {
          _showSnackBar('ตรวจพบใบหน้า $facesDetected คน, บันทึกการเข้าเรียน $newRecords คน', Colors.green);
        }
        
        // Refresh attendance records
        await _loadSessionRecords();
      } else {
        print('❌ Failed to process attendance: ${result['error']}');
      }
      
    } catch (e) {
      print('❌ Error processing attendance image: $e');
    }
  }

  // ========== UI Helpers ==========
  
  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
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
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ยืนยัน'),
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
        title: Text('การเช็คชื่อ - ${widget.className}'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _isSessionActive ? null : _showSessionSettings, // ปิดการแก้ไขเมื่อ session กำลังทำงาน
            tooltip: 'ตั้งค่าการเช็คชื่อ',
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCameraPreview(),
                _buildSessionControl(),
                _buildSessionStatus(),
                Expanded(child: _buildAttendanceList()),
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
                        _isCameraReady ? 'กล้องพร้อมใช้งาน' : 'กำลังเตรียมกล้อง...',
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
              'การจัดการคาบเรียน',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (!_isSessionActive)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCameraReady && !_isLoading ? _startAttendanceSession : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('เริ่มคาบเรียน'),
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
                      onPressed: _isLoading ? null : () async {
                        final imagePath = await _cameraService.captureImage(); // แก้ไขจาก captureSingleImage
                        if (imagePath != null) {
                          await _processAttendanceImage(imagePath);
                          _showSnackBar('ถ่ายรูปเช็คชื่อเพิ่มเติมแล้ว', Colors.blue);
                        }
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('เช็คชื่อเพิ่ม'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _endAttendanceSession,
                      icon: const Icon(Icons.stop),
                      label: const Text('จบคาบเรียน'),
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
                  _isSessionActive ? 'คาบเรียนกำลังดำเนินการ' : 'คาบเรียนสิ้นสุดแล้ว',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    'เวลาที่เหลือ',
                    timeRemaining.isNegative ? 'สิ้นสุดแล้ว' : 
                    '${timeRemaining.inHours}h ${timeRemaining.inMinutes % 60}m',
                    timeRemaining.isNegative ? Colors.red : Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    'การเช็คชื่ออัตโนมัติ',
                    _isPeriodicCaptureActive ? 'เปิด' : 'ปิด', // แก้ไขจาก captureStatus
                    _isPeriodicCaptureActive ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    'ช่วงเวลาถ่ายรูป',
                    '$_captureIntervalMinutes นาที',
                    Colors.purple,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    'จำนวนคนเช็คชื่อ',
                    '${_attendanceRecords.length}',
                    Colors.indigo,
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
                  'รายการเช็คชื่อ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text('${_attendanceRecords.length} คน'),
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
                        Text('ยังไม่มีการเช็คชื่อ'),
                        SizedBox(height: 8),
                        Text(
                          'รายการจะแสดงเมื่อมีการตรวจพบใบหน้าอัตโนมัติ',
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
                        title: Text(record.studentId ?? 'Unknown Student'),
                        subtitle: Text(
                          '${record.checkInTime.toLocal().toString().split(' ')[1].substring(0, 5)} - ${record.status.toUpperCase()}',
                        ),
                        trailing: (record.faceMatchScore != null && record.faceMatchScore! > 0)
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

  void _showSessionSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ตั้งค่าการเช็คชื่อ'),
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
                        'การตั้งค่าจะใช้กับการเริ่มคาบเรียนครั้งถัดไป',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('ระยะเวลาคาบเรียน'),
                subtitle: Text('$_sessionDurationHours ชั่วโมง'),
                trailing: DropdownButton<int>(
                  value: _sessionDurationHours,
                  items: [1, 2, 3, 4, 6, 8].map((hours) => 
                    DropdownMenuItem(value: hours, child: Text('$hours ชั่วโมง'))
                  ).toList(),
                  onChanged: _isSessionActive ? null : (value) {
                    if (value != null) {
                      setState(() => _sessionDurationHours = value);
                    }
                  },
                ),
              ),
              ListTile(
                title: const Text('ช่วงเวลาถ่ายรูป'),
                subtitle: Text('ทุก $_captureIntervalMinutes นาที'),
                trailing: DropdownButton<int>(
                  value: _captureIntervalMinutes,
                  items: [3, 5, 10, 15, 20].map((minutes) => 
                    DropdownMenuItem(value: minutes, child: Text('$minutes นาที'))
                  ).toList(),
                  onChanged: _isSessionActive ? null : (value) {
                    if (value != null) {
                      setState(() => _captureIntervalMinutes = value);
                    }
                  },
                ),
              ),
              ListTile(
                title: const Text('เวลาสำหรับมาทัน'),
                subtitle: Text('$_onTimeLimitMinutes นาที'),
                trailing: DropdownButton<int>(
                  value: _onTimeLimitMinutes,
                  items: [15, 30, 45, 60].map((minutes) => 
                    DropdownMenuItem(value: minutes, child: Text('$minutes นาที'))
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
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}