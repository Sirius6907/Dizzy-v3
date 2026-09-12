import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_service.dart';
import '../errors/app_log.dart';

/// S2 (v1.1.9): lazy Supabase client. Keys come from --dart-define
/// (never hardcoded). All cloud calls fail soft — app never blocks.
///
/// v1.2.0-A1: falls back to runtime `.env` via [EnvService] so
/// `flutter run` dev builds also get cloud (CI release builds inject
/// compile-time defines; local dev reads the `.env` file).
class CloudClient {
  static String get _url {
    const c = String.fromEnvironment('SUPABASE_URL');
    if (c.isNotEmpty) return c;
    return EnvService.get('SUPABASE_URL');
  }

  static String get _anonKey {
    const c = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (c.isNotEmpty) return c;
    return EnvService.get('SUPABASE_ANON_KEY');
  }

  static bool _ready = false;
  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;
  static bool get isReady => _ready;

  static final ValueNotifier<bool> cloudAvailable =
      ValueNotifier<bool>(false);

  /// P14: edge-function URL builder (tmdb-proxy, catalog, resolve…).
  /// '' when unconfigured — callers fail soft.
  static String functionUrl(String name) =>
      _url.isEmpty ? '' : '$_url/functions/v1/$name';

  /// P14: anon key for edge-function calls (CORS-allowed `apikey` header).
  static String get anonKey => _anonKey;

  static SupabaseClient get db => Supabase.instance.client;

  /// Init once at startup. Returns false (soft) if keys missing.
  static Future<bool> init() async {
    if (!isConfigured) {
      AppLog.d('[Cloud] SUPABASE_URL/ANON_KEY missing — cloud disabled.');
      return false;
    }
    try {
      await Supabase.initialize(url: _url, anonKey: _anonKey);
      _ready = true;
      cloudAvailable.value = true;
      AppLog.d('[Cloud] Supabase ready.');
      return true;
    } catch (e) {
      AppLog.d('[Cloud] init failed (soft): $e');
      return false;
    }
  }
}
