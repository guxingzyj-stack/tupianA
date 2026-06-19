import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/device_config_api.dart';
import '../../../core/api/enhance_api.dart';
import '../../../core/device/device_id.dart';
import '../../../core/models/device_config_models.dart';
import '../../../core/models/enhance_models.dart';
import '../../../core/models/video_models.dart';
import '../../../core/share/family_share_service.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/elderly_app_bar.dart';
import '../../../core/widgets/long_press_compare.dart';
import '../../../core/widgets/option_picker.dart';
import '../../history/storage/history_db.dart';
import '../../shared/placeholder_screen.dart';

class ResultPage extends ConsumerStatefulWidget {
  const ResultPage({super.key, required this.jobId, this.args});

  final String jobId;
  final ResultPageArgs? args;

  @override
  ConsumerState<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends ConsumerState<ResultPage> {
  int _selectedIndex = 0;
  bool _loading = false;
  bool _actionBusy = false;
  String? _error;
  final Map<int, String> _resultRefs = {};
  final Map<int, String> _resultUrls = {};
  String? _baseImageRef;
  bool _appliedPreferred = false;

  AnalyzeResult? get _result => widget.args?.analyzeResult;

  String get _currentImageRef {
    return _resultRefs[_selectedIndex] ??
        _baseImageRef ??
        _result?.baseImageUrl ??
        '';
  }

  @override
  void initState() {
    super.initState();
    _resultRefs.addAll(widget.args?.cachedResultPaths ?? const {});
    _baseImageRef =
        widget.args?.baseLocalPath ?? widget.args?.analyzeResult.baseImageUrl;
    Future<void>.microtask(_recordBaseResult);
    Future<void>.microtask(_applyInitialOption);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final originalPath = widget.args?.originalImagePath;
    if (result == null || originalPath == null) {
      return const PlaceholderScreen(
        title: '修好了',
        message: '这次结果暂时找不到',
        icon: Icons.image_not_supported_rounded,
      );
    }

    final options = result.analysis.options;
    final showAnimateButton = ref
        .watch(deviceConfigProvider)
        .maybeWhen(
          data: (config) =>
              config.enableVideo &&
              (!result.isOldPhoto || config.enableAnimateOld),
          orElse: () => true,
        );
    return Scaffold(
      appBar: const ElderlyAppBar(title: '修好了'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _SectionHeader(title: '照片已修好', subtitle: '长按图片可对比原图，原照片不会被覆盖。'),
            const SizedBox(height: 16),
            _ResultImageCard(
              loading: _loading,
              child: LongPressCompareView(
                originalImage: FileImage(File(originalPath)),
                resultImage: _imageProvider(_currentImageRef),
                borderRadius: 16,
              ),
            ),
            const SizedBox(height: 22),
            _OptionSection(
              options: options,
              selectedIndex: _selectedIndex,
              onSelect: _selectOption,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _InlineError(message: _error!),
            ],
            const SizedBox(height: 22),
            _ActionPanel(
              actionBusy: _actionBusy,
              onShare: _shareCurrentImage,
              onSave: _saveCurrentImage,
              onAnimate: showAnimateButton ? _openAnimateSetup : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectOption(int index) async {
    if (index == _selectedIndex && _resultRefs.containsKey(index)) {
      return;
    }
    setState(() {
      _selectedIndex = index;
      _error = null;
    });
    if (_resultRefs.containsKey(index)) {
      return;
    }

    setState(() => _loading = true);
    try {
      final enhanced = await ref
          .read(enhanceApiProvider)
          .enhance(jobId: widget.jobId, optionIndex: index);
      if (!mounted) {
        return;
      }
      final localFile = await ref
          .read(historyRepositoryProvider)
          .cacheResultImage(
            dio: ref.read(dioProvider),
            imageUrl: enhanced.resultImageUrl,
            jobId: widget.jobId,
            name: 'option_$index',
          );
      await _recordOptionResult(index, localFile.path);
      await _rememberPreferredOption(index);
      setState(() {
        _resultRefs[index] = localFile.path;
        _resultUrls[index] = enhanced.resultImageUrl;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = humanApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _applyInitialOption() async {
    if (_appliedPreferred || _result == null) {
      return;
    }
    _appliedPreferred = true;
    var targetIndex = 0;
    try {
      final config = await ref.read(deviceConfigProvider.future);
      final preferred = config.preferredStyle;
      final options = _result!.analysis.options;
      if (preferred != null && preferred.isNotEmpty) {
        final index = options.indexWhere((option) => option.name == preferred);
        if (index >= 0) {
          targetIndex = index;
        }
      }
    } catch (_) {
      // Preference loading should never block the result page.
    }
    if (!mounted ||
        _result == null ||
        targetIndex >= _result!.analysis.options.length ||
        _resultRefs.containsKey(targetIndex)) {
      return;
    }
    await _selectOption(targetIndex);
  }

  Future<void> _rememberPreferredOption(int optionIndex) async {
    final result = _result;
    if (result == null || optionIndex >= result.analysis.options.length) {
      return;
    }
    final name = result.analysis.options[optionIndex].name;
    if (!{'更明亮', '更鲜艳', '更柔和'}.contains(name)) {
      return;
    }
    try {
      final config = await ref.read(deviceConfigProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref
          .read(deviceConfigApiProvider)
          .updateConfig(
            deviceId: deviceId,
            update: DeviceConfigUpdate(
              preferredStyle: name,
              shareTarget: config.shareTarget,
              wechatAppId: config.wechatAppId,
              wechatUniversalLink: config.wechatUniversalLink,
              relayBaseUrl: config.relayBaseUrl,
              aiModel: config.aiModel,
            ),
          );
      ref.invalidate(deviceConfigProvider);
    } catch (_) {
      // The selected result is already saved locally; preference sync can retry later.
    }
  }

  Future<void> _shareCurrentImage() async {
    await _runImageAction(() async {
      final file = await _downloadCurrentImage();
      await ref.read(familyShareServiceProvider).shareImage(file);
    });
  }

  Future<void> _saveCurrentImage() async {
    await _runImageAction(() async {
      final file = await _downloadCurrentImage();
      final name = '老照_${DateTime.now().millisecondsSinceEpoch}';
      await ImageGallerySaverPlus.saveFile(file.path, name: name);
      _showSnack('已保存');
    });
  }

  Future<void> _recordBaseResult() async {
    final args = widget.args;
    final result = _result;
    if (args == null || result == null || result.baseImageUrl.isEmpty) {
      return;
    }
    try {
      final localFile = await ref
          .read(historyRepositoryProvider)
          .cacheResultImage(
            dio: ref.read(dioProvider),
            imageUrl: result.baseImageUrl,
            jobId: widget.jobId,
            name: 'base',
          );
      await ref
          .read(historyRepositoryProvider)
          .upsertBaseResult(
            jobId: widget.jobId,
            originalImagePath: args.originalImagePath,
            analyzeResult: result,
            baseImagePath: localFile.path,
          );
      if (mounted) {
        setState(() => _baseImageRef = localFile.path);
        ref.invalidate(historyEntriesProvider);
      }
    } catch (_) {
      // The result page can still work from the network image; history can retry
      // once the user selects an option or saves/shares.
    }
  }

  Future<void> _recordOptionResult(int optionIndex, String localPath) async {
    final args = widget.args;
    final result = _result;
    if (args == null || result == null) {
      return;
    }
    final options = result.analysis.options;
    final name = optionIndex < options.length
        ? options[optionIndex].name
        : '修好的照片';
    await ref
        .read(historyRepositoryProvider)
        .upsertOptionResult(
          jobId: widget.jobId,
          originalImagePath: args.originalImagePath,
          analyzeResult: result,
          optionIndex: optionIndex,
          resultImagePath: localPath,
          intentName: name,
        );
    ref.invalidate(historyEntriesProvider);
  }

  void _openAnimateSetup() {
    final imageUrl = _currentVideoImageUrl();
    if (imageUrl.isEmpty) {
      _showSnack('这张照片暂时不能做动态');
      return;
    }
    context.go(
      '/video/animate',
      extra: VideoSetupArgs(
        imageUrl: imageUrl,
        isOldPhoto: _result?.isOldPhoto ?? false,
      ),
    );
  }

  String _currentVideoImageUrl() {
    return _resultUrls[_selectedIndex] ?? _result?.baseImageUrl ?? '';
  }

  Future<void> _runImageAction(Future<void> Function() action) async {
    setState(() => _actionBusy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        _showSnack('网络不太好,稍后再试');
      }
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<File> _downloadCurrentImage() async {
    final currentRef = _currentImageRef;
    if (!_isNetworkRef(currentRef)) {
      final file = File(currentRef);
      if (await file.exists()) {
        return file;
      }
    }

    final local = await ref
        .read(historyRepositoryProvider)
        .cacheResultImage(
          dio: ref.read(dioProvider),
          imageUrl: currentRef,
          jobId: widget.jobId,
          name: _selectedIndex >= 0
              ? 'option_${_selectedIndex}_action'
              : 'base_action',
        );
    return local;
  }

  ImageProvider _imageProvider(String ref) {
    if (_isNetworkRef(ref)) {
      return NetworkImage(ref);
    }
    return FileImage(File(ref));
  }

  bool _isNetworkRef(String ref) {
    return ref.startsWith('http://') || ref.startsWith('https://');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF68736F),
          ),
        ),
      ],
    );
  }
}

class _ResultImageCard extends StatelessWidget {
  const _ResultImageCard({required this.child, required this.loading});

  final Widget child;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Stack(
        children: [
          child,
          Positioned(
            left: 14,
            bottom: 14,
            child: _StatusChip(
              icon: Icons.check_circle_rounded,
              text: '已生成新照片',
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (loading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(strokeWidth: 5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionSection extends StatelessWidget {
  const _OptionSection({
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<RepairOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE4DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('换一种修法', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '不满意可以点下面任意一种效果。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          OptionPicker(
            options: [
              for (final option in options)
                RepairOptionViewModel(name: option.name),
            ],
            selectedIndex: selectedIndex,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.actionBusy,
    required this.onShare,
    required this.onSave,
    required this.onAnimate,
  });

  final bool actionBusy;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback? onAnimate;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  onPressed: actionBusy ? null : onShare,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BigButton(
                  text: '保存',
                  icon: Icons.download_rounded,
                  height: 74,
                  isPrimary: false,
                  onPressed: actionBusy ? null : onSave,
                ),
              ),
            ],
          ),
          if (onAnimate != null) ...[
            const SizedBox(height: 12),
            BigButton(
              text: '让照片动起来',
              subtitle: '生成 8 秒祝福视频',
              icon: Icons.movie_creation_rounded,
              height: 88,
              isPrimary: false,
              onPressed: onAnimate,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5C2BC)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w800,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
