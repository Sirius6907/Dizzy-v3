import 'package:dizzy/utils/torrent/torrent_trackers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('magnetWithTrackers', () {
    test('a bare magnet gets the public tracker list', () {
      final out = magnetWithTrackers('magnet:?xt=urn:btih:ABCDEF0123456789');
      expect(out, startsWith('magnet:?xt=urn:btih:ABCDEF0123456789&tr='));
      expect(magnetTrackers(out).length, publicTrackers.length);
    });

    test('index trackers are kept and public ones appended', () {
      final magnet =
          'magnet:?xt=urn:btih:ABCDEF0123456789&tr=${Uri.encodeComponent('udp://tracker.knaben.org:1337/announce')}';
      final out = magnetWithTrackers(magnet);
      final trackers = magnetTrackers(out);
      expect(trackers.first, 'udp://tracker.knaben.org:1337/announce');
      expect(trackers.length, publicTrackers.length + 1);
    });

    test('is idempotent', () {
      final once = magnetWithTrackers('magnet:?xt=urn:btih:ABCDEF0123456789');
      final twice = magnetWithTrackers(once);
      expect(twice, once);
    });

    test('the same host over another scheme is not duplicated', () {
      final magnet =
          'magnet:?xt=urn:btih:ABCDEF0123456789&tr=${Uri.encodeComponent('http://tracker.opentrackr.org:1337/announce')}';
      final out = magnetWithTrackers(magnet);
      expect(
        magnetTrackers(out)
            .where((t) => t.contains('tracker.opentrackr.org'))
            .length,
        1,
      );
    });

    test('a non magnet string is returned unchanged', () {
      expect(magnetWithTrackers('https://example.com/x.mp4'), 'https://example.com/x.mp4');
    });
  });
}
