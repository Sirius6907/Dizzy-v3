import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/stream/torrent_file_guard.dart';

void main() {
  group('TorrentFileGuard', () {
    test('accepts common video files', () {
      expect(TorrentFileGuard.isVideo('Show.S01E01.mkv'), isTrue);
      expect(TorrentFileGuard.isVideo('movie.MP4'), isTrue);
      expect(TorrentFileGuard.isVideo('clip.webm'), isTrue);
      expect(TorrentFileGuard.isVideo('ep.ts'), isTrue);
    });

    test('rejects decoy executables and sidecars', () {
      expect(
        TorrentFileGuard.isVideo('Godzilla Minus Zero 1080p HD h264- ETHEL.exe'),
        isFalse,
      );
      expect(TorrentFileGuard.isVideo('setup.msi'), isFalse);
      expect(TorrentFileGuard.isVideo('movie.srt'), isFalse);
      expect(TorrentFileGuard.isVideo('archive.rar'), isFalse);
    });

    test('rejects files without an extension', () {
      expect(TorrentFileGuard.isVideo('README'), isFalse);
      expect(TorrentFileGuard.isVideo('trailingdot.'), isFalse);
    });
  });
}
