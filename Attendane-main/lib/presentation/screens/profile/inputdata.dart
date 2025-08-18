import 'dart:io';
import 'package:flutter/material.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/face_recognition_service.dart';
import 'package:myproject2/presentation/screens/profile/profileteachaer.dart';
import 'package:myproject2/presentation/screens/profile/updated_profile.dart';

class InputDataPage extends StatefulWidget {
  const InputDataPage({super.key});

  @override
  State<InputDataPage> createState() => _InputDataPageState();
}

class _InputDataPageState extends State<InputDataPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _fullNameController = TextEditingController();
  final _schoolIdController = TextEditingController();
  bool _isLoading = false;
  bool _isFaceProcessing = false;
  String _selectedRole = 'student';

  @override
  void dispose() {
    _fullNameController.dispose();
    _schoolIdController.dispose();
    super.dispose();
  }

  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your full name';
    }
    if (value.length < 2) {
      return 'Name must be at least 2 characters long';
    }
    return null;
  }

  String? _validateSchoolId(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your school ID';
    }
    if (value.length < 5) {
      return 'School ID must be at least 5 characters';
    }
    return null;
  }

  Future<void> _saveUserProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      print('🔄 Saving user profile...');
      
      // บันทึกข้อมูลผู้ใช้ก่อน
      await _authService.saveUserProfile(
        fullName: _fullNameController.text.trim(),
        schoolId: _schoolIdController.text.trim(),
        userType: _selectedRole,
      );

      print('✅ User profile saved successfully');

      // ตรวจสอบว่าข้อมูลบันทึกสำเร็จ
      final savedProfile = await _authService.getUserProfile();
      if (savedProfile == null) {
        throw Exception('Failed to save user profile');
      }

      print('📋 Saved profile: $savedProfile');

      // ถ้าเป็นนักเรียน ต้องถ่ายรูปก่อน
      if (_selectedRole == 'student') {
        print('👨‍🎓 User is student, checking face data...');
        
        if (!mounted) return;
        
        await _handleStudentFaceCapture();
      }

      // เมื่อทุกอย่างเรียบร้อย นำทางไปยังหน้าที่เหมาะสม
      if (mounted) {
        _navigateToProfilePage();
      }
    } catch (e) {
      print('❌ Error in _saveUserProfile: $e');
      if (mounted) {
        _showErrorDialog(
          'เกิดข้อผิดพลาดในการบันทึกข้อมูล: ${e.toString()}',
          showRetry: true,
          onRetry: _saveUserProfile,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleStudentFaceCapture() async {
    if (!mounted) return;
    
    final hasFace = await _authService.hasFaceEmbedding();
    if (hasFace) {
      print('✅ Face data already exists');
      return;
    }

    print('📸 No face data found, starting face capture...');
    
    bool faceProcessed = false;
    int attempts = 0;
    const maxAttempts = 3;

    while (!faceProcessed && attempts < maxAttempts && mounted) {
      attempts++;
      print('🔄 Face capture attempt $attempts/$maxAttempts');
      
      try {
        await _processFaceCapture();
        
        // ตรวจสอบอีกครั้งว่ามีข้อมูลใบหน้าแล้ว
        faceProcessed = await _authService.hasFaceEmbedding();

        if (!faceProcessed && mounted) {
          final shouldRetry = await _showRetryDialog(
            'ข้อมูลใบหน้าไม่สมบูรณ์',
            'การบันทึกข้อมูลใบหน้าไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
            attempts < maxAttempts,
          );
          
          if (!shouldRetry) break;
        }
      } catch (e) {
        print('❌ Error in face capture attempt $attempts: $e');
        if (mounted) {
          final shouldRetry = await _showRetryDialog(
            'เกิดข้อผิดพลาด',
            e.toString(),
            attempts < maxAttempts,
          );
          
          if (!shouldRetry) break;
        }
      }
    }

    // ตรวจสอบสุดท้าย
    final finalCheck = await _authService.hasFaceEmbedding();
    if (!finalCheck && mounted) {
      _showErrorDialog(
        'ไม่สามารถบันทึกข้อมูลใบหน้าได้หลังจากพยายาม $attempts ครั้ง\nกรุณาติดต่อผู้ดูแลระบบ',
        showRetry: false,
      );
      throw Exception('Failed to save face data after $attempts attempts');
    }
  }

  Future<void> _processFaceCapture() async {
    if (!mounted) return;
    
    setState(() => _isFaceProcessing = true);
    
    try {
      print('📱 Opening image picker...');
      
      final String? imagePath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => ImagePickerScreen(
            instructionText: "กรุณาเลือกรูปภาพที่เห็นใบหน้าชัดเจน และต้องมีเพียงใบหน้าของคุณเท่านั้น",
          ),
        ),
      );

      if (!mounted) return;

      if (imagePath == null) {
        throw Exception('ไม่ได้เลือกรูปภาพ');
      }

      print('📷 Image selected: $imagePath');

      // ตรวจสอบไฟล์ก่อนประมวลผล
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('ไม่พบไฟล์รูปภาพที่เลือก');
      }

      final fileStat = await file.stat();
      if (fileStat.size == 0) {
        throw Exception('ไฟล์รูปภาพเสียหายหรือว่างเปล่า');
      }

      print('🔍 File validation passed, size: ${fileStat.size} bytes');

      // ประมวลผลใบหน้า
      final faceService = FaceRecognitionService();
      
      try {
        print('🤖 Initializing face recognition service...');
        await faceService.initialize();
        
        print('🧠 Processing face embedding...');
        final embedding = await faceService.getFaceEmbedding(imagePath);
        
        print('💾 Saving face embedding to database...');
        await _authService.saveFaceEmbedding(embedding);
        
        print('✅ Face embedding saved successfully');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกข้อมูลใบหน้าสำเร็จ'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } finally {
        await faceService.dispose();
        print('🧹 Face recognition service disposed');
      }

      // ลบไฟล์ชั่วคราว
      try {
        if (await file.exists()) {
          await file.delete();
          print('🗑️ Temporary image file deleted');
        }
      } catch (e) {
        print('⚠️ Failed to delete temporary file: $e');
      }

    } catch (e) {
      print('❌ Error in _processFaceCapture: $e');
      
      String errorMessage = 'เกิดข้อผิดพลาด: ${e.toString()}';
      
      if (e.toString().contains('ไม่พบใบหน้า')) {
        errorMessage = 'ไม่พบใบหน้าในรูปภาพ กรุณาเลือกรูปที่เห็นใบหน้าชัดเจน';
      } else if (e.toString().contains('พบใบหน้าหลาย')) {
        errorMessage = 'พบใบหน้าหลายใบในรูปภาพ กรุณาเลือกรูปที่มีเพียงใบหน้าของคุณเท่านั้น';
      } else if (e.toString().contains('ไม่ได้เลือกรูปภาพ')) {
        errorMessage = 'กรุณาเลือกรูปภาพใบหน้าเพื่อดำเนินการต่อ';
      }
      
      throw Exception(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isFaceProcessing = false);
      }
    }
  }

  Future<bool> _showRetryDialog(String title, String message, bool canRetry) async {
    if (!mounted) return false;
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (canRetry)
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ลองใหม่'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(canRetry ? 'ข้าม' : 'ปิด'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showErrorDialog(String message, {bool showRetry = false, VoidCallback? onRetry}) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เกิดข้อผิดพลาด'),
        content: Text(message),
        actions: [
          if (showRetry && onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onRetry();
              },
              child: const Text('ลองใหม่'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  void _navigateToProfilePage() {
    if (!mounted) return;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => _selectedRole == 'teacher'
            ? const TeacherProfile()
            : const UpdatedProfile(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'User Information',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _selectedRole == 'teacher'
                          ? Icons.school
                          : Icons.person_outline,
                      size: 100,
                      color: Colors.purple.shade400,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'Welcome!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please complete your profile',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 32),

                  // Role Selection
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select your role',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildRoleOption(
                                'student', 'Student', Icons.person),
                            const SizedBox(width: 12),
                            _buildRoleOption(
                                'teacher', 'Teacher', Icons.school),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextFormField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      hintText: 'Enter your full name',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: _validateFullName,
                    textCapitalization: TextCapitalization.words,
                    enabled: !_isLoading && !_isFaceProcessing,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _schoolIdController,
                    decoration: InputDecoration(
                      labelText: 'School ID',
                      hintText: 'Enter your school ID',
                      prefixIcon: const Icon(Icons.numbers),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: _validateSchoolId,
                    enabled: !_isLoading && !_isFaceProcessing,
                  ),
                  const SizedBox(height: 40),

                  // Loading indicator for face processing
                  if (_isFaceProcessing)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'กำลังประมวลผลข้อมูลใบหน้า...',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (_isLoading || _isFaceProcessing) ? null : _saveUserProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade400,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _selectedRole == 'student' 
                                  ? 'Save Profile & Setup Face ID'
                                  : 'Save Profile',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleOption(String role, String label, IconData icon) {
    final isSelected = _selectedRole == role;
    return Expanded(
      child: InkWell(
        onTap: (_isLoading || _isFaceProcessing) ? null : () => setState(() => _selectedRole = role),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.purple.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.purple.shade400 : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color:
                    isSelected ? Colors.purple.shade400 : Colors.grey.shade600,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.purple.shade700
                      : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}