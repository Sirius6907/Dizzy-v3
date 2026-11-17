import 'dart:async';

import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/music_player_controller.dart';
import 'package:dizzy/services/music/music_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Streams extends Fake implements PlayerStream {
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

class _Backend extends Fake implements Player {
  final events = _Streams();
  var openCount = 0;
  var rejectFirstOpen = true;
  var nativeState = const PlayerState();

  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state => nativeState;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    openCount++;
    if (rejectFirstOpen) {
      rejectFirstOpen = false;
      events.errorEvents.add('stream: Failed to open');
      return;
    }
    nativeState = nativeState.copyWith(playing: true);
    events.playingEvents.add(true);
  }

  @override
  Future<void> play() async {
    nativeState = nativeState.copyWith(playing: true);
    events.playingEvents.add(true);
  }

  @override
  Future<void> setVolume(double volume) async {}
}

class _Service extends MusicService {
  _Service({required this.alternative});
  final MusicStreamResult? alternative;
  int calls = 0;

  @override
  Future<MusicStreamResult?> getNextAudioStream(MusicTrack track) async {
    calls++;
    return alternative;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const track = MusicTrack(
    id: 'saavn_fallback-test',
    title: 'Fallback track',
    artist: 'Test artist',
    album: 'Test album',
    coverUrl: '',
    durationSeconds: 200,
    previewUrl: 'https://cdn.test/first.m4a',
  );

  test('a rejected stream URL is retried with the next candidate', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend();
    final service = _Service(
      alternative: const MusicStreamResult(
        url: 'https://cdn.test/alternative.m4a',
        userAgent: 'test-agent',
        format: 'm4a',
        quality: 'YouTube HQ',
        isLossless: false,
      ),
    );
    final controller = MusicPlayerController(
      playerFactory: () => backend,
      musicService: service,
    );

    await controller.playTrack(track);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.calls, 1);
    expect(backend.openCount, greaterThanOrEqualTo(2));
    expect(controller.errorMessage, isNull);
    expect(controller.isPlaying, isTrue);
    await backend.events.close();
  });
}
