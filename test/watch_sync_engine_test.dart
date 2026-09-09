import 'package:dizzy/services/watchparty/watch_sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatchSyncEngine (WP-P2)', () {
    test('target adds in-flight elapsed minus clock offset', () {
      expect(
        WatchSyncEngine.targetPosition(
          hostPositionMs: 42000,
          hostSentAtMs: 1000,
          nowMs: 1600,
          clockOffsetMs: 100,
        ),
        42500,
      );
    });

    test('target never goes backwards on negative elapsed', () {
      expect(
        WatchSyncEngine.targetPosition(
          hostPositionMs: 42000,
          hostSentAtMs: 2000,
          nowMs: 1500,
          clockOffsetMs: 0,
        ),
        42000,
      );
    });

    test('resync null inside tolerance, corrected outside', () {
      expect(
        WatchSyncEngine.resyncPosition(
            guestPositionMs: 42000, targetPositionMs: 43000),
        isNull,
      );
      expect(
        WatchSyncEngine.resyncPosition(
            guestPositionMs: 42000, targetPositionMs: 44000),
        44000,
      );
      // Clamped at zero, never negative.
      expect(
        WatchSyncEngine.resyncPosition(
            guestPositionMs: 10000, targetPositionMs: -5000),
        0,
      );
    });

    test('toast only beyond 5s drift', () {
      expect(WatchSyncEngine.shouldToast(42000, 44000), isFalse);
      expect(WatchSyncEngine.shouldToast(42000, 48000), isTrue);
    });

    test('medianOffset picks middle sample, 0 when empty', () {
      expect(WatchSyncEngine.medianOffset([120, 80, 100]), 100);
      expect(WatchSyncEngine.medianOffset([]), 0);
    });

    test('message round-trips, rejects wrong version/empty media', () {
      const msg = WatchSyncMessage(
        mediaRef: 'tmdb:movie:550',
        positionMs: 42170,
        playing: true,
        speed: 1.0,
        hostSentAtMs: 999,
      );
      final back =
          WatchSyncMessage.fromJson(Map<String, dynamic>.from(msg.toJson()));
      expect(back.isUsable, isTrue);
      expect(back.mediaRef, 'tmdb:movie:550');
      expect(back.positionMs, 42170);
      expect(back.playing, isTrue);

      expect(
        WatchSyncMessage.fromJson({'v': 2, 'media_ref': 'x'}).isUsable,
        isFalse,
      );
      expect(WatchSyncMessage.fromJson({}).isUsable, isFalse);
    });

    test('guest controls locked except volume', () {
      expect(GuestControlPolicy.canSeek, isFalse);
      expect(GuestControlPolicy.canChangeSpeed, isFalse);
      expect(GuestControlPolicy.canChangeTracks, isFalse);
      expect(GuestControlPolicy.canAdjustVolume, isTrue);
    });
  });
}
