import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/quality_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// P18: rendition policy — the quality menu offers exactly what the video
/// can play, and switching lands on the first matching file.
StreamSource s(String badge, String title) => StreamSource(
      name: 'S',
      title: '$title $badge',
      url: 'https://cdn/x.mp4',
      addonName: 'test',
    );

void main() {
  group('P18: rendition policy', () {
    test('HLS offers the full ladder, Auto first', () {
      final opts = QualityService.optionsFor(isHls: true, badges: const {});
      expect(opts.first, QualityChoice.auto);
      expect(
          opts.toSet(),
          containsAll([
            QualityChoice.q480,
            QualityChoice.q720,
            QualityChoice.q1080,
            QualityChoice.q1440,
            QualityChoice.q2160,
          ]));
    });

    test('progressive offers only badges present in files', () {
      final opts = QualityService.optionsFor(
          isHls: false, badges: const {'720p', '1080p'});
      expect(opts.first, QualityChoice.auto);
      expect(opts, contains(QualityChoice.q720));
      expect(opts, contains(QualityChoice.q1080));
      expect(opts, isNot(contains(QualityChoice.q480)));
      expect(opts, isNot(contains(QualityChoice.q2160)));
    });

    test('ladder labels union with badges (no rung left behind)', () {
      final opts = QualityService.optionsFor(
        isHls: false,
        badges: const {'720p'},
        renditionLabels: const {'1080p'},
      );
      expect(opts, contains(QualityChoice.q720));
      expect(opts, contains(QualityChoice.q1080));
    });

    test('switch lands on first matching file, null when absent', () {
      final a = s('720p', 'Show A');
      final b = s('720p', 'Show B');
      final hd = s('1080p', 'Show C');
      expect(QualityService.matchProgressive([a, b, hd], QualityChoice.q720),
          same(a));
      expect(
          QualityService.matchProgressive([a, b], QualityChoice.q2160), isNull);
      expect(QualityService.matchProgressive([a], QualityChoice.auto), isNull);
    });

    test('unknown badges never surface as options', () {
      final opts = QualityService.optionsFor(
          isHls: false, badges: const {'CAM', 'HDTS', ''});
      expect(opts, [QualityChoice.auto]);
    });
  });
}
