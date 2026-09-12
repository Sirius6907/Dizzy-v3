import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_auth_service.dart';
import '../cloud/cloud_client.dart';
import '../device/device_id_service.dart';

/// v1.2.0-T2.2/T2.9: opt-in error-log pipeline (client side).
///
/// Privacy contract (PRD FR-8/FR-9, TRD §8.2):
/// - Sends ONLY when `consentCrash == true` AND cloud ready.
/// - Payload: {device_code, platform, app_version, screen, code, detail, count}
/// - NEVER: URLs, magnets, tokens, titles, stack traces, raw exception text.
/// - `detail` is a short enum string (e.g. `timeout_20s`), never raw text.
/// - Consent OFF → drop silently, zero transmission, no exceptions.
///
/// Transport: `report-error` edge function (SPEC — Backend §7 item 2).
/// Until the edge + `app_logs` table exist, sends fail soft and stay queued
/// (cap 100, drop-oldest). Throttle: same code+screen max 1 send / 24h / device.
class AppErrorLog {
  const AppErrorLog._();

  static const _queueKey = 'app_error_queue_v1';
  static const _throttlePrefix = 'app_error_sent_at_v1_';
  static const _maxQueue = 100;
  static const _throttleWindow = Duration(hours: 24);

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

      final prefs = await SharedPreferences.getInstance();

      // Throttle: same code+screen once per 24h per device.
      final throttleKey = '$_throttlePrefix${code}_$screen';
      final last = prefs.getInt(throttleKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final throttled = nowMs - last < _throttleWindow.inMilliseconds;

      // Queue the entry (for flush now or later).
      final queue = _readQueue(prefs);
      queue.add({
        'code': code,
        'screen': screen,
        'detail': detail.length > 64 ? detail.substring(0, 64) : detail,
        'at': nowMs,
      });
      while (queue.length > _maxQueue) {
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
    try {
      if (!CloudAuthService.consentCrash.value) return;
      if (!CloudClient.isReady) return;
      if (CloudClient.db.auth.currentUser == null) return;

      final prefs = await SharedPreferences.getInstance();
      final queue = _readQueue(prefs);
      if (queue.isEmpty) return;

      final deviceCode = DeviceIdService.deviceCode.value ?? '';
      final platform = _platform();
      final version = await _appVersion();

      // Send oldest first, stop at first failure (keep rest queued).
      final remaining = List<Map<String, dynamic>>.from(queue);
      while (remaining.isNotEmpty) {
        final entry = remaining.first;
        try {
          await CloudClient.db.functions.invoke(
            'report-error',
            body: {
              'device_code': deviceCode,
              'platform': platform,
              'app_version': version,
              'screen': entry['screen'],
              'code': entry['code'],
              'detail': entry['detail'],
              'count': 1,
            },
          );
          remaining.removeAt(0);
        } catch (_) {
          break; // edge missing / offline — retry next flush.
        }
      }
      await prefs.setString(_queueKey, jsonEncode(remaining));
    } catch (_) {
      // Fail soft.
    }
  }

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

  static String _platform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
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

  /// Test hook: pure throttle decision (no prefs needed).
  @visibleForTesting
  static bool shouldThrottle(int lastSentMs, int nowMs) {
    return nowMs - lastSentMs < _throttleWindow.inMilliseconds;
  }
}
