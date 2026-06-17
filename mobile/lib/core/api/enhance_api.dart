import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

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
    final imageBytes = await _prepareImageBytes(imageFile);
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

  Future<List<int>> _prepareImageBytes(File file) async {
    final original = await file.readAsBytes();
    if (original.length <= 2 * 1024 * 1024) {
      final decoded = img.decodeImage(original);
      if (decoded == null) {
        return original;
      }
      final longest = math.max(decoded.width, decoded.height);
      if (longest <= 2400) {
        return original;
      }
    }

    final decoded = img.decodeImage(original);
    if (decoded == null) {
      return original;
    }

    final longest = math.max(decoded.width, decoded.height);
    final resized = longest > 2400
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 2400 : null,
            height: decoded.height > decoded.width ? 2400 : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    var quality = 88;
    var encoded = img.encodeJpg(resized, quality: quality);
    while (encoded.length > 2 * 1024 * 1024 && quality > 58) {
      quality -= 8;
      encoded = img.encodeJpg(resized, quality: quality);
    }
    return encoded;
  }
}
