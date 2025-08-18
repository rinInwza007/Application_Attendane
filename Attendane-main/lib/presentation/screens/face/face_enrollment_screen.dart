// lib/presentation/screens/face/face_enrollment_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/presentation/common_widgets/image_picker_screen.dart';

class FaceEnrollmentScreen extends StatefulWidget {
  final bool isUpdate; // true = อัปเดตข้อมูลเดิม, false = ลงทะเบียนใหม่

  const FaceEnrollmentScreen({
    super.key,
    this.isUpdate = false,
  });

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  final AuthService _authService = AuthService();
  
  // Camera controller
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  
  // Face images
  List<String> _capturedImages = [];
  final int _requiredImages = 3; // จำนวนรูปที่ต้องการ
  
  // State management
  bool _isProcessing = false;
  bool _isUploading = false;
  String _statusMessage = 'กรุณาถ่ายรูปใบหน้าของคุณ 3 รูป';
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _cleanupImages();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _statusMessage = 'ไม่พบกล้องในเครื่อง';
        });
        return;
      }

      // ใช้กล้องหน้าถ้ามี
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _statusMessage = widget.isUpdate 
              ? 'อัปเดตข้อมูลใบหน้า - ถ่ายรูปใหม่ 3 รูป'
              : 'ลงทะเบียนใบหน้า - ถ่ายรูป 3 รูป';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'ไม่สามารถเปิดกล้องได้: $e';
      });
    }
  }

  Future<void> _captureImage() async {
    if (!_isCameraInitialized || _cameraController == null) return;
    if (_capturedImages.length >= _requiredImages) return;
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'กำลังถ่ายรูป...';
    });

    try {
      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();
      
      // Save to permanent location
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'face_enrollment_${_capturedImages.length + 1}_$timestamp.jpg';
      final String savedPath = path.join(appDir.path, 'face_enrollment', fileName);
      
      // Ensure directory exists
      final Directory faceDir = Directory(path.dirname(savedPath));
      if (!await faceDir.exists()) {
        await faceDir.create(recursive: true);
      }
      
      // Copy to permanent location
      await File(imageFile.path).copy(savedPath);
      
      // Add to list
      setState(() {
        _capturedImages.add(savedPath);
        _statusMessage = _capturedImages.length < _requiredImages
            ? 'ถ่ายรูปแล้ว ${_capturedImages.length}/$_requiredImages รูป'
            : 'ถ่ายรูปครบแล้ว! กดปุ่มบันทึกเพื่อลงทะเบียน';
      });

      // Delete temporary file
      await File(imageFile.path).delete();

    } catch (e) {
      setState(() {
        _statusMessage = 'เกิดข้อผิดพลาดในการถ่ายรูป: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _addImageFromGallery() async {
    if (_capturedImages.length >= _requiredImages) return;

    try {
      final String? imagePath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => ImagePickerScreen(
            instructionText: "เลือกรูปใบหน้าที่ชัดเจน มีเพียงใบหน้าของคุณเท่านั้น",
          ),
        ),
      );

      if (imagePath != null && mounted) {
        setState(() {
          _capturedImages.add(imagePath);
          _statusMessage = _capturedImages.length < _requiredImages
              ? 'เลือกรูปแล้ว ${_capturedImages.length}/$_requiredImages รูป'
              : 'เลือกรูปครบแล้ว! กดปุ่มบันทึกเพื่อลงทะเบียน';
        });
      }
    } catch (e) {
      _showErrorSnackBar('เกิดข้อผิดพลาดในการเลือกรูป: $e');
    }
  }

  void _removeImage(int index) {
    if (index < 0 || index >= _capturedImages.length) return;

    setState(() {
      final imagePath = _capturedImages.removeAt(index);
      _statusMessage = 'ลบรูปแล้ว - เหลือ ${_capturedImages.length}/$_requiredImages รูป';
    });

    // Delete file
    File(imagePath).delete().catchError((e) {
      print('Error deleting file: $e');
    });
  }

  Future<void> _processEnrollment() async {
    if (_capturedImages.length < _requiredImages) {
      _showErrorSnackBar('กรุณาถ่ายรูปให้ครบ $_requiredImages รูป');
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'กำลังประมวลผลและบันทึกข้อมูลใบหน้า...';
    });

    try {
      // TODO: Send images to FastAPI for processing
      // For now, simulate processing
      await Future.delayed(const Duration(seconds: 3));

      // Get user profile for student ID
      final userProfile = await _authService.getUserProfile();
      if (userProfile == null) {
        throw Exception('ไม่พบข้อมูลผู้ใช้');
      }

      final studentId = userProfile['school_id'];
      final studentEmail = userProfile['email'];

      // Process each image and create embeddings
      final List<List<double>> embeddings = [];
      
      for (int i = 0; i < _capturedImages.length; i++) {
        setState(() {
          _statusMessage = 'กำลังประมวลผลรูปที่ ${i + 1}/$_requiredImages...';
        });

        // TODO: Send to FastAPI for face embedding extraction
        // final embedding = await _sendImageToAPI(_capturedImages[i], studentId, studentEmail);
        
        // For now, create dummy embedding
        final dummyEmbedding = List.generate(128, (index) => (index * 0.01));
        embeddings.add(dummyEmbedding);
        
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Calculate average embedding
      final averageEmbedding = _calculateAverageEmbedding(embeddings);

      // Save to database
      if (widget.isUpdate) {
        // Update existing face data
        await _authService.saveFaceEmbedding(averageEmbedding);
        setState(() {
          _statusMessage = 'อัปเดตข้อมูลใบหน้าสำเร็จ!';
        });
      } else {
        // Save new face data
        await _authService.saveFaceEmbedding(averageEmbedding);
        setState(() {
          _statusMessage = 'ลงทะเบียนใบหน้าสำเร็จ!';
        });
      }

      // Clean up images
      await _cleanupImages();

      // Show success message and go back
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        Navigator.of(context).pop(true);
      }

    } catch (e) {
      setState(() {
        _statusMessage = 'เกิดข้อผิดพลาด: $e';
        _isUploading = false;
      });
      
      _showErrorSnackBar('ไม่สามารถบันทึกข้อมูลใบหน้าได้: $e');
    }
  }

  List<double> _calculateAverageEmbedding(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];
    
    final embeddingSize = embeddings.first.length;
    final averageEmbedding = List<double>.filled(embeddingSize, 0.0);
    
    // Sum all embeddings
    for (final embedding in embeddings) {
      for (int i = 0; i < embeddingSize; i++) {
        averageEmbedding[i] += embedding[i];
      }
    }
    
    // Calculate average
    for (int i = 0; i < embeddingSize; i++) {
      averageEmbedding[i] /= embeddings.length;
    }
    
    return averageEmbedding;
  }

  Future<void> _cleanupImages() async {
    for (final imagePath in _capturedImages) {
      try {
        await File(imagePath).delete();
      } catch (e) {
        print('Error deleting file $imagePath: $e');
      }
    }
    _capturedImages.clear();
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.isUpdate ? 'อัปเดตข้อมูลใบหน้า' : 'ลงทะเบียนใบหน้า',
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            await _cleanupImages();
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
      body: Column(
        children: [
          // Status message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.black.withOpacity(0.8),
            child: Text(
              _statusMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Camera preview or loading
          Expanded(
            flex: 3,
            child: _isUploading
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'กำลังประมวลผล...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  )
                : _isCameraInitialized && _cameraController != null
                    ? Stack(
                        children: [
                          CameraPreview(_cameraController!),
                          
                          // Face detection overlay
                          Positioned.fill(
                            child: CustomPaint(
                              painter: FaceEnrollmentOverlayPainter(),
                            ),
                          ),
                          
                          // Capture progress indicator
                          Positioned(
                            top: 20,
                            left: 20,
                            right: 20,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(_requiredImages, (index) {
                                  final isCompleted = index < _capturedImages.length;
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isCompleted ? Colors.green : Colors.white.withOpacity(0.3),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        color: Colors.black,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 16),
                              Text(
                                'กำลังเปิดกล้อง...',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
          
          // Captured images preview
          if (_capturedImages.isNotEmpty)
            Container(
              height: 120,
              color: Colors.grey.shade900,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                itemCount: _capturedImages.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_capturedImages[index]),
                            width: 80,
                            height: 104,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          
          // Control buttons
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            child: Column(
              children: [
                if (_capturedImages.length < _requiredImages) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _captureImage,
                          icon: _isProcessing 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.camera_alt),
                          label: Text(_isProcessing ? 'กำลังถ่าย...' : 'ถ่ายรูป'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addImageFromGallery,
                          icon: const Icon(Icons.photo_library, color: Colors.white),
                          label: const Text(
                            'เลือกรูป',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : _processEnrollment,
                      icon: _isUploading 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        _isUploading 
                            ? 'กำลังประมวลผล...' 
                            : widget.isUpdate 
                                ? 'อัปเดตข้อมูลใบหน้า'
                                : 'บันทึกข้อมูลใบหน้า',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _isUploading ? null : () {
                      setState(() {
                        _capturedImages.clear();
                        _statusMessage = 'ถ่ายรูปใหม่ให้ครบ $_requiredImages รูป';
                      });
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'ถ่ายใหม่',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for face enrollment overlay
class FaceEnrollmentOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.white.withOpacity(0.8);

    // Draw face detection oval
    final center = Offset(size.width / 2, size.height / 2);
    final radiusX = size.width * 0.35;
    final radiusY = size.height * 0.4;

    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radiusX * 2,
        height: radiusY * 2,
      ),
      paint,
    );

    // Draw corner guides
    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.white;

    final cornerLength = 30.0;
    final left = center.dx - radiusX;
    final right = center.dx + radiusX;
    final top = center.dy - radiusY;
    final bottom = center.dy + radiusY;

    // Top-left corner
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left, top + cornerLength), cornerPaint);

    // Top-right corner
    canvas.drawLine(Offset(right, top), Offset(right - cornerLength, top), cornerPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLength), cornerPaint);

    // Bottom-left corner
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLength, bottom), cornerPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - cornerLength), cornerPaint);

    // Bottom-right corner
    canvas.drawLine(Offset(right, bottom), Offset(right - cornerLength, bottom), cornerPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLength), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}