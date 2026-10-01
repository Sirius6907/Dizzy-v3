import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase K4 — DM outbox. Optimistic, persisted, retried.
///
/// Contract (plan §2f): "optimistic send queue with retry (outbox pattern) so
/// messages never lose on kill". The entry is written to disk BEFORE the
/// network attempt starts, so a process death mid-send leaves a record that
/// the next launch (or the next resume) retries instead of dropping.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.recipientUid,
    required this.recipientUsername,
    required this.body,
    required this.createdAtMs,
    this.attempts = 0,
    this.lastAttemptMs = 0,
  });

  final String id;
  final String recipientUid;
  final String recipientUsername;
  final String body;
  final int createdAtMs;
  final int attempts;

  /// 0 = never attempted.
  final int lastAttemptMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': recipientUid,
    'user': recipientUsername,
    'body': body,
    'ts': createdAtMs,
    'attempts': attempts,
    'last': lastAttemptMs,
  };

  static OutboxEntry fromJson(Map<String, dynamic> j) => OutboxEntry(
    id: j['id'] as String? ?? '',
    recipientUid: j['uid'] as String? ?? '',
    recipientUsername: j['user'] as String? ?? '',
    body: j['body'] as String? ?? '',
    createdAtMs: (j['ts'] as num?)?.toInt() ?? 0,
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    lastAttemptMs: (j['last'] as num?)?.toInt() ?? 0,
  );

  OutboxEntry copyWith({int? attempts, int? lastAttemptMs}) => OutboxEntry(
    id: id,
    recipientUid: recipientUid,
    recipientUsername: recipientUsername,
    body: body,
    createdAtMs: createdAtMs,
    attempts: attempts ?? this.attempts,
    lastAttemptMs: lastAttemptMs ?? this.lastAttemptMs,
  );
}

class DmOutbox {
  DmOutbox._();

  static const String kPrefsKey = 'dm_outbox';

  /// Hard ceiling on a single entry's backoff, so a dead server still gets
  /// retried every few minutes rather than drifting out to hours.
  static const int maxBackoffMs = 5 * 60 * 1000;

  /// After this many attempts we stop and ask the user (never silent-hold).
  static const int maxAttempts = 12;

  static final ValueNotifier<List<OutboxEntry>> entries =
      ValueNotifier<List<OutboxEntry>>(const []);
  static final Random _rng = Random();
  static bool _loaded = false;
  static Timer? _scheduler;

  // ── pure backoff / scheduling (tested) ───────────────────────────────────

  /// 1s → 2s → 4s … capped at [maxBackoffMs], with ±20% jitter so a server
  /// blip does not produce a thundering herd of retries.
  static int backoffMs(int attempts, {int? jitterSample}) {
    if (attempts <= 0) return 1000;
    final exp = attempts > 30 ? 30 : attempts;
    var ms = 1000 * (1 << exp);
    if (ms > maxBackoffMs || ms <= 0) ms = maxBackoffMs;
    // jitterSample is 0..9999 in tests; real calls use the clock-backed rng.
    final jitter = (jitterSample ?? _rng.nextInt(10000)) / 10000.0;
    return (ms * (0.8 + 0.4 * jitter)).round();
  }

  static bool isExhausted(OutboxEntry e) => e.attempts >= maxAttempts;

  /// Due when it has never been tried, or its backoff window has elapsed.
  static bool isDue(OutboxEntry e, int nowMs) {
    if (isExhausted(e)) return false;
    if (e.lastAttemptMs <= 0) return true;
    return nowMs - e.lastAttemptMs >= backoffMs(e.attempts);
  }

  static List<OutboxEntry> dueNow(Iterable<OutboxEntry> list, int nowMs) =>
      list.where((e) => isDue(e, nowMs)).toList();

  /// Oldest first — order matters so a retry does not reorder a conversation.
  static List<OutboxEntry> forRecipient(
    Iterable<OutboxEntry> list,
    String uid,
  ) {
    final out = list.where((e) => e.recipientUid == uid).toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    return out;
  }

  // ── persistence ──────────────────────────────────────────────────────────

  static String encode(List<OutboxEntry> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<OutboxEntry> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      if (v is! List) return const [];
      return v
          .whereType<Map<String, dynamic>>()
          .map(OutboxEntry.fromJson)
          .where((e) => e.id.isNotEmpty && e.body.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Test seam: drop in-memory state so a test can prove a queued message
  /// survives a process death (only the persisted store is kept).
  @visibleForTesting
  static void resetMemory() {
    entries.value = const [];
    _loaded = false;
  }

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    entries.value = decode(prefs.getString(kPrefsKey));
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefsKey, encode(entries.value));
  }

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${_rng.nextInt(0x7fffffff).toRadixString(16)}';

  /// Called BEFORE the send attempt — this is the "never lose on kill" step.
  static Future<OutboxEntry> enqueue({
    required String recipientUid,
    required String recipientUsername,
    required String body,
  }) async {
    await load();
    final entry = OutboxEntry(
      id: _newId(),
      recipientUid: recipientUid,
      recipientUsername: recipientUsername,
      body: body,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    entries.value = [...entries.value, entry];
    await _persist();
    return entry;
  }

  static Future<void> markSent(String id) async {
    await load();
    if (entries.value.any((e) => e.id == id)) {
      entries.value = entries.value.where((e) => e.id != id).toList();
      await _persist();
    }
  }

  /// Counts the attempt. Exhausted entries stop being due (see
  /// [isExhausted]) so a dead endpoint cannot spin forever.
  static Future<void> recordFailure(String id, {int? nowMs}) async {
    await load();
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final next = <OutboxEntry>[];
    var changed = false;
    for (final e in entries.value) {
      if (e.id == id) {
        next.add(e.copyWith(attempts: e.attempts + 1, lastAttemptMs: now));
        changed = true;
      } else {
        next.add(e);
      }
    }
    if (changed) {
      entries.value = next;
      await _persist();
    }
  }

  static Future<void> remove(String id) async {
    await load();
    if (entries.value.any((e) => e.id == id)) {
      entries.value = entries.value.where((e) => e.id != id).toList();
      await _persist();
    }
  }

  /// Retry every due entry. Failures stay queued — they are never dropped.
  static Future<int> flush({
    required Future<bool> Function(OutboxEntry entry) send,
    int? nowMs,
  }) async {
    await load();
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    var sent = 0;
    for (final e in List.of(entries.value)) {
      if (!isDue(e, now)) continue;
      var ok = false;
      try {
        ok = await send(e);
      } catch (_) {
        ok = false;
      }
      if (ok) {
        await markSent(e.id);
        sent++;
      } else {
        await recordFailure(e.id);
      }
    }
    return sent;
  }

  /// One timer for the whole app: retries whatever is stuck while it is
  /// alive, and again on the next launch after a kill.
  static void startScheduler(
    Future<bool> Function(OutboxEntry entry) send, {
    Duration every = const Duration(seconds: 45),
  }) {
    _scheduler ??= Timer.periodic(every, (_) {
      unawaited(flush(send: send));
    });
  }

  static void stopScheduler() {
    _scheduler?.cancel();
    _scheduler = null;
  }
}
