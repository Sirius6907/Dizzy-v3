import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/stream/dub_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The owner's anime rule (2026-11-15): anime is watched with the
/// ORIGINAL audio plus English subtitles, or in the ENGLISH dub. A Hindi
/// dub must never be offered for anime.
StreamSource _src(String name, {String? description}) => StreamSource(
      name: name,
      description: description,
      url: 'https://example.invalid/$name',
      addonName: 'test',
    );

void main() {
  group('anime audio buckets', () {
    test('an original release with English subtitles is the SUB bucket', () {
      final s = _src('[SubsPlease] Frieren - 01 (1080p) [Eng Subs]');
      expect(
        animeAudioBucket(s, mediaTitle: 'Frieren'),
        AnimeAudioBucket.originalWithEnglishSubs,
      );
    });

    test('an English dub is the DUB bucket', () {
      final s = _src('Frieren S01E01 [1080p] [Eng Dub]');
      expect(
        animeAudioBucket(s, mediaTitle: 'Frieren'),
        AnimeAudioBucket.englishDub,
      );
    });

    test('a Hindi dub is recognised and never offered', () {
      final s = _src('Frieren S01E01 [1080p] [Hindi Dub]');
      expect(
        animeAudioBucket(s, mediaTitle: 'Frieren'),
        AnimeAudioBucket.hindiDub,
      );
    });

    test('a Hindi dub with English subtitles is still a Hindi dub', () {
      final s = _src('Frieren S01E01 [Hindi Dub + Eng Subs]');
      expect(
        animeAudioBucket(s, mediaTitle: 'Frieren'),
        AnimeAudioBucket.hindiDub,
      );
    });

    test('the show title cannot tag every source as Hindi', () {
      // "Hindi Medium" is a show title, not an audio language.
      final s = _src('Hindi Medium S01E01 [1080p]');
      expect(
        animeAudioBucket(s, mediaTitle: 'Hindi Medium'),
        AnimeAudioBucket.originalWithEnglishSubs,
      );
    });
  });
}
