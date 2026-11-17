import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/app_log.dart';

/// Merges ad-block filter DATA for the embed webview engine.
///
/// Rule sets are data, never code: two open-source lists (EasyList, uBlock
/// filters) plus a shipped supplemental file with the domains measured on the
/// embed sites. The service is offline-first — a cached list that is younger
/// than [defaultRefreshAfter] is used without any network call, and a failed
/// refresh keeps the stale cache instead of leaving the engine empty.
///
/// Everything is injectable ([client], [cacheDir], [assetLoader]) so the merge
/// and refresh policy is unit-tested without touching the network or the app's
/// real support directory.
class FilterListService {
  FilterListService._();

  static const easylistUrl = 'https://easylist.to/easylist/easylist.txt';
  static const ublockUrl =
      'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt';
  static const supplementalAssetPath = 'assets/adblock/dizzy_supplemental.txt';

  static const defaultRefreshAfter = Duration(days: 7);
  static const _fetchTimeout = Duration(seconds: 10);
  static const _cacheDirName = 'adblock';

  /// Every rule the engine should compile, deduped, comments removed.
  ///
  /// Order: EasyList, uBlock, supplemental — so a shipped rule is never lost
  /// to a duplicate in a downloaded list.
  static Future<List<String>> loadRules({
    http.Client? client,
    Directory? cacheDir,
    Future<String> Function(String assetKey)? assetLoader,
    Duration refreshAfter = defaultRefreshAfter,
  }) async {
    Directory? dir = cacheDir;
    try {
      dir ??= await _defaultCacheDir();
    } catch (e) {
      AppLog.d('[Adblock] no cache dir (soft): $e');
    }

    final rules = <String>{};
    if (dir != null) {
      rules.addAll(
        await _cachedOrFetched(
          dir: dir,
          fileName: 'easylist.txt',
          url: easylistUrl,
          client: client,
          refreshAfter: refreshAfter,
        ),
      );
      rules.addAll(
        await _cachedOrFetched(
          dir: dir,
          fileName: 'ublock.txt',
          url: ublockUrl,
          client: client,
          refreshAfter: refreshAfter,
        ),
      );
    }

    try {
      final load = assetLoader ?? rootBundle.loadString;
      rules.addAll(_cleanRules(await load(supplementalAssetPath)));
    } catch (e) {
      // The supplemental list is shipped, so this only happens in a broken
      // build — the downloaded lists still work.
      AppLog.d('[Adblock] supplemental asset unavailable (soft): $e');
    }

    return rules.toList(growable: false);
  }

  /// Fresh cache → read it; stale/absent → fetch, and if the fetch fails keep
  /// whatever stale copy exists.
  static Future<List<String>> _cachedOrFetched({
    required Directory dir,
    required String fileName,
    required String url,
    required http.Client? client,
    required Duration refreshAfter,
  }) async {
    final file = File(p.join(dir.path, fileName));

    final fresh = await _readIfFresh(file, refreshAfter);
    if (fresh != null) return _cleanRules(fresh);

    final http.Client httpClient = client ?? http.Client();
    try {
      final res = await httpClient
          .get(Uri.parse(url))
          .timeout(_fetchTimeout);
      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        try {
          await dir.create(recursive: true);
          await file.writeAsString(res.body, flush: true);
        } catch (e) {
          // A read-only cache dir must not cost the user their ad blocking.
          AppLog.d('[Adblock] cache write failed (soft): $e');
        }
        return _cleanRules(res.body);
      }
      AppLog.d('[Adblock] $fileName refresh HTTP ${res.statusCode}');
    } catch (e) {
      AppLog.d('[Adblock] $fileName refresh failed (soft): $e');
    } finally {
      if (client == null) httpClient.close();
    }

    // Network failed or answered garbage: stale beats empty.
    try {
      if (await file.exists()) return _cleanRules(await file.readAsString());
    } catch (_) {}
    return const [];
  }

  static Future<String?> _readIfFresh(File file, Duration refreshAfter) async {
    try {
      if (!await file.exists()) return null;
      final modified = (await file.stat()).modified;
      if (DateTime.now().difference(modified) > refreshAfter) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Split into usable rules: trim, drop blanks, `!` comments and `[...]`
  /// list headers (EasyList opens with `[Adblock Plus 2.0]`).
  static List<String> _cleanRules(String text) {
    final out = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('!') || line.startsWith('[')) continue;
      out.add(line);
    }
    return out;
  }

  static Future<Directory> _defaultCacheDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, _cacheDirName));
  }
}
