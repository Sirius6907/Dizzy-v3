import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DizzySocialService (Phase 1 + 2)', () {
    group('getThreadId (deterministic)', () {
      test('consistent regardless of argument order', () {
        final a = DizzySocialService.getThreadId('user_a', 'user_b');
        final b = DizzySocialService.getThreadId('user_b', 'user_a');
        expect(a, equals(b));
      });

      test('format is dm:{uid1}_{uid2}', () {
        final tid = DizzySocialService.getThreadId('alpha', 'beta');
        expect(tid, startsWith('dm:'));
        expect(tid, contains('_'));
      });

      test('sorts ids lexicographically', () {
        final tid = DizzySocialService.getThreadId('zebra', 'apple');
        // 'apple' < 'zebra' so thread should be dm:apple_zebra
        expect(tid, 'dm:apple_zebra');
      });

      test('same user gives predictable thread', () {
        final tid = DizzySocialService.getThreadId('u1', 'u1');
        expect(tid, 'dm:u1_u1');
      });
    });

    group('claimUsername (fail-soft)', () {
      test('returns failure when cloud unavailable', () async {
        final res = await DizzySocialService.claimUsername('test_user');
        expect(res['success'], isFalse);
      });
    });

    group('searchUsers (fail-soft + guard)', () {
      test('returns empty for short query', () async {
        final results = await DizzySocialService.searchUsers('a');
        expect(results, isEmpty);
      });

      test('returns empty for empty query', () async {
        final results = await DizzySocialService.searchUsers('');
        expect(results, isEmpty);
      });

      test('returns empty when cloud unavailable', () async {
        final results = await DizzySocialService.searchUsers('testuser');
        expect(results, isEmpty);
      });

      test('handles whitespace-only query', () async {
        final results = await DizzySocialService.searchUsers('   ');
        expect(results, isEmpty);
      });
    });

    group('sendDirectMessage (fail-soft)', () {
      test('returns false when cloud unavailable', () async {
        final result = await DizzySocialService.sendDirectMessage(
          recipientUid: 'user_b',
          body: 'hello',
        );
        expect(result, isFalse);
      });

      test('returns false with empty body', () async {
        final result = await DizzySocialService.sendDirectMessage(
          recipientUid: 'user_b',
          body: '',
        );
        expect(result, isFalse);
      });

      test('returns false with null current user', () async {
        final result = await DizzySocialService.sendDirectMessage(
          recipientUid: 'user_b',
          body: 'hello',
        );
        expect(result, isFalse);
      });
    });

    group('currentUsername', () {
      test('starts as null', () {
        expect(DizzySocialService.currentUsername.value, isNull);
      });
    });
  });
}
