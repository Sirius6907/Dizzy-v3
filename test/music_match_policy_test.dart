import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/jiosaavn_music_client.dart';
import 'package:dizzy/services/music/music_match_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// v1.3.3-T3.3 — the wrong-song bug must never come back.
///
/// These tests pin the rule that matters: an exact hit resolves, and
/// ANYTHING less than exact returns null instead of a plausible-looking
/// wrong song (poster-A-plays-B is the worst streaming bug).
void main() {
  group('normalize', () {
    test('strips case, punctuation and bracketed credits', () {
      expect(MusicMatchPolicy.normalize('Kesariya'), 'kesariya');
      expect(MusicMatchPolicy.normalize('Kesariya (From "Brahmastra")'), 'kesariya');
      expect(MusicMatchPolicy.normalize('Kesariya feat. Arijit'), 'kesariya');
      expect(MusicMatchPolicy.normalize('  Kesariya!!  '), 'kesariya');
    });

    test('folds transliteration pairs on both sides', () {
      // "Jhia" / "Jhiya" / "Jia" must converge — Odia romanisation varies.
      expect(MusicMatchPolicy.normalize('Jhia'), MusicMatchPolicy.normalize('Jia'));
      expect(MusicMatchPolicy.normalize('Khatti'), MusicMatchPolicy.normalize('Khati'));
    });
  });

  group('titlesMatch', () {
    test('exact and case/punctuation variants match', () {
      expect(MusicMatchPolicy.titlesMatch('Kesariya', 'kesariya'), isTrue);
      expect(MusicMatchPolicy.titlesMatch('Tum Hi Ho', 'Tum Hi Ho (Reprise)'), isTrue);
    });

    test('word order differences match (token set)', () {
      expect(MusicMatchPolicy.titlesMatch('Kal Ho Naa Ho', 'Naa Ho Kal Ho'), isTrue);
    });

    test('a different song never matches', () {
      expect(MusicMatchPolicy.titlesMatch('Kesariya', 'Kesari Teri'), isFalse);
      expect(MusicMatchPolicy.titlesMatch('Tum Hi Ho', 'Tum Se Hi'), isFalse);
      expect(MusicMatchPolicy.titlesMatch('Channa Mereya', 'Channa Ve'), isFalse);
    });

    test('empty input never matches', () {
      expect(MusicMatchPolicy.titlesMatch('', 'Kesariya'), isFalse);
      expect(MusicMatchPolicy.titlesMatch('Kesariya', ''), isFalse);
    });
  });

  group('pickExact — exact match or nothing', () {
    test('exact title resolves to the right index', () {
      final titles = ['Kesari Teri', 'Kesariya', 'Kesariya (From "Brahmastra")'];
      final i = MusicMatchPolicy.pickExact('Kesariya', candidateTitles: titles);
      expect(i, isNotNull);
      expect(titles[i!], startsWith('Kesariya'));
    });

    test('substring-only candidates return null (no wrong song)', () {
      final titles = ['Kesari Teri', 'Kesariya Remix Extravaganza Version'];
      final i = MusicMatchPolicy.pickExact('Kesariya', candidateTitles: titles);
      // 'Kesariya Remix...' has a different token set → not an exact hit.
      expect(i, isNull);
    });

    test('wrong query returns null instead of best guess', () {
      final titles = ['Tum Hi Ho', 'Tum Se Hi'];
      expect(MusicMatchPolicy.pickExact('Tum Hi Ho', candidateTitles: titles), 0);
      expect(MusicMatchPolicy.pickExact('Channa Mereya', candidateTitles: titles), isNull);
    });

    test('year is a tiebreak only, never a way in', () {
      final titles = ['Kesariya', 'Kesariya'];
      final years = [2015, 2022];
      expect(
        MusicMatchPolicy.pickExact('Kesariya',
            candidateTitles: titles, year: 2022, candidateYears: years),
        1,
      );
      // Right title, wrong year → still matches (year never blocks).
      expect(
        MusicMatchPolicy.pickExact('Kesariya',
            candidateTitles: titles, year: 1999, candidateYears: years),
        isNotNull,
      );
    });

    test('language hint disambiguates same-title duplicates', () {
      final titles = ['Neele Neele Ambar', 'Neele Neele Ambar'];
      final langs = ['hindi', 'oriya'];
      expect(
        MusicMatchPolicy.pickExact('Neele Neele Ambar',
            candidateTitles: titles,
            lang: 'oriya',
            candidateLangs: langs),
        1,
      );
    });

    test('empty candidate list → null', () {
      expect(MusicMatchPolicy.pickExact('Kesariya', candidateTitles: const []), isNull);
    });
  });

  group('languageHint', () {
    test('detects Odia script and Odia keywords', () {
      expect(MusicMatchPolicy.languageHint('ଝିଅ ଗୀତ'), 'oriya');
      expect(MusicMatchPolicy.languageHint('odia song'), 'oriya');
      expect(MusicMatchPolicy.languageHint('sambalpuri dj'), 'oriya');
      expect(MusicMatchPolicy.languageHint('ollywood mashup'), 'oriya');
    });

    test('detects Hindi/Punjabi/Tamil hints', () {
      expect(MusicMatchPolicy.languageHint('hindi song'), 'hindi');
      expect(MusicMatchPolicy.languageHint('bollywood party'), 'hindi');
      expect(MusicMatchPolicy.languageHint('punjabi bhangra'), 'punjabi');
      expect(MusicMatchPolicy.languageHint('tamil hits'), 'tamil');
      expect(MusicMatchPolicy.languageHint('गाना'), 'hindi');
    });

    test('no hint returns empty (never guesses)', () {
      expect(MusicMatchPolicy.languageHint('kesariya'), '');
    });
  });

  group('JioSaavn row mapping', () {
    test('maps an edge row to MusicTrack with a namespaced id', () {
      final t = JiosaavnMusicClient.toTrack({
        'id': 'abc123',
        'title': 'Kesariya',
        'artist': 'Arijit Singh',
        'album': 'Brahmastra',
        'coverUrl': 'https://c.saavncdn.com/450/x-500x500.jpg',
        'durationSeconds': 268,
        'previewUrl': 'https://aac.saavncdn.com/x.m4a',
      });
      expect(t, isNotNull);
      expect(t!.id, 'saavn_abc123'); // cannot collide with a Deezer id
      expect(t.title, 'Kesariya');
      expect(t.durationSeconds, 268);
      expect(t.previewUrl, isNotNull);
    });

    test('drops rows with no id or no title', () {
      expect(JiosaavnMusicClient.toTrack({'id': '', 'title': 'X'}), isNull);
      expect(JiosaavnMusicClient.toTrack({'id': '1', 'title': ''}), isNull);
    });

    test('missing optional fields degrade safely', () {
      final t = JiosaavnMusicClient.toTrack({'id': '1', 'title': 'X'});
      expect(t, isNotNull);
      expect(t!.artist, 'Unknown Artist');
      expect(t.album, 'Single');
      expect(t.durationSeconds, 0);
      expect(t.previewUrl, isNull);
    });

    test('pickExact over tracks returns null for a non-exact query', () {
      final tracks = [
        const MusicTrack(
          id: 'saavn_1', title: 'Kesari Teri', artist: 'A', album: 'B',
          coverUrl: '', durationSeconds: 100,
        ),
      ];
      expect(JiosaavnMusicClient.pickExact(tracks, 'Kesariya'), isNull);
      expect(JiosaavnMusicClient.pickExact(tracks, 'Kesari Teri'), isNotNull);
    });
  });
}