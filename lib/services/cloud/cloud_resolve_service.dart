import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_client.dart';
import '../net/dizzy_net.dart';

/// P21 — Cloud resolve API client (`resolve` edge function).
///
/// The server holds the TMDB key; the app never sees it. Given a title
/// (+optional year/type/imdbId) the edge returns `{tmdbId, imdbId, year,
/// title}` with year-pinned matching — smarter than raw proxy passthrough,
/// so scrapers call this FIRST when cloud is ready.
///
/// Cost per fresh title: **2 reads, 1 write** —
///   read 1: local prefs cache (`resolve:<type>:<key>`, 30-day TTL),
///   read 2: the edge fetch itself,
///   write:   caching the answer back to prefs.
/// Everything fail-soft: null = "fall through to the next chain rung".
/// No addon changes — scrapers consume plain IDs.
class CloudResolveService {
  const CloudResolveService._();

  static const _ttlDays = 30;

  /// Bump on gate changes so poisoned entries (resolved by older, looser
  /// logic) auto-expire instead of serving wrong videos for 30 days.
  /// v2 = 2026-10-10 exact-title lock (server + client).
  /// v3 = 2026-11-14 corpus-aware resolve (server-side title corpus, year
  /// pinning, and the Authorization header the edge function requires).
  static const _gateVersion = 'v3';

  /// Pure: cleaned-title comparison for the exact-title lock.
  /// Same normalization as the `resolve` edge fn + TmdbHelper._cleanString.
  /// Unit-tested: a mismatched echo must never resolve.
  static bool titlesMatch(String requested, String echoed) {
    String clean(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return clean(requested) == clean(echoed);
  }

  static String _cacheKey(
      {required String type, String? imdbId, required String title, String? year}) {
    final raw = '${imdbId ?? ''}|$title|${year ?? ''}'.toLowerCase().trim();
    return 'resolve:$_gateVersion:$type:${raw.hashCode}';
  }

  /// The headers the `resolve` edge function needs.
  ///
  /// 2026-11-14: the function is deployed with JWT verification ON, so a
  /// request that carries only `apikey` comes back
  /// `401 UNAUTHORIZED_NO_AUTH_HEADER` — measured live, every call. The
  /// app then silently fell through to the weaker local chain, which is
  /// exactly why regional titles resolved to nothing (or to the wrong
  /// film). The anon key IS a valid JWT (role=anon), so sending it as a
  /// bearer token is enough.
  @visibleForTesting
  static Map<String, String> buildHeaders() => {
        'apikey': CloudClient.anonKey,
        'Authorization': 'Bearer ${CloudClient.anonKey}',
        'Accept': 'application/json',
      };

  /// Does the edge answer count as "this is the film you asked for"?
  ///
  /// The old rule was "the echoed title must equal the requested title",
  /// which existed because a wrong id plays the wrong video (poster A,
  /// playback B) across ~40 scrapers. That rule is still right for a
  /// plain exact match, but the resolver now also answers from the title
  /// CORPUS, where the canonical title can differ from the request
  /// ("Dahaan" for "Dahaan: The Evil Within") or sit one edit away
  /// ("Minal" / "Minall").
  ///
  /// Those two cases are accepted only when the SERVER says it matched
  /// that way (`source` + `matchQuality`), because the server applies the
  /// year and language guards the client cannot see. Anything else stays
  /// rejected.
  static bool acceptsEcho({
    required String requested,
    required String echoed,
    Map<String, dynamic>? payload,
  }) {
    if (titlesMatch(requested, echoed)) return true;
    final source = (payload?['source'] ?? '').toString();
    final quality = (payload?['matchQuality'] ?? '').toString();
    if (source == 'corpus') {
      return quality == 'exact' || quality == 'alias' || quality == 'fuzzy';
    }
    if (source == 'tmdb') return quality == 'fuzzy';
    return false;
  }

  /// title/year/type/imdbId → `{tmdbId, imdbId, year, title}` or null.
  static Future<Map<String, dynamic>?> resolveIds({
    required String title,
    String? year,
    String type = 'movie',
    String? imdbId,
    String? lang,
  }) async {
    final t = title.trim();
    final imdb = (imdbId ?? '').trim();
    if (t.isEmpty && imdb.isEmpty) return null;
    if (!CloudClient.isConfigured) return null;

    final key = _cacheKey(type: type, imdbId: imdb, title: t, year: year);
    try {
      // Read 1: local cache.
      final prefs = await SharedPreferences.getInstance();
      final hit = prefs.getString(key);
      if (hit != null) {
        final decoded = jsonDecode(hit) as Map<String, dynamic>?;
        final at = (decoded?['_at'] as int?) ?? 0;
        final ageDays =
            (DateTime.now().millisecondsSinceEpoch - at) ~/ 86400000;
        if (ageDays <= _ttlDays) return decoded;
      }

      // Read 2: the edge function (server key inside, app keyless).
      final base = CloudClient.functionUrl('resolve');
      if (base.isEmpty) return null;
      final uri = Uri.parse(base).replace(queryParameters: {
        if (t.isNotEmpty) 'title': t,
        if ((year ?? '').trim().isNotEmpty) 'year': year!.trim(),
        'type': type == 'tv' ? 'tv' : 'movie',
        if (imdb.isNotEmpty) 'imdbId': imdb,
        if ((lang ?? '').trim().isNotEmpty) 'lang': lang!.trim().toLowerCase(),
      });
      final res = await DizzyNet.instance.get(uri, headers: buildHeaders())
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (data == null || data['tmdbId'] == null) return null;

      // Client-side exact-title lock (2026-10-10): never trust a resolved id
      // whose echoed title doesn't match the request. The server gates too,
      // but belt-and-suspenders — a mismatched id plays the WRONG video
      // (poster A, playback B) across ~40 scrapers. Mismatch → null so the
      // chain falls through to its next rung instead of playing garbage.
      // v3: the server's own guarded matches (a corpus alias, or a one-edit
      // spelling) are accepted - it applies the year + language guards the
      // client cannot see.
      final gotTitle = (data['title'] ?? '').toString();
      if (gotTitle.isNotEmpty &&
          !acceptsEcho(requested: t, echoed: gotTitle, payload: data)) {
        return null;
      }

      // Write: cache for 30 days (titles don't change IDs).
      data['_at'] = DateTime.now().millisecondsSinceEpoch;
      // ignore: unawaited_futures
      prefs.setString(key, jsonEncode(data));
      return data;
    } catch (_) {
      return null;
    }
  }
}
