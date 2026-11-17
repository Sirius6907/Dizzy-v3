// TEMPORARY live-probe harness for Group A HTTP scrapers.
// Exercises the real scraper code paths against live upstreams.
// Usage: flutter test test/live_probe_agentA_test.dart --reporter expanded
//        PROBE_SET=new|old|series  (env var selects the query)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/config/env_service.dart';
import 'package:dizzy/services/scraper/stream_scraper.dart';
import 'package:dizzy/services/scraper/sites/a111477.dart';
import 'package:dizzy/services/scraper/sites/cinejoy.dart';
import 'package:dizzy/services/scraper/sites/dulo.dart';
import 'package:dizzy/services/scraper/sites/flystream.dart';
import 'package:dizzy/services/scraper/sites/fourkhdhub.dart';
import 'package:dizzy/services/scraper/sites/frame.dart';
import 'package:dizzy/services/scraper/sites/fsharetv.dart';
import 'package:dizzy/services/scraper/sites/fsonic.dart';
import 'package:dizzy/services/scraper/sites/hindmoviez.dart';
import 'package:dizzy/services/scraper/sites/kisskh.dart';
import 'package:dizzy/services/scraper/sites/lmscript.dart';
import 'package:dizzy/services/scraper/sites/mapple.dart';
import 'package:dizzy/services/scraper/sites/megasource.dart';
import 'package:dizzy/services/scraper/sites/meowtv.dart';
import 'package:dizzy/services/scraper/sites/movienight.dart';
import 'package:dizzy/services/scraper/sites/nova.dart';
import 'package:dizzy/services/scraper/sites/purstream.dart';
import 'package:dizzy/services/scraper/sites/rivestream.dart';
import 'package:dizzy/services/scraper/sites/vadapav.dart';
import 'package:dizzy/services/scraper/sites/vidapi.dart';
import 'package:dizzy/services/scraper/sites/vidlink.dart';
import 'package:dizzy/services/scraper/sites/vidzee.dart';
import 'package:dizzy/services/scraper/sites/xdownloader.dart';
import 'package:dizzy/services/scraper/sites/xpass.dart';

class _Query {
  final String type;
  final String title;
  final int year;
  final int? season;
  final int? episode;
  final String imdbId;
  const _Query(this.type, this.title, this.year, this.imdbId,
      {this.season, this.episode});
}

const _queries = {
  'new': _Query('movie', 'Project Hail Mary', 2026, 'tt12042730'),
  'old': _Query('movie', 'Hocus Pocus', 1993, 'tt0107120'),
  'series': _Query('series', 'Cops', 1989, 'tt0096563', season: 1, episode: 1),
};

String _host(String? u) {
  if (u == null || u.isEmpty) return '-';
  final p = Uri.tryParse(u);
  if (p == null) return u;
  return p.host.isEmpty ? u : p.host;
}

void _log(String path, String line) {
  try {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter_test installs an HttpOverrides that returns HTTP 400 for every
    // real request. Clear it so the probe exercises live upstreams.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await EnvService.initialize();
  });

  final setName = Platform.environment['PROBE_SET'] ?? 'new';
  final q = _queries[setName] ?? _queries['new']!;
  final outDir =
      'artifacts/audit-v2/scrapers/groupA/${setName == 'new' ? 'new' : setName}';
  final started = DateTime.now();

  final scrapers = <String, StreamScraper>{
    // control (not in scope) — proves the harness itself works
    'a111477': A111477Scraper(),
    'vadapav': VadapavScraper(),
    'hindmoviez': HindMoviezScraper(),
    'fourkhdhub': FourKHDHubScraper(),
    'xdownloader': XDownloaderScraper(),
    'cinejoy': CinejoyScraper(),
    'dulo': DuloScraper(),
    'flystream': FlyStreamScraper(),
    'movienight': MovieNightScraper(),
    'rivestream': RiveStreamScraper(),
    'mapple': MappleScraper(),
    'nova': NovaScraper(),
    'megasource': MegaSourceScraper(),
    'purstream': PurstreamScraper(),
    'vidapi': VidApiScraper(),
    'vidzee': VidZeeScraper(),
    'frame': FrameScraper(),
    'fsharetv': FshareTvScraper(),
    'fsonic': FSonicScraper(),
    'kisskh': KissKhScraper(),
    'lmscript': LMScriptScraper(),
    'meowtv': MeowTvScraper(),
    'vidlink': VidLinkScraper(),
    'xpass': XPassScraper(),
  };

  test('probe group A [$setName]', () async {
    print('=== PROBE SET $setName | ${q.type} "${q.title}" ${q.year} '
        '${q.imdbId} S${q.season}E${q.episode} | start $started ===');
    for (final entry in scrapers.entries) {
      final id = entry.key;
      final sw = Stopwatch()..start();
      String outcome = 'OK';
      List<StreamSource> list = const [];
      try {
        list = await entry.value
            .scrapeStream(
              type: q.type,
              title: q.title,
              year: q.year,
              season: q.season,
              episode: q.episode,
              imdbId: q.imdbId,
            )
            .toList()
            .timeout(const Duration(seconds: 45));
      } catch (e) {
        outcome = 'EXCEPTION:${e.runtimeType}:$e';
      }
      sw.stop();
      final valid = list
          .where((s) =>
              (s.url != null && s.url!.startsWith('http')) ||
              (s.infoHash != null && s.infoHash!.isNotEmpty))
          .toList();
      final first = valid.isNotEmpty ? valid.first : (list.isNotEmpty ? list.first : null);
      final line = 'PROBE|$id|$setName|count=${list.length}|valid=${valid.length}'
          '|ms=${sw.elapsedMilliseconds}'
          '|host=${_host(first?.url)}'
          '|quality=${first?.quality ?? '-'}'
          '|first=${first?.url ?? first?.infoHash ?? '-'}'
          '|outcome=$outcome';
      print(line);
      _log('$outDir/$id.log', line);
      if (list.isNotEmpty) {
        for (final s in list.take(5)) {
          _log('$outDir/$id.log',
              '    sample addon=${s.addonName} q=${s.quality} url=${s.url ?? s.infoHash}');
        }
      }
    }
    print('=== PROBE SET $setName DONE in '
        '${DateTime.now().difference(started).inSeconds}s ===');
  }, timeout: const Timeout(Duration(minutes: 25)));
}
