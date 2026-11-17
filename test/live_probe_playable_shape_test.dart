// Why did every playable probe come back 0?
//
// Takes a real stream URL from the app's own scraper and tries the byte
// pull in several shapes, so the probe's request can be fixed to match
// what the player really needs (referer? range? redirect?).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/config/env_service.dart';
import 'package:dizzy/services/scraper/sites/lmscript.dart';

Future<void> _pull(
  String label,
  String url,
  Map<String, String> headers, {
  bool head = false,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final uri = Uri.parse(url);
    final req = head ? await client.headUrl(uri) : await client.getUrl(uri);
    for (final e in headers.entries) {
      req.headers.set(e.key, e.value);
    }
    final res = await req.close().timeout(const Duration(seconds: 15));
    var got = 0;
    await for (final chunk in res) {
      got += chunk.length;
      if (got >= 2048) break;
    }
    print('$label -> status=${res.statusCode} '
        'type=${res.headers.value('content-type')} bytes=$got');
  } catch (e) {
    print('$label -> ERR ${e.runtimeType}: $e');
  } finally {
    client.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await EnvService.initialize();
  });

  test('playable probe shapes', () async {
    final list = await LMScriptScraper()
        .scrapeStream(
          type: 'movie',
          title: 'Project Hail Mary',
          year: 2026,
          imdbId: 'tt12042730',
        )
        .toList()
        .timeout(const Duration(seconds: 30));
    print('sources: ${list.length}');
    final http = list
        .where((s) =>
            (s.url ?? '').startsWith('http://') ||
            (s.url ?? '').startsWith('https://'))
        .toList();
    print('http sources: ${http.length}');
    if (http.isEmpty) return;
    final url = http.first.url!;
    print('url host: ${Uri.parse(url).host}');

    await _pull('plain GET', url, {'User-Agent': 'Mozilla/5.0'});
    await _pull('range', url, {
      'User-Agent': 'Mozilla/5.0',
      'Range': 'bytes=0-2047',
    });
    await _pull('range+referer', url, {
      'User-Agent': 'Mozilla/5.0',
      'Range': 'bytes=0-2047',
      'Referer': 'https://lmscript.com/',
    });
    await _pull('head', url, {'User-Agent': 'Mozilla/5.0'}, head: true);
    await _pull('no headers', url, {});
  });
}
