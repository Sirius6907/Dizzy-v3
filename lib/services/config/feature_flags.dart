/// Compile-time feature flags (v1.1.9 Task 18).
/// Flip to `true` to re-enable a gated feature. Zero runtime cost.
library;

import 'package:flutter/foundation.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';

/// Arabic-dubbed anime section (pages + service + extractor wiring).
/// OFF by default: saves APK size pressure + removes a dead-code network
/// surface. Reversible — set true, rebuild, done.
const bool kEnableArabic = false;

/// P2: defaults used when the server has no opinion, or cannot be reached.
///
/// These are the values the app must ship with. A server flag may only
/// *restrict* (turn something off) or enable something already built; it
/// must never be the only record that a feature exists, because a device
/// that starts offline would otherwise be permanently broken.
const Map<String, bool> kServerFlagsFallback = <String, bool>{
  'watch_party': true,
  'party_voice': true,
  'error_reporting': true,
  'scraper_health': true,
  'anime_arabic': kEnableArabic,
  'kids_mode': false,
};

/// P2: skeleton for server-driven flags.
///
/// Reads a `feature_flags` table of `{key, enabled}` rows. That table does
/// not exist yet — it is P8 scope — so today every lookup returns the
/// fallbacks above and the fetch is skipped. The point of landing this now
/// is that callers can be written against one accessor and gain remote
/// control for free when the table ships.
///
/// Every failure is silent and non-fatal: unreachable cloud, missing table,
/// permission denied, malformed rows all resolve to [kServerFlagsFallback].
/// A flag service that can crash the app on boot is worse than no flags.
class ServerFlags {
  const ServerFlags._();

  /// Reserved for P8. Referenced only as a string so this file keeps
  /// compiling whether or not the table exists.
  static const String tableName = 'feature_flags';

  static final ValueNotifier<Map<String, bool>> current =
      ValueNotifier<Map<String, bool>>(Map<String, bool>.of(kServerFlagsFallback));

  static bool _loaded = false;

  /// True once a fetch has run. False means "still on fallbacks".
  static bool get isLoaded => _loaded;

  /// Single accessor for gated UI. Unknown keys are OFF, never true: an
  /// unrecognised flag name is a typo, and a typo must not enable a
  /// feature nobody built. Membership is checked against the *shipped*
  /// key set, not against whatever the last load happened to return.
  static bool isOn(String key) {
    if (!kServerFlagsFallback.containsKey(key)) return false;
    return current.value[key] ?? kServerFlagsFallback[key]!;
  }

  /// Fetch server flags once. Returns the values in force afterwards.
  ///
  /// Safe to call at startup: on any failure it returns the fallbacks and
  /// never throws.
  static Future<Map<String, bool>> load() async {
    if (!CloudClient.isReady) {
      _loaded = true;
      return current.value;
    }
    try {
      final res = await CloudClient.db
          .from(tableName)
          .select('key,enabled')
          .limit(200);
      final rows = res as List<dynamic>;
      current.value = merge(mergeable(rows));
    } catch (e) {
      // Table absent (the normal case until P8), RLS denial, or offline.
      AppLog.d('[ServerFlags] server flags unavailable, using fallbacks.');
      current.value = Map<String, bool>.of(kServerFlagsFallback);
    } finally {
      _loaded = true;
    }
    return current.value;
  }

  /// Keeps only usable rows: string keys, real booleans, known flags.
  /// Anything else is dropped rather than guessed at.
  @visibleForTesting
  static List<Map<String, dynamic>> mergeable(List<dynamic> rows) {
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final key = row['key'];
      final enabled = row['enabled'];
      if (key is! String || enabled is! bool) continue;
      if (!kServerFlagsFallback.containsKey(key)) continue;
      out.add(<String, dynamic>{'key': key, 'enabled': enabled});
    }
    return out;
  }

  /// Server rows over fallback defaults. Unknown keys never enter the map.
  @visibleForTesting
  static Map<String, bool> merge(List<Map<String, dynamic>> rows) {
    final out = Map<String, bool>.of(kServerFlagsFallback);
    for (final row in rows) {
      final key = row['key'];
      final enabled = row['enabled'];
      if (key is String && enabled is bool) out[key] = enabled;
    }
    return out;
  }

  /// Test hook: drop back to the shipped defaults.
  @visibleForTesting
  static void reset() {
    _loaded = false;
    current.value = Map<String, bool>.of(kServerFlagsFallback);
  }
}
