import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/music_player_controller.dart';
import 'package:dizzy/services/music/music_sleep_timer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trackA = MusicTrack(
    id: 'track_1',
    title: 'Track One',
    artist: 'Artist One',
    album: 'Album One',
    coverUrl: 'https://example.com/a.jpg',
    durationSeconds: 180,
  );

  const trackB = MusicTrack(
    id: 'track_2',
    title: 'Track Two',
    artist: 'Artist Two',
    album: 'Album Two',
    coverUrl: 'https://example.com/b.jpg',
    durationSeconds: 210,
  );

  const trackC = MusicTrack(
    id: 'track_3',
    title: 'Track Three',
    artist: 'Artist Three',
    album: 'Album Three',
    coverUrl: 'https://example.com/c.jpg',
    durationSeconds: 240,
  );

  group('MusicPlayerController — hasNext contract', () {
    test('at last track with repeatMode.off, hasNext is false', () {
      final controller = MusicPlayerController.instance;
      controller.debugSeedPlaybackState(
        track: trackC,
        queue: [trackA, trackB, trackC],
      );

      // Repeat off -> last track has no next
      expect(controller.hasNext, isFalse);
    });

    test('at last track with repeatMode.one, hasNext is false (no wraparound)', () {
      final controller = MusicPlayerController.instance;
      controller.debugSeedPlaybackState(
        track: trackC,
        queue: [trackA, trackB, trackC],
      );

      // Toggle to repeat.all, then repeat.one
      controller.toggleRepeat(); // -> all
      controller.toggleRepeat(); // -> one
      expect(controller.repeatMode, MusicRepeatMode.one);

      // Repeat.one repeats current track, not next in queue
      expect(controller.hasNext, isFalse);

      // Reset
      controller.toggleRepeat(); // -> off
    });

    test('at last track with repeatMode.all, hasNext is true (wraps around)', () {
      final controller = MusicPlayerController.instance;
      controller.debugSeedPlaybackState(
        track: trackC,
        queue: [trackA, trackB, trackC],
      );

      controller.toggleRepeat(); // -> all
      expect(controller.repeatMode, MusicRepeatMode.all);
      expect(controller.hasNext, isTrue);

      // Reset
      controller.toggleRepeat(); // -> one
      controller.toggleRepeat(); // -> off
    });

    test('at first or middle track, hasNext is always true', () {
      final controller = MusicPlayerController.instance;
      controller.debugSeedPlaybackState(
        track: trackA,
        queue: [trackA, trackB, trackC],
      );
      expect(controller.hasNext, isTrue);

      controller.debugSeedPlaybackState(
        track: trackB,
        queue: [trackA, trackB, trackC],
      );
      expect(controller.hasNext, isTrue);
    });
  });

  group('MusicPlayerController — seek clamping', () {
    test('seekTo with negative position is safe and clamped to zero', () async {
      final controller = MusicPlayerController.instance;
      controller.debugSeedPlaybackState(
        track: trackA,
        queue: [trackA],
        position: const Duration(seconds: 30),
      );

      await controller.seekTo(const Duration(seconds: -15));
      expect(controller.position, Duration.zero);
    });

    test('seekTo beyond duration is clamped to duration', () async {
      final controller = MusicPlayerController.instance;
      controller.debugSeedPlaybackState(
        track: trackA, // 180 seconds
        queue: [trackA],
        position: const Duration(seconds: 30),
      );

      await controller.seekTo(const Duration(seconds: 500));
      expect(controller.position, const Duration(seconds: 180));
    });
  });

  group('MusicSleepTimerService — timer cancellation and formatted remaining', () {
    test('formattedRemaining handles zero, minutes, and hours accurately', () {
      final timer = MusicSleepTimerService.instance;

      timer.remainingSeconds.value = 0;
      expect(timer.formattedRemaining, '00:00');

      timer.remainingSeconds.value = 65;
      expect(timer.formattedRemaining, '01:05');

      timer.remainingSeconds.value = 3665;
      expect(timer.formattedRemaining, '1h 1m');
    });

    test('cancelTimer clears active state without crashing', () {
      final timer = MusicSleepTimerService.instance;
      timer.startTimer(const Duration(minutes: 15));
      expect(timer.isActive.value, isTrue);

      timer.cancelTimer();
      expect(timer.isActive.value, isFalse);
      expect(timer.remainingSeconds.value, 0);
    });
  });
}
