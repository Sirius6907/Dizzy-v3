import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/continue_watching/continue_watching_item.dart';
import 'package:dizzy/services/cloud/cloud_sync_service.dart';

ContinueWatchingItem item({
  required String id,
  required DateTime at,
  int position = 100,
  int total = 1000,
  String? rawUrl,
}) =>
    ContinueWatchingItem(
      id: id,
      title: id,
      type: 'movie',
      positionSeconds: position,
      totalDurationSeconds: total,
      lastWatchedAt: at,
      isTorrent: false,
      rawUrl: rawUrl,
    );

void main() {
  group('S3A CloudSync mergeNewestWins', () {
    test('newer local progress wins and preserves local source', () {
      final old = DateTime(2026, 9, 7);
      final newer = DateTime(2026, 9, 8);
      final local = item(id: 'tt1', at: newer, rawUrl: 'https://device-only');
      final remote = item(id: 'tt1', at: old);
      final out = CloudSyncService.mergeNewestWins([local], [remote]);
      expect(out, hasLength(1));
      expect(out.single.positionSeconds, local.positionSeconds);
      expect(out.single.rawUrl, 'https://device-only');
    });

    test('newer remote progress wins without source URL', () {
      final old = DateTime(2026, 9, 7);
      final newer = DateTime(2026, 9, 8);
      final local = item(id: 'tt1', at: old, rawUrl: 'https://device-only');
      final remote = item(id: 'tt1', at: newer);
      final out = CloudSyncService.mergeNewestWins([local], [remote]);
      expect(out.single.lastWatchedAt, newer);
      expect(out.single.rawUrl, isNull);
    });

    test('completed items are not restored', () {
      final now = DateTime(2026, 9, 8);
      final done = item(id: 'tt1', at: now, position: 950, total: 1000);
      expect(CloudSyncService.mergeNewestWins([], [done]), isEmpty);
    });

    test('caps merged sessions at 50', () {
      final now = DateTime(2026, 9, 8);
      final all = List.generate(
        55,
        (i) => item(id: 'tt$i', at: now.add(Duration(seconds: i))),
      );
      expect(CloudSyncService.mergeNewestWins(all, []), hasLength(50));
    });
  });
}
