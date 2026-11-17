import 'package:flutter/foundation.dart';

import '../music/music_player_controller.dart';

/// UX5 — Global Media Coordinator.
///
/// Single place that resolves video <-> music playback conflicts and
/// tracks video mini-player state.
///
/// Rules (non-tech, Easy English):
/// - Only ONE thing plays sound at a time.
/// - Starting a video softly pauses music and the audiobook.
/// - Starting music asks video / audiobook to pause (via the request hooks).
/// - Navigating away from fullscreen video -> mini-player, never full stop.
class GlobalMediaCoordinator extends ChangeNotifier {
  GlobalMediaCoordinator._();
  static final GlobalMediaCoordinator instance = GlobalMediaCoordinator._();

  /// True while a video is on screen (fullscreen or mini-player).
  final ValueNotifier<bool> videoActive = ValueNotifier<bool>(false);

  /// True while video is in mini-player (navigated away, still playing).
  final ValueNotifier<bool> videoMiniPlayerVisible = ValueNotifier<bool>(false);

  /// Title shown on the mini-player pill.
  final ValueNotifier<String> videoMiniTitle = ValueNotifier<String>('');

  /// PlayerScreen registers here so music can request a video pause.
  VoidCallback? onPauseVideoRequest;

  /// True while an audiobook is playing (it is audio, not video — background
  /// playback must survive, so this never touches [videoActive]).
  final ValueNotifier<bool> audiobookActive = ValueNotifier<bool>(false);

  /// AudiobookPlayerScreen registers here so music/video can request a pause.
  VoidCallback? onPauseAudiobookRequest;

  bool _notifying = false;
  bool _attached = false;

  /// Last observed music state, so one tap of play asks for exactly one pause
  /// instead of firing on every position tick.
  bool _lastMusicPlaying = false;

  /// Observes music playback; call once at startup (main).
  /// When music starts while video or a book is active, asks them to pause.
  void attach() {
    if (_attached) return;
    _attached = true;
    _lastMusicPlaying = MusicPlayerController.instance.isPlaying;
    MusicPlayerController.instance.addListener(_onMusicChanged);
  }

  void _onMusicChanged() {
    try {
      final playing = MusicPlayerController.instance.isPlaying;
      final wasPlaying = _lastMusicPlaying;
      _lastMusicPlaying = playing;
      // Rising edge only: a ticking progress bar must not re-ask forever.
      if (!isMusicStart(playing: playing, wasPlaying: wasPlaying)) return;
      if (videoActive.value || audiobookActive.value) notifyMusicStarted();
    } catch (_) {}
  }

  /// Call when a video starts playing (fullscreen).
  Future<void> notifyVideoStarted({String title = ''}) async {
    videoActive.value = true;
    videoMiniPlayerVisible.value = false;
    if (title.isNotEmpty) videoMiniTitle.value = title;
    // One sound at a time: softly pause music and the book.
    try {
      if (MusicPlayerController.instance.isPlaying) {
        await MusicPlayerController.instance.pause();
      }
    } catch (_) {}
    if (audiobookActive.value) {
      try {
        onPauseAudiobookRequest?.call();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Call when user navigates away from video but audio continues.
  void notifyVideoToMiniPlayer({String title = ''}) {
    videoActive.value = true;
    videoMiniPlayerVisible.value = true;
    if (title.isNotEmpty) videoMiniTitle.value = title;
    notifyListeners();
  }

  /// Call when video fully closed.
  void notifyVideoStopped() {
    videoActive.value = false;
    videoMiniPlayerVisible.value = false;
    notifyListeners();
  }

  /// Call when an audiobook chapter starts playing.
  ///
  /// A book is audio: it keeps playing in the background (unlike video), but
  /// it still owns the only speaker, so music and any on-screen video yield.
  Future<void> notifyAudiobookStarted({String title = ''}) async {
    audiobookActive.value = true;
    try {
      if (MusicPlayerController.instance.isPlaying) {
        await MusicPlayerController.instance.pause();
      }
    } catch (_) {}
    if (videoActive.value) {
      try {
        onPauseVideoRequest?.call();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Call when the audiobook player is closed.
  void notifyAudiobookStopped() {
    audiobookActive.value = false;
    notifyListeners();
  }

  /// Call when music starts; asks video and the book to pause first.
  void notifyMusicStarted() {
    if (_notifying) return;
    _notifying = true;
    try {
      if (videoActive.value) {
        onPauseVideoRequest?.call();
      }
      if (audiobookActive.value) {
        onPauseAudiobookRequest?.call();
      }
    } finally {
      _notifying = false;
    }
    notifyListeners();
  }

  /// Pure helper (unit-tested): which side should yield?
  /// Returns 'pause-music' when video starts, 'pause-video' when music starts.
  static String resolveConflict({required bool videoStarting}) =>
      videoStarting ? 'pause-music' : 'pause-video';

  /// Pure helper (unit-tested): only the moment music goes from silent to
  /// playing is a conflict, not every following tick.
  static bool isMusicStart({
    required bool playing,
    required bool wasPlaying,
  }) => playing && !wasPlaying;

  /// Test seam: drop listeners and forget any armed hooks.
  @visibleForTesting
  void resetForTest() {
    if (_attached) {
      MusicPlayerController.instance.removeListener(_onMusicChanged);
    }
    _attached = false;
    _notifying = false;
    _lastMusicPlaying = false;
    videoActive.value = false;
    videoMiniPlayerVisible.value = false;
    videoMiniTitle.value = '';
    audiobookActive.value = false;
    onPauseVideoRequest = null;
    onPauseAudiobookRequest = null;
  }
}
