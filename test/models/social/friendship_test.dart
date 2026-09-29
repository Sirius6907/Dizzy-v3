import 'package:dizzy/models/social/friendship.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Friendship model', () {
    test('toJson round-trips correctly', () {
      final f = Friendship(
        requesterId: 'user-a',
        addresseeId: 'user-b',
        status: FriendStatus.pending,
        createdAt: DateTime.utc(2026, 9, 20, 12, 0, 0),
        updatedAt: DateTime.utc(2026, 9, 20, 12, 0, 0),
      );
      final json = f.toJson();
      expect(json['requester_id'], 'user-a');
      expect(json['addressee_id'], 'user-b');
      expect(json['status'], 'pending');
      expect(json['created_at'], '2026-09-20T12:00:00.000Z');
      expect(json['updated_at'], '2026-09-20T12:00:00.000Z');
    });

    test('fromJson handles accepted status', () {
      final json = {
        'requester_id': 'u1',
        'addressee_id': 'u2',
        'status': 'accepted',
        'created_at': '2026-09-20T10:00:00Z',
        'updated_at': '2026-09-20T11:00:00Z',
      };
      final f = Friendship.fromJson(json);
      expect(f.requesterId, 'u1');
      expect(f.addresseeId, 'u2');
      expect(f.status, FriendStatus.accepted);
    });

    test('fromJson defaults unknown status to pending', () {
      final json = {
        'requester_id': 'u1',
        'addressee_id': 'u2',
        'status': 'unknown_status',
        'created_at': '2026-09-20T10:00:00Z',
        'updated_at': '2026-09-20T11:00:00Z',
      };
      final f = Friendship.fromJson(json);
      expect(f.status, FriendStatus.pending);
    });

    test('fromJson handles missing timestamps', () {
      final json = {
        'requester_id': 'u1',
        'addressee_id': 'u2',
        'status': 'blocked',
      };
      final f = Friendship.fromJson(json);
      expect(f.status, FriendStatus.blocked);
      expect(f.createdAt, isNotNull);
      expect(f.updatedAt, isNotNull);
    });

    test('peerId returns addressee when self is requester', () {
      final f = Friendship(
        requesterId: 'me',
        addresseeId: 'other',
        status: FriendStatus.accepted,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(f.peerId('me'), 'other');
    });

    test('peerId returns requester when self is addressee', () {
      final f = Friendship(
        requesterId: 'other',
        addresseeId: 'me',
        status: FriendStatus.accepted,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(f.peerId('me'), 'other');
    });

    test('peerId returns requester when self matches neither (edge)', () {
      final f = Friendship(
        requesterId: 'a',
        addresseeId: 'b',
        status: FriendStatus.accepted,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // Neither matches 'me' — falls through to requesterId
      expect(f.peerId('me'), 'a');
    });
  });
}
