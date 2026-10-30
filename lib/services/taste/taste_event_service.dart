import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_auth_service.dart';
import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';

/// The eight behaviours the taste engine learns from. Stored as snake_case.
enum TasteEventKind {
  play('play'),
  view('view'),
  complete('complete'),
  addList('add_list'),
  removeList('remove_list'),
  search('search'),
  rate('rate'),
  notifOpen('notif_open');

  const TasteEventKind(this.wire);

  final String wire;
}

/// Consent-gated, batched behaviour log (v1.3.3 Phase 2, client half).
///
/// Every call is local and synchronous; nothing leaves the device until a
/// batch is flushed with personalisation consent on. Failures keep the events
/// queued (capped) so a dead network costs the user nothing.
class TasteEventService {
  const TasteEventService._();

  static const _queueKey = 'taste_events_queue_v1';
  static const batchSize = 20;
  static const maxQueued = 200;

  static List<Map<String, dynamic>> _queue = [];
  static bool _loaded = false;
  static Future<void>? _inflight;
  static Timer? _timer;

  static bool Function()? _consentOverride;
  static Future<bool> Function(List<Map<String, dynamic>>)? _senderOverride;

  static bool _consentOn() =>
      _consentOverride?.call() ??
      CloudAuthService.consentGenrePrefs.value;

  /// Loads the offline queue once. Never throws: a corrupt blob is discarded.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queueKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      _queue = list.take(maxQueued).toList();
    } catch (e) {
      AppLog.d('taste: queue load failed $e');
      _queue = [];
    }
  }

  static void record(
    TasteEventKind kind, {
    String entityType = 'movie',
    String entityId = '',
    String title = '',
    String lang = '',
    List<String> genres = const [],
    Map<String, dynamic>? meta,
  }) {
    if (!_loaded) unawaited(ensureLoaded());
    _queue.add({
      'kind': kind.wire,
      'entity_type': entityType,
      'entity_id': entityId,
      'title': title.length > 300 ? title.substring(0, 300) : title,
      'lang': lang,
      'genres': genres.take(8).toList(),
      'meta': {...?meta, 'client_ts': DateTime.now().toUtc().toIso8601String()},
    });
    while (_queue.length > maxQueued) {
      _queue.removeAt(0);
    }
    _ensureTimer();
    if (_queue.length >= batchSize && _consentOn()) {
      unawaited(flush());
    } else {
      unawaited(_persist());
    }
  }

  /// Sends queued events in batches. Stops on the first failed send and keeps
  /// the rest for next time. Concurrent callers await the same run.
  static Future<void> flush() {
    final running = _inflight;
    if (running != null) return running;
    final next = _runFlush().whenComplete(() => _inflight = null);
    _inflight = next;
    return next;
  }

  static Future<void> _runFlush() async {
    await ensureLoaded();
    if (!_consentOn() || _queue.isEmpty) return;
    // Captured so a reset mid-flight can never drain a newer queue.
    final queue = _queue;
    final sender = _senderOverride ?? _cloudSend;
    while (queue.isNotEmpty) {
      final chunk = queue.take(batchSize).toList(growable: false);
      var ok = false;
      try {
        ok = await sender(chunk);
      } catch (e) {
        AppLog.d('taste: send failed $e');
        ok = false;
      }
      if (!identical(_queue, queue)) return;
      if (!ok) break;
      queue.removeRange(0, chunk.length);
      await _persist();
    }
  }

  static Future<bool> _cloudSend(List<Map<String, dynamic>> rows) async {
    if (!CloudClient.isReady) return false;
    try {
      // user_id is filled by the column default (auth.uid()) under RLS.
      await CloudClient.db.from('user_events').insert(rows);
      return true;
    } catch (e) {
      AppLog.d('taste: insert failed $e');
      return false;
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_queueKey, jsonEncode(_queue));
    } catch (_) {
      // Persistence is best-effort; in-memory queue still drains.
    }
  }

  static void _ensureTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(flush());
    });
  }

  // ── test seam ────────────────────────────────────────────────────────────
  static void configureForTest({
    required bool Function() consent,
    required Future<bool> Function(List<Map<String, dynamic>>) sender,
  }) {
    _consentOverride = consent;
    _senderOverride = sender;
  }

  static void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _queue = [];
    _loaded = true;
    _inflight = null;
    _consentOverride = null;
    _senderOverride = null;
  }

  static int get debugQueueLength => _queue.length;

  static List<String> get debugQueuedEntityIds =>
      _queue.map((e) => '${e['entity_id']}').toList();
}
