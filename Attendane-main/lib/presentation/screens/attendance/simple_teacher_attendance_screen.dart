// lib/presentation/screens/attendance/simple_teacher_attendance_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:myproject2/data/models/attendance_record_model.dart';
import 'package:myproject2/data/models/attendance_session_model.dart';
import 'package:myproject2/data/models/webcam_config_model.dart'; // เพิ่ม import

class SimpleTeacherAttendanceScreen extends StatefulWidget {
  final String classId;
  final String className;

  const SimpleTeacherAttendanceScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<SimpleTeacherAttendanceScreen> createState() => _SimpleTeacherAttendanceScreenState();
}

class _SimpleTeacherAttendanceScreenState extends State<SimpleTeacherAttendanceScreen> {
  final SimpleAttendanceService _attendanceService = SimpleAttendanceService();
  
  AttendanceSessionModel? _currentSession;
  List<AttendanceRecordModel> _attendanceRecords = [];
  Timer? _refreshTimer;
  
  bool _isLoading = false;
  bool _isCreatingSession = false;
  
  // เพิ่มตัวแปร webcam config ที่หายไป
  WebcamConfigModel? _webcamConfig;

  // Form controllers for creating session
  final _durationController = TextEditingController(text: '2');
  final _onTimeLimitController = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _loadActiveSession();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _durationController.dispose();
    _onTimeLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveSession() async {
    setState(() => _isLoading = true);
    
    try {
      final session = await _attendanceService.getActiveSessionForClass(widget.classId);
      
      if (mounted) {
        setState(() {
          _currentSession = session;
          _isLoading = false;
        });

        if (session != null) {
          _loadAttendanceRecords();
          _startAutoRefresh();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Error loading session: $e');
      }
    }
  }

  Future<void> _loadAttendanceRecords() async {
    if (_currentSession == null) return;

    try {
      final records = await _attendanceService.getAttendanceRecords(_currentSession!.id);
      
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
      if (_currentSession?.isActive == true) {
        _loadAttendanceRecords();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _createAttendanceSession() async {
    if (!_validateSessionForm()) return;

    setState(() => _isCreatingSession = true);

    try {
      final durationHours = int.parse(_durationController.text);
      final onTimeLimitMinutes = int.parse(_onTimeLimitController.text);

      final session = await _attendanceService.createAttendanceSession(
        classId: widget.classId,
        durationHours: durationHours,
        onTimeLimitMinutes: onTimeLimitMinutes,
      );

      if (mounted) {
        setState(() {
          _currentSession = session;
          _attendanceRecords = [];
          _isCreatingSession = false;
        });

        _startAutoRefresh();
        _showSuccessSnackBar('Attendance session started successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingSession = false);
        _showErrorSnackBar('Error creating session: $e');
      }
    }
  }

  bool _validateSessionForm() {
    final duration = int.tryParse(_durationController.text);
    final onTimeLimit = int.tryParse(_onTimeLimitController.text);

    if (duration == null || duration < 1 || duration > 8) {
      _showErrorSnackBar('Duration must be between 1-8 hours');
      return false;
    }

    if (onTimeLimit == null || onTimeLimit < 1 || onTimeLimit > 60) {
      _showErrorSnackBar('On-time limit must be between 1-60 minutes');
      return false;
    }

    return true;
  }

  Future<void> _endAttendanceSession() async {
    if (_currentSession == null) return;

    final confirm = await _showConfirmDialog(
      'End Attendance Session',
      'Are you sure you want to end the current attendance session? Students who haven\'t checked in will be marked as absent.',
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _attendanceService.endAttendanceSession(_currentSession!.id);
      
      if (mounted) {
        setState(() {
          _currentSession = null;
          _attendanceRecords = [];
          _isLoading = false;
        });

        _refreshTimer?.cancel();
        _showSuccessSnackBar('Attendance session ended successfully');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Error ending session: $e');
      }
    }
  }

  Future<void> _configureWebcam() async {
    final result = await showDialog<WebcamConfigModel>(
      context: context,
      builder: (context) => _SimpleWebcamConfigDialog(
        initialConfig: _webcamConfig ?? WebcamConfigModel(
          ipAddress: '192.168.1.100',
          port: 8080,
        ),
        attendanceService: _attendanceService,
      ),
    );

    if (result != null) {
      setState(() => _webcamConfig = result);
      _showSuccessSnackBar('Webcam configured successfully');
    }
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

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance - ${widget.className}'),
        centerTitle: true,
        actions: [
          if (_currentSession != null)
            IconButton(
              icon: const Icon(Icons.videocam),
              onPressed: _configureWebcam,
              tooltip: 'Configure Webcam',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadActiveSession,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _currentSession == null 
              ? _buildCreateSessionView()
              : _buildActiveSessionView(),
    );
  }

  Widget _buildCreateSessionView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create Attendance Session',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _durationController,
                    decoration: const InputDecoration(
                      labelText: 'Class Duration (hours)',
                      hintText: '2',
                      suffixText: 'hours',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _onTimeLimitController,
                    decoration: const InputDecoration(
                      labelText: 'On-time Limit (minutes)',
                      hintText: '30',
                      suffixText: 'minutes',
                      border: OutlineInputBorder(),
                      helperText: 'Students arriving after this time will be marked as late',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCreatingSession ? null : _createAttendanceSession,
                      icon: _isCreatingSession 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _isCreatingSession ? 'Creating...' : 'Start Attendance Session',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildWebcamSetupCard(),
        ],
      ),
    );
  }

  Widget _buildWebcamSetupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Webcam Setup',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure IP Webcam for capturing student photos during attendance.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, 
                           color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Setup Instructions:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Install "IP Webcam" app on Android phone\n'
                    '2. Connect phone to same WiFi network\n'
                    '3. Open app and tap "Start server"\n'
                    '4. Note the IP address shown\n'
                    '5. Configure webcam settings below',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _configureWebcam,
                icon: Icon(
                  _webcamConfig?.isConnected == true 
                      ? Icons.check_circle 
                      : Icons.settings,
                  color: _webcamConfig?.isConnected == true 
                      ? Colors.green 
                      : null,
                ),
                label: Text(
                  _webcamConfig?.isConnected == true 
                      ? 'Webcam Connected' 
                      : 'Configure Webcam',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionView() {
    if (_currentSession == null) return const SizedBox();

    final session = _currentSession!;
    final timeRemaining = session.endTime.difference(DateTime.now());
    final onTimeDeadline = session.onTimeDeadline;
    final isOnTimePeriod = DateTime.now().isBefore(onTimeDeadline);

    return Column(
      children: [
        // Session Info Card
        Card(
          margin: const EdgeInsets.all(16),
          color: session.isActive ? Colors.green.shade50 : Colors.grey.shade100,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      session.isActive ? Icons.radio_button_checked : Icons.stop_circle,
                      color: session.isActive ? Colors.green : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Attendance Session ${session.isActive ? "Active" : "Ended"}',
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
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        'Time Remaining',
                        timeRemaining.isNegative 
                            ? 'Ended' 
                            : '${timeRemaining.inHours}h ${timeRemaining.inMinutes % 60}m',
                        timeRemaining.isNegative ? Colors.red : Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoChip(
                        'On-time Until',
                        _formatTime(onTimeDeadline),
                        isOnTimePeriod ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
                if (session.isActive) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _endAttendanceSession,
                      icon: const Icon(Icons.stop),
                      label: const Text('End Session'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Attendance Records
        Expanded(
          child: Card(
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
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _attendanceRecords.length,
                          itemBuilder: (context, index) {
                            final record = _attendanceRecords[index];
                            return _buildAttendanceRecordTile(record);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
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

  Widget _buildAttendanceRecordTile(AttendanceRecordModel record) {
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
      leading: CircleAvatar(
        backgroundColor: statusColor.withOpacity(0.1),
        child: Icon(statusIcon, color: statusColor),
      ),
      title: Text(record.studentId),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(record.studentEmail),
          Text(
            'Checked in: ${_formatTime(record.checkInTime)}',
            style: const TextStyle(fontSize: 12),
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
}

// Simple Webcam Configuration Dialog
class _SimpleWebcamConfigDialog extends StatefulWidget {
  final WebcamConfigModel initialConfig;
  final SimpleAttendanceService attendanceService;

  const _SimpleWebcamConfigDialog({
    required this.initialConfig,
    required this.attendanceService,
  });

  @override
  State<_SimpleWebcamConfigDialog> createState() => _SimpleWebcamConfigDialogState();
}

class _SimpleWebcamConfigDialogState extends State<_SimpleWebcamConfigDialog> {
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  
  bool _isTestingConnection = false;
  bool _connectionSuccess = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialConfig.ipAddress);
    _portController = TextEditingController(text: widget.initialConfig.port.toString());
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final config = _buildConfig();
    
    setState(() => _isTestingConnection = true);
    
    try {
      final success = await widget.attendanceService.testWebcamConnection(config);
      
      setState(() {
        _connectionSuccess = success;
        _isTestingConnection = false;
      });

      if (success) {
        _showSnackBar('Connection successful!', Colors.green);
      } else {
        _showSnackBar('Connection failed. Please check your settings.', Colors.red);
      }
    } catch (e) {
      setState(() => _isTestingConnection = false);
      _showSnackBar('Connection error: $e', Colors.red);
    }
  }

  WebcamConfigModel _buildConfig() {
    return WebcamConfigModel(
      ipAddress: _ipController.text.trim(),
      port: int.tryParse(_portController.text) ?? 8080,
      isConnected: _connectionSuccess,
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure IP Webcam'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, 
                           color: Colors.blue.shade700, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'IP Webcam Setup:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Install "IP Webcam" from Play Store\n'
                    '2. Start the server in the app\n'
                    '3. Enter the IP address shown below',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8080',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.settings_ethernet),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isTestingConnection ? null : _testConnection,
                icon: _isTestingConnection
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _connectionSuccess ? Icons.check_circle : Icons.wifi,
                        color: _connectionSuccess ? Colors.green : null,
                      ),
                label: Text(
                  _isTestingConnection 
                      ? 'Testing...' 
                      : _connectionSuccess 
                          ? 'Connection OK' 
                          : 'Test Connection',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _connectionSuccess
              ? () => Navigator.of(context).pop(_buildConfig())
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}