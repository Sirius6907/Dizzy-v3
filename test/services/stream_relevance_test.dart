import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/stream/stream_relevance.dart';

StreamSource _src(String title, {String addon = 'test'}) =>
    StreamSource(title: title, url: 'https://example.com/a.mkv', addonName: addon);

void main() {
  group('StreamRelevance', () {
    test('keeps a source whose year and episode both match', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Nocturne (2026) - S01E02 - For Such a Time as This [WEBDL-1080p]'),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 2,
      );
      expect(ok, isTrue);
    });

    test('rejects a different show that only shares the title word', () {
      // The exact wrong file auto-played on the emulator for "Nocturne (2026)".
      final ok = StreamRelevance.isRelevant(
        source: _src(
          'Castlevania Nocturne (2023) S01E01 A Common Enemy in Evil '
          '(1080p BDRip x265 10bit AC3 5.1 - Goki)[TAoE].mkv',
        ),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 1,
      );
      expect(ok, isFalse);
    });

    test('rejects a file for the wrong episode', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Nocturne (2026) - S01E01 - Lazarus Come Forth! [WEBDL-2160p]'),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 2,
      );
      expect(ok, isFalse);
    });

    test('rejects a file for the wrong season', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Nocturne S02E01 1080p WEB-DL'),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 1,
      );
      expect(ok, isFalse);
    });

    test('keeps a multi-episode file that contains the request', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Nocturne S01E01-E03 1080p WEB-DL'),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 2,
      );
      expect(ok, isTrue);
    });

    test('keeps a season pack with no episode marker', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Nocturne S01 1080p WEB-DL'),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 4,
      );
      expect(ok, isTrue);
    });

    test('keeps a source with no year or episode evidence', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Nocturne 1080p WEB-DL'),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 2,
      );
      expect(ok, isTrue);
    });

    test('does not read 1080p or 1920x1080 as a year', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Nocturne 1920x1080 1080p WEB-DL'),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 2,
      );
      expect(ok, isTrue);
    });

    test('ignores a number that is part of the requested title', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Blade Runner 2049 (2017) 1080p BluRay'),
        title: 'Blade Runner 2049',
        year: 2017,
      );
      expect(ok, isTrue);
    });

    test('accepts a season spanning several years when one matches', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Nocturne (2024-2026) S01E02 1080p'),
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 2,
      );
      expect(ok, isTrue);
    });

    test('rejects a different show even when the app has no year', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Castlevania Nocturne (2023) S01E01'),
        title: 'Nocturne',
        season: 1,
        episode: 1,
      );
      expect(ok, isFalse);
    });

    test('accepts an article or language prefix around the title', () {
      expect(
        StreamRelevance.isRelevant(
          source: _src('The Nocturne 1080p WEB-DL'),
          title: 'Nocturne',
          season: 1,
          episode: 1,
        ),
        isTrue,
      );
      expect(
        StreamRelevance.isRelevant(
          source: _src('Hindi Nocturne 1080p WEB-DL'),
          title: 'Nocturne',
          season: 1,
          episode: 1,
        ),
        isTrue,
      );
    });

    test('accepts a provider title that drops trailing words', () {
      expect(
        StreamRelevance.isRelevant(
          source: _src('Mission.Impossible.Dead.Reckoning.2023.1080p.WEB-DL'),
          title: 'Mission: Impossible – Dead Reckoning Part One',
          year: 2023,
        ),
        isTrue,
      );
    });

    test('accepts a dotted release name with audio markers', () {
      expect(
        StreamRelevance.isRelevant(
          source: _src(
            'Nocturne.S01E01.Lazzaro.vieni.fuori.ITA.ENG.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-MeGusta',
          ),
          title: 'Nocturne',
          season: 1,
          episode: 1,
        ),
        isTrue,
      );
    });

    test('accepts a movie year written without parentheses', () {
      final ok = StreamRelevance.isRelevant(
        source: _src('Oppenheimer.2023.1080p.BluRay.x264'),
        title: 'Oppenheimer',
        year: 2023,
      );
      expect(ok, isTrue);
    });
  });
}
