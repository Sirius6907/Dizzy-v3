import 'dart:async';
import 'package:flutter/material.dart';
import 'music_player_controller.dart';

class MusicSleepTimerService {
  MusicSleepTimerService._();
  static final MusicSleepTimerService instance = MusicSleepTimerService._();

  final ValueNotifier<int> remainingSeconds = ValueNotifier<int>(0);
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> stopAtEndOfTrack = ValueNotifier<bool>(false);

  Timer? _ticker;
  double _savedVolume = 1.0;
  String? _targetTrackId;

  void startTimer(Duration duration) {
    cancelTimer();
    _savedVolume = MusicPlayerController.instance.volume;
    remainingSeconds.value = duration.inSeconds;
    isActive.value = true;
    stopAtEndOfTrack.value = false;

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds.value <= 1) {
        _onTimerExpired();
      } else {
        remainingSeconds.value--;
        _checkFadeOut(remainingSeconds.value);
      }
    });
  }

  void startEndOfTrackTimer() {
    cancelTimer();
    final current = MusicPlayerController.instance.currentTrack;
    if (current == null) return;

    _targetTrackId = current.id;
    stopAtEndOfTrack.value = true;
    isActive.value = true;

    // Remaining duration of current song
    final pos = MusicPlayerController.instance.position;
    final dur = MusicPlayerController.instance.duration;
    final remaining = (dur - pos).inSeconds;
    remainingSeconds.value = remaining > 0 ? remaining : 30;

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final nowTrack = MusicPlayerController.instance.currentTrack;
      if (nowTrack == null || nowTrack.id != _targetTrackId) {
        _onTimerExpired();
        return;
      }

      final curPos = MusicPlayerController.instance.position;
      final curDur = MusicPlayerController.instance.duration;
      final rem = (curDur - curPos).inSeconds;
      remainingSeconds.value = rem > 0 ? rem : 0;

      if (remainingSeconds.value <= 1) {
        _onTimerExpired();
      } else {
        _checkFadeOut(remainingSeconds.value);
      }
    });
  }

  void _checkFadeOut(int secondsLeft) {
    // Smooth fade out over last 20 seconds
    if (secondsLeft <= 20 && secondsLeft > 0) {
      final fraction = secondsLeft / 20.0;
      MusicPlayerController.instance.setVolume((_savedVolume * fraction).clamp(0.02, 1.0));
    }
  }

  Future<void> _onTimerExpired() async {
    cancelTimer();
    await MusicPlayerController.instance.pause();
    // Restore saved volume for next time user plays
    await Future.delayed(const Duration(milliseconds: 300));
    await MusicPlayerController.instance.setVolume(_savedVolume);
  }

  void cancelTimer() {
    _ticker?.cancel();
    _ticker = null;
    isActive.value = false;
    stopAtEndOfTrack.value = false;
    remainingSeconds.value = 0;
    _targetTrackId = null;
    if (_savedVolume > 0) {
      MusicPlayerController.instance.setVolume(_savedVolume);
    }
  }

  String get formattedRemaining {
    final s = remainingSeconds.value;
    if (s <= 0) return '00:00';
    final m = s ~/ 60;
    final sec = s % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final remM = m % 60;
      return '${h}h ${remM}m';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
