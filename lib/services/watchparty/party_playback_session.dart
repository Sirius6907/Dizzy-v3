import 'dart:async';
import 'dart:convert';

import '../cloud/watch_party_service.dart';
import '../errors/app_error_log.dart';
import 'party_session.dart';
import 'watch_sync_engine.dart';

/// v1.2.0-T2.8: party playback wiring (host heartbeat + guest follow +
/// auto-reconnect). Player-agnostic: the player supplies small callbacks,
/// this session handles all party math + transport.
///
/// Host: every 500ms broadcasts host_state (position + playing + speed).
/// Play/pause/seek actions also send immediate events.
/// Guest: listens, applies silent resync (1.5s drift auto-fix, 5s+ toast),
/// follows play/pause, switches audio by language code.
/// Net cut: auto-reconnect channel with backoff (1s, 2s, 4s, max 3).
class PartyPlaybackSession {
  PartyPlaybackSession({
    required this.getPositionMs,
    required this.isPlaying,
    required this.getSpeed,
    this.getAudioLang,
    required this.seekToMs,
    required this.setPlaying,
    this.onToast,
    this.onGuestMediaSwitch,
  });

  final int Function() getPositionMs;
  final bool Function() isPlaying;
  final double Function() getSpeed;
  final String? Function()? getAudioLang;
  final Future<void> Function(int ms) seekToMs;
  final Future<void> Function(bool play) setPlaying;
  final void Function(String msg)? onToast;
  final Future<void> Function(WatchSyncMessage msg)? onGuestMediaSwitch;

  Timer? _heartbeat;
  StreamSubscription<WatchPartyEvent>? _sub;
  int _reconnectAttempts = 0;
  bool _running = false;

  /// v1.2.0-P3: how many player-bound sessions are alive (guest-in-player?).
  static int activeCount = 0;

  static const _maxReconnect = 3;
  static const _backoff = [1, 2, 4];

  bool get running => _running;

  void start() {
    if (_running) return;
    _running = true;
    activeCount++;
    final s = PartySession.instance;
    if (s.inParty && s.isHost) {
      _heartbeat = Timer.periodic(
        const Duration(milliseconds: WatchSyncEngine.heartbeatIntervalMs),
        (_) => _broadcastHostState(),
      );
    }
    if (s.inParty && !s.isHost) {
      _sub = WatchPartyService.events.listen(_onEvent);
    }
  }

  Future<void> stop() async {
    final wasRunning = _running;
    _running = false;
    if (wasRunning && activeCount > 0) activeCount--;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _sub?.cancel();
    _sub = null;
    _reconnectAttempts = 0;
  }

  /// Host: immediate event on user action (play/pause/seek).
  Future<void> sendAction(String type, {int? positionMs}) async {
    final s = PartySession.instance;
    if (!s.inParty || !s.isHost) return;
    if (type == 'host_state') {
      await _broadcastHostState();
      return;
    }
    await WatchPartyService.sendControl(
      type: type,
      positionMs: positionMs ?? getPositionMs(),
    );
  }

