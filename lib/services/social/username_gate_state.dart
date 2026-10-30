import 'package:flutter/foundation.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';
import 'dizzy_social_service.dart';

/// v1.3.3 — first-run @username gate.
///
/// The decision is server truth, never a local "first launch" flag: a
/// reinstall wipes prefs, and an Android backup restore keeps them, so a
/// local flag lies in both directions. One row in `usernames` for
/// `auth.uid()` is the only honest signal that this person already has a
/// name.
enum UsernameGate { undecided, needed, notNeeded }

enum UsernameProblem { empty, tooShort, tooLong, badChars }

/// A name from the previous owner of this physical device. Shown as
/// "Welcome back, @name?" so a reinstall never re-asks and never leaves a
/// ghost claim on a dead anonymous uid.
class ReturningUser {
  const ReturningUser({required this.userId, required this.username});

  final String userId;
  final String username;
}

abstract final class UsernameGatePolicy {
  static const int minLength = 3;
  static const int maxLength = 20;

  /// Mirrors the server regex in `claim_username`; the server stays the
  /// authority for reserved words and uniqueness.
  static final RegExp _allowed = RegExp(r'^[a-z0-9_]+$');

  static UsernameGate decide({
    required bool cloudReady,
    required bool? hasUsername,
  }) {
    if (!cloudReady || hasUsername == null) return UsernameGate.undecided;
    return hasUsername ? UsernameGate.notNeeded : UsernameGate.needed;
  }

  static ReturningUser? returningUser({
    required String? currentUid,
    required String? previousUid,
    required String? previousUsername,
  }) {
    final name = (previousUsername ?? '').trim();
    if (currentUid == null || currentUid.isEmpty) return null;
    if (previousUid == null || previousUid.isEmpty) return null;
    if (previousUid == currentUid) return null;
    if (name.isEmpty) return null;
    return ReturningUser(userId: previousUid, username: name);
  }

  static String normalize(String raw) => raw.trim().toLowerCase();

  static UsernameProblem? localProblem(String raw) {
    final v = normalize(raw);
    if (v.isEmpty) return UsernameProblem.empty;
    if (v.length < minLength) return UsernameProblem.tooShort;
    if (v.length > maxLength) return UsernameProblem.tooLong;
    if (!_allowed.hasMatch(v)) return UsernameProblem.badChars;
    return null;
  }

  /// After two real failures the gate offers "Later"; the app is a media
  /// player and must never be bricked by a name prompt on a bad network.
  static bool canDefer(int failedAttempts) => failedAttempts >= 2;
}

/// Boot-time state holder. Everything fails soft: an unreachable server
/// leaves the gate undecided, which shows nothing.
class UsernameGateState {
  UsernameGateState._();

  static final ValueNotifier<UsernameGate> phase = ValueNotifier(
    UsernameGate.undecided,
  );
  static final ValueNotifier<ReturningUser?> returning = ValueNotifier(null);

  static bool _deferredThisSession = false;

  static bool get deferredThisSession => _deferredThisSession;
  static void deferThisSession() => _deferredThisSession = true;

  /// No keys configured (e.g. a dev desktop build without .env) — the gate
  /// has nothing to ask and must not add a wait to every boot.
  static bool get possible => CloudClient.isConfigured;

  /// Reads `usernames` for the current session. RLS only lets a user see
  /// their own row, so this doubles as the presence check.
  static Future<UsernameGate> resolve() async {
    if (!CloudClient.isReady) {
      phase.value = UsernameGate.undecided;
      return phase.value;
    }
    bool? has;
    try {
      final uid = CloudClient.db.auth.currentUser?.id;
      if (uid == null) {
        phase.value = UsernameGate.undecided;
        return phase.value;
      }
      final row = await CloudClient.db
          .from('usernames')
          .select('username')
          .eq('user_id', uid)
          .maybeSingle();
      has = row != null;
    } catch (e) {
      AppLog.d('[UsernameGate] resolve failed (soft): $e');
    }
    phase.value = UsernameGatePolicy.decide(
      cloudReady: CloudClient.isReady,
      hasUsername: has,
    );
    return phase.value;
  }

  /// Single-flight [resolve]: startup fires this from two places and a slow
  /// boot must not stack duplicate queries against the `usernames` row.
  static Future<UsernameGate>? _inflight;

  static Future<UsernameGate> ensureResolved() {
    final running = _inflight;
    if (running != null) return running;
    final next = resolve().whenComplete(() => _inflight = null);
    _inflight = next;
    return next;
  }

  /// Adopts the previous owner of this device: the server decides the
  /// candidate (device_boot), the audited merge_devices RPC does the move.
  static Future<bool> adopt(ReturningUser candidate) async {
    try {
      final uid = CloudClient.db.auth.currentUser?.id;
      if (uid == null) return false;
      final res = await CloudClient.db.rpc('merge_devices', params: {
        'p_old_anon_uid': candidate.userId,
        'p_canonical_uid': uid,
      });
      if (res is! Map || res['success'] != true) return false;
      returning.value = null;
      await DizzySocialService.loadCurrentUsername();
      await resolve();
      return phase.value == UsernameGate.notNeeded;
    } catch (e) {
      AppLog.d('[UsernameGate] adopt failed (soft): $e');
      return false;
    }
  }

  /// Claims through the existing service; on success the gate is done.
  static Future<Map<String, dynamic>> claim(String raw) async {
    final res = await DizzySocialService.claimUsername(
      UsernameGatePolicy.normalize(raw),
    );
    if (res['success'] == true) {
      phase.value = UsernameGate.notNeeded;
      returning.value = null;
    }
    return res;
  }

  /// Live availability check. `null` means "could not ask" — the UI then
  /// lets the claim call decide.
  static Future<bool?> isAvailable(String raw) async {
    if (!CloudClient.isReady) return null;
    try {
      final res = await CloudClient.db.rpc('username_available', params: {
        'p_username': UsernameGatePolicy.normalize(raw),
      });
      if (res is Map && res['available'] is bool) {
        return res['available'] as bool;
      }
      return null;
    } catch (e) {
      AppLog.d('[UsernameGate] availability failed (soft): $e');
      return null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    phase.value = UsernameGate.undecided;
    returning.value = null;
    _deferredThisSession = false;
  }
}
