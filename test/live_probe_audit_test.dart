// TEMPORARY — v1.3.5 M2 Task 7: liveness audit of every active HTTP scraper.
//
// What it measures, per scraper x title:
//   listed    - the scraper yielded a source with a URL / embed / info hash
//   playable  - the URL actually hands over bytes (playlist + first segment)
//   embed     - the source is an externalUrl embed (no direct URL to verify)
//   exception - the scrape threw / timed out
//
// A LISTED source is not a PLAYABLE source. The owner's report was
// "posters and catalogues are there, but there are almost no sources", so
// both numbers are recorded and never conflated.
//
// Corpus: 10 mainstream NEW + 10 mainstream OLD titles (5 movies + 5 series
// in each half). Mainstream = TMDB original_language en or hi ONLY.
// Odia / regional titles are deliberately EXCLUDED from this audit (owner
// decision 2026-11-16: they need their own scraper and their own plan).
//
// Usage:
//   flutter test test/live_probe_audit_test.dart --dart-define-from-file=.env \
//     --reporter expanded
//   PROBE_SET=new|old   (env var, optional, filters the half)
//
// Results: artifacts/audit-dsh/scraper_audit_probe.log  (PROBE| + SUMMARY|)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/config/env_service.dart';
import 'package:dizzy/services/scraper/stream_scraper.dart';
import 'package:dizzy/services/scraper/sites/a111477.dart';
import 'package:dizzy/services/scraper/sites/kisskh.dart';
import 'package:dizzy/services/scraper/sites/lmscript.dart';
import 'package:dizzy/services/scraper/sites/meowtv.dart';
import 'package:dizzy/services/scraper/sites/movy.dart';
import 'package:dizzy/services/scraper/sites/rivestream.dart';
import 'package:dizzy/services/scraper/sites/vadapav.dart';
import 'package:dizzy/services/scraper/sites/videasy.dart';
import 'package:dizzy/services/scraper/sites/vidapi.dart';
import 'package:dizzy/services/scraper/sites/vidcore.dart';
import 'package:dizzy/services/scraper/sites/vidfast.dart';
import 'package:dizzy/services/scraper/sites/vidlink.dart';
import 'package:dizzy/services/scraper/sites/vidup.dart';
import 'package:dizzy/services/scraper/sites/vidzee.dart';

class _Title {
  final String type; // movie | series
  final String title;
  final int year;
  final int tmdbId;
  final String imdbId;
  final bool isNew;
  const _Title({
    required this.type,
    required this.title,
    required this.year,
    required this.tmdbId,
    required this.imdbId,
    required this.isNew,
  });
}

final _logFile = File('artifacts/audit-dsh/scraper_audit_probe.log');
const _tmdb = 'https://api.themoviedb.org/3';
const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

