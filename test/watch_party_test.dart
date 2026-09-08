import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/cloud/watch_party_service.dart';

void main() {
  group('S3C WatchParty primitives', () {
    test('Room IDs are six safe uppercase characters', () {
      final id = WatchPartyService.generateRoomId();
      expect(id, hasLength(6));
      expect(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$').hasMatch(id), isTrue);
    });

    test('only exact six-digit private passes are valid', () {
      expect(WatchPartyService.validPass('123456'), isTrue);
      expect(WatchPartyService.validPass('12345'), isFalse);
      expect(WatchPartyService.validPass('1234567'), isFalse);
      expect(WatchPartyService.validPass('abcdef'), isFalse);
    });

    test('pass hash is deterministic and does not return raw pass', () {
      final hash = WatchPartyService.hashPass('123456');
      expect(hash, isNot('123456'));
      expect(hash, WatchPartyService.hashPass('123456'));
      expect(hash, hasLength(64));
    });

    test('control event round trips safely', () {
      final source = WatchPartyEvent(
        type: 'seek',
        positionMs: 34567,
        sentAt: DateTime.utc(2026, 9, 8),
      );
      final restored = WatchPartyEvent.fromJson(source.toJson());
      expect(restored.type, 'seek');
      expect(restored.positionMs, 34567);
    });
  });
}
