/// Source probe: one scraper, one TMDB id, one player.
///
/// This exists because a full app run cannot answer "is THIS scraper giving a
/// playable video for THIS episode?" without the race, the failover chain and
/// the UI in between. Here the answer is direct: scrape with exactly one
/// scraper, list what it returned, and open a returned URL with the same
/// player settings the app uses.
///
/// Nothing in this file is app code: it only *calls* app code (scrapers,
/// [TmdbHelper], [PlayerSettings]) so a probe result always describes the
/// shipped behaviour.
library;

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/player_settings.dart';
import 'package:dizzy/services/scraper/sites/tmdb_helper.dart';
import 'package:dizzy/services/scraper/stream_scraper.dart';

/// What the user typed into the probe.
enum ProbeKind { movie, series }

extension ProbeKindX on ProbeKind {
  bool get isSeries => this == ProbeKind.series;

  /// The value the app passes to [StreamScraper.scrapeStream] (scrapers branch
  /// on `'series'`, not on `'tv'`).
  String get scrapeType => isSeries ? 'series' : 'movie';

  /// The TMDB endpoint segment for this kind.
  String get tmdbEndpoint => isSeries ? 'tv' : 'movie';

  String get label => isSeries ? 'Series' : 'Movie';
}

/// TMDB identity for one title, in the shape the scrapers expect.
class ProbeMetadata {
  const ProbeMetadata({
    required this.title,
    required this.kind,
    this.year,
    this.imdbId,
  });

  final String title;
  final ProbeKind kind;
  final int? year;
  final String? imdbId;

  String get scrapeType => kind.scrapeType;

  /// Builds metadata from a TMDB `movie/{id}` or `tv/{id}` detail payload.
  ///
  /// Returns null when the payload has no usable title: a probe run with an
  /// empty title would silently scrape nothing and read as "scraper is dead".
  static ProbeMetadata? fromTmdbDetail(
    Map<String, dynamic>? detail,
    ProbeKind kind, {
    String? imdbId,
  }) {
    if (detail == null) return null;
    final rawTitle = kind.isSeries
        ? (detail['name'] ?? detail['original_name'])
        : (detail['title'] ?? detail['original_title']);
    final title = rawTitle?.toString().trim() ?? '';
    if (title.isEmpty) return null;
    final rawDate =
        (kind.isSeries ? detail['first_air_date'] : detail['release_date'])
            ?.toString();
    final rawImdb = imdbId ?? detail['imdb_id']?.toString();
    return ProbeMetadata(
      title: title,
      kind: kind,
      year: _yearOf(rawDate),
      imdbId: (rawImdb != null && rawImdb.startsWith('tt')) ? rawImdb : null,
    );
  }

  /// First four digits of a TMDB date (`2026-10-09` → `2026`).
  static int? _yearOf(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  @override
  String toString() =>
      '$title${year != null ? ' ($year)' : ''} · $scrapeType'
      '${imdbId != null ? ' · $imdbId' : ''}';
}

/// Resolves a TMDB id to [ProbeMetadata] through the app's keyless-first chain.
class ProbeMetadataResolver {
  const ProbeMetadataResolver();

  Future<ProbeMetadata?> resolve({
    required int tmdbId,
    required ProbeKind kind,
  }) async {
    final detail = await TmdbHelper.fetchDetail(
      endpoint: kind.tmdbEndpoint,
      tmdbId: tmdbId,
    );
    var meta = ProbeMetadata.fromTmdbDetail(detail, kind);
    if (meta == null) return null;
    if (meta.imdbId == null) {
      // `imdb_id` is not on every detail payload; external_ids is the backup
      // (and it is what the id-first scrapers need).
      final imdb = await TmdbHelper.fetchImdbId(
        endpoint: kind.tmdbEndpoint,
        tmdbId: tmdbId,
      );
      if (imdb != null) {
        meta = ProbeMetadata(
          title: meta.title,
          kind: meta.kind,
          year: meta.year,
          imdbId: imdb,
        );
      }
    }
    return meta;
  }
}

/// How a returned [StreamSource] has to be played.
enum SourceShape { hls, dash, progressive, file, embed, torrent, local, unknown }

extension SourceShapeX on SourceShape {
  String get label => switch (this) {
    SourceShape.hls => 'HLS',
    SourceShape.dash => 'DASH',
    SourceShape.progressive => 'MP4',
    SourceShape.file => 'FILE',
    SourceShape.embed => 'EMBED',
    SourceShape.torrent => 'TORRENT',
    SourceShape.local => 'LOCAL',
    SourceShape.unknown => '???',
  };

