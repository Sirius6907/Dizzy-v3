import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../profiles/dizzy_profile_service.dart';
import '../social/dizzy_identity_service.dart';

/// Outcome of the birth-year age gate.
enum AgeGateResult {
  /// Year confirmed 18+ and stored on this device.
  granted,

  /// Year says the user is younger than [AdultSectionGate.minAge].
  underage,

  /// Not a plausible year at all (future, year zero, 1800s...).
  invalidYear,

  /// Too many underage attempts — gate is closed for a cooling-off period.
  lockedOut,

  /// Kids profile: the gate cannot be opened at all, for anyone.
  kidsProfile,
}

/// 18+ Heaven gate — triple lock (ALL three must pass):
///   1. Hard local age gate: birth-year confirm, 18+, remembered per device.
///   2. Admin allow for THIS device (devices.adult_allowed via device_boot).
///   3. Not a kids profile (hard exclude, same posture as Watch Party).
///
/// Fail-closed: offline / boot fault / unknown = hidden. Last-known admin
/// value is cached so a block survives offline; a fresh allow needs at
/// least one confirmed online boot.
///
/// The age gate is deliberately *hard*: there is no "unlock" boolean a user
/// can flip. [localConfirmed] only becomes true through
/// [submitBirthYear] with a year that makes the user at least
/// [minAge] years old, and repeated underage attempts trigger a
/// persisted cooling-off window ([maxAttempts] → [lockDuration]).
class AdultSectionGate {
  AdultSectionGate._();

  static const String _keyLocalConfirm = 'adult_heaven_local_18_v1';
  static const String _keyAdminAllowed = 'adult_heaven_admin_allowed_v1';
  static const String _keyBirthYear = 'adult_heaven_birth_year_v1';
  static const String _keyPrivateMode = 'adult_heaven_private_mode_v1';
  static const String _keyFailures = 'adult_heaven_gate_failures_v1';
  static const String _keyLockedUntil = 'adult_heaven_gate_locked_until_v1';

  /// Minimum age, in years.
  static const int minAge = 18;

  /// Upper bound for a believable birth year.
  static const int maxAge = 120;

  /// Underage attempts tolerated before the gate cools off.
  static const int maxAttempts = 5;

  /// Cooling-off window once [maxAttempts] is reached.
  static const Duration lockDuration = Duration(hours: 24);

  /// Local "I am 18+ and here is my birth year" confirm.
  /// Boots false, never auto-loads true.
  static final ValueNotifier<bool> localConfirmed = ValueNotifier<bool>(false);

  /// Last-known server allow for this device (cached, fail-closed).
  static final ValueNotifier<bool> adminAllowed = ValueNotifier<bool>(false);

  /// Effective visibility: all three locks ANDed.
  static final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  /// Private mode (default ON): disguise the Settings entry and shield the
  /// 18+ surface from screenshots / the Android recents preview.
  static final ValueNotifier<bool> privateMode = ValueNotifier<bool>(true);

  /// The confirmed birth year, or null when the gate never passed.
  static final ValueNotifier<int?> birthYear = ValueNotifier<int?>(null);

  /// Remaining underage attempts before the cooling-off kicks in.
  static final ValueNotifier<int> attemptsLeft = ValueNotifier<int>(
    maxAttempts,
  );

