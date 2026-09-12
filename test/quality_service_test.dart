import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/quality_service.dart';

StreamSource src(String badge) => StreamSource(
      name: 'S $badge',
      title: 'Movie $badge x264',
      url: 'https://cdn/x.mp4',
      addonName: 'test',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7: badges → choices', () {
    test('fromBadge maps 480..4K, rejects garbage', () {
      expect(QualityChoice.fromBadge('480p'), QualityChoice.q480);
      expect(QualityChoice.fromBadge('720p'), QualityChoice.q720);
      expect(QualityChoice.fromBadge('1080p'), QualityChoice.q1080);
      expect(QualityChoice.fromBadge('1440p'), QualityChoice.q1440);
      expect(QualityChoice.fromBadge('4K'), QualityChoice.q2160);
      expect(QualityChoice.fromBadge('CAM'), isNull);
      expect(QualityChoice.fromBadge(null), isNull);
    });

    test('bitrate caps ascend, auto uncapped', () {
      expect(QualityChoice.auto.maxBitrate, isNull);
      expect(QualityChoice.q480.maxBitrate, lessThan(QualityChoice.q720.maxBitrate!));
      expect(QualityChoice.q720.maxBitrate, lessThan(QualityChoice.q1080.maxBitrate!));
      expect(QualityChoice.q2160.maxBitrate, lessThanOrEqualTo(30000000));
    });
  });

  group('P7: optionsFor — only what the source has', () {
    test('HLS offers everything (master adapts)', () {
      final opts = QualityService.optionsFor(isHls: true, badges: const {});
      expect(opts, QualityChoice.values);
    });

    test('progressive offers Auto + present badges in order', () {
      final opts = QualityService.optionsFor(
        isHls: false,
        badges: const {'1080p', '480p'},
      );
      expect(opts, [QualityChoice.auto, QualityChoice.q480, QualityChoice.q1080]);
    });

    test('progressive with no badges → Auto only (never a dead choice)', () {
      final opts = QualityService.optionsFor(isHls: false, badges: const {'CAM'});
      expect(opts, [QualityChoice.auto]);
    });
  });

  group('P7: matching + urls + toast', () {
    test('matchProgressive finds first ranked match', () {
      final chain = [src('1080p'), src('720p')];
      expect(QualityService.matchProgressive(chain, QualityChoice.q720)?.quality, '720p');
      expect(QualityService.matchProgressive(chain, QualityChoice.q2160), isNull);
      expect(QualityService.matchProgressive(chain, QualityChoice.auto), isNull);
    });

    test('isHlsUrl ignores query/fragment, case-insensitive', () {
      expect(QualityService.isHlsUrl('https://c/a/MASTER.M3U8?tok=1'), isTrue);
      expect(QualityService.isHlsUrl('https://c/a/f.mp4'), isFalse);
      expect(QualityService.isHlsUrl(null), isFalse);
    });

    test('toast is easy english', () {
      expect(QualityService.toastFor(QualityChoice.auto), contains('Auto'));
      expect(QualityService.toastFor(QualityChoice.q720), 'Quality: 720p');
    });
  });

  group('P7: persistence (per-device, Auto default)', () {
    test('fresh prefs → auto; save → reload keeps', () async {
      SharedPreferences.setMockInitialValues({});
      final s = QualityService();
      expect(await s.load(), QualityChoice.auto);
      await s.save(QualityChoice.q1080);
      expect(s.current, QualityChoice.q1080);

      final s2 = QualityService();
      expect(await s2.load(), QualityChoice.q1080);
    });

    test('corrupt value → fail-soft auto', () async {
      SharedPreferences.setMockInitialValues(
          {QualityService.prefsKey: 'nope'});
      expect(await QualityService().load(), QualityChoice.auto);
    });
  });
}
