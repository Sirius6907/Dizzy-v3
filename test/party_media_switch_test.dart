import 'package:dizzy/services/watchparty/watch_sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// P18: media_switch matrix — every wire shape the lobby/guest path can
/// receive must parse to a clear usable/unusable verdict (never a crash,
/// never a silent wrong-title switch).
Map<String, dynamic> msg({
  Object? v = 2,
  Object? ref = 'tmdb:123',
  bool? playing,
  Object? speed,
  bool? prefetch,
}) {
  final m = <String, dynamic>{'type': 'media_switch'};
  if (v != null) m['v'] = v;
  if (ref != null) m['media_ref'] = ref;
  if (playing != null) m['playing'] = playing;
  if (speed != null) m['speed'] = speed;
  if (prefetch != null) m['prefetch_ready'] = prefetch;
  m['position_ms'] = 0;
  m['host_sent_at'] = 0;
  return m;
}

void main() {
  group('P18: media_switch matrix', () {
    test('v1 + v2 with a ref are usable', () {
      expect(WatchSyncMessage.fromJson(msg(v: 1)).isUsable, isTrue);
      expect(WatchSyncMessage.fromJson(msg(v: 2)).isUsable, isTrue);
    });

    test('future protocol version is rejected (no blind apply)', () {
      expect(WatchSyncMessage.fromJson(msg(v: 3)).isUsable, isFalse);
      expect(WatchSyncMessage.fromJson(msg(v: 99)).isUsable, isFalse);
    });

    test('empty/missing ref is rejected (no wrong-title switch)', () {
      expect(WatchSyncMessage.fromJson(msg(ref: '')).isUsable, isFalse);
      expect(WatchSyncMessage.fromJson(msg(ref: null)).isUsable, isFalse);
    });

    test('safe defaults: paused, 1x, prefetch off', () {
      final m = WatchSyncMessage.fromJson(msg());
      expect(m.playing, isFalse);
      expect(m.speed, 1.0);
      expect(m.prefetchReady, isFalse);
      expect(m.positionMs, 0);
    });

    test('round-trip keeps the switch usable', () {
      final back = WatchSyncMessage.fromJson(
          WatchSyncMessage.fromJson(msg(prefetch: true)).toJson());
      expect(back.isUsable, isTrue);
      expect(back.mediaRef, 'tmdb:123');
      expect(back.prefetchReady, isTrue);
    });
  });
}
