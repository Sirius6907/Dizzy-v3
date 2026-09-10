import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/stream/stream_model.dart';
import '../cloud/remote_config_service.dart';
import '../p2p/p2p_settings_service.dart';
import 'scraper_quarantine_service.dart';
import 'scraper_reporter.dart';

abstract class StreamScraper {
  String get name;

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

  void registerScraper(StreamScraper scraper) {
    if (!_scrapers.any((s) => s.runtimeType == scraper.runtimeType)) {
      _scrapers.add(scraper);
    }
  }

  void unregisterTorrentScrapers() {
    _scrapers.removeWhere((s) => s.name == 'Dizzy');
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
      if (!p2pAllowed && s.name == 'Dizzy') {
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

    debugPrint('[ScraperManager] Scraping across ${activeScrapers.length} active scrapers (${activeScrapers.map((s) => s.runtimeType).join(", ")}) for "$title" (P2P enabled: $p2pAllowed)...');

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
