// lib/presentation/common_widgets/image_picker_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
// Remove image_picker import since it's not in pubspec.yaml

class ImagePickerScreen extends StatefulWidget {
  final String instructionText;
  final Function(String imagePath)? onImageSelected;

  const ImagePickerScreen({
    super.key,
    required this.instructionText,
    this.onImageSelected,
  });

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showErrorSnackBar('No cameras available on this device');
        return;
      }

      // Platform-specific camera selection
      CameraDescription selectedCamera;
      
      if (kIsWeb) {
        // Web: ใช้กล้องแรกที่เจอ
        selectedCamera = _cameras.first;
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // Desktop: ใช้กล้องแรกที่เจอ (webcam)
        selectedCamera = _cameras.first;
      } else {
        // Mobile: หา front camera
        selectedCamera = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );
      }

      // Platform-specific resolution
      ResolutionPreset resolution;
      if (kIsWeb) {
        resolution = ResolutionPreset.medium; // Web รองรับดี
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        resolution = ResolutionPreset.high; // Desktop webcam รองรับ high
      } else {
        resolution = ResolutionPreset.high; // Mobile
      }

      _cameraController = CameraController(
        selectedCamera,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }

      print('✅ Camera initialized for ${_getPlatformName()}');
      print('📷 Using camera: ${selectedCamera.name} (${selectedCamera.lensDirection})');
      
    } catch (e) {
      print('❌ Error initializing camera: $e');
      _showErrorSnackBar('Failed to initialize camera: $e');
    }
  }

  String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  Future<void> _captureImage() async {
    if (!_isCameraInitialized || _cameraController == null) {
      _showErrorSnackBar('Camera not ready');
      return;
    }

    setState(() => _isCapturing = true);

    try {
      // Take picture
      final XFile imageFile = await _cameraController!.takePicture();
      print('📸 Image captured: ${imageFile.path}');
      
      // Save to permanent location
      final String savedPath = await _saveImageFile(imageFile);
      
      // Delete temporary file
      try {
        await File(imageFile.path).delete();
        print('🗑️ Temporary file deleted');
      } catch (e) {
        print('⚠️ Warning: Could not delete temporary file: $e');
      }

      if (mounted) {
        Navigator.of(context).pop(savedPath);
        widget.onImageSelected?.call(savedPath);
      }
      
    } catch (e) {
      print('❌ Error capturing image: $e');
      _showErrorSnackBar('Failed to capture image: $e');
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<String> _saveImageFile(XFile imageFile) async {
    if (kIsWeb) {
      return await _saveImageWeb(imageFile);
    } else {
      return await _saveImageDesktopMobile(imageFile);
    }
  }

  Future<String> _saveImageWeb(XFile imageFile) async {
    try {
      // Web: อ่านเป็น bytes
      final bytes = await imageFile.readAsBytes();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'face_image_$timestamp.jpg';
      
      // Web จะเก็บใน memory หรือ browser storage
      final String webPath = '/face_images/$fileName';
      
      print('📷 Web image saved: $fileName (${bytes.length} bytes)');
      return webPath;
      
    } catch (e) {
      throw Exception('Failed to save image on web: $e');
    }
  }

  Future<String> _saveImageDesktopMobile(XFile imageFile) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'face_image_$timestamp.jpg';
      final String savedPath = path.join(appDir.path, 'face_images', fileName);
      
      // Ensure directory exists
      final Directory imageDir = Directory(path.dirname(savedPath));
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
        print('📁 Created directory: ${imageDir.path}');
      }
      
      // Copy to permanent location
      await File(imageFile.path).copy(savedPath);
      print('💾 Image saved to: $savedPath');
      
      return savedPath;
      
    } catch (e) {
      throw Exception('Failed to save image on desktop/mobile: $e');
    }
  }

  // Remove gallery picker since image_picker is not available
  Future<void> _pickFromGallery() async {
    _showErrorSnackBar('Gallery picker not available in this build');
  }

  Future<void> _switchCamera() async {
    if (!_isCameraInitialized || _cameras.length < 2) {
      _showErrorSnackBar('Camera switching not available');
      return;
    }

    try {
      setState(() => _isCameraInitialized = false);

      final currentCamera = _cameraController!.description;
      final newCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection != currentCamera.lensDirection,
        orElse: () => _cameras.firstWhere(
          (camera) => camera != currentCamera,
        ),
      );

      await _cameraController!.dispose();

      _cameraController = CameraController(
        newCamera,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }

      print('🔄 Camera switched to: ${newCamera.name}');

    } catch (e) {
      print('❌ Error switching camera: $e');
      _showErrorSnackBar('Failed to switch camera: $e');
      // Try to reinitialize original camera
      _initializeCamera();
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
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
        title: Text('Select Face Image - ${_getPlatformName()}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Show available cameras count
          if (_cameras.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  '${_cameras.length} cam${_cameras.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          
          // Switch camera button
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _isCameraInitialized ? _switchCamera : null,
              tooltip: 'Switch Camera',
            ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.black.withOpacity(0.8),
            child: Column(
              children: [
                Text(
                  widget.instructionText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Platform: ${_getPlatformName()}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          // Camera preview
          Expanded(
            child: _isCameraInitialized && _cameraController != null
                ? Stack(
                    children: [
                      // Camera preview
                      Positioned.fill(
                        child: AspectRatio(
                          aspectRatio: _cameraController!.value.aspectRatio,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                      
                      // Face guide overlay
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FaceGuideOverlayPainter(),
                        ),
                      ),

                      // Camera info overlay
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _cameraController?.description.name ?? 'Camera',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 16),
                          const Text(
                            'Initializing camera...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Platform: ${_getPlatformName()}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          
          // Control buttons
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            child: Row(
              children: [
                // Take photo button
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_isCapturing || !_isCameraInitialized) ? null : _captureImage,
                    icon: _isCapturing 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black54,
                            ),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_isCapturing ? 'Capturing...' : 'Take Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[600],
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Gallery button (disabled)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: null, // Disabled since image_picker not available
                    icon: const Icon(Icons.photo_library, color: Colors.grey),
                    label: const Text(
                      'Gallery',
                      style: TextStyle(color: Colors.grey),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Platform info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.black,
            child: Text(
              'Running on ${_getPlatformName()} • ${_cameras.length} camera(s) available',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class FaceGuideOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.white.withOpacity(0.8);

    // Draw face guide oval
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

    // Corner lines
    final corners = [
      [Offset(left, top), Offset(left + cornerLength, top)],
      [Offset(left, top), Offset(left, top + cornerLength)],
      [Offset(right, top), Offset(right - cornerLength, top)],
      [Offset(right, top), Offset(right, top + cornerLength)],
      [Offset(left, bottom), Offset(left + cornerLength, bottom)],
      [Offset(left, bottom), Offset(left, bottom - cornerLength)],
      [Offset(right, bottom), Offset(right - cornerLength, bottom)],
      [Offset(right, bottom), Offset(right, bottom - cornerLength)],
    ];

    for (final corner in corners) {
      canvas.drawLine(corner[0], corner[1], cornerPaint);
    }

    // Add instruction text
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Align your face within the oval',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    
    final textOffset = Offset(
      (size.width - textPainter.width) / 2,
      center.dy + radiusY + 20,
    );
    
    // Draw background for text
    final textBgPaint = Paint()
      ..color = Colors.black.withOpacity(0.6);
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          textOffset.dx - 8,
          textOffset.dy - 4,
          textPainter.width + 16,
          textPainter.height + 8,
        ),
        const Radius.circular(4),
      ),
      textBgPaint,
    );
    
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}