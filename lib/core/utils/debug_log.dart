import 'package:flutter/foundation.dart';

class DebugLog {
  static final Map<String, DateTime> _lastLogAt = <String, DateTime>{};

  static void info(String message) {
    if (!kDebugMode) return;
    debugPrint('[RTL] $message');
  }

  static void throttled(
    String key,
    String message, {
    Duration interval = const Duration(seconds: 5),
  }) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    final last = _lastLogAt[key];
    if (last != null && now.difference(last) < interval) return;
    _lastLogAt[key] = now;
    debugPrint('[RTL] $message');
  }
}
