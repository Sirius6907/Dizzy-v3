import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'cloud_client.dart';
import '../device/device_id_service.dart';
import '../errors/app_log.dart';

/// S2 (v1.1.9): identity + consent. Anonymous-first, Google optional.
/// Everything fails soft — offline means local-only, never an error screen.
class CloudAuthService {
  static const _keyAnonId = 'cloud_anon_id_v1';
  static const _keyTelemetry = 'consent_telemetry_v1';
  static const _keyGenrePrefs = 'consent_genre_prefs_v1';
  static const _keyCrash = 'consent_crash_v1';
  static const _keyWatchParty = 'consent_watch_party_v1';
  static const _keyOnboarded = 'cloud_consent_onboarded_v1';

  static final ValueNotifier<bool> signedIn = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> onboarded = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> consentTelemetry =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> consentGenrePrefs =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> consentCrash = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> consentWatchParty =
      ValueNotifier<bool>(false);

  static String? _anonId;
  static String? get anonId => _anonId;

  /// Owner key for cloud rows: user uuid when logged in, else anon id.
  static String? get ownerKey {
    final u = CloudClient.isReady
        ? CloudClient.db.auth.currentUser?.id
        : null;
    return u ?? _anonId;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    onboarded.value = prefs.getBool(_keyOnboarded) ?? false;
    consentTelemetry.value = prefs.getBool(_keyTelemetry) ?? false;
    consentGenrePrefs.value = prefs.getBool(_keyGenrePrefs) ?? false;
    consentCrash.value = prefs.getBool(_keyCrash) ?? false;
    consentWatchParty.value = prefs.getBool(_keyWatchParty) ?? false;

    _anonId = prefs.getString(_keyAnonId);
    if (_anonId == null) {
      final fresh = const Uuid().v4();
      await prefs.setString(_keyAnonId, fresh);
      _anonId = fresh;
    }
    if (!CloudClient.isReady) return;

    try {
      // Reuse existing session or sign in anonymously.
      final session = CloudClient.db.auth.currentSession;
      if (session == null) {
        await CloudClient.db.auth.signInAnonymously();
      }
      signedIn.value = CloudClient.db.auth.currentUser != null;
      CloudClient.db.auth.onAuthStateChange.listen((data) {
        signedIn.value = data.session?.user != null;
      });
      // Install telemetry is consent-gated. Auth itself remains anonymous
      // and local-first; no installs row until user explicitly opts in.
      if (consentTelemetry.value) await _upsertInstall();
    } catch (e) {
      AppLog.d('[CloudAuth] anon sign-in failed (soft): $e');
    }
  }

  static Future<void> _upsertInstall() async {
    if (!CloudClient.isReady || _anonId == null) return;
    try {
      String platform = 'unknown';
      if (Platform.isAndroid) platform = 'android';
      if (Platform.isWindows) platform = 'windows';
      if (Platform.isLinux) platform = 'linux';
      final uid = CloudClient.db.auth.currentUser?.id;
      if (uid == null) return;
      await CloudClient.db.from('installs').upsert({
        'owner_user_id': uid,
        'anon_id': _anonId!,
        'device_code': DeviceIdService.deviceCode.value,
        'platform': platform,
        'app_version': '1.1.9',
        'last_seen_at': DateTime.now().toIso8601String(),
      }, onConflict: 'owner_user_id');
    } catch (e) {
      AppLog.d('[CloudAuth] install upsert failed (soft): $e');
    }
  }

  static Future<void> signOut() async {
    try {
      if (CloudClient.isReady) await CloudClient.db.auth.signOut();
    } catch (_) {}
    // Keep anon id — local app keeps working, cloud pauses.
    signedIn.value = false;
  }

  static Future<void> setOnboarded() async {
    onboarded.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboarded, true);
  }

  static Future<void> setConsent(
      {bool? telemetry,
      bool? genrePrefs,
      bool? crash,
      bool? watchParty}) async {
    final prefs = await SharedPreferences.getInstance();
    if (telemetry != null) {
      consentTelemetry.value = telemetry;
      await prefs.setBool(_keyTelemetry, telemetry);
    }
    if (genrePrefs != null) {
      consentGenrePrefs.value = genrePrefs;
      await prefs.setBool(_keyGenrePrefs, genrePrefs);
    }
    if (crash != null) {
      consentCrash.value = crash;
      await prefs.setBool(_keyCrash, crash);
    }
    if (watchParty != null) {
      consentWatchParty.value = watchParty;
      await prefs.setBool(_keyWatchParty, watchParty);
    }
    await _pushConsents();
    if (consentTelemetry.value) await _upsertInstall();
  }

  /// Push consent row to cloud (soft-fail). Only when cloud ready.
  static Future<void> _pushConsents() async {
    if (!CloudClient.isReady) return;
    try {
      final uid = CloudClient.db.auth.currentUser?.id;
      if (uid == null) return;
      await CloudClient.db.from('consents').upsert({
        'owner_user_id': uid,
        'telemetry': consentTelemetry.value,
        'genre_prefs': consentGenrePrefs.value,
        'crash': consentCrash.value,
        'watch_party': consentWatchParty.value,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      AppLog.d('[CloudAuth] consent push failed (soft): $e');
    }
  }

  /// GDPR-style: delete all cloud rows for this owner. Local data untouched.
  static Future<bool> deleteCloudData() async {
    if (!CloudClient.isReady) return false;
    try {
      final uid = CloudClient.db.auth.currentUser?.id;
      if (uid == null) return false;
      await CloudClient.db
          .from('genre_prefs')
          .delete()
          .eq('owner_user_id', uid);
      await CloudClient.db
          .from('consents')
          .delete()
          .eq('owner_user_id', uid);
      await CloudClient.db
          .from('installs')
          .delete()
          .eq('owner_user_id', uid);
      if (uid.isNotEmpty) {
        await CloudClient.db
            .from('cloud_backups')
            .delete()
            .eq('user_id', uid);
        await CloudClient.db.from('profiles').delete().eq('user_id', uid);
        // WP-P5: full wipe — party traces too (chat cascade-follows rooms).
        await CloudClient.db
            .from('room_messages')
            .delete()
            .eq('sender_id', uid);
        await CloudClient.db
            .from('room_members')
            .delete()
            .eq('user_id', uid);
        await CloudClient.db
            .from('rooms')
            .delete()
            .eq('host_user_id', uid);
        await CloudClient.db
            .from('cloud_sessions')
            .delete()
            .eq('user_id', uid);
      }
      return true;
    } catch (e) {
      AppLog.d('[CloudAuth] delete failed: $e');
      return false;
    }
  }
}
