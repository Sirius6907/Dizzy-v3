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
  var nativeState = const PlayerState();
  var pauses = 0;
  var opens = 0;
  Completer<void>? openGate;

  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state => nativeState;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opens++;
    final gate = openGate;
    if (gate != null) await gate.future;
  }
  @override
  Future<void> play() async {
    nativeState = nativeState.copyWith(playing: true);
    events.playingEvents.add(true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    nativeState = nativeState.copyWith(playing: false);
    events.playingEvents.add(false);
  }

  @override
  Future<void> setVolume(double volume) async {}
}

class _NoStreams extends MusicService {
  @override
  Future<MusicStreamResult?> getNextAudioStream(MusicTrack track) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const track = MusicTrack(
    id: 'saavn_tap-test',
    title: 'Tap track',
    artist: 'Test artist',
    album: 'Test album',
    coverUrl: '',
    durationSeconds: 200,
    previewUrl: 'https://audio-test.invalid/song.m4a',
  );

  late _Backend backend;
  late MusicPlayerController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = _Backend();
    controller = MusicPlayerController(
      playerFactory: () => backend,
      musicService: _NoStreams(),
    );
    await controller.playTrack(track);
    expect(controller.isPlaying, isTrue);
  });

  tearDown(() async {
    await backend.events.close();
  });

  test('a ghost double tap on play/pause pauses exactly once', () async {
    await controller.togglePlayPause();
    expect(controller.isPlaying, isFalse);
    expect(backend.pauses, 1);

    // The finger's second landing arrives while the first action is still in
    // its fade-out, and even after it finishes it is inside the window.
    await controller.togglePlayPause();

    expect(backend.pauses, 1);
    expect(controller.isPlaying, isFalse);
  });

  test('a later tap is a new intent and plays again', () async {
    await controller.togglePlayPause();
    expect(controller.isPlaying, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 350));
    await controller.togglePlayPause();

    expect(controller.isPlaying, isTrue);
    expect(backend.pauses, 1);
  });

  test('the visual lock is up while the transport action runs', () async {
    expect(controller.actionLock.value, isFalse);

    final first = controller.togglePlayPause();
    // The pause fade keeps the action in flight for ~70 ms.
    expect(controller.actionLock.value, isTrue);

    // Tapping the visibly locked button cannot start a second pause.
    await controller.togglePlayPause();
    await first;

    expect(controller.actionLock.value, isFalse);
    expect(backend.pauses, 1);
  });

  test('a ghost double tap on a row loads the track once', () async {
    final gate = Completer<void>();
    backend
      ..opens = 0
      ..openGate = gate;

    final first = controller.playTrack(track);
    await Future<void>.delayed(Duration.zero);
    expect(controller.isLoading, isTrue);

    // The second tap lands while the first open is still resolving.
    await controller.playTrack(track);

    gate.complete();
    backend.openGate = null;
    await first;

    expect(backend.opens, 1);
  });
}
