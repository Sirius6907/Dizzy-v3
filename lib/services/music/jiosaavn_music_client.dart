import 'package:flutter/foundation.dart';

import '../../models/music/music_track.dart';
import '../cloud/cloud_client.dart';
import 'music_match_policy.dart';

/// v1.3.3-T3.0 — JioSaavn client (desi backbone: Hindi/Punjabi/Bollywood
/// plus Ollywood depth).
///
/// Talks ONLY to the Supabase `music-source` edge function. The upstream
/// Saavn endpoints are never in the app (secure-edge-proxy rule), so a
/// provider change is a server deploy, not an app update.
///
/// Failure shape: every method returns an empty list rather than throwing.
/// One dead source must cost the user one row, never the music page.
class JiosaavnMusicClient {
  static final JiosaavnMusicClient instance = JiosaavnMusicClient._internal();
  JiosaavnMusicClient._internal();

  /// Per-call budget. The edge itself holds a 10s upstream timeout, so this
  /// sits above it — a shorter outer timer would fire first and cancel the
  /// server's own retry window (site §2 rule).
  static const Duration callBudget = Duration(seconds: 14);

  Future<List<MusicTrack>> search(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _call(op: 'search', query: q, limit: limit);
  }

  /// Trending/songs for the desi rows.
  Future<List<MusicTrack>> trending({int limit = 20}) async {
    return _call(op: 'trending', limit: limit);
  }

  Future<List<MusicTrack>> _call({
    required String op,
    String query = '',
    required int limit,
  }) async {
    if (!CloudClient.isReady) return const [];
    try {
      final res = await CloudClient.db.functions
          .invoke('music-source', body: {
            'provider': 'jiosaavn',
            'op': op,
            if (query.isNotEmpty) 'query': query,
            'limit': limit,
          })
          .timeout(callBudget);
      final data = res.data;
      if (data is! Map) return const [];
      final rows = data['tracks'];
      if (rows is! List) return const [];
      final out = <MusicTrack>[];
      for (final row in rows) {
        if (row is! Map) continue;
        final t = _toTrack(Map<String, dynamic>.from(row));
        if (t != null) out.add(t);
      }
      return out;
    } catch (e) {
      debugPrint('JioSaavn search failed (soft): $e');
      return const [];
    }
  }

  /// Edge row → the app's shared MusicTrack. Ids namespaced `saavn_` so a
  /// Saavn id can never collide with a Deezer id downstream.
  @visibleForTesting
  static MusicTrack? toTrack(Map<String, dynamic> row) => _toTrack(row);

  static MusicTrack? _toTrack(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString().trim();
    final title = (row['title'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty) return null;
    final preview = (row['previewUrl'] ?? '').toString().trim();
    return MusicTrack(
      id: 'saavn_$id',
      title: title,
      artist: (row['artist'] ?? 'Unknown Artist').toString(),
      album: (row['album'] ?? 'Single').toString(),
      coverUrl: (row['coverUrl'] ?? '').toString(),
      durationSeconds: int.tryParse((row['durationSeconds'] ?? 0).toString()) ?? 0,
      previewUrl: preview.isEmpty ? null : preview,
    );
  }

  /// Exact-match picker over Saavn results (site §13: exact or nothing).
  /// Returns null rather than a wrong song.
  @visibleForTesting
  static MusicTrack? pickExact(List<MusicTrack> tracks, String wanted, {int? year}) {
    final idx = MusicMatchPolicy.pickExact(
      wanted,
      candidateTitles: tracks.map((t) => t.title).toList(),
      lang: MusicMatchPolicy.languageHint(wanted),
    );
    return idx == null ? null : tracks[idx];
  }
}