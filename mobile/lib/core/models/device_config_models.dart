class DeviceConfig {
  const DeviceConfig({
    required this.deviceId,
    this.nickname,
    required this.dailyBudgetCny,
    required this.dailyVideoLimit,
    this.preferredStyle,
    required this.enableVideo,
    required this.enableAnimateOld,
    this.shareTarget,
    this.wechatAppId,
    this.wechatUniversalLink,
    this.relayBaseUrl,
    this.aiModel,
    required this.hasRelayApiKey,
  });

  final String deviceId;
  final String? nickname;
  final double dailyBudgetCny;
  final int dailyVideoLimit;
  final String? preferredStyle;
  final bool enableVideo;
  final bool enableAnimateOld;
  final String? shareTarget;
  final String? wechatAppId;
  final String? wechatUniversalLink;
  final String? relayBaseUrl;
  final String? aiModel;
  final bool hasRelayApiKey;

  factory DeviceConfig.fromJson(Map<String, dynamic> json) {
    return DeviceConfig(
      deviceId: json['device_id'] as String? ?? '',
      nickname: json['nickname'] as String?,
      dailyBudgetCny: (json['daily_budget_cny'] as num?)?.toDouble() ?? 10,
      dailyVideoLimit: json['daily_video_limit'] as int? ?? 10,
      preferredStyle: json['preferred_style'] as String?,
      enableVideo: json['enable_video'] as bool? ?? true,
      enableAnimateOld: json['enable_animate_old'] as bool? ?? false,
      shareTarget: json['share_target'] as String?,
      wechatAppId: json['wechat_app_id'] as String?,
      wechatUniversalLink: json['wechat_universal_link'] as String?,
      relayBaseUrl: json['relay_base_url'] as String?,
      aiModel: json['ai_model'] as String?,
      hasRelayApiKey: json['has_relay_api_key'] as bool? ?? false,
    );
  }
}

class DeviceConfigUpdate {
  const DeviceConfigUpdate({
    this.nickname,
    this.dailyBudgetCny,
    this.dailyVideoLimit,
    this.preferredStyle,
    this.enableVideo,
    this.enableAnimateOld,
    this.shareTarget,
    this.wechatAppId,
    this.wechatUniversalLink,
    this.relayBaseUrl,
    this.relayApiKey,
    this.aiModel,
    this.clearRelayApiKey = false,
  });

  final String? nickname;
  final double? dailyBudgetCny;
  final int? dailyVideoLimit;
  final String? preferredStyle;
  final bool? enableVideo;
  final bool? enableAnimateOld;
  final String? shareTarget;
  final String? wechatAppId;
  final String? wechatUniversalLink;
  final String? relayBaseUrl;
  final String? relayApiKey;
  final String? aiModel;
  final bool clearRelayApiKey;

  Map<String, dynamic> toJson() {
    return {
      if (nickname != null) 'nickname': nickname,
      if (dailyBudgetCny != null) 'daily_budget_cny': dailyBudgetCny,
      if (dailyVideoLimit != null) 'daily_video_limit': dailyVideoLimit,
      if (preferredStyle != null) 'preferred_style': preferredStyle,
      if (enableVideo != null) 'enable_video': enableVideo,
      if (enableAnimateOld != null) 'enable_animate_old': enableAnimateOld,
      if (shareTarget != null) 'share_target': shareTarget,
      if (wechatAppId != null) 'wechat_app_id': wechatAppId,
      if (wechatUniversalLink != null)
        'wechat_universal_link': wechatUniversalLink,
      if (relayBaseUrl != null) 'relay_base_url': relayBaseUrl,
      if (relayApiKey != null && relayApiKey!.isNotEmpty)
        'relay_api_key': relayApiKey,
      if (aiModel != null) 'ai_model': aiModel,
      if (clearRelayApiKey) 'clear_relay_api_key': clearRelayApiKey,
    };
  }
}
