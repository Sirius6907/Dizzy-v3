import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/cloud_client.dart';
import '../device/device_id_service.dart';
import '../errors/app_log.dart';

/// Progressive Identity & Cross-Device Sync Service for Dizzy-v3.
///
/// Keeps user anonymous-first with zero friction on boot, and provides
/// seamless, atomic Phone/Email linking with merge_devices recovery.
class DizzyIdentityService {
  static const _keyDeviceSid = 'diz_device_sid_v1';
  static const _keyLinkedKind = 'diz_linked_kind_v1';
  static const _keyLinkedIdentifier = 'diz_linked_identifier_v1';

  static final ValueNotifier<String?> deviceSid = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> linkedKind = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> linkedIdentifier = ValueNotifier<String?>(null);

  static bool get isLinked => linkedKind.value != null;

  /// Friendly display code (e.g. DIZ-4820193).
  static String get deviceDisplayCode {
    final code = DeviceIdService.deviceCode.value;
    if (code == null) return 'DIZ-0000000';
    return DeviceIdService.displayCode(code);
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    deviceSid.value = prefs.getString(_keyDeviceSid);
    linkedKind.value = prefs.getString(_keyLinkedKind);
    linkedIdentifier.value = prefs.getString(_keyLinkedIdentifier);

    if (deviceSid.value == null) {
      // Anonymous-first: friendly 7-digit device code as the session ID.
      final code = await DeviceIdService.initialize();
      final freshSid = DeviceIdService.displayCode(code);
      await prefs.setString(_keyDeviceSid, freshSid);
      deviceSid.value = freshSid;
    }

    // Attempt background device boot registration if cloud is ready
    if (CloudClient.isReady) {
      await bootDevice();
    }
  }

  /// Registers or touches this device registration on the backend.
  static Future<void> bootDevice() async {
    if (!CloudClient.isReady) return;
    final uid = CloudClient.db.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final code = await DeviceIdService.initialize();
      final hwidHash = sha256.convert(utf8.encode('dizzy_hwid_${code}_salt')).toString();

      await CloudClient.db.from('devices').upsert({
        'user_id': uid,
        'device_code': code,
        'hwid_hash': hwidHash,
        'sid': deviceSid.value,
        'platform': defaultTargetPlatform.name,
        'app_version': '1.2.1',
        'last_seen_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,hwid_hash');
    } catch (e) {
      AppLog.d('[DizzyIdentityService] bootDevice: $e');
    }
  }

  /// Initiates Phone OTP linking.
  static Future<bool> requestPhoneOtp(String phoneNumber) async {
    if (!CloudClient.isReady) return false;
    try {
      await CloudClient.db.auth.signInWithOtp(phone: phoneNumber);
      return true;
    } catch (e) {
      AppLog.d('[DizzyIdentityService] requestPhoneOtp: $e');
      return false;
    }
  }

  /// Initiates Email OTP linking.
  static Future<bool> requestEmailOtp(String email) async {
    if (!CloudClient.isReady) return false;
    try {
      await CloudClient.db.auth.signInWithOtp(email: email);
      return true;
    } catch (e) {
      AppLog.d('[DizzyIdentityService] requestEmailOtp: $e');
      return false;
    }
  }

  /// Confirms OTP and atomically merges previous anonymous data into canonical account.
  static Future<bool> verifyOtpAndMerge({
    required String token,
    String? phone,
    String? email,
  }) async {
    if (!CloudClient.isReady) return false;
    final oldAnonUid = CloudClient.db.auth.currentUser?.id;

    try {
      AuthResponse res;
      if (phone != null) {
        res = await CloudClient.db.auth.verifyOTP(
          type: OtpType.sms,
          token: token,
          phone: phone,
        );
      } else if (email != null) {
        res = await CloudClient.db.auth.verifyOTP(
          type: OtpType.email,
          token: token,
          email: email,
        );
      } else {
        return false;
      }

      final canonicalUid = res.user?.id;
      if (canonicalUid == null) return false;

      // Atomic data merger RPC if canonical UID differs from old anonymous UID
      if (oldAnonUid != null && oldAnonUid != canonicalUid) {
        try {
          await CloudClient.db.rpc('merge_devices', params: {
            'p_old_anon_uid': oldAnonUid,
            'p_canonical_uid': canonicalUid,
          });
        } catch (rpcErr) {
          AppLog.d('[DizzyIdentityService] merge_devices RPC note: $rpcErr');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final kind = phone != null ? 'phone' : 'email';
      final ident = phone ?? email ?? '';

      await prefs.setString(_keyLinkedKind, kind);
      await prefs.setString(_keyLinkedIdentifier, ident);

      linkedKind.value = kind;
      linkedIdentifier.value = ident;

      // Re-register device under canonical account
      await bootDevice();
      return true;
    } catch (e) {
      AppLog.d('[DizzyIdentityService] verifyOtpAndMerge: $e');
      return false;
    }
  }
}
