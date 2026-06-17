import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class PhotoRescueApp extends StatelessWidget {
  const PhotoRescueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '老照修复',
      debugShowCheckedModeBanner: false,
      theme: ElderlyTheme.light,
      routerConfig: appRouter,
    );
  }
}
