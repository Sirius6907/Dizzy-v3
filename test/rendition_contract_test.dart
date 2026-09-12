import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/hls_rendition_parser.dart';
import 'package:dizzy/services/stream/source_ranker.dart';

const _master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
https://cdn/x/1080/index.m3u8
''';

void main() {
  group('P9: master playlist parsing', () {
    test('3 variants, labels + relative resolve + best-first', () {
      final r = HlsRenditionParser.parseMaster(
          _master, 'https://cdn/x/master.m3u8');
      expect(r.map((e) => e.label), ['1080p', '720p', '480p']);
      expect(r.first.url, 'https://cdn/x/1080/index.m3u8');
      expect(r[1].url, 'https://cdn/x/720p/index.m3u8');
      expect(r.last.bitrate, 800000);
    });

    test('bandwidth-only master still ladders', () {
      const body = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000
a.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=12000000
b.m3u8
''';
      final r = HlsRenditionParser.parseMaster(body, 'https://c/m.m3u8');
      expect(r.map((e) => e.label), ['1080p', '480p']);
    });

    test('garbage / media playlist / empty → empty (never throws)', () {
      expect(HlsRenditionParser.parseMaster('', 'https://c/m.m3u8'), isEmpty);
      expect(
          HlsRenditionParser.parseMaster(
              '#EXTM3U\n#EXTINF:6,\nseg.ts\n', 'https://c/m.m3u8'),
          isEmpty);
      expect(HlsRenditionParser.parseMaster('💩', '💩'), isEmpty);
    });
  });

  group('P9: contract — model + ranker', () {
    test('fromJson parses renditions, skips malformed', () {
      final s = StreamSource.fromJson({
        'url': 'https://c/m.m3u8',
        'renditions': [
          {'label': '720p', 'url': 'https://c/720.m3u8', 'bitrate': 2800000},
          {'label': 'bad'}, // no url → skipped
          'junk', // not a map → skipped
        ],
      }, 'addon');
      expect(s.renditions.map((e) => e.label), ['720p']);
      expect(s.renditions.first.bitrate, 2800000);
    });

    test('missing renditions key → empty (old JSON still fine)', () {
      final s = StreamSource.fromJson({'url': 'https://c/f.mp4'}, 'a');
      expect(s.renditions, isEmpty);
    });

    test('copyWith carries renditions', () {
      final s = StreamSource(url: 'u', addonName: 'a');
      final c = s.copyWith(
          renditions: [const Rendition(label: '480p', url: 'u2')]);
      expect(c.renditions.map((e) => e.label), ['480p']);
      expect(s.renditions, isEmpty);
    });

    test('ranker scores +15 for rendition-bearing sources', () {
      const ctx = RankerContext();
      final plain = StreamSource(url: 'https://c/f.mp4', addonName: 'a');
      final rich = StreamSource(
        url: 'https://c/m.m3u8',
        addonName: 'a',
        renditions: const [Rendition(label: '720p', url: 'u')],
      );
      expect(SourceRanker.score(rich, ctx) - SourceRanker.score(plain, ctx),
          15);
      // Rich source wins the order even listed second.
      final ordered = SourceRanker.order([plain, rich], ctx);
      expect(ordered.first.url, 'https://c/m.m3u8');
    });
  });
}
