import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// S2 (v1.1.9): lazy Supabase client. Keys come from --dart-define
/// (never hardcoded). All cloud calls fail soft — app never blocks.
class CloudClient {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool _ready = false;
  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;
  static bool get isReady => _ready;

  static final ValueNotifier<bool> cloudAvailable =
      ValueNotifier<bool>(false);

  static SupabaseClient get db => Supabase.instance.client;

  /// Init once at startup. Returns false (soft) if keys missing.
  static Future<bool> init() async {
    if (!isConfigured) {
      debugPrint('[Cloud] SUPABASE_URL/ANON_KEY missing — cloud disabled.');
      return false;
    }
    try {
      await Supabase.initialize(url: _url, anonKey: _anonKey);
      _ready = true;
      cloudAvailable.value = true;
      debugPrint('[Cloud] Supabase ready.');
      return true;
    } catch (e) {
      debugPrint('[Cloud] init failed (soft): $e');
      return false;
    }
  }
}
