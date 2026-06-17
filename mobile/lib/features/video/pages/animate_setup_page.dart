import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/device_config_api.dart';
import '../../../core/api/video_api.dart';
import '../../../core/device/device_id.dart';
import '../../../core/models/video_models.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/elderly_app_bar.dart';
import '../../shared/placeholder_screen.dart';

class AnimateSetupPage extends ConsumerStatefulWidget {
  const AnimateSetupPage({super.key, required this.args});

  final VideoSetupArgs args;

  @override
  ConsumerState<AnimateSetupPage> createState() => _AnimateSetupPageState();
}

class _AnimateSetupPageState extends ConsumerState<AnimateSetupPage> {
  int _selectedIndex = 0;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final disabledMessage = ref
        .watch(deviceConfigProvider)
        .maybeWhen(
          data: (config) {
            if (!config.enableVideo) {
              return '视频功能暂时关闭';
            }
            if (widget.args.isOldPhoto && !config.enableAnimateOld) {
              return '老照片暂时不做动态';
            }
            return null;
          },
          orElse: () => null,
        );
    if (disabledMessage != null) {
      return PlaceholderScreen(
        title: '让照片动',
        message: disabledMessage,
        icon: Icons.movie_creation_outlined,
      );
    }

    if (widget.args.imageUrl.isEmpty) {
      return const PlaceholderScreen(
        title: '让照片动',
        message: '这张照片暂时不能做动态',
        icon: Icons.movie_creation_outlined,
      );
    }

    return Scaffold(
      appBar: const ElderlyAppBar(title: '让照片动'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('选择动态效果', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '生成约 8 秒视频，适合发给家人群。涉及人物的照片会尽量保持自然。',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF68736F)),
            ),
            const SizedBox(height: 18),
            for (var index = 0; index < motionPresets.length; index++) ...[
              _MotionCard(
                preset: motionPresets[index],
                selected: index == _selectedIndex,
                onTap: () => setState(() => _selectedIndex = index),
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              _InlineNotice(message: _error!, danger: true),
            ],
            const SizedBox(height: 12),
            const _InlineNotice(
              message: '智能生成内容可能和真实不同，发出前请先看一遍。',
              danger: false,
            ),
            const SizedBox(height: 20),
            BigButton(
              text: _busy ? '正在开始' : '开始制作',
              subtitle: '做好后会自动打开结果',
              icon: Icons.play_arrow_rounded,
              height: 90,
              onPressed: _busy ? null : _startVideo,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startVideo() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = await ref.read(deviceConfigProvider.future);
      if (!config.enableVideo ||
          (widget.args.isOldPhoto && !config.enableAnimateOld)) {
        if (mounted) {
          setState(() => _error = '这个功能暂时关闭');
        }
        return;
      }
      final deviceId = await ref.read(deviceIdProvider.future);
      final preset = motionPresets[_selectedIndex];
      final created = await ref
          .read(videoApiProvider)
          .createVideo(
            deviceId: deviceId,
            imageUrl: widget.args.imageUrl,
            motion: preset.id,
            isOldPhoto: widget.args.isOldPhoto,
          );
      if (!mounted) {
        return;
      }
      context.go(
        '/video/waiting/${created.jobId}',
        extra: VideoWaitingArgs(
          estimatedSeconds: created.estimatedSeconds,
          resultTitle: preset.name,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = humanApiError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _MotionCard extends StatelessWidget {
  const _MotionCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final MotionPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(minHeight: 98),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colorScheme.primary : const Color(0xFFDDE4DF),
            width: selected ? 2.4 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.08 : 0.04),
              blurRadius: selected ? 16 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : const Color(0xFFF1F3F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.auto_awesome_motion_rounded,
                size: 32,
                color: selected ? colorScheme.primary : const Color(0xFF68736F),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF68736F),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, required this.danger});

  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Theme.of(context).colorScheme.error
        : const Color(0xFF725018);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFFF1F0) : const Color(0xFFFFFBF3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: danger ? const Color(0xFFF5C2BC) : const Color(0xFFF0DDC4),
        ),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
