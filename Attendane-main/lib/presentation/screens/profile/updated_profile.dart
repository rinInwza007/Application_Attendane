// lib/presentation/screens/profile/updated_profile.dart
import 'package:flutter/material.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/presentation/screens/settings/setting.dart';
import 'package:myproject2/presentation/screens/attendance/updated_student_attendance_screen.dart';
import 'package:myproject2/presentation/screens/face/multi_step_face_capture_screen.dart';


class UpdatedProfile extends StatefulWidget {
  const UpdatedProfile({super.key});

  @override
  State<UpdatedProfile> createState() => _UpdatedProfileState();
}

class _UpdatedProfileState extends State<UpdatedProfile> {
  final AuthService _authService = AuthService();
  int _selectedTabIndex = 0;
  bool _isLoading = false;
  final TextEditingController _classCodeController = TextEditingController();

  // Mock data structure for joined classes
  final List<Map<String, dynamic>> _joinedClasses = [];

  final Map<String, String> _classTypes = {
    'CS101': 'Main',
    'MT201': 'Main',
    'PHY101': 'Secondary',
    'ENG201': 'Secondary',
  };

  List<Map<String, dynamic>> get _filteredClasses {
    if (_selectedTabIndex == 0) return _joinedClasses;

    final filterType = _selectedTabIndex == 1 ? 'Main' : 'Secondary';
    return _joinedClasses
        .where((cls) => _classTypes[cls['id']] == filterType)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final classes = await _authService.getStudentClasses();
      setState(() {
        _joinedClasses.clear();
        _joinedClasses.addAll(classes);
      });
    } catch (e) {
      print('Error loading classes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load classes. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ตั้งค่า Face Recognition แบบใหม่
  Future<void> _setupFaceRecognition() async {
    final shouldSetup = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
  children: [
    Icon(Icons.face_6, color: Colors.blue), // เปลี่ยนจาก Icons.face_retouching_natural
    SizedBox(width: 12),
    Text('Setup Multi-Step Face Recognition'), // เปลี่ยนข้อความ
  ],
),
        content: const Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      'Advanced Multi-Step Face Recognition จะช่วยให้การเช็คชื่อปลอดภัยและแม่นยำมากขึ้น',
      style: TextStyle(fontWeight: FontWeight.w500),
    ),
    SizedBox(height: 12),
    Text('คุณสมบัติพิเศษ:'), // เปลี่ยนข้อความ
    SizedBox(height: 8),
    // เพิ่มคำอธิบายใหม่
    Row(
      children: [
        Icon(Icons.check, size: 16, color: Colors.green),
        SizedBox(width: 8),
        Expanded(child: Text('ถ่ายภาพใบหน้า 6 ท่าทาง (หน้าตรง, ซ้าย, ขวา, เงย, ก้ม, ยิ้ม)')),
      ],
    ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('ระบบตรวจจับใบหน้าอัตโนมัติ')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('ป้องกันการโกงและปลอดภัยสูง')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ข้ามไปก่อน'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
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
    
    if (shouldSetup == true && mounted) {
      _openFaceRegistration();
    }
  }

  // เปิดหน้าจอลงทะเบียนใบหน้าแบบ Real-time
  Future<void> _openFaceRegistration() async {
  if (!mounted) return;
  
  setState(() => _isLoading = true);
  
  try {
    debugPrint('📱 Opening multi-step face registration...');
    
    // เปลี่ยนชื่อตัวแปร
    final currentUserEmail = _authService.getCurrentUserEmail();
    
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => MultiStepFaceCaptureScreen(
          studentId: currentUserEmail?.split('@').first ?? 'unknown',
          studentEmail: currentUserEmail, // ใช้ชื่อใหม่
          isUpdate: true,
          onAllImagesCapture: (imagePaths) async {
            debugPrint('✅ All face images captured: ${imagePaths.length} images');
            
            try {
              debugPrint('🔄 Processing multi-step face images...');
            } catch (e) {
              debugPrint('❌ Error processing multi-step face images: $e');
              throw e;
            }
          },
        ),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('ตั้งค่า Face Recognition สำเร็จ!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    debugPrint('❌ Error in multi-step face registration: $e');
    if (mounted) {
      _showErrorSnackBar('เกิดข้อผิดพลาดในการตั้งค่า Multi-Step Face Recognition: ${e.toString()}');
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  // จัดการ Face Recognition ที่มีอยู่แล้ว
  Future<void> _manageFaceRecognition() async {
    final hasFace = await _authService.hasFaceEmbedding();
    
    if (!hasFace) {
      _setupFaceRecognition();
      return;
    }

    // แสดง dialog สำหรับจัดการ Face Recognition ที่มีอยู่
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: Colors.green),
            SizedBox(width: 12),
            Text('Face Recognition'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Face Recognition ของคุณพร้อมใช้งานแล้ว',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text('คุณสามารถ:'),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('เช็คชื่อด้วย Face Recognition')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.refresh, size: 16, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(child: Text('อัปเดตข้อมูลใบหน้าใหม่')),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.delete, size: 16, color: Colors.red),
                SizedBox(width: 8),
                Expanded(child: Text('ลบข้อมูลใบหน้า')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _updateFaceRecognition();
            },
            child: const Text('อัปเดต'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteFaceRecognition();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  // อัปเดตข้อมูล Face Recognition
  Future<void> _updateFaceRecognition() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('อัปเดต Face Recognition'),
        content: const Text(
          'คุณต้องการอัปเดตข้อมูลใบหน้าใหม่หรือไม่?\n\nข้อมูลใบหน้าเดิมจะถูกแทนที่ด้วยข้อมูลใหม่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('อัปเดต'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _openFaceRegistration();
    }
  }

  // ลบข้อมูล Face Recognition
  Future<void> _deleteFaceRecognition() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบ Face Recognition'),
        content: const Text(
          'คุณต้องการลบข้อมูล Face Recognition หรือไม่?\n\nหลังจากลบแล้ว คุณจะไม่สามารถเช็คชื่อด้วย Face Recognition ได้จนกว่าจะตั้งค่าใหม่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _authService.deactivateFaceEmbedding();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Row(
      children: [
        Icon(Icons.check_circle, color: Colors.white),
        SizedBox(width: 12),
        Text('ตั้งค่า Multi-Step Face Recognition สำเร็จ!'), // เปลี่ยนข้อความ
      ],
    ),
    backgroundColor: Colors.green,
    duration: Duration(seconds: 3),
  ),
);
          setState(() {}); // Refresh UI
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('ไม่สามารถลบข้อมูล Face Recognition ได้: ${e.toString()}');
        }
      }
    }
  }

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

