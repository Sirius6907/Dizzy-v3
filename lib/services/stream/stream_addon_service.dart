import 'dart:convert';

import '../../models/addon/addon.dart';
import '../../models/stream/stream_model.dart';
import '../addon/addon_manager.dart';
import '../net/dizzy_net.dart';
import '../errors/app_log.dart';

/// Fetches streams from installed Stremio addons only (no built-in scrapers).
///
/// Lives apart from `StreamService` so the anime pipeline can use addons
/// (Torrentio/AcuAnime through a Kitsu id) without importing the scraper
/// registry back into itself.
abstract final class StreamAddonService {
  /// Stremio stream path for an addon call.
  ///
  /// Series and anime addons need the episode in the ID itself
  /// (`series/tt123:1:2`, `anime/kitsu:123:53`); calling with the bare title
  /// ID returns nothing or the wrong episode.
  static String buildPath({
    required String type,
    required String id,
    int? season,
    int? episode,
  }) {
    var mediaId = id;
    final segments = id.split(':');
    final isEpisodic = type == 'series' || type == 'anime';
    final alreadyScoped = segments.length >= 3;

    if (isEpisodic && !alreadyScoped) {
      if (type == 'anime') {
        if (episode != null) mediaId = '$id:$episode';
      } else if (season != null && episode != null) {
        mediaId = '$id:$season:$episode';
      }
    }

    final encoded = mediaId.split(':').map(Uri.encodeComponent).join(':');
    return '$type/$encoded';
  }

  static Future<List<StreamSource>> fetchFrom(
    InstalledAddon addon,
    String type,
    String id, {
    int? season,
    int? episode,
  }) async {
    try {
      if (addon.manifest.idPrefixes.isNotEmpty) {
        final matchesPrefix = addon.manifest.idPrefixes.any(
          (p) => id.startsWith(p),
        );
        if (!matchesPrefix) return [];
      }
      if (addon.manifest.types.isNotEmpty &&
          !addon.manifest.types.contains(type)) {
        return [];
      }

      final url =
          '${addon.baseUrl}/stream/'
          '${buildPath(type: type, id: id, season: season, episode: episode)}'
          '.json';

      final response = await DizzyNet.instance
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final streams = data['streams'] as List<dynamic>?;
      if (streams == null || streams.isEmpty) return [];

      return streams
          .whereType<Map>()
          .map(
            (json) => StreamSource.fromJson(
              Map<String, dynamic>.from(json),
              addon.manifest.name,
            ),
          )
          .where(
            (s) => s.url != null || s.infoHash != null || s.externalUrl != null,
          )
          .toList();
    } catch (e) {
      AppLog.d('Addon ${addon.manifest.name} stream fetch failed: $e');
      return [];
    }
  }

  /// All active, gate-allowed stream addons, sequentially.
  static Stream<StreamSource> fetchAll({
    required String type,
    required String id,
    int? season,
    int? episode,
  }) async* {
    final addons = AddonManager.instance.activeStreamAddons
        .where(AddonManager.allowAddon)
        .toList(growable: false);
    for (final addon in addons) {
      final sources = await fetchFrom(
        addon,
        type,
        id,
        season: season,
        episode: episode,
      );
      for (final source in sources) {
        yield source;
      }
    }
  }
}
