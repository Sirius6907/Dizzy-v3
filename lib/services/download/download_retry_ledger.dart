import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_resume_policy.dart';

/// Phase K2 — per-task retry ledger.
///
/// Deliberately kept OUTSIDE [DownloadTask]: the task model is persisted to
/// a JSON file the app has shipped for a while, and a new field would change
/// that shape for no benefit. Retrying is policy, not task data, so it lives
/// here with its own key and its own (fail-soft) store.
class DownloadRetryLedger {
  DownloadRetryLedger._();

  static const String kPrefsKey = 'download_retry_ledger';

  static const Map<String, Map<String, int>> _empty = {};
  static Map<String, Map<String, int>> _state = _empty;
  static bool _loaded = false;

  static int attemptsFor(String id) => _state[id]?['a'] ?? 0;
  static int lastAttemptFor(String id) => _state[id]?['t'] ?? 0;

  static String encode(Map<String, Map<String, int>> s) {
    final out = <String, dynamic>{};
    s.forEach((k, v) => out[k] = v);
    return jsonEncode(out);
  }

  static Map<String, Map<String, int>> decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final v = jsonDecode(raw);
      if (v is! Map) return {};
      final out = <String, Map<String, int>>{};
      v.forEach((key, value) {
        if (key is! String || value is! Map) return;
        final a = (value['a'] as num?)?.toInt();
        final t = (value['t'] as num?)?.toInt();
        if (a == null || t == null) return;
        out[key] = {'a': a, 't': t};
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Test seam: drop in-memory state (the store is left alone) so a test can
  /// simulate a process restart.
  @visibleForTesting
  static void resetMemory() {
    _state = {};
    _loaded = false;
  }

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _state = decode(prefs.getString(kPrefsKey));
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefsKey, encode(_state));
  }

  /// Called from the central failure path. Nothing is ever dropped here —
  /// the caller decides whether the task is retryable.
  static Future<void> recordFailure(String id, {int? nowMs}) async {
    await load();
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _state[id] = {'a': (attemptsFor(id)) + 1, 't': now};
    await _persist();
  }

  /// A finished (or user-canceled) task forgets its history so a future
  /// failure starts from a clean slate.
  static Future<void> clear(String id) async {
    await load();
    if (_state.remove(id) != null) await _persist();
  }

  static bool shouldRetry(
    String id, {
    int? nowMs,
    bool justReconnected = true,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return DownloadResumePolicy.retryOnReconnect(
      justCameBackOnline: justReconnected,
      hadConnectivity: true,
      attempts: attemptsFor(id),
      lastAttemptMs: lastAttemptFor(id),
      nowMs: now,
    );
  }

  /// The ids eligible for a retry right now. Exhausted attempts are left in
  /// the ledger (so the UI can still say "gave up") but never returned.
  static List<String> eligible({int? nowMs, bool justReconnected = true}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return _state.keys
        .where(
          (id) => shouldRetry(id, nowMs: now, justReconnected: justReconnected),
        )
        .toList()
      ..sort();
  }

  static int get exhaustedCount => _state.keys
      .where((id) => DownloadResumePolicy.isExhausted(attemptsFor(id)))
      .length;
}
