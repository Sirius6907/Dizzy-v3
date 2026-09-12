import 'package:dizzy/services/watchparty/party_voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PartyVoiceService (WP-P3)', () {
    test('token request carries normalized room + device + role', () {
      final req = PartyVoiceService.buildTokenRequest(
          'k7q2m9', '4820193', true);
      expect(req['room_code'], 'K7Q2M9');
      expect(req['device_code'], '4820193');
      expect(req['wants_publish'], isTrue);

      final guest =
          PartyVoiceService.buildTokenRequest('ABC234', '1000001', false);
      expect(guest['wants_publish'], isFalse);
    });

    test('host publishes, guest subscribes-only', () {
      final host = PartyVoiceService.grantsFor(true);
      expect(host['roomJoin'], isTrue);
      expect(host['canPublish'], isTrue);
      expect(host['canSubscribe'], isTrue);

      final guest = PartyVoiceService.grantsFor(false);
      expect(guest['roomJoin'], isTrue);
      expect(guest['canPublish'], isFalse);
      expect(guest['canSubscribe'], isTrue);
    });

    test('starts disconnected, mic off, no speakers', () {
      expect(PartyVoiceService.connected.value, isFalse);
      expect(PartyVoiceService.micOn.value, isFalse);
      expect(PartyVoiceService.speakingIds.value, isEmpty);
      expect(PartyVoiceService.currentRoomCode, isNull);
    });
  });

  group('P4: deafen + per-user mute (pure)', () {
    test('mute-user request shape', () {
      final req = PartyVoiceService.muteUserRequest('k7q2m9', 'DEV123');
      expect(req['room_code'], 'K7Q2M9');
      expect(req['action'], 'mute_user');
      expect(req['target_identity'], 'DEV123');
    });

    test('deafen with no room only flips the flag (fail-soft)', () async {
      PartyVoiceService.deafened.value = false;
      await PartyVoiceService.setDeafened(true);
      expect(PartyVoiceService.deafened.value, isTrue);
      await PartyVoiceService.setDeafened(false);
      expect(PartyVoiceService.deafened.value, isFalse);
    });

    test('muteUser with no room/host returns false, never throws', () async {
      expect(await PartyVoiceService.muteUser('DEV123'), isFalse);
      expect(await PartyVoiceService.muteUser(''), isFalse);
    });

    test('remoteIds empty when disconnected', () {
      expect(PartyVoiceService.remoteIds, isEmpty);
    });
  });
}
