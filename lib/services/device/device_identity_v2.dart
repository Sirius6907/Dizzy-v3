import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/app_log.dart';

/// Phase H — stable device identity v2.
///
/// hwid = sha256(ANDROID_ID / identifierForVendor + FIXED app salt).
/// The salt is a compile-time constant, so an uninstall/reinstall on the
/// SAME phone reproduces the SAME hash → one physical device = one
/// `devices` row forever.
///
/// Fallback chain (all fail-soft, no crash):
///   1. Android: ANDROID_ID (stable per app-signing-key + user profile;
///      same release key since v1.1.7 → same ID across reinstalls)
///   2. iOS: identifierForVendor (stable unless ALL vendor apps removed)
///   3. null/older ROM → random persisted id + `hwidStable=false`
///      (today's behavior — admin sees a weak-identity merge candidate)
///
/// Privacy: the RAW Android ID never leaves the device, is never stored,
/// never logged — only the salted hash is uploaded.
class DeviceIdentityV2 {
  DeviceIdentityV2._();

  /// Fixed app salt — MUST stay constant forever or reinstall hashes
  /// change and every device re-registers as new.
  static const String appSalt = 'dizzy_identity_v2_salt_2026';

  static const String _keyFallbackId = 'diz_hwid_fallback_id_v1';

  static String? _cachedHash;
  static bool? _cachedStable;

  /// Pure: salted sha256 of a platform id. Deterministic by design.
  static String hashOf(String platformId) =>
      sha256.convert(utf8.encode('$appSalt:$platformId')).toString();

  /// Stable hwid hash + stability flag, cached for the process lifetime.
  static Future<({String hash, bool stable})> stableHwid() async {
    if (_cachedHash != null) {
      return (hash: _cachedHash!, stable: _cachedStable!);
    }
    final raw = await _platformId();
    final hash = hashOf(raw.id);
    _cachedHash = hash;
    _cachedStable = raw.stable;
    return (hash: hash, stable: raw.stable);
  }

  /// Platform id lookup. Returns `(id, stable)`; never throws.
  static Future<({String id, bool stable})> _platformId() async {
    try {
      final info = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final a = await info.androidInfo;
        final id = a.id.trim();
        if (id.isNotEmpty && id != 'unknown') {
          return (id: id, stable: true);
        }
      } else if (!kIsWeb && Platform.isIOS) {
        final i = await info.iosInfo;
        final id = (i.identifierForVendor ?? '').trim();
        if (id.isNotEmpty) return (id: id, stable: true);
      }
    } catch (e) {
      AppLog.d('[DeviceIdentityV2] platform id failed (soft): $e');
    }
    // Fallback: random persisted id — reinstall = new identity, but the
    // server knows (hwid_stable=false) so admins treat it as a merge
    // candidate instead of an error.
    try {
      final prefs = await SharedPreferences.getInstance();
      var fb = prefs.getString(_keyFallbackId);
      if (fb == null || fb.isEmpty) {
        fb = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
            hashOf('${DateTime.now().microsecondsSinceEpoch}').substring(0, 12);
        await prefs.setString(_keyFallbackId, fb);
      }
      return (id: fb, stable: false);
    } catch (_) {
      return (id: 'ephemeral', stable: false);
    }
  }

  /// Test-only: drop the process cache.
  @visibleForTesting
  static void resetCache() {
    _cachedHash = null;
    _cachedStable = null;
  }
}