  void _showClassPreview(Map<String, String> classData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(classData['name'] ?? ''),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _previewInfoRow('Course ID', classData['id']),
              _previewInfoRow('Teacher', classData['teacher']),
              _previewInfoRow('Schedule', classData['schedule']),
              _previewInfoRow('Room', classData['room']),
              const SizedBox(height: 12),
              Text(
                'Description',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Text(classData['description'] ?? ''),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final userEmail = _authService.getCurrentUserEmail();
                if (userEmail == null) {
                  throw Exception('User not logged in');
                }

                await _authService.joinClass(
                  classId: classData['id']!,
                  studentEmail: userEmail,
                );

                await _loadClasses();

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Successfully joined the class!')),
                );
              } catch (e) {
                print('Error joining class: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to join class. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade100,
              foregroundColor: Colors.purple.shade700,
            ),
            child: const Text('Join Class'),
          ),
        ],
      ),
    );
  }

  Widget _previewInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value ?? 'N/A'),
          ),
        ],
      ),
    );
  }

  void _handleSearch(String code, StateSetter setState,
      String? Function(String) updateError) async {
    if (code.isEmpty) {
      setState(() => updateError('Please enter a class code'));
      return;
    }

    try {
      final classDetails = await _authService.getClassByInviteCode(code);

      if (classDetails == null) {
        setState(() => updateError('The class code is not valid.'));
        return;
      }

      final classToJoin = {
        'id': classDetails['class_id']?.toString() ?? '',
        'name': classDetails['class_name']?.toString() ?? '',
        'teacher': classDetails['teacher_email']?.toString() ?? '',
        'code': code,
        'schedule': classDetails['schedule']?.toString() ?? '',
        'room': classDetails['room']?.toString() ?? '',
        'description': 'Join this class to start learning',
        'students': '0',
        'maxStudents': '50'
      };

      final userEmail = _authService.getCurrentUserEmail();
      if (userEmail == null) {
        setState(() => updateError('You must be logged in to join a class'));
        return;
      }

      if (_joinedClasses.any((c) => c['id'] == classDetails['class_id'])) {
        setState(() => updateError('You have already joined this class'));
        return;
      }

      _classCodeController.clear();
      Navigator.pop(context);
      _showClassPreview(classToJoin);
    } catch (e) {
      print('Error searching class: $e');
      setState(() => updateError('Error checking class code'));
    }
  }

  void _searchClass() {
    String? errorText;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Join Class'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _classCodeController,
                decoration: InputDecoration(
                  labelText: 'Enter Class Code',
                  hintText: 'e.g., CS101-2024',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (errorText != null) {
                    setState(() => errorText = null);
                  }
                },
                onSubmitted: (value) {
                  _handleSearch(value, setState, (msg) => errorText = msg);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final code = _classCodeController.text.trim();
                    _handleSearch(code, setState, (msg) => errorText = msg);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade100,
                    foregroundColor: Colors.purple.shade700,
                  ),
                  child: const Text('Search'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _leaveClass(int index) {
    final classData = _joinedClasses[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Class'),
        content: Text('Are you sure you want to leave ${classData['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final userEmail = _authService.getCurrentUserEmail();
                if (userEmail == null) {
                  throw Exception('User not logged in');
                }

                await _authService.leaveClass(
                  classId: classData['id'],
                  studentEmail: userEmail,
                );

                await _loadClasses();

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Successfully left the class'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                print('Error leaving class: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to leave class. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _toggleFavorite(int index) {
    setState(() {
      _joinedClasses[index]['isFavorite'] =
          !_joinedClasses[index]['isFavorite'];
    });
  }

  // ปุ่มสำหรับไปหน้าเช็คชื่อแบบใหม่
  void _goToAttendance(Map<String, dynamic> classData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UpdatedStudentAttendanceScreen(
          classId: classData['id'],
          className: classData['name'],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  void dispose() {
    _classCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = _authService.getCurrentUserEmail();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Student Home',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // ปุ่มจัดการ Face Recognition
          IconButton(
    icon: const Icon(Icons.face_6), // เปลี่ยนจาก Icons.face_retouching_natural
    onPressed: _manageFaceRecognition,
    tooltip: 'Manage Multi-Step Face Recognition', // เปลี่ยน tooltip
  ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const Setting()),
            ).then((_) => setState(() {})),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildProfileHeader(currentEmail),
                const SizedBox(height: 16),
                _buildTabBar(),
                const SizedBox(height: 16),
                _buildClassList(),
                _buildJoinClassButton(),
              ],
            ),
    );
  }

  Widget _buildClassList() {
    final displayedClasses = _filteredClasses;
    return Expanded(
      child: displayedClasses.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.school_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No classes joined yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join a class to get started!',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: displayedClasses.length,
              itemBuilder: (context, index) => _buildClassCard(index),
            ),
    );
  }

  Widget _buildClassCard(int index) {
    final classData = _filteredClasses[index];
    final joinedDate = classData['joinedDate'] as DateTime;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      classData['id']?.substring(0, 2) ?? 'NA',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        classData['id'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        classData['name'] ?? '',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Teacher: ${classData['teacher']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    // ปุ่มเช็คชื่อแบบใหม่
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
  icon: Icon(
    Icons.face_6, // เปลี่ยนจาก Icons.face_retouching_natural
    color: Colors.green.shade700,
  ),
  onPressed: () => _goToAttendance(classData),
  tooltip: 'Multi-Step Face Recognition Check-in', // เปลี่ยน tooltip
),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        classData['isFavorite']
                            ? Icons.star
                            : Icons.star_border,
                        color: classData['isFavorite']
                            ? Colors.amber
                            : Colors.grey,
                      ),
                      onPressed: () => _toggleFavorite(index),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.exit_to_app,
                        color: Colors.red,
                      ),
                      onPressed: () => _leaveClass(index),
                      tooltip: 'Leave Class',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Joined on: ${_formatDate(joinedDate)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinClassButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: _searchClass,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple.shade100,
          foregroundColor: Colors.purple.shade700,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline),
            SizedBox(width: 8),
            Text(
              'Join Class',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(String? email) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.purple.shade200,
            child: const Icon(Icons.person, size: 35, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Student',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email ?? 'No email',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.purple.shade700,
                  ),
                ),
              ],
            ),
          ),
          // แสดงสถานะ Face Recognition แบบใหม่
          FutureBuilder<bool>(
            future: _authService.hasFaceEmbedding(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              
              final hasFace = snapshot.data ?? false;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: hasFace ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
  hasFace ? Icons.verified_user : Icons.face_6, // เปลี่ยนจาก Icons.face_retouching_off
  size: 18,
  color: hasFace ? Colors.green.shade700 : Colors.orange.shade700,
),
Text(
  hasFace ? 'Multi-Step Ready' : 'Setup Face ID', // เปลี่ยนข้อความ
  style: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: hasFace ? Colors.green.shade700 : Colors.orange.shade700,
  ),
),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = ['All Classes', 'Main Classes', 'Secondary Classes'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final text = entry.value;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: index == 1 ? 8 : 0,
              ),
              child: _buildTabButton(text, index),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabButton(String text, int index) {
    final isSelected = _selectedTabIndex == index;
    return ElevatedButton(
      onPressed: () => setState(() => _selectedTabIndex = index),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isSelected ? Colors.purple.shade100 : Colors.grey.shade100,
        elevation: isSelected ? 2 : 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isSelected ? Colors.purple.shade700 : Colors.grey.shade700,
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}