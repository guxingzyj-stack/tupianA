import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../dev/widget_demos.dart';
import '../features/enhance/pages/analyzing_page.dart';
import '../features/enhance/pages/result_page.dart';
import '../features/enhance/pages/select_photo_page.dart';
import '../features/enhance/pages/shoot_old_photo_page.dart';
import '../features/history/pages/history_page.dart';
import '../features/home/home_page.dart';
import '../features/settings/pages/settings_page.dart';
import '../features/template/pages/template_page.dart';
import '../features/video/pages/animate_setup_page.dart';
import '../features/video/pages/video_result_page.dart';
import '../features/video/pages/video_waiting_page.dart';
import '../core/models/enhance_models.dart';
import '../core/models/video_models.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(
      path: '/enhance/select',
      builder: (context, state) => const SelectPhotoPage(),
    ),
    GoRoute(
      path: '/enhance/analyzing',
      builder: (context, state) {
        final extra = state.extra;
        final args = extra is AnalyzePageArgs
            ? extra
            : AnalyzePageArgs(imagePath: extra is String ? extra : '');
        return AnalyzingPage(args: args);
      },
    ),
    GoRoute(
      path: '/enhance/shoot-old',
      builder: (context, state) => const ShootOldPhotoPage(),
    ),
    GoRoute(
      path: '/enhance/result/:jobId',
      builder: (context, state) {
        final jobId = state.pathParameters['jobId'] ?? '';
        final args = state.extra is ResultPageArgs
            ? state.extra! as ResultPageArgs
            : null;
        return ResultPage(jobId: jobId, args: args);
      },
    ),
    GoRoute(
      path: '/template',
      builder: (context, state) => const TemplatePage(),
    ),
    GoRoute(
      path: '/video/animate',
      builder: (context, state) {
        final args = state.extra is VideoSetupArgs
            ? state.extra! as VideoSetupArgs
            : const VideoSetupArgs(imageUrl: '');
        return AnimateSetupPage(args: args);
      },
    ),
    GoRoute(
      path: '/video/waiting/:jobId',
      builder: (context, state) {
        final jobId = state.pathParameters['jobId'] ?? '';
        final args = state.extra is VideoWaitingArgs
            ? state.extra! as VideoWaitingArgs
            : const VideoWaitingArgs(estimatedSeconds: 120);
        return VideoWaitingPage(jobId: jobId, args: args);
      },
    ),
    GoRoute(
      path: '/video/result/:jobId',
      builder: (context, state) {
        final jobId = state.pathParameters['jobId'] ?? '';
        final args = state.extra is VideoResultArgs
            ? state.extra! as VideoResultArgs
            : const VideoResultArgs(videoUrl: '');
        return VideoResultPage(jobId: jobId, args: args);
      },
    ),
    GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/dev/widgets',
      builder: (context, state) => const WidgetDemosPage(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('找不到页面')),
    body: const Center(child: Text('这个页面暂时打不开')),
  ),
);
