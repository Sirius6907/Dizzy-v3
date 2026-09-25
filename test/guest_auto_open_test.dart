import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/watchparty/guest_auto_open.dart';
import 'package:dizzy/services/watchparty/party_session.dart';
import 'package:dizzy/services/watchparty/watch_sync_engine.dart';

void main() {
  group('P3: parseRef', () {
    test('movie ref', () {
      final t = GuestAutoOpen.parseRef('tmdb:movie:550', title: 'Fight Club');
      expect(t, isNotNull);
      expect(t!.kind, RefKind.movie);
      expect(t.tmdbId, 550);
      expect(t.title, 'Fight Club');
    });

    test('tv ref with S/E in string', () {
      final t = GuestAutoOpen.parseRef('tmdb:tv:123:S2:E5');
      expect(t, isNotNull);
      expect(t!.kind, RefKind.tv);
      expect(t.tmdbId, 123);
      expect(t.season, 2);
      expect(t.episode, 5);
    });

    test('tv ref without S/E uses msg fields, default 1', () {
      final t = GuestAutoOpen.parseRef('tmdb:tv:123', season: 3);
      expect(t!.season, 3);
      expect(t.episode, 1);
    });

    test('imdb ref', () {
      final t = GuestAutoOpen.parseRef('imdb:tt1234567');
      expect(t, isNotNull);
      expect(t!.kind, RefKind.movie);
      expect(t.imdbId, 'tt1234567');
    });

    test('garbage → null (fail-soft)', () {
      expect(GuestAutoOpen.parseRef(''), isNull);
      expect(GuestAutoOpen.parseRef('hello'), isNull);
      expect(GuestAutoOpen.parseRef('tmdb:movie:'), isNull);
      expect(GuestAutoOpen.parseRef('tmdb:tv:abc'), isNull);
    });
  });

  group('P3: handle guards (no network)', () {
    test('host never opens, guest same-title skips', () async {
      final s = PartySession.instance;
      s.end();
      // Outsider (no party) → no-op.
      await GuestAutoOpen.handle(const WatchSyncMessage(
        mediaRef: 'tmdb:movie:550',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 1,
      ));
      expect(GuestAutoOpen.busy, isFalse);
      s.end();
    });

    test('follow service arm/disarm idempotent', () async {
      GuestFollowService.arm();
      expect(GuestFollowService.armed, isTrue);
      GuestFollowService.arm(); // second arm = no-op
      expect(GuestFollowService.armed, isTrue);
      await GuestFollowService.disarm();
      expect(GuestFollowService.armed, isFalse);
    });

    test('parseRef covers all ref shapes for auto-open chain', () {
      // Guest auto-open chain: msg → parseRef → WatchScreen → autoplay →
      // wired PlayerScreen. Har ref shape parse honi chahiye warna guest
      // "Couldn't open this one" par atakta hai.
      expect(
          GuestAutoOpen.parseRef('tmdb:movie:550', title: 'Fight Club'),
          isNotNull);
      expect(GuestAutoOpen.parseRef('tmdb:tv:123:S2:E5'), isNotNull);
      expect(
          GuestAutoOpen.parseRef('imdb:tt1234567', title: 'Some Movie'),
          isNotNull);
      // host position ke saath wala msg bhi usable hona chahiye.
      const msg = WatchSyncMessage(
        mediaRef: 'tmdb:movie:550',
        mediaTitle: 'Fight Club',
        positionMs: 90000,
        playing: true,
        hostSentAtMs: 1,
      );
      expect(msg.isUsable, isTrue);
      expect(GuestAutoOpen.parseRef(msg.mediaRef, title: msg.mediaTitle),
          isNotNull);
    });

    test('guest opens near host position, never 0:00 mid-title', () {
      // host 90s pe hai, msg 2s purana → guest ~92s pe khulna chahiye.
      const msg = WatchSyncMessage(
        mediaRef: 'tmdb:movie:550',
        positionMs: 90000,
        playing: true,
        hostSentAtMs: 1000,
      );
      final pos = GuestAutoOpen.initialPositionFor(msg, nowMs: 3000);
      expect(pos.inMilliseconds, greaterThanOrEqualTo(90000));
      expect(pos.inMilliseconds, lessThan(95000));
      // stale/future timestamp → elapsed 0, host position as-is (no jump).
      final same = GuestAutoOpen.initialPositionFor(msg, nowMs: 500);
      expect(same.inMilliseconds, 90000);
    });
  });
}
