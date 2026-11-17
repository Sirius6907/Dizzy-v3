import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/quality_service.dart';
import 'package:dizzy/services/player/startup_bandwidth_policy.dart';

/// The badge is derived from the title text, so each helper builds a title
/// the real parsers understand (2160p/4K, 1080p, 720p).
StreamSource src({
  String quality = '1080p',
  String addon = 'x',
  String? title,
}) =>
    StreamSource(
      name: quality,
      title: title ?? 'Movie 2026 $quality',
      addonName: addon,
      url: 'https://example.com/$quality',
    );

void main() {
  group('affordableFor', () {
    test('slow links never reach 4K', () {
      expect(StartupBandwidthPolicy.affordableFor(14.0), QualityChoice.q1080);
      expect(StartupBandwidthPolicy.affordableFor(38.9), QualityChoice.q1440);
      expect(StartupBandwidthPolicy.affordableFor(3.0), QualityChoice.q480);
      expect(StartupBandwidthPolicy.affordableFor(8.0), QualityChoice.q720);
    });

    test('unknown measurement means no decision', () {
      expect(StartupBandwidthPolicy.affordableFor(null), isNull);
      expect(StartupBandwidthPolicy.affordableFor(0), isNull);
    });

    test('fast links allow 4K', () {
      expect(StartupBandwidthPolicy.affordableFor(40.0), QualityChoice.q2160);
      expect(StartupBandwidthPolicy.affordableFor(200.0), QualityChoice.q2160);
    });
  });

  group('cannotSustain', () {
    test('4K badge on a 14 Mbps link', () {
      expect(
        StartupBandwidthPolicy.cannotSustain(
          source: src(quality: '2160p'),
          mbps: 14,
        ),
        isTrue,
      );
    });

    test('1080p badge on a 14 Mbps link', () {
      expect(
        StartupBandwidthPolicy.cannotSustain(
          source: src(quality: '1080p'),
          mbps: 14,
        ),
        isFalse,
      );
    });

    test('size/runtime estimate flags a 17 GB 2h file', () {
      final big = src(
        quality: '2160p',
        title: 'Movie.2026.2160p.WEB-DL [17.0 GB]',
      );
      expect(
        StartupBandwidthPolicy.cannotSustain(
          source: big,
          mbps: 14,
          runtime: const Duration(minutes: 119),
        ),
        isTrue,
      );
    });
  });

  group('pickStart', () {
    final fourk = src(quality: '2160p', addon: 'a');
    final hd = src(quality: '1080p', addon: 'b');
    final sd = src(quality: '720p', addon: 'c');

    test('steps a 4K start down to the affordable rung', () {
      final picked = StartupBandwidthPolicy.pickStart(
        current: fourk,
        candidates: [fourk, hd, sd],
        mbps: 14,
      );
      expect(picked.quality, '1080p');
    });

    test('keeps the current source when the link can feed it', () {
      final picked = StartupBandwidthPolicy.pickStart(
        current: hd,
        candidates: [fourk, hd, sd],
        mbps: 14,
      );
      expect(identical(picked, hd), isTrue);
    });

    test('nothing below the rung → pick the smallest available', () {
      final picked = StartupBandwidthPolicy.pickStart(
        current: fourk,
        candidates: [fourk, hd],
        mbps: 2,
      );
      // 1080p is still above 480p, but it is the smallest real option and
      // strictly better than opening the 4K file.
      expect(identical(picked, hd), isTrue);
    });

    test('only-4K title keeps playing (availability beats policy)', () {
      final picked = StartupBandwidthPolicy.pickStart(
        current: fourk,
        candidates: [fourk],
        mbps: 5,
      );
      expect(identical(picked, fourk), isTrue);
    });

    test('no measurement leaves the start untouched', () {
      final picked = StartupBandwidthPolicy.pickStart(
        current: fourk,
        candidates: [fourk, hd],
        mbps: null,
      );
      expect(identical(picked, fourk), isTrue);
    });
  });

  test('HLS cap follows the affordable rung', () {
    expect(StartupBandwidthPolicy.hlsCapBps(14), 7800000); // 1080p × 1.3
    expect(StartupBandwidthPolicy.hlsCapBps(null), isNull);
  });

  test('auto ladder never ups to a rung the link cannot feed', () {
    expect(
      StartupBandwidthPolicy.capAutoTarget(QualityChoice.q2160, 14),
      QualityChoice.q1080,
    );
    expect(
      StartupBandwidthPolicy.capAutoTarget(QualityChoice.q720, 14),
      QualityChoice.q720,
    );
  });

  group('parseRuntime', () {
    test('minutes', () {
      expect(
        StartupBandwidthPolicy.parseRuntime('119 min'),
        const Duration(minutes: 119),
      );
    });
    test('h + m', () {
      expect(
        StartupBandwidthPolicy.parseRuntime('2h 3min'),
        const Duration(minutes: 123),
      );
    });
    test('plain number', () {
      expect(
        StartupBandwidthPolicy.parseRuntime('98'),
        const Duration(minutes: 98),
      );
    });
    test('garbage', () {
      expect(StartupBandwidthPolicy.parseRuntime(null), isNull);
      expect(StartupBandwidthPolicy.parseRuntime('—'), isNull);
    });
  });
}
