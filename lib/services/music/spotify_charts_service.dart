import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/music/music_track.dart';

/// One Spotify editorial chart, as published on the public web player.
class SpotifyChartSpec {
  /// Stable cache key + rail identity.
  final String key;

  /// Public playlist id behind the chart card.
  final String playlistId;

  /// Rail title shown on Dizzy's home.
  final String railTitle;

  /// Album label attached to every track (used by the player + queue).
  final String albumTitle;

  /// `true` for the weekly "Top Songs" chart, `false` for the daily
  /// "Top 50" chart. Spotify publishes both cadences for India and
  /// Global; the cadence is what the title promises, so it is kept.
  final bool weekly;

  const SpotifyChartSpec({
    required this.key,
    required this.playlistId,
    required this.railTitle,
    required this.albumTitle,
    required this.weekly,
  });
}

/// The four charts the Spotify India page surfaces, in the order Dizzy
/// shows them: India daily, India weekly, Global daily, Global weekly.
const List<SpotifyChartSpec> kSpotifyChartSpecs = <SpotifyChartSpec>[
  SpotifyChartSpec(
    key: 'top50_in',
    playlistId: '37i9dQZEVXbLZ52XmnySJg',
    railTitle: '🇮🇳 Top 50 India · Daily',
    albumTitle: 'Top 50 - India',
    weekly: false,
  ),
  SpotifyChartSpec(
    key: 'top_songs_in',
    playlistId: '37i9dQZEVXbMWDif5SCBJq',
    railTitle: '🇮🇳 Top Songs India · Weekly',
    albumTitle: 'Top Songs - India',
    weekly: true,
  ),
  SpotifyChartSpec(
    key: 'top50_global',
    playlistId: '37i9dQZEVXbMDoHDwVN2tF',
    railTitle: '🌍 Top 50 Global · Daily',
    albumTitle: 'Top 50 - Global',
    weekly: false,
  ),
  SpotifyChartSpec(
    key: 'top_songs_global',
    playlistId: '37i9dQZEVXbNG2KDcFcKOF',
    railTitle: '🌍 Top Songs Global · Weekly',
    albumTitle: 'Top Songs - Global',
    weekly: true,
  ),
];

class SpotifyChart {
  final SpotifyChartSpec spec;
  final String coverUrl;
  final List<MusicTrack> tracks;
  final DateTime fetchedAt;

  const SpotifyChart({
    required this.spec,
    required this.coverUrl,
    required this.tracks,
    required this.fetchedAt,
  });

  bool get isEmpty => tracks.isEmpty;
}

class _ChartEntry {
  final SpotifyChart? chart;
  final DateTime expiresAt;
  _ChartEntry(this.chart, this.expiresAt);
}

/// Dynamic Spotify chart feed (2026-11-12).
///
/// Reads the four editorial charts straight from the public web player
/// embed — no account, no API key, no server deploy. The embed page ships
/// its playlist state in `__NEXT_DATA__`, so one GET returns the chart
/// name, its real cover art, and the full 50-track list with titles,
/// artists, durations and a 30s preview.
///
/// Refresh cadence is the calendar day: the cache key carries the date,
/// so the first home load after midnight refetches and the rails change
/// on their own. A failed fetch is retried after 15 minutes instead of
/// being cached for the whole day, so one flaky request never blanks the
/// charts until tomorrow.
///
/// Playback: chart tracks carry `spotify_<id>` ids as pure metadata.
/// [YoutubeStreamResolver] resolves audio from title + artist + duration,
/// so these entries play like any other track while the chart position,
/// art and cadence stay Spotify's.
class SpotifyChartsService {
  SpotifyChartsService._();

  static final SpotifyChartsService instance = SpotifyChartsService._();

  static const Duration _requestBudget = Duration(seconds: 12);
  static const Duration _failureBackoff = Duration(minutes: 15);

  static const String _embedBase = 'https://open.spotify.com/embed/playlist/';

  Future<String> Function(Uri uri)? _fetchOverride;
  final Map<String, _ChartEntry> _cache = <String, _ChartEntry>{};
  final Map<String, Future<SpotifyChart?>> _inFlight = {};

  /// Test seam: build an isolated instance whose HTML comes from
  /// [fetch] instead of the network. Nothing else changes.
  @visibleForTesting
  factory SpotifyChartsService.withFetcher(
    Future<String> Function(Uri uri) fetch,
  ) {
    final service = SpotifyChartsService._();
    service._fetchOverride = fetch;
    return service;
  }

  /// All four charts in display order. A chart that fails to load is
  /// omitted, never replaced with a placeholder.
  Future<List<SpotifyChart>> fetchAll() async {
    final charts = await Future.wait<SpotifyChart?>([
      for (final spec in kSpotifyChartSpecs) chart(spec),
    ]);
    return charts.whereType<SpotifyChart>().where((c) => !c.isEmpty).toList();
  }

