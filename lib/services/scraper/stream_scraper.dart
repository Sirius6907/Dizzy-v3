import 'dart:async';
import '../../models/stream/stream_model.dart';
import '../cloud/remote_config_service.dart';
import '../p2p/p2p_settings_service.dart';
import 'scraper_quarantine_service.dart';
import 'scraper_reporter.dart';
import '../errors/app_log.dart';

abstract class StreamScraper {
  String get name;

  /// True for torrent/P2P scrapers (Knaben, TorrentGalaxy). Used instead of
  /// string-matching `name == 'Dizzy'` — every HTTP scraper now has a unique
  /// name, so identity comparison on names is unreliable for type checks.
  bool get isTorrentScraper => false;

  /// Yields sources progressively one-by-one as they are resolved.
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async* {
    final list = await scrape(
      type: type,
      title: title,
      year: year,
      season: season,
      episode: episode,
      imdbId: imdbId,
    );
    for (final s in list) {
      yield s;
    }
  }

  /// Bulk scrape fallback.
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    return [];
  }
}

class ScraperManager {
  ScraperManager._internal();
  static final ScraperManager instance = ScraperManager._internal();

  final List<StreamScraper> _scrapers = [];
  bool get hasScrapers => _scrapers.isNotEmpty;

  /// v1.2.0-P2 (T2.1): read-only snapshot for the Sources health dashboard.
  List<StreamScraper> get scrapers => List.unmodifiable(_scrapers);

  void registerScraper(StreamScraper scraper) {
    if (!_scrapers.any((s) => s.runtimeType == scraper.runtimeType)) {
      _scrapers.add(scraper);
    }
  }

  void unregisterTorrentScrapers() {
    _scrapers.removeWhere((s) => s.isTorrentScraper);
  }

  /// True when a scraper with this (case-insensitive) unique name is registered.
  bool hasScraper(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return false;
    return _scrapers.any((s) => s.name.toLowerCase() == key);
  }

  /// True when [addonName] belongs to a registered built-in HTTP scraper
  /// (i.e. NOT a torrent scraper and NOT an external Stremio addon).
  /// Used by UI filters (e.g. "DizzyHTTP addon disabled" toggle).
  bool isBuiltinHttpSource(String addonName) {
    final key = addonName.trim().toLowerCase();
    if (key.isEmpty) return false;
    return _scrapers
        .any((s) => !s.isTorrentScraper && s.name.toLowerCase() == key);
  }

  Stream<StreamSource> scrapeAll({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) {
    final controller = StreamController<StreamSource>();

    // v1.1.9 (Task 19): snapshot per scrape — mid-scrape P2P toggles apply
    // on the NEXT scrape by design (consistent source set per run).
    final p2pAllowed = P2pSettingsService.isP2pEnabled.value;
    final activeScrapers = _scrapers.where((s) {
      if (!p2pAllowed && s.isTorrentScraper) {
        return false;
      }
      // F0 (v1.1.9): dead scraper quarantine — skip dead endpoints, retry after 7d
      if (ScraperQuarantineService.isQuarantined(s.name)) {
        return false;
      }
      // v1.2.0-ADMIN: remote kill map from dashboard — admin-killed scrapers
      // are skipped app-wide within ~1h (remote config cache TTL).
      if (RemoteConfigService.isKilled(s.name)) {
        return false;
      }
      return true;
    }).toList();

    if (activeScrapers.isEmpty) {
      controller.close();
      return controller.stream;
    }

    AppLog.d('[ScraperManager] Scraping across ${activeScrapers.length} active scrapers (${activeScrapers.map((s) => s.runtimeType).join(", ")}) for "$title" (P2P enabled: $p2pAllowed)...');

    int pendingScrapers = activeScrapers.length;
    final seenHashes = <String>{};
    final seenUrls = <String>{};

    void checkClose() {
      if (pendingScrapers == 0 && !controller.isClosed) {
        controller.close();
      }
    }

    for (final scraper in activeScrapers) {
      var yielded = 0;
      scraper
          .scrapeStream(
        type: type,
        title: title,
        year: year,
        season: season,
        episode: episode,
        imdbId: imdbId,
      )
          .listen(
        (source) {
          if (controller.isClosed) return;
          yielded++;

          // v1.2.0-ADMIN: first success auto-heals local quarantine.
          if (yielded == 1) ScraperQuarantineService.markSuccess(scraper.name);

          // If P2P is disabled, strictly discard any torrent source
          if (!p2pAllowed &&
              (source.addonName == 'Dizzy' ||
                  (source.infoHash != null && source.infoHash!.isNotEmpty))) {
            return;
          }

          // Torrent sources pass directly with deduplication
          if (source.infoHash != null && source.infoHash!.isNotEmpty) {
            final hashLower = source.infoHash!.toLowerCase();
            if (seenHashes.contains(hashLower)) return;
            seenHashes.add(hashLower);
            controller.add(source);
            return;
          }

          final rawUrl = source.url ?? source.externalUrl;
          if (rawUrl != null && rawUrl.startsWith('http')) {
            if (seenUrls.contains(rawUrl)) return;
            seenUrls.add(rawUrl);
            controller.add(source);
          } else {
            controller.add(source);
          }
        },
        onError: (_) {
          // v1.2.0-ADMIN: error vote (throttled 24h server+client).
          // ignore: unawaited_futures
          ScraperReporter.reportError(scraper.name);
          // v1.2.0-P1 (T1.3): a throw = persistent failure signal → reset the
          // 7-day retry clock. Note: zero-yield (empty) does NOT quarantine —
          // a healthy scraper may simply have no sources for a niche title.
          // Empty results only send a throttled crowd vote via reportEmpty.
          ScraperQuarantineService.markFailed(scraper.name);
        },
        onDone: () {
          pendingScrapers--;
          if (yielded == 0) {
            // v1.2.0-ADMIN: empty vote (throttled 24h server+client).
            // ignore: unawaited_futures
            ScraperReporter.reportEmpty(scraper.name);
          }
          checkClose();
        },
      );
    }

    return controller.stream;
  }
}
