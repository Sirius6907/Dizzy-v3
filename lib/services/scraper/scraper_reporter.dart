import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';

/// v1.2.0-ADMIN: crowdsourced dead-scraper votes → `scraper-ingest` edge.
///
/// Called when a scraper yields 0 sources for a title (likely dead/slow).
/// Throttled: max 1 vote per scraper per 24h per device (local + server dedupe).
/// Fire-and-forget, fails soft — never blocks scraping.
class ScraperReporter {
  static const _prefix = 'scraper_vote_at_v1_';

  static Future<void> reportEmpty(String scraperName,
      {String kind = 'empty'}) {
    return _send(scraperName, kind);
  }

  static Future<void> reportError(String scraperName) {
    return _send(scraperName, 'error');
  }

  static Future<void> _send(String scraperName, String kind) async {
    try {
      final name = scraperName.trim().toLowerCase();
      if (name.isEmpty || !CloudClient.isReady) return;

      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$name';
      final last = prefs.getInt(key) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last <
          const Duration(hours: 24).inMilliseconds) {
        return;
      }
      await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);

      await CloudClient.db.functions.invoke(
        'scraper-ingest',
        body: {
          'scraper': name,
          'kind': kind,
          'app_version': '1.2.0',
        },
      );
    } catch (e) {
      AppLog.d('[ScraperReporter] vote failed (soft): $e');
    }
  }
}
