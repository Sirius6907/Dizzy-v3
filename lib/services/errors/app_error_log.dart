import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_auth_service.dart';
import '../cloud/cloud_client.dart';
import '../device/device_id_service.dart';

/// One payload → one server call. Completing normally means the report
/// was consumed — stored, or deliberately rejected. Throwing means it did
/// NOT land (edge missing, offline, 5xx) and must stay queued.
typedef AppErrorTransport = Future<void> Function(Map<String, dynamic> payload);

/// v1.2.0-T2.2/T2.9: opt-in error-log pipeline (client side).
///
/// Privacy contract (PRD FR-8/FR-9, TRD §8.2):
/// - Sends ONLY when `consentCrash == true` AND cloud ready.
/// - Payload: {device_code, platform, app_version, screen, code, detail}
/// - NEVER: URLs, magnets, tokens, titles, stack traces, raw exception text.
/// - `detail` is a short enum string (e.g. `timeout_20s`), never raw text.
/// - Consent OFF → drop silently, zero transmission, no exceptions.
///
/// Transport: the `report-error` edge function, which validates the same
/// contract and writes through the `report_error` RPC — the only writer to
/// `device_logs`. Sends fail soft and stay queued (cap 100, drop-oldest).
/// Throttle: same code+screen max 1 immediate send / 24h / device.
///
/// P2 note — [buildPayload] is the privacy gate, and it is load-bearing.
/// Callers are not trusted to honour the contract: `error_boundary.dart`
/// passes `'$error'` as `detail` for framework and async errors. Every
/// free-form field is therefore matched against its allowlist *as a whole*
/// and replaced when it does not match. Partial stripping is not a
/// sanitiser — "Bad state: no element" becomes "badstatenoelement" and
/// still leaks the words.
class AppErrorLog {
  const AppErrorLog._();

  static const _queueKey = 'app_error_queue_v1';
  static const _throttlePrefix = 'app_error_sent_at_v1_';
  static const _maxQueue = 100;
  static const _throttleWindow = Duration(hours: 24);

  static const _codeMax = 48;
  static const _screenMax = 64;
  static const _detailMax = 64;
  static const _versionMax = 32;

  static final RegExp _codePattern = RegExp(r'^[a-z0-9_]+$');
  static final RegExp _screenPattern = RegExp(r'^[a-z0-9_]+$');
  static final RegExp _detailPattern = RegExp(r'^[a-z0-9_.\-]+$');
  static final RegExp _versionPattern = RegExp(r'^[a-z0-9_.+\-]+$');
  static final RegExp _devicePattern = RegExp(r'^[1-9][0-9]{6}$');

  static const _platforms = <String>{
    'android', 'ios', 'windows', 'linux', 'macos', 'fuchsia', 'web',
  };

  static Timer? _flushTimer;
  static bool _flushScheduled = false;