  /// Wall-clock ms until which the gate refuses input (0 = open).
  static final ValueNotifier<int> lockedUntilMs = ValueNotifier<int>(0);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      localConfirmed.value = prefs.getBool(_keyLocalConfirm) ?? false;
      adminAllowed.value = prefs.getBool(_keyAdminAllowed) ?? false;
      birthYear.value = prefs.getInt(_keyBirthYear);
      privateMode.value = prefs.getBool(_keyPrivateMode) ?? true;
      final until = prefs.getInt(_keyLockedUntil) ?? 0;
      if (until != 0 &&
          until <= DateTime.now().millisecondsSinceEpoch) {
        // Cooling-off finished while the app was closed — fresh attempts.
        await _resetFailures();
      } else {
        final fails = prefs.getInt(_keyFailures) ?? 0;
        attemptsLeft.value = (maxAttempts - fails).clamp(0, maxAttempts);
        lockedUntilMs.value = until;
      }
    } catch (_) {
      // Unreadable prefs → stay hidden (fail-closed).
      localConfirmed.value = false;
      adminAllowed.value = false;
      birthYear.value = null;
      privateMode.value = true;
      attemptsLeft.value = maxAttempts;
      lockedUntilMs.value = 0;
    }
    _loaded = true;
    recompute();
  }

  /// True when the active profile is a kids profile (zero 18+ everywhere).
  /// Mirrors WatchPartyService.isKidsProfile.
  static bool get isKidsProfile =>
      DizzyProfileService.active?.isKids ?? false;

  // ── Pure age maths (testable, no I/O) ────────────────────────────────

  /// True when [year] is a plausible birth year that makes the holder at
  /// least [minAge] old in [nowYear].
  static bool isAdultYear(int year, {int? nowYear}) {
    final now = nowYear ?? DateTime.now().year;
    if (year < now - maxAge || year > now) return false;
    return now - year >= minAge;
  }

  /// True when [year] is structurally possible (not future, not absurd).
  static bool isPlausibleYear(int year, {int? nowYear}) {
    final now = nowYear ?? DateTime.now().year;
    return year >= now - maxAge && year <= now;
  }

  /// Pure decision used by the dialog and the tests.
  static AgeGateResult evaluateYears(
    int year, {
    int? nowYear,
    bool kids = false,
  }) {
    if (kids) return AgeGateResult.kidsProfile;
    if (!isPlausibleYear(year, nowYear: nowYear)) {
      return AgeGateResult.invalidYear;
    }
    return isAdultYear(year, nowYear: nowYear)
        ? AgeGateResult.granted
        : AgeGateResult.underage;
  }

  // ── Gate interaction ─────────────────────────────────────────────────

  static bool isLockedOut({int? nowMs}) =>
      (nowMs ?? DateTime.now().millisecondsSinceEpoch) < lockedUntilMs.value;

  static Duration lockRemaining({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final left = lockedUntilMs.value - now;
    return left <= 0 ? Duration.zero : Duration(milliseconds: left);
  }

  /// The one way to open the local lock: submit a birth year.
  ///
  /// On success the year is remembered for this device and
  /// [localConfirmed] flips true (subject to the other two locks).
  /// Underage attempts are counted and, after [maxAttempts], the gate
  /// refuses everything for [lockDuration].
  static Future<AgeGateResult> submitBirthYear(
    int year, {
    int? nowMs,
    int? nowYear,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (isKidsProfile) return AgeGateResult.kidsProfile;
    if (isLockedOut(nowMs: now)) return AgeGateResult.lockedOut;
    if (lockedUntilMs.value != 0) {
      // Cooling-off elapsed — hand back a full set of attempts.
      await _resetFailures();
    }

    final verdict = evaluateYears(
      year,
      nowYear: nowYear,
      kids: isKidsProfile,
    );

    if (verdict == AgeGateResult.granted) {
      await _resetFailures();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_keyBirthYear, year);
        await prefs.setBool(_keyLocalConfirm, true);
      } catch (_) {}
      birthYear.value = year;
      localConfirmed.value = true;
      recompute();
      return AgeGateResult.granted;
    }

    if (verdict == AgeGateResult.underage) {
      final remaining = await _recordFailure(nowMs: now);
      if (remaining <= 0) return AgeGateResult.lockedOut;
      return AgeGateResult.underage;
    }

    return verdict;
  }

  static Future<int> _recordFailure({required int nowMs}) async {
    final used = maxAttempts - attemptsLeft.value + 1;
    final left = (maxAttempts - used).clamp(0, maxAttempts);
    attemptsLeft.value = left;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyFailures, used);
      if (left <= 0) {
        final until = nowMs + lockDuration.inMilliseconds;
        await prefs.setInt(_keyLockedUntil, until);
        lockedUntilMs.value = until;
      }
    } catch (_) {}
    return left;
  }

  static Future<void> _resetFailures() async {
    attemptsLeft.value = maxAttempts;
    lockedUntilMs.value = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFailures);
      await prefs.remove(_keyLockedUntil);
    } catch (_) {}
  }

  /// Lock the section down again (Privacy page toggle OFF).
  ///
  /// Passing `true` is a no-op on purpose: the only unlock path is
  /// [submitBirthYear]. Callers that want to unlock must collect a birth
  /// year, which is why this stays narrow.
  static Future<void> setLocalConfirmed(bool value) async {
    if (value) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLocalConfirm, false);
      await prefs.remove(_keyBirthYear);
    } catch (_) {}
    localConfirmed.value = false;
    birthYear.value = null;
    await _resetFailures();
    recompute();
  }

  /// Private mode: disguise the entry point + shield screenshots/recents.
  static Future<void> setPrivateMode(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPrivateMode, value);
    } catch (_) {}
    privateMode.value = value;
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

  /// Test-only reset so persistence cases don't bleed into each other.
  @visibleForTesting
  static void debugReset() {
    _loaded = false;
    localConfirmed.value = false;
    adminAllowed.value = false;
    visible.value = false;
    privateMode.value = true;
    birthYear.value = null;
    attemptsLeft.value = maxAttempts;
    lockedUntilMs.value = 0;
  }
}
