import 'dart:async';

import '../../models/addon/addon.dart';
import '../../models/stream/stream_model.dart';
import '../addon/addon_manager.dart';
import 'stream_addon_service.dart';
import '../scraper/stream_scraper.dart';
import '../scraper/sites/knaben.dart';
import '../scraper/sites/torrent_galaxy.dart';
import '../scraper/sites/fourkhdhub.dart';
import '../scraper/sites/xdownloader.dart';
import '../scraper/sites/videasy.dart';
import '../scraper/sites/vidsrc.dart';
import '../scraper/sites/multiembed.dart';
import '../scraper/sites/vidcore.dart';
import '../scraper/sites/flystream.dart';
import '../scraper/sites/movienight.dart';
import '../scraper/sites/downloadeverything.dart';
import '../scraper/sites/movy.dart';
import '../scraper/sites/vuflix.dart';
import '../scraper/sites/rivestream.dart';
import '../scraper/sites/cinejoy.dart';
import '../scraper/sites/dulo.dart';
import '../scraper/sites/vidup.dart';
import '../scraper/sites/flaxmovies.dart';
import '../scraper/sites/vidgod.dart';
import '../scraper/sites/vidfast.dart';
import '../scraper/sites/peestream.dart';
import '../scraper/sites/lookmovie.dart';
import '../scraper/sites/hexa.dart';
import '../scraper/sites/bcine.dart';
import '../scraper/sites/mapple.dart';
import '../scraper/sites/nova.dart';
import '../scraper/sites/megasource.dart';
import '../scraper/sites/purstream.dart';
import '../scraper/sites/vidapi.dart';
import '../scraper/sites/vidrock.dart';
import '../scraper/sites/vidvault.dart';
import '../scraper/sites/vidzee.dart';
import '../scraper/sites/cinesrc.dart';
import '../scraper/sites/cinesu.dart';
import '../scraper/sites/frame.dart';
import '../scraper/sites/fsharetv.dart';
import '../scraper/sites/fsonic.dart';
import '../scraper/sites/fsonline.dart';
import '../scraper/sites/kisskh.dart';
import '../scraper/sites/lmscript.dart';
import '../scraper/sites/meowtv.dart';
import '../scraper/sites/vidlink.dart';
import '../scraper/sites/vixsrc.dart';
import '../scraper/sites/xpass.dart';
import '../scraper/sites/a111477.dart';
import '../scraper/sites/vadapav.dart';
import '../scraper/sites/hindmoviez.dart';
import '../anime/anime_scraper_service.dart';
import '../anime/kitsu_resolver.dart';
import '../anime_arabic/anime_arabic_service.dart';
import '../anime_arabic/anime_arabic_extractor.dart';

/// Service that fetches playback streams from all installed Stremio addons
/// and built-in scrapers.
class StreamService {
  StreamService._();

  /// Scrapers whose upstream hosts are gone (2026-11-06 audit: DNS/timeout).
  /// Keeping them registered only burns the resolve budget; the verified
  /// default stream addons cover the same content.
  static const Set<String> retiredScrapers = {
    'bcine',
    'cinesrc',
    'cinesu',
    'downloadeverything',
    'hindmoviez',
    'lookmovie',
    'torrentgalaxy',
    'vidgod',
    'vidrock',
    'vidsrc',
    'vidvault',
    'vuflix',
    'vixsrc',
    'fsonline',
    'movy',
  };

  static void _reg(StreamScraper scraper) {
    if (retiredScrapers.contains(scraper.name.toLowerCase())) return;
    ScraperManager.instance.registerScraper(scraper);
  }