  /// Log an error. Fire-and-forget — never throws, never blocks UI.
  static Future<void> log({
    required String code,
    required String screen,
    String detail = '',
  }) async {
    try {
      if (!CloudAuthService.consentCrash.value) return; // opt-in gate

      final safeCode = sanitizeCode(code);
      final safeScreen = sanitizeScreen(screen);
      final prefs = await SharedPreferences.getInstance();

      // Throttle: same code+screen once per 24h per device.
      final throttleKey = throttleKeyFor(safeCode, safeScreen);
      final last = prefs.getInt(throttleKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final throttled = shouldThrottle(last, nowMs);

      // Queue the entry (for flush now or later).
      final queue = _readQueue(prefs);
      queue.add(<String, dynamic>{
        'code': safeCode,
        'screen': safeScreen,
        'detail': sanitizeDetail(detail),
        'at': nowMs,
      });
      while (queue.length > maxQueue) {
        queue.removeAt(0);
      }
      await prefs.setString(_queueKey, jsonEncode(queue));

      if (throttled) return;
      await prefs.setInt(throttleKey, nowMs);
      unawaited(flush());
    } catch (_) {
      // Logging must never break the app.
    }
  }

  /// Flush queued entries to the `report-error` edge. Safe to call anytime.
  static Future<void> flush() async {
    if (!CloudClient.isReady) return;
    if (CloudClient.db.auth.currentUser == null) return;
    try {
      await drain(
        consent: CloudAuthService.consentCrash.value,
        send: _sendToEdge,
      );
    } catch (_) {
      // Fail soft.
    }
  }

  /// Drain the queue oldest-first, stopping at the first entry that does
  /// not land. Returns true when nothing is left queued. Never throws.
  ///
  /// [consent] is checked once, before the first send, not per entry: a
  /// mid-drain consent change must not leave a half-sent queue behind.
  @visibleForTesting
  static Future<bool> drain({
    required bool consent,
    required AppErrorTransport send,
  }) async {
    if (!consent) return false;
    final prefs = await SharedPreferences.getInstance();
    final remaining = List<Map<String, dynamic>>.from(_readQueue(prefs));
    if (remaining.isEmpty) return true;

    final deviceCode = DeviceIdService.deviceCode.value ?? '';
    final platform = _platform();
    final version = await _appVersion();

    while (remaining.isNotEmpty) {
      final entry = remaining.first;
      // `.toString()` rather than a cast: a queue written by an older
      // build must not throw here. A non-string falls out of the
      // allowlist and lands as 'unknown', which is the fail-soft answer.
      final payload = buildPayload(
        deviceCode: deviceCode,
        platform: platform,
        appVersion: version,
        screen: (entry['screen'] ?? '').toString(),
        code: (entry['code'] ?? '').toString(),
        detail: (entry['detail'] ?? '').toString(),
      );
      try {
        // Any normal return consumes the entry — the server may have
        // chosen not to store it, and retrying that forever would pin the
        // queue at its 100-slot cap.
        await send(payload);
        remaining.removeAt(0);
      } catch (_) {
        // Edge missing / offline / 5xx. Keep this entry and everything
        // behind it for the next flush, then stop.
        break;
      }
    }
    await prefs.setString(_queueKey, jsonEncode(remaining));
    return remaining.isEmpty;
  }

  /// The exact wire shape the `report_error` RPC accepts — six fields, no
  /// count (the server folds repeats into its own `count` column).
  @visibleForTesting
  static Map<String, dynamic> buildPayload({
    required String deviceCode,
    required String platform,
    required String appVersion,
    required String screen,
    required String code,
    String detail = '',
  }) =>
      <String, dynamic>{
        'device_code': sanitizeDeviceCode(deviceCode),
        'platform': sanitizePlatform(platform),
        'app_version': sanitizeVersion(appVersion),
        'screen': sanitizeScreen(screen),
        'code': sanitizeCode(code),
        'detail': sanitizeDetail(detail),
      };

  // ── privacy gate ──
  // Each of these returns the value only when the WHOLE string matches the
  // allowlist, so free text cannot ride along in an enum column.

  /// `unknown` when the install code is missing or malformed. The code is
  /// minted at startup; a crash before that still gets counted.
  @visibleForTesting
  static String sanitizeDeviceCode(String raw) {
    final v = raw.trim();
    return _devicePattern.hasMatch(v) ? v : 'unknown';
  }

  @visibleForTesting
  static String sanitizePlatform(String raw) {
    final v = raw.trim().toLowerCase();
    return _platforms.contains(v) ? v : 'unknown';
  }

  @visibleForTesting
  static String sanitizeVersion(String raw) =>
      _strict(raw, _versionMax, _versionPattern);

  @visibleForTesting
  static String sanitizeScreen(String raw) {
    final v = _strict(raw, _screenMax, _screenPattern);
    return v.isEmpty ? 'unknown' : v;
  }

  /// `unknown` rather than a drop: losing the code loses the whole report,
  /// and an unrecognised code is still an error worth counting.
  @visibleForTesting
  static String sanitizeCode(String raw) {
    final v = _strict(raw, _codeMax, _codePattern);
    return v.isEmpty ? 'unknown' : v;
  }

  /// `redacted` marks a caller that tried to send free text, so a
  /// misbehaving call site is visible in the dashboard instead of silent.
  @visibleForTesting
  static String sanitizeDetail(String raw) {
    final v = _strict(raw, _detailMax, _detailPattern);
    return v.isEmpty && raw.trim().isNotEmpty ? 'redacted' : v;
  }

  static String _strict(String raw, int max, RegExp pattern) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty || v.length > max || !pattern.hasMatch(v)) return '';
    return v;
  }

  // ── transport ──

  static Future<void> _sendToEdge(Map<String, dynamic> payload) async {
    // Throws when the edge is unreachable or answers non-2xx; the entry
    // then stays queued for the next flush.
    final res = await CloudClient.db.functions
        .invoke('report-error', body: payload);
    final data = res.data;
    if (data is! Map || data['ok'] != true) {
      throw StateError('report-error did not acknowledge the report');
    }
    // stored:false is a normal completion: the server consumed the report
    // and chose not to keep it (bad code, or the device hit its daily cap).
  }

  // ── schedule ──

  /// Schedule periodic flush (call once at startup). 15-min cadence.
  static void schedulePeriodicFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    _flushTimer ??= Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(flush()),
    );
  }

  /// Flush once on app start (call after cloud init).
  static Future<void> flushOnStart() => flush();

  // ── internals / test hooks ──

  static List<Map<String, dynamic>> _readQueue(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_queueKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// Queued entries, oldest first. Test hook.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> pending() async =>
      _readQueue(await SharedPreferences.getInstance());

  /// Drop the queue. Test hook — isolates one test from the next.
  @visibleForTesting
  static Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(<dynamic>[]));
  }

  /// Test hook: queue cap (oldest entries are dropped past this).
  @visibleForTesting
  static int get maxQueue => _maxQueue;

  /// Test hook: the throttle slot for a code+screen pair.
  @visibleForTesting
  static String throttleKeyFor(String code, String screen) =>
      '$_throttlePrefix${code}_$screen';

  /// Test hook: pure throttle decision (no prefs needed).
  @visibleForTesting
  static bool shouldThrottle(int lastSentMs, int nowMs) {
    return nowMs - lastSentMs < _throttleWindow.inMilliseconds;
  }

  static String _platform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isFuchsia) return 'fuchsia';
    return 'unknown';
  }

  static Future<String> _appVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      return pkg.version;
    } catch (_) {
      return 'unknown';
    }
  }
}
