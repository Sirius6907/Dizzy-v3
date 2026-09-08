import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// F0 (v1.1.9): Dead Scraper Quarantine.
///
/// Scrapers documented down in `docs/scraper-status-v1.1.9.md` are auto-skipped
/// so users don't wait on spinning dead endpoints. Every 7 days, each
/// quarantined scraper gets one retry attempt. If it succeeds, it unquarantines.
class ScraperQuarantineService {
  static const _key = 'scraper_quarantine_v1';
  static const _cooldown = Duration(days: 7);

  /// Baseline known-dead scrapers triaged in docs/scraper-status-v1.1.9.md.
  /// Matched against `scraper.name.toLowerCase()`.
  static const Set<String> _baselineDead = {
    'flaxmovies',
    'peestream',
    'vidfast',
    'vidgod',
    'vidup',
    'bcine',
  };

  static Map<String, DateTime> _quarantineMap = {};
  static bool _loaded = false;

  static Future<void> initialize() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _quarantineMap = decoded.map(
          (k, v) => MapEntry(k, DateTime.tryParse(v.toString()) ?? DateTime.now()),
        );
      }
    } catch (_) {}

    // Seed baseline dead if not already tracked.
    final now = DateTime.now();
    var changed = false;
    for (final name in _baselineDead) {
      if (!_quarantineMap.containsKey(name)) {
        _quarantineMap[name] = now;
        changed = true;
      }
    }
    if (changed) _persist();
  }

  /// Returns true if [scraperName] should be skipped on this scrape run.
  static bool isQuarantined(String scraperName) {
    final key = scraperName.trim().toLowerCase();
    final quarantinedAt = _quarantineMap[key];
    if (quarantinedAt == null) return false;

    // Has the 7-day cooldown elapsed? If so, allow retry.
    if (DateTime.now().difference(quarantinedAt) >= _cooldown) {
      return false;
    }
    return true;
  }

  /// Called when a scraper successfully returns sources — unquarantines it.
  static void markSuccess(String scraperName) {
    final key = scraperName.trim().toLowerCase();
    if (_quarantineMap.remove(key) != null) {
      _persist();
      debugPrint('[Quarantine] $scraperName recovered! Unquarantined.');
    }
  }

  /// Called after persistent failures to reset the 7-day retry clock.
  static void markFailed(String scraperName) {
    final key = scraperName.trim().toLowerCase();
    _quarantineMap[key] = DateTime.now();
    _persist();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _quarantineMap.map((k, v) => MapEntry(k, v.toIso8601String()));
      await prefs.setString(_key, jsonEncode(map));
    } catch (_) {}
  }

  /// Pure helper for unit testing.
  static bool shouldSkip({
    required String name,
    required Map<String, DateTime> map,
    required DateTime now,
    Duration cooldown = const Duration(days: 7),
  }) {
    final key = name.trim().toLowerCase();
    final at = map[key];
    if (at == null) return false;
    return now.difference(at) < cooldown;
  }
}
