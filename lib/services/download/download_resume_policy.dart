import 'package:connectivity_plus/connectivity_plus.dart';

/// Phase K2 — pure download policy: Wi-Fi-only gating + retry backoff.
///
/// Everything here is I/O free so the rules that decide whether a download
/// may run right now can be pinned by tests instead of by device QA.
class DownloadResumePolicy {
  DownloadResumePolicy._();

  /// Retries after a failed download before we stop and ask the user.
  static const int maxAttempts = 5;

  /// Cap on a single retry wait: a dead host should still get another shot
  /// every few minutes rather than drifting out to hours.
  static const int maxBackoffMs = 15 * 60 * 1000;

  /// Phase K2 "Wi-Fi only": cellular counts as not-wifi, and an empty or
  /// unknown result list is treated as cellular too (fail towards the
  /// user's data plan, never against it).
  static bool isWifi(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return true;
    if (results.contains(ConnectivityResult.ethernet)) return true;
    return false;
  }

  static bool isOffline(List<ConnectivityResult> results) =>
      results.isEmpty || results.every((r) => r == ConnectivityResult.none);

  /// True when downloads must be held back on this connection.
  static bool blockOn({
    required bool wifiOnly,
    required List<ConnectivityResult> results,
  }) {
    if (!wifiOnly) return false;
    if (isOffline(results)) return false; // the offline path already pauses
    return !isWifi(results);
  }

  /// 10s → 20s → 40s … capped, with a little jitter so a whole fleet of
  /// clients does not retry in lockstep.
  static int backoffMs(int attempts, {int? jitterSample}) {
    if (attempts <= 0) return 10000;
    final exp = attempts > 20 ? 20 : attempts;
    var ms = 10000 * (1 << exp);
    if (ms > maxBackoffMs || ms <= 0) ms = maxBackoffMs;
    final jitter = (jitterSample ?? 5000) / 10000.0;
    return (ms * (0.9 + 0.2 * jitter)).round();
  }

  static bool isExhausted(int attempts) => attempts >= maxAttempts;

  static bool attemptDue({
    required int attempts,
    required int lastAttemptMs,
    required int nowMs,
  }) {
    if (isExhausted(attempts)) return false;
    if (lastAttemptMs <= 0) return true;
    return nowMs - lastAttemptMs >= backoffMs(attempts);
  }

  /// Plan §2f: "WorkManager retry for failed/incomplete when back online".
  /// The app already has a connectivity watcher, so the retry fires from
  /// there — but only the *first* one may be immediate. A task that fails
  /// again goes back to its backoff window, so a flapping connection cannot
  /// turn into a retry storm.
  static bool retryOnReconnect({
    required bool justCameBackOnline,
    required bool hadConnectivity,
    required int attempts,
    required int lastAttemptMs,
    required int nowMs,
  }) {
    if (!justCameBackOnline || !hadConnectivity) return false;
    if (isExhausted(attempts)) return false;
    if (attempts == 0) return true;
    return attemptDue(
      attempts: attempts,
      lastAttemptMs: lastAttemptMs,
      nowMs: nowMs,
    );
  }
}
