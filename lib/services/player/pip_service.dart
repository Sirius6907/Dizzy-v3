import 'dart:io';
import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import '../errors/app_log.dart';

/// F1 (v1.1.9): Android-only Picture-in-Picture helper.
///
/// On non-Android platforms (Windows/Linux/macOS/web), `isSupported` is false
/// and all operations are safe no-ops.
class PipService {
  static final Floating _floating = Floating();

  /// True ONLY on Android where PiP hardware/OS capability is present.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Checks if the device OS actually allows PiP right now.
  static Future<bool> canEnterPip() async {
    if (!isSupported) return false;
    try {
      return await _floating.isPipAvailable;
    } catch (_) {
      return false;
    }
  }

  /// Attempts to enter PiP mode. Returns true if granted.
  static Future<bool> enterPip({
    int widthRatio = 16,
    int heightRatio = 9,
  }) async {
    if (!isSupported) return false;
    try {
      final status = await _floating.enable(
        ImmediatePiP(
          aspectRatio: Rational(widthRatio, heightRatio),
        ),
      );
      return status == PiPStatus.enabled;
    } catch (e) {
      AppLog.d('[PipService] enterPip failed: $e');
      return false;
    }
  }

  /// Listen to PiP status changes (e.g. to hide player chrome while in PiP).
  static Stream<PiPStatus> get pipStatusStream => _floating.pipStatusStream;
}