  /// One chart, cached for the current calendar day.
  Future<SpotifyChart?> chart(SpotifyChartSpec spec) async {
    final now = DateTime.now();
    final cached = _cache[spec.key];
    if (cached != null && cached.expiresAt.isAfter(now)) return cached.chart;

    final inFlight = _inFlight[spec.key];
    if (inFlight != null) return inFlight;

    final future = _load(spec, now);
    _inFlight[spec.key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(spec.key);
    }
  }

  Future<SpotifyChart?> _load(SpotifyChartSpec spec, DateTime now) async {
    try {
      final html = await _fetchHtml(Uri.parse('$_embedBase${spec.playlistId}'));
      final chart = parseChartHtml(html, spec, now: now);
      if (chart == null || chart.isEmpty) {
        _cache[spec.key] = _ChartEntry(null, now.add(_failureBackoff));
        return null;
      }
      _cache[spec.key] = _ChartEntry(chart, _endOfDay(now));
      return chart;
    } catch (e) {
      debugPrint('Spotify chart ${spec.key} failed (soft): $e');
      _cache[spec.key] = _ChartEntry(null, now.add(_failureBackoff));
      return null;
    }
  }

  Future<String> _fetchHtml(Uri uri) async {
    final override = _fetchOverride;
    if (override != null) return override(uri);

    final res = await http
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/131.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'en-IN,en;q=0.9',
          },
        )
        .timeout(_requestBudget);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', uri);
    }
    // Spotify serves UTF-8; decoding the bytes explicitly keeps
    // Devanagari/Punjabi titles intact instead of latin1-mangling them.
    return utf8.decode(res.bodyBytes);
  }

  /// Parses one embed page into a chart. Pure and synchronous so the
  /// parser is unit-testable without the network.
  @visibleForTesting
  static SpotifyChart? parseChartHtml(
    String html,
    SpotifyChartSpec spec, {
    DateTime? now,
  }) {
    final entity = _entityFromHtml(html);
    if (entity == null) return null;

    final coverUrl = _coverUrlFrom(entity);
    final trackList = entity['trackList'];
    if (trackList is! List) return null;

    final tracks = <MusicTrack>[];
    for (final row in trackList) {
      if (row is! Map) continue;
      final title = row['title']?.toString().trim() ?? '';
      if (title.isEmpty) continue;

      final uri = row['uri']?.toString() ?? '';
      final trackId = uri.contains(':') ? uri.split(':').last : '';
      final durationMs = int.tryParse(row['duration']?.toString() ?? '') ?? 0;
      final preview = row['audioPreview'];
      final previewUrl = preview is Map ? preview['url']?.toString() : null;

      tracks.add(
        MusicTrack(
          id: trackId.isEmpty
              ? 'spotify_${spec.key}_${tracks.length}'
              : 'spotify_$trackId',
          title: title,
          artist: row['subtitle']?.toString().trim() ?? '',
          album: spec.albumTitle,
          coverUrl: coverUrl,
          durationSeconds: durationMs > 0 ? (durationMs / 1000).round() : 0,
          explicit: row['isExplicit'] == true,
          previewUrl: (previewUrl == null || previewUrl.isEmpty)
              ? null
              : previewUrl,
          trackNumber: tracks.length + 1,
        ),
      );
    }

    return SpotifyChart(
      spec: spec,
      coverUrl: coverUrl,
      tracks: tracks,
      fetchedAt: now ?? DateTime.now(),
    );
  }

  static Map<String, dynamic>? _entityFromHtml(String html) {
    final match = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) return null;

    try {
      final decoded = jsonDecode(match.group(1)!);
      if (decoded is! Map) return null;
      final props = decoded['props'];
      if (props is! Map) return null;
      final pageProps = props['pageProps'];
      if (pageProps is! Map) return null;
      final state = pageProps['state'];
      if (state is! Map) return null;
      final data = state['data'];
      if (data is! Map) return null;
      final entity = data['entity'];
      return entity is Map<String, dynamic> ? entity : null;
    } catch (_) {
      return null;
    }
  }

  static String _coverUrlFrom(Map<String, dynamic> entity) {
    final coverArt = entity['coverArt'];
    if (coverArt is Map) {
      final sources = coverArt['sources'];
      if (sources is List) {
        for (final source in sources) {
          if (source is Map) {
            final url = source['url']?.toString() ?? '';
            if (url.isNotEmpty) return url;
          }
        }
      }
    }
    final visual = entity['visualIdentity'];
    if (visual is Map) {
      final url = visual['url']?.toString() ?? '';
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  static DateTime _endOfDay(DateTime now) =>
      DateTime(now.year, now.month, now.day + 1);

  /// Test seam: drop the cache so the next call refetches.
  @visibleForTesting
  void debugClear() {
    _cache.clear();
    _inFlight.clear();
  }
}
