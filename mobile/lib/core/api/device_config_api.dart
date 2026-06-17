import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_id.dart';
import '../models/device_config_models.dart';
import 'api_client.dart';

final deviceConfigApiProvider = Provider<DeviceConfigApi>((ref) {
  return DeviceConfigApi(ref.watch(dioProvider));
});

final deviceConfigProvider = FutureProvider<DeviceConfig>((ref) async {
  final deviceId = await ref.watch(deviceIdProvider.future);
  return ref.watch(deviceConfigApiProvider).getConfig(deviceId);
});

class DeviceConfigApi {
  const DeviceConfigApi(this._dio);

  final Dio _dio;

  Future<DeviceConfig> getConfig(String deviceId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/devices/$deviceId/config',
    );
    return DeviceConfig.fromJson(response.data ?? const {});
  }

  Future<DeviceConfig> updateConfig({
    required String deviceId,
    required DeviceConfigUpdate update,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/devices/$deviceId/config',
      data: update.toJson(),
    );
    return DeviceConfig.fromJson(response.data ?? const {});
  }
}
