import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../profiles/dizzy_profile_service.dart';
import '../social/dizzy_identity_service.dart';

/// 18+ Heaven gate — triple lock (ALL three must pass):
///   1. Local 18+ confirm (Privacy page switch, never for kids profiles).
///   2. Admin allow for THIS device (devices.adult_allowed via device_boot).
///   3. Not a kids profile (hard exclude, same posture as Watch Party).
///
/// Fail-closed: offline / boot fault / unknown = hidden. Last-known admin
/// value is cached so a block survives offline; a fresh allow needs at
/// least one confirmed online boot.
class AdultSectionGate {
  AdultSectionGate._();

  static const String _keyLocalConfirm = 'adult_heaven_local_18_v1';
  static const String _keyAdminAllowed = 'adult_heaven_admin_allowed_v1';

  /// Local "I am 18+" confirm. Boots false, never auto-loads true.
  static final ValueNotifier<bool> localConfirmed = ValueNotifier<bool>(false);

  /// Last-known server allow for this device (cached, fail-closed).
  static final ValueNotifier<bool> adminAllowed = ValueNotifier<bool>(false);

  /// Effective visibility: all three locks ANDed.
  static final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      localConfirmed.value = prefs.getBool(_keyLocalConfirm) ?? false;
      adminAllowed.value = prefs.getBool(_keyAdminAllowed) ?? false;
    } catch (_) {
      // Unreadable prefs → stay hidden (fail-closed).
      localConfirmed.value = false;
      adminAllowed.value = false;
    }
    _loaded = true;
    recompute();
  }

  /// True when the active profile is a kids profile (zero 18+ everywhere).
  /// Mirrors WatchPartyService.isKidsProfile.
  static bool get isKidsProfile =>
      DizzyProfileService.active?.isKids ?? false;

  /// Explicit "I am 18+" confirm from the Privacy page. Kids: no-op.
  static Future<void> setLocalConfirmed(bool value) async {
    if (value && isKidsProfile) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLocalConfirm, value);
    } catch (_) {}
    localConfirmed.value = value;
    recompute();
  }

  /// Called from device boot with the server answer. Persists last-known.
  static Future<void> applyServerAllow(bool allowed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAdminAllowed, allowed);
    } catch (_) {}
    adminAllowed.value = allowed;
    recompute();
  }

  /// One-shot refresh: re-run device boot for the current flag (boot
  /// already does this; this is the Privacy page "check again" path).
  static Future<void> refreshFromServer() async {
    if (!CloudClient.isReady) return;
    try {
      await DizzyIdentityService.bootDevice();
      // bootDevice parses adult_allowed from the same response into
      // applyServerAllow (wired below in DizzyIdentityService).
    } catch (_) {
      // Offline → keep last-known (fail-closed stays as-is).
    }
  }

  /// Re-evaluate visibility. Called after profile switches too.
  static void recompute() {
    visible.value =
        localConfirmed.value && adminAllowed.value && !isKidsProfile;
  }

  /// Pure gate for unit tests: local AND admin AND NOT kids.
  @visibleForTesting
  static bool computeVisible({
    required bool local,
    required bool admin,
    required bool kids,
  }) =>
      local && admin && !kids;
}
