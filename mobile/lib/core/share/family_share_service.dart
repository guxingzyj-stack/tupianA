import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluwx/fluwx.dart';
import 'package:share_plus/share_plus.dart';

import '../api/device_config_api.dart';
import '../models/device_config_models.dart';

final familyShareServiceProvider = Provider<FamilyShareService>((ref) {
  return FamilyShareService(ref, Fluwx());
});

class FamilyShareService {
  FamilyShareService(this._ref, this._fluwx);

  final Ref _ref;
  final Fluwx _fluwx;
  String? _registeredAppId;
  String? _registeredUniversalLink;

  Future<void> shareImage(File file, {String text = '修好的照片'}) async {
    final sharedToWeChat = await _tryShareToWeChat((_) async {
      final source = Platform.isIOS
          ? WeChatImageToShare(uint8List: await file.readAsBytes())
          : WeChatImageToShare(localImagePath: file.path);
      return _fluwx.share(
        WeChatShareImageModel(
          source,
          title: text,
          description: text,
          scene: WeChatScene.session,
        ),
      );
    });
    if (sharedToWeChat) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/jpeg')],
        text: text,
      ),
    );
  }

  Future<void> shareVideo(File file, {String text = '修好的视频'}) async {
    final sharedToWeChat = await _tryShareToWeChat((_) async {
      return _fluwx.share(
        WeChatShareFileModel(
          WeChatFile.file(file, suffix: '.mp4'),
          title: text,
          description: text,
          scene: WeChatScene.session,
        ),
      );
    });
    if (sharedToWeChat) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'video/mp4')],
        text: text,
      ),
    );
  }

  Future<bool> _tryShareToWeChat(
    Future<bool> Function(DeviceConfig config) share,
  ) async {
    try {
      final config = await _ref.read(deviceConfigProvider.future);
      final appId = config.wechatAppId?.trim();
      if (appId == null || appId.isEmpty) {
        return false;
      }
      final registered = await _ensureRegistered(
        appId,
        _blankToNull(config.wechatUniversalLink),
      );
      if (!registered || !await _fluwx.isWeChatInstalled) {
        return false;
      }
      return await share(config);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureRegistered(String appId, String? universalLink) async {
    if (_registeredAppId == appId &&
        _registeredUniversalLink == universalLink) {
      return true;
    }
    final registered = await _fluwx.registerApi(
      appId: appId,
      universalLink: universalLink,
    );
    if (registered) {
      _registeredAppId = appId;
      _registeredUniversalLink = universalLink;
    }
    return registered;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
