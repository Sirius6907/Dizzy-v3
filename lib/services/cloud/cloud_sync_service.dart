import 'package:flutter/foundation.dart';

import '../../models/continue_watching/continue_watching_item.dart';
import '../continue_watching/continue_watching_service.dart';
import 'cloud_client.dart';

/// S3A (v1.1.9): cross-device Continue Watching sync.
///
/// Strictly signed-in accounts only — anonymous installs never upload watch
/// history. Payload is sanitized: no stream URLs, magnets, headers, tokens,
/// addon/source labels or IP-like values. Newer `lastWatchedAt` wins.
class CloudSyncService {
  static bool _syncing = false;
  static DateTime? _lastSyncAt;
  static const _minimumInterval = Duration(seconds: 30);

  static bool get isLoggedIn {
    if (!CloudClient.isReady) return false;
    final user = CloudClient.db.auth.currentUser;
    return user != null && !user.isAnonymous;
  }

  static Future<void> syncNow({bool force = false}) async {
    if (!isLoggedIn || _syncing) return;
    final now = DateTime.now();
    if (!force && _lastSyncAt != null &&
        now.difference(_lastSyncAt!) < _minimumInterval) {
      return;
    }
    _syncing = true;
    try {
      final uid = CloudClient.db.auth.currentUser!.id;
      final local = List<ContinueWatchingItem>.from(
          ContinueWatchingService.activeItems.value);

      // Upload only safe metadata + progress. Source credentials stay device-only.
      for (final item in local) {
        await CloudClient.db.from('cloud_sessions').upsert({
          'user_id': uid,
          'media_id': item.id,
          'title': item.title,
          'media_type': item.type,
          'poster_url': item.posterUrl,
          'backdrop_url': item.backdropUrl,
          'year': item.year,
          'season': item.season,
          'episode': item.episode,
          'episode_title': item.episodeTitle,
          'position_seconds': item.positionSeconds,
          'total_duration_seconds': item.totalDurationSeconds,
          'updated_at': item.lastWatchedAt.toUtc().toIso8601String(),
        }, onConflict: 'user_id,media_id');
      }

      final response = await CloudClient.db
          .from('cloud_sessions')
          .select()
          .eq('user_id', uid)
          .order('updated_at', ascending: false)
          .limit(50);
      final remote = (response as List)
          .whereType<Map<String, dynamic>>()
          .map(_fromSafeJson)
          .toList();
      final merged = mergeNewestWins(local, remote);
      await ContinueWatchingService.replaceSessionsFromCloud(merged);
      _lastSyncAt = now;
    } catch (e) {
      debugPrint('[CloudSync] sync failed (soft): $e');
    } finally {
      _syncing = false;
    }
  }

  /// Pure merge: newest timestamp wins; cap matches local CW cap.
  static List<ContinueWatchingItem> mergeNewestWins(
      List<ContinueWatchingItem> local, List<ContinueWatchingItem> remote) {
    final byId = <String, ContinueWatchingItem>{};
    for (final item in [...local, ...remote]) {
      final old = byId[item.sessionKey];
      if (old == null || item.lastWatchedAt.isAfter(old.lastWatchedAt)) {
        byId[item.sessionKey] = item;
      }
    }
    final merged = byId.values.where((e) => !e.isCompleted).toList()
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return merged.take(50).toList();
  }

  static ContinueWatchingItem _fromSafeJson(Map<String, dynamic> json) {
    int asInt(dynamic value) => value is int
        ? value
        : int.tryParse(value?.toString() ?? '') ?? 0;
    return ContinueWatchingItem(
      id: json['media_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: json['media_type']?.toString() ?? 'movie',
      posterUrl: json['poster_url']?.toString(),
      backdropUrl: json['backdrop_url']?.toString(),
      year: json['year']?.toString(),
      season: json['season'] == null ? null : asInt(json['season']),
      episode: json['episode'] == null ? null : asInt(json['episode']),
      episodeTitle: json['episode_title']?.toString(),
      positionSeconds: asInt(json['position_seconds']),
      totalDurationSeconds: asInt(json['total_duration_seconds']),
      lastWatchedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
      isTorrent: false,
      // Remote source details intentionally absent: user picks a source locally.
    );
  }
}
