import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env.dart';

final dioProvider = Provider<Dio>((ref) => createApiDio());

Dio createApiDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppEnv.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {'X-App-Token': AppEnv.appToken},
    ),
  );

  dio.interceptors.add(_RetryOnNetworkErrorInterceptor(dio));
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (error, handler) {
        handler.reject(_toHumanError(error));
      },
    ),
  );

  return dio;
}

class _RetryOnNetworkErrorInterceptor extends Interceptor {
  _RetryOnNetworkErrorInterceptor(this._dio);

  static const _maxRetries = 2;
  static const _retryAttemptKey = 'retry_attempt';

  final Dio _dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = err.requestOptions.extra[_retryAttemptKey] as int? ?? 0;
    if (!_shouldRetry(err) || attempt >= _maxRetries) {
      handler.next(err);
      return;
    }

    final options = err.requestOptions;
    options.extra[_retryAttemptKey] = attempt + 1;
    await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));

    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _shouldRetry(DioException error) {
    if (error.response != null) {
      return false;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => true,
      DioExceptionType.badCertificate ||
      DioExceptionType.badResponse ||
      DioExceptionType.cancel => false,
    };
  }
}

DioException _toHumanError(DioException error) {
  final responseData = error.response?.data;
  final statusCode = error.response?.statusCode;
  var message = _defaultMessageForStatus(statusCode);
  if (statusCode != 401 && statusCode != 403 && responseData is Map) {
    final detail = responseData['detail'];
    final errorMessage = responseData['error'];
    if (detail is String && detail.trim().isNotEmpty) {
      message = detail.trim();
    } else if (errorMessage is String && errorMessage.trim().isNotEmpty) {
      message = errorMessage.trim();
    }
  }
  return DioException(
    requestOptions: error.requestOptions,
    response: error.response,
    type: error.type,
    error: message,
    stackTrace: error.stackTrace,
  );
}

String _defaultMessageForStatus(int? statusCode) {
  return switch (statusCode) {
    400 || 404 || 422 => '这次操作没成功,重新试试',
    401 || 403 => '应用配置不对,请让家人帮忙看一下',
    429 => '今天操作有点多,稍等一下',
    500 || 502 || 503 || 504 => '服务器暂时忙,稍后再试',
    _ => '网络不太好,稍后再试',
  };
}

String humanApiError(Object error) {
  if (error is DioException && error.error is String) {
    return error.error! as String;
  }
  return '网络不太好,稍后再试';
}
