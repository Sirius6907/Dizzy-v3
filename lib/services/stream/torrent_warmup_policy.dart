/// When a torrent stream is safe to hand to the player.
///
/// TorrServer downloads on demand: the first player request can sit 45s+
/// with zero bytes while the swarm warms up, and mpv then reports
/// "Failed to open". Waiting for a small initial buffer fixes that without
/// stalling forever on a dead swarm.
abstract final class TorrentWarmupPolicy {
  static const int targetLoadedBytes = 2 * 1024 * 1024;

  /// Never block the player longer than this; a slow swarm still gets a try.
  static const Duration maxWait = Duration(seconds: 12);

  /// Engine preload means the requested file's head is already being filled.
  static const Duration preloadGrace = Duration(seconds: 2);

  static bool isReady({
    required int loadedBytes,
    required int preloadedBytes,
    required Duration elapsed,
  }) {
    if (elapsed >= maxWait) return true;
    if (loadedBytes >= targetLoadedBytes) return true;
    if (preloadedBytes > 0 && elapsed >= preloadGrace) return true;
    return false;
  }
}
