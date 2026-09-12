import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/bandwidth_meter.dart';
import 'package:dizzy/services/player/quality_service.dart';

/// Feed [n] steady samples: buffer grows [bufPerTick]s per 1s tick while
/// playing a rendition assumed at [bitrateBps].
BandwidthMeter feedSteady(
  BandwidthMeter m,
  DateTime t0, {
  required int ticks,
  required double bufPerTick,
  required int bitrateBps,
}) {
  var buffered = 20.0;
  for (var i = 0; i < ticks; i++) {
    buffered += bufPerTick;
    m.addSample(
      at: t0.add(Duration(seconds: i)),
      bufferedAheadSec: buffered,
      assumedBitrateBps: bitrateBps,
    );
  }
  return m;
}

void main() {
  group('P8: verdict policy boundaries', () {
    test('2.9→480, 3→720, 7.9→720, 8→1080, 19.9→1080, 20→2160', () {
      expect(BandwidthMeter.verdictFor(2.9), QualityChoice.q480);
      expect(BandwidthMeter.verdictFor(3.0), QualityChoice.q720);
      expect(BandwidthMeter.verdictFor(7.9), QualityChoice.q720);
      expect(BandwidthMeter.verdictFor(8.0), QualityChoice.q1080);
      expect(BandwidthMeter.verdictFor(19.9), QualityChoice.q1080);
      expect(BandwidthMeter.verdictFor(20.0), QualityChoice.q2160);
      expect(BandwidthMeter.verdictFor(200.0), QualityChoice.q2160);
    });
  });

  group('P8: stability gate', () {
    test('thin/short history → null (no flip-flop)', () {
      final m = BandwidthMeter();
      final t0 = DateTime(2026, 1, 1);
      feedSteady(m, t0, ticks: 4, bufPerTick: 2.0, bitrateBps: 6000000);
      expect(m.isStable, isFalse);
      expect(m.stableTarget(dataSaver: false), isNull);
    });

    test('10s+ steady fast → 2160; steady slow → 480', () {
      final t0 = DateTime(2026, 1, 1);
      // 4s of buffer per 1s wall × 6 Mbps ≈ 24 Mbps → 2160p.
      final fast = feedSteady(BandwidthMeter(), t0,
          ticks: 12, bufPerTick: 4.0, bitrateBps: 6000000);
      expect(fast.isStable, isTrue);
      expect(fast.estimatedMbps, greaterThan(20));
      expect(fast.stableTarget(dataSaver: false), QualityChoice.q2160);

      // 0.3s per 1s × 6 Mbps ≈ 1.8 Mbps → 480p.
      final slow = feedSteady(BandwidthMeter(), t0,
          ticks: 12, bufPerTick: 0.3, bitrateBps: 6000000);
      expect(slow.stableTarget(dataSaver: false), QualityChoice.q480);
    });

    test('seek drain discards history (re-anchors, no false downshift)', () {
      final m = BandwidthMeter();
      final t0 = DateTime(2026, 1, 1);
      feedSteady(m, t0, ticks: 12, bufPerTick: 4.0, bitrateBps: 6000000);
      expect(m.isStable, isTrue);
      // User seeks: buffered collapses 60 → 5.
      m.addSample(
        at: t0.add(const Duration(seconds: 12)),
        bufferedAheadSec: 5.0,
        assumedBitrateBps: 6000000,
      );
      expect(m.isStable, isFalse);
      expect(m.stableTarget(dataSaver: false), isNull);
    });

    test('data saver caps at 720p even on fiber', () {
      final m = feedSteady(BandwidthMeter(), DateTime(2026, 1, 1),
          ticks: 12, bufPerTick: 4.0, bitrateBps: 6000000);
      expect(m.stableTarget(dataSaver: true), QualityChoice.q720);
    });

    test('reset() forgets stale speeds', () {
      final m = feedSteady(BandwidthMeter(), DateTime(2026, 1, 1),
          ticks: 12, bufPerTick: 4.0, bitrateBps: 6000000);
      m.reset();
      expect(m.isStable, isFalse);
      expect(m.estimatedMbps, isNull);
    });
  });

  group('P8: weak-device AV1 dodge', () {
    StreamSource s(String badge, String title) => StreamSource(
          name: 'S',
          title: '$title $badge',
          url: 'https://cdn/x.mp4',
          addonName: 'test',
        );
    test('avoidAv1 skips AV1 file, falls back when only AV1', () {
      final h264 = s('720p', 'Show 720p x264');
      final av1 = s('720p', 'Show 720p AV1');
      expect(
        QualityService.matchProgressive([av1, h264], QualityChoice.q720,
            avoidAv1: true),
        same(h264),
      );
      expect(
        QualityService.matchProgressive([av1], QualityChoice.q720,
            avoidAv1: true),
        same(av1),
      );
      // Default path unchanged (no dodge).
      expect(
        QualityService.matchProgressive([av1, h264], QualityChoice.q720),
        same(av1),
      );
    });
  });
}
