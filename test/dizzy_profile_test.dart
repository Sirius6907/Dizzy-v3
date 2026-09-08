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
  });
}
