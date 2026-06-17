import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_models.dart';
import 'api_client.dart';

final videoApiProvider = Provider<VideoApi>((ref) {
  return VideoApi(ref.watch(dioProvider));
});

class VideoApi {
  const VideoApi(this._dio);

  final Dio _dio;

  Future<VideoCreateResult> createVideo({
    required String deviceId,
    required String imageUrl,
    required String motion,
    bool isOldPhoto = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/video',
      data: {
        'device_id': deviceId,
        'image_url': imageUrl,
        'motion': motion,
        'is_old_photo': isOldPhoto,
      },
    );
    return VideoCreateResult.fromJson(response.data ?? const {});
  }

  Future<JobStatusResult> getJobStatus(String jobId) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/jobs/$jobId');
    return JobStatusResult.fromJson(response.data ?? const {});
  }
}
