/// Bandwidth-aware START quality.
///
/// P8's [BandwidthMeter] only reacts after a stable 10s window, so a 4K
/// source could already be stuttering before the ladder noticed (2026-11-09
/// audit: a 17 GB 2160p file auto-played on a ~14 Mbps link and downshifted
/// only after playback had begun). This policy runs BEFORE the first open:
/// it turns a measured throughput (or a torrent file-size estimate) into the
/// highest rung that link can actually sustain, and steps the start source
/// down when it cannot.
///
/// Manual quality always bypasses this — the caller only asks while Auto is
/// selected.
library;

import '../../models/stream/stream_model.dart';
import 'bandwidth_meter.dart';
import 'quality_service.dart';

abstract final class StartupBandwidthPolicy {
  /// Container/protocol headroom on top of the nominal stream bitrate.
  static const double overhead = 1.3;

  /// Throughput (Mbps) each rung needs to play without stuttering.
  /// Higher than [BandwidthMeter.verdictFor] on purpose: that table decides
  /// a *sustained* ladder and is deliberately forgiving, while the start
  /// decision has no buffer yet.
  static const Map<QualityChoice, double> floorMbps = {
    QualityChoice.q480: 2.5,
    QualityChoice.q720: 6.0,
    QualityChoice.q1080: 12.0,
    QualityChoice.q1440: 22.0,
    QualityChoice.q2160: 39.0,
  };

  /// Highest rung [mbps] can sustain. Null when the link is unmeasured.
  static QualityChoice? affordableFor(double? mbps) {
    if (mbps == null || mbps <= 0) return null;
    QualityChoice best = QualityChoice.q480;
    for (final entry in floorMbps.entries) {
      if (mbps >= entry.value) best = entry.key;
    }
    return best;
  }

  /// Bitrate cap (bits/sec) for an HLS master on this link, or null when
  /// the link is unknown (leave mpv's own adaptation alone).
  static int? hlsCapBps(double? mbps) {
    final rung = affordableFor(mbps);
    if (rung == null) return null;
    final bitrate = rung.maxBitrate;
    if (bitrate == null) return null;
    return (bitrate * overhead).round();
  }

  /// The [StreamSource.quality] badge as a rung, or null when unknown.
  static QualityChoice? rungOf(StreamSource source) =>
      QualityChoice.fromBadge(source.quality);

  /// Estimated bitrate (bits/sec) of a source from its advertised size and
  /// the title's runtime. Torrent/HTTP releases very often state the size in
  /// the title (e.g. "… 2160p … [a11 17.0 GB]"), which is enough to tell a
  /// 4K remux from a 720p rip even before a byte is downloaded.
  static int? estimatedBitrateBps(StreamSource source, Duration? runtime) {
    final size = source.sizeBytes;
    if (size == null || runtime == null) return null;
    final seconds = runtime.inMilliseconds / 1000.0;
    if (seconds < 30) return null;
    return (size * 8 / seconds).round();
  }

  /// True when a measured link cannot feed [source] (by badge or by size).
  static bool cannotSustain({
    required StreamSource source,
    required double? mbps,
    Duration? runtime,
  }) {
    if (mbps == null || mbps <= 0) return false;
    final rung = rungOf(source);
    if (rung != null && rung != QualityChoice.auto) {
      final needed = floorMbps[rung];
      if (needed != null && mbps < needed) return true;
    }
    final estimated = estimatedBitrateBps(source, runtime);
    if (estimated != null && estimated > mbps * 1000000 * 1.05) return true;
    return false;
  }

  /// Picks the source to open at start.
  ///
  /// Returns [current] unless the measured link cannot sustain it, in which
  /// case the best candidate at/below the affordable rung is returned. When
  /// every candidate is above the affordable rung the smallest one wins (a
  /// 1080p file on a 3 Mbps link still beats a 4K one); the current source is
  /// kept only when it is the sole option.
  static StreamSource pickStart({
    required StreamSource current,
    required List<StreamSource> candidates,
    required double? mbps,
    Duration? runtime,
  }) {
    if (mbps == null || mbps <= 0) return current;
    if (!cannotSustain(source: current, mbps: mbps, runtime: runtime)) {
      return current;
    }
    final affordable = affordableFor(mbps);
    if (affordable == null) return current;

    StreamSource? best;
    int bestScore = -1;
    for (final c in candidates) {
      if (identical(c, current)) continue;
      final rung = rungOf(c);
      if (rung == null || rung == QualityChoice.auto) continue;
      if (rung.index > affordable.index) continue;
      // Prefer the highest affordable rung, then the same provider, then a
      // torrent with seeders (cheapest path to bytes already in the swarm).
      var score = rung.index * 100;
      if (c.addonName == current.addonName) score += 10;
      if ((c.seeders ?? 0) > 0) score += 5;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best != null) return best;

    // Nothing at/below the affordable rung: take the SMALLEST rung available
    // rather than opening a 4K file on a link that cannot feed it.
    StreamSource? smallest;
    int smallestRank = 99;
    for (final c in candidates) {
      final rung = rungOf(c);
      if (rung == null || rung == QualityChoice.auto) continue;
      if (rung.index < smallestRank) {
        smallestRank = rung.index;
        smallest = c;
      }
    }
    return smallest ?? current;
  }

  /// Caps an AUTO ladder target to what the live measurement sustains.
  ///
  /// P8's meter allows 2160p from ~20 Mbps, which is not enough for a real
  /// 4K bitrate; Auto must never step UP to a rung the link cannot feed.
  /// Manual picks never pass through here.
  static QualityChoice capAutoTarget(QualityChoice target, double? mbps) {
    final affordable = affordableFor(mbps);
    if (affordable == null) return target;
    if (target.index <= affordable.index) return target;
    return affordable;
  }

  /// Minimum swarm throughput (bytes/s) needed to feed [source] without
  /// stalling, from the size/runtime estimate. Null when unknown.
  static int? requiredSwarmBps(StreamSource source, Duration? runtime) {
    final estimated = estimatedBitrateBps(source, runtime);
    if (estimated == null) return null;
    return (estimated * overhead).round() ~/ 8;
  }

  /// Runtime ("119 min", "2h 3min", "1h 56m") → Duration. Null when unparsable.
  static Duration? parseRuntime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final text = raw.toLowerCase();
    final hourMatch = RegExp(r'(\d+)\s*h').firstMatch(text);
    final minMatch = RegExp(r'(\d+)\s*m').firstMatch(text);
    var minutes = 0;
    if (hourMatch != null) minutes += (int.tryParse(hourMatch.group(1)!) ?? 0) * 60;
    if (minMatch != null) minutes += int.tryParse(minMatch.group(1)!) ?? 0;
    if (minutes == 0) {
      final plain = int.tryParse(RegExp(r'\d+').firstMatch(text)?.group(0) ?? '');
      if (plain == null) return null;
      minutes = plain;
    }
    if (minutes <= 0) return null;
    return Duration(minutes: minutes);
  }
}
