import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../models/template_models.dart';
import 'api_client.dart';

final templateApiProvider = Provider<TemplateApi>((ref) {
  return TemplateApi(ref.watch(dioProvider));
});

final templateCatalogProvider = FutureProvider<TemplateCatalog>((ref) async {
  return ref.watch(templateApiProvider).getTemplates();
});

class TemplateApi {
  const TemplateApi(this._dio);

  final Dio _dio;

  Future<TemplateCatalog> getTemplates() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/templates');
    return TemplateCatalog.fromJson(response.data ?? const {});
  }

  Future<TemplateApplyResult> applyTemplate({
    required String deviceId,
    required String templateId,
    required int textIndex,
    required File imageFile,
  }) async {
    final bytes = await _prepareImageBytes(imageFile);
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/template/apply',
      data: {
        'device_id': deviceId,
        'template_id': templateId,
        'text_index': textIndex,
        'image': base64Encode(bytes),
      },
    );
    return TemplateApplyResult.fromJson(response.data ?? const {});
  }

  Future<List<int>> _prepareImageBytes(File file) async {
    final original = await file.readAsBytes();
    final decoded = img.decodeImage(original);
    if (decoded == null) {
      return original;
    }

    final longest = math.max(decoded.width, decoded.height);
    if (original.length <= 2 * 1024 * 1024 && longest <= 2400) {
      return original;
    }

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
