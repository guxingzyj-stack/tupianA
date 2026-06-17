import 'package:flutter/material.dart';

class LongPressCompareView extends StatefulWidget {
  const LongPressCompareView({
    super.key,
    required this.originalImage,
    required this.resultImage,
    this.borderRadius = 8,
  });

  final ImageProvider originalImage;
  final ImageProvider resultImage;
  final double borderRadius;

  @override
  State<LongPressCompareView> createState() => _LongPressCompareViewState();
}

class _LongPressCompareViewState extends State<LongPressCompareView> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final image = _showOriginal ? widget.originalImage : widget.resultImage;
    return GestureDetector(
      onLongPressStart: (_) => setState(() => _showOriginal = true),
      onLongPressEnd: (_) => setState(() => _showOriginal = false),
      onLongPressCancel: () => setState(() => _showOriginal = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                child: Image(
                  key: ValueKey(_showOriginal),
                  image: image,
                  fit: BoxFit.cover,
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _showOriginal ? '原图' : '按住看原图',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
