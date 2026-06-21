import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../image/upload_image_optimizer.dart';
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
    final bytes = await prepareUploadImageBytes(imageFile);
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
}
