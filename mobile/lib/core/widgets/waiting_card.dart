import 'dart:math' as math;

import 'package:flutter/material.dart';

class WaitingCard extends StatelessWidget {
  const WaitingCard({
    super.key,
    required this.estimatedSeconds,
    required this.message,
    this.progress,
  });

  final int estimatedSeconds;
  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final minutes = math.max(1, (estimatedSeconds / 60).ceil());
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE4DF), width: 1.2),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4EF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.auto_awesome_motion_rounded,
              size: 46,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            '预计 $minutes 分钟内完成',
            style: textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF68736F),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 22),
          if (progress == null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 0.9),
              duration: Duration(seconds: math.min(estimatedSeconds, 90)),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  minHeight: 14,
                  value: value,
                  borderRadius: BorderRadius.circular(8),
                );
              },
            )
          else
            LinearProgressIndicator(
              minHeight: 14,
              value: progress!.clamp(0, 1),
              borderRadius: BorderRadius.circular(8),
            ),
        ],
      ),
    );
  }
}
