import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/cloud/cloud_client.dart';

// Lazy cloud recovery (2026-11-12): a failed cold-start init must not
// leave the session permanently cloudless. CloudClient.retry() is the
// seam pure-HTTP edge callers use to recover instead of hard-gating on
// the boot-time init result.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudClient.retry', () {
    test('returns false without throwing when cloud is unconfigured', () async {
      // Test environment has no SUPABASE dart-defines and no .env, so
      // isConfigured is false — retry must answer false cheaply.
      final ready = await CloudClient.retry();
      expect(ready, isFalse);
      expect(CloudClient.isConfigured, isFalse);
    });
  });
}
