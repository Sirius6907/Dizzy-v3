import 'package:dizzy/services/watchparty/party_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P11: chat soul (pure parts)', () {
    test('allowedEmoji is the server 8 (order matters for UI row)', () {
      expect(PartyChatService.allowedEmoji,
          ['❤️', '😂', '😮', '😢', '😡', '👍', '👏', '🎉']);
    });

    test('parseReactions: server shape → counts', () {
      expect(
        PartyChatService.parseReactions({
          '❤️': ['u1', 'u2'],
          '😂': ['u3'],
        }),
        {'❤️': 2, '😂': 1},
      );
    });

    test('parseReactions: forgiving (int map, garbage)', () {
      expect(PartyChatService.parseReactions({'👍': 4}), {'👍': 4});
      expect(PartyChatService.parseReactions({'👍': 0}), isEmpty);
      expect(PartyChatService.parseReactions({'👍': []}), isEmpty);
      expect(PartyChatService.parseReactions(null), isEmpty);
      expect(PartyChatService.parseReactions('junk'), isEmpty);
      expect(PartyChatService.parseReactions({'x' * 20: ['u']}), isEmpty,
          reason: 'overlong keys rejected');
    });

    test('message carries reply fields + counts, old JSON still fine', () {
      final m = PartyChatMessage.fromJson({
        'id': 'm1',
        'sender_id': 'u1',
        'sender_code': '4820193',
        'body': 'agreed!',
        'created_at': '2026-09-12T10:00:00Z',
        'reply_to_id': 'm0',
        'reply_preview': 'interval in 5 min',
        'reply_to_code': '1111111',
        'reactions': {
          '❤️': ['u1', 'u2', 'u3']
        },
      });
      expect(m.replyToId, 'm0');
      expect(m.replyPreview, 'interval in 5 min');
      expect(m.replyName, 'DIZ-1111111');
      expect(m.reactions, {'❤️': 3});

      final old = PartyChatMessage.fromJson({'id': 'm2'});
      expect(old.replyToId, isNull);
      expect(old.replyPreview, isNull);
      expect(old.reactions, isEmpty);
      expect(old.replyName, 'Guest');
    });
  });
}
