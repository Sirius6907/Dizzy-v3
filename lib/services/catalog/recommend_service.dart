import 'dart:convert';

import '../cloud/cloud_client.dart';
import '../net/dizzy_net.dart';
import '../net/retry_policy.dart';
import 'catalog_service.dart';

/// Personal rail client for the `recommend` edge function (Phase 2).
///
/// The function answers from the user's rolled-up taste profile; this class
/// only carries the user's token and parses cards. Cold users (under three
/// events) get `personal:false` → null, and the home rail stays hidden.
/// Every failure is soft: home still paints the fresh feed.
class RecommendService {
  const RecommendService._();

  static Future<List<CatalogCard>?> fetch() async {
    if (!CloudClient.isReady) return null;
    final token = CloudClient.db.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;
    try {
      final base = CloudClient.functionUrl('recommend');
      if (base.isEmpty) return null;
      final res = await DizzyNet.instance.get(
        Uri.parse(base),
        headers: {
          'apikey': CloudClient.anonKey,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
        timeout: const Duration(seconds: 8),
        policy: RetryPolicy.quick,
        screen: 'home',
        code: 'recommend_feed',
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (data?['personal'] != true) return null;
      final cards = ((data?['items'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CatalogCard.tryParse)
          .whereType<CatalogCard>()
          .toList();
      return cards.isEmpty ? null : cards;
    } catch (_) {
      return null;
    }
  }
}
