import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// P18: persistent-room contract (pure client side — IDs, guards, limits).
void main() {
  group('P18: persistent rooms', () {
    test('generated IDs fit the unambiguous alphabet', () {
      for (var i = 0; i < 25; i++) {
        final id = WatchPartyService.generateRoomId();
        expect(id, hasLength(6));
        expect(WatchPartyService.validRoomId(id), isTrue,
            reason: 'generator output must always validate: $id');
      }
    });

    test('room ID check forgives case/space, rejects lookalikes', () {
      expect(WatchPartyService.validRoomId('ab23cd'), isTrue);
      expect(WatchPartyService.validRoomId('  AB23CD  '), isTrue);
      // 0/O/1/I/L are excluded from the alphabet (no misreads).
      expect(WatchPartyService.validRoomId('AB01CD'), isFalse);
      expect(WatchPartyService.validRoomId('AB12CO'), isFalse);
      expect(WatchPartyService.validRoomId('SHORT'), isFalse);
      expect(WatchPartyService.validRoomId('TOOLONG1'), isFalse);
    });

    test('private-room pass is exactly 6 digits', () {
      expect(WatchPartyService.validPass('123456'), isTrue);
      expect(WatchPartyService.validPass(' 123456 '), isTrue);
      expect(WatchPartyService.validPass('12345'), isFalse);
      expect(WatchPartyService.validPass('abcdef'), isFalse);
      expect(WatchPartyService.validPass(''), isFalse);
    });

    test('v1 room size stays 20 (client mirror of server cap)', () {
      expect(WatchPartyService.maxMembers, 20);
    });
  });
}
