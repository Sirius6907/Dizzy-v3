import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/player/playback_duration_guard.dart';

void main() {
  group('trusted', () {
    test('rejects zero / sub-second placeholders', () {
      expect(PlaybackDurationGuard.trusted(Duration.zero), isNull);
      expect(
        PlaybackDurationGuard.trusted(const Duration(milliseconds: 800)),
        isNull,
      );
    });

    test('rejects absurd durations', () {
      expect(
        PlaybackDurationGuard.trusted(const Duration(hours: 30)),
        isNull,
      );
    });

    test('accepts a normal movie length', () {
      expect(
        PlaybackDurationGuard.trusted(const Duration(minutes: 119)),
        const Duration(minutes: 119),
      );
    });

    test('catalog runtime catches a wrong/bogus duration', () {
      const runtime = Duration(minutes: 119);
      // 8h "duration" on a 2h film = garbage container.
      expect(
        PlaybackDurationGuard.trusted(
          const Duration(hours: 8),
          reference: runtime,
        ),
        isNull,
      );
      // 20 min on a 2h film = wrong file.
      expect(
        PlaybackDurationGuard.trusted(
          const Duration(minutes: 20),
          reference: runtime,
        ),
        isNull,
      );
      // A few minutes of credits is fine.
      expect(
        PlaybackDurationGuard.trusted(
          const Duration(minutes: 126),
          reference: runtime,
        ),
        const Duration(minutes: 126),
      );
    });
  });

  group('remaining', () {
    test('never negative', () {
      expect(
        PlaybackDurationGuard.remaining(
          const Duration(minutes: 5),
          const Duration(minutes: 2),
        ),
        Duration.zero,
      );
    });

    test('counts down', () {
      expect(
        PlaybackDurationGuard.remaining(
          const Duration(seconds: 3),
          const Duration(minutes: 2),
        ),
        const Duration(seconds: 117),
      );
    });

    test('unknown duration has no remaining', () {
      expect(
        PlaybackDurationGuard.remaining(const Duration(seconds: 3), null),
        isNull,
      );
    });
  });

  test('real progress needs more than one decoded frame', () {
    expect(PlaybackDurationGuard.hasRealProgress(const Duration(seconds: 1)),
        isFalse);
    expect(PlaybackDurationGuard.hasRealProgress(const Duration(seconds: 5)),
        isTrue);
  });
}
