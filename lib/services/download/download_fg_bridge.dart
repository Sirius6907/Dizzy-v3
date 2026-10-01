import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Phase K2 — Dart side of the downloads foreground service.
///
/// Publishes one aggregate progress notification while downloads are
/// running, and receives the Pause / Cancel buttons pressed on it. Every
/// call is fail-soft: if the service cannot start (no permission, an OEM
/// that refuses), downloads keep working — they just lose background
/// protection, which is strictly better than a thrown exception.
class DownloadFgBridge {
  DownloadFgBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.sirius6907.dizzyv3/downloads',
  );

  static bool _attached = false;
  static bool _running = false;

  /// Set by the download service: pause the queue when the notification's
  /// Pause button is pressed, stop everything when Cancel is.
  static void Function()? onPause;
  static void Function()? onClearAll;

  static bool get isRunning => _running;

  @visibleForTesting
  static void resetForTest() {
    _attached = false;
    _running = false;
  }

  static void attach() {
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onAction') return null;
      final action = call.arguments?.toString();
      if (action == 'pause') {
        onPause?.call();
      } else if (action == 'stop') {
        onClearAll?.call();
        _running = false;
      }
      return null;
    });
  }

  /// Publishes (or refreshes) the notification. No-op while nothing is
  /// downloading, so we never leave a stale notification behind.
  static Future<void> publish({
    required int active,
    required int percent,
    String label = '',
  }) async {
    attach();
    try {
      if (active <= 0) {
        await stop();
        return;
      }
      await _channel.invokeMethod('show', {
        'active': active,
        'percent': percent.clamp(0, 100),
        'label': label,
      });
      _running = true;
    } catch (e) {
      debugPrint('[DownloadFgBridge] publish failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!_running) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('[DownloadFgBridge] stop failed: $e');
    }
    _running = false;
  }
}
