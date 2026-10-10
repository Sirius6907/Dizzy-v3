import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Desktop database bridge (2026-10-10).
///
/// Why: `sqflite` ships Android/iOS/macOS Darwin plugins only — there is
/// NO Windows/Linux plugin. Any package that stores its index in sqflite
/// (`flutter_cache_manager` → every `CachedNetworkImage`) throws
/// `MissingPluginException` on first write on desktop, so ALL remote
/// images render blank (music covers, artist photos, posters — everything).
///
/// Fix: on desktop, route sqflite through the FFI backend before anything
/// touches a database. Mobile keeps the native plugins (untouched path).
/// Safe to call multiple times; never throws (fail-soft — startup must
/// never die because a cache backend hiccuped).
class DesktopDatabase {
  static bool _ready = false;

  static Future<void> initialize() async {
    if (_ready) return;
    if (!(Platform.isWindows || Platform.isLinux)) {
      _ready = true;
      return;
    }
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ready = true;
      debugPrint('[DesktopDatabase] sqflite FFI backend ready');
    } catch (e) {
      debugPrint('[DesktopDatabase] FFI init failed (images may stay blank): $e');
    }
  }
}
