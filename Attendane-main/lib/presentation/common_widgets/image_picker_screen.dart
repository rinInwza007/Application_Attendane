// lib/presentation/common_widgets/image_picker_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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
      if (_cameras.isEmpty) return;

      // Use front camera if available
      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      _showErrorSnackBar('Failed to initialize camera: $e');
    }
  }

  Future<void> _captureImage() async {
    if (!_isCameraInitialized || _cameraController == null) return;

    setState(() => _isCapturing = true);

    try {
      // Take picture
      final XFile imageFile = await _cameraController!.takePicture();
      
      // Save to permanent location
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'face_image_$timestamp.jpg';
      final String savedPath = path.join(appDir.path, 'face_images', fileName);
      
      // Ensure directory exists
      final Directory imageDir = Directory(path.dirname(savedPath));
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }
      
      // Copy to permanent location
      await File(imageFile.path).copy(savedPath);
      
      // Delete temporary file
      await File(imageFile.path).delete();

      if (mounted) {
        Navigator.of(context).pop(savedPath);
        widget.onImageSelected?.call(savedPath);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to capture image: $e');
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (imageFile != null && mounted) {
        Navigator.of(context).pop(imageFile.path);
        widget.onImageSelected?.call(imageFile.path);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: $e');
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Select Face Image'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.black.withOpacity(0.8),
            child: Text(
              widget.instructionText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Camera preview
          Expanded(
            child: _isCameraInitialized && _cameraController != null
                ? Stack(
                    children: [
                      CameraPreview(_cameraController!),
                      
                      // Face guide overlay
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FaceGuideOverlayPainter(),
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
                            'Initializing camera...',
                            style: TextStyle(color: Colors.white),
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
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isCapturing ? null : _captureImage,
                    icon: _isCapturing 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_isCapturing ? 'Capturing...' : 'Take Photo'),
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
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                    label: const Text(
                      'From Gallery',
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}