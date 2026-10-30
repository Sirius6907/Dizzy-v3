import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../net/dizzy_net.dart';
import '../net/retry_policy.dart';

/// One slim browse card from the `catalog` edge feed.
class CatalogCard {
  final int id;
  final String title;
  final String? poster;
  final String? backdrop;
  final String year;
  final double rating;
  final String mediaType;
  final String lang;

  /// Why this card was recommended (`genre:Action`, `lang:hi`). Empty for
  /// plain catalog feeds.
  final String reason;

  const CatalogCard({
    required this.id,
    required this.title,
    this.poster,
    this.backdrop,
    this.year = '',
    this.rating = 0,
    this.mediaType = 'movie',
    this.lang = '',
    this.reason = '',
  });

  /// Lenient parse — a single bad card never kills the feed.
  static CatalogCard? tryParse(Map<String, dynamic> j) {
    try {
      final id = int.tryParse('${j['id'] ?? ''}');
      final title = (j['title'] ?? '').toString();
      if (id == null || title.isEmpty) return null;
      return CatalogCard(
        id: id,
        title: title,
        poster: j['poster']?.toString(),
        backdrop: j['backdrop']?.toString(),
        year: (j['year'] ?? '').toString(),
        rating: double.tryParse('${j['rating'] ?? 0}') ?? 0,
        mediaType: (j['media_type'] ?? 'movie').toString(),
        lang: (j['lang'] ?? '').toString(),
        reason: (j['reason_code'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// P22 — warm-rows-first browse feeds (`catalog` edge function).
///
/// Read order: **warm edge rows → prefs snapshot → null** (offline shows
/// last-good, never a spinner of death). Every success refreshes the
/// snapshot, so the next cold start paints instantly.
class CatalogService {
  const CatalogService._();

  static String _snapKey(
    String feed,
    String type,
    int page,
    String region,
    String language,
    String providers,
  ) =>
      'catalog_snap:$feed:$type:$page:$region:$language:$providers';

  /// [region] is the audience's country (the catalog is India-first by
  /// default, matching the app's audience), [language] is a comma list of
  /// ISO 639-1 codes, [providers] a comma list of TMDB watch-provider ids
  /// used only by `feed=discover`.
  static Future<List<CatalogCard>?> fetchFeed({
    String feed = 'trending',
    String type = 'all',
    int page = 1,
    String region = 'IN',
    String language = '',
    String providers = '',
  }) async {
    final key = _snapKey(feed, type, page, region, language, providers);
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    List<CatalogCard>? decode(String raw) {
      try {
        final list = (jsonDecode(raw) as List)
            .whereType<Map<String, dynamic>>()
            .map(CatalogCard.tryParse)
            .whereType<CatalogCard>()
            .toList();
        return list.isEmpty ? null : list;
      } catch (_) {
        return null;
      }
    }

    if (CloudClient.isReady) {
      try {
        final base = CloudClient.functionUrl('catalog');
        if (base.isNotEmpty) {
          final uri = Uri.parse(base).replace(
            queryParameters: {
              'feed': feed,
              'type': type,
              'page': '$page',
              'region': region,
              if (language.isNotEmpty) 'language': language,
              if (providers.isNotEmpty) 'providers': providers,
            },
          );
          // P3: shared client. A timeout now returns a synthetic 504
          // instead of throwing, so this falls through to the snapshot
          // the same way a 500 always did.
          final res = await DizzyNet.instance.get(
            uri,
            headers: {
              'apikey': CloudClient.anonKey,
              'Accept': 'application/json',
            },
            timeout: const Duration(seconds: 8),
            policy: RetryPolicy.quick,
            screen: 'home',
            code: 'catalog_feed',
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>?;
            final cards = ((data?['items'] as List?) ?? [])
                .whereType<Map<String, dynamic>>()
                .map(CatalogCard.tryParse)
                .whereType<CatalogCard>()
                .toList();
            if (cards.isNotEmpty) {
              // ignore: unawaited_futures
              prefs?.setString(key, jsonEncode(data?['items']));
              return cards;
            }
          }
        }
      } catch (_) {
        // Fall through to the snapshot.
      }
    }

    // Warm snapshot (last-good) — instant offline paint.
    try {
      final snap = prefs?.getString(key);
      if (snap != null) return decode(snap);
    } catch (_) {}
    return null;
  }
}