void _log(String line) {
  _logFile.parent.createSync(recursive: true);
  _logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

String _host(String? u) {
  if (u == null || u.isEmpty) return '-';
  final p = Uri.tryParse(u);
  return (p == null || p.host.isEmpty) ? (u.isEmpty ? '-' : u) : p.host;
}

// ---------------------------------------------------------------------------
// TMDB corpus — mainstream only (en / hi).
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>?> _tmdbGet(
  String path,
  String key, {
  Map<String, String> extra = const {},
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    // MERGE, never replace: Uri.replace(queryParameters:) drops the query
    // string that is already on the path (that silently emptied the corpus).
    final base = Uri.parse('$_tmdb$path');
    final merged = <String, String>{
      ...base.queryParameters,
      ...extra,
      'api_key': key,
      'language': 'en-US',
    };
    final uri = base.replace(queryParameters: merged);
    final req = await client.getUrl(uri);
    req.headers.set('User-Agent', _ua);
    req.headers.set('Accept', 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<String?> _imdbId(int tmdbId, String kind, String key) async {
  final json = await _tmdbGet('/$kind/$tmdbId/external_ids', key);
  if (json == null) return null;
  final id = json['imdb_id'];
  if (id == null || id.toString().isEmpty) return null;
  return id.toString();
}

Future<List<_Title>> _discover({
  required String kind,
  required String key,
  required bool isNew,
  required int take,
}) async {
  final out = <_Title>[];
  final today = DateTime.now();
  // The RESULT field differs from the FILTER field on TMDB: discover/movie
  // returns `release_date` (the filter is `primary_release_date`).
  final resultDateField = kind == 'tv' ? 'first_air_date' : 'release_date';
  final filterDateField = kind == 'tv' ? 'first_air_date' : 'primary_release_date';
  final params = <String, String>{
    'sort_by': isNew ? '$filterDateField.desc' : 'vote_average.desc',
    'vote_count.gte': isNew ? '150' : '800',
    'page': '1',
  };
  if (isNew) {
    params['$filterDateField.lte'] = today.toIso8601String().substring(0, 10);
    params['$filterDateField.gte'] = DateTime.now()
        .subtract(const Duration(days: 540))
        .toIso8601String()
        .substring(0, 10);
  } else {
    params['$filterDateField.lte'] = '2014-12-31';
  }
  // TMDB's with_original_language does NOT accept a comma separated list
  // (it answers 200 with zero results). Ask per language instead.
  // India-first corpus: both languages, Hindi included.
  final perLang = (take / 2).ceil();
  for (final lang in const ['en', 'hi']) {
    if (out.length >= take) break;
    var langCount = 0;
    final json = await _tmdbGet(
      '/discover/$kind',
      key,
      extra: {...params, 'with_original_language': lang},
    );
    final results = (json?['results'] as List? ?? []);
    for (final r in results) {
      if (out.length >= take || langCount >= perLang) break;
      if (r is! Map<String, dynamic>) continue;
      final id = r['id'];
      final name = r['title'] ?? r['name'];
      final date = r[resultDateField];
      if (id is! int || name == null || date == null || date.toString().isEmpty) {
        continue;
      }
      final year = int.tryParse(date.toString().substring(0, 4)) ?? 0;
      if (year == 0) continue;
      final imdb = await _imdbId(id, kind, key);
      if (imdb == null) continue;
      langCount++;
      out.add(
        _Title(
          type: kind == 'tv' ? 'series' : 'movie',
          title: name.toString(),
          year: year,
          tmdbId: id,
          imdbId: imdb,
          isNew: isNew,
        ),
      );
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Playable = the server actually hands over bytes.
// ---------------------------------------------------------------------------

Future<(bool, String)> _playable(String url) async {
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return (false, '');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final uri = Uri.parse(url);
    final req = await client.getUrl(uri);
    req.headers.set('User-Agent', _ua);
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 && res.statusCode != 206) return (false, '');
    final ctype = (res.headers.value('content-type') ?? '').toLowerCase();
    var body = '';
    var bytes = 0;
    await for (final chunk in res) {
      body += utf8.decode(chunk, allowMalformed: true);
      bytes += chunk.length;
      if (bytes >= 16384) break;
    }
    if (ctype.contains('mpegurl') || body.trimLeft().startsWith('#EXTM3U')) {
      final segment = body
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .firstOrNull;
      if (segment == null) return (false, '');
      final segUri = uri.resolve(segment);
      final segClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final segReq = await segClient.getUrl(segUri);
        segReq.headers.set('User-Agent', _ua);
        segReq.headers.set('Range', 'bytes=0-4095');
        final segRes = await segReq.close().timeout(const Duration(seconds: 15));
        if (segRes.statusCode != 200 && segRes.statusCode != 206) {
          return (false, '');
        }
        var got = 0;
        await for (final chunk in segRes) {
          got += chunk.length;
          if (got >= 512) break;
        }
        final name = segUri.pathSegments.isEmpty ? '' : segUri.pathSegments.last;
        return (got > 0, name);
      } finally {
        segClient.close();
      }
    }
    final path = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return (bytes > 0, path);
  } catch (_) {
    return (false, '');
  } finally {
    client.close();
  }
}

/// Does the embed page itself answer? (403/404 means the embed is gone.)
Future<(int, String)> _embedAlive(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua);
    req.headers.set('Accept', 'text/html,application/xhtml+xml,*/*');
    final res = await req.close().timeout(const Duration(seconds: 15));
    var bytes = 0;
    await for (final chunk in res) {
      bytes += chunk.length;
      if (bytes >= 4096) break;
    }
    return (res.statusCode, '$bytes');
  } catch (e) {
    return (-1, e.runtimeType.toString());
  } finally {
    client.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tmdbKey;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await EnvService.initialize();
    tmdbKey = EnvService.get('TMDB_API_KEY');
    if (tmdbKey.isEmpty) {
      // ignore: avoid_print
      print('!! TMDB_API_KEY missing - run with --dart-define-from-file=.env');
    }
  });

  final scrapers = <String, StreamScraper Function()>{
    'a111477': A111477Scraper.new,
    'vadapav': VadapavScraper.new,
    'rivestream': RiveStreamScraper.new,
    'vidapi': VidApiScraper.new,
    'vidzee': VidZeeScraper.new,
    'lmscript': LMScriptScraper.new,
    'vidlink': VidLinkScraper.new,
    'videasy': VideasyScraper.new,
    'vidcore': VidCoreScraper.new,
    'movy': MovyScraper.new,
    'vidfast': VidFastScraper.new,
    'vidup': VidUpScraper.new,
    'kisskh': KissKhScraper.new,
    'meowtv': MeowTvScraper.new,
  };

  test('scraper liveness audit', () async {
    final set = Platform.environment['PROBE_SET'] ?? 'all';

    final corpus = <_Title>[];
    for (final isNew in [true, false]) {
      if (set != 'all' && set != (isNew ? 'new' : 'old')) continue;
      for (final kind in ['movie', 'tv']) {
        final got = await _discover(
          kind: kind,
          key: tmdbKey,
          isNew: isNew,
          take: 5,
        );
        corpus.addAll(got);
      }
    }
    _log('SUMMARY|corpus|new=${corpus.where((t) => t.isNew).length} '
        'old=${corpus.where((t) => !t.isNew).length} '
        'total=${corpus.length}');
    for (final t in corpus) {
      _log('CORPUS|${t.isNew ? "new" : "old"}|${t.type}|${t.imdbId}|'
          'tmdb=${t.tmdbId}|${t.year}|${t.title}');
    }
    // ignore: avoid_print
    print('=== AUDIT CORPUS | ${corpus.length} titles ===');

    final listed = <String, int>{for (final k in scrapers.keys) k: 0};
    final playable = <String, int>{for (final k in scrapers.keys) k: 0};
    final embed = <String, int>{for (final k in scrapers.keys) k: 0};
    final sources = <String, int>{for (final k in scrapers.keys) k: 0};
    final errors = <String, int>{for (final k in scrapers.keys) k: 0};
    final ms = <String, int>{for (final k in scrapers.keys) k: 0};

    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= corpus.length) return;
        final t = corpus[i];
        for (final entry in scrapers.entries) {
          final sw = Stopwatch()..start();
          var outcome = 'OK';
          List<StreamSource> list = const [];
          try {
            list = await entry
                .value()
                .scrapeStream(
                  type: t.type,
                  title: t.title,
                  year: t.year,
                  season: t.type == 'series' ? 1 : null,
                  episode: t.type == 'series' ? 1 : null,
                  imdbId: t.imdbId,
                )
                .toList()
                .timeout(const Duration(seconds: 25));
          } catch (err) {
            outcome = 'EXCEPTION:${err.runtimeType}';
            errors[entry.key] = errors[entry.key]! + 1;
          }
          sw.stop();
          ms[entry.key] = ms[entry.key]! + sw.elapsedMilliseconds;

          final directs = list
              .where((s) => (s.url ?? '').isNotEmpty)
              .toList();
          final embeds = list
              .where(
                (s) =>
                    (s.url ?? '').isEmpty &&
                    (s.externalUrl ?? '').isNotEmpty &&
                    s.behaviorHints?['dizzyEmbed'] == true,
              )
              .toList();
          final torrents = list.where((s) => s.infoHash != null).toList();

          if (list.isNotEmpty) listed[entry.key] = listed[entry.key]! + 1;
          sources[entry.key] = sources[entry.key]! + list.length;
          if (embeds.isNotEmpty) embed[entry.key] = embed[entry.key]! + 1;

          var playNote = '-';
          if (directs.isNotEmpty) {
            final (ok, note) = await _playable(directs.first.url!);
            if (ok) {
              playable[entry.key] = playable[entry.key]! + 1;
              playNote = 'PLAYABLE:$note';
            } else {
              playNote = 'DEADLINK';
            }
          } else if (embeds.isNotEmpty) {
            final (code, bytes) = await _embedAlive(embeds.first.externalUrl!);
            playNote = 'EMBED:$code/$bytes';
          }

          _log(
            'PROBE|${entry.key}|${t.isNew ? "new" : "old"}|${t.type}|'
            '${t.imdbId}|${t.year}|listed=${list.length}|'
            'direct=${directs.length}|embed=${embeds.length}|'
            'torrent=${torrents.length}|ms=${sw.elapsedMilliseconds}|'
            'host=${_host(list.isEmpty ? null : (list.first.url ?? list.first.externalUrl))}|'
            '$playNote|$outcome',
          );
        }
      }
    }

    await Future.wait([worker(), worker(), worker(), worker()])
        .timeout(const Duration(minutes: 40));

    for (final k in scrapers.keys) {
      _log(
        'SUMMARY|scraper|$k|titles_listed=${listed[k]}|total_sources=${sources[k]}|'
        'playable_titles=${playable[k]}|embed_titles=${embed[k]}|'
        'exceptions=${errors[k]}|avg_ms=${ms[k]! ~/ corpus.length}|of=${corpus.length}',
      );
      // ignore: avoid_print
      print('SUMMARY|scraper|$k|titles_listed=${listed[k]}|'
          'total_sources=${sources[k]}|playable_titles=${playable[k]}|'
          'embed_titles=${embed[k]}|exceptions=${errors[k]}|of=${corpus.length}');
    }
  }, timeout: const Timeout(Duration(minutes: 45)));
}
