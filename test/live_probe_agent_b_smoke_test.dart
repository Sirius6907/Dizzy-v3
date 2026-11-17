// Throwaway live-probe harness (agent B) — group 1.
import 'package:dizzy/services/scraper/sites/movy.dart';
import 'package:dizzy/services/scraper/sites/videasy.dart';
import 'package:dizzy/services/scraper/sites/vidcore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'probe_b_common.dart';

void main() {
  setUpAll(initProbeEnv);

  test('smoke + tmdb', () async {
    await probeTmdb();
    final all = [VideasyScraper(), VidCoreScraper(), MovyScraper()];
    clearLogs(all);
    for (final s in all) {
      for (final t in targets) {
        await probeOne(s, t);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