  static void _registerBuiltInScrapers() {
    // Source of truth = builtin addon entry (kept in lockstep with the
    // Settings switch via AddonManager.toggleAddon). isP2pEnabled mirrors it.
    if (AddonManager.instance.isDizzyActive) {
      ScraperManager.instance.registerScraper(KnabenScraper());
      _reg(TorrentGalaxyScraper());
    } else {
      ScraperManager.instance.unregisterTorrentScrapers();
    }
    _reg(A111477Scraper());
    _reg(VadapavScraper());
    _reg(HindMoviezScraper());
    _reg(FourKHDHubScraper());
    _reg(XDownloaderScraper());
    _reg(VideasyScraper());
    _reg(VidSrcScraper());
    _reg(MultiEmbedScraper());
    _reg(VidCoreScraper());
    _reg(FlyStreamScraper());
    _reg(MovieNightScraper());
    _reg(DownloadEverythingScraper());
    _reg(MovyScraper());
    _reg(VuflixScraper());
    _reg(RiveStreamScraper());
    _reg(CinejoyScraper());
    _reg(DuloScraper());
    _reg(VidUpScraper());
    _reg(FlaxMoviesScraper());
    _reg(VidGodScraper());
    _reg(VidFastScraper());
    _reg(PeeStreamScraper());
    _reg(LookMovieScraper());
    _reg(HexaScraper());
    _reg(BcineScraper());
    _reg(MappleScraper());
    _reg(NovaScraper());
    _reg(MegaSourceScraper());
    _reg(PurstreamScraper());
    _reg(VidApiScraper());
    _reg(VidRockScraper());
    _reg(VidVaultScraper());
    _reg(VidZeeScraper());
    _reg(CineSrcScraper());
    _reg(CineSuScraper());
    _reg(FrameScraper());
    _reg(FshareTvScraper());
    _reg(FSonicScraper());
    _reg(FSOnlineScraper());
    _reg(KissKhScraper());
    _reg(LMScriptScraper());
    _reg(MeowTvScraper());
    _reg(VidLinkScraper());
    _reg(VixSrcScraper());
    _reg(XPassScraper());
  }

