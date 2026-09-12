/// P8 — Auto quality by REAL internet speed (480p floor, 4K cap).
///
/// No speed-test pings, no extra traffic: the meter watches the demuxer's
/// cache-fill rate (how fast buffered seconds grow vs wall-clock) and
/// multiplies by the current rendition's assumed bitrate. Seeks drain the
/// buffer — those samples are discarded, never measured.
///
/// Policy: <3 Mbps → 480p • 3–8 → 720p • 8–20 → 1080p • 20+ → source max.
/// A target only fires on a stable 10s window (no flip-flopping), and the
/// player applies it at a keyframe via resume-reopen (mpv lands on keyframes).
/// Data Saver ON caps everything at 720p, always.
library;

import 'quality_service.dart';

/// One cache-fill observation.
class _Sample {
  final DateTime at;
  final double mbps;
  _Sample(this.at, this.mbps);
}

class BandwidthMeter {
  /// Seconds of stable history required before a target fires.
  static const stableWindowSec = 10;

  /// Minimum samples inside the window (guards sparse tickers).
  static const minSamples = 3;

  /// Assumed bitrate when the current quality is unknown (mid 1080p).
  static const fallbackBitrateBps = 6000000;

  final List<_Sample> _samples = [];
  double? _lastBufferedAheadSec;

  /// Feed the meter. Call every ~2s while playing (never while seeking or
  /// paused — the caller guards that; double-guarded here via drop detect).
  ///
  /// [bufferedAheadSec] = buffered position minus play position, in seconds.
  /// [assumedBitrateBps] = current rendition's bitrate (badge table).
  void addSample({
    required DateTime at,
    required double bufferedAheadSec,
    required int assumedBitrateBps,
  }) {
    final prev = _lastBufferedAheadSec;
    _lastBufferedAheadSec = bufferedAheadSec;
    if (_samples.isEmpty) {
      _prune(at);
      _samples.add(_Sample(at, -1)); // anchor, no rate yet
      return;
    }
    if (prev == null) return;
    final dtWall = at.difference(_samples.last.at).inMilliseconds / 1000.0;
    if (dtWall <= 0) return;
    final dBuf = bufferedAheadSec - prev;
    if (dBuf < 0) {
      // Buffer drained (seek / stall) — not a speed signal. Re-anchor.
      _samples.clear();
      _samples.add(_Sample(at, -1));
      return;
    }
    final fillRatio = dBuf / dtWall;
    final mbps = fillRatio * assumedBitrateBps / 1000000.0;
    _samples.add(_Sample(at, mbps.clamp(0.0, 1000.0)));
    _prune(at);
  }

  void _prune(DateTime now) {
    _samples.removeWhere(
        (s) => now.difference(s.at).inSeconds > stableWindowSec + 4);
    if (_samples.length > 40) {
      _samples.removeRange(0, _samples.length - 40);
    }
  }

  /// Median of valid samples inside the stable window. Null when thin.
  double? get estimatedMbps {
    final vals = [
      for (final s in _samples)
        if (s.mbps >= 0) s.mbps,
    ];
    if (vals.length < minSamples) return null;
    vals.sort();
    return vals[vals.length ~/ 2];
  }

  /// True when the window is full enough to trust (span ≥ 10s + samples).
  bool get isStable {
    if (_samples.length < minSamples + 1) return false; // +1 anchor
    final span =
        _samples.last.at.difference(_samples.first.at).inSeconds;
    return span >= stableWindowSec && estimatedMbps != null;
  }

  /// Raw policy mapping (no caps). Pure — unit-tested at boundaries.
  static QualityChoice verdictFor(double mbps) {
    if (mbps < 3) return QualityChoice.q480;
    if (mbps < 8) return QualityChoice.q720;
    if (mbps < 20) return QualityChoice.q1080;
    return QualityChoice.q2160;
  }

  /// Fires ONLY on a stable window (else null → keep current). Data Saver
  /// caps the verdict at 720p. Auto mode only — manual choice bypasses.
  QualityChoice? stableTarget({required bool dataSaver}) {
    if (!isStable) return null;
    var target = verdictFor(estimatedMbps!);
    if (dataSaver && target.index > QualityChoice.q720.index) {
      target = QualityChoice.q720;
    }
    return target;
  }

  /// New video / new source: forget everything (stale speeds must not
  /// downshift a fresh fast source).
  void reset() {
    _samples.clear();
    _lastBufferedAheadSec = null;
  }
}
