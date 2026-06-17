import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/models/enhance_models.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/elderly_app_bar.dart';
import '../providers/photo_picker_provider.dart';

class SelectPhotoPage extends ConsumerStatefulWidget {
  const SelectPhotoPage({super.key});

  @override
  ConsumerState<SelectPhotoPage> createState() => _SelectPhotoPageState();
}

class _SelectPhotoPageState extends ConsumerState<SelectPhotoPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ElderlyAppBar(title: '选择照片'),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  '从哪里选照片?',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '一次处理一张，原图会保留在手机里。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF68736F),
                  ),
                ),
                const SizedBox(height: 20),
                BigButton(
                  text: '从相册选',
                  subtitle: '修最近拍的照片',
                  icon: Icons.photo_library_rounded,
                  height: 96,
                  onPressed: _busy ? null : _pickFromGallery,
                ),
                const SizedBox(height: 14),
                BigButton(
                  text: '现场拍照',
                  subtitle: '拍完直接修',
                  icon: Icons.photo_camera_rounded,
                  height: 96,
                  isPrimary: false,
                  onPressed: _busy ? null : _takePhoto,
                ),
                const SizedBox(height: 14),
                BigButton(
                  text: '拍纸质老照片',
                  subtitle: '翻拍、裁正、修复泛黄划痕',
                  icon: Icons.filter_frames_rounded,
                  height: 96,
                  isPrimary: false,
                  onPressed: _busy ? null : _openOldPhotoCamera,
                ),
                const SizedBox(height: 20),
                const _PrivacyNotice(),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: 0.72),
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
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    await _runPicker(() {
      return ref.read(photoPickerControllerProvider).pickFromGallery();
    });
  }

  Future<void> _takePhoto() async {
    await _runPicker(() {
      return ref.read(photoPickerControllerProvider).takePhoto();
    });
  }

  Future<void> _runPicker(Future<PickedPhoto?> Function() pick) async {
    setState(() => _busy = true);
    try {
      final photo = await pick();
      if (!mounted || photo == null) {
        return;
      }
      context.go(
        '/enhance/analyzing',
        extra: AnalyzePageArgs(imagePath: photo.path),
      );
    } on PhotoPermissionException catch (error) {
      if (!mounted) {
        return;
      }
      await _showPermissionDialog(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnack('照片暂时打不开,换一张试试');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showPermissionDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('需要权限'),
          content: Text(message, style: Theme.of(context).textTheme.bodyLarge),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('先不了'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  void _openOldPhotoCamera() {
    context.go('/enhance/shoot-old');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 18)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE4DF)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '只生成新的修复结果，不会改动原照片。',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
