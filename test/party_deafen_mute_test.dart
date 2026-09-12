import 'package:dizzy/services/watchparty/party_voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// P18: deafen/mute Discord rules — no room needed (all three exercise the
/// local-state early returns, so no LiveKit in unit tests).
void main() {
  group('P18: deafen/mute', () {
    test('deafen sticks locally with no room joined', () async {
      try {
        await PartyVoiceService.setDeafened(true);
        expect(PartyVoiceService.deafened.value, isTrue);
        await PartyVoiceService.setDeafened(false);
        expect(PartyVoiceService.deafened.value, isFalse);
      } finally {
        PartyVoiceService.deafened.value = false;
      }
    });

    test('mic cannot turn on while deafened (undeafen first)', () async {
      PartyVoiceService.deafened.value = true;
      PartyVoiceService.micOn.value = false;
      try {
        await PartyVoiceService.setMicEnabled(true);
        expect(PartyVoiceService.micOn.value, isFalse,
            reason: 'Discord rule: deafened mic stays off');
      } finally {
        PartyVoiceService.deafened.value = false;
      }
    });

    test('mic toggle with no room is a silent no-op', () async {
      PartyVoiceService.micOn.value = false;
      await PartyVoiceService.toggleMic();
      expect(PartyVoiceService.micOn.value, isFalse);
    });
  });
}
