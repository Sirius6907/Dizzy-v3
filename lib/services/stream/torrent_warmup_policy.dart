/// When a torrent is safe to hand to the player — and when a swarm is
/// hopeless and must be rejected BEFORE mpv ever opens it.
///
/// History (2026-11-09 audit): the old policy declared "ready" after a 2s
/// preload grace even with **zero** bytes buffered, and returned "ready" at
/// the 12s ceiling no matter what. mpv then opened the localhost stream and
/// sat on a black frame for 94s while TorrServer trickled ~4 KB/s. Nothing
/// could fail over because mpv reported "buffering", not an error.
///
/// The rules below are grounded in live TorrServer counters
/// (`loaded_size`, `active_peers`, `download_speed`):
///  - ready   → 2 MB buffered, or ≥512 KB and a genuinely feeding swarm;
///  - hopeless→ no *active* peer after 8s, no byte growth for 9s, or still
///              under the floor at the 14s ceiling;
///  - warming → everything else (keep polling).
enum TorrentReadiness { warming, ready, hopeless }

abstract final class TorrentWarmupPolicy {
  /// Bytes that make a start worth trying (≈2-3s of a 6 Mbps stream).
  static const int targetLoadedBytes = 2 * 1024 * 1024;

  /// Absolute floor before mpv may open: below this the demuxer just blocks.
  static const int minimumStartBytes = 512 * 1024;

  /// Bytes/s meaning "the swarm is actually feeding us" (≈9.6 Mbps).
  static const int healthySpeedBps = 1200 * 1024;

  /// Hard ceiling on the wait. The old "ready anyway at 12s" is gone; a
  /// swarm that cannot deliver [minimumStartBytes] by then is hopeless.
  static const Duration maxWait = Duration(seconds: 14);

  /// No *active* peers this long → dead swarm. DHT can still list thousands
  /// of `total_peers`, which is exactly how a starved torrent looked alive.
  static const Duration peerGrace = Duration(seconds: 8);

  /// No byte growth for this long → starved, even when peers are connected.
  static const Duration noByteGrace = Duration(seconds: 9);

  static TorrentReadiness evaluate({
    required int loadedBytes,
    required int activePeers,
    required int speedBps,
    required Duration sinceBytesGrew,
    required Duration elapsed,
    int servedBytes = 0,
  }) {
    // TorrServer only serves its HTTP reader when pieces are actually
    // available, so bytes delivered to a live reader are the strongest proof
    // the swarm works. `loaded_size` is a cache counter that can lag (or stay
    // at 0 for a file served straight from disk), and judging on it alone is
    // what rejected healthy torrents.
    final buffered = loadedBytes > servedBytes ? loadedBytes : servedBytes;

    // A real buffer wins regardless of the clock.
    if (buffered >= targetLoadedBytes) return TorrentReadiness.ready;

    // Moving but not there yet: accept a slow-but-sustainable swarm once it
    // has proven a minimum of data (mpv can start and keep filling).
    if (buffered >= minimumStartBytes &&
        speedBps >= healthySpeedBps &&
        elapsed >= const Duration(seconds: 3)) {
      return TorrentReadiness.ready;
    }

    // No active peer, no throughput AND a frozen buffer after the grace →
    // dead swarm. Peers alone can never prove death: TorrServer reports
    // `active_peers = 0` whenever no transfer is in flight.
    if (elapsed >= peerGrace &&
        activePeers <= 0 &&
        speedBps <= 0 &&
        sinceBytesGrew >= peerGrace &&
        buffered < minimumStartBytes) {
      return TorrentReadiness.hopeless;
    }

    // Peers present but nothing arrives → starved swarm. The elapsed floor
    // keeps the first seconds (before any piece completes) from looking
    // frozen.
    if (elapsed >= noByteGrace &&
        sinceBytesGrew >= noByteGrace &&
        buffered < minimumStartBytes) {
      return TorrentReadiness.hopeless;
    }

    // Hard ceiling: never hand a starved stream to the player.
    if (elapsed >= maxWait) {
      return buffered >= minimumStartBytes
          ? TorrentReadiness.ready
          : TorrentReadiness.hopeless;
    }

    return TorrentReadiness.warming;
  }

  /// Convenience wrapper for callers that only care about the boolean.
  static bool isReady({
    required int loadedBytes,
    required int activePeers,
    required int speedBps,
    required Duration sinceBytesGrew,
    required Duration elapsed,
    int servedBytes = 0,
  }) =>
      evaluate(
        loadedBytes: loadedBytes,
        activePeers: activePeers,
        speedBps: speedBps,
        sinceBytesGrew: sinceBytesGrew,
        elapsed: elapsed,
        servedBytes: servedBytes,
      ) ==
      TorrentReadiness.ready;

  /// Minimum throughput (bytes/s) a swarm must sustain for a file whose
  /// bitrate is [requiredBps]. Used to reject a torrent that *is* downloading
  /// but cannot possibly feed this file (4K remux on a 2 Mbps swarm).
  static int minimumSustainableBps(int requiredBps) {
    if (requiredBps <= 0) return 0;
    // 35% headroom: mpv reads in bursts and the cache must refill.
    return (requiredBps * 1.35).round();
  }
}
