import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImagePickerScreen extends StatefulWidget {
  final Function(String imagePath)? onImageCaptured;
  final String? instructionText;

  const ImagePickerScreen({
    super.key,
    this.onImageCaptured,
    this.instructionText,
  });

  @override
  ImagePickerScreenState createState() => ImagePickerScreenState();
}

class ImagePickerScreenState extends State<ImagePickerScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    // ลบไฟล์ชั่วคราวถ้ามี
    _cleanupTempFile();
    super.dispose();
  }

  Future<void> _cleanupTempFile() async {
    if (_imagePath != null) {
      try {
        final file = File(_imagePath!);
        if (await file.exists()) {
          await file.delete();
          print('🗑️ Temporary file cleaned up: $_imagePath');
        }
      } catch (e) {
        print('⚠️ Failed to cleanup temp file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // ลบไฟล์ชั่วคราวเมื่อกลับ
        await _cleanupTempFile();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('เลือกรูปภาพใบหน้า'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _cleanupTempFile();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // คำแนะนำ
              if (widget.instructionText != null)
                Container(
                  margin: const EdgeInsets.all(16.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, 
                           color: Colors.blue.shade700, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.instructionText!,
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // แสดง error message ถ้ามี
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, 
                           color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _errorMessage = null),
                        color: Colors.red.shade700,
                      ),
                    ],
                  ),
                ),

              // แสดงรูปภาพที่เลือก หรือข้อความแนะนำ
              Expanded(
                child: _imagePath == null
                    ? _buildEmptyState()
                    : _buildImagePreview(),
              ),

              // ปุ่มควบคุม
              _buildControlButtons(),
              
              // แสดง loading indicator
              if (_isProcessing)
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'กำลังประมวลผลรูปภาพ...',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'ยังไม่ได้เลือกรูปภาพ',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'กรุณาเลือกรูปภาพใบหน้าของคุณ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // แสดงรูปภาพที่เลือก
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_imagePath!),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _errorMessage = 'ไม่สามารถแสดงรูปภาพได้';
                      _imagePath = null;
                    });
                  }
                });
                return Container(
                  color: Colors.grey.shade200,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, 
                             size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text('ไม่สามารถแสดงรูปภาพได้',
                             style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        
        // ปุ่มลบรูปภาพ
        Positioned(
          top: 24,
          right: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: _isProcessing ? null : () {
                _cleanupTempFile();
                setState(() {
                  _imagePath = null;
                  _errorMessage = null;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_imagePath == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _pickImageFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('เลือกรูปภาพ'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.purple.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _pickImageFromGallery,
                    icon: const Icon(Icons.refresh),
                    label: const Text('เลือกใหม่'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.purple.shade400),
                      foregroundColor: Colors.purple.shade400,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _confirmSelection,
                    icon: const Icon(Icons.check),
                    label: const Text('ยืนยัน'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _pickImageFromGallery() async {
    if (!mounted) return;
    
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      print('📱 Opening image picker...');
      
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (!mounted) return;

      if (image == null) {
        setState(() => _isProcessing = false);
        return;
      }

      print('📷 Image selected: ${image.path}');

      // ตรวจสอบไฟล์ต้นฉบับ
      final originalFile = File(image.path);
      if (!await originalFile.exists()) {
        throw Exception('ไฟล์รูปภาพไม่ถูกต้อง');
      }

      final fileStat = await originalFile.stat();
      if (fileStat.size == 0) {
        throw Exception('ไฟล์รูปภาพเสียหายหรือว่างเปล่า');
      }

      if (fileStat.size > 10 * 1024 * 1024) { // 10MB limit
        throw Exception('ไฟล์รูปภาพมีขนาดใหญ่เกินไป (ขีดจำกัด 10MB)');
      }

      // ตรวจสอบนามสกุลไฟล์
      final extension = path.extension(image.path).toLowerCase();
      if (!['.jpg', '.jpeg', '.png'].contains(extension)) {
        throw Exception('รูปแบบไฟล์ไม่รองรับ กรุณาเลือกไฟล์ .jpg, .jpeg หรือ .png');
      }

      print('✅ File validation passed');

      // สร้างชื่อไฟล์ใหม่
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String imageName = 'face_$timestamp.jpg';
      final String newFilePath = path.join(appDir.path, imageName);
      
      print('📂 Copying file to: $newFilePath');

      // คัดลอกไฟล์
      await originalFile.copy(newFilePath);

      // ตรวจสอบไฟล์ที่คัดลอกแล้ว
      final copiedFile = File(newFilePath);
      if (!await copiedFile.exists()) {
        throw Exception('ไม่สามารถบันทึกรูปภาพได้');
      }

      final copiedStat = await copiedFile.stat();
      if (copiedStat.size == 0) {
        await copiedFile.delete();
        throw Exception('การคัดลอกไฟล์ล้มเหลว');
      }

      print('✅ File copied successfully, size: ${copiedStat.size} bytes');

      // ลบไฟล์เก่าถ้ามี
      await _cleanupTempFile();

      if (mounted) {
        setState(() {
          _imagePath = newFilePath;
          _isProcessing = false;
          _errorMessage = null;
        });
      }

    } catch (e) {
      print('❌ Error in _pickImageFromGallery: $e');
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _confirmSelection() async {
    if (_imagePath == null || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      // ตรวจสอบไฟล์อีกครั้งก่อนส่งกลับ
      final file = File(_imagePath!);
      if (!await file.exists()) {
        throw Exception('ไฟล์รูปภาพหายไป กรุณาเลือกใหม่');
      }

      final fileStat = await file.stat();
      if (fileStat.size == 0) {
        throw Exception('ไฟล์รูปภาพเสียหาย กรุณาเลือกใหม่');
      }

      print('✅ File validation passed, returning: $_imagePath');

      // ส่งค่ากลับโดยไม่ลบไฟล์ (ให้หน้าที่เรียกใช้จัดการ)
      if (widget.onImageCaptured != null) {
        widget.onImageCaptured!(_imagePath!);
      }

      if (mounted) {
        Navigator.of(context).pop(_imagePath);
      }

    } catch (e) {
      print('❌ Error in _confirmSelection: $e');
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }
}