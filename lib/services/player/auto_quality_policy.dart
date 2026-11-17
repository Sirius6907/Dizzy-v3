/// Which sources the AUTO quality ladder is allowed to re-open.
///
/// The auto ladder walks *rungs* (480p → 2160p) and re-opens the video at a
/// different rung. That only makes sense for a source that actually has a
/// ladder.
///
/// A torrent has exactly ONE file. "Lowering the quality" of a torrent means
/// picking a different encode of the same title — a different SOURCE, not a
/// different rendition of the current one. Swapping it mid-playback tears
/// down a stream that is already playing and re-enters the swarm from zero,
/// so a slow swarm would replace a working 1080p playback with a stalled
/// re-download of the same episode.
///
/// The torrent case is already handled where it belongs, and both places
/// decide BEFORE the player opens anything:
///   * [StartupBandwidthPolicy.pickStart] — the start source is chosen at a
///     rung the measured link can sustain.
///   * the player's torrent failure path — the swarm's measured speed caps
///     the NEXT source after a dead/starved torrent.
///
/// v1.3.2 had the same rule ("auto quality applies to non-torrent sources")
/// and lost no playback to it.
library;

import '../../models/stream/stream_model.dart';

abstract final class AutoQualityPolicy {
  /// True when [source] may be re-opened at another quality rung.
  ///
  /// False for torrents and for magnet URLs: both are single-file sources.
  static bool supportsQualitySwitch(StreamSource source) {
    if (source.isTorrent) return false;
    final url = source.url ?? '';
    if (url.startsWith('magnet:')) return false;
    return true;
  }
}
