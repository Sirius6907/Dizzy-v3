import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'party_voice_service.dart';

/// Phase K3 — bridge between LiveKit voice state and the Android microphone
/// foreground service.
///
/// Android's own contract: while a `foregroundServiceType="microphone"`
/// service is running the mic thread survives the screen going off. We start
/// it the moment voice connects and stop it the moment voice drops, so the
/// ongoing-call notification is never lying about the mic state.
class VoiceBackgroundGate {
  VoiceBackgroundGate._();

  static const MethodChannel _channel = MethodChannel(
    'com.sirius6907.dizzyv3/voice',
  );

  static bool _attached = false;
  static bool _running = false;
  static String? _lastRoom;

  /// True while our own service is believed to be running (test/debug seam).
  static bool get isRunning => _running;

  /// Test seam: forget every latch so a test can drive the gate from a
  /// known-cold state.
  @visibleForTesting
  static void resetForTest() {
    _attached = false;
    _running = false;
    _lastRoom = null;
    PartyVoiceService.connected.removeListener(_sync);
  }

  static Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    PartyVoiceService.connected.addListener(_sync);
    await _sync();
  }

  static Future<void> detach() async {
    PartyVoiceService.connected.removeListener(_sync);
    _attached = false;
    await _stop();
  }

  static Future<void> _sync() async {
    if (PartyVoiceService.connected.value) {
      final room = PartyVoiceService.currentRoomCode ?? _lastRoom ?? '';
      // Already running for this same room — nothing to restart, otherwise
      // the notification would flicker on every reconnect event.
      if (_running && room == _lastRoom) return;
      await _start(room);
    } else {
      await _stop();
    }
  }

  static Future<void> _start(String room) async {
    try {
      await _channel.invokeMethod('start', {'room': room});
      _running = true;
      _lastRoom = room;
    } catch (e) {
      // Fail-soft: voice still works, it just may not survive the screen
      // turning off. Never let a platform channel break the call itself.
      debugPrint('[VoiceBackgroundGate] start failed: $e');
      _running = false;
    }
  }

  static Future<void> _stop() async {
    if (!_running) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('[VoiceBackgroundGate] stop failed: $e');
    }
    _running = false;
  }
}
