import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/big_button.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            _HomeHeader(onHistoryTap: () => context.go('/history')),
            const SizedBox(height: 18),
            const _HeroPanel(),
            const SizedBox(height: 18),
            BigButton(
              text: '智能修照片',
              subtitle: '模糊、逆光、老照片，一键变清楚',
              icon: Icons.auto_fix_high_rounded,
              height: 104,
              backgroundColor: theme.colorScheme.primary,
              onPressed: () => context.go('/enhance/select'),
            ),
            const SizedBox(height: 14),
            BigButton(
              text: '做祝福视频',
              subtitle: '照片套模板，发给家人更体面',
              icon: Icons.volunteer_activism_rounded,
              height: 104,
              backgroundColor: theme.colorScheme.secondary,
              onPressed: () => context.go('/template'),
            ),
            const SizedBox(height: 18),
            const _TrustPanel(),
            const SizedBox(height: 32),
            _VoiceHint(onLongPress: () => context.go('/settings')),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onHistoryTap});

  final VoidCallback onHistoryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '老照修复',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text('家庭照片智能助手', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        IconButton(
          tooltip: '历史',
          iconSize: 30,
          style: IconButton.styleFrom(
            fixedSize: const Size(56, 56),
            backgroundColor: const Color(0xFFE3F3EE),
            foregroundColor: const Color(0xFF18211F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: onHistoryTap,
          icon: const Icon(Icons.history_rounded),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE4DF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('拍坏了也能救', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 10),
          Text(
            '选一张照片，系统自动判断怎么修。原图不会被覆盖，结果可以保存或发给家人。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF68736F),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(
                child: _MetricPill(icon: Icons.touch_app_rounded, text: '3步完成'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _MetricPill(
                  icon: Icons.lock_outline_rounded,
                  text: '保留原图',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustPanel extends StatelessWidget {
  const _TrustPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0DDC4)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF7E7C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFF8C5A10),
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '不会覆盖原照片，删除记录也不会删手机相册。',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF725018),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceHint extends StatelessWidget {
  const _VoiceHint({required this.onLongPress});

  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDDE4DF)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.record_voice_over_rounded,
              color: theme.colorScheme.primary,
              size: 26,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '不会点?说一声也行',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
