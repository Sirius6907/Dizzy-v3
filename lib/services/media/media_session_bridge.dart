import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../music/music_player_controller.dart';

/// Phase K1 — Dart side of the "now playing" layer.
///
/// [MediaSessionBridge] publishes what is playing to the native
/// [MediaPlaybackService], which renders it as a MediaStyle notification
/// bound to a system media session (lock screen, Bluetooth, Android Auto).
/// Transport buttons and audio-focus loss arrive on the same channel and
/// are routed into [MediaSessionActions], so playback decisions stay in
/// Dart — the native layer never decides what plays next.
///
/// Everything is fail-soft: a missing service, a denied foreground start or
/// a platform channel that is not registered must never stop the music.
@immutable
class MediaSessionState {
  const MediaSessionState({
    required this.title,
    this.subtitle,
    this.artPath,
    this.playing = false,
    this.positionMs = 0,
    this.durationMs = 0,
  });

  final String title;
  final String? subtitle;

  /// Local file path only — the native side decodes it, it never fetches.
  final String? artPath;
  final bool playing;
  final int positionMs;
  final int durationMs;

  /// Clamped so a negative seek or a duration that has not been probed yet
  /// cannot render a nonsense progress bar.
  Map<String, Object?> toMap() {
    final duration = durationMs < 0 ? 0 : durationMs;
    var position = positionMs < 0 ? 0 : positionMs;
    if (duration > 0 && position > duration) position = duration;
    return <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'art': artPath,
      'playing': playing,
      'positionMs': position,
      'durationMs': duration,
    };
  }

  /// Everything that makes a notification visibly different. Position is
  /// deliberately coarse so a ticking clock cannot spam the platform side.
  String get fingerprint =>
      '$title|${subtitle ?? ''}|$playing|$durationMs|${positionMs ~/ 5000}';

  @override
  bool operator ==(Object other) =>
      other is MediaSessionState && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;
}

/// Button handlers fed by the notification / lock screen / headset buttons.
@immutable
class MediaSessionActions {
  const MediaSessionActions({
    this.onToggle,
    this.onPlay,
    this.onPause,
    this.onNext,
    this.onPrev,
    this.onSeekRelative,
    this.onSeekAbsolute,
    this.onStop,
    this.onFocusLost,
  });

  final Future<void> Function()? onToggle;
  final Future<void> Function()? onPlay;
  final Future<void> Function()? onPause;
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrev;
  final Future<void> Function(int deltaMs)? onSeekRelative;
  final Future<void> Function(int positionMs)? onSeekAbsolute;
  final Future<void> Function()? onStop;
  final Future<void> Function()? onFocusLost;
}

