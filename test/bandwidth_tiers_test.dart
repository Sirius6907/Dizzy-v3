import 'package:dizzy/services/player/bandwidth_meter.dart';
import 'package:dizzy/services/player/quality_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// P18: bandwidth tiers — mid-ladder rungs end-to-end (the existing suite
/// pins 480/2160 extremes + saver cap at the top; these pin 720/1080 and
/// the below-range guard). Calibration: bufPerTick × bitrate ≈ Mbps.
BandwidthMeter feed(BandwidthMeter m, double bufPerTick, int bitrateBps) {
  var buffered = 20.0;
  final t0 = DateTime(2026, 1, 1);
  for (var i = 0; i < 12; i++) {
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
  group('P18: bandwidth tiers', () {
    test('steady ~6 Mbps settles on 720p', () {
      final m = feed(BandwidthMeter(), 1.0, 6000000);
      expect(m.isStable, isTrue);
      expect(m.stableTarget(dataSaver: false), QualityChoice.q720);
    });

    test('steady ~12 Mbps settles on 1080p; saver pulls it to 720p', () {
      final m = feed(BandwidthMeter(), 2.0, 6000000);
      expect(m.isStable, isTrue);
      expect(m.stableTarget(dataSaver: false), QualityChoice.q1080);
      expect(m.stableTarget(dataSaver: true), QualityChoice.q720);
    });

    test('zero/negative/epsilon-below readings stay on 480p', () {
      expect(BandwidthMeter.verdictFor(0), QualityChoice.q480);
      expect(BandwidthMeter.verdictFor(-5), QualityChoice.q480);
      expect(BandwidthMeter.verdictFor(2.999), QualityChoice.q480);
      expect(BandwidthMeter.verdictFor(7.999), QualityChoice.q720);
      expect(BandwidthMeter.verdictFor(19.999), QualityChoice.q1080);
    });
  });
}
