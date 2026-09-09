import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatchParty lobby (WP-P1)', () {
    test('validRoomId accepts 6-char unambiguous codes', () {
      expect(WatchPartyService.validRoomId('K7Q2M9'), isTrue);
      expect(WatchPartyService.validRoomId('k7q2m9'), isTrue);
      expect(WatchPartyService.validRoomId('  K7Q2M9  '), isTrue);
    });

    test('validRoomId rejects ambiguous chars + wrong lengths', () {
      expect(WatchPartyService.validRoomId(''), isFalse);
      expect(WatchPartyService.validRoomId('K7Q2M'), isFalse);
      expect(WatchPartyService.validRoomId('K7Q2M99'), isFalse);
      // 0, O, 1, I are not in the alphabet (L is valid).
      expect(WatchPartyService.validRoomId('K7Q2M0'), isFalse);
      expect(WatchPartyService.validRoomId('K7Q2MO'), isFalse);
      expect(WatchPartyService.validRoomId('K7Q2M1'), isFalse);
      expect(WatchPartyService.validRoomId('K7Q2MI'), isFalse);
      expect(WatchPartyService.validRoomId('K7Q2ML'), isTrue);
      expect(WatchPartyService.validRoomId('K7Q-29'), isFalse);
    });

    test('generateRoomId always passes validRoomId', () {
      for (var i = 0; i < 50; i++) {
        expect(
          WatchPartyService.validRoomId(WatchPartyService.generateRoomId()),
          isTrue,
        );
      }
    });

    test('fromJson carries member_count, defaults 0', () {
      final withCount = WatchPartyRoom.fromJson({
        'room_id': 'K7Q2M9',
        'title': 'Movie night',
        'visibility': 'public',
        'status': 'live',
        'member_count': 7,
      });
      expect(withCount.memberCount, 7);
      expect(withCount.isPrivate, isFalse);

      final withoutCount = WatchPartyRoom.fromJson({'room_id': 'ABC234'});
      expect(withoutCount.memberCount, 0);
      expect(withoutCount.title, 'Watch Party');
    });
  });
}
