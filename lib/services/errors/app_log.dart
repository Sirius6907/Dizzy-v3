import 'package:flutter/foundation.dart';

import 'session_trail.dart';

/// P16 — release-stripped debug logger.
///
/// `debugPrint`/`print` still emit in release builds (console spam + wasted
/// cycles). [AppLog.d] compiles to a no-op in release (`kDebugMode` is a
/// compile-time constant), while behaving exactly like `debugPrint` in debug.
///
/// Rule: player/scraper/party internals log via `AppLog.d`. Anything the
/// USER must see uses toasts/easy messages, never logs.
class AppLog {
  const AppLog._();

  static void d(Object? message) {
    if (kDebugMode) {
      // ignore: avoid_print
      debugPrint('$message');
    }
  }

  /// v1.3.3-T2.3 — record a coarse enum breadcrumb for the crash trail.
  /// Costs one string append; the trail only ships with an error report.
  /// Callers pass constants like `nav_home` / `play_start` — never text.
  static void trail(String token) => SessionTrail.record(token);
}
