import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';

/// v1.3.3-T1.3: missed-call phone verify (stub-first, gateway key later).
///
/// Flow: number → request_phone_link RPC (pending row + gateway number) →
/// user gives a missed call → provider webhook → confirm_phone_link (Edge,
/// service-role) → app polls request_phone_link until status=verified.
///
/// Until the gateway key exists, the number is saved as UNVERIFIED and the
/// UI badges it clearly — never a silent fail. On key day: admin sets the
/// `missedcall_gateway_number` remote-config value, deploys the
/// `missedcall-webhook` Edge fn, and this same client starts verifying
/// with zero app update.
class PhoneLinkService {
  static const _keyPhone = 'diz_phone_number_v1';
  static const _keyPhoneVerified = 'diz_phone_verified_v1';

  static final ValueNotifier<String?> phoneNumber = ValueNotifier<String?>(null);
  static final ValueNotifier<bool> phoneVerified = ValueNotifier<bool>(false);

  /// Which verification rails exist in THIS build. Missed-call ships in
  /// v1.3.3; the old Supabase-SMS path stays as an explicit fallback flag
  /// (off by default — costly + sender-ID friction).
  static const bool missedCallSupported = true;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      phoneNumber.value = prefs.getString(_keyPhone);
      phoneVerified.value = prefs.getBool(_keyPhoneVerified) ?? false;
    } catch (_) {}
  }

  /// Normalize to E.164-ish (+country + digits). Returns null when invalid.
  static String? normalize(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(clean)) return clean;
    // Bare 10-digit Indian number → assume +91 (Easy-English market).
    if (RegExp(r'^[6-9][0-9]{9}$').hasMatch(clean)) return '+91$clean';
    return null;
  }

  /// Save number locally (unverified badge) + open a pending server row.
  /// Returns the gateway number to missed-call, or '' when the gateway
  /// isn't configured yet (stub mode — number still saved).
  static Future<Map<String, dynamic>> requestLink(String rawNumber) async {
    final number = normalize(rawNumber);
    if (number == null) {
      return {'success': false, 'error': 'Enter a valid number, e.g. +91…'};
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPhone, number);
      await prefs.setBool(_keyPhoneVerified, false);
      phoneNumber.value = number;
      phoneVerified.value = false;
    } catch (_) {}
    if (!CloudClient.isReady) {
      // Offline: number kept locally, verify later. Never a dead end.
      return {'success': true, 'status': 'pending', 'gateway_number': ''};
    }
    try {
      final res = await CloudClient.db
          .rpc('request_phone_link', params: {'p_phone': number});
      if (res is Map && res['success'] == true) {
        if (res['status'] == 'verified') {
          await _markVerified(number);
        }
        return {
          'success': true,
          'status': res['status'] ?? 'pending',
          'gateway_number': res['gateway_number']?.toString() ?? '',
          'cooldown': res['cooldown'] == true,
        };
      }
      return {
        'success': false,
        'error': (res is Map ? res['error'] : null)?.toString() ??
            'Could not start verification right now'
      };
    } catch (e) {
      AppLog.d('[PhoneLink] request: $e');
      return {'success': true, 'status': 'pending', 'gateway_number': ''};
    }
  }

  /// Poll until verified (6 tries × 10s). Called after the missed call.
  static Future<bool> pollVerified({int tries = 6}) async {
    final number = phoneNumber.value;
    if (number == null || !CloudClient.isReady) return false;
    for (var i = 0; i < tries; i++) {
      try {
        final res = await CloudClient.db
            .rpc('request_phone_link', params: {'p_phone': number});
        if (res is Map && res['status'] == 'verified') {
          await _markVerified(number);
          return true;
        }
      } catch (e) {
        AppLog.d('[PhoneLink] poll: $e');
      }
      await Future.delayed(const Duration(seconds: 10));
    }
    return false;
  }

  static Future<void> _markVerified(String number) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPhone, number);
      await prefs.setBool(_keyPhoneVerified, true);
    } catch (_) {}
    phoneNumber.value = number;
    phoneVerified.value = true;
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyPhone);
      await prefs.remove(_keyPhoneVerified);
    } catch (_) {}
    phoneNumber.value = null;
    phoneVerified.value = false;
  }
}
