// lib/presentation/screens/face/realtime_face_detection_screen.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:myproject2/data/services/face_recognition_service.dart';
import 'package:myproject2/data/services/auth_service.dart';

class RealtimeFaceDetectionScreen extends StatefulWidget {
  final String? sessionId;
  final bool isRegistration;
  final String? instructionText;
  final Function(List<double> embedding)? onFaceEmbeddingCaptured;
  final Function(String message)? onCheckInSuccess;

  const RealtimeFaceDetectionScreen({
    super.key,
    this.sessionId,
    this.isRegistration = false,
    this.instructionText,
    this.onFaceEmbeddingCaptured,
    this.onCheckInSuccess,
  });

  @override
  State<RealtimeFaceDetectionScreen> createState() => _RealtimeFaceDetectionScreenState();
}

class _RealtimeFaceDetectionScreenState extends State<RealtimeFaceDetectionScreen>
    with WidgetsBindingObserver {
  
  // Camera และ Face Detection
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;
  late final FaceRecognitionService _faceService;
  late final AuthService _authService;
  
  // State Management
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _faceDetected = false;
  bool _faceVerified = false;
  bool _isCapturing = false;
  
  // Face Detection Data
  Face? _currentFace;
  Rect? _faceRect;
  double _confidence = 0.0;
  String _statusMessage = "กรุณาวางใบหน้าของคุณในกรอบ";
  Color _statusColor = Colors.orange;
  
  // Timer และ Animation
  int _countdown = 0;
  bool _showCountdown = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeResources();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeServices() async {
    try {
      print('🔄 Initializing services...');
      
      // สร้าง Face Detector
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
          enableTracking: true,
          minFaceSize: 0.15,
          enableContours: true,
        ),
      );
      
      _faceService = FaceRecognitionService();
      _authService = AuthService();
      
      await _faceService.initialize();
      await _initializeCamera();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = "กรุณาวางใบหน้าของคุณในกรอบ";
        });
      }
      
      print('✅ Services initialized successfully');
    } catch (e) {
      print('❌ Error initializing services: $e');
      if (mounted) {
        _showErrorDialog('ไม่สามารถเปิดกล้องได้', e.toString());
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('ไม่พบกล้องในเครื่อง');
      }
      
      // ใช้กล้องหน้าถ้ามี ไม่งั้นใช้กล้องแรกที่หาเจอ
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {});
        _startImageStream();
      }
    } catch (e) {
      print('❌ Error initializing camera: $e');
      if (mounted) {
        _showErrorDialog('ไม่สามารถเปิดกล้องได้', e.toString());
      }
    }
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    _cameraController!.startImageStream((CameraImage image) async {
      if (_isProcessing) return;
      
      _isProcessing = true;
      await _processImage(image);
      _isProcessing = false;
    });
  }

  Future<void> _processImage(CameraImage image) async {
    try {
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) return;
      
      final faces = await _faceDetector.processImage(inputImage);
      
      if (!mounted) return;
      
      setState(() {
        if (faces.isNotEmpty) {
          _currentFace = faces.first;
          _faceDetected = true;
          _updateFaceStatus(_currentFace!);
        } else {
          _currentFace = null;
          _faceDetected = false;
          _faceVerified = false;
          _statusMessage = "ไม่พบใบหน้า กรุณาวางหน้าในกรอบ";
          _statusColor = Colors.red;
          _confidence = 0.0;
        }
      });
      
      // ถ้าตรวจพบใบหน้าที่ดีและยังไม่ได้เริ่มนับถอยหลัง
      if (_faceDetected && _isGoodFace(_currentFace!) && !_showCountdown && !_isCapturing) {
        _startCountdown();
      }
      
    } catch (e) {
      print('❌ Error processing image: $e');
    }
  }

  // แก้ไขการแปลง CameraImage เป็น InputImage
  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      // สำหรับ Android ใช้ nv21 format
      if (Platform.isAndroid) {
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg, // ปรับตามการหมุนของกล้อง
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }
      
      // สำหรับ iOS ใช้ bgra8888 format
      if (Platform.isIOS) {
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.bgra8888,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }
      
      return null;
    } catch (e) {
      print('❌ Error converting camera image: $e');
      return null;
    }
  }

  void _updateFaceStatus(Face face) {
    double qualityScore = 0.0;
    String message = "";
    Color color = Colors.orange;
    
    // ตรวจสอบการหันหน้า
    final headEulerAngleY = face.headEulerAngleY ?? 0;
    final headEulerAngleZ = face.headEulerAngleZ ?? 0;
    
    if (headEulerAngleY.abs() > 15) {
      message = "กรุณาหันหน้าตรงไปที่กล้อง";
      color = Colors.orange;
    } else if (headEulerAngleZ.abs() > 15) {
      message = "กรุณาไม่เอียงหัว";
      color = Colors.orange;
    } else {
      // ตรวจสอบดวงตา
      final leftEye = face.leftEyeOpenProbability;
      final rightEye = face.rightEyeOpenProbability;
      
      if (leftEye != null && leftEye < 0.5) {
        message = "กรุณาลืมตา";
        color = Colors.orange;
      } else if (rightEye != null && rightEye < 0.5) {
        message = "กรุณาลืมตา";
        color = Colors.orange;
      } else {
        // คำนวณคุณภาพใบหน้า
        qualityScore = _calculateFaceQuality(face);
        
        if (qualityScore > 0.8) {
          message = "ใบหน้าดี! กำลังเตรียมจับภาพ...";
          color = Colors.green;
          _faceVerified = true;
        } else if (qualityScore > 0.6) {
          message = "ใบหน้าดี กรุณาอยู่นิ่งๆ";
          color = Colors.blue;
        } else {
          message = "กรุณาปรับตำแหน่งใบหน้า";
          color = Colors.orange;
        }
      }
    }
    
    _confidence = qualityScore;
    _statusMessage = message;
    _statusColor = color;
  }

  double _calculateFaceQuality(Face face) {
    double score = 0.5; // Base score
    
    // Face size score (bigger is better, up to a point)
    final faceSize = face.boundingBox.width * face.boundingBox.height;
    final screenSize = MediaQuery.of(context).size.width * MediaQuery.of(context).size.height;
    final sizeRatio = faceSize / screenSize;
    
    if (sizeRatio > 0.15 && sizeRatio < 0.4) {
      score += 0.2;
    }
    
    // Head angle score
    final headY = face.headEulerAngleY?.abs() ?? 30;
    final headZ = face.headEulerAngleZ?.abs() ?? 30;
    
    if (headY < 10 && headZ < 10) {
      score += 0.2;
    }
    
    // Eye open score
    final leftEyeOpen = face.leftEyeOpenProbability ?? 0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 0;
    
    if (leftEyeOpen > 0.7 && rightEyeOpen > 0.7) {
      score += 0.1;
    }
    
    return score.clamp(0.0, 1.0);
  }

  bool _isGoodFace(Face face) {
    return _calculateFaceQuality(face) > 0.8;
  }

  Future<void> _startCountdown() async {
    if (_showCountdown) return;
    
    setState(() {
      _showCountdown = true;
      _countdown = 3;
    });
    
    for (int i = 3; i > 0; i--) {
      if (!mounted || !_faceDetected || !_isGoodFace(_currentFace!)) {
        setState(() {
          _showCountdown = false;
          _countdown = 0;
        });
        return;
      }
      
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    
    if (mounted && _faceDetected && _isGoodFace(_currentFace!)) {
      await _captureAndProcess();
    }
    
    setState(() {
      _showCountdown = false;
      _countdown = 0;
    });
  }

  Future<void> _captureAndProcess() async {
    if (_isCapturing) return;
    
    setState(() {
      _isCapturing = true;
      _statusMessage = "กำลังประมวลผลใบหน้า...";
      _statusColor = Colors.blue;
    });
    
    try {
      // หยุด image stream ชั่วคราว
      await _cameraController?.stopImageStream();
      
      // ถ่ายรูป
      final XFile imageFile = await _cameraController!.takePicture();
      
      // ประมวลผลใบหน้า
      final embedding = await _faceService.getFaceEmbedding(imageFile.path);
      
      if (widget.isRegistration) {
        // สำหรับการลงทะเบียน
        await _authService.saveFaceEmbedding(embedding);
        
        if (mounted) {
          setState(() {
            _statusMessage = "ลงทะเบียนใบหน้าสำเร็จ!";
            _statusColor = Colors.green;
          });
          
          widget.onFaceEmbeddingCaptured?.call(embedding);
          
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.of(context).pop(true);
        }
      } else {
        // สำหรับการเช็คชื่อ
        await _performAttendanceCheck(embedding);
      }
      
      // ลบไฟล์ชั่วคราว
      final file = File(imageFile.path);
      if (await file.exists()) {
        await file.delete();
      }
      
    } catch (e) {
      print('❌ Error capturing and processing: $e');
      if (mounted) {
        setState(() {
          _statusMessage = "เกิดข้อผิดพลาด: ${e.toString()}";
          _statusColor = Colors.red;
        });
        
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          setState(() {
            _statusMessage = "กรุณาลองอีกครั้ง";
            _statusColor = Colors.orange;
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
        // เริ่ม image stream ใหม่
        _startImageStream();
      }
    }
  }

  Future<void> _performAttendanceCheck(List<double> embedding) async {
    try {
      final userProfile = await _authService.getUserProfile();
      if (userProfile == null) {
        throw Exception('ไม่พบข้อมูลผู้ใช้');
      }
      
      final studentId = userProfile['school_id'];
      
      // ตรวจสอบใบหน้า
      final isVerified = await _authService.verifyFace(studentId, embedding);
      
      if (isVerified) {
        // เช็คชื่อสำเร็จ
        if (mounted) {
          setState(() {
            _statusMessage = "เช็คชื่อสำเร็จ!";
            _statusColor = Colors.green;
          });
          
          widget.onCheckInSuccess?.call("เช็คชื่อสำเร็จด้วย Face Recognition");
          
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('ไม่สามารถยืนยันใบหน้าได้ กรุณาลองใหม่');
      }
      
    } catch (e) {
      throw Exception('การเช็คชื่อล้มเหลว: $e');
    }
  }

  Future<void> _disposeResources() async {
    try {
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
      await _faceDetector.close();
      await _faceService.dispose();
    } catch (e) {
      print('❌ Error disposing resources: $e');
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('ปิด'),
          ),
        ],
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
          widget.isRegistration ? 'ลงทะเบียนใบหน้า' : 'เช็คชื่อด้วยใบหน้า',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: !_isInitialized
          ? const Center(
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
            )
          : Stack(
              children: [
                // Camera Preview
                if (_cameraController != null && _cameraController!.value.isInitialized)
                  Positioned.fill(
                    child: CameraPreview(_cameraController!),
                  ),
                
                // Face Detection Overlay
                if (_faceDetected && _currentFace != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FaceDetectionPainter(
                        face: _currentFace!,
                        imageSize: _cameraController!.value.previewSize!,
                        isGoodFace: _isGoodFace(_currentFace!),
                      ),
                    ),
                  ),
                
                // Top Instructions
                Positioned(
                  top: 40,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (widget.instructionText != null)
                          Text(
                            widget.instructionText!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Confidence Indicator
                if (_faceDetected)
                  Positioned(
                    top: 140,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'คุณภาพใบหน้า: ${(_confidence * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _confidence,
                            backgroundColor: Colors.grey.shade600,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _confidence > 0.8 ? Colors.green : 
                              _confidence > 0.6 ? Colors.blue : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Countdown
                if (_showCountdown)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _countdown.toString(),
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Processing Indicator
                if (_isCapturing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'กำลังประมวลผล...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class FaceDetectionPainter extends CustomPainter {
  final Face face;
  final Size imageSize;
  final bool isGoodFace;

  FaceDetectionPainter({
    required this.face,
    required this.imageSize,
    required this.isGoodFace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = isGoodFace ? Colors.green : Colors.orange;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    final scaledRect = Rect.fromLTRB(
      face.boundingBox.left * scaleX,
      face.boundingBox.top * scaleY,
      face.boundingBox.right * scaleX,
      face.boundingBox.bottom * scaleY,
    );

    // Draw face bounding box
    canvas.drawRect(scaledRect, paint);

    // Draw corner decorations
    final cornerLength = 30.0;
    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = isGoodFace ? Colors.green : Colors.orange;

    // Top-left corner
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.top),
      Offset(scaledRect.left + cornerLength, scaledRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.top),
      Offset(scaledRect.left, scaledRect.top + cornerLength),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.top),
      Offset(scaledRect.right - cornerLength, scaledRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.top),
      Offset(scaledRect.right, scaledRect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.bottom),
      Offset(scaledRect.left + cornerLength, scaledRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.bottom),
      Offset(scaledRect.left, scaledRect.bottom - cornerLength),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.bottom),
      Offset(scaledRect.right - cornerLength, scaledRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.bottom),
      Offset(scaledRect.right, scaledRect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}