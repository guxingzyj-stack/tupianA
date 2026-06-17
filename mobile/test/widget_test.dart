import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lao_zhao/app/app.dart';
import 'package:lao_zhao/app/env.dart';
import 'package:lao_zhao/app/router.dart';
import 'package:lao_zhao/core/api/api_client.dart';
import 'package:lao_zhao/core/api/template_api.dart';
import 'package:lao_zhao/core/api/device_config_api.dart';
import 'package:lao_zhao/core/api/video_api.dart';
import 'package:lao_zhao/core/device/device_id.dart';
import 'package:lao_zhao/core/models/device_config_models.dart';
import 'package:lao_zhao/core/models/enhance_models.dart';
import 'package:lao_zhao/core/models/template_models.dart';
import 'package:lao_zhao/core/models/video_models.dart';
import 'package:lao_zhao/core/widgets/confirm_dialog.dart';
import 'package:lao_zhao/features/history/storage/history_db.dart';

void main() {
  test('app version matches MVP release version', () {
    expect(AppEnv.appVersion, '0.1.0');
  });

  test('api client retries transient network errors', () async {
    final dio = createApiDio()
      ..httpClientAdapter = _FlakyAdapter(failuresBeforeSuccess: 2);

    final response = await dio.get<Map<String, dynamic>>('/retry');

    expect(response.data?['ok'], true);
    expect((dio.httpClientAdapter as _FlakyAdapter).attempts, 3);
  });

  test('api client does not retry server responses', () async {
    final adapter = _StatusAdapter(
      statusCode: 401,
      body: '{"detail":"应用 token 不对"}',
    );
    final dio = createApiDio()..httpClientAdapter = adapter;

    try {
      await dio.get<Map<String, dynamic>>('/unauthorized');
      fail('request should fail');
    } on DioException catch (error) {
      expect(error.error, '应用配置不对,请让家人帮忙看一下');
      expect(error.error, isNot(contains('token')));
    }
    expect(adapter.attempts, 1);
  });

  test('api client shows daily budget message from server', () async {
    final adapter = _StatusAdapter(
      statusCode: 429,
      body: '{"detail":"今天的预算用完了,明天再试"}',
    );
    final dio = createApiDio()..httpClientAdapter = adapter;

    try {
      await dio.post<Map<String, dynamic>>('/api/video');
      fail('request should fail');
    } on DioException catch (error) {
      expect(humanApiError(error), '今天的预算用完了,明天再试');
    }
  });

  test('api client hides validation error internals', () async {
    final adapter = _StatusAdapter(
      statusCode: 422,
      body:
          '{"detail":[{"type":"missing","loc":["body","image"],"msg":"Field required"}]}',
    );
    final dio = createApiDio()..httpClientAdapter = adapter;

    try {
      await dio.post<Map<String, dynamic>>('/api/analyze');
      fail('request should fail');
    } on DioException catch (error) {
      expect(humanApiError(error), '这次操作没成功,重新试试');
      expect(humanApiError(error), isNot(contains('Field required')));
    }
  });

  test('video api sends old photo flag', () async {
    final adapter = _CaptureAdapter(
      body: '{"job_id":"job-1","status":"pending","estimated_seconds":20}',
    );
    final dio = createApiDio()..httpClientAdapter = adapter;

    final result = await VideoApi(dio).createVideo(
      deviceId: 'd1',
      imageUrl: 'http://example.com/photo.jpg',
      motion: 'slow_zoom',
      isOldPhoto: true,
    );

    expect(result.jobId, 'job-1');
    expect(adapter.path, '/api/video');
    expect(adapter.sentJson, containsPair('is_old_photo', true));
  });

  testWidgets('generated video share confirm waits before enabling', (
    tester,
  ) async {
    Future<bool>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                result = showConfirmDialog(
                  context: context,
                  title: '确认发给家人?',
                  message: '这是智能生成的视频,可能和真实不同。',
                  confirmText: '发家人',
                  cancelText: '先不发',
                  confirmDelaySeconds: 2,
                );
              },
              child: const Text('打开确认'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pump();

    expect(find.text('确认发给家人?'), findsOneWidget);
    expect(find.text('2 秒后可发'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 秒后可发'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('发家人'), findsOneWidget);

    await tester.tap(find.text('发家人'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });

  test('device config carries WeChat share settings', () {
    final config = DeviceConfig.fromJson(const {
      'device_id': 'd1',
      'wechat_app_id': 'wx123',
      'wechat_universal_link': 'https://example.com/wechat/',
      'is_old_photo': true,
      'has_relay_api_key': false,
    });

    expect(config.wechatAppId, 'wx123');
    expect(config.wechatUniversalLink, 'https://example.com/wechat/');
    final result = AnalyzeResult.fromJson(const {
      'job_id': 'j1',
      'base_image_url': 'http://example.com/base.jpg',
      'is_old_photo': true,
      'analysis': {
        'scene': '老照片',
        'subject': '家人',
        'problems': [],
        'options': [],
      },
    });
    expect(result.isOldPhoto, isTrue);
    expect(result.toJson()['is_old_photo'], isTrue);

    final update = const DeviceConfigUpdate(
      wechatAppId: 'wx456',
      wechatUniversalLink: 'https://family.example/wechat/',
    ).toJson();

    expect(update['wechat_app_id'], 'wx456');
    expect(update['wechat_universal_link'], 'https://family.example/wechat/');

    final partial = const DeviceConfigUpdate(preferredStyle: '更柔和').toJson();
    expect(partial, {'preferred_style': '更柔和'});

    final clearable = const DeviceConfigUpdate(
      shareTarget: '',
      wechatAppId: '',
      wechatUniversalLink: '',
      relayBaseUrl: '',
      aiModel: '',
    ).toJson();
    expect(clearable['share_target'], '');
    expect(clearable['wechat_app_id'], '');
    expect(clearable['wechat_universal_link'], '');
    expect(clearable['relay_base_url'], '');
    expect(clearable['ai_model'], '');
  });

  testWidgets('home page shows primary actions', (tester) async {
    await tester.pumpPhotoRescueApp();

    expect(find.text('拍坏了也能救'), findsOneWidget);
    expect(find.text('智能修照片'), findsOneWidget);
    expect(find.text('做祝福视频'), findsOneWidget);
  });

  testWidgets('home photo action opens photo picker choices', (tester) async {
    await tester.pumpPhotoRescueApp();

    await tester.tap(find.text('智能修照片'));
    await tester.pumpAndSettle();

    expect(find.text('从哪里选照片?'), findsOneWidget);
    expect(find.text('从相册选'), findsOneWidget);
    expect(find.text('现场拍照'), findsOneWidget);
    expect(find.text('拍纸质老照片'), findsOneWidget);
  });

  testWidgets('history action opens empty history page', (tester) async {
    appRouter.go('/');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [historyEntriesProvider.overrideWith((ref) async => [])],
        child: const PhotoRescueApp(),
      ),
    );

    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();

    expect(find.text('我修过的照片'), findsOneWidget);
    expect(find.text('还没有作品'), findsOneWidget);
  });

  testWidgets('history page shows video entries', (tester) async {
    appRouter.go('/history');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceConfigProvider.overrideWith((ref) async => _deviceConfig()),
          historyEntriesProvider.overrideWith((ref) async {
            return [
              HistoryEntry(
                id: 'v1',
                jobId: 'v1',
                originalPath: '',
                basePath: null,
                resultPaths: const {},
                createdAt: DateTime.now(),
                intentName: '中秋团圆',
                analyzeResult: const AnalyzeResult(
                  jobId: 'v1',
                  baseImageUrl: '',
                  analysis: PhotoAnalysis(
                    scene: '视频',
                    subject: '祝福',
                    problems: [],
                    options: [],
                  ),
                ),
                mediaType: 'video',
                videoPath: 'missing.mp4',
              ),
            ];
          }),
        ],
        child: const PhotoRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('中秋团圆'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('share_history_v1')), findsOneWidget);
  });

  testWidgets('history delete asks before deleting', (tester) async {
    final repository = _FakeHistoryRepository();
    appRouter.go('/history');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceConfigProvider.overrideWith((ref) async => _deviceConfig()),
          historyRepositoryProvider.overrideWithValue(repository),
          historyEntriesProvider.overrideWith((ref) async {
            return [
              HistoryEntry(
                id: 'job-1',
                jobId: 'job-1',
                originalPath: '',
                basePath: null,
                resultPaths: const {},
                createdAt: DateTime.now(),
                intentName: '更明亮',
                analyzeResult: const AnalyzeResult(
                  jobId: 'job-1',
                  baseImageUrl: '',
                  analysis: PhotoAnalysis(
                    scene: '照片',
                    subject: '家人',
                    problems: [],
                    options: [],
                  ),
                ),
              ),
            ];
          }),
        ],
        child: const PhotoRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('delete_history_job-1')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('delete_history_job-1')),
    );
    await tester.tap(find.byKey(const ValueKey('delete_history_job-1')));
    await tester.pumpAndSettle();

    expect(find.text('删除这条记录?'), findsOneWidget);
    expect(repository.deletedJobId, isNull);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repository.deletedJobId, 'job-1');
  });

  testWidgets('old photo action opens dedicated camera page', (tester) async {
    await tester.pumpPhotoRescueApp();

    await tester.tap(find.text('智能修照片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拍纸质老照片'));
    await tester.pumpAndSettle();

    expect(find.text('拍老照片'), findsOneWidget);
    expect(find.text('把照片放进框里再拍'), findsOneWidget);
  });

  testWidgets('animate setup page shows safe motion choices', (tester) async {
    appRouter.go(
      '/video/animate',
      extra: const VideoSetupArgs(imageUrl: 'http://example.com/photo.jpg'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceConfigProvider.overrideWith((ref) async => _deviceConfig()),
        ],
        child: const PhotoRescueApp(),
      ),
    );

    expect(find.text('让照片动'), findsOneWidget);
    expect(find.text('缓慢推镜'), findsOneWidget);
    expect(find.text('环境微动'), findsOneWidget);
    expect(find.text('人物轻动'), findsOneWidget);
  });

  testWidgets('animate setup hides old photo motion when disabled', (
    tester,
  ) async {
    appRouter.go(
      '/video/animate',
      extra: const VideoSetupArgs(
        imageUrl: 'http://example.com/old-photo.jpg',
        isOldPhoto: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceConfigProvider.overrideWith(
            (ref) async => _deviceConfig(enableAnimateOld: false),
          ),
        ],
        child: const PhotoRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('老照片暂时不做动态'), findsOneWidget);
    expect(find.text('缓慢推镜'), findsNothing);
  });

  testWidgets('template page shows templates and preset text', (tester) async {
    appRouter.go('/template');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          templateCatalogProvider.overrideWith((ref) async {
            return const TemplateCatalog(
              categories: [
                TemplateCategory(
                  id: 'festival',
                  name: '节日祝福',
                  templates: [
                    BlessingTemplate(
                      id: 'midautumn_reunion',
                      name: '中秋团圆',
                      motion: 'slow_zoom',
                      textPresets: ['中秋快乐 阖家团圆', '千里共婵娟', '团圆庆中秋'],
                    ),
                  ],
                ),
              ],
            );
          }),
        ],
        child: const PhotoRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('做祝福'), findsOneWidget);
    expect(find.text('节日祝福'), findsOneWidget);
    expect(find.text('中秋团圆'), findsOneWidget);

    await tester.tap(find.text('中秋团圆'));
    await tester.pumpAndSettle();

    expect(find.text('中秋快乐 阖家团圆'), findsOneWidget);
    expect(find.text('选照片制作'), findsAtLeastNWidgets(1));
  });

  testWidgets('settings unlocks child config after long press version', (
    tester,
  ) async {
    appRouter.go('/settings');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceIdProvider.overrideWith((ref) async => 'd1'),
          deviceConfigProvider.overrideWith((ref) async {
            return const DeviceConfig(
              deviceId: 'd1',
              dailyBudgetCny: 10,
              dailyVideoLimit: 10,
              preferredStyle: '更明亮',
              enableVideo: true,
              enableAnimateOld: false,
              hasRelayApiKey: false,
            );
          }),
        ],
        child: const PhotoRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('子女配置'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('version_unlock_text')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('version_unlock_text')),
    );
    final versionUnlock = find
        .byKey(const ValueKey('version_unlock_text'))
        .hitTestable();
    expect(versionUnlock, findsOneWidget);

    await tester.longPress(versionUnlock);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 640));
    await tester.pumpAndSettle();

    expect(find.text('子女配置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('保存配置'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('保存配置'), findsOneWidget);
    expect(find.text('Relay API Key'), findsOneWidget);
  });
}

