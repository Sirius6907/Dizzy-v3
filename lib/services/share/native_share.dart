import 'dart:io';

import 'package:flutter/services.dart';

/// Zero-dependency native share sheet.
///
/// Android → `ACTION_SEND` chooser via `MainActivity` channel.
/// Everywhere else (Windows/Linux/desktop) → returns false so the caller
/// keeps its clipboard fallback. No `share_plus` needed (its `pub add`
/// currently fails on the pre-existing media_kit git-override resolution).
abstract final class NativeShare {
  static const MethodChannel _channel =
      MethodChannel('com.sirius6907.dizzyv3/share');

  /// Returns true when the system share sheet opened.
  static Future<bool> shareText(String text) async {
    if (!Platform.isAndroid) return false;
    if (text.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'shareText',
        {'text': text},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
