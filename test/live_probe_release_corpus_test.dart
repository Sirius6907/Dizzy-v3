// TEMPORARY bulk live-probe: yield of every promising HTTP scraper across a
// large content corpus (100+ old, 200+ new titles from Cinemeta â€” no API key).
// Usage: flutter test test/live_probe_bulk_test.dart --reporter expanded
// Results append to artifacts/audit/bulk_probe.log (PROBE| and SUMMARY| lines).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/config/env_service.dart';
import 'package:dizzy/services/scraper/sites/a111477.dart';
import 'package:dizzy/services/scraper/sites/lmscript.dart';
import 'package:dizzy/services/scraper/sites/rivestream.dart';
import 'package:dizzy/services/scraper/sites/vadapav.dart';
import 'package:dizzy/services/scraper/sites/videasy.dart';
import 'package:dizzy/services/scraper/sites/vidcore.dart';
import 'package:dizzy/services/scraper/sites/vidlink.dart';
import 'package:dizzy/services/scraper/sites/vidzee.dart';
import 'package:dizzy/services/scraper/sites/vidapi.dart';
import 'package:dizzy/services/scraper/stream_scraper.dart';
import 'package:dizzy/services/stream/dub_filter.dart';

class _Title {
  final String type;
  final String name;
  final int year;
  final String imdbId;
  final bool isNew;
  final bool isAnime;
  const _Title(this.type, this.name, this.year, this.imdbId, this.isNew,
      [this.isAnime = false]);
}

// ---------------------------------------------------------------------------
// TMDB side of the corpus (the owner's "TMDB + IMDb" requirement).
//
// The corpus is built from BOTH sides:
//   * TMDB /discover  - release-date ordered, Bollywood + Hollywood + anime
//   * Cinemeta        - the IMDb side (it is indexed by IMDb id)
// Every TMDB title gets its IMDb id from /movie|{id}/external_ids, so the
// probe measures the same id space the app uses at runtime.
// ---------------------------------------------------------------------------

const _tmdbEdge = 'tmdb-proxy';

