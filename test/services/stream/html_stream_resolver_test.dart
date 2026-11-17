import 'package:dizzy/services/stream/html_stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HtmlStreamResolver.looksLikeMediaUrl', () {
    test('media extensions are media', () {
      expect(HtmlStreamResolver.looksLikeMediaUrl('https://a.b/x.m3u8'), isTrue);
      expect(HtmlStreamResolver.looksLikeMediaUrl('https://a.b/x.mp4?t=1'), isTrue);
      expect(HtmlStreamResolver.looksLikeMediaUrl('https://a.b/x.MKV'), isTrue);
      expect(
        HtmlStreamResolver.looksLikeMediaUrl('http://127.0.0.1:8090/stream'),
        isTrue,
      );
    });

    test('player pages are not media', () {
      expect(HtmlStreamResolver.looksLikeMediaUrl('https://a.b/embed/tt1'), isFalse);
      expect(HtmlStreamResolver.looksLikeMediaUrl('https://a.b/watch/'), isFalse);
    });
  });

  group('HtmlStreamResolver.extractMediaUrl', () {
    test('finds a jwplayer file entry', () {
      const html = '''
        <html><head><script>
          var player = {"file":"https://cdn.example.com/hls/master.m3u8","title":"x"};
        </script></head><body></body></html>
      ''';
      final res = HtmlStreamResolver.extractMediaUrl(html);
      expect(res, isNotNull);
      expect(res!.url, 'https://cdn.example.com/hls/master.m3u8');
    });

    test('finds a sources array entry', () {
      const html = '''
        <script>var sources: [{file:"https://cdn.example.com/v/clip.mp4",label:"720p"}];</script>
      ''';
      final res = HtmlStreamResolver.extractMediaUrl(html);
      expect(res, isNotNull);
      expect(res!.url, 'https://cdn.example.com/v/clip.mp4');
    });

    test('finds a video tag src', () {
      const html = '<html><video src="https://cdn.example.com/movie.mp4"></video></html>';
      final res = HtmlStreamResolver.extractMediaUrl(html);
      expect(res, isNotNull);
      expect(res!.url, 'https://cdn.example.com/movie.mp4');
    });

    test('finds a bare media url', () {
      const html =
          '<html>redirecting to https://cdn.example.com/stream/index.m3u8 now</html>';
      final res = HtmlStreamResolver.extractMediaUrl(html);
      expect(res, isNotNull);
      expect(res!.url, contains('.m3u8'));
    });

    test('unescapes escaped slashes', () {
      const html =
          r'<script>var f = "https:\/\/cdn.example.com\/hls\/main.m3u8";</script>';
      final res = HtmlStreamResolver.extractMediaUrl(html);
      expect(res, isNotNull);
      expect(res!.url, 'https://cdn.example.com/hls/main.m3u8');
    });

    test('resolves relative playlist paths against the page url', () {
      const html = '<script>var p = "/hls/playlist.m3u8";</script>';
      final res = HtmlStreamResolver.extractMediaUrl(
        html,
        pageUrl: 'https://player.example.com/embed/tt1',
      );
      expect(res, isNotNull);
      expect(res!.url, 'https://player.example.com/hls/playlist.m3u8');
    });

    test('ignores pages without a stream', () {
      const html = '<html><body><a href="/next">next</a></body></html>';
      expect(HtmlStreamResolver.extractMediaUrl(html), isNull);
    });

    test('ignores javascript and data urls', () {
      const html =
          '<script>var f = "javascript:void(0)"; var d = "data:text/html,x";</script>';
      expect(HtmlStreamResolver.extractMediaUrl(html), isNull);
    });
  });
}
