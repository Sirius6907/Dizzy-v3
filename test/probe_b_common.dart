// Throwaway live-probe harness (agent B). Deleted when the audit is done.
import 'dart:async';
import 'dart:io';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/config/env_service.dart';
import 'package:dizzy/services/scraper/sites/tmdb_helper.dart';
import 'package:dizzy/services/scraper/stream_scraper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProbeTarget {
  const ProbeTarget(this.label, this.title, this.year, this.imdbId);
  final String label;
  final String title;
  final int year;
  final String imdbId;
}

const targets = <ProbeTarget>[
  ProbeTarget('new', 'Project Hail Mary', 2026, 'tt12042730'),
  ProbeTarget('old', 'Hocus Pocus', 1993, 'tt0107120'),
];

final String logDir = () {
  final sep = Platform.pathSeparator;
  return 'artifacts${sep}audit-v2${sep}scrapers${sep}groupB';
}();

Future<void> initProbeEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs a fake HttpClient that answers 400 to every request
  // (so unit tests never touch the network). A live probe needs the real one.
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  await EnvService.initialize();
  // Production path uses the cloud edge (tmdb-proxy + resolve). Init is
  // fail-soft; if it stays false the keyless proxy path is exercised instead.
  try {
    final ok = await CloudClient.init().timeout(const Duration(seconds: 20));
    // ignore: avoid_print
    print('PROBE-ENV cloud.ready=$ok configured=${CloudClient.isConfigured}');
  } catch (e) {
    // ignore: avoid_print
    print('PROBE-ENV cloud.init threw: $e');
  }
}

String hostOf(String? url) {
  if (url == null || url.isEmpty) return '-';
  try {
    return Uri.parse(url).host;
  } catch (_) {
    return '?';
  }
}

/// One probe: runs the real scrape() path, appends a log block, prints a
/// single machine-greppable line.
Future<void> probeOne(
  StreamScraper scraper,
  ProbeTarget t, {
  String type = 'movie',
}) async {
  final sw = Stopwatch()..start();
  var count = 0;
  String? firstUrl;
  String? firstQuality;
  String? failure = '';
  var hosts = <String>{};

  try {
    final list = await scraper
        .scrape(
          type: type,
          title: t.title,
          year: t.year,
          imdbId: t.imdbId,
        )
        .timeout(const Duration(seconds: 45));
    count = list.length;
    if (list.isNotEmpty) {
      final first = list.first;
      firstUrl = first.url ?? first.infoHash;
      firstQuality = first.quality ?? '-';
      for (final s in list) {
        hosts.add(hostOf(s.url ?? s.infoHash));
      }
    } else {
      failure = 'empty';
    }
    _append(scraper, t, sw.elapsedMilliseconds, count, firstUrl, failure,
        list: list);
  } catch (e) {
    failure = e is TimeoutException ? 'timeout>45s' : 'exception: $e';
    _append(scraper, t, sw.elapsedMilliseconds, 0, null, failure);
  }

  // ignore: avoid_print
  print(
    'PROBE|${scraper.runtimeType}|${scraper.name}|${t.label}|'
    '${sw.elapsedMilliseconds}ms|$count|${hostOf(firstUrl)}|'
    '${firstQuality ?? '-'}|${hosts.take(4).join(",")}|$failure',
  );
}

void _append(
  StreamScraper scraper,
  ProbeTarget t,
  int ms,
  int count,
  String? firstUrl,
  String failure, {
  List<StreamSource> list = const [],
}) {
  final f = File('$logDir${Platform.pathSeparator}${scraper.name}.log');
  f.parent.createSync(recursive: true);
  final b = StringBuffer()
    ..writeln('===== ${scraper.runtimeType} / ${t.label} =====')
    ..writeln('title=${t.title} year=${t.year} imdbId=${t.imdbId} type=movie')
    ..writeln('latencyMs=$ms sources=$count failure=${failure.isEmpty ? 'none' : failure}');
  for (final s in list.take(8)) {
    b.writeln(
      '  src name=${s.name} title=${s.title} url=${s.url ?? ''} '
      'host=${hostOf(s.url)} infoHash=${s.infoHash ?? ''} q=${s.quality ?? ''}',
    );
  }
  if (list.isEmpty) b.writeln('  (no sources)');
  b.writeln();
  f.writeAsStringSync(b.toString(), mode: FileMode.append, flush: true);
}

void clearLogs(List<StreamScraper> scrapers) {
  Directory(logDir).createSync(recursive: true);
  for (final s in scrapers) {
    final f = File('$logDir${Platform.pathSeparator}${s.name}.log');
    if (f.existsSync()) f.deleteSync();
  }
}

/// Probes the shared TMDB resolver once so a resolution outage is never
/// mistaken for 20 dead scrapers.
Future<void> probeTmdb() async {
  for (final t in targets) {
    final sw = Stopwatch()..start();
    final id = await TmdbHelper.resolveTmdbId(
      imdbId: t.imdbId,
      title: t.title,
      type: 'movie',
      year: t.year,
    );
    // ignore: avoid_print
    print('PROBE-TMDB|${t.label}|${t.imdbId}|${sw.elapsedMilliseconds}ms|$id');
  }
}
