import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _kTraktAccessToken = 'trakt_access_token';
  static const _kTraktRefreshToken = 'trakt_refresh_token';
  static const _kTraktTokenExpiry = 'trakt_token_expiry_ms';
  static const _kTraktUsername = 'trakt_username';

  static const _kSimklAccessToken = 'simkl_access_token';
  static const _kSimklUsername = 'simkl_username';

  static final ValueNotifier<int> movieFinishedRevision = ValueNotifier<int>(0);

  // v1.1.9 (Task 17): single cached instance — cold start + every token
  // read skips the platform-channel round trip. Signatures unchanged.
  static SharedPreferences? _cachedPrefs;
  static Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  // Tokens at rest. flutter_secure_storage is not a dependency, so refresh /
  // access tokens are obfuscated (base64 + static XOR pad) instead of stored
  // as plaintext. This is a stopgap, NOT real secure storage — adding
  // flutter_secure_storage is the proper fix.
  static const _secretPrefix = 'obv1:';
  static const List<int> _xorPad = [
    0x44,
    0x69,
    0x7a,
    0x7a,
    0x79,
    0x2d,
    0x76,
    0x33,
    0x53,
    0x65,
    0x63,
    0x75,
    0x72,
    0x65,
    0x21,
    0x00,
  ];

  static String _obfuscate(String plain) {
    final bytes = utf8.encode(plain);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ _xorPad[i % _xorPad.length],
    );
    return '$_secretPrefix${base64Url.encode(out)}';
  }

  /// Returns `null` for a corrupt value so the caller re-authenticates instead
  /// of using garbage. Legacy plaintext (no prefix) is returned as-is.
  static String? _deobfuscate(String stored) {
    if (!stored.startsWith(_secretPrefix)) return stored;
    try {
      final raw = base64Url.decode(stored.substring(_secretPrefix.length));
      final bytes = List<int>.generate(
        raw.length,
        (i) => raw[i] ^ _xorPad[i % _xorPad.length],
      );
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readSecret(String key) async {
    final prefs = await _prefs();
    final stored = prefs.getString(key);
    if (stored == null) return null;
    final plain = _deobfuscate(stored);
    // Opportunistic migration: upgrade legacy plaintext on first read.
    if (plain != null && !stored.startsWith(_secretPrefix)) {
      await prefs.setString(key, _obfuscate(plain));
    }
    return plain;
  }

  static Future<void> _writeSecret(String key, String value) async {
    final prefs = await _prefs();
    await prefs.setString(key, _obfuscate(value));
  }

  // ── Trakt ─────────────────────────────────────────────────────────────────
  static Future<String?> getTraktAccessToken() async {
    final prefs = await _prefs();
    return prefs.getString(_kTraktAccessToken);
  }

  static Future<void> setTraktAccessToken(String token) async {
    final prefs = await _prefs();
    await prefs.setString(_kTraktAccessToken, token);
  }

  static Future<String?> getTraktRefreshToken() async =>
      _readSecret(_kTraktRefreshToken);

  static Future<void> setTraktRefreshToken(String token) async =>
      _writeSecret(_kTraktRefreshToken, token);

  static Future<int?> getTraktTokenExpiry() async {
    final prefs = await _prefs();
    return prefs.getInt(_kTraktTokenExpiry);
  }

  static Future<void> setTraktTokenExpiry(int expiryMs) async {
    final prefs = await _prefs();
    await prefs.setInt(_kTraktTokenExpiry, expiryMs);
  }

  static Future<String?> getTraktUsername() async {
    final prefs = await _prefs();
    return prefs.getString(_kTraktUsername);
  }

  static Future<void> setTraktUsername(String username) async {
    final prefs = await _prefs();
    await prefs.setString(_kTraktUsername, username);
  }

  static Future<bool> clearTraktAuth() async {
    final prefs = await _prefs();
    await prefs.remove(_kTraktAccessToken);
    await prefs.remove(_kTraktRefreshToken);
    await prefs.remove(_kTraktTokenExpiry);
    await prefs.remove(_kTraktUsername);
    return true;
  }

  // ── Simkl ─────────────────────────────────────────────────────────────────
  static Future<String?> getSimklAccessToken() async =>
      _readSecret(_kSimklAccessToken);

  static Future<void> setSimklAccessToken(String token) async =>
      _writeSecret(_kSimklAccessToken, token);

  static Future<String?> getSimklUsername() async {
    final prefs = await _prefs();
    return prefs.getString(_kSimklUsername);
  }

  static Future<void> setSimklUsername(String username) async {
    final prefs = await _prefs();
    await prefs.setString(_kSimklUsername, username);
  }

  static Future<void> clearSimklAuth() async {
    final prefs = await _prefs();
    await prefs.remove(_kSimklAccessToken);
    await prefs.remove(_kSimklUsername);
  }
}
