import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/stream/torrent_warmup_policy.dart';

void main() {
  group('TorrentWarmupPolicy', () {
    test('waits while the swarm has no bytes', () {
      expect(
        TorrentWarmupPolicy.isReady(
          loadedBytes: 0,
          preloadedBytes: 0,
          elapsed: const Duration(seconds: 4),
        ),
        isFalse,
      );
    });

    test('opens once 2 MB are buffered', () {
      expect(
        TorrentWarmupPolicy.isReady(
          loadedBytes: 2 * 1024 * 1024,
          preloadedBytes: 0,
          elapsed: const Duration(seconds: 1),
        ),
        isTrue,
      );
    });

    test('trusts engine preload after a short grace', () {
      expect(
        TorrentWarmupPolicy.isReady(
          loadedBytes: 0,
          preloadedBytes: 65536,
          elapsed: const Duration(seconds: 1),
        ),
        isFalse,
      );
      expect(
        TorrentWarmupPolicy.isReady(
          loadedBytes: 0,
          preloadedBytes: 65536,
          elapsed: const Duration(seconds: 3),
        ),
        isTrue,
      );
    });

    test('never blocks past the cap', () {
      expect(
        TorrentWarmupPolicy.isReady(
          loadedBytes: 0,
          preloadedBytes: 0,
          elapsed: TorrentWarmupPolicy.maxWait,
        ),
        isTrue,
      );
    });
  });
}
