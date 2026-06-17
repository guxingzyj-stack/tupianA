import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/video_api.dart';
import '../../../core/models/video_models.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/elderly_app_bar.dart';
import '../../../core/widgets/waiting_card.dart';

class VideoWaitingPage extends ConsumerStatefulWidget {
  const VideoWaitingPage({super.key, required this.jobId, required this.args});

  final String jobId;
  final VideoWaitingArgs args;

  @override
  ConsumerState<VideoWaitingPage> createState() => _VideoWaitingPageState();
}

class _VideoWaitingPageState extends ConsumerState<VideoWaitingPage> {
  Timer? _timer;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ElderlyAppBar(title: '安心等'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WaitingCard(
                estimatedSeconds: widget.args.estimatedSeconds,
                message: '正在做动态',
                progress: _progress / 100,
              ),
              const SizedBox(height: 16),
              _WaitingNotice(
                icon: Icons.notifications_active_outlined,
                text: '做好后会自动打开，不用一直盯着屏幕。',
                color: Theme.of(context).colorScheme.primary,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _WaitingNotice(
                  icon: Icons.error_outline_rounded,
                  text: _error!,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 14),
                BigButton(
                  text: '再试一次',
                  icon: Icons.refresh_rounded,
                  height: 76,
                  isPrimary: false,
                  onPressed: _poll,
                ),
              ],
              const Spacer(),
              BigButton(
                text: '先回首页',
                subtitle: '制作会继续进行',
                icon: Icons.home_rounded,
                height: 88,
                isPrimary: false,
                onPressed: () => context.go('/'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _poll() async {
    try {
      final status = await ref
          .read(videoApiProvider)
          .getJobStatus(widget.jobId);
      if (!mounted) {
        return;
      }
      if (status.isDone && status.resultUrl != null) {
        _timer?.cancel();
        context.go(
          '/video/result/${status.jobId}',
          extra: VideoResultArgs(
            videoUrl: status.resultUrl!,
            title: widget.args.resultTitle,
          ),
        );
        return;
      }
      if (status.isFailed) {
        _timer?.cancel();
        setState(() {
          _progress = status.progress;
          _error = status.error ?? '制作失败了,稍后再试';
        });
        return;
      }
      setState(() {
        _progress = status.progress;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = humanApiError(error));
      }
    }
  }
}

class _WaitingNotice extends StatelessWidget {
  const _WaitingNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE4DF)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
