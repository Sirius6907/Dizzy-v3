import 'package:dizzy/services/watchparty/party_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PartyChatService (WP-P4)', () {
    test('validBody trims and caps at 500', () {
      expect(PartyChatService.validBody('hi'), isTrue);
      expect(PartyChatService.validBody('   '), isFalse);
      expect(PartyChatService.validBody(''), isFalse);
      expect(PartyChatService.validBody('a' * 500), isTrue);
      expect(PartyChatService.validBody('a' * 501), isFalse);
      expect(PartyChatService.validBody('  hi  '), isTrue);
    });

    test('isExpired hides messages older than 24h', () {
      final now = DateTime.utc(2026, 9, 9, 12);
      expect(
        PartyChatService.isExpired(
            DateTime.utc(2026, 9, 9, 11, 59),
            now: now),
        isFalse,
      );
      expect(
        PartyChatService.isExpired(
            DateTime.utc(2026, 9, 8, 12),
            now: now),
        isTrue,
      );
      expect(
        PartyChatService.isExpired(
            DateTime.utc(2026, 9, 8, 11),
            now: now),
        isTrue,
      );
    });

    test('message display names never leak uuid', () {
      final withCode = PartyChatMessage.fromJson({
        'id': '1',
        'sender_id': 'some-uuid-1234',
        'sender_code': '4820193',
        'body': 'hi',
        'created_at': '2026-09-09T11:00:00Z',
      });
      expect(withCode.displayName, 'DIZ-4820193');
      expect(withCode.displayName.contains('uuid'), isFalse);

      final noCode = PartyChatMessage.fromJson({
        'id': '2',
        'sender_id': 'other-uuid',
        'body': 'hey',
        'created_at': '2026-09-09T11:00:00Z',
      });
      expect(noCode.displayName, 'Guest');
    });

    test('fromJson junk timestamps become expired epoch', () {
      final junk = PartyChatMessage.fromJson({'id': '3'});
      expect(junk.body, isEmpty);
      expect(
        PartyChatService.isExpired(junk.createdAt,
            now: DateTime.utc(2026, 9, 9)),
        isTrue,
      );
    });

    test('member host flag + display name', () {
      const host = PartyMember(
          userId: 'u1', role: 'host', deviceCode: '1111111');
      expect(host.isHost, isTrue);
      expect(host.displayName, 'DIZ-1111111');
      const guest =
          PartyMember(userId: 'u2', role: 'member', deviceCode: null);
      expect(guest.isHost, isFalse);
      expect(guest.displayName, 'Guest');
    });
  });
}
