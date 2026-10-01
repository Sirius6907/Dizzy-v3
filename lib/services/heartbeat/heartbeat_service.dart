import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../cloud/remote_config_service.dart';
import '../download/download_service.dart';
import '../media/global_media_coordinator.dart';
import '../music/music_player_controller.dart';
import '../device/device_identity_v2.dart';
import '../watchparty/party_session.dart';
import '../watchparty/voice_background_gate.dart';
import 'heartbeat_policy.dart';

/// Phase L2 — presence + coarse activity for the admin fleet view.
///
/// Cadence: one presence beat every `heartbeat_interval_s` (default 5 min,
/// ±10% jitter) plus an immediate beat when the derived activity actually
/// changes — the server no-ops identical beats inside 60s, so a chatty
/// client still cannot become a write faucet.
///
/// Offline: at most ONE beat is held (last activity wins) and flushed on
/// reconnect; we never queue a backlog.
///
/// Consent OFF: no beats at all — only the boot-time `last_seen_at` ages.
/// That is the designed privacy degradation, not a failure mode.
///
/// Everything that can fail does so silently: a heartbeat is telemetry, and
/// telemetry must never be able to break the app.
class HeartbeatService {
  HeartbeatService._();

  static final HeartbeatService instance = HeartbeatService._();

  static const String _consentKey = 'heartbeat_consent';

  Timer? _presenceTimer;
  Timer? _probeTimer;
  bool _started = false;
  bool _consent = true;
  bool _pending = false;
  Activity _pendingActivity = Activity.idle;
  Activity _lastSent = Activity.idle;
  int _lastSentMs = 0;
  Activity _announced = Activity.idle;
  Activity _explicit = Activity.idle;
  String _hwid = '';
  bool _sending = false;

  /// Settings → Privacy binds to this (mirrors `consent`).
  final ValueNotifier<bool> consentNotifier = ValueNotifier<bool>(true);

  bool get consent => _consent;
  bool get hasPendingBeat => _pending;
  bool get started => _started;

  @visibleForTesting
  void resetForTest() {
    _presenceTimer?.cancel();
    _probeTimer?.cancel();
    _presenceTimer = null;
    _probeTimer = null;
    _started = false;
    _consent = true;
    _pending = false;
    _pendingActivity = Activity.idle;
    _lastSent = Activity.idle;
    _lastSentMs = 0;
    _announced = Activity.idle;
    _explicit = Activity.idle;
    _hwid = '';
    _sending = false;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final prefs = await SharedPreferences.getInstance();
    _consent = prefs.getBool(_consentKey) ?? true;
    consentNotifier.value = _consent;
    if (!_consent) return;

    try {
      final identity = await DeviceIdentityV2.stableHwid();
      _hwid = identity.hash;
    } catch (e) {
      debugPrint('[Heartbeat] identity unavailable: $e');
      _hwid = '';
    }

    _schedule();
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(
      const Duration(seconds: HeartbeatPolicy.activityProbeSeconds),
      (_) => unawaited(_onProbe()),
    );
  }

  /// The privacy switch (Settings → Privacy). Turning it OFF stops every
  /// future beat immediately; turning it ON resumes on the normal cadence.
  Future<void> setConsent(bool allow) async {
    _consent = allow;
    consentNotifier.value = allow;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentKey, allow);
    } catch (e) {
      debugPrint('[Heartbeat] consent persist failed: $e');
    }

    if (!allow) {
      _presenceTimer?.cancel();
      _presenceTimer = null;
      _pending = false;
      return;
    }
    if (!_started) {
      await start();
      return;
    }
    if (_hwid.isNotEmpty && _probeTimer == null) {
      _probeTimer = Timer.periodic(
        const Duration(seconds: HeartbeatPolicy.activityProbeSeconds),
        (_) => unawaited(_onProbe()),
      );
    }
    _schedule();
    await beat(force: true);
  }

  /// Pages declare what only they can know (reader = reading, audiobook
  /// playing = listening). Passing null falls back to derived signals.
  void noteActivity(Activity? activity) {
    _explicit = activity ?? Activity.idle;
    unawaited(beat());
  }

  void noteReading() => noteActivity(Activity.reading);
  void clearReading() => noteActivity(Activity.idle);

  void noteAudiobook({required bool playing}) =>
      noteActivity(playing ? Activity.listening : Activity.idle);

  /// Derive the coarsest honest answer from signals the app already keeps.
  Activity derive() {
    // A live mic outranks everything: the user is in voice right now.
    if (VoiceBackgroundGate.isRunning) return Activity.inVoice;
    // A reader screen declares itself — it is the foreground surface.
    if (_explicit == Activity.reading) return Activity.reading;
    if (GlobalMediaCoordinator.instance.videoActive.value) {
      return Activity.watching;
    }
    if (PartySession.instance.inParty) return Activity.inRoom;
    if (DownloadService.instance.activeDownloadCount > 0) {
      return Activity.downloading;
    }
    final music = MusicPlayerController.instance;
    if (music.hasTrack && music.isPlaying) return Activity.listening;
    if (_explicit == Activity.listening) return Activity.listening;
    return Activity.idle;
  }

  Future<void> beat({bool force = false}) async {
    if (!_consent || _hwid.isEmpty || _sending) return;

    final activity = derive();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!HeartbeatPolicy.beatDue(
      current: activity,
      lastSent: _lastSent,
      lastSentMs: _lastSentMs,
      nowMs: now,
      force: force,
    )) {
      return;
    }

    if (!await _online()) {
      // Offline: hold ONE beat — the newest activity wins, no backlog.
      _pending = true;
      _pendingActivity = activity;
      return;
    }
    await _send(activity);
  }

  Future<void> _onProbe() async {
    if (!_consent || _hwid.isEmpty) return;

    final activity = derive();
    if (activity != _announced) {
      _announced = activity;
      await beat();
      return;
    }

    if (_pending && await _online()) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (HeartbeatPolicy.shouldFlush(
        pending: _pending,
        online: true,
        lastSentMs: _lastSentMs,
        nowMs: now,
        cooldownMs: HeartbeatPolicy.changedActivityCooldownMs,
      )) {
        await _send(_pendingActivity);
      }
    }
  }

  Future<void> _send(Activity activity) async {
    _sending = true;
    try {
      final reply = await CloudClient.db.rpc('device_heartbeat', params: {
        'p_hwid_hash': _hwid,
        'p_activity': activity.rpcKey,
      });
      if (HeartbeatPolicy.replyOk(reply)) {
        _lastSent = activity;
        _lastSentMs = DateTime.now().millisecondsSinceEpoch;
        _pending = false;
        _announced = activity;
      }
      // A non-ok reply (unknown_device before boot, throttled) is simply
      // dropped: the next cadence tick tries again, nothing loops here.
    } catch (e) {
      // Network hiccup — keep it pending so reconnect can flush it.
      _pending = true;
      _pendingActivity = activity;
      debugPrint('[Heartbeat] send failed: $e');
    } finally {
      _sending = false;
    }
  }

  void _schedule() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    if (!_consent || _hwid.isEmpty) return;

    final intervalS = RemoteConfigService.heartbeatIntervalSeconds;
    final delayMs = HeartbeatPolicy.nextDelayMs(
      intervalS,
      jitterSample: DateTime.now().millisecondsSinceEpoch,
    );
    _presenceTimer = Timer(Duration(milliseconds: delayMs), () {
      unawaited(beat());
      _schedule();
    });
  }

  Future<bool> _online() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return false;
      return !results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      // Cannot tell → attempt the send; a failure just re-pends it.
      return true;
    }
  }
}
