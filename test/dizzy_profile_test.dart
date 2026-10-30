import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/profiles/dizzy_profile.dart';

void main() {
  group('S3B DizzyProfile model', () {
    test('JSON round-trip preserves profile fields', () {
      final p = DizzyProfile(
        id: 'p1',
        name: 'Kid',
        avatar: '🧸',
        isKids: true,
        pinHash: 'hashed',
        createdAt: DateTime.utc(2026, 9, 8),
      );
      final restored = DizzyProfile.fromJson(p.toJson());
      expect(restored.id, 'p1');
      expect(restored.isKids, isTrue);
      expect(restored.hasPin, isTrue);
      expect(restored.avatar, '🧸');
    });

    test('cloud JSON never includes raw PIN', () {
      final p = DizzyProfile(
        id: 'p1',
        name: 'Main',
        avatar: '✨',
        isKids: false,
        pinHash: 'sha256-only',
        createdAt: DateTime.now(),
      );
      final cloud = p.toCloudJson();
      expect(cloud.containsKey('pin'), isFalse);
      expect(cloud['pin_hash'], 'sha256-only');
    });

    test('v1.3.3: cloud profile_id maps to id + updatedAt parses', () {
      final cloud = {
        'user_id': 'u1',
        'profile_id': 'p9',
        'name': 'Night Owl',
        'avatar': '🌙',
        'is_kids': false,
        'pin_hash': null,
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-12T00:00:00Z',
      };
      final restored = DizzyProfile.fromJson(cloud);
      expect(restored.id, 'p9');
      expect(restored.name, 'Night Owl');
      expect(restored.updatedAt.isAfter(restored.createdAt), isTrue);
    });

    test('v1.3.3: missing updatedAt falls back to createdAt', () {
      final p = DizzyProfile(
        id: 'p1',
        name: 'Main',
        avatar: '✨',
        isKids: false,
        createdAt: DateTime.utc(2026, 10, 1),
      );
      final restored = DizzyProfile.fromJson(p.toJson()..remove('updatedAt'));
      expect(restored.updatedAt, restored.createdAt);
    });

    test('v1.3.3: rename bumps updatedAt via copyWith', () {
      final p = DizzyProfile(
        id: 'p1',
        name: 'Old',
        avatar: '✨',
        isKids: false,
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      );
      final next = p.copyWith(
        name: 'New',
        updatedAt: DateTime.utc(2026, 10, 12),
      );
      expect(next.name, 'New');
      expect(next.updatedAt.isAfter(p.updatedAt), isTrue);
    });
  });
}
