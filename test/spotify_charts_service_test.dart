import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/music/spotify_charts_service.dart';

const _fixture = '''
<html><body><script id="__NEXT_DATA__" type="application/json">
{"props":{"pageProps":{"state":{"data":{"entity":{
  "name":"Top 50 - India",
  "coverArt":{"sources":[{"url":"https://covers.example/640.jpg"},{"url":"https://covers.example/64.jpg"}]},
  "trackList":[
    {"uri":"spotify:track:abc1","title":"Saiyaan","subtitle":"Arijit Singh","duration":"231000","isExplicit":false,"audioPreview":{"url":"https://p.example/1.mp3"}},
    {"uri":"spotify:track:def2","title":"Sahiba","subtitle":"Aditya Rikhari","duration":"198000","isExplicit":true}
  ]
}}}}}}
</script></body></html>
''';

SpotifyChart? _parse(String html) =>
    SpotifyChartsService.parseChartHtml(html, kSpotifyChartSpecs.first);

void main() {
  group('SpotifyChartsService.parseChartHtml', () {
    test('parses cover, tracks, ids, durations and explicit flags', () {
      final chart = _parse(_fixture);
      expect(chart, isNotNull);
      expect(chart!.spec.key, 'top50_in');
      expect(chart.coverUrl, 'https://covers.example/640.jpg');
      expect(chart.tracks, hasLength(2));

      final first = chart.tracks.first;
      expect(first.id, 'spotify_abc1');
      expect(first.title, 'Saiyaan');
      expect(first.artist, 'Arijit Singh');
      expect(first.album, 'Top 50 - India');
      expect(first.durationSeconds, 231);
      expect(first.trackNumber, 1);
      expect(first.previewUrl, 'https://p.example/1.mp3');
      expect(first.explicit, isFalse);

      final second = chart.tracks[1];
      expect(second.id, 'spotify_def2');
      expect(second.explicit, isTrue);
      expect(second.previewUrl, isNull);
    });

    test('keeps Devanagari titles intact through explicit UTF-8 decode', () {
      final html = _fixture.replaceFirst('Saiyaan', 'साइयां');
      final chart = _parse(html);
      expect(chart!.tracks.first.title, 'साइयां');
    });

    test('returns null for html without embedded state', () {
      expect(_parse('<html><body>login wall</body></html>'), isNull);
    });

    test('returns null when trackList is missing', () {
      const html = '''
<script id="__NEXT_DATA__" type="application/json">
{"props":{"pageProps":{"state":{"data":{"entity":{"name":"x"}}}}}}
</script>''';
      expect(_parse(html), isNull);
    });

    test('skips rows without a title but keeps the rest', () {
      final html = _fixture.replaceFirst(
        '"title":"Saiyaan"',
        '"title":""',
      );
      final chart = _parse(html);
      expect(chart!.tracks, hasLength(1));
      expect(chart.tracks.first.title, 'Sahiba');
    });
  });

  group('SpotifyChartsService.fetchAll', () {
    test('omits charts whose fetch fails, never placeholders', () async {
      final service = SpotifyChartsService.withFetcher(
        (uri) async {
          if (uri.path.contains('37i9dQZEVXbMDoHDwVN2tF')) {
            throw Exception('network flap');
          }
          return _fixture;
        },
      );
      final charts = await service.fetchAll();
      expect(charts, hasLength(3));
      expect(
        charts.map((c) => c.spec.playlistId),
        isNot(contains('37i9dQZEVXbMDoHDwVN2tF')),
      );
      for (final c in charts) {
        expect(c.tracks, isNotEmpty);
      }
    });
  });
}
