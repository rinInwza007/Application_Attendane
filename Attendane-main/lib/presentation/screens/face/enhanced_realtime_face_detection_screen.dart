import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/unified_attendance_service.dart';
import 'package:myproject2/data/services/unified_face_service.dart';

class EnhancedRealtimeFaceDetectionScreen extends StatefulWidget {
  final String? sessionId;
  final bool isRegistration;
  final String? studentId;
  final String? studentEmail;
  final UnifiedAttendanceService? attendanceService;
  final String? instructionText;
  final Function(List<double> embedding)? onFaceEmbeddingCaptured;
  final Function(String message)? onCheckInSuccess;

  const EnhancedRealtimeFaceDetectionScreen({
    super.key,
    this.sessionId,
    this.isRegistration = false,
    this.studentId,
    this.studentEmail,
    this.attendanceService,
    this.instructionText,
    this.onFaceEmbeddingCaptured,
    this.onCheckInSuccess,
  });

  @override
  State<EnhancedRealtimeFaceDetectionScreen> createState() => _EnhancedRealtimeFaceDetectionScreenState();
}

class _EnhancedRealtimeFaceDetectionScreenState extends State<EnhancedRealtimeFaceDetectionScreen>
    with WidgetsBindingObserver {
  
  // Camera และ Face Detection
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;
  late final UnifiedFaceService _faceService;
  late final AuthService _authService;
  late final UnifiedAttendanceService _attendanceService;
  
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
      print('🔄 Initializing enhanced face detection services...');
      
      // Initialize services
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
          enableTracking: true,
          minFaceSize: 0.15,
          enableContours: true,
        ),
      );
      
      _faceService = UnifiedFaceService();
      _authService = AuthService();
      _attendanceService = widget.attendanceService ?? UnifiedAttendanceService();
      
      await _faceService.initialize();
      await _initializeCamera();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = widget.instructionText ?? "กรุณาวางใบหน้าของคุณในกรอบ";
        });
      }
      
      print('✅ Enhanced face detection services initialized successfully');
    } catch (e) {
      print('❌ Error initializing enhanced services: $e');
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
      
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {});
        _startImageStream();
      }
    } catch (e) {
      print('❌ Error initializing enhanced camera: $e');
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
      
      // Enhanced face quality check and auto capture
      if (_faceDetected && _isGoodFace(_currentFace!) && !_showCountdown && !_isCapturing) {
        _startCountdown();
      }
      
    } catch (e) {
      print('❌ Error processing enhanced image: $e');
    }
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      if (Platform.isAndroid) {
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }
      
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
      print('❌ Error converting enhanced camera image: $e');
      return null;
    }
  }

  void _updateFaceStatus(Face face) {
    double qualityScore = 0.0;
    String message = "";
    Color color = Colors.orange;
    
    // Enhanced face quality analysis
    final headEulerAngleY = face.headEulerAngleY ?? 0;
    final headEulerAngleZ = face.headEulerAngleZ ?? 0;
    
    if (headEulerAngleY.abs() > 15) {
      message = "กรุณาหันหน้าตรงไปที่กล้อง";
      color = Colors.orange;
    } else if (headEulerAngleZ.abs() > 15) {
      message = "กรุณาไม่เอียงหัว";
      color = Colors.orange;
    } else {
      final leftEye = face.leftEyeOpenProbability;
      final rightEye = face.rightEyeOpenProbability;
      
      if (leftEye != null && leftEye < 0.5) {
        message = "กรุณาลืมตา";
        color = Colors.orange;
      } else if (rightEye != null && rightEye < 0.5) {
        message = "กรุณาลืมตา";
        color = Colors.orange;
      } else {
        qualityScore = _calculateEnhancedFaceQuality(face);
        
        if (qualityScore > 0.9) {
          message = "คุณภาพใบหน้าดีเยี่ยม! กำลังเตรียมจับภาพ...";
          color = Colors.green;
          _faceVerified = true;
        } else if (qualityScore > 0.8) {
          message = "คุณภาพใบหน้าดี กำลังเตรียมจับภาพ...";
          color = Colors.lightGreen;
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

  double _calculateEnhancedFaceQuality(Face face) {
    double score = 0.3; // Base score
    
    // Enhanced face size analysis
    final faceSize = face.boundingBox.width * face.boundingBox.height;
    final screenSize = MediaQuery.of(context).size.width * MediaQuery.of(context).size.height;
    final sizeRatio = faceSize / screenSize;
    
    if (sizeRatio > 0.2 && sizeRatio < 0.5) {
      score += 0.3; // Better size range
    } else if (sizeRatio > 0.15 && sizeRatio < 0.6) {
      score += 0.2;
    }
    
    // Enhanced head angle analysis
    final headY = face.headEulerAngleY?.abs() ?? 30;
    final headZ = face.headEulerAngleZ?.abs() ?? 30;
    
    if (headY < 5 && headZ < 5) {
      score += 0.3; // Perfect alignment
    } else if (headY < 10 && headZ < 10) {
      score += 0.2; // Good alignment
    } else if (headY < 15 && headZ < 15) {
      score += 0.1; // Acceptable alignment
    }
    
    // Enhanced eye analysis
    final leftEyeOpen = face.leftEyeOpenProbability ?? 0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 0;
    
    if (leftEyeOpen > 0.8 && rightEyeOpen > 0.8) {
      score += 0.2; // Wide open eyes
    } else if (leftEyeOpen > 0.7 && rightEyeOpen > 0.7) {
      score += 0.1; // Open eyes
    }
    
    // Additional quality factors for enhanced detection
    final smileProbability = face.smilingProbability ?? 0;
    if (smileProbability > 0.3 && smileProbability < 0.8) {
      score += 0.1; // Natural expression bonus
    }
    
    return score.clamp(0.0, 1.0);
  }

  bool _isGoodFace(Face face) {
    return _calculateEnhancedFaceQuality(face) > 0.8;
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
      _statusMessage = "กำลังประมวลผลด้วย Enhanced AI...";
      _statusColor = Colors.blue;
    });
    
    try {
      await _cameraController?.stopImageStream();
      
      final XFile imageFile = await _cameraController!.takePicture();
      
      if (widget.isRegistration) {
        await _performEnhancedRegistration(imageFile.path);
      } else {
        await _performEnhancedCheckIn(imageFile.path);
      }
      
      final file = File(imageFile.path);
      if (await file.exists()) {
        await file.delete();
      }
      
    } catch (e) {
      print('❌ Error in enhanced capture and processing: $e');
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
        _startImageStream();
      }
    }
  }

  Future<void> _performEnhancedRegistration(String imagePath) async {
    try {
      // Use enhanced API for multiple image registration
      final result = await _attendanceService.enrollFaceMultiple(
        imagePaths: [imagePath],
        studentId: widget.studentId ?? '',
        studentEmail: widget.studentEmail ?? '',
      );

      if (result['success']) {
        if (mounted) {
          setState(() {
            _statusMessage = "Enhanced Face Registration สำเร็จ!";
            _statusColor = Colors.green;
          });
          
          widget.onFaceEmbeddingCaptured?.call([]);
          
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.of(context).pop(true);
        }
      } else {
        throw Exception(result['error'] ?? 'Enhanced registration failed');
      }
      
    } catch (e) {
      throw Exception('Enhanced registration failed: $e');
    }
  }

  Future<void> _performEnhancedCheckIn(String imagePath) async {
    try {
      final result = await _attendanceService.processPeriodicCapture(
        imagePath: imagePath,
        sessionId: widget.sessionId ?? '',
        captureTime: DateTime.now(),
        deleteImageAfter: true,
      );

      if (result['success']) {
        if (mounted) {
          setState(() {
            _statusMessage = "Enhanced Check-in สำเร็จ!";
            _statusColor = Colors.green;
          });
          
          widget.onCheckInSuccess?.call("Enhanced Face Recognition check-in successful");
          
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.of(context).pop(true);
        }
      } else {
        throw Exception(result['error'] ?? 'Enhanced check-in failed');
      }
      
    } catch (e) {
      throw Exception('Enhanced check-in failed: $e');
    }
  }

  Future<void> _disposeResources() async {
    try {
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
      await _faceDetector.close();
      await _faceService.dispose();
    } catch (e) {
      print('❌ Error disposing enhanced resources: $e');
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
          widget.isRegistration ? 'Enhanced Face Registration' : 'Enhanced Face Check-in',
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
                    'กำลังเตรียม Enhanced Face Detection...',
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
                
                // Enhanced Face Detection Overlay
                if (_faceDetected && _currentFace != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: EnhancedFaceDetectionPainter(
                        face: _currentFace!,
                        imageSize: _cameraController!.value.previewSize!,
                        isGoodFace: _isGoodFace(_currentFace!),
                        confidence: _confidence,
                      ),
                    ),
                  ),
                
                // Enhanced Status Display
                Positioned(
                  top: 40,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _statusColor.withOpacity(0.5)),
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
                
                // Enhanced Confidence Indicator
                if (_faceDetected)
                  Positioned(
                    top: 160,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _statusColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Enhanced Face Quality: ${(_confidence * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _confidence,
                            backgroundColor: Colors.grey.shade600,
                            valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Enhanced Countdown
                if (_showCountdown)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.7),
                      child: Center(
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.green, width: 4),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _countdown.toString(),
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const Text(
                                  'Enhanced',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Enhanced Processing Indicator
                if (_isCapturing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 4,
                            ),
                            SizedBox(height: 20),
                            Text(
                              'กำลังประมวลผลด้วย Enhanced AI...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'โปรดรอสักครู่',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
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

class EnhancedFaceDetectionPainter extends CustomPainter {
  final Face face;
  final Size imageSize;
  final bool isGoodFace;
  final double confidence;

  EnhancedFaceDetectionPainter({
    required this.face,
    required this.imageSize,
    required this.isGoodFace,
    required this.confidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Enhanced face detection visualization
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

    // Draw enhanced face bounding box with gradient effect
    final gradient = LinearGradient(
      colors: isGoodFace 
          ? [Colors.green, Colors.lightGreen]
          : [Colors.orange, Colors.deepOrange],
    );
    
    // Draw main face rectangle
    canvas.drawRect(scaledRect, paint);
    
    // Draw confidence indicator around the face
    final confidencePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = (isGoodFace ? Colors.green : Colors.orange).withOpacity(confidence);
    
    final expandedRect = Rect.fromLTRB(
      scaledRect.left - 10,
      scaledRect.top - 10,
      scaledRect.right + 10,
      scaledRect.bottom + 10,
    );
    
    canvas.drawRect(expandedRect, confidencePaint);

    // Enhanced corner decorations
    final cornerLength = 40.0;
    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..color = isGoodFace ? Colors.green : Colors.orange;

    // Draw enhanced corner indicators
    final corners = [
      // Top-left
      [Offset(scaledRect.left, scaledRect.top), Offset(scaledRect.left + cornerLength, scaledRect.top)],
      [Offset(scaledRect.left, scaledRect.top), Offset(scaledRect.left, scaledRect.top + cornerLength)],
      // Top-right
      [Offset(scaledRect.right, scaledRect.top), Offset(scaledRect.right - cornerLength, scaledRect.top)],
      [Offset(scaledRect.right, scaledRect.top), Offset(scaledRect.right, scaledRect.top + cornerLength)],
      // Bottom-left
      [Offset(scaledRect.left, scaledRect.bottom), Offset(scaledRect.left + cornerLength, scaledRect.bottom)],
      [Offset(scaledRect.left, scaledRect.bottom), Offset(scaledRect.left, scaledRect.bottom - cornerLength)],
      // Bottom-right
      [Offset(scaledRect.right, scaledRect.bottom), Offset(scaledRect.right - cornerLength, scaledRect.bottom)],
      [Offset(scaledRect.right, scaledRect.bottom), Offset(scaledRect.right, scaledRect.bottom - cornerLength)],
    ];

    for (final corner in corners) {
      canvas.drawLine(corner[0], corner[1], cornerPaint);
    }
    
    // Draw confidence percentage text
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${(confidence * 100).toInt()}%',
        style: TextStyle(
          color: isGoodFace ? Colors.green : Colors.orange,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        scaledRect.left + 10,
        scaledRect.top - 30,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}