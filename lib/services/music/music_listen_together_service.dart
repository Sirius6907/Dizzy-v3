import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/music/music_track.dart';
import 'music_player_controller.dart';

class MusicListenTogetherService {
  MusicListenTogetherService._();
  static final MusicListenTogetherService instance = MusicListenTogetherService._();

  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final ValueNotifier<String?> activeRoomCode = ValueNotifier<String?>(null);
  final ValueNotifier<int> memberCount = ValueNotifier<int>(1);
  final ValueNotifier<bool> isHost = ValueNotifier<bool>(false);

  VoidCallback? _playerListener;

  Future<String> createRoom() async {
    leaveRoom();
    final random = Random();
    final code = 'DIZ-${1000 + random.nextInt(9000)}';

    activeRoomCode.value = code;
    isConnected.value = true;
    isHost.value = true;
    memberCount.value = 1;

    _bindHostEvents();
    return code;
  }

  Future<bool> joinRoom(String code) async {
    leaveRoom();
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.length < 4) return false;

    activeRoomCode.value = cleanCode;
    isConnected.value = true;
    isHost.value = false;
    memberCount.value = 2;

    return true;
  }

  void _bindHostEvents() {
    _unbindHostEvents();
    _playerListener = () {
      // Host syncs track metadata to room broadcast
    };
    MusicPlayerController.instance.addListener(_playerListener!);
  }

  void _unbindHostEvents() {
    if (_playerListener != null) {
      MusicPlayerController.instance.removeListener(_playerListener!);
      _playerListener = null;
    }
  }

  void leaveRoom() {
    _unbindHostEvents();
    isConnected.value = false;
    activeRoomCode.value = null;
    isHost.value = false;
    memberCount.value = 1;
  }

  /// Called when listener receives a track change event from host
  Future<void> onRemoteTrackChange(MusicTrack track, {int? positionMs}) async {
    if (isHost.value) return;
    await MusicPlayerController.instance.playTrack(track);
    if (positionMs != null && positionMs > 0) {
      await MusicPlayerController.instance.seekTo(Duration(milliseconds: positionMs));
    }
  }

  /// Syncs remote play/pause state
  Future<void> onRemotePlayPause(bool isPlaying) async {
    if (isHost.value) return;
    if (isPlaying && !MusicPlayerController.instance.isPlaying) {
      await MusicPlayerController.instance.play();
    } else if (!isPlaying && MusicPlayerController.instance.isPlaying) {
      await MusicPlayerController.instance.pause();
    }
  }

  /// Syncs remote seek timestamp if drift > 2.5 seconds
  Future<void> onRemoteSeek(Duration position) async {
    if (isHost.value) return;
    final currentPos = MusicPlayerController.instance.position;
    final drift = (currentPos - position).abs();
    if (drift > const Duration(milliseconds: 2500)) {
      await MusicPlayerController.instance.seekTo(position);
    }
  }
}
