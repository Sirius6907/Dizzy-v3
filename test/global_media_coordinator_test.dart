import 'package:dizzy/services/media/global_media_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Only one thing plays sound at a time."
///
/// These tests pin the request wiring without touching real playback: the
/// coordinator never decides anything itself, it just asks the surface that
/// owns the speaker to stand down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final coordinator = GlobalMediaCoordinator.instance;
  var videoPauses = 0;
  var audiobookPauses = 0;

  setUp(() {
    coordinator.resetForTest();
    videoPauses = 0;
    audiobookPauses = 0;
    coordinator.onPauseVideoRequest = () => videoPauses++;
    coordinator.onPauseAudiobookRequest = () => audiobookPauses++;
  });

  tearDown(() => coordinator.resetForTest());

  test('video starting takes the speaker from the book', () async {
    await coordinator.notifyAudiobookStarted();
    expect(coordinator.audiobookActive.value, isTrue);
    expect(
      coordinator.videoActive.value,
      isFalse,
      reason: 'a book is audio — it must keep playing in the background',
    );

    await coordinator.notifyVideoStarted(title: 'Live cricket');

    expect(coordinator.videoActive.value, isTrue);
    expect(coordinator.videoMiniTitle.value, 'Live cricket');
    expect(audiobookPauses, 1);
  });

  test('the book starting takes the speaker from on-screen video', () async {
    await coordinator.notifyVideoStarted();
    expect(coordinator.videoActive.value, isTrue);

    await coordinator.notifyAudiobookStarted();

    expect(coordinator.audiobookActive.value, isTrue);
    expect(videoPauses, 1);
  });

  test('music starting asks whoever is on screen to pause', () async {
    await coordinator.notifyVideoStarted();
    await coordinator.notifyAudiobookStarted();

    // Those two setups already asked each other to pause; from here on we
    // only want to count what the music request itself did.
    videoPauses = 0;
    audiobookPauses = 0;

    coordinator.notifyMusicStarted();

    expect(videoPauses, 1);
    expect(audiobookPauses, 1);
  });

  test('closing a book frees the speaker', () async {
    await coordinator.notifyAudiobookStarted();
    coordinator.notifyAudiobookStopped();

    expect(coordinator.audiobookActive.value, isFalse);
  });

  test('closing video clears both flags', () async {
    await coordinator.notifyVideoStarted(title: 'x');
    coordinator.notifyVideoToMiniPlayer(title: 'x');
    expect(coordinator.videoMiniPlayerVisible.value, isTrue);

    coordinator.notifyVideoStopped();

    expect(coordinator.videoActive.value, isFalse);
    expect(coordinator.videoMiniPlayerVisible.value, isFalse);
  });

  test('only the rising edge of music counts as a start', () {
    expect(
      GlobalMediaCoordinator.isMusicStart(playing: true, wasPlaying: false),
      isTrue,
    );
    expect(
      GlobalMediaCoordinator.isMusicStart(playing: true, wasPlaying: true),
      isFalse,
      reason: 'a progress tick must not re-ask for a pause every second',
    );
    expect(
      GlobalMediaCoordinator.isMusicStart(playing: false, wasPlaying: true),
      isFalse,
    );
  });

  test('the legacy conflict helper still answers the same way', () {
    expect(
      GlobalMediaCoordinator.resolveConflict(videoStarting: true),
      'pause-music',
    );
    expect(
      GlobalMediaCoordinator.resolveConflict(videoStarting: false),
      'pause-video',
    );
  });
}
