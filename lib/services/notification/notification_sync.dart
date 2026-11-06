import 'package:flutter/foundation.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';
import 'notification_prefs.dart';

/// Mirrors the local notification gate to `notification_settings` so the
/// server-side push brain honours the same switches while the app is asleep.
///
/// Fail-soft by design: a failed sync only means the brain falls back to its
/// defaults (everything on, quiet hours off). It must never block a toggle.
class NotificationSync {
  NotificationSync._();

  static Future<bool> Function(Map<String, dynamic> params)? _sender;
  static Future<bool> Function(String tone)? _toneSender;

  /// RPC argument names and value clamping live here so the server can stay
  /// strict (checks + range constraints) without rejecting a client bug.
  static Map<String, dynamic> paramsFor(
    NotificationGate gate, {
    required int tzOffsetMinutes,
  }) {
    return {
      'p_off': gate.off.toList(),
      'p_quiet_enabled': gate.quietEnabled,
      'p_quiet_start': gate.quietStartMinute.clamp(0, 1439),
      'p_quiet_end': gate.quietEndMinute.clamp(0, 1439),
      'p_tz_offset': tzOffsetMinutes.clamp(-840, 840),
    };
  }

  static Future<bool> push({
    required NotificationGate gate,
    int? tzOffsetMinutes,
  }) async {
    final params = paramsFor(
      gate,
      tzOffsetMinutes: tzOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes,
    );
    try {
      final sender = _sender ?? _rpc;
      return await sender(params);
    } catch (e) {
      AppLog.d('[NotifySync] push failed (soft): $e');
      return false;
    }
  }

  /// Message style is its own RPC so the existing sync signature (and its
  /// deployed callers) never has to change.
  static Future<void> pushTone(NotificationTone tone) async {
    try {
      final sender = _toneSender ?? _rpcTone;
      await sender(tone.wire);
    } catch (e) {
      AppLog.d('[NotifySync] tone push failed (soft): $e');
    }
  }

  static Future<bool> _rpcTone(String tone) async {
    if (!CloudClient.isReady) return false;
    final res = await CloudClient.db.rpc(
      'set_notification_tone',
      params: {'p_tone': tone},
    );
    return res is Map && res['success'] == true;
  }

  static Future<bool> _rpc(Map<String, dynamic> params) async {
    if (!CloudClient.isReady) return false;
    final res = await CloudClient.db.rpc(
      'sync_notification_settings',
      params: params,
    );
    return res is Map && res['success'] == true;
  }

  @visibleForTesting
  static void configureForTest(
    Future<bool> Function(Map<String, dynamic> params) sender,
  ) {
    _sender = sender;
  }

  @visibleForTesting
  static void configureToneForTest(Future<bool> Function(String tone) sender) {
    _toneSender = sender;
  }

  @visibleForTesting
  static void resetForTest() {
    _sender = null;
    _toneSender = null;
  }
}
