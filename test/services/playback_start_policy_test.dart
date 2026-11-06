import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/player/playback_start_policy.dart';

void main() {
  const episode = Duration(minutes: 62, seconds: 26);

  group('PlaybackStartPolicy.sanitize', () {
    test('rejects a start exactly at the end', () {
      expect(
        PlaybackStartPolicy.sanitize(episode, duration: episode),
        isNull,
      );
    });

    test('rejects a start inside the last 30 seconds', () {
      expect(
        PlaybackStartPolicy.sanitize(
          episode - const Duration(seconds: 10),
          duration: episode,
        ),
        isNull,
      );
    });

    test('rejects a start beyond 95 percent', () {
      expect(
        PlaybackStartPolicy.sanitize(
          Duration(milliseconds: (episode.inMilliseconds * 0.97).round()),
          duration: episode,
        ),
        isNull,
      );
    });

    test('keeps a normal resume point', () {
      expect(
        PlaybackStartPolicy.sanitize(
          const Duration(minutes: 20),
          duration: episode,
        ),
        const Duration(minutes: 20),
      );
    });

    test('treats null, zero and negative starts as no resume', () {
      expect(PlaybackStartPolicy.sanitize(null), isNull);
      expect(PlaybackStartPolicy.sanitize(Duration.zero), isNull);
      expect(
        PlaybackStartPolicy.sanitize(const Duration(seconds: -5)),
        isNull,
      );
    });

    test('keeps a start while duration is still unknown', () {
      expect(
        PlaybackStartPolicy.sanitize(const Duration(minutes: 20)),
        const Duration(minutes: 20),
      );
    });

    test('does not loop very short clips back to zero', () {
      const clip = Duration(seconds: 20);
      expect(
        PlaybackStartPolicy.sanitize(
          const Duration(seconds: 18),
          duration: clip,
        ),
        const Duration(seconds: 18),
      );
    });
  });

  group('PlaybackStartPolicy.resumeAfterFailover', () {
    test('drops the position when the old source never played', () {
      expect(
        PlaybackStartPolicy.resumeAfterFailover(
          position: episode,
          confirmedPlayback: false,
          duration: episode,
        ),
        isNull,
      );
    });

    test('drops an end-of-file position from a half-open source', () {
      expect(
        PlaybackStartPolicy.resumeAfterFailover(
          position: episode,
          confirmedPlayback: true,
          duration: episode,
        ),
        isNull,
      );
    });

    test('keeps a verified mid-episode position', () {
      expect(
        PlaybackStartPolicy.resumeAfterFailover(
          position: const Duration(minutes: 8),
          confirmedPlayback: true,
          duration: episode,
        ),
        const Duration(minutes: 8),
      );
    });
  });

  group('PlaybackStartPolicy.isAtTail', () {
    test('detects a position sitting at the very end', () {
      expect(PlaybackStartPolicy.isAtTail(episode, episode), isTrue);
    });

    test('does not flag the first minute', () {
      expect(
        PlaybackStartPolicy.isAtTail(
          const Duration(seconds: 30),
          episode,
        ),
        isFalse,
      );
    });

    test('does not flag short clips', () {
      expect(
        PlaybackStartPolicy.isAtTail(
          const Duration(seconds: 19),
          const Duration(seconds: 20),
        ),
        isFalse,
      );
    });
  });
}
