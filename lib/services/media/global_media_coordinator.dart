import 'package:flutter/foundation.dart';

import '../music/music_player_controller.dart';

/// UX5 — Global Media Coordinator.
///
/// Single place that resolves video <-> music playback conflicts and
/// tracks video mini-player state.
///
/// Rules (non-tech, Easy English):
/// - Only ONE thing plays sound at a time.
/// - Starting a video softly pauses music.
/// - Starting music asks video to pause (via [onPauseVideoRequest]).
/// - Navigating away from fullscreen video -> mini-player, never full stop.
class GlobalMediaCoordinator extends ChangeNotifier {
  GlobalMediaCoordinator._();
  static final GlobalMediaCoordinator instance =
      GlobalMediaCoordinator._();

  /// True while a video is on screen (fullscreen or mini-player).
  final ValueNotifier<bool> videoActive = ValueNotifier<bool>(false);

  /// True while video is in mini-player (navigated away, still playing).
  final ValueNotifier<bool> videoMiniPlayerVisible =
      ValueNotifier<bool>(false);

  /// Title shown on the mini-player pill.
  final ValueNotifier<String> videoMiniTitle =
      ValueNotifier<String>('');

  /// PlayerScreen registers here so music can request a video pause.
  VoidCallback? onPauseVideoRequest;

  bool _notifying = false;
  bool _attached = false;

  /// Observes music playback; call once at startup (main).
  /// When music starts while video is active, asks video to pause.
  void attach() {
    if (_attached) return;
    _attached = true;
    MusicPlayerController.instance.addListener(_onMusicChanged);
  }

  void _onMusicChanged() {
    try {
      if (MusicPlayerController.instance.isPlaying &&
          videoActive.value) {
        notifyMusicStarted();
      }
    } catch (_) {}
  }

  /// Call when a video starts playing (fullscreen).
  Future<void> notifyVideoStarted({String title = ''}) async {
    videoActive.value = true;
    videoMiniPlayerVisible.value = false;
    if (title.isNotEmpty) videoMiniTitle.value = title;
    // One sound at a time: softly pause music.
    try {
      if (MusicPlayerController.instance.isPlaying) {
        await MusicPlayerController.instance.pause();
      }
    } catch (_) {}
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

  /// Call when music starts; asks video to pause first.
  void notifyMusicStarted() {
    if (_notifying) return;
    _notifying = true;
    try {
      if (videoActive.value) {
        onPauseVideoRequest?.call();
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
}