  /// Fetches streams from all active stream-capable addons for the given
  /// content type and ID.
  static Stream<StreamSource> fetchStreams({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final controller = StreamController<StreamSource>();

    // 18+ Heaven: adult stream addons answer only when the gate is open.
    final addons = AddonManager.instance.activeStreamAddons
        .where(AddonManager.allowAddon)
        .toList(growable: false);
    final isHttpActive = AddonManager.instance.isDizzyHttpActive;

    if (addons.isEmpty && !isHttpActive) {
      controller.close();
      return controller.stream;
    }

    _registerBuiltInScrapers();

    int pending = addons.length + (isHttpActive ? 1 : 0);

    // A listener cancel does NOT set isClosed, so cancellation needs its own
    // flag — otherwise queued addons keep hitting the network after the user
    // has left the sheet (and every late result is buffered forever).
    var disposed = false;
    StreamSubscription<StreamSource>? scraperSub;
    Timer? budget;
    var closed = false;

    void closeOnce() {
      if (closed) return;
      closed = true;
      budget?.cancel();
      if (!controller.isClosed) controller.close();
    }

    // Hard resolve budget: past 20s the sheet shows what it already has, and
    // the scrape itself is cancelled (not just the UI stream).
    budget = Timer(const Duration(seconds: 20), () {
      scraperSub?.cancel();
      closeOnce();
    });

    controller.onCancel = () {
      disposed = true;
      budget?.cancel();
      scraperSub?.cancel();
    };

    // Built-in scrapers (if active)
    if (isHttpActive) {
      final isImdb = id.startsWith('tt');
      final cleanImdbId = isImdb ? id.split(':')[0] : null;

      scraperSub = ScraperManager.instance
          .scrapeAll(
            type: type,
            title: title,
            year: year,
            season: season,
            episode: episode,
            imdbId: cleanImdbId,
          )
          .listen(
            (source) {
              if (!disposed && !controller.isClosed) controller.add(source);
            },
            onDone: () {
              pending--;
              if (pending <= 0) closeOnce();
            },
          );
    }

    // P4: bounded addon pool — a flat window of 10 addon fetches. A worker
    // takes the next addon the moment its own fetch finishes, so addon #11
    // no longer waits for #10's whole wave. Close semantics unchanged.
    () async {
      const addonParallel = 10;
      final queue = List<InstalledAddon>.from(addons);

      Future<void> runAddon(InstalledAddon addon) async {
        try {
          final sources = await _fetchFromAddon(
            addon,
            type,
            id,
            season: season,
            episode: episode,
          );
          if (!disposed && !controller.isClosed) {
            for (final source in sources) {
              controller.add(source);
            }
          }
        } catch (_) {
        } finally {
          pending--;
          if (pending <= 0) closeOnce();
        }
      }

      Future<void> worker() async {
        while (queue.isNotEmpty) {
          if (disposed || controller.isClosed) return;
          await runAddon(queue.removeAt(0));
        }
      }

      await Future.wait(
        List.generate(
          addons.length < addonParallel ? addons.length : addonParallel,
          (_) => worker(),
        ),
      );
    }();

    return controller.stream;
  }

  /// Fetches streams specifically for a targeted provider/addon that was previously used by the user.
  ///
  /// - If [targetAddonName] == 'DizzyHTTP' (legacy, pre-v1.2.0): scrapes all built-in alive HTTP scrapers.
  /// - If [targetAddonName] == 'Dizzy' (legacy): only built-in torrent scrapers.
  /// - If [targetAddonName] is a v1.2.0 site key (e.g. 'flystream'): prefers that scraper, falls back to full pool.
  /// - If [targetAddonName] matches a Stremio addon (e.g. 'Torrentio', 'CyberFlix'): Only calls that specific addon.
  static Stream<StreamSource> fetchStreamsForTargetAddon({
    required String targetAddonName,
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final controller = StreamController<StreamSource>();
    final normalizedTarget = targetAddonName.trim().toLowerCase();

    final isArabicAnime =
        id.startsWith('arabic_anime:') ||
        normalizedTarget == 'arabicanime' ||
        normalizedTarget.contains('arabic');

    if (isArabicAnime) {
      () async {
        try {
          String slug = '';
          if (id.startsWith('arabic_anime:')) {
            final parts = id.split(':');
            if (parts.length >= 2) slug = parts[1];
          } else if (id.isNotEmpty) {
            slug = id;
          }
          if (slug.isEmpty && title.isNotEmpty) {
            final searchResults = await AnimeArabicService.instance.search(
              title,
            );
            if (searchResults.isNotEmpty) {
              slug = searchResults.first.slug;
            }
          }
          final epNum = episode ?? 1;
          if (slug.isNotEmpty) {
            final details = await AnimeArabicService.instance.getDetails(slug);
            final targetEp = details.episodes.firstWhere(
              (e) => e.number == epNum,
              orElse: () => ArabicEpisode(
                number: epNum,
                title: 'الحلقة $epNum',
                encodedHref: '',
                watchPath: '/e/$slug-$epNum#tok',
              ),
            );
            final hits = await AnimeArabicExtractor.instance.resolveEpisode(
              targetEp,
            );
            final sources = AnimeArabicExtractor.toSources(
              hits,
              animeTitle: details.title,
              episodeNumber: epNum,
            );
            for (final s in sources) {
              if (!controller.isClosed) controller.add(s);
            }
          }
        } catch (_) {}
        if (!controller.isClosed) controller.close();
      }();
      return controller.stream;
    }

    // Check if targeting general anime providers
    final isAnime =
        type == 'anime' ||
        id.startsWith('anilist:') ||
        normalizedTarget == 'megaplay' ||
        normalizedTarget == 'anidb' ||
        normalizedTarget == 'watchhentai' ||
        normalizedTarget == 'hentaini' ||
        normalizedTarget == 'anime';

    if (isAnime) {
      int? anilistId;
      if (id.startsWith('anilist:')) {
        final parts = id.split(':');
        if (parts.length >= 2) {
          anilistId = int.tryParse(parts[1]);
        }
      }
      return AnimeScraperService.instance.scrapeStreamsByDetails(
        title: title,
        anilistId: anilistId,
        episodeNumber: episode ?? 1,
      );
    }

    // Check if targeting built-in DizzyHTTP / Dizzy
    // v1.2.0-P1: Continue Watching stores unique site keys (e.g. 'flystream',
    // 'vidsrc') but ALSO legacy 'DizzyHTTP' (pre-v1.2.0). DizzyHTTP = run the
    // full HTTP pool; a unique key = filter that scraper's sources after the
    // run. Legacy 'Dizzy' = torrent-only filter. Zero-match targets fall back
    // to the general fetch (never an empty screen).
    final isLocalDizzyTorrent = normalizedTarget == 'dizzy';
    final isLegacyHttpPool =
        normalizedTarget == 'dizzyhttp' ||
        (normalizedTarget.contains('dizzy') && !isLocalDizzyTorrent);

    // A unique v1.2.0 site key (e.g. 'flystream') = prefer that scraper's
    // sources, fall back to the full pool when it yields nothing.
    final isUniqueSiteKey =
        !isLegacyHttpPool &&
        !isLocalDizzyTorrent &&
        ScraperManager.instance.hasScraper(normalizedTarget);

    if (isLegacyHttpPool || isLocalDizzyTorrent || isUniqueSiteKey) {
      _registerBuiltInScrapers();

      final isImdb = id.startsWith('tt');
      final cleanImdbId = isImdb ? id.split(':')[0] : null;
      final siteKeyFallback = <StreamSource>[];
      var siteKeyDirectHits = 0;

      StreamSubscription<StreamSource>? sub;
      controller.onCancel = () => sub?.cancel();

      sub = ScraperManager.instance
          .scrapeAll(
            type: type,
            title: title,
            year: year,
            season: season,
            episode: episode,
            imdbId: cleanImdbId,
          )
          .listen(
            (source) {
              if (!controller.isClosed) {
                // Legacy DizzyHTTP pool = HTTP-only; legacy Dizzy = torrents-only.
                if (isLegacyHttpPool &&
                    (source.infoHash != null && source.infoHash!.isNotEmpty)) {
                  return;
                }
                if (isLocalDizzyTorrent &&
                    (source.infoHash == null || source.infoHash!.isEmpty)) {
                  return;
                }
                // Unique site key: stash non-matching sources for fallback.
                if (isUniqueSiteKey &&
                    source.addonName.trim().toLowerCase() != normalizedTarget) {
                  siteKeyFallback.add(source);
                  return;
                }
                if (isUniqueSiteKey) siteKeyDirectHits++;
                controller.add(source);
              }
            },
            onError: (_) {},
            onDone: () {
              // Unique key with zero direct hits → release the fallback pool.
              if (isUniqueSiteKey &&
                  siteKeyDirectHits == 0 &&
                  !controller.isClosed) {
                for (final s in siteKeyFallback) {
                  controller.add(s);
                }
              }
              if (!controller.isClosed) controller.close();
            },
          );

      return controller.stream;
    }

    // Otherwise, find the matching Stremio addon.
    // 18+ Heaven: adult addons match only when the gate is open.
    final matchingAddons = AddonManager.instance.activeStreamAddons
        .where(
          (a) =>
              AddonManager.allowAddon(a) &&
              (a.manifest.name.toLowerCase() == normalizedTarget ||
                  a.manifest.name.toLowerCase().contains(normalizedTarget) ||
                  normalizedTarget.contains(a.manifest.name.toLowerCase())),
        )
        .toList();

    if (matchingAddons.isNotEmpty) {
      final matchingAddon = matchingAddons.first;
      () async {
        var fetchType = type;
        var fetchId = id;
        // Anime pages carry an AniList id; addons understand Kitsu. Resolve
        // once so the panel keeps working instead of showing "No streams".
        if (id.startsWith('anilist:')) {
          final kitsuId = await KitsuResolver.instance.kitsuIdFor(
            anilistId: int.tryParse(id.substring('anilist:'.length)),
            titles: [title],
            year: year,
          );
          if (kitsuId != null) {
            fetchType = 'anime';
            fetchId = 'kitsu:$kitsuId';
          }
        }
        final sources = await _fetchFromAddon(
          matchingAddon,
          fetchType,
          fetchId,
          season: season,
          episode: episode,
        );
        if (!controller.isClosed) {
          for (final source in sources) {
            controller.add(source);
          }
          await controller.close();
        }
      }();
    } else {
      // Fallback: If no exact addon match found, run general fetch
      return fetchStreams(
        type: type,
        id: id,
        title: title,
        year: year,
        season: season,
        episode: episode,
      );
    }

    return controller.stream;
  }

  /// Stremio stream path for an addon call.
  ///
  /// Series and anime addons need the episode in the ID itself
  /// (`series/tt123:1:2`, `anime/kitsu:123:53`); calling with the bare title
  /// ID returns nothing or the wrong episode.
  static String buildAddonStreamPath({
    required String type,
    required String id,
    int? season,
    int? episode,
  }) => StreamAddonService.buildPath(
    type: type,
    id: id,
    season: season,
    episode: episode,
  );

  static Future<List<StreamSource>> _fetchFromAddon(
    InstalledAddon addon,
    String type,
    String id, {
    int? season,
    int? episode,
  }) => StreamAddonService.fetchFrom(
    addon,
    type,
    id,
    season: season,
    episode: episode,
  );
}
