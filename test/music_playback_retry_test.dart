import 'dart:async';

import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/music_player_controller.dart';
import 'package:dizzy/services/music/music_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AudioStreams extends Fake implements PlayerStream {
  final playingEvents = StreamController<bool>.broadcast(sync: true);
  final errorEvents = StreamController<String>.broadcast(sync: true);
  final positionEvents = StreamController<Duration>.broadcast(sync: true);

  @override
  Stream<bool> get playing => playingEvents.stream;
  @override
  Stream<String> get error => errorEvents.stream;
  @override
  Stream<Duration> get position => positionEvents.stream;
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<PlayerLog> get log => const Stream.empty();

  Future<void> close() async {
    await playingEvents.close();
    await errorEvents.close();
    await positionEvents.close();
  }
}

class _AudioBackend extends Fake implements Player {
  final events = _AudioStreams();
  var opened = false;
  var failNextOpen = true;
  var nativeState = const PlayerState();

  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state => nativeState;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (failNextOpen) {
      failNextOpen = false;
      opened = false;
      events.errorEvents.add('HTTP 403: expired audio stream');
    } else {
      opened = true;
    }
  }

  @override
  Future<void> play() async {
    if (opened) {
      nativeState = nativeState.copyWith(playing: true);
      events.playingEvents.add(true);
    }
  }

  @override
  Future<void> pause() async {
    nativeState = nativeState.copyWith(playing: false);
    events.playingEvents.add(false);
  }

  @override
  Future<void> setVolume(double volume) async {}
}

class _NoAlternativeService extends MusicService {
  @override
  Future<MusicStreamResult?> getNextAudioStream(MusicTrack track) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const track = MusicTrack(
    id: 'saavn_retry-test',
    title: 'Retry track',
    artist: 'Test artist',
    album: 'Test album',
    coverUrl: '',
    durationSeconds: 200,
    previewUrl: 'https://audio-test.invalid/song.m4a',
  );

  test(
    'native open failure stays stopped and Play reloads the audio',
    () async {
      SharedPreferences.setMockInitialValues({});
      final backend = _AudioBackend();
      final controller = MusicPlayerController(
        playerFactory: () => backend,
        musicService: _NoAlternativeService(),
      );
      await controller.playTrack(track);
      expect(controller.errorMessage, isNotNull);
      expect(controller.isPlaying, isFalse);
      expect(controller.isCurrentTrackLossless, isFalse);
      expect(controller.currentQualityLabel, 'Audio unavailable');

      await controller.play();
      expect(controller.errorMessage, isNull);
      expect(controller.isPlaying, isTrue);
      expect(controller.currentTrack?.id, track.id);
      await backend.events.close();
    },
  );

  test(
    'advancing playback recovers a native diagnostic without reopening',
    () async {
      SharedPreferences.setMockInitialValues({});
      final backend = _AudioBackend()..failNextOpen = false;
      final controller = MusicPlayerController(
        playerFactory: () => backend,
        musicService: _NoAlternativeService(),
      );
      await controller.playTrack(track);
      final quality = controller.currentQualityLabel;
      backend.events.positionEvents.add(const Duration(seconds: 5));
      backend.events.errorEvents.add(
        'Audio decoder reported a recoverable failure',
      );
      backend.events.playingEvents.add(true);
      expect(controller.errorMessage, isNotNull);
      backend.events.positionEvents.add(const Duration(seconds: 6));
      expect(controller.isPlaying, isTrue);
      expect(controller.errorMessage, isNull);
      expect(controller.currentQualityLabel, quality);
      expect(controller.isCurrentTrackLossless, isFalse);
      await controller.togglePlayPause();
      expect(controller.isPlaying, isFalse);
      // Pausing then resuming is two separate intents; wait past the ghost-tap
      // window so the second tap is not treated as a duplicate of the first.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await controller.togglePlayPause();
      expect(controller.isPlaying, isTrue);
      await backend.events.close();
    },
  );

  test(
    'paused or stalled native state cannot clear a playback failure',
    () async {
      SharedPreferences.setMockInitialValues({});
      final backend = _AudioBackend()..failNextOpen = false;
      final controller = MusicPlayerController(
        playerFactory: () => backend,
        musicService: _NoAlternativeService(),
      );
      await controller.playTrack(track);
      backend.events.positionEvents.add(const Duration(seconds: 5));
      backend.events.errorEvents.add('Failed to open audio');
      backend.events.playingEvents.add(true);
      backend.events.positionEvents.add(const Duration(seconds: 5));
      expect(controller.errorMessage, isNotNull);
      backend.nativeState = backend.nativeState.copyWith(playing: false);
      backend.events.positionEvents.add(const Duration(seconds: 20));
      expect(controller.isPlaying, isFalse);
      expect(controller.errorMessage, isNotNull);
      await backend.events.close();
    },
  );
}
