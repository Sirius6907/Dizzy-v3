import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// F6+/C5 (v1.1.9): local genre-preference scores.
///
/// Counts genres from titles the user watches / lists, keeps a 0.0–1.0
/// score map in prefs. Powers "Because You Watched" ranking today;
/// syncs to Supabase `genre_prefs` (C5) when the user opts in.
/// Privacy: genre SCORES only (e.g. action:0.8) — never raw watch titles.
class GenrePreferenceService {
  static const _key = 'genre_preference_scores_v1';
  static const _maxGenres = 40;

  static final ValueNotifier<Map<String, double>> scores =
      ValueNotifier<Map<String, double>>({});

  static bool _loaded = false;

  /// Record genres for one watched/listed title. Cheap: called on
  /// episode-complete / list-add only, never per-tick.
  static Future<void> recordGenres(List<String> genres) async {
    if (genres.isEmpty) return;
    await _ensureLoaded();
    final map = Map<String, double>.from(scores.value);
    for (final raw in genres) {
      final g = raw.trim().toLowerCase();
      if (g.isEmpty) continue;
      map[g] = ((map[g] ?? 0.0) + 0.15).clamp(0.0, 1.0);
    }
    // Decay everything slightly so tastes drift over time.
    for (final k in map.keys.toList()) {
      map[k] = (map[k]! * 0.995);
    }
    // Cap map size: drop lowest scores.
    if (map.length > _maxGenres) {
      final sorted = map.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (var i = 0; i < map.length - _maxGenres; i++) {
        map.remove(sorted[i].key);
      }
    }
    scores.value = map;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(map));
    } catch (_) {}
  }

  /// Rank candidate genre lists by overlap with learned scores.
  /// Returns candidates sorted best-first (stable, pure function — testable).
  static List<T> rankByGenreOverlap<T>(
    List<T> candidates,
    List<String> Function(T) genresOf,
  ) {
    final s = scores.value;
    if (s.isEmpty) return candidates;
    final scored = candidates.map((c) {
      double total = 0;
      for (final g in genresOf(c)) {
        total += s[g.trim().toLowerCase()] ?? 0.0;
      }
      return (item: c, score: total);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.item).toList();
  }

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = Map<String, dynamic>.from(jsonDecode(raw));
        scores.value = decoded.map(
          (k, v) => MapEntry(k, (v as num).toDouble().clamp(0.0, 1.0)),
        );
      }
    } catch (_) {}
  }

  /// For cloud sync (C5): export scores as plain map.
  static Map<String, double> exportScores() =>
      Map<String, double>.from(scores.value);

  /// For cloud sync (C5): merge remote scores (max-wins per genre).
  static Future<void> mergeRemoteScores(Map<String, double> remote) async {
    if (remote.isEmpty) return;
    await _ensureLoaded();
    final map = Map<String, double>.from(scores.value);
    for (final e in remote.entries) {
      final g = e.key.trim().toLowerCase();
      if (g.isEmpty) continue;
      final v = e.value.clamp(0.0, 1.0);
      map[g] = (v > (map[g] ?? 0.0)) ? v : map[g]!;
    }
    scores.value = map;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(map));
    } catch (_) {}
  }
}
