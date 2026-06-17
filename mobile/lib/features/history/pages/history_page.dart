import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/share/family_share_service.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/elderly_app_bar.dart';
import '../storage/history_db.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(historyEntriesProvider);
    return Scaffold(
      appBar: const ElderlyAppBar(title: '我修过的照片'),
      body: SafeArea(
        child: entries.when(
          data: (items) {
            if (items.isEmpty) {
              return const _EmptyHistory();
            }
            final grouped = _groupEntries(items);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text('最近作品', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  '修好的照片和视频会保存在这里，方便再次查看或发给家人。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF68736F),
                  ),
                ),
                const SizedBox(height: 12),
                for (final group in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 10),
                    child: Text(
                      group.key,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.70,
                        ),
                    itemCount: group.value.length,
                    itemBuilder: (context, index) {
                      final entry = group.value[index];
                      return _HistoryTile(entry: entry);
                    },
                  ),
                ],
              ],
            );
          },
          loading: () => const Center(
            child: SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(strokeWidth: 5),
            ),
          ),
          error: (error, stackTrace) => const _HistoryProblem(),
        ),
      ),
    );
  }

  Map<String, List<HistoryEntry>> _groupEntries(List<HistoryEntry> entries) {
    final grouped = <String, List<HistoryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(_dateLabel(entry.createdAt), () => []).add(entry);
    }
    return grouped;
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(date.year, date.month, date.day);
    final days = today.difference(itemDay).inDays;
    if (days == 0) {
      return '今天';
    }
    if (days == 1) {
      return '昨天';
    }
    if (days <= 7) {
      return '$days 天前';
    }
    return '更早';
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailPath = entry.thumbnailPath;
    return InkWell(
      onTap: () {
        if (entry.isVideo) {
          context.go(
            '/video/result/${entry.jobId}',
            extra: entry.toVideoArgs(),
          );
          return;
        }
        context.go(
          '/enhance/result/${entry.jobId}',
          extra: entry.toResultArgs(),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDDE4DF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child:
                            thumbnailPath == null ||
                                !File(thumbnailPath).existsSync()
                            ? ColoredBox(
                                color: const Color(0xFFF1F3F1),
                                child: Icon(
                                  entry.isVideo
                                      ? Icons.play_circle_fill_rounded
                                      : Icons.image_not_supported_rounded,
                                  size: entry.isVideo ? 58 : 44,
                                  color: const Color(0xFF68736F),
                                ),
                              )
                            : Image.file(
                                File(thumbnailPath),
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _TypeBadge(isVideo: entry.isVideo),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                entry.intentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SmallActionButton(
                      key: ValueKey('share_history_${entry.jobId}'),
                      icon: Icons.ios_share_rounded,
                      text: '发',
                      onTap: () => _shareEntry(context, ref),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SmallActionButton(
                      key: ValueKey('delete_history_${entry.jobId}'),
                      icon: Icons.delete_outline_rounded,
                      text: '删',
                      danger: true,
                      onTap: () => _confirmDelete(context, ref),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareEntry(BuildContext context, WidgetRef ref) async {
    final path = entry.isVideo ? entry.videoPath : entry.thumbnailPath;
    if (path == null || path.isEmpty) {
      _showSnack(context, '这条记录暂时不能发');
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      if (!context.mounted) {
        return;
      }
      _showSnack(context, '这条记录暂时不能发');
      return;
    }
    if (!context.mounted) {
      return;
    }
    try {
      if (entry.isVideo) {
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
      }
      final share = ref.read(familyShareServiceProvider);
      if (entry.isVideo) {
        await share.shareVideo(file, text: entry.intentName);
      } else {
        await share.shareImage(file, text: entry.intentName);
      }
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, '暂时发不了,稍后再试');
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除这条记录?',
      message: '只删除这里的记录,不会删手机相册里的原图。',
      confirmText: '删除',
      cancelText: '先不删',
      danger: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      await ref.read(historyRepositoryProvider).deleteEntry(entry.jobId);
      ref.invalidate(historyEntriesProvider);
      if (context.mounted) {
        _showSnack(context, '已删除');
      }
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, '暂时删不了,稍后再试');
      }
    }
  }

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 18)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDDE4DF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4EF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '还没有作品',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '修好的照片和祝福视频会自动出现在这里。',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF68736F)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryProblem extends StatelessWidget {
  const _HistoryProblem();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDDE4DF)),
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
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '历史记录暂时打不开',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '修图和保存功能不受影响，稍后再回来看看。',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF68736F)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVideo ? Icons.play_arrow_rounded : Icons.image_rounded,
              size: 17,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              isVideo ? '视频' : '照片',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
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

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
