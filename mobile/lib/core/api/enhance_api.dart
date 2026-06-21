import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../image/upload_image_optimizer.dart';
import '../models/enhance_models.dart';
import 'api_client.dart';

final enhanceApiProvider = Provider<EnhanceApi>((ref) {
  return EnhanceApi(ref.watch(dioProvider));
});

class EnhanceApi {
  const EnhanceApi(this._dio);

  final Dio _dio;

  Future<AnalyzeResult> analyze({
    required File imageFile,
    required String deviceId,
    bool isShotPaper = false,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final imageBytes = await prepareUploadImageBytes(imageFile);
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/analyze',
      data: {
        'device_id': deviceId,
        'image': base64Encode(imageBytes),
        'is_shot_paper': isShotPaper,
      },
      onSendProgress: onSendProgress,
    );
    return AnalyzeResult.fromJson(response.data ?? const {});
  }

  Future<EnhanceResult> enhance({
    required String jobId,
    required int optionIndex,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/enhance',
      data: {'job_id': jobId, 'option_index': optionIndex},
    );
    return EnhanceResult.fromJson(response.data ?? const {});
  }
}
