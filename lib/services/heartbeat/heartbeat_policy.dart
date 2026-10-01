/// Phase L2 — the rules behind the fleet heartbeat.
///
/// Pure and I/O free so cadence, jitter, throttling and the consent
/// degradation can be tested without a device, a timer or a network.
library;

/// What the user is doing, coarse by design (never content, never titles).
enum Activity {
  idle('idle'),
  watching('watching'),
  listening('listening'),
  reading('reading'),
  downloading('downloading'),
  inRoom('in_room'),
  inVoice('in_voice');

  const Activity(this.rpcKey);

  /// Value sent to `device_heartbeat` — also the exact set the server's
  /// CHECK constraint accepts. Add a value here only with the migration.
  final String rpcKey;

  static Activity fromKey(String? key) =>
      Activity.values.firstWhere((a) => a.rpcKey == key, orElse: () => Activity.idle);
}

class HeartbeatPolicy {
  HeartbeatPolicy._();

  /// Server default; the `heartbeat_interval_s` config key overrides it.
  static const int defaultIntervalSeconds = 300;

  /// The server no-ops identical beats inside 60s, so anything faster is
  /// just wasted round trips.
  static const int minIntervalSeconds = 60;

  /// A presence older than an hour is meaningless — never go slower.
  static const int maxIntervalSeconds = 3600;

  /// How often we re-derive activity between presence beats.
  static const int activityProbeSeconds = 15;

  /// Minimum gap between two sends carrying the SAME activity.
  static const int sameActivityCooldownMs = 60000;

  /// Minimum gap between two sends carrying DIFFERENT activities (a real
  /// change the server will always accept).
  static const int changedActivityCooldownMs = 5000;

  /// A typo'd or hostile config value must neither spam nor stall us.
  static int clampInterval(int? rawSeconds) {
    if (rawSeconds == null || rawSeconds < minIntervalSeconds) {
      return defaultIntervalSeconds;
    }
    if (rawSeconds > maxIntervalSeconds) return maxIntervalSeconds;
    return rawSeconds;
  }

  /// Cadence ±10%. A whole fleet installing the same build would otherwise
  /// beat in lockstep the moment it lands.
  ///
  /// [jitterSample] is any integer (we take a time-derived value); only its
  /// magnitude matters, so tests can drive it exactly.
  static int nextDelayMs(int intervalSeconds, {required int jitterSample}) {
    final baseMs = clampInterval(intervalSeconds) * 1000;
    final spreadMs = baseMs ~/ 10;
    if (spreadMs == 0) return baseMs;
    final offset = (jitterSample.abs() % (spreadMs * 2 + 1)) - spreadMs;
    return baseMs + offset;
  }

  /// Consent OFF degrades to boot-time `last_seen_at` only: no beats at all.
  /// This is the designed privacy path, not an error state.
  static bool consentAllows(bool consent) => consent;

  /// Whether a pending (offline-captured) beat may go out now.
  ///
  /// It waits for connectivity AND for the same-activity server window —
  /// flushing into a 429-equivalent would only teach us nothing.
  static bool shouldFlush({
    required bool pending,
    required bool online,
    required int lastSentMs,
    required int nowMs,
    int cooldownMs = sameActivityCooldownMs,
  }) {
    if (!pending || !online) return false;
    if (nowMs - lastSentMs < cooldownMs) return false;
    return true;
  }

  /// A beat is worth sending when either the activity changed (send even
  /// inside the no-op window — the server accepts those) or the presence
  /// itself has gone stale.
  static bool beatDue({
    required Activity current,
    required Activity lastSent,
    required int lastSentMs,
    required int nowMs,
    bool force = false,
  }) {
    if (force) return true;
    final changed = current != lastSent;
    final cooldown =
        changed ? changedActivityCooldownMs : sameActivityCooldownMs;
    return nowMs - lastSentMs >= cooldown;
  }

  /// Parse an RPC reply defensively: anything unrecognised means "do not
  /// retry in a loop", not "crash" or "send again forever".
  static bool replyOk(Object? reply) =>
      reply is Map && reply['ok'] == true;
}