  /// True when mpv can open it directly. Embeds need the app's webview and
  /// torrents need TorrServer, so the probe names them instead of failing.
  bool get opensInMpv =>
      this != SourceShape.embed && this != SourceShape.torrent;
}

/// Classifies [source] the way the player decides how to open it.
SourceShape classifySource(StreamSource source) {
  final url = (source.url ?? '').trim();
  final external = (source.externalUrl ?? '').trim();
  if ((source.infoHash ?? '').isNotEmpty || url.startsWith('magnet:')) {
    return SourceShape.torrent;
  }
  if (source.isEmbedSource || (url.isEmpty && external.isNotEmpty)) {
    return SourceShape.embed;
  }
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  if (path.endsWith('.m3u8') || url.contains('.m3u8')) return SourceShape.hls;
  if (path.endsWith('.mpd') || url.contains('.mpd')) return SourceShape.dash;
  for (final ext in const ['.mp4', '.mkv', '.webm', '.avi', '.mov', '.ts']) {
    if (path.endsWith(ext)) return SourceShape.progressive;
  }
  if (url.startsWith('file:') || path.endsWith('.mp4')) return SourceShape.local;
  if (url.isEmpty) return SourceShape.unknown;
  // Extension-less direct link — worker-hosted downloads (`/d/…`), signed CDN
  // tokens and similar. The app hands every non-embed, non-torrent URL to mpv
  // whatever the extension says, so the probe must label them as direct files
  // instead of '???'. `unknown` stays reserved for "nothing to open at all".
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return SourceShape.file;
  }
  return SourceShape.unknown;
}

/// A single probe run: what one scraper returned for one target.
class ProbeRun {
  ProbeRun({
    required this.scraperName,
    required this.sources,
    required this.elapsed,
    this.error,
  });

  final String scraperName;
  final List<StreamSource> sources;
  final Duration elapsed;
  final Object? error;

  bool get isEmpty => sources.isEmpty;

  Map<SourceShape, int> get shapeCounts {
    final counts = <SourceShape, int>{};
    for (final s in sources) {
      final shape = classifySource(s);
      counts[shape] = (counts[shape] ?? 0) + 1;
    }
    return counts;
  }

  String get summary {
    if (error != null) return '$scraperName: ERROR $error';
    if (sources.isEmpty) {
      return '$scraperName: 0 sources in ${elapsed.inMilliseconds}ms';
    }
    final parts = shapeCounts.entries
        .map((e) => '${e.value} ${e.key.label}')
        .join(', ');
    return '$scraperName: ${sources.length} sources ($parts) '
        'in ${elapsed.inMilliseconds}ms';
  }
}

/// Runs exactly one scraper for one target.
class SourceProbe {
  const SourceProbe({this.timeout = const Duration(seconds: 45)});

  /// Scrapers can sit on slow upstreams; this is a hard cap so the probe UI
  /// never hangs without an answer.
  final Duration timeout;

  Future<ProbeRun> run({
    required StreamScraper scraper,
    required ProbeMetadata meta,
    int? season,
    int? episode,
  }) async {
    final watch = Stopwatch()..start();
    final collected = <StreamSource>[];
    Object? failure;
    try {
      await for (final source in scraper
          .scrapeStream(
            type: meta.scrapeType,
            title: meta.title,
            year: meta.year,
            season: meta.kind.isSeries ? season : null,
            episode: meta.kind.isSeries ? episode : null,
            imdbId: meta.imdbId,
          )
          .timeout(timeout)) {
        collected.add(source);
      }
    } catch (e) {
      failure = e;
    }
    watch.stop();
    return ProbeRun(
      scraperName: scraper.name,
      sources: collected,
      elapsed: watch.elapsed,
      error: failure,
    );
  }
}

/// Everything the player needs to open [source] exactly like the app does.
class OpenPlan {
  const OpenPlan({
    required this.url,
    required this.headers,
    required this.isLive,
    required this.isTorrentStream,
  });

  final String url;
  final Map<String, String>? headers;
  final bool isLive;
  final bool isTorrentStream;
}

/// Builds the open plan for [source] with the app's own resolution rules
/// (`_initStream`): `::` sanitising, CDN header resolution and `proxyHeaders`
/// merging.
OpenPlan buildOpenPlan(StreamSource source) {
  final raw = (source.url ?? source.externalUrl ?? '').trim();
  final sanitized = raw.contains('::') ? raw.replaceAll('::', '%3A%3A') : raw;
  final headers = PlayerSettings.resolveStreamHeaders(sanitized, source.headers);
  final proxy = source.behaviorHints?['proxyHeaders']?['request'];
  if (proxy is Map) {
    headers.addAll(Map<String, String>.from(proxy));
  }
  final lower = sanitized.toLowerCase();
  final isLive =
      source.behaviorHints?['isLive'] == true ||
      source.addonName.toLowerCase() == 'iptv' ||
      (source.name ?? '').toLowerCase() == 'iptv' ||
      lower.contains('/live/') ||
      lower.contains('/hls/live');
  final isTorrentStream =
      lower.contains(':8090') ||
      lower.contains('/stream?link=') ||
      lower.contains('/stream?');
  return OpenPlan(
    url: sanitized,
    headers: headers.isEmpty ? null : headers,
    isLive: isLive,
    isTorrentStream: isTorrentStream,
  );
}

/// Short, single-line description of a source for the results table.
String describeSource(StreamSource source) {
  final quality = source.quality;
  final title = (source.title ?? source.name ?? '').trim();
  final bits = <String>[
    classifySource(source).label,
    if (quality != null && quality.isNotEmpty) quality,
    if (title.isNotEmpty) title,
  ];
  return bits.join(' · ');
}
