// lib/presentation/screens/face/webrtc_face_detection_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:myproject2/data/services/webrtc_camera_service.dart';
import 'package:myproject2/data/services/face_recognition_service.dart';
import 'package:myproject2/data/services/auth_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class WebRTCFaceDetectionScreen extends StatefulWidget {
  final String? sessionId;
  final bool isRegistration;
  final String? instructionText;
  final Function(List<double> embedding)? onFaceEmbeddingCaptured;
  final Function(String message)? onCheckInSuccess;
  final String? signalingServerUrl;

  const WebRTCFaceDetectionScreen({
    super.key,
    this.sessionId,
    this.isRegistration = false,
    this.instructionText,
    this.onFaceEmbeddingCaptured,
    this.onCheckInSuccess,
    this.signalingServerUrl,
  });

  @override
  State<WebRTCFaceDetectionScreen> createState() => _WebRTCFaceDetectionScreenState();
}

class _WebRTCFaceDetectionScreenState extends State<WebRTCFaceDetectionScreen>
    with WidgetsBindingObserver {
  
  // Services
  late final WebRTCCameraService _cameraService;
  late final FaceDetector _faceDetector;
  late final FaceRecognitionService _faceRecognitionService;
  late final AuthService _authService;
  
  // State Management
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isConnected = false;
  bool _faceDetected = false;
  bool _faceVerified = false;
  bool _isCapturing = false;
  
  // Face Detection
  Face? _currentFace;
  double _confidence = 0.0;
  String _statusMessage = "กำลังเตรียมกล้อง...";
  Color _statusColor = Colors.orange;
  
  // UI State
  int _countdown = 0;
  bool _showCountdown = false;
  CameraPosition _currentCameraPosition = CameraPosition.front;
  
  // Timers
  Timer? _faceDetectionTimer;
  Timer? _countdownTimer;

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
    if (state == AppLifecycleState.paused) {
      _cameraService.stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_isInitialized) {
        _cameraService.startCamera(position: _currentCameraPosition);
      }
    }
  }

  // Initialize all services
  Future<void> _initializeServices() async {
    try {
      print('🔄 Initializing WebRTC Face Detection...');
      
      // Initialize services
      _cameraService = WebRTCCameraService();
      _authService = AuthService();
      _faceRecognitionService = FaceRecognitionService();
      
      // Setup face detector
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
          enableTracking: true,
          minFaceSize: 0.15,
          enableContours: true,
        ),
      );
      
      // Setup camera service callbacks
      _cameraService.onFrameCaptured = _processFrame;
      _cameraService.onError = _handleError;
      _cameraService.onConnectionChanged = _handleConnectionChanged;
      
      // Initialize services
      await _faceRecognitionService.initialize();
      
      // Initialize camera
      final cameraInitialized = await _cameraService.initialize();
      if (!cameraInitialized) {
        throw Exception('Failed to initialize camera');
      }
      
      // Connect to signaling server if provided
      if (widget.signalingServerUrl != null) {
        await _cameraService.connectToSignalingServer(widget.signalingServerUrl!);
      }
      
      // Start camera
      final cameraStarted = await _cameraService.startCamera(
        position: _currentCameraPosition,
      );
      
      if (!cameraStarted) {
        throw Exception('Failed to start camera');
      }
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = "วางใบหน้าของคุณในกรอบ";
          _statusColor = Colors.blue;
        });
      }
      
      print('✅ WebRTC Face Detection initialized successfully');
      
    } catch (e) {
      print('❌ Error initializing: $e');
      if (mounted) {
        _showErrorDialog('ไม่สามารถเปิดกล้องได้', e.toString());
      }
    }
  }

  // Process captured frame for face detection
  Future<void> _processFrame(Uint8List frameData) async {
    if (_isProcessing || !mounted) return;
    
    _isProcessing = true;
    
    try {
      // Convert frame data to InputImage
      // This is a simplified approach - in real implementation,
      // you'd convert the actual video frame data
      
      // For now, we'll use a placeholder approach
      // In actual implementation, convert frameData to InputImage
      
      setState(() {
        _faceDetected = false;
        _statusMessage = "กำลังตรวจจับใบหน้า...";
        _statusColor = Colors.blue;
      });
      
    } catch (e) {
      print('❌ Error processing frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // Handle camera connection changes
  void _handleConnectionChanged(bool connected) {
    if (mounted) {
      setState(() {
        _isConnected = connected;
        if (connected) {
          _statusMessage = "เชื่อมต่อสำเร็จ - วางใบหน้าในกรอบ";
          _statusColor = Colors.green;
        } else {
          _statusMessage = "กำลังเชื่อมต่อ...";
          _statusColor = Colors.orange;
        }
      });
    }
  }

  // Handle camera errors
  void _handleError(String error) {
    if (mounted) {
      setState(() {
        _statusMessage = "เกิดข้อผิดพลาด: $error";
        _statusColor = Colors.red;
      });
    }
  }

  // Switch camera (front/back)
  Future<void> _switchCamera() async {
    if (!_cameraService.isInitialized) return;
    
    setState(() {
      _statusMessage = "กำลังเปลี่ยนกล้อง...";
      _statusColor = Colors.blue;
    });
    
    final switched = await _cameraService.switchCamera();
    
    if (switched) {
      _currentCameraPosition = _currentCameraPosition == CameraPosition.front 
          ? CameraPosition.back 
          : CameraPosition.front;
      
      setState(() {
        _statusMessage = "เปลี่ยนกล้องสำเร็จ";
        _statusColor = Colors.green;
      });
      
      // Reset status after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _statusMessage = "วางใบหน้าของคุณในกรอบ";
            _statusColor = Colors.blue;
          });
        }
      });
    } else {
      setState(() {
        _statusMessage = "ไม่สามารถเปลี่ยนกล้องได้";
        _statusColor = Colors.red;
      });
    }
  }

  // Start countdown before capture
  Future<void> _startCountdown() async {
    if (_showCountdown || !mounted) return;
    
    setState(() {
      _showCountdown = true;
      _countdown = 3;
    });
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _countdown--;
      });
      
      if (_countdown <= 0) {
        timer.cancel();
        _captureAndProcess();
      }
    });
  }

  // Capture and process image
  Future<void> _captureAndProcess() async {
    if (_isCapturing || !mounted) return;
    
    setState(() {
      _isCapturing = true;
      _showCountdown = false;
      _statusMessage = "กำลังประมวลผลใบหน้า...";
      _statusColor = Colors.blue;
    });
    
    try {
      // Capture high-quality image
      final imageData = await _cameraService.captureHighQualityImage();
      
      if (imageData == null) {
        throw Exception('ไม่สามารถจับภาพได้');
      }
      
      // Save temporary image file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(
        tempDir.path,
        'face_capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ));
      
      await tempFile.writeAsBytes(imageData);
      
      // Process face recognition
      final embedding = await _faceRecognitionService.getFaceEmbedding(tempFile.path);
      
      if (widget.isRegistration) {
        // Registration mode
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
        // Verification mode
        await _performAttendanceCheck(embedding);
      }
      
      // Clean up temporary file
      await tempFile.delete();
      
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
      }
    }
  }

  // Perform attendance check
  Future<void> _performAttendanceCheck(List<double> embedding) async {
    try {
      final userProfile = await _authService.getUserProfile();
      if (userProfile == null) {
        throw Exception('ไม่พบข้อมูลผู้ใช้');
      }
      
      final studentId = userProfile['school_id'];
      
      // Verify face
      final isVerified = await _authService.verifyFace(studentId, embedding);
      
      if (isVerified) {
        // Success
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

  // Show error dialog
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

  // Dispose resources
  Future<void> _disposeResources() async {
    try {
      _faceDetectionTimer?.cancel();
      _countdownTimer?.cancel();
      
      await _cameraService.dispose();
      await _faceDetector.close();
      await _faceRecognitionService.dispose();
    } catch (e) {
      print('❌ Error disposing resources: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.isRegistration ? 'ลงทะเบียนใบหน้า (WebRTC)' : 'เช็คชื่อด้วยใบหน้า (WebRTC)',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isInitialized)
            IconButton(
              icon: Icon(
                _currentCameraPosition == CameraPosition.front 
                    ? Icons.camera_front 
                    : Icons.camera_rear,
                color: Colors.white,
              ),
              onPressed: _switchCamera,
              tooltip: 'Switch Camera',
            ),
        ],
      ),
      body: !_isInitialized
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'กำลังเปิดกล้อง WebRTC...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // WebRTC Video View
                if (_cameraService.localRenderer != null)
                  Positioned.fill(
                    child: RTCVideoView(
                      _cameraService.localRenderer!,
                      mirror: _currentCameraPosition == CameraPosition.front,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                
                // Face Detection Overlay
                if (_faceDetected && _currentFace != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: WebRTCFaceDetectionPainter(
                        face: _currentFace!,
                        isGoodFace: _faceVerified,
                      ),
                    ),
                  ),
                
                // Connection Status Indicator
                Positioned(
                  top: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isConnected ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isConnected ? Icons.wifi : Icons.wifi_off,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isConnected ? 'WebRTC' : 'Disconnected',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Instructions
                Positioned(
                  top: 60,
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
                    top: 180,
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
                              'กำลังประมวลผล WebRTC...',
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
                
                // Manual Capture Button
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton.icon(
                      onPressed: _isCapturing ? null : _startCountdown,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('จับภาพ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// Custom painter for face detection overlay
class WebRTCFaceDetectionPainter extends CustomPainter {
  final Face face;
  final bool isGoodFace;

  WebRTCFaceDetectionPainter({
    required this.face,
    required this.isGoodFace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = isGoodFace ? Colors.green : Colors.orange;

    // Draw face bounding box
    final rect = face.boundingBox;
    canvas.drawRect(rect, paint);

    // Draw corner decorations
    final cornerLength = 30.0;
    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = isGoodFace ? Colors.green : Colors.orange;

    // Top-left corner
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left + cornerLength, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left, rect.top + cornerLength),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right - cornerLength, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left + cornerLength, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left, rect.bottom - cornerLength),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right - cornerLength, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right, rect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}