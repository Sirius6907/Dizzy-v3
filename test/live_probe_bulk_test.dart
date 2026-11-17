// TEMPORARY bulk live-probe: yield of every promising HTTP scraper across a
// large content corpus (100+ old, 200+ new titles from Cinemeta — no API key).
// Usage: flutter test test/live_probe_bulk_test.dart --reporter expanded
// Results append to artifacts/audit/bulk_probe.log (PROBE| and SUMMARY| lines).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/config/env_service.dart';
import 'package:dizzy/services/scraper/sites/a111477.dart';
import 'package:dizzy/services/scraper/sites/lmscript.dart';
import 'package:dizzy/services/scraper/sites/movy.dart';
import 'package:dizzy/services/scraper/sites/rivestream.dart';
import 'package:dizzy/services/scraper/sites/vadapav.dart';
import 'package:dizzy/services/scraper/sites/videasy.dart';
import 'package:dizzy/services/scraper/sites/vidcore.dart';
import 'package:dizzy/services/scraper/sites/vidlink.dart';
import 'package:dizzy/services/scraper/sites/vidzee.dart';
import 'package:dizzy/services/scraper/sites/vidapi.dart';
import 'package:dizzy/services/scraper/stream_scraper.dart';

class _Title {
  final String type;
  final String name;
  final int year;
  final String imdbId;
  final bool isNew;
  const _Title(this.type, this.name, this.year, this.imdbId, this.isNew);
}

const _cinemeta = 'https://v3-cinemeta.strem.io';

String _host(String? u) {
  if (u == null || u.isEmpty) return '-';
  final p = Uri.tryParse(u);
  return (p == null || p.host.isEmpty) ? (u.isEmpty ? '-' : u) : p.host;
}

final _logFile = File('artifacts/audit/bulk_probe.log');

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
  // NEW: latest movies + latest series (200 target).
  for (final type in ['movie', 'series']) {
    var count = 0;
    for (final skip in [0, 100]) {
      if (count >= 100) break;
      final metas = await _catalog(type, '$type/latest.json?skip=$skip');
      for (final m in metas) {
        if (count >= 100) break;
        final id = (m['imdb_id'] ?? '') as String;
        final name = (m['name'] ?? '') as String;
        final year = _yearOf(m);
        if (id.isEmpty || name.isEmpty || year < 2025) continue;
        titles.add(_Title(type, name, year, id, true));
        count++;
      }
    }
  }
  // OLD: popular classics (100 target) — top catalogs filtered to ≤2014.
  for (final type in ['movie', 'series']) {
    var count = 0;
    for (final skip in [0, 100]) {
      if (count >= 50) break;
      final metas = await _catalog(type, '$type/top.json?skip=$skip');
      for (final m in metas) {
        if (count >= 50) break;
        final id = (m['imdb_id'] ?? '') as String;
        final name = (m['name'] ?? '') as String;
        final year = _yearOf(m);
        if (id.isEmpty || name.isEmpty || year == 0 || year > 2014) continue;
        titles.add(_Title(type, name, year, id, false));
        count++;
      }
    }
  }
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
    'movy': MovyScraper.new,
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
                  season: t.type == 'series' ? 1 : null,
                  episode: t.type == 'series' ? 1 : null,
                  imdbId: t.imdbId,
                )
                .toList()
                .timeout(const Duration(seconds: 25));
          } catch (err) {
            outcome = 'EXCEPTION:${err.runtimeType}';
          }
          sw.stop();
          final valid = list
              .where((s) => (s.url ?? '').isNotEmpty || s.infoHash != null)
              .length;
          if (valid > 0) {
            counts[e.key] = counts[e.key]! + 1;
            valids[e.key] = valids[e.key]! + valid;
          }
          _log(
            'PROBE|${e.key}|${t.isNew ? "new" : "old"}|${t.type}|'
            '${t.imdbId}|${t.year}|valid=$valid|ms=${sw.elapsedMilliseconds}|'
            'host=${_host(list.isEmpty ? null : list.first.url)}|$outcome',
          );
        }));
      }
    }

    await Future.wait([
      worker(),
      worker(),
      worker(),
      worker(),
      worker(),
    ]).timeout(const Duration(minutes: 55));

    for (final k in scrapers.keys) {
      _log('SUMMARY|scraper|$k|titles_with_sources=${counts[k]}|'
          'total_sources=${valids[k]}|of=${corpus.length}');
      print('SUMMARY|scraper|$k|titles_with_sources=${counts[k]}|'
          'total_sources=${valids[k]}|of=${corpus.length}');
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
