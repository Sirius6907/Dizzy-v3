import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:dizzy/services/adblock/filter_list_service.dart';

/// Offline-first behaviour is the whole point of this service: a broken
/// network must never leave the ad-block engine empty, and a fresh cache must
/// cost zero requests.
void main() {
  const supplemental = '! measured on vidfast.vc\n'
      '||vinnyvower.cfd^\n'
      '||contain.remanpurflertawneys.cyou^\n'
      'googletagmanager.com\$third-party\n';

  Future<String> loadSupplemental(String key) async {
    expect(key, FilterListService.supplementalAssetPath);
    return supplemental;
  }

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dizzy_adblock_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  http.Client failingClient() =>
      MockClient((request) async => throw const SocketException('offline'));

  void writeCache(String name, String body, {DateTime? modified}) {
    final file = File(p.join(dir.path, name))..writeAsStringSync(body);
    if (modified != null) file.setLastModifiedSync(modified);
  }

  test('merges fresh cached lists with the shipped supplemental list', () async {
    writeCache('easylist.txt', '[Adblock Plus 2.0]\n! comment\n||ads.example^\n');
    writeCache('ublock.txt', '||track.example^\n');

    final rules = await FilterListService.loadRules(
      client: failingClient(),
      cacheDir: dir,
      assetLoader: loadSupplemental,
    );

    expect(rules, contains('||ads.example^'));
    expect(rules, contains('||track.example^'));
    expect(rules, contains('||vinnyvower.cfd^'));
    expect(rules, contains('googletagmanager.com\$third-party'));
    // Comments and list headers are never rules.
    expect(rules.any((r) => r.startsWith('!') || r.startsWith('[')), isFalse);
  });

  test('a failed refresh keeps the stale cache instead of emptying', () async {
    writeCache(
      'easylist.txt',
      '||old-but-valid.example^\n',
      modified: DateTime.now().subtract(const Duration(days: 30)),
    );

    final rules = await FilterListService.loadRules(
      client: failingClient(),
      cacheDir: dir,
      assetLoader: loadSupplemental,
    );

    expect(rules, contains('||old-but-valid.example^'));
    expect(rules, contains('||vinnyvower.cfd^'));
  });

  test('a successful refresh replaces the cache on disk', () async {
    final client = MockClient(
      (request) async => http.Response('||fresh.example^\n', 200),
    );

    final rules = await FilterListService.loadRules(
      client: client,
      cacheDir: dir,
      assetLoader: loadSupplemental,
    );

    expect(rules, contains('||fresh.example^'));
    final written = File(p.join(dir.path, 'easylist.txt'));
    expect(written.existsSync(), isTrue);
    expect(written.readAsStringSync(), contains('||fresh.example^'));
  });

  test('the shipped supplemental asset carries the measured hosts', () {
    final file = File(FilterListService.supplementalAssetPath);
    expect(file.existsSync(), isTrue);
    final body = file.readAsStringSync();
    expect(body, contains('||vinnyvower.cfd^'));
    expect(body, contains('||contain.remanpurflertawneys.cyou^'));
    expect(body, contains('cloudflareinsights.com'));
  });
}
