// lib/presentation/screens/attendance/teacher_attendance_management_screen.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/services/unified_attendance_service.dart';
import 'package:myproject2/data/services/unified_camera_service.dart';


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
  final UnifiedAttendanceService  _attendanceService = UnifiedAttendanceService ();
  final UnifiedCameraService  _cameraService = UnifiedCameraService ();
  
  AttendanceSessionModel? _currentSession;
  List<AttendanceRecordModel> _attendanceRecords = [];
  Timer? _refreshTimer;
  
  bool _isLoading = false;
  bool _isSessionActive = false;
  bool _isCameraReady = false;
  
  // Session configuration
  int _sessionDurationHours = 2;
  int _captureIntervalMinutes = 5;
  int _onTimeLimitMinutes = 30;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadCurrentSession();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _cameraService.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      // Setup camera callbacks
      _cameraService.onImageCaptured = _handlePeriodicImage;
      _cameraService.onError = _handleCameraError;
      _cameraService.onStatusChanged = _handleCameraStatusChanged;
      
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

  Future<void> _loadSessionRecords() async {
  if (_currentSession == null) return;
  
  try {
    // ใช้ getSessionRecords แทน getAttendanceRecords
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

  Future<void> _loadAttendanceRecords() async {
    if (_currentSession == null) return;

    try {
      final records = await _attendanceService.getSessionRecords(_currentSession!.id);
      
      if (mounted) {
        setState(() => _attendanceRecords = records);
      }
    } catch (e) {
      print('Error loading attendance records: $e');
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isSessionActive) {
        _loadAttendanceRecords();
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
      // Create new attendance session
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
        startPeriodicCapture();
        
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
      
      // End session in database
      await _attendanceService.endSession (_currentSession!.id);
      
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
  
  Future<void> startPeriodicCapture({
  required String sessionId,
  Duration interval = const Duration(minutes: 5),
  required Function(String imagePath, DateTime captureTime) onCapture,
}) async {}

  void _stopPeriodicCapture() {
    _cameraService.stopPeriodicCapture();
    print('⏹️ Stopped periodic capture');
  }

  Future<void> _captureFinalAttendance() async {
    try {
      print('📸 Taking final attendance snapshot...');
      final imagePath = await _cameraService.captureImage();
      
      if (imagePath != null) {
        await _processAttendanceImage(imagePath, isFinalCapture: true);
        print('✅ Final attendance snapshot processed');
      }
    } catch (e) {
      print('❌ Error in final capture: $e');
    }
  }

  // ========== Camera Event Handlers ==========
  
  void _handlePeriodicImage(String imagePath) {
    print('📷 Periodic image captured: $imagePath');
    _processAttendanceImage(imagePath);
  }

  void _handleCameraError(String error) {
    print('❌ Camera error: $error');
    if (mounted) {
      _showSnackBar('เกิดข้อผิดพลาดกับกล้อง: $error', Colors.red);
    }
  }

  void _handleCameraStatusChanged(bool isActive) {
    print('📸 Camera status changed: $isActive');
    if (mounted) {
      _showSnackBar(
        isActive ? 'เริ่มการเช็คชื่ออัตโนมัติ' : 'หยุดการเช็คชื่ออัตโนมัติ',
        isActive ? Colors.green : Colors.orange,
      );
    }
  }

  Future<void> _processAttendanceImage(String imagePath, {bool isFinalCapture = false}) async {
    try {
      // TODO: Send image to FastAPI for face recognition processing
      // This will be implemented with the new FastAPI endpoints
      
      print('🔄 Processing attendance image: $imagePath');
      print('   Session ID: ${_currentSession?.id}');
      print('   Is final capture: $isFinalCapture');
      
      // For now, just reload attendance records
      await _loadAttendanceRecords();
      
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
            onPressed: _showSessionSettings,
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
                child: CameraPreview(_cameraService.controller!),
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
                        final imagePath = await _cameraService.captureImage ();
                        if (imagePath != null) {
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
    final captureStatus = _cameraService.isRunning;

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
                    captureStatus ? 'เปิด' : 'ปิด',
                    captureStatus ? Colors.green : Colors.orange,
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
                    child: Text('ยังไม่มีการเช็คชื่อ'),
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
                        subtitle: Text(
                          '${record.timeOnly} - ${record.statusInThai}',
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

  void _showSessionSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ตั้งค่าการเช็คชื่อ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('ระยะเวลาคาบเรียน'),
                subtitle: Text('$_sessionDurationHours ชั่วโมง'),
                trailing: DropdownButton<int>(
                  value: _sessionDurationHours,
                  items: [1, 2, 3, 4].map((hours) => 
                    DropdownMenuItem(value: hours, child: Text('$hours ชั่วโมง'))
                  ).toList(),
                  onChanged: (value) {
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
                  items: [3, 5, 10, 15].map((minutes) => 
                    DropdownMenuItem(value: minutes, child: Text('$minutes นาที'))
                  ).toList(),
                  onChanged: (value) {
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
                  onChanged: (value) {
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