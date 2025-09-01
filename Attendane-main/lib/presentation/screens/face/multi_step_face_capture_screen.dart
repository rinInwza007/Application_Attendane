// lib/presentation/screens/face/multi_step_face_capture_screen.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:myproject2/data/services/unified_face_service.dart';

class MultiStepFaceCaptureScreen extends StatefulWidget {
  final String? studentId;
  final String? studentEmail;
  final Function(List<String> imagePaths)? onAllImagesCapture;
  final bool isUpdate;

  const MultiStepFaceCaptureScreen({
    super.key,
    this.studentId,
    this.studentEmail,
    this.onAllImagesCapture,
    this.isUpdate = false,
  });

  @override
  State<MultiStepFaceCaptureScreen> createState() => _MultiStepFaceCaptureScreenState();
}

// Face capture steps data
class FaceCaptureStep {
  final String title;
  final String instruction;
  final String detailInstruction;
  final IconData icon;
  final Color color;
  final String pose;
  final bool Function(Face face) validator;

  FaceCaptureStep({
    required this.title,
    required this.instruction,
    required this.detailInstruction,
    required this.icon,
    required this.color,
    required this.pose,
    required this.validator,
  });
}

class _MultiStepFaceCaptureScreenState extends State<MultiStepFaceCaptureScreen>
    with TickerProviderStateMixin {
  
  // Camera และ Face Detection
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;
  late final UnifiedFaceService _faceService;
  late final AuthService _authService;
  
  // Animation Controllers
  late AnimationController _instructionAnimController;
  late AnimationController _frameAnimController;
  late AnimationController _progressAnimController;
  late Animation<double> _instructionAnimation;
  late Animation<double> _frameAnimation;
  late Animation<double> _progressAnimation;
  
  // State Management
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _faceDetected = false;
  bool _isCapturing = false;
  bool _isPreparing = false;
  
  // Face Detection Data
  Face? _currentFace;
  double _confidence = 0.0;
  String _statusMessage = "";
  Color _statusColor = Colors.orange;
  
  // Multi-step capture
  int _currentStepIndex = 0;
  List<String> _capturedImages = [];
  List<FaceCaptureStep> _captureSteps = [];
  
  // Timing
  int _countdown = 0;
  bool _showCountdown = false;
  int _preparationTime = 3;
  bool _stepCompleted = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCaptureSteps();
    _initializeServices();
  }

  void _initializeAnimations() {
    _instructionAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _frameAnimController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _progressAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _instructionAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _instructionAnimController, curve: Curves.easeInOut),
    );
    
    _frameAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _frameAnimController, curve: Curves.easeInOut),
    );
    
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressAnimController, curve: Curves.easeInOut),
    );
    
    _frameAnimController.repeat(reverse: true);
    _instructionAnimController.forward();
  }

  void _initializeCaptureSteps() {
    _captureSteps = [
      FaceCaptureStep(
        title: "มองตรง",
        instruction: "กรุณามองตรงไปที่กล้อง",
        detailInstruction: "วางใบหน้าให้อยู่ตรงกลางกรอบ\nมองตรงไปที่กล้อง ไม่หันซ้ายหรือขวา",
        icon: Icons.face,
        color: Colors.blue,
        pose: "front",
        validator: (face) => _isFrontPose(face),
      ),
      FaceCaptureStep(
        title: "หันซ้าย",
        instruction: "กรุณาหันหน้าไปทางซ้ายเล็กน้อย",
        detailInstruction: "หันหน้าไปทางซ้ายประมาณ 15-20 องศา\nยังคงมองไปที่กล้อง",
        icon: Icons.arrow_back,
        color: Colors.green,
        pose: "left",
        validator: (face) => _isLeftPose(face),
      ),
      FaceCaptureStep(
        title: "หันขวา", 
        instruction: "กรุณาหันหน้าไปทางขวาเล็กน้อย",
        detailInstruction: "หันหน้าไปทางขวาประมาณ 15-20 องศา\nยังคงมองไปที่กล้อง",
        icon: Icons.arrow_forward,
        color: Colors.orange,
        pose: "right",
        validator: (face) => _isRightPose(face),
      ),
      FaceCaptureStep(
        title: "เงยหน้า",
        instruction: "กรุณาเงยหน้าขึ้นเล็กน้อย",
        detailInstruction: "เงยหน้าขึ้นประมาณ 10-15 องศา\nยังคงมองไปที่กล้อง",
        icon: Icons.keyboard_arrow_up,
        color: Colors.purple,
        pose: "up",
        validator: (face) => _isUpPose(face),
      ),
      FaceCaptureStep(
        title: "ก้มหน้า",
        instruction: "กรุณาก้มหน้าลงเล็กน้อย", 
        detailInstruction: "ก้มหน้าลงประมาณ 10-15 องศา\nยังคงมองไปที่กล้อง",
        icon: Icons.keyboard_arrow_down,
        color: Colors.teal,
        pose: "down",
        validator: (face) => _isDownPose(face),
      ),
      FaceCaptureStep(
        title: "ยิ้ม",
        instruction: "กรุณายิ้มให้กล้อง",
        detailInstruction: "ยิ้มธรรมชาติ มองตรงไปที่กล้อง\nนี่เป็นท่าสุดท้าย!",
        icon: Icons.sentiment_very_satisfied,
        color: Colors.pink,
        pose: "smile",
        validator: (face) => _isSmilePose(face),
      ),
    ];
  }

  // Pose validation functions
  bool _isFrontPose(Face face) {
    final headY = face.headEulerAngleY?.abs() ?? 30;
    final headZ = face.headEulerAngleZ?.abs() ?? 30;
    return headY < 8 && headZ < 8;
  }

  bool _isLeftPose(Face face) {
    final headY = face.headEulerAngleY ?? 0;
    return headY > 12 && headY < 25; // หันซ้าย (บวก)
  }

  bool _isRightPose(Face face) {
    final headY = face.headEulerAngleY ?? 0;
    return headY < -12 && headY > -25; // หันขวา (ลบ)
  }

  bool _isUpPose(Face face) {
    final headX = face.headEulerAngleX ?? 0;
    return headX < -5 && headX > -20; // เงยหน้า (ลบ)
  }

  bool _isDownPose(Face face) {
    final headX = face.headEulerAngleX ?? 0;
    return headX > 5 && headX < 20; // ก้มหน้า (บวก)
  }

  bool _isSmilePose(Face face) {
    final smilingProb = face.smilingProbability ?? 0;
    final headY = face.headEulerAngleY?.abs() ?? 30;
    return smilingProb > 0.7 && headY < 10; // ยิ้ม + มองตรง
  }

  Future<void> _initializeServices() async {
    try {
      print('🔄 Initializing multi-step face capture services...');
      
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
          enableTracking: true,
          minFaceSize: 0.2,
          enableContours: false,
        ),
      );
      
      _faceService = UnifiedFaceService();
      _authService = AuthService();
      
      await _faceService.initialize();
      await _initializeCamera();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _updateStatusForCurrentStep();
        });
        _instructionAnimController.forward();
      }
      
      print('✅ Multi-step face capture services initialized');
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
        setState(() {});
        _startImageStream();
      }
    } catch (e) {
      print('❌ Error initializing camera: $e');
      throw e;
    }
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    _cameraController!.startImageStream((CameraImage image) async {
      if (_isProcessing || _showCountdown || _stepCompleted) return;
      
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
          _statusMessage = "ไม่พบใบหน้า กรุณาวางหน้าในกรอบ";
          _statusColor = Colors.red;
          _confidence = 0.0;
        }
      });
      
      // Auto capture when conditions are met
      if (_faceDetected && _isCorrectPose(_currentFace!) && !_showCountdown && !_stepCompleted) {
        await _startCountdownCapture();
      }
      
    } catch (e) {
      print('❌ Error processing image: $e');
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
      print('❌ Error converting camera image: $e');
      return null;
    }
  }

  void _updateFaceStatus(Face face) {
    final currentStep = _captureSteps[_currentStepIndex];
    final isCorrectPose = currentStep.validator(face);
    final quality = _calculateFaceQuality(face);
    
    _confidence = quality;
    
    if (!isCorrectPose) {
      _statusMessage = currentStep.instruction;
      _statusColor = Colors.orange;
    } else if (quality < 0.7) {
      _statusMessage = "คุณภาพใบหน้ายังไม่ดีพอ กรุณาปรับแสง";
      _statusColor = Colors.yellow.shade700;
    } else if (quality < 0.85) {
      _statusMessage = "ท่าถูกต้อง กรุณาอยู่นิ่งๆ";
      _statusColor = Colors.blue;
    } else {
      _statusMessage = "ดีเยี่ยม! กำลังถ่ายภาพ...";
      _statusColor = Colors.green;
    }
  }

  void _updateStatusForCurrentStep() {
    final currentStep = _captureSteps[_currentStepIndex];
    _statusMessage = currentStep.instruction;
    _statusColor = currentStep.color;
  }

  double _calculateFaceQuality(Face face) {
    double score = 0.3; // Base score
    
    // Face size
    final faceSize = face.boundingBox.width * face.boundingBox.height;
    final screenSize = MediaQuery.of(context).size.width * MediaQuery.of(context).size.height;
    final sizeRatio = faceSize / screenSize;
    
    if (sizeRatio > 0.15 && sizeRatio < 0.45) {
      score += 0.25;
    }
    
    // Eye openness
    final leftEye = face.leftEyeOpenProbability ?? 0;
    final rightEye = face.rightEyeOpenProbability ?? 0;
    
    if (leftEye > 0.8 && rightEye > 0.8) {
      score += 0.2;
    }
    
    // Face landmarks quality
    if (face.landmarks.isNotEmpty) {
      score += 0.15;
    }
    
    // Lighting/clarity (approximated by confidence)
    score += 0.1; // Assume good lighting
    
    return score.clamp(0.0, 1.0);
  }

  bool _isCorrectPose(Face face) {
    final currentStep = _captureSteps[_currentStepIndex];
    return currentStep.validator(face) && _calculateFaceQuality(face) > 0.8;
  }

  Future<void> _startCountdownCapture() async {
    if (_showCountdown || _stepCompleted) return;
    
    setState(() {
      _showCountdown = true;
      _countdown = 3;
    });
    
    for (int i = 3; i > 0; i--) {
      if (!mounted || !_faceDetected || !_isCorrectPose(_currentFace!)) {
        setState(() {
          _showCountdown = false;
          _countdown = 0;
        });
        return;
      }
      
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    
    if (mounted && _faceDetected && _isCorrectPose(_currentFace!)) {
      await _captureCurrentStep();
    }
    
    setState(() {
      _showCountdown = false;
      _countdown = 0;
    });
  }

  Future<void> _captureCurrentStep() async {
    if (_isCapturing) return;
    
    setState(() {
      _isCapturing = true;
      _stepCompleted = true;
      _statusMessage = "กำลังบันทึกภาพ...";
      _statusColor = Colors.blue;
    });
    
    try {
      await _cameraController?.stopImageStream();
      
      final XFile imageFile = await _cameraController!.takePicture();
      _capturedImages.add(imageFile.path);
      
      print('✅ Captured step ${_currentStepIndex + 1}: ${imageFile.path}');
      
      // Animate progress
      await _progressAnimController.forward();
      
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (_currentStepIndex < _captureSteps.length - 1) {
        // Move to next step
        setState(() {
          _currentStepIndex++;
          _stepCompleted = false;
          _statusMessage = _captureSteps[_currentStepIndex].instruction;
          _statusColor = _captureSteps[_currentStepIndex].color;
        });
        
        _progressAnimController.reset();
        _instructionAnimController.reset();
        _instructionAnimController.forward();
        
        // Start preparation period
        await _startPreparationPeriod();
        
        _startImageStream();
      } else {
        // All steps completed
        await _completeAllCaptures();
      }
      
    } catch (e) {
      print('❌ Error capturing step: $e');
      setState(() {
        _statusMessage = "เกิดข้อผิดพลาด กรุณาลองใหม่";
        _statusColor = Colors.red;
        _stepCompleted = false;
      });
      _startImageStream();
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _startPreparationPeriod() async {
    setState(() {
      _isPreparing = true;
      _preparationTime = 3;
    });
    
    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      
      setState(() => _preparationTime = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    
    setState(() => _isPreparing = false);
  }

  Future<void> _completeAllCaptures() async {
    setState(() {
      _statusMessage = "บันทึกข้อมูลใบหน้าสำเร็จ!";
      _statusColor = Colors.green;
    });
    
    try {
      // Process images and save face embedding
      if (_capturedImages.isNotEmpty) {
        widget.onAllImagesCapture?.call(_capturedImages);
        
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      print('❌ Error completing captures: $e');
      _showErrorDialog('บันทึกข้อมูลล้มเหลว', e.toString());
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
              Navigator.of(context).pop(false);
            },
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _instructionAnimController.dispose();
    _frameAnimController.dispose();
    _progressAnimController.dispose();
    
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    
    // Clean up captured images if incomplete
    for (final imagePath in _capturedImages) {
      try {
        File(imagePath).delete();
      } catch (e) {
        print('Warning: Could not delete $imagePath');
      }
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Face Capture',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
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
                    'กำลังเตรียมกล้อง...',
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
                      painter: MultiStepFaceOverlayPainter(
                        face: _currentFace!,
                        imageSize: _cameraController!.value.previewSize!,
                        isCorrectPose: _isCorrectPose(_currentFace!),
                        confidence: _confidence,
                        currentStep: _captureSteps[_currentStepIndex],
                        frameAnimation: _frameAnimation,
                      ),
                    ),
                  ),
                
                // Progress Indicator
                Positioned(
                  top: 60,
                  left: 20,
                  right: 20,
                  child: AnimatedBuilder(
                    animation: _instructionAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, -30 * (1 - _instructionAnimation.value)),
                        child: Opacity(
                          opacity: _instructionAnimation.value,
                          child: _buildProgressIndicator(),
                        ),
                      );
                    },
                  ),
                ),
                
                // Current Step Instructions
                Positioned(
                  top: 120,
                  left: 20,
                  right: 20,
                  child: AnimatedBuilder(
                    animation: _instructionAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - _instructionAnimation.value)),
                        child: Opacity(
                          opacity: _instructionAnimation.value,
                          child: _buildInstructionCard(),
                        ),
                      );
                    },
                  ),
                ),
                
                // Status Message
                Positioned(
                  bottom: 180,
                  left: 20,
                  right: 20,
                  child: _buildStatusCard(),
                ),
                
                // Confidence Indicator
                if (_faceDetected)
                  Positioned(
                    bottom: 120,
                    left: 20,
                    right: 20,
                    child: _buildConfidenceIndicator(),
                  ),
                
                // Countdown Overlay
                if (_showCountdown)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                      child: Center(
                        child: _buildCountdownWidget(),
                      ),
                    ),
                  ),
                
                // Preparation Overlay
                if (_isPreparing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.7),
                      child: Center(
                        child: _buildPreparationWidget(),
                      ),
                    ),
                  ),
                
                // Processing Overlay
                if (_isCapturing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                      child: Center(
                        child: _buildProcessingWidget(),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            'ขั้นตอนที่ ${_currentStepIndex + 1} จาก ${_captureSteps.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(_captureSteps.length, (index) {
              final isCompleted = index < _currentStepIndex;
              final isCurrent = index == _currentStepIndex;
              final isNext = index > _currentStepIndex;
              
              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.symmetric(horizontal: index == 0 || index == _captureSteps.length - 1 ? 0 : 2),
                  decoration: BoxDecoration(
                    color: isCompleted 
                        ? Colors.green 
                        : isCurrent 
                            ? _captureSteps[_currentStepIndex].color
                            : Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: isCurrent ? AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, child) {
                      return LinearProgressIndicator(
                        value: _progressAnimation.value,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.8),
                        ),
                      );
                    },
                  ) : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard() {
    final currentStep = _captureSteps[_currentStepIndex];
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: currentStep.color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: currentStep.color.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  currentStep.icon,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentStep.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentStep.instruction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            currentStep.detailInstruction,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _statusColor.withOpacity(0.5)),
      ),
      child: Text(
        _statusMessage,
        style: TextStyle(
          color: _statusColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildConfidenceIndicator() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _statusColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'คุณภาพภาพ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(_confidence * 100).toInt()}%',
                style: TextStyle(
                  color: _statusColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _confidence,
            backgroundColor: Colors.grey.shade600,
            valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
            minHeight: 6,
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.green, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
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
                  'ถ่ายภาพ',
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
        const SizedBox(height: 24),
        Text(
          'อยู่นิ่งๆ กำลังถ่ายภาพ...',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPreparationWidget() {
    final currentStep = _captureSteps[_currentStepIndex];
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: currentStep.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: currentStep.color.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _preparationTime.toString(),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Icon(
                  currentStep.icon,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'เตรียมตัวสำหรับ: ${currentStep.title}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          currentStep.instruction,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProcessingWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            strokeWidth: 6,
            valueColor: AlwaysStoppedAnimation<Color>(
              _captureSteps[_currentStepIndex].color,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'กำลังบันทึกภาพ...',
          style: TextStyle(
            color: _captureSteps[_currentStepIndex].color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'ขั้นตอนที่ ${_currentStepIndex + 1} จาก ${_captureSteps.length}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

// Custom painter for multi-step face overlay
class MultiStepFaceOverlayPainter extends CustomPainter {
  final Face face;
  final Size imageSize;
  final bool isCorrectPose;
  final double confidence;
  final FaceCaptureStep currentStep;
  final Animation<double> frameAnimation;

  MultiStepFaceOverlayPainter({
    required this.face,
    required this.imageSize,
    required this.isCorrectPose,
    required this.confidence,
    required this.currentStep,
    required this.frameAnimation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    final scaledRect = Rect.fromLTRB(
      face.boundingBox.left * scaleX,
      face.boundingBox.top * scaleY,
      face.boundingBox.right * scaleX,
      face.boundingBox.bottom * scaleY,
    );

    // Draw animated face frame
    final frameColor = isCorrectPose ? Colors.green : currentStep.color;
    final frameScale = frameAnimation.value;
    
    final animatedRect = Rect.fromCenter(
      center: scaledRect.center,
      width: scaledRect.width * frameScale,
      height: scaledRect.height * frameScale,
    );

    // Main frame
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = frameColor;

    canvas.drawRRect(
      RRect.fromRectAndRadius(animatedRect, const Radius.circular(12)),
      framePaint,
    );

    // Confidence ring
    final confidencePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..color = frameColor.withOpacity(confidence);
    
    final confidenceRect = Rect.fromCenter(
      center: scaledRect.center,
      width: scaledRect.width + 20,
      height: scaledRect.height + 20,
    );
    
    canvas.drawArc(
      confidenceRect,
      -math.pi / 2,
      2 * math.pi * confidence,
      false,
      confidencePaint,
    );

    // Corner indicators
    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..color = frameColor;

    final cornerLength = 25.0;
    final corners = [
      // Top-left
      [Offset(animatedRect.left, animatedRect.top), Offset(animatedRect.left + cornerLength, animatedRect.top)],
      [Offset(animatedRect.left, animatedRect.top), Offset(animatedRect.left, animatedRect.top + cornerLength)],
      // Top-right  
      [Offset(animatedRect.right, animatedRect.top), Offset(animatedRect.right - cornerLength, animatedRect.top)],
      [Offset(animatedRect.right, animatedRect.top), Offset(animatedRect.right, animatedRect.top + cornerLength)],
      // Bottom-left
      [Offset(animatedRect.left, animatedRect.bottom), Offset(animatedRect.left + cornerLength, animatedRect.bottom)],
      [Offset(animatedRect.left, animatedRect.bottom), Offset(animatedRect.left, animatedRect.bottom - cornerLength)],
      // Bottom-right
      [Offset(animatedRect.right, animatedRect.bottom), Offset(animatedRect.right - cornerLength, animatedRect.bottom)],
      [Offset(animatedRect.right, animatedRect.bottom), Offset(animatedRect.right, animatedRect.bottom - cornerLength)],
    ];

    for (final corner in corners) {
      canvas.drawLine(corner[0], corner[1], cornerPaint);
    }

    // Step indicator icon
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(currentStep.icon.codePoint),
        style: TextStyle(
          fontSize: 24,
          color: frameColor,
          fontFamily: currentStep.icon.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(
        scaledRect.left + 10,
        scaledRect.top - 40,
      ),
    );

    // Quality percentage
    final qualityPainter = TextPainter(
      text: TextSpan(
        text: '${(confidence * 100).toInt()}%',
        style: TextStyle(
          fontSize: 16,
          color: frameColor,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.8),
              offset: Offset(1, 1),
              blurRadius: 3,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    qualityPainter.layout();
    qualityPainter.paint(
      canvas,
      Offset(
        scaledRect.right - qualityPainter.width - 10,
        scaledRect.top - 40,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}