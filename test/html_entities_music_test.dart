import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/jiosaavn_music_client.dart';
import 'package:dizzy/utils/text/html_entities.dart';

void main() {
  group('unescapeHtmlEntities', () {
    test('unescapes the entities that occur in music metadata', () {
      expect(unescapeHtmlEntities('Vishal &amp; Shekhar'), 'Vishal & Shekhar');
      expect(unescapeHtmlEntities('Aashiqui&nbsp;2'), 'Aashiqui 2');
      expect(unescapeHtmlEntities('Don&#39;t'), "Don't");
      expect(unescapeHtmlEntities('&#x27;Round Midnight'), "'Round Midnight");
      expect(unescapeHtmlEntities('&quot;Kabhi&quot;'), '"Kabhi"');
    });

    test('leaves plain text untouched', () {
      expect(unescapeHtmlEntities('Arijit Singh'), 'Arijit Singh');
      expect(unescapeHtmlEntities(''), '');
    });

    test('passes through unknown or malformed references untouched', () {
      // Real text that merely contains "&" must never be mangled.
      expect(unescapeHtmlEntities('ATB & friends amp vibes'), 'ATB & friends amp vibes');
      expect(unescapeHtmlEntities('&unknown;'), '&unknown;');
      expect(unescapeHtmlEntities('&'), '&');
      expect(unescapeHtmlEntities('a & b'), 'a & b');
      expect(unescapeHtmlEntities('amp;'), 'amp;');
    });

    test('is idempotent', () {
      const once = 'Vishal &amp; Shekhar';
      expect(unescapeHtmlEntities(unescapeHtmlEntities(once)),
          unescapeHtmlEntities(once));
    });
  });

  group('JiosaavnMusicClient.toTrack (Saavn boundary)', () {
    test('unescapes title, artist and album', () {
      final t = JiosaavnMusicClient.toTrack({
        'id': 'abc123',
        'title': 'Tum Hi Ho &amp; More',
        'artist': 'Arijit Singh &amp; Shreya Ghoshal',
        'album': 'Aashiqui 2 &amp; Other Hits',
        'coverUrl': 'https://img.example/c.jpg',
        'durationSeconds': 260,
      });

      expect(t, isNotNull);
      expect(t!.id, 'saavn_abc123');
      expect(t.title, 'Tum Hi Ho & More');
      expect(t.artist, 'Arijit Singh & Shreya Ghoshal');
      expect(t.album, 'Aashiqui 2 & Other Hits');
    });

    test('returns null for rows without id or title', () {
      expect(JiosaavnMusicClient.toTrack({'id': '', 'title': 'x'}), isNull);
      expect(JiosaavnMusicClient.toTrack({'id': 'x', 'title': '  '}), isNull);
    });
  });

  group('MusicTrack.fromJson (Deezer boundary)', () {
    test('unescapes title, artist and album', () {
      final t = MusicTrack.fromJson({
        'id': 'dz42',
        'title': 'Believer &amp; Friends',
        'artist': {'id': '9', 'name': 'Imagine Dragons &amp; Co.'},
        'album': {'id': '3', 'title': 'Evolve &amp; Beyond'},
        'duration': 204,
      });

      expect(t.title, 'Believer & Friends');
      expect(t.artist, 'Imagine Dragons & Co.');
      expect(t.album, 'Evolve & Beyond');
      expect(t.artistId, '9');
    });
  });
}
