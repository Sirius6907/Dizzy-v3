import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:dizzy/services/watchparty/guest_auto_open.dart';
import 'package:dizzy/services/watchparty/party_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// P18: persistent-room contract (pure client side — IDs, guards, limits).
void main() {
  group('P18: persistent rooms', () {
    test('generated IDs fit the unambiguous alphabet', () {
      for (var i = 0; i < 25; i++) {
        final id = WatchPartyService.generateRoomId();
        expect(id, hasLength(6));
        expect(WatchPartyService.validRoomId(id), isTrue,
            reason: 'generator output must always validate: $id');
      }
    });

    test('room ID check forgives case/space, rejects lookalikes', () {
      expect(WatchPartyService.validRoomId('ab23cd'), isTrue);
      expect(WatchPartyService.validRoomId('  AB23CD  '), isTrue);
      // 0/O/1/I/L are excluded from the alphabet (no misreads).
      expect(WatchPartyService.validRoomId('AB01CD'), isFalse);
      expect(WatchPartyService.validRoomId('AB12CO'), isFalse);
      expect(WatchPartyService.validRoomId('SHORT'), isFalse);
      expect(WatchPartyService.validRoomId('TOOLONG1'), isFalse);
    });

    test('private-room pass is exactly 6 digits', () {
      expect(WatchPartyService.validPass('123456'), isTrue);
      expect(WatchPartyService.validPass(' 123456 '), isTrue);
      expect(WatchPartyService.validPass('12345'), isFalse);
      expect(WatchPartyService.validPass('abcdef'), isFalse);
      expect(WatchPartyService.validPass(''), isFalse);
    });

    test('v1 room size stays 20 (client mirror of server cap)', () {
      expect(WatchPartyService.maxMembers, 20);
    });

    test('late-join catch-up: room row carries host now-watching', () {
      // joinRoom full `rooms` row padhta hai — current_media_ref se guest
      // Task 1 wala catch-up chalta hai. Ye contract pin karta hai ki
      // fromJson ye columns parse kare (select * hai, column drop nahi).
      final room = WatchPartyRoom.fromJson({
        'room_id': 'AB23CD',
        'title': 'Late Join Room',
        'media_ref': null,
        'current_media_ref': 'tmdb:movie:99',
        'current_title': 'Late Movie',
        'visibility': 'public',
        'status': 'lobby',
      });
      expect(room.nowWatchingRef, 'tmdb:movie:99');
      expect(room.currentTitle, 'Late Movie');
      expect(room.isLiveNow, isTrue);
      expect(room.watchingLabel, 'Late Movie');
      // Empty room → guest "Choosing…" par, auto-open skip.
      const empty = WatchPartyRoom(
        roomId: 'XY78ZZ',
        title: 'Empty',
        mediaRef: null,
        isPrivate: false,
        status: 'lobby',
      );
      expect(empty.nowWatchingRef, isNull);
      expect(empty.watchingLabel, 'Choosing…');
    });

    test('public-list join boots the same guest session as code join', () {
      // Contract for _joinPublic (watch_party_page.dart): joinRoom success ke
      // baad PartySession me guest state hona chahiye — warna GuestFollow
      // kabhi arm nahi hota aur cinema-hall sync dead rehta hai.
      // Pehle purani state saaf (singleton hai).
      PartySession.instance.end();
      expect(PartySession.instance.inParty, isFalse);

      const room = WatchPartyRoom(
        roomId: 'AB23CD',
        title: 'Test Room',
        mediaRef: null,
        currentMediaRef: 'tmdb:movie:42',
        currentTitle: 'Test Movie',
        isPrivate: false,
        status: 'lobby',
      );

      // Yehi sequence _joinPublic ko joinRoom-success par karni chahiye.
      PartySession.instance.startAsGuest(room: room);
      final nowRef = room.nowWatchingRef;
      if (nowRef != null && nowRef.isNotEmpty) {
        PartySession.instance.setGuestMedia(
          mediaRef: nowRef,
          mediaTitle: room.currentTitle,
        );
      }

      expect(PartySession.instance.inParty, isTrue);
      expect(PartySession.instance.isHost, isFalse);
      expect(PartySession.instance.mediaRef, 'tmdb:movie:42');

      // GuestAutoOpen ref parse bhi usable hona chahiye (auto-open path).
      final target = GuestAutoOpen.parseRef(nowRef!);
      expect(target, isNotNull);

      PartySession.instance.end();
    });
  });
}
