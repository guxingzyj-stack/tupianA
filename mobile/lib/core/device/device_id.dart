import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final deviceIdProvider = FutureProvider<String>((ref) async {
  const key = 'device_id';
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(key);
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }

  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final generated =
      'device-${DateTime.now().millisecondsSinceEpoch}-'
      '${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
  await prefs.setString(key, generated);
  return generated;
});
