import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/template_api.dart';
import '../../../core/device/device_id.dart';
import '../../../core/models/template_models.dart';
import '../../../core/models/video_models.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/elderly_app_bar.dart';
import '../../enhance/providers/photo_picker_provider.dart';

class TemplatePage extends ConsumerStatefulWidget {
  const TemplatePage({super.key});

  @override
  ConsumerState<TemplatePage> createState() => _TemplatePageState();
}

class _TemplatePageState extends ConsumerState<TemplatePage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(templateCatalogProvider);
    return Scaffold(
      appBar: const ElderlyAppBar(title: '做祝福'),
      body: SafeArea(
        child: Stack(
          children: [
            catalog.when(
              data: _buildCatalog,
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              error: (error, stackTrace) => _TemplateError(
                message: humanApiError(error),
                onRetry: () => ref.invalidate(templateCatalogProvider),
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.36),
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalog(TemplateCatalog catalog) {
    final categories = catalog.categories;
    if (categories.isEmpty) {
      return _TemplateError(
        message: '祝福模板暂时打不开',
        onRetry: () => ref.invalidate(templateCatalogProvider),
      );
    }
    return DefaultTabController(
      length: categories.length,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '选择一个模板',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 18),
            tabs: [for (final category in categories) Tab(text: category.name)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final category in categories)
                  _TemplateGrid(category: category, onSelect: _showApplySheet),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showApplySheet(BlessingTemplate template) async {
    var selectedTextIndex = 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      template.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    for (
                      var index = 0;
                      index < template.textPresets.length;
                      index++
                    ) ...[
                      _TextPresetTile(
                        text: template.textPresets[index],
                        selected: index == selectedTextIndex,
                        onTap: () {
                          setSheetState(() => selectedTextIndex = index);
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 14),
                    BigButton(
                      text: '选照片制作',
                      icon: Icons.photo_library_rounded,
                      onPressed: () {
                        Navigator.of(context).pop();
                        _pickAndApply(template, selectedTextIndex);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickAndApply(BlessingTemplate template, int textIndex) async {
    setState(() => _busy = true);
    try {
      final photo = await ref
          .read(photoPickerControllerProvider)
          .pickFromGallery();
      if (!mounted || photo == null) {
        return;
      }
      final deviceId = await ref.read(deviceIdProvider.future);
      final created = await ref
          .read(templateApiProvider)
          .applyTemplate(
            deviceId: deviceId,
            templateId: template.id,
            textIndex: textIndex,
            imageFile: File(photo.path),
          );
      if (!mounted) {
        return;
      }
      context.go(
        '/video/waiting/${created.jobId}',
        extra: VideoWaitingArgs(
          estimatedSeconds: created.estimatedSeconds,
          resultTitle: template.name,
        ),
      );
    } on PhotoPermissionException catch (error) {
      if (mounted) {
        await _showPermissionDialog(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showSnack(humanApiError(error));
      }
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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 18)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({required this.category, required this.onSelect});

  final TemplateCategory category;
  final ValueChanged<BlessingTemplate> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.86,
      ),
      itemCount: category.templates.length,
      itemBuilder: (context, index) {
        final template = category.templates[index];
        return _TemplateCard(
          template: template,
          categoryId: category.id,
          onTap: () => onSelect(template),
        );
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.categoryId,
    required this.onTap,
  });

  final BlessingTemplate template;
  final String categoryId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _categoryColors(categoryId);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDE4DF), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                  ),
                  child: Icon(
                    _categoryIcon(categoryId),
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                template.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF18211F),
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '选照片制作',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF68736F),
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

  List<Color> _categoryColors(String id) {
    switch (id) {
      case 'birthday':
        return const [Color(0xFFB65A3A), Color(0xFFE0A35E)];
      case 'motion':
        return const [Color(0xFF176B5E), Color(0xFF62A89A)];
      case 'family':
        return const [Color(0xFF6254A3), Color(0xFF9B8BD5)];
      default:
        return const [Color(0xFF9E3E55), Color(0xFFE08678)];
    }
  }

  IconData _categoryIcon(String id) {
    switch (id) {
      case 'birthday':
        return Icons.cake_rounded;
      case 'motion':
        return Icons.movie_creation_rounded;
      case 'family':
        return Icons.family_restroom_rounded;
      default:
        return Icons.celebration_rounded;
    }
  }
}

class _TextPresetTile extends StatelessWidget {
  const _TextPresetTile({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : const Color(0xFF4A4A4A),
            width: selected ? 3 : 1.4,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateError extends StatelessWidget {
  const _TemplateError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 72),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          BigButton(
            text: '重试',
            icon: Icons.refresh_rounded,
            isPrimary: false,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