extension _PumpApp on WidgetTester {
  Future<void> pumpPhotoRescueApp() async {
    appRouter.go('/');
    await pumpWidget(const ProviderScope(child: PhotoRescueApp()));
    await pumpAndSettle();
  }
}

class _FakeHistoryRepository extends HistoryRepository {
  String? deletedJobId;

  @override
  Future<void> deleteEntry(String jobId) async {
    deletedJobId = jobId;
  }
}

DeviceConfig _deviceConfig({
  bool enableVideo = true,
  bool enableAnimateOld = true,
}) {
  return DeviceConfig(
    deviceId: 'd1',
    dailyBudgetCny: 10,
    dailyVideoLimit: 10,
    preferredStyle: '更明亮',
    enableVideo: enableVideo,
    enableAnimateOld: enableAnimateOld,
    hasRelayApiKey: false,
  );
}

class _FlakyAdapter implements HttpClientAdapter {
  _FlakyAdapter({required this.failuresBeforeSuccess});

  final int failuresBeforeSuccess;
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts += 1;
    if (attempts <= failuresBeforeSuccess) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts += 1;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter({required this.body});

  final String body;
  String? path;
  Map<String, dynamic>? sentJson;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    sentJson = Map<String, dynamic>.from(options.data as Map);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
