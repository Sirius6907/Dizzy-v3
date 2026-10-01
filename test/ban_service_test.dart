import 'package:dizzy/services/moderation/ban_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase D — ban levels, expiry, escalation parsing (pure, no network).
void main() {
  group('BanState.fromRpc', () {
    test('parses full ban with days left', () {
      final s = BanState.fromRpc(
          {'level': 'full', 'days_left': 7, 'reason': 'spam'});
      expect(s.level, BanLevel.full);
      expect(s.daysLeft, 7);
      expect(s.blocksEverything, isTrue);
      expect(s.easyEnglish, contains('7 more days'));
      expect(s.easyEnglish, contains('spam'));
    });

    test('parses permanent ban (days_left -1)', () {
      final s = BanState.fromRpc({'level': 'full', 'days_left': -1});
      expect(s.isBanned, isTrue);
      expect(s.easyEnglish, contains('permanently'));
    });

    test('social level blocks only social, not everything', () {
      final s = BanState.fromRpc({'level': 'social', 'days_left': 3});
      expect(s.blocksSocial, isTrue);
      expect(s.blocksEverything, isFalse);
      expect(s.easyEnglish, contains('Friends and rooms are paused'));
    });

    test('expired / none → not banned', () {
      expect(BanState.fromRpc({'level': 'none'}).isBanned, isFalse);
      expect(BanState.fromRpc(null).isBanned, isFalse);
      expect(BanState.fromRpc('garbage').isBanned, isFalse);
      expect(BanState.fromRpc({'level': 'weird'}).isBanned, isFalse);
    });

    test('days_left 0 with a level = <24h left, still banned', () {
      final s = BanState.fromRpc({'level': 'full', 'days_left': 0});
      expect(s.isBanned, isTrue);
      expect(s.easyEnglish, contains('until review'));
    });

    test('malformed days_left falls back to 0, never throws', () {
      final s =
          BanState.fromRpc({'level': 'full', 'days_left': 'not-a-number'});
      expect(s.daysLeft, 0);
      expect(s.isBanned, isTrue);
    });
  });

  group('escalation (offence history shape)', () {
    test('server increments offence_count; state stays level-driven', () {
      // 1st offence social → 2nd offence full (server side, admin_ban_user).
      // App only ever sees the resulting level — pin that behaviour.
      const first = BanState(level: BanLevel.social, daysLeft: 7);
      const second = BanState(level: BanLevel.full, daysLeft: -1);
      expect(first.blocksSocial, isTrue);
      expect(second.blocksEverything, isTrue);
      expect(first.easyEnglish == second.easyEnglish, isFalse);
    });
  });
}