// Kept for the case where the tmdb-proxy allowlist opens /discover and
// /external_ids (then the corpus can carry the IMDb id of every TMDB
// title, not only the Cinemeta side).
// ignore: unused_element
Future<Map<String, dynamic>?> _tmdbProxy(
  String path, [
  Map<String, String> query = const {},
]) async {
  final base = CloudClient.functionUrl(_tmdbEdge);
  if (base.isEmpty) return null;
  final uri = Uri.parse(base).replace(queryParameters: {
    'path': path,
    ...query,
  });
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final req = await client.getUrl(uri);
    req.headers.set('apikey', CloudClient.anonKey);
    req.headers.set('Authorization', 'Bearer ${CloudClient.anonKey}');
    req.headers.set('Accept', 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<List<_Title>> _tmdbCorpus({
  required String kind,
  required List<String> langs,
  required int take,
  required bool anime,
}) async {
  final out = <_Title>[];
  // The catalogue edge function is the app's own TMDB gateway (the
  // direct TMDB host is not reachable from a build machine, and the
  // tmdb-proxy allowlist does not open /discover). Its `latest` feed is
  // release-date ordered, which is exactly the corpus order wanted.
  final base = CloudClient.functionUrl('catalog');
  if (base.isEmpty) return out;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  for (final lang in langs) {
    if (out.length >= take) break;
    final uri = Uri.parse(base).replace(queryParameters: {
      'feed': 'latest',
      'type': kind,
      'language': lang,
      'region': 'IN',
      'page': '1',
    });
    try {
      final req = await client.getUrl(uri);
      req.headers.set('apikey', CloudClient.anonKey);
      req.headers.set('Authorization', 'Bearer ${CloudClient.anonKey}');
      req.headers.set('Accept', 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      for (final it in (json['items'] as List? ?? [])) {
        if (out.length >= take) break;
        if (it is! Map<String, dynamic>) continue;
        final title = '${it['title'] ?? ''}';
        final id = '${it['id'] ?? ''}';
        final year = int.tryParse('${it['year'] ?? ''}') ?? 0;
        if (title.isEmpty || id.isEmpty || year == 0) continue;
        out.add(_Title(
          kind == 'tv' ? 'series' : 'movie',
          title,
          year,
          '',
          true,
          anime,
        ));
      }
    } catch (_) {
      // A failed bucket must not kill the corpus.
    }
  }
  client.close();
  return out;
}

const _cinemeta = 'https://v3-cinemeta.strem.io';

String _host(String? u) {
  if (u == null || u.isEmpty) return '-';
  final p = Uri.tryParse(u);
  return (p == null || p.host.isEmpty) ? (u.isEmpty ? '-' : u) : p.host;
}

/// Lowercase, letters and digits only, spaces kept.
String _norm(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();

/// Does the release file name look like the title we asked for?
bool _looksLike(String fileName, String title) {
  final h = _norm(fileName);
  final n = _norm(title);
  if (h.isEmpty || n.isEmpty) return false;
  if (h.contains(n)) return true;
  final words = n.split(RegExp(r'\s+'))
      .where((w) => w.length >= 4 && !_noiseWords.contains(w))
      .toList();
  if (words.isEmpty) return false;
  final hits = words.where(h.contains).length;
  return hits >= (words.length == 1 ? 1 : words.length - 1);
}

const _noiseWords = {
  'the',
  'and',
  'with',
  'part',
  'full',
  'hd',
  'bluray',
  'webrip',
  'dual',
  'hindi',
  'english',
  'tamil',
  'telugu',
  'malayalam',
  'kannada',
  'odia',
  'dubbed',
  'subbed',
};

final _logFile = File('artifacts/audit/bulk_probe.log');

/// Playable = the server actually hands over bytes.
///
/// A source that is LISTED is not a source that PLAYS: the owner's report
/// was "posters and catalogues are there, but there are almost no
/// sources", and the only way to tell the two apart is to pull bytes.
///
/// Most of these streams are HLS playlists (m3u8), not progressive
/// files, so a playable probe fetches the playlist and then the FIRST
/// SEGMENT. The segment file name usually carries the release title,
/// which is what makes the right-content check possible.
Future<(bool, String)> _playable(String url) async {
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return (false, '');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final uri = Uri.parse(url);
    final req = await client.getUrl(uri);
    req.headers.set('User-Agent', 'Mozilla/5.0');
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
    // NOTE: no drain() after the break - it throws on a cancelled
    // subscription and would turn every playable source into a failure.
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
        segReq.headers.set('User-Agent', 'Mozilla/5.0');
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

void _log(String line) {
  _logFile.parent.createSync(recursive: true);
  _logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

Future<List<Map<String, dynamic>>> _catalog(String type, String extra) async {
  final uri = Uri.parse('$_cinemeta/catalog/$type/$extra');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['metas'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
  } finally {
    client.close();
  }
}

int _yearOf(Map<String, dynamic> meta) {
  final y = meta['year'];
  if (y is int) return y;
  final release = (meta['releaseInfo'] ?? '').toString();
  final m = RegExp(r'\d{4}').firstMatch(release);
  return m == null ? 0 : int.parse(m.group(0)!);
}

Future<List<_Title>> _buildCorpus() async {
  final titles = <_Title>[];

  // --- TMDB side: release-date ordered, Bollywood + Hollywood ------------
  titles.addAll(await _tmdbCorpus(
    kind: 'movie',
    langs: const ['hi', 'te', 'ml', 'kn', 'en'],
    take: 100,
    anime: false,
  ));
  titles.addAll(await _tmdbCorpus(
    kind: 'tv',
    langs: const ['hi', 'te', 'ml', 'kn'],
    take: 100,
    anime: false,
  ));

  // --- IMDb side: the Cinemeta catalogue, which is indexed by IMDb id ---
  for (final type in ['movie', 'series']) {
    var count = 0;
    for (final skip in [0, 100]) {
      if (count >= 50) break;
      final metas = await _catalog(type, '$type/latest.json?skip=$skip');
      for (final m in metas) {
        if (count >= 50) break;
        final id = (m['imdb_id'] ?? '') as String;
        final name = (m['name'] ?? '') as String;
        final year = _yearOf(m);
        if (id.isEmpty || name.isEmpty || year < 2024) continue;
        titles.add(_Title(type, name, year, id, true));
        count++;
      }
    }
  }

  // --- Anime: 60 titles; the probe picks the episode numbers -------------
  titles.addAll(await _tmdbCorpus(
    kind: 'tv',
    langs: const ['ja'],
    take: 60,
    anime: true,
  ));

  return titles;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await EnvService.initialize();
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
    // 'movy' is deliberately OUT: it is the torrent/seed based one
    // ("could not acquire seed"), and the owner asked for the probe to run
    // with P2P off so the probe itself never pulls a single piece of
    // torrent traffic over the ISP connection.
  };

  test('bulk corpus probe', () async {
    final corpus = await _buildCorpus();
    _log('SUMMARY|corpus|new=${corpus.where((t) => t.isNew).length} '
        'old=${corpus.where((t) => !t.isNew).length} '
        'total=${corpus.length}');
    print('=== BULK PROBE | ${corpus.length} titles '
        '(${corpus.where((t) => t.isNew).length} new) ===');

    final counts = <String, int>{for (final k in scrapers.keys) k: 0};
    final valids = <String, int>{for (final k in scrapers.keys) k: 0};
    final playTitles = <String, int>{for (final k in scrapers.keys) k: 0};
    final playSources = <String, int>{for (final k in scrapers.keys) k: 0};
    final rightTitles = <String, int>{for (final k in scrapers.keys) k: 0};
    // Anime audio buckets (the owner's rule).
    var animeSub = 0;
    var animeDub = 0;
    var animeHindi = 0;
    // Per-title roll-up: a title counts once, no matter how many scrapers
    // answered for it.
    final sourceTitles = <String>{};
    final playableTitleKeys = <String>{};

    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= corpus.length) return;
        final t = corpus[i];
        await Future.wait(scrapers.entries.map((e) async {
          final sw = Stopwatch()..start();
          String outcome = 'OK';
          List<StreamSource> list = const [];
          try {
            list = await e
                .value()
                .scrapeStream(
                  type: t.type,
                  title: t.name,
                  year: t.year,
                  season: t.type == 'series' ? 1 + (i % 3) : null,
                  episode: t.type == 'series' ? 1 + (i % 12) : null,
                  imdbId: t.imdbId,
                )
                .toList()
                .timeout(const Duration(seconds: 25));
          } catch (err) {
            outcome = 'EXCEPTION:${err.runtimeType}';
          }
          sw.stop();
          // HTTP only: a magnet/infoHash source is P2P, and this probe
          // runs with P2P off on purpose.
          final http = list
              .where((s) =>
                  (s.url ?? '').startsWith('http://') ||
                  (s.url ?? '').startsWith('https://'))
              .toList();
          final valid = http.length;
          // Playable: pull bytes from the first listed source. One probe
          // per title keeps the traffic polite - a title is playable if
          // ONE of its sources really delivers.
          var playable = 0;
          var contentHint = '';
          for (final s in http.take(1)) {
            final (ok, hint) = await _playable(s.url!);
            if (ok) {
              playable++;
              contentHint = hint;
            }
          }
          // Right content: the segment/file name usually carries the
          // release title, so it can be compared with what was asked for.
          var rightContent = false;
          if (playable > 0 && contentHint.isNotEmpty) {
            rightContent = _looksLike(contentHint, t.name);
          }
          if (valid > 0) {
            counts[e.key] = counts[e.key]! + 1;
            valids[e.key] = valids[e.key]! + valid;
          }
          if (playable > 0) {
            playTitles[e.key] = playTitles[e.key]! + 1;
            playSources[e.key] = playSources[e.key]! + playable;
          }
          if (rightContent) {
            rightTitles[e.key] = rightTitles[e.key]! + 1;
          }
          if (t.isAnime) {
            // The owner's anime rule: original audio + English subs, or
            // the English dub. A Hindi dub is counted separately so the
            // report can say how much of the catalogue is Hindi dubs.
            for (final s in http) {
              switch (animeAudioBucket(s, mediaTitle: t.name)) {
                case AnimeAudioBucket.originalWithEnglishSubs:
                  animeSub++;
                case AnimeAudioBucket.englishDub:
                  animeDub++;
                case AnimeAudioBucket.hindiDub:
                  animeHindi++;
                case AnimeAudioBucket.other:
                  break;
              }
            }
          }
          final titleKey = t.imdbId.isEmpty ? t.name : t.imdbId;
          if (valid > 0) sourceTitles.add(titleKey);
          if (playable > 0) playableTitleKeys.add(titleKey);
          _log(
            'PROBE|${e.key}|${t.isNew ? "new" : "old"}|${t.type}|'
            '${t.imdbId}|${t.year}|http=$valid|playable=$playable|'
            'right=$rightContent|ms=${sw.elapsedMilliseconds}|'
            'host=${_host(list.isEmpty ? null : list.first.url)}|$outcome',
          );
        }));
      }
    }

    await Future.wait([
      worker(),
      worker(),
      worker(),
    ]).timeout(const Duration(minutes: 55));

    for (final k in scrapers.keys) {
      _log('SUMMARY|scraper|$k|titles_with_sources=${counts[k]}|'
          'total_sources=${valids[k]}|playable_titles=${playTitles[k]}|'
          'playable_sources=${playSources[k]}|right_content=${rightTitles[k]}|'
          'of=${corpus.length}');
      print('SUMMARY|scraper|$k|titles_with_sources=${counts[k]}|'
          'total_sources=${valids[k]}|playable_titles=${playTitles[k]}|'
          'playable_sources=${playSources[k]}|right_content=${rightTitles[k]}|'
          'of=${corpus.length}');
    }
    // The four numbers the owner asked for, per scraper and overall.
    var anySource = 0;
    var anyPlayable = 0;
    for (final t in corpus) {
      final key = t.imdbId.isEmpty ? t.name : t.imdbId;
      if (sourceTitles.contains(key)) anySource++;
      if (playableTitleKeys.contains(key)) anyPlayable++;
    }
    _log('SUMMARY|catalogue|titles=${corpus.length}|'
        'with_sources=$anySource|playable=$anyPlayable|'
        'tmdb=${corpus.where((t) => t.imdbId.isNotEmpty).length}');
    print('SUMMARY|catalogue|titles=${corpus.length}|'
        'with_sources=$anySource|playable=$anyPlayable|'
        'tmdb=${corpus.where((t) => t.imdbId.isNotEmpty).length}');
    _log('SUMMARY|anime|sources_sub=$animeSub|dub_english=$animeDub|'
        'dub_hindi=$animeHindi|'
        'anime_titles=${corpus.where((t) => t.isAnime).length}');
    print('SUMMARY|anime|sources_sub=$animeSub|dub_english=$animeDub|'
        'dub_hindi=$animeHindi|'
        'anime_titles=${corpus.where((t) => t.isAnime).length}');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
