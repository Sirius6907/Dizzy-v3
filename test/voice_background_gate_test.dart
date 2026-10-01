import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/watchparty/party_voice_service.dart';
import 'package:dizzy/services/watchparty/voice_background_gate.dart';

/// Phase K3 — the microphone foreground service follows voice state exactly:
/// on when the mic is live, off when it drops, never doubled up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sirius6907.dizzyv3/voice');
  final calls = <MethodCall>[];
  var failNext = false;

  void armHandler() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (failNext) {
            throw PlatformException(code: 'VOICE_START', message: 'blocked');
          }
          calls.add(call);
          return true;
        });
  }

  setUp(() {
    VoiceBackgroundGate.resetForTest();
    PartyVoiceService.connected.value = false;
    PartyVoiceService.currentRoomCode = null;
    calls.clear();
    failNext = false;
    armHandler();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    VoiceBackgroundGate.resetForTest();
  });

  test('connecting starts the service once, carrying the room code', () async {
    PartyVoiceService.currentRoomCode = 'K3ABC';
    PartyVoiceService.connected.value = true;

    await VoiceBackgroundGate.attach();

    expect(calls.length, 1);
    expect(calls.single.method, 'start');
    expect((calls.single.arguments as Map)['room'], 'K3ABC');
    expect(VoiceBackgroundGate.isRunning, isTrue);
  });

  test('disconnecting stops it, and the stop is never repeated', () async {
    PartyVoiceService.currentRoomCode = 'K3ABC';
    PartyVoiceService.connected.value = true;
    await VoiceBackgroundGate.attach();
    expect(calls.length, 1);

    PartyVoiceService.connected.value = false;
    await pumpEventQueue();
    PartyVoiceService.connected.value = false;
    await pumpEventQueue();

    expect(calls.map((c) => c.method).toList(), ['start', 'stop']);
    expect(VoiceBackgroundGate.isRunning, isFalse);
  });

  test('reconnect cycles are start → stop → start, never stacked', () async {
    PartyVoiceService.currentRoomCode = 'K3ABC';
    PartyVoiceService.connected.value = true;
    await VoiceBackgroundGate.attach();

    PartyVoiceService.connected.value = false;
    await pumpEventQueue();
    PartyVoiceService.connected.value = true;
    await pumpEventQueue();

    expect(calls.map((c) => c.method).toList(), ['start', 'stop', 'start']);
    expect(VoiceBackgroundGate.isRunning, isTrue);
  });

  test('starting without a room still starts (no empty-room crash)', () async {
    PartyVoiceService.connected.value = true;
    await VoiceBackgroundGate.attach();

    expect(calls.single.method, 'start');
    expect((calls.single.arguments as Map)['room'], '');
  });

  test('a blocked platform channel never breaks voice itself', () async {
    failNext = true;
    PartyVoiceService.currentRoomCode = 'K3ABC';
    PartyVoiceService.connected.value = true;

    // Must not throw — voice keeps working, it just loses the guarantee.
    await VoiceBackgroundGate.attach();

    expect(VoiceBackgroundGate.isRunning, isFalse);
    expect(calls, isEmpty);
  });

  test('stop failure is swallowed so teardown cannot hang the call', () async {
    PartyVoiceService.currentRoomCode = 'K3ABC';
    PartyVoiceService.connected.value = true;
    await VoiceBackgroundGate.attach();
    expect(VoiceBackgroundGate.isRunning, isTrue);

    failNext = true;
    PartyVoiceService.connected.value = false;
    await pumpEventQueue();

    expect(VoiceBackgroundGate.isRunning, isFalse);
  });
}