  /// v1.2.0-P2: host announces "I am now playing X" (any title, any time).
  /// One call does all three: local session state + realtime event for guests
  /// + DB "now watching" row (fail-soft each). Unlimited titles per room.
  /// P10: [prefetchReady]=true marks prefetch-verified titles (guest prewarms).
  /// [previewOnly]=true sends ONLY the realtime event (upcoming-title hint):
  /// local session + DB row stay untouched so the real announce still fires.
  Future<void> announceMedia({
    required String ref,
    String? title,
    int? season,
    int? episode,
    bool prefetchReady = false,
    bool previewOnly = false,
  }) async {
    final s = PartySession.instance;
    if (!s.inParty || !s.isHost) return;
    if (!previewOnly) {
      s.switchMedia(mediaRef: ref, mediaTitle: title, season: season, episode: episode);
      // ignore: unawaited_futures
      WatchPartyService.updateCurrentMedia(
        roomId: s.room!.roomId,
        ref: ref,
        title: title,
      );
    }
    try {
      await WatchPartyService.sendControl(
        type: 'media_switch',
        positionMs: 0,
        text: jsonEncode(WatchSyncMessage(
          mediaRef: ref,
          mediaTitle: title,
          season: season,
          episode: episode,
          positionMs: 0,
          playing: true,
          hostSentAtMs: DateTime.now().millisecondsSinceEpoch,
          prefetchReady: prefetchReady,
        ).toJson()),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _broadcastHostState() async {
    final s = PartySession.instance;
    if (!s.inParty || !s.isHost || s.mediaRef == null) return;
    try {
      await WatchPartyService.sendControl(
        type: 'host_state',
        positionMs: getPositionMs(),
        text: jsonEncode(WatchSyncMessage(
          mediaRef: s.mediaRef!,
          positionMs: getPositionMs(),
          playing: isPlaying(),
          speed: getSpeed(),
          audioTrack: getAudioLang?.call(),
          hostSentAtMs: DateTime.now().millisecondsSinceEpoch,
        ).toJson()),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _onEvent(WatchPartyEvent event) async {
    final s = PartySession.instance;
    if (!s.inParty || s.isHost) return;
    _reconnectAttempts = 0; // traffic = alive
    if (event.type == 'host_state' && event.text != null) {
      WatchSyncMessage msg;
      try {
        msg = WatchSyncMessage.fromJson(
            Map<String, dynamic>.from(jsonDecode(event.text!)));
      } catch (_) {
        // P15: malformed realtime payload — silent-but-logged (parse class).
        unawaited(AppErrorLog.log(
            code: 'sync_msg_parse', screen: 'party'));
        return;
      }
      if (!msg.isUsable) return;
      // Media gate: different title → ask player to open host's media.
      if (msg.mediaRef != s.mediaRef) {
        s.setGuestMedia(
          mediaRef: msg.mediaRef,
          mediaTitle: msg.mediaTitle,
          season: msg.season,
          episode: msg.episode,
        );
        await onGuestMediaSwitch?.call(msg);
        return;
      }
      final target = WatchSyncEngine.targetPosition(
        hostPositionMs: msg.positionMs,
        hostSentAtMs: msg.hostSentAtMs,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        // v1.2.0: no join-time clock ping yet — 0 offset is conservative
        // (guest may sit up to ~RTT behind, inside the 1.5s tolerance).
        clockOffsetMs: 0,
      );
      final resync = WatchSyncEngine.resyncPosition(
        guestPositionMs: getPositionMs(),
        targetPositionMs: target,
      );
      if (resync != null) await seekToMs(resync);
      if (WatchSyncEngine.shouldToast(getPositionMs(), target)) {
        onToast?.call('Catching up…');
      }
      if (msg.playing != isPlaying()) await setPlaying(msg.playing);
    } else if (event.type == 'play') {
      await setPlaying(true);
    } else if (event.type == 'pause') {
      await setPlaying(false);
    } else if (event.type == 'seek' && event.positionMs != null) {
      await seekToMs(event.positionMs!);
    } else if (event.type == 'media_switch' && event.text != null) {
      try {
        final msg = WatchSyncMessage.fromJson(
            Map<String, dynamic>.from(jsonDecode(event.text!)));
        // P10: ready-hint is GuestFollowService's (prewarm only) — the player
        // stays quiet until the real switch lands. Never set guest media early:
        // that would make the follow-service skip the real open as "same".
        if (msg.prefetchReady) return;
        if (msg.isUsable) {
          s.setGuestMedia(
            mediaRef: msg.mediaRef,
            mediaTitle: msg.mediaTitle,
            season: msg.season,
            episode: msg.episode,
          );
          await onGuestMediaSwitch?.call(msg);
        }
      } catch (_) {}
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnect) {
      onToast?.call('Reconnecting… tap Retry if stuck.');
      return;
    }
    final delay = _backoff[_reconnectAttempts.clamp(0, _backoff.length - 1)];
    _reconnectAttempts++;
    onToast?.call('Reconnecting…');
    Future.delayed(Duration(seconds: delay), () async {
      final s = PartySession.instance;
      if (!_running || !s.inParty || s.room == null) return;
      try {
        await WatchPartyService.connect(s.room!);
        _reconnectAttempts = 0;
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  /// Test hook: backoff delays for attempt n (0-based).
  static int backoffForAttempt(int n) =>
      _backoff[n.clamp(0, _backoff.length - 1)];
}
