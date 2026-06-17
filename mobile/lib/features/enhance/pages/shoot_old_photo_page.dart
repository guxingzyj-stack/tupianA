import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/enhance_models.dart';
import '../../../core/widgets/elderly_app_bar.dart';

class ShootOldPhotoPage extends StatefulWidget {
  const ShootOldPhotoPage({super.key});

  @override
  State<ShootOldPhotoPage> createState() => _ShootOldPhotoPageState();
}

class _ShootOldPhotoPageState extends State<ShootOldPhotoPage> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  bool _takingPhoto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('no camera');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '相机暂时打不开');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ElderlyAppBar(title: '拍老照片'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
              child: Text(
                '把照片放进框里再拍',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FutureBuilder<void>(
                    future: _initializeFuture,
                    builder: (context, snapshot) {
                      if (_error != null) {
                        return _CameraMessage(message: _error!);
                      }
                      if (snapshot.connectionState != ConnectionState.done ||
                          _controller == null ||
                          !_controller!.value.isInitialized) {
                        return const _CameraMessage(message: '正在打开相机');
                      }
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_controller!),
                          const _GuideFrame(),
                          const _CameraHint(),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
              child: Center(
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: FilledButton(
                    onPressed: _takingPhoto ? null : _takePhoto,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: _takingPhoto
                        ? const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 4,
                            ),
                          )
                        : const Icon(Icons.camera_alt_rounded, size: 40),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() => _takingPhoto = true);
    try {
      final file = await controller.takePicture();
      final tempDir = await getTemporaryDirectory();
      final target = File(
        '${tempDir.path}${Platform.pathSeparator}'
        'old_photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(file.path).copy(target.path);
      if (!mounted) {
        return;
      }
      context.go(
        '/enhance/analyzing',
        extra: AnalyzePageArgs(imagePath: target.path, isShotPaper: true),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('这张没拍好,再试一次', style: TextStyle(fontSize: 18)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _takingPhoto = false);
      }
    }
  }
}

class _GuideFrame extends StatelessWidget {
  const _GuideFrame();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFFFFFFF);
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.82,
        heightFactor: 0.62,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: color.withValues(alpha: 0.72),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const Positioned(
              left: 0,
              top: 0,
              child: _CornerGuide(alignment: _CornerAlignment.topLeft),
            ),
            const Positioned(
              right: 0,
              top: 0,
              child: _CornerGuide(alignment: _CornerAlignment.topRight),
            ),
            const Positioned(
              left: 0,
              bottom: 0,
              child: _CornerGuide(alignment: _CornerAlignment.bottomLeft),
            ),
            const Positioned(
              right: 0,
              bottom: 0,
              child: _CornerGuide(alignment: _CornerAlignment.bottomRight),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CornerAlignment { topLeft, topRight, bottomLeft, bottomRight }

class _CornerGuide extends StatelessWidget {
  const _CornerGuide({required this.alignment});

  final _CornerAlignment alignment;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    const width = 6.0;
    const color = Color(0xFFFFFFFF);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerGuidePainter(
          alignment: alignment,
          color: color,
          strokeWidth: width,
        ),
      ),
    );
  }
}

class _CornerGuidePainter extends CustomPainter {
  const _CornerGuidePainter({
    required this.alignment,
    required this.color,
    required this.strokeWidth,
  });

  final _CornerAlignment alignment;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    switch (alignment) {
      case _CornerAlignment.topLeft:
        path
          ..moveTo(0, size.height)
          ..lineTo(0, 0)
          ..lineTo(size.width, 0);
        break;
      case _CornerAlignment.topRight:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height);
        break;
      case _CornerAlignment.bottomLeft:
        path
          ..moveTo(0, size.height)
          ..lineTo(size.width, size.height)
          ..moveTo(0, size.height)
          ..lineTo(0, 0);
        break;
      case _CornerAlignment.bottomRight:
        path
          ..moveTo(0, size.height)
          ..lineTo(size.width, size.height)
          ..lineTo(size.width, 0);
        break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerGuidePainter oldDelegate) {
    return oldDelegate.alignment != alignment ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _CameraHint extends StatelessWidget {
  const _CameraHint();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              '拍完会自动裁正',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE9ECEF),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
