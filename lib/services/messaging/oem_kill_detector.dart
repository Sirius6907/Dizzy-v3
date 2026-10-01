import 'package:shared_preferences/shared_preferences.dart';

/// Phase K4 — OEM battery-killer detector.
///
/// Plan §2f: "detect OEM-battery-kill (heartbeat gaps) → guide user to
/// disable optimization for Dizzy". Heartbeats land in Phase L, so the
/// signal available right now is the cheaper one: the app was alive very
/// recently, went away without a clean shutdown, and still had unsent
/// messages waiting — that is a kill, not a user pressing Home.
class OemKillDetector {
  OemKillDetector._();

  static const String kLastAliveKey = 'oem_last_alive_ms';
  static const String kGuideShownKey = 'oem_battery_guide_shown';

  /// A normal cold start minutes-to-hours after the last run is ordinary
  /// user behaviour, not evidence of anything.
  static const int minGapMs = 30 * 1000;
  static const int maxGapMs = 30 * 60 * 1000;

  /// Pure decision, tested. Suggest only when all three hold:
  ///  - there is something we lost or could lose (pending outbox),
  ///  - the app went away recently (a kill, not a session the user ended),
  ///  - and it has not been shown recently (never nag).
  static bool shouldSuggest({required int gapMs, required int pendingCount}) {
    if (pendingCount <= 0) return false;
    if (gapMs < minGapMs || gapMs > maxGapMs) return false;
    return true;
  }

  static Future<void> markAlive({int? nowMs}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      kLastAliveKey,
      nowMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<int> lastAlive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(kLastAliveKey) ?? 0;
  }

  /// Call once at boot. Returns true when the Easy English battery guide
  /// should be offered this session (and remembers that it was).
  static Future<bool> considerBoot({
    required int pendingCount,
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final last = await lastAlive();
    if (last <= 0) return false;
    if (!shouldSuggest(gapMs: now - last, pendingCount: pendingCount)) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kGuideShownKey) ?? false) return false;
    await prefs.setBool(kGuideShownKey, true);
    return true;
  }

  /// Test seam: clear the persisted "already shown" latch.
  static Future<void> resetShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kGuideShownKey);
  }
}
