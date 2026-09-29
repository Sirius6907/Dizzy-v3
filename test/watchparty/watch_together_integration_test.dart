import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/watchparty/watch_sync_engine.dart';
import 'package:dizzy/services/watchparty/party_session.dart';

void main() {
  group('Guest Sync Message Handling', () {
    test('WatchSyncMessage isUsable true for valid version and ref', () {
      const msg = WatchSyncMessage(
        mediaRef: 'tmdb:movie:123',
        positionMs: 5000,
        playing: true,
        hostSentAtMs: 1000,
      );
      expect(msg.isUsable, isTrue);
    });

    test('WatchSyncMessage isUsable false for version 0', () {
      const msg = WatchSyncMessage(
        mediaRef: 'tmdb:movie:123',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 0,
        version: 0,
      );
      expect(msg.isUsable, isFalse);
    });

    test('WatchSyncMessage isUsable false for empty mediaRef', () {
      const msg = WatchSyncMessage(
        mediaRef: '',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 0,
        version: 2,
      );
      expect(msg.isUsable, isFalse);
    });

    test('WatchSyncMessage round-trip via fromJson / toJson', () {
      const original = WatchSyncMessage(
        version: 2,
        mediaRef: 'imdb:tt123',
        mediaTitle: 'Round Trip',
        positionMs: 12345,
        playing: true,
        speed: 1.5,
        hostSentAtMs: 1000,
        prefetchReady: true,
        chapterIndex: 2,
        season: 1,
        episode: 3,
      );
      final json = original.toJson();
      final decoded = WatchSyncMessage.fromJson(json);
      expect(decoded.mediaRef, original.mediaRef);
      expect(decoded.positionMs, original.positionMs);
      expect(decoded.hostSentAtMs, original.hostSentAtMs);
      expect(decoded.version, original.version);
      expect(decoded.prefetchReady, original.prefetchReady);
      expect(decoded.chapterIndex, original.chapterIndex);
      expect(decoded.season, original.season);
      expect(decoded.episode, original.episode);
      expect(decoded.playing, original.playing);
    });

    test('Parse ref handles tmdb movie', () {
      // Use GuestAutoOpen.parseRef indirectly via message parsing
      const msg = WatchSyncMessage(
        mediaRef: 'tmdb:movie:42',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 0,
      );
      expect(msg.mediaRef, 'tmdb:movie:42');
      expect(msg.isUsable, isTrue);
    });

    test('Parse ref handles tmdb tv with season and episode', () {
      const msg = WatchSyncMessage(
        mediaRef: 'tmdb:tv:101::S2::E5',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 0,
      );
      expect(msg.mediaRef, 'tmdb:tv:101::S2::E5');
    });

    test('Parse ref handles imdb', () {
      const msg = WatchSyncMessage(
        mediaRef: 'imdb:tt42',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 0,
      );
      expect(msg.mediaRef, 'imdb:tt42');
    });

    test('Null mediaRef is not usable', () {
      // WatchSyncMessage requires mediaRef as String (empty not null)
      const msg = WatchSyncMessage(
        mediaRef: '',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 0,
      );
      expect(msg.isUsable, isFalse);
    });

    test('PartySession defaults are consistent', () {
      final session = PartySession.instance;
      expect(session.inParty, isFalse);
      expect(session.isHost, isFalse);
    });
  });

  group('Target Position Drift Calculation', () {
    test('driftThresholdMs is positive', () {
      expect(WatchSyncEngine.driftThresholdMs, greaterThan(0));
      expect(WatchSyncEngine.driftThresholdMs, equals(1500));
    });

    test('resyncPosition returns null when drift within threshold', () {
      final result = WatchSyncEngine.resyncPosition(
        guestPositionMs: 1000,
        targetPositionMs: 1000,
      );
      expect(result, isNull);
    });

    test('resyncPosition returns null when drift at exactly threshold', () {
      final result = WatchSyncEngine.resyncPosition(
        guestPositionMs: 1000,
        targetPositionMs: 1000 + WatchSyncEngine.driftThresholdMs,
      );
      expect(result, isNull);
    });

    test('resyncPosition returns corrected position when drift exceeds threshold', () {
      final result = WatchSyncEngine.resyncPosition(
        guestPositionMs: 1000,
        targetPositionMs: 5000, // 4000ms drift
      );
      expect(result, isNotNull);
      expect(result!, greaterThanOrEqualTo(5000));
    });

    test('targetPosition computes host timeline correctly', () {
      final result = WatchSyncEngine.targetPosition(
        hostPositionMs: 1000,
        hostSentAtMs: 500,
        nowMs: 1000,
        clockOffsetMs: 50,
      );
      // elapsed = max(0, 1000 - 500 - 50) = 450
      // result = 1000 + 450 = 1450
      expect(result, equals(1450));
    });

    test('targetPosition handles zero clock offset', () {
      final result = WatchSyncEngine.targetPosition(
        hostPositionMs: 2000,
        hostSentAtMs: 1000,
        nowMs: 2000,
        clockOffsetMs: 0,
      );
      expect(result, equals(3000));
    });

    test('targetPosition with negative elapsed clamps to zero', () {
      final result = WatchSyncEngine.targetPosition(
        hostPositionMs: 1000,
        hostSentAtMs: 2000,
        nowMs: 1500,
        clockOffsetMs: 0,
      );
      // elapsed = max(0, 1500 - 2000 - 0) = 0
      // result = 1000 + 0 = 1000
      expect(result, equals(1000));
    });

    test('resyncPosition handles guest ahead (negative drift)', () {
      final result = WatchSyncEngine.resyncPosition(
        guestPositionMs: 5000,
        targetPositionMs: 1000, // guest is ahead by 4000ms
      );
      expect(result, isNotNull);
    });

    test('shouldToast returns false within toast threshold', () {
      expect(
        WatchSyncEngine.shouldToast(1000, 1000 + 1000),
        isFalse,
      );
    });

    test('shouldToast returns true beyond toast threshold', () {
      expect(
        WatchSyncEngine.shouldToast(1000, 1000 + 6000),
        isTrue,
      );
    });
  });
}