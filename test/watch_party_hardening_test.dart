import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatchParty hardening (WP-P5)', () {
    test('20-member cap boundary', () {
      expect(WatchPartyService.maxMembers, 20);
      expect(WatchPartyService.isFull(0), isFalse);
      expect(WatchPartyService.isFull(19), isFalse);
      expect(WatchPartyService.isFull(20), isTrue);
      expect(WatchPartyService.isFull(21), isTrue);
    });

    test('join gate helpers stay strict', () {
      // Room IDs still 6-char; pass still 6-digit (unchanged contracts).
      expect(WatchPartyService.validRoomId('K7Q2M9'), isTrue);
      expect(WatchPartyService.validRoomId('short'), isFalse);
      expect(WatchPartyService.validPass('123456'), isTrue);
      expect(WatchPartyService.validPass('12345'), isFalse);
    });
  });
}
