import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../device/device_id_service.dart';
import '../errors/app_log.dart';
import 'legal_terms.dart';

/// Records that this person agreed to [LegalTerms], locally and on the server.
///
/// Why both: the local copy is what decides whether to show the gate again
/// (it works offline, and it is the only thing available on first launch); the
/// server row is the evidence, with a timestamp the user cannot edit and the
/// device code that ties it to an install even after a reinstall rotates the
/// anonymous uid.
///
/// The stored version is compared to [LegalTerms.version], so publishing new
/// wording re-opens the gate for everyone without any extra bookkeeping.
class LegalAcceptanceService {
  const LegalAcceptanceService._();

  static const _keyVersion = 'legal_accepted_version_v1';
  static const _keyAt = 'legal_accepted_at_v1';

  /// A version agreed to locally but not yet accepted by the server. Written
  /// on every accept and cleared only by a successful RPC, so agreeing while
  /// offline still counts on this phone and the evidence row lands by itself
  /// on the next launch with a network. Without this, a plane-mode first run
  /// would show "agreed" forever while the server kept no record of it.
  static const _keyPending = 'legal_acceptance_pending_v1';

  /// Version this install has agreed to, or null if never.
  static final ValueNotifier<String?> acceptedVersion =
      ValueNotifier<String?>(null);

  /// When it was agreed. Local time on accept; replaced by the server's
  /// timestamp as soon as one is available, so the date shown is not a guess.
  static final ValueNotifier<DateTime?> acceptedAt =
      ValueNotifier<DateTime?>(null);

  /// True when this install has not agreed to the current text — either never,
  /// or the wording was published after they agreed.
  static bool get needsAcceptance =>
      acceptedVersion.value != LegalTerms.version;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    acceptedVersion.value = prefs.getString(_keyVersion);
    acceptedAt.value = DateTime.tryParse(prefs.getString(_keyAt) ?? '');
    // Fire and forget: a cold start must not wait on the network for this.
    unawaited(refreshFromServer());
  }

  /// Marks the current text as agreed. Safe to call twice — the server keeps
  /// the first timestamp and the local copy just rewrites the same value.
  static Future<void> accept() async {
    final now = DateTime.now().toUtc();
    acceptedVersion.value = LegalTerms.version;
    acceptedAt.value = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyVersion, LegalTerms.version);
      await prefs.setString(_keyAt, now.toIso8601String());
      await prefs.setString(_keyPending, LegalTerms.version);
    } catch (e) {
      AppLog.d('[Legal] local save failed (soft): $e');
    }
    await _push();
  }

  /// Pulls the authoritative timestamp for the current version, if the server
  /// has one. Also covers a reinstall: the local pref is gone but the row
  /// survives on the same uid.
  static Future<void> refreshFromServer() async {
    if (!CloudClient.isReady) return;
    if (CloudClient.db.auth.currentUser == null) return;
    // A previous accept may never have reached the server (offline, cold
    // start, a 5xx). Retry it first — otherwise the local "agreed" and the
    // server's silence never reconcile.
    await _retryPending();
    try {
      final res = await CloudClient.db.rpc('my_legal_acceptance');
      if (res is! Map) return;
      if (res['version']?.toString() != LegalTerms.version) return;
      final at = DateTime.tryParse(res['accepted_at']?.toString() ?? '');
      if (at == null) return;
      acceptedAt.value = at.toLocal();
      // The server knows we agreed — make the local copy agree with it, so an
      // offline launch right after this does not re-prompt.
      if (acceptedVersion.value != LegalTerms.version) {
        acceptedVersion.value = LegalTerms.version;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyVersion, LegalTerms.version);
        await prefs.setString(_keyAt, at.toIso8601String());
      }
    } catch (e) {
      AppLog.d('[Legal] server refresh failed (soft): $e');
    }
  }

  static Future<void> _retryPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString(_keyPending);
      if (pending == null || pending != LegalTerms.version) return;
      await _push();
    } catch (e) {
      AppLog.d('[Legal] pending retry failed (soft): $e');
    }
  }

  static Future<bool> _push() async {
    if (!CloudClient.isReady) return false;
    if (CloudClient.db.auth.currentUser == null) return false;
    try {
      await CloudClient.db.rpc('record_acceptance', params: {
        'p_version': LegalTerms.version,
        'p_terms_version': LegalTerms.termsVersion,
        'p_privacy_version': LegalTerms.privacyVersion,
        'p_device_code': DeviceIdService.deviceCode.value,
        'p_platform': defaultTargetPlatform.name,
        'p_app_version': await _appVersion(),
      });
      // Only a successful RPC clears the pending flag. Anything else keeps it
      // for the next launch — a retry is free, a lost consent record is not.
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_keyPending) == LegalTerms.version) {
          await prefs.remove(_keyPending);
        }
      } catch (e) {
        AppLog.d('[Legal] pending clear failed (soft): $e');
      }
      return true;
    } catch (e) {
      AppLog.d('[Legal] acceptance push failed (soft): $e');
      return false;
    }
  }

  static Future<String?> _appVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      return pkg.version;
    } catch (_) {
      return null;
    }
  }

  /// Formats the agreement date the way Settings shows it ("20 Nov 2026").
  static String describeAcceptedAt(DateTime? at) {
    if (at == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${at.day} ${months[at.month - 1]} ${at.year}';
  }
}
