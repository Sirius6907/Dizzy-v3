import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/utils/perf/storage_guard.dart';

void main() {
  group('StorageGuard.decideCritical', () {
    test('healthy disk allows', () {
      expect(
        StorageGuard.decideCritical(
          freeBytes: 10 * 1024 * 1024 * 1024,
          totalBytes: 64 * 1024 * 1024 * 1024,
        ),
        false,
      );
    });

    test('free under 500MB blocks', () {
      expect(
        StorageGuard.decideCritical(
          freeBytes: 400 * 1024 * 1024,
          totalBytes: 64 * 1024 * 1024 * 1024,
        ),
        true,
      );
    });

    test('over 90% used blocks even with headroom', () {
      // 128GB disk, 6GB free = 95% used → critical despite 6GB free.
      expect(
        StorageGuard.decideCritical(
          freeBytes: 6 * 1024 * 1024 * 1024,
          totalBytes: 128 * 1024 * 1024 * 1024,
        ),
        true,
      );
    });

    test('exactly at boundary stays safe', () {
      // 89% used, 7GB free on 64GB → allow.
      expect(
        StorageGuard.decideCritical(
          freeBytes: 7 * 1024 * 1024 * 1024,
          totalBytes: 64 * 1024 * 1024 * 1024,
        ),
        false,
      );
    });

    test('unknown space never blocks playback', () {
      expect(
        StorageGuard.decideCritical(freeBytes: 0, totalBytes: 0),
        false,
      );
    });
  });
}
