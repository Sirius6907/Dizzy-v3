import 'package:flutter/services.dart';

/// Screen shield for the 18+ surface ("private mode").
///
/// While the adult page is on screen we ask the platform to set
/// `FLAG_SECURE`, which blanks screenshots and replaces the Android recents
/// thumbnail with a neutral card. The flag is cleared on leaving the page so
/// the rest of the app behaves normally.
///
/// Only Android implements the channel; every other platform (and the widget
/// test VM) answers with a `MissingPluginException` that we swallow, so the
/// page never fails to open because of the shield.
class PrivateModeShield {
  PrivateModeShield._();

  static const MethodChannel _channel =
      MethodChannel('com.sirius6907.dizzyv3/secure');

  /// Last value we successfully sent, so callers can stay idempotent.
  static bool _engaged = false;

  /// True while the platform is holding `FLAG_SECURE` for us.
  static bool get engaged => _engaged;

  /// Enable or disable the shield. Safe to call repeatedly.
  static Future<void> setSecure(bool enabled) async {
    if (_engaged == enabled) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
      _engaged = enabled;
    } on MissingPluginException {
      // Desktop/test: no native handler. Nothing to protect there; keep the
      // Dart side quiet so navigation never breaks.
    } on PlatformException {
      // Native refused (e.g. window not attached yet) — leave state alone so
      // the next call retries.
    }
  }

  /// Drop the shield regardless of cached state (page dispose path).
  static Future<void> release() async {
    if (!_engaged) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': false});
    } catch (_) {
      // Best effort: the window is going away anyway.
    }
    _engaged = false;
  }

  /// Test hook: forget the cached state between cases.
  static void debugReset() => _engaged = false;
}
