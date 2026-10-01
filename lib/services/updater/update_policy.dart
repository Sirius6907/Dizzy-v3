/// Phase I1 — rollout + channel gates. Pure, no I/O, fully testable.
///
/// Plan §2d: "server rollout gate: bucket = hash(hwid) % 100 < rollout_percent
/// else silent skip" and "channel gate: beta opt-in sees prereleases, stable
/// only stable".
///
/// The bucket is computed from the STABLE hwid (Phase H) so a device stays in
/// (or out of) the same rollout bucket across reinstalls — a fresh random id
/// would reshuffle every bucket on every reinstall and make staged rollouts
/// meaningless.
class UpdatePolicy {
  static const String stableChannel = 'stable';
  static const String betaChannel = 'beta';

  /// Server keys (remote_config) read by the app.
  static const String keyRolloutPercent = 'rollout_percent';
  static const String keyUpdateChannel = 'update_channel';

  /// FNV-1a 32-bit. Explicit (not String.hashCode) so the bucket is stable
  /// across VM versions and isolate runs.
  static int hashBucket(String stableHwid) {
    var hash = 0x811c9dc5;
    final units = stableHwid.codeUnits;
    for (final u in units) {
      hash ^= u;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash % 100;
  }

  /// Clamps the raw server value into a usable 0..100 percent.
  /// Missing/garbage → 100 (offer to everyone) so a bad key can never hide
  /// updates from users.
  static int parseRolloutPercent(Object? raw) {
    if (raw == null) return 100;
    final n = raw is num ? raw.toInt() : int.tryParse(raw.toString().trim());
    if (n == null) return 100;
    return n.clamp(0, 100);
  }

  /// Normalises a raw channel value. Anything unknown → stable (safe default:
  /// prereleases are never shown by accident).
  static String normalizeChannel(Object? raw) {
    final v = (raw?.toString() ?? '').trim().toLowerCase();
    return v == betaChannel ? betaChannel : stableChannel;
  }

  /// True when this device's bucket is inside the staged rollout.
  static bool inRollout({
    required String stableHwid,
    required int rolloutPercent,
  }) {
    if (rolloutPercent >= 100) return true;
    if (rolloutPercent <= 0) return false;
    return hashBucket(stableHwid) < rolloutPercent;
  }

  /// Stable channel never sees a prerelease; beta sees everything.
  static bool channelAllows({
    required String channel,
    required bool isPrerelease,
  }) {
    if (!isPrerelease) return true;
    return normalizeChannel(channel) == betaChannel;
  }

  /// Full gate: rollout bucket AND channel must both allow the offer.
  static bool shouldOffer({
    required String stableHwid,
    required int rolloutPercent,
    required String channel,
    required bool isPrerelease,
  }) {
    return inRollout(stableHwid: stableHwid, rolloutPercent: rolloutPercent) &&
        channelAllows(channel: channel, isPrerelease: isPrerelease);
  }
}
