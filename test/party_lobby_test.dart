import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P12: lobby room aliveness', () {
    test('live room: title label + isLiveNow', () {
      final r = WatchPartyRoom.fromJson({
        'room_id': 'ABC123',
        'title': 'Friday Night',
        'current_media_ref': 'tmdb:movie:550',
        'current_title': 'Fight Club',
        'visibility': 'public',
        'status': 'live',
        'member_count': 4,
      });
      expect(r.isLiveNow, isTrue);
      expect(r.watchingLabel, 'Fight Club');
      expect(r.nowWatchingRef, 'tmdb:movie:550');
      expect(r.memberCount, 4);
    });

    test('picking room: Choosing… label, not live', () {
      final r = WatchPartyRoom.fromJson({
        'room_id': 'XYZ789',
        'title': 'Chill',
        'visibility': 'public',
        'status': 'lobby',
        'member_count': 1,
      });
      expect(r.isLiveNow, isFalse);
      expect(r.watchingLabel, 'Choosing…');
    });

    test('blank title with ref still counts live, label falls back', () {
      final r = WatchPartyRoom.fromJson({
        'room_id': 'QWE456',
        'title': 'X',
        'current_media_ref': 'tmdb:tv:123:S1:E1',
        'current_title': '   ',
        'visibility': 'public',
        'status': 'live',
      });
      expect(r.isLiveNow, isTrue);
      expect(r.watchingLabel, 'Choosing…');
    });

    test('legacy rows (no current_* keys) behave as picking', () {
      final r = WatchPartyRoom.fromJson({
        'room_id': 'OLD001',
        'title': 'Old',
        'media_ref': 'tmdb:movie:1',
        'visibility': 'public',
        'status': 'live',
      });
      expect(r.isLiveNow, isFalse);
      expect(r.nowWatchingRef, 'tmdb:movie:1');
    });
  });
}
