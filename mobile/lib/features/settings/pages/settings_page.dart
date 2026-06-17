import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/env.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/device_config_api.dart';
import '../../../core/device/device_id.dart';
import '../../../core/models/device_config_models.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/elderly_app_bar.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _nickname = TextEditingController();
  final _dailyBudget = TextEditingController();
  final _dailyVideoLimit = TextEditingController();
  final _shareTarget = TextEditingController();
  final _wechatAppId = TextEditingController();
  final _wechatUniversalLink = TextEditingController();
  final _relayBaseUrl = TextEditingController();
  final _relayApiKey = TextEditingController();
  final _aiModel = TextEditingController();
  bool _childUnlocked = false;
  bool _saving = false;
  bool _enableVideo = true;
  bool _enableAnimateOld = false;
  bool _clearRelayKey = false;
  String _preferredStyle = '更明亮';
  String? _loadedDeviceId;

  @override
  void dispose() {
    _nickname.dispose();
    _dailyBudget.dispose();
    _dailyVideoLimit.dispose();
    _shareTarget.dispose();
    _wechatAppId.dispose();
    _wechatUniversalLink.dispose();
    _relayBaseUrl.dispose();
    _relayApiKey.dispose();
    _aiModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(deviceConfigProvider);
    return Scaffold(
      appBar: const ElderlyAppBar(title: '设置'),
      body: SafeArea(
        child: Stack(
          children: [
            config.when(
              data: (config) {
                _loadConfig(config);
                return _childUnlocked
                    ? _buildChildConfig(context, config)
                    : _buildLockedSettings(context, config);
              },
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              error: (error, stackTrace) => _SettingsError(
                message: humanApiError(error),
                onRetry: () => ref.invalidate(deviceConfigProvider),
              ),
            ),
            if (_saving)
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

  Widget _buildLockedSettings(BuildContext context, DeviceConfig config) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('家庭设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '这里显示当前设备的使用配置。子女可长按底部版本号进入高级配置。',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF68736F)),
        ),
        const SizedBox(height: 18),
        _SummaryTile(
          icon: Icons.movie_creation_rounded,
          title: '视频功能',
          value: config.enableVideo ? '已开启' : '已关闭',
        ),
        const SizedBox(height: 12),
        _SummaryTile(
          icon: Icons.tune_rounded,
          title: '默认偏好',
          value: config.preferredStyle ?? '更明亮',
        ),
        const SizedBox(height: 12),
        _SummaryTile(
          icon: Icons.family_restroom_rounded,
          title: '分享目标',
          value: config.shareTarget?.isNotEmpty == true
              ? config.shareTarget!
              : '未设置',
        ),
        const SizedBox(height: 12),
        _SummaryTile(
          icon: Icons.chat_bubble_rounded,
          title: '微信分享',
          value: config.wechatAppId?.isNotEmpty == true ? '已配置' : '系统分享',
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF0DDC4)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                color: Color(0xFF8C5A10),
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '高级配置已隐藏，避免误触修改。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF725018),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 44),
        TextButton(
          key: const ValueKey('version_unlock_text'),
          onLongPress: _unlockChildConfig,
          onPressed: () {},
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF68736F),
            padding: const EdgeInsets.symmetric(vertical: 12),
            textStyle: Theme.of(context).textTheme.bodyLarge,
          ),
          child: Text('版本 ${AppEnv.appVersion}', textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _buildChildConfig(BuildContext context, DeviceConfig config) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('子女配置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '用于控制预算、分享、模型和视频能力。保存后会同步到这台设备。',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF68736F)),
        ),
        const SizedBox(height: 18),
        _SettingsGroup(
          title: '老人使用',
          children: [
            _field(_nickname, '老人备注', hint: '王奶奶'),
            _numberField(_dailyBudget, '日预算上限', suffix: '元'),
            _numberField(_dailyVideoLimit, '每日视频上限', suffix: '次'),
            DropdownButtonFormField<String>(
              initialValue: _preferredStyle,
              decoration: const InputDecoration(labelText: '默认修图偏好'),
              items: const [
                DropdownMenuItem(value: '更明亮', child: Text('更明亮')),
                DropdownMenuItem(value: '更鲜艳', child: Text('更鲜艳')),
                DropdownMenuItem(value: '更柔和', child: Text('更柔和')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _preferredStyle = value);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroup(
          title: '视频与分享',
          children: [
            _switchTile(
              title: '视频功能',
              value: _enableVideo,
              onChanged: (value) => setState(() => _enableVideo = value),
            ),
            _switchTile(
              title: '老照片动起来',
              value: _enableAnimateOld,
              onChanged: (value) => setState(() => _enableAnimateOld = value),
            ),
            _field(_shareTarget, '微信分享目标', hint: '家人群'),
            _field(_wechatAppId, '微信 AppID', hint: 'wx...'),
            _field(
              _wechatUniversalLink,
              '微信 Universal Link',
              hint: 'https://.../',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroup(
          title: '智能服务',
          children: [
            _field(_relayBaseUrl, 'Relay 地址', hint: 'https://.../v1'),
            _field(
              _relayApiKey,
              'Relay API Key',
              hint: config.hasRelayApiKey ? '已设置,留空不改' : '还没有设置',
              obscure: true,
            ),
            _field(_aiModel, '分析模型', hint: 'claude-sonnet-4-6'),
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                value: _clearRelayKey,
                onChanged: (value) =>
                    setState(() => _clearRelayKey = value ?? false),
                title: const Text('清除已保存的 API Key'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        BigButton(
          text: '保存配置',
          icon: Icons.save_rounded,
          onPressed: _saving ? null : _saveConfig,
        ),
        const SizedBox(height: 12),
        BigButton(
          text: '退出配置',
          icon: Icons.lock_rounded,
          isPrimary: false,
          onPressed: () => setState(() => _childUnlocked = false),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF8FAF8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    required String suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          filled: true,
          fillColor: const Color(0xFFF8FAF8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: Colors.transparent,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontSize: 20)),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  void _loadConfig(DeviceConfig config) {
    if (_loadedDeviceId == config.deviceId) {
      return;
    }
    _loadedDeviceId = config.deviceId;
    _nickname.text = config.nickname ?? '';
    _dailyBudget.text = config.dailyBudgetCny.toStringAsFixed(1);
    _dailyVideoLimit.text = config.dailyVideoLimit.toString();
    _shareTarget.text = config.shareTarget ?? '';
    _wechatAppId.text = config.wechatAppId ?? '';
    _wechatUniversalLink.text = config.wechatUniversalLink ?? '';
    _relayBaseUrl.text = config.relayBaseUrl ?? '';
    _relayApiKey.clear();
    _aiModel.text = config.aiModel ?? 'claude-sonnet-4-6';
    final preferred = config.preferredStyle;
    _preferredStyle = {'更明亮', '更鲜艳', '更柔和'}.contains(preferred)
        ? preferred!
        : '更明亮';
    _enableVideo = config.enableVideo;
    _enableAnimateOld = config.enableAnimateOld;
    _clearRelayKey = false;
  }

  void _unlockChildConfig() {
    if (mounted && !_childUnlocked) {
      setState(() => _childUnlocked = true);
      _showSnack('已进入子女配置');
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref
          .read(deviceConfigApiProvider)
          .updateConfig(
            deviceId: deviceId,
            update: DeviceConfigUpdate(
              nickname: _blankToNull(_nickname.text),
              dailyBudgetCny: double.tryParse(_dailyBudget.text.trim()),
              dailyVideoLimit: int.tryParse(_dailyVideoLimit.text.trim()),
              preferredStyle: _preferredStyle,
              enableVideo: _enableVideo,
              enableAnimateOld: _enableAnimateOld,
              shareTarget: _trimmed(_shareTarget.text),
              wechatAppId: _trimmed(_wechatAppId.text),
              wechatUniversalLink: _trimmed(_wechatUniversalLink.text),
              relayBaseUrl: _trimmed(_relayBaseUrl.text),
              relayApiKey: _blankToNull(_relayApiKey.text),
              aiModel: _trimmed(_aiModel.text),
              clearRelayApiKey: _clearRelayKey,
            ),
          );
      ref.invalidate(deviceConfigProvider);
      if (mounted) {
        _loadedDeviceId = null;
        _showSnack('已保存');
      }
    } catch (error) {
      if (mounted) {
        _showSnack(humanApiError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _trimmed(String value) {
    return value.trim();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE4DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE4DF), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4EF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 28,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF68736F),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDDE4DF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 72,
                color: Theme.of(context).colorScheme.error,
              ),
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
        ),
      ),
    );
  }
}
