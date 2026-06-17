import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/video_models.dart';
import '../../../core/share/family_share_service.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/elderly_app_bar.dart';
import '../../history/storage/history_db.dart';

class VideoResultPage extends ConsumerStatefulWidget {
  const VideoResultPage({super.key, required this.jobId, required this.args});

  final String jobId;
  final VideoResultArgs args;

  @override
  ConsumerState<VideoResultPage> createState() => _VideoResultPageState();
}

class _VideoResultPageState extends ConsumerState<VideoResultPage> {
  VideoPlayerController? _controller;
  Future<void>? _initialize;
  bool _busy = false;
  String? _localVideoPath;

  @override
  void initState() {
    super.initState();
    final controller = _isNetworkRef(widget.args.videoUrl)
        ? VideoPlayerController.networkUrl(Uri.parse(widget.args.videoUrl))
        : VideoPlayerController.file(File(widget.args.videoUrl));
    _controller = controller;
    _initialize = controller.initialize().then((_) {
      controller
        ..setLooping(true)
        ..play();
      if (mounted) {
        setState(() {});
      }
    });
    Future<void>.microtask(_recordVideoResult);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: const ElderlyAppBar(title: '做好了'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('祝福视频已生成', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '请先看一遍，确认自然后再发给家人。',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF68736F)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDDE4DF)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 300),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<void>(
                  future: _initialize,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done ||
                        controller == null ||
                        !controller.value.isInitialized) {
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 5),
                      );
                    }
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.62),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'AI 生成',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: IconButton(
                            tooltip: controller.value.isPlaying ? '暂停' : '播放',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.92,
                              ),
                              foregroundColor: const Color(0xFF18211F),
                              fixedSize: const Size(50, 50),
                            ),
                            onPressed: () {
                              if (controller.value.isPlaying) {
                                controller.pause();
                              } else {
                                controller.play();
                              }
                              setState(() {});
                            },
                            icon: Icon(
                              controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAF8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFDDE4DF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('下一步', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: BigButton(
                          text: '发家人',
                          icon: Icons.ios_share_rounded,
                          height: 74,
                          onPressed: _busy ? null : _shareVideo,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BigButton(
                          text: '保存',
                          icon: Icons.download_rounded,
                          height: 74,
                          isPrimary: false,
                          onPressed: _busy ? null : _saveVideo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '这是智能生成视频，可能和真实不同。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareVideo() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '确认发给家人?',
      message: '这是智能生成的视频,可能和真实不同。',
      confirmText: '发家人',
      cancelText: '先不发',
      confirmDelaySeconds: 2,
    );
    if (!confirmed) {
      return;
    }
    await _runAction(() async {
      final file = await _downloadVideo();
      await ref.read(familyShareServiceProvider).shareVideo(file);
    });
  }

  Future<void> _saveVideo() async {
    await _runAction(() async {
      final file = await _downloadVideo();
      final name = '老照动态_${DateTime.now().millisecondsSinceEpoch}';
      await ImageGallerySaverPlus.saveFile(file.path, name: name);
      _showSnack('已保存');
    });
  }

  Future<File> _downloadVideo() async {
    final localPath = _localVideoPath;
    if (localPath != null) {
      final localFile = File(localPath);
      if (await localFile.exists()) {
        return localFile;
      }
    }
    if (!_isNetworkRef(widget.args.videoUrl)) {
      final localFile = File(widget.args.videoUrl);
      if (await localFile.exists()) {
        return localFile;
      }
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/lao_zhao_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    await ref.read(dioProvider).download(widget.args.videoUrl, file.path);
    return file;
  }

  Future<void> _recordVideoResult() async {
    if (widget.jobId.isEmpty || widget.args.videoUrl.isEmpty) {
      return;
    }
    try {
      final file = _isNetworkRef(widget.args.videoUrl)
          ? await ref
                .read(historyRepositoryProvider)
                .cacheResultVideo(
                  dio: ref.read(dioProvider),
                  videoUrl: widget.args.videoUrl,
                  jobId: widget.jobId,
                  name: 'video',
                )
          : File(widget.args.videoUrl);
      if (!await file.exists()) {
        return;
      }
      await ref
          .read(historyRepositoryProvider)
          .upsertVideoResult(
            jobId: widget.jobId,
            videoPath: file.path,
            intentName: widget.args.title,
          );
      _localVideoPath = file.path;
      ref.invalidate(historyEntriesProvider);
    } catch (_) {
      // The video can still play from its current URL; history recording can fail
      // silently without interrupting an elderly user.
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        _showSnack('网络不太好,稍后再试');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isNetworkRef(String ref) {
    return ref.startsWith('http://') || ref.startsWith('https://');
  }
}
