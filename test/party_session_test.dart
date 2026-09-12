import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:dizzy/services/watchparty/party_session.dart';
import 'package:dizzy/services/watchparty/party_playback_session.dart';
import 'package:dizzy/services/watchparty/watch_sync_engine.dart';

WatchPartyRoom _room(String id) => WatchPartyRoom(
      roomId: id,
      title: 'Test Party',
      mediaRef: 'tmdb:movie:550',
      isPrivate: false,
      status: 'lobby',
    );

void main() {
  group('PartySession transitions', () {
    test('starts idle, host start sets all fields', () {
      final s = PartySession.instance;
      s.end(); // reset singleton
      expect(s.inParty, isFalse);
      s.startAsHost(room: _room('ABC123'), mediaRef: 'tmdb:movie:550');
      expect(s.inParty, isTrue);
      expect(s.isHost, isTrue);
      expect(s.mediaRef, 'tmdb:movie:550');
      s.end();
      expect(s.inParty, isFalse);
      expect(s.mediaRef, isNull);
    });

    test('guest start + media gate update', () {
      final s = PartySession.instance;
      s.end();
      s.startAsGuest(room: _room('XYZ789'));
      expect(s.isHost, isFalse);
      expect(s.mediaRef, isNull);
      s.setGuestMedia(mediaRef: 'tmdb:tv:123:S1:E2');
      expect(s.mediaRef, 'tmdb:tv:123:S1:E2');
      s.end();
    });

    test('guest cannot switch media via host-only API', () {
      final s = PartySession.instance;
      s.end();
      s.startAsGuest(room: _room('QWE456'));
      s.switchMedia(mediaRef: 'tmdb:movie:999');
      expect(s.mediaRef, isNull); // ignored for guests
      s.end();
    });

    test('P1: host starts with NO media (persistent room)', () {
      final s = PartySession.instance;
      s.end();
      s.startAsHost(room: _room('NOP001'));
      expect(s.inParty, isTrue);
      expect(s.isHost, isTrue);
      expect(s.mediaRef, isNull); // choosing… state
      // Host plays later → switchMedia attaches it.
      s.switchMedia(mediaRef: 'tmdb:movie:550', mediaTitle: 'Fight Club');
      expect(s.mediaRef, 'tmdb:movie:550');
      expect(s.mediaTitle, 'Fight Club');
      s.end();
    });
  });

  group('P1: now-watching resolution', () {
    test('current columns win, legacy media_ref fallback', () {
      const r = WatchPartyRoom(
        roomId: 'ABC123',
        title: 'Party',
        mediaRef: 'tmdb:movie:550',
        currentMediaRef: 'tmdb:tv:123:S1:E2',
        currentTitle: 'Show',
        isPrivate: false,
        status: 'lobby',
      );
      expect(r.nowWatchingRef, 'tmdb:tv:123:S1:E2');
    });

    test('empty room → null (Choosing… UI)', () {
      const r = WatchPartyRoom(
        roomId: 'EMPTY1',
        title: 'Party',
        mediaRef: null,
        isPrivate: false,
        status: 'lobby',
      );
      expect(r.nowWatchingRef, isNull);
    });

    test('legacy row without new columns still resolves', () {
      final r = _room('OLD123');
      expect(r.nowWatchingRef, 'tmdb:movie:550');
    });
  });

  group('P2: sync message v2', () {
    test('title + season + episode round-trip, v1 still usable', () {
      const msg = WatchSyncMessage(
        mediaRef: 'tmdb:tv:123:S1:E2',
        mediaTitle: 'Show',
        season: 1,
        episode: 2,
        positionMs: 5000,
        playing: true,
        hostSentAtMs: 1,
      );
      final back = WatchSyncMessage.fromJson(
          Map<String, dynamic>.from(msg.toJson()));
      expect(back.isUsable, isTrue);
      expect(back.mediaTitle, 'Show');
      expect(back.season, 1);
      expect(back.episode, 2);
      // Legacy v1 payload (no new keys) still parses.
      final old = WatchSyncMessage.fromJson({
        'v': 1,
        'media_ref': 'tmdb:movie:550',
        'position_ms': 0,
        'playing': false,
        'host_sent_at': 1,
      });
      expect(old.isUsable, isTrue);
      expect(old.mediaTitle, isNull);
    });

    test('announceMedia no-ops for guests and outsiders', () async {
      final s = PartySession.instance;
      s.end();
      s.startAsGuest(room: _room('GUEST1'));
      final sess = PartyPlaybackSession(
        getPositionMs: () => 0,
        isPlaying: () => false,
        getSpeed: () => 1.0,
        seekToMs: (_) async {},
        setPlaying: (_) async {},
      );
      await sess.announceMedia(ref: 'tmdb:movie:1', title: 'X');
      expect(s.mediaRef, isNull); // guest state untouched
      s.end();
    });
  });

  group('Room code normalize', () {
    test('trims, uppercases, strips spaces', () {
      expect(PartySession.normalizeCode(' abc123 '), 'ABC123');
      expect(PartySession.normalizeCode('a b c 1 2 3'), 'ABC123');
    });

    test('already-clean codes pass through', () {
      expect(PartySession.normalizeCode('ABC123'), 'ABC123');
    });
  });

  group('Reconnect backoff', () {
    test('1s, 2s, 4s then caps', () {
      expect(PartyPlaybackSession.backoffForAttempt(0), 1);
      expect(PartyPlaybackSession.backoffForAttempt(1), 2);
      expect(PartyPlaybackSession.backoffForAttempt(2), 4);
      expect(PartyPlaybackSession.backoffForAttempt(99), 4);
    });
  });

  group('Guest control policy', () {
    test('guests locked out of transport, keep volume', () {
      expect(GuestControlPolicy.canSeek, isFalse);
      expect(GuestControlPolicy.canChangeSpeed, isFalse);
      expect(GuestControlPolicy.canChangeTracks, isFalse);
      expect(GuestControlPolicy.canAdjustVolume, isTrue);
    });
  });

  group('Media ref builders', () {
    test('canonical formats', () {
      expect(PartySession.movieRef('550'), 'tmdb:movie:550');
      expect(PartySession.tvRef('123', 2, 5), 'tmdb:tv:123:S2:E5');
      expect(PartySession.imdbRef('tt1234567'), 'imdb:tt1234567');
    });
  });
}
