import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/cloud_client.dart';
import '../device/device_identity_v2.dart';
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

  /// Phase H/C: true when the server says THIS device was revoked.
  /// Fail-soft: only flipped by a confirmed device_boot response.
  static final ValueNotifier<bool> deviceRevoked = ValueNotifier<bool>(false);

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
      // Phase H: stable identity v2 — hwid_hash = salted ANDROID_ID (survives
      // reinstall); hwid_legacy = old random-code hash (dedupe helper for
      // pre-H rows); hwid_stable tells the server when the anchor is weak.
      // Server-side device_boot does the upsert + reinstall auto-merge and
      // returns whether THIS device was revoked (Phase C notice screen).
      final identity = await DeviceIdentityV2.stableHwid();
      final legacyHash =
          sha256.convert(utf8.encode('dizzy_hwid_${code}_salt')).toString();

      final res = await CloudClient.db.rpc('device_boot', params: {
        'p_hwid_hash': identity.hash,
        'p_hwid_legacy': legacyHash,
        'p_hwid_stable': identity.stable,
        'p_device_code': code,
        'p_sid': deviceSid.value ?? '',
        'p_platform': defaultTargetPlatform.name,
        'p_app_version': await _appVersion(),
      });
      if (res is Map && res['revoked'] == true) {
        deviceRevoked.value = true;
      } else if (res is Map && res['success'] == true) {
        deviceRevoked.value = false;
      }
    } catch (e) {
      AppLog.d('[DizzyIdentityService] bootDevice: $e');
    }
  }

  /// Real app version from the installed package (never a hardcoded guess).
  static Future<String> _appVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      return pkg.version;
    } catch (_) {
      return 'unknown';
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
