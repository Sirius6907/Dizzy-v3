/// F2 — a local record of which episodes the user actually finished.
///
/// The storage guard can only *safely* offer to delete an episode the user
/// has already watched. Nothing in the app knows that today:
///
///  - `ContinueWatchingService` **deletes** a session once it passes 90%,
///    so a finished episode leaves no local trace at all.
///  - Watched state lives in Trakt and Simkl, both behind a sign-in the
///    user may never have done. An anonymous-first app cannot depend on it.
///
/// So we keep the smallest thing that makes the cleanup suggestion honest:
/// a key per finished episode and the time it finished. No progress, no
/// position, no title, no ids beyond what the download task already holds —
/// this is a "did they watch it" flag, not a second watch-history system.
///
/// Bounded on purpose: a prefs map is not a database. Oldest entries are
/// dropped past [maxEntries], which costs the cleanup guard a candidate
/// for very old episodes and nothing else. Anonymous-first means no
/// account, no upload, and no way to lose anything the user cares about.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_sweep.dart';

class WatchedEpisodeLedger {
  const WatchedEpisodeLedger._();

  static const _prefsKey = 'dizzy_watched_episodes_v2';

  /// Hard cap. ~500 keys is a few tens of KB of JSON — small enough that
  /// reading it on the downloads screen costs nothing.
  static const int maxEntries = 500;

  /// Notifier so a card or badge can rebuild when an episode is marked.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, int> _cache = <String, int>{};
  static bool _loaded = false;

  /// Read the ledger once. Safe to call repeatedly; the second call is a
  /// no-op, and a corrupt store degrades to empty rather than throwing.
  static Future<void> initialize() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final parsed = <String, int>{};
          decoded.forEach((key, value) {
            if (value is int) parsed[key] = value;
          });
          _cache = parsed;
        }
      }
    } catch (_) {
      _cache = <String, int>{};
    }
    _loaded = true;
  }

  /// Record that the user reached the end of an episode.
  ///
  /// Re-watching moves the timestamp forward: the cleanup guard prefers
  /// the *least* recently touched episode, and a rewatch is the strongest
  /// signal there is that the file is worth keeping.
  static Future<void> markWatched({
    required String mediaId,
    required int? season,
    required int? episode,
    DateTime? at,
  }) async {
    await initialize();
    final key = storageSweepKey(mediaId: mediaId, season: season, episode: episode);
    final when = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final next = Map<String, int>.from(_cache)..[key] = when;

    if (next.length > maxEntries) {
      final byAge = next.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      for (final entry in byAge.take(next.length - maxEntries)) {
        next.remove(entry.key);
      }
    }
    _cache = next;
    revision.value++;
    await _persist();
  }

  /// Every watched key, for [rankStorageSweepCandidates].
  static Set<String> watchedKeys() => _cache.keys.toSet();

  static bool isWatched({
    required String mediaId,
    required int? season,
    required int? episode,
  }) =>
      _cache.containsKey(
        storageSweepKey(mediaId: mediaId, season: season, episode: episode),
      );

  /// Total watched episodes on record. Shown on the downloads screen so
  /// the suggestion is never a mystery.
  static int get count => _cache.length;

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_cache));
    } catch (_) {
      // A ledger we cannot save only costs us a cleanup suggestion.
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _cache = <String, int>{};
    _loaded = false;
    revision.value = 0;
  }
}