class MediaSessionBridge {
  MediaSessionBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.sirius6907.dizzyv3/media',
  );

  /// Minimum gap between position-only refreshes (title / play state push
  /// straight through with `force: true`).
  static const Duration _throttle = Duration(milliseconds: 1000);

  static MediaSessionActions _actions = const MediaSessionActions();
  static bool _attached = false;
  static bool _running = false;
  static DateTime _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);
  static String? _lastFingerprint;
  static String? _lastForced;
  static bool _serviceMissing = false;

  /// Whether we believe the native notification is currently up.
  static bool get isRunning => _running;

  @visibleForTesting
  static void resetForTest() {
    _actions = const MediaSessionActions();
    _attached = false;
    _running = false;
    _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);
    _lastFingerprint = null;
    _lastForced = null;
    _serviceMissing = false;
  }

  /// Registers button handlers. Safe to call repeatedly — the newest wins.
  static Future<void> attach(MediaSessionActions actions) async {
    _actions = actions;
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler(_onNativeMessage);
  }

  /// Clears handlers and takes the notification down.
  static Future<void> detach() async {
    _actions = const MediaSessionActions();
    await hide();
    if (!_attached) return;
    _attached = false;
    _channel.setMethodCallHandler(null);
  }

  static Future<void> publish(
    MediaSessionState state, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final fingerprint = state.fingerprint;
    if (!force) {
      // Same visible content → nothing to do; a fast-forwarded clock only
      // matters once it crosses the 5s bucket or the throttle window.
      if (fingerprint == _lastFingerprint &&
          now.difference(_lastPublish) < _throttle) {
        return;
      }
      if (fingerprint == _lastForced &&
          now.difference(_lastPublish) < _throttle) {
        return;
      }
    }
    _lastPublish = now;
    _lastFingerprint = fingerprint;
    if (force) _lastForced = fingerprint;

    final ok = await _invoke('show', state.toMap());
    if (ok) {
      _running = true;
      return;
    }
    // Nothing reached the service — forget the throttle so the next tick can
    // try again instead of being told "already published".
    _lastFingerprint = null;
    _lastForced = null;
    _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Takes the notification down (nothing is playing any more).
  static Future<void> hide() async {
    if (!_running) return;
    _running = false;
    _lastFingerprint = null;
    _lastForced = null;
    _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);
    final ok = await _invoke('hide');
    if (!ok && !_serviceMissing) {
      // The service refused the message but exists, so it may still be
      // showing — let a later hide retry rather than declaring ourselves clean.
      _running = true;
    }
  }

  static Future<void> _onNativeMessage(MethodCall call) async {
    switch (call.method) {
      case 'onPlayPause':
        final mode = call.arguments as String?;
        if (mode == 'play') {
          await _actions.onPlay?.call();
        } else if (mode == 'pause') {
          await _actions.onPause?.call();
        } else {
          await _actions.onToggle?.call();
        }
      case 'onNext':
        await _actions.onNext?.call();
      case 'onPrev':
        await _actions.onPrev?.call();
      case 'onSeek':
        final delta = (call.arguments as num?)?.toInt() ?? 0;
        await _actions.onSeekRelative?.call(delta);
      case 'onSeekTo':
        final at = (call.arguments as num?)?.toInt() ?? 0;
        await _actions.onSeekAbsolute?.call(at);
      case 'onStop':
        await _actions.onStop?.call();
      case 'onFocusLost':
        // Another app took the audio (call, assistant). Losing that fight on
        // purpose is the polite behaviour — pause and let Dart tell the UI.
        await _actions.onFocusLost?.call();
      default:
        break;
    }
  }

  static Future<bool> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod(method, args);
      _serviceMissing = false;
      return true;
    } on PlatformException catch (e) {
      // A refused foreground start (Android 12 background limits) still
      // leaves playback untouched — just note it.
      debugPrint('[MediaSessionBridge] $method failed: ${e.code}');
      return false;
    } on MissingPluginException {
      // Not an Android build (or the service is absent): silently skip.
      _serviceMissing = true;
      _running = false;
      return false;
    }
  }
}

/// Keeps the media notification in step with the music player.
///
/// The controller is a [ChangeNotifier], so we listen for state changes AND
/// tick a timer while playing — the position bar would otherwise freeze.
class MusicMediaSessionWatcher {
  MusicMediaSessionWatcher(this.controller);

  final MusicPlayerController controller;
  Timer? _ticker;
  bool _started = false;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> start() async {
    if (!isSupported || _started) return;
    _started = true;

    await MediaSessionBridge.attach(
      MediaSessionActions(
        onToggle: controller.togglePlayPause,
        onPlay: controller.play,
        onPause: controller.pause,
        onNext: controller.playNext,
        onPrev: controller.playPrevious,
        onSeekRelative: (deltaMs) async {
          final target = controller.position + Duration(milliseconds: deltaMs);
          await controller.seekTo(target);
        },
        onSeekAbsolute: (positionMs) =>
            controller.seekTo(Duration(milliseconds: positionMs)),
        onStop: controller.pause,
        onFocusLost: () async {
          if (controller.isPlaying) await controller.pause();
        },
      ),
    );

    controller.addListener(_onControllerChanged);
    _onControllerChanged();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _push());
  }

  void _onControllerChanged() {
    if (!_started) return;
    _push(force: controller.isPlaying == false);
  }

  Future<void> _push({bool force = false}) async {
    if (!_started) return;
    final track = controller.currentTrack;
    if (track == null) {
      await MediaSessionBridge.hide();
      return;
    }
    await MediaSessionBridge.publish(
      MediaSessionState(
        title: track.title,
        subtitle: track.artist.isNotEmpty ? track.artist : track.album,
        playing: controller.isPlaying,
        positionMs: controller.position.inMilliseconds,
        durationMs: controller.duration.inMilliseconds,
      ),
      force: force,
    );
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _ticker?.cancel();
    _ticker = null;
    controller.removeListener(_onControllerChanged);
    await MediaSessionBridge.detach();
  }
}
