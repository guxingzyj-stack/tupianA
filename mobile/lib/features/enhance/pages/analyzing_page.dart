import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/enhance_api.dart';
import '../../../core/device/device_id.dart';
import '../../../core/models/enhance_models.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/elderly_app_bar.dart';

enum _AnalyzeStage { preparing, uploading, thinking, failed }

class AnalyzingPage extends ConsumerStatefulWidget {
  const AnalyzingPage({super.key, required this.args});

  final AnalyzePageArgs args;

  @override
  ConsumerState<AnalyzingPage> createState() => _AnalyzingPageState();
}

class _AnalyzingPageState extends ConsumerState<AnalyzingPage> {
  _AnalyzeStage _stage = _AnalyzeStage.preparing;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_startAnalyze);
  }

  Future<void> _startAnalyze() async {
    final imagePath = widget.args.imagePath;
    if (imagePath.isEmpty || !File(imagePath).existsSync()) {
      setState(() {
        _stage = _AnalyzeStage.failed;
        _error = '照片暂时打不开,换一张试试';
      });
      return;
    }

    setState(() {
      _stage = _AnalyzeStage.uploading;
      _progress = 0;
      _error = null;
    });

    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      final api = ref.read(enhanceApiProvider);
      final result = await api.analyze(
        imageFile: File(imagePath),
        deviceId: deviceId,
        isShotPaper: widget.args.isShotPaper,
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) {
            return;
          }
          final progress = sent / total;
          setState(() {
            _progress = progress.clamp(0, 1);
            if (sent >= total) {
              _stage = _AnalyzeStage.thinking;
            }
          });
        },
      );

      if (!mounted) {
        return;
      }
      context.go(
        '/enhance/result/${result.jobId}',
        extra: ResultPageArgs(
          originalImagePath: imagePath,
          analyzeResult: result,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _AnalyzeStage.failed;
        _error = humanApiError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final imagePath = widget.args.imagePath;
    return Scaffold(
      appBar: const ElderlyAppBar(title: '正在修图'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
          child: ListView(
            children: [
              if (File(imagePath).existsSync())
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFDDE4DF)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.file(File(imagePath), fit: BoxFit.cover),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFDDE4DF)),
                ),
                child: Column(
                  children: [
                    Icon(
                      _stage == _AnalyzeStage.failed
                          ? Icons.error_outline_rounded
                          : Icons.auto_fix_high_rounded,
                      color: _stage == _AnalyzeStage.failed
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                      size: 46,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _title,
                      style: textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _subtitle,
                      style: textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF68736F),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    if (_stage == _AnalyzeStage.uploading)
                      LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress,
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(8),
                      )
                    else if (_stage == _AnalyzeStage.thinking ||
                        _stage == _AnalyzeStage.preparing)
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(strokeWidth: 5),
                      )
                    else
                      BigButton(
                        text: '再试一次',
                        icon: Icons.refresh_rounded,
                        onPressed: _startAnalyze,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '正在安全处理，不会修改手机里的原图。',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _title {
    return switch (_stage) {
      _AnalyzeStage.preparing => '正在准备照片',
      _AnalyzeStage.uploading => '上传照片中...',
      _AnalyzeStage.thinking => '正在想还有几种修法...',
      _AnalyzeStage.failed => _error ?? '网络不太好,稍后再试',
    };
  }

  String get _subtitle {
    return switch (_stage) {
      _AnalyzeStage.preparing => '请稍等一下',
      _AnalyzeStage.uploading => '马上就好',
      _AnalyzeStage.thinking => '修好后会自动跳到结果页',
      _AnalyzeStage.failed => '可以换张照片,也可以再试一次',
    };
  }
}
