import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';

/// One slim browse card from the `catalog` edge feed.
class CatalogCard {
  final int id;
  final String title;
  final String? poster;
  final String? backdrop;
  final String year;
  final double rating;
  final String mediaType;

  const CatalogCard({
    required this.id,
    required this.title,
    this.poster,
    this.backdrop,
    this.year = '',
    this.rating = 0,
    this.mediaType = 'movie',
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

  static String _snapKey(String feed, String type, int page) =>
      'catalog_snap:$feed:$type:$page';

  static Future<List<CatalogCard>?> fetchFeed({
    String feed = 'trending',
    String type = 'all',
    int page = 1,
  }) async {
    final key = _snapKey(feed, type, page);
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
          final uri = Uri.parse(base).replace(queryParameters: {
            'feed': feed,
            'type': type,
            'page': '$page',
          });
          final res = await http.get(uri, headers: {
            'apikey': CloudClient.anonKey,
            'Accept': 'application/json',
          }).timeout(const Duration(seconds: 8));
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
