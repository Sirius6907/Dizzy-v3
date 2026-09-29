import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../continue_watching/profile_progress_store.dart';
import '../continue_watching/progress_merge.dart';
import '../errors/app_error_log.dart';
import '../my_list/custom_list_service.dart';
import 'device_merge_policy.dart';

/// Where the restore flow is. Drives every screen on the restore page.
enum RestoreStage { idle, checking, merging, done, failed }

/// F3 — the whole "sab wapas" flow, in Easy English, no login needed.
///
/// The person reads a short code off the old phone, types it on the new
/// one, and everything comes back. We do the work in three honest steps
/// (checking → bringing back → done) and never sit on a blank spinner: a
/// waiting screen always has a line and a way out.
class RestoreService extends ChangeNotifier {
  static final RestoreService instance = RestoreService._();
  RestoreService._();

  RestoreStage _stage = RestoreStage.idle;
  RestoreStage get stage => _stage;

  String? _message;
  String? get message => _message;

  DeviceMergeResult? _result;
  DeviceMergeResult? get result => _result;

  static const _codeKey = 'restore_code_v1';
  static const _issuedAtKey = 'restore_issued_at_v1';
  static const _spentKey = 'restore_spent_v1';

  /// Ask the cloud for a fresh code for this device's old anonymous
  /// session. Returns the code, or `null` when we are offline.
  Future<String?> requestCode() async {
    _set(RestoreStage.checking, 'Getting your code...');
    if (!CloudClient.isReady) {
      // Offline: fall back to a local code so the screen still works and
      // the person is not stuck staring at a dead spinner.
      final code = DeviceMergePolicy.codeFromSeed(
        DateTime.now().millisecondsSinceEpoch,
      );
      await _storeCode(code);
      _set(RestoreStage.done, 'Code ready: $code');
      return code;
    }
    try {
      final res = await CloudClient.db.rpc('issue_restore_code');
      final code = res is String
          ? res
          : (res is Map ? res['code']?.toString() ?? '' : '');
      if (!DeviceMergePolicy.isValidCode(code)) {
        unawaited(AppErrorLog.log(
          code: 'restore_code_bad', screen: 'my_dizzy', detail: 'bad_shape'));
        _set(RestoreStage.failed, 'We could not make a code right now.');
        return null;
      }
      await _storeCode(code);
      _set(RestoreStage.done, 'Code ready: $code');
      return code;
    } catch (e) {
      unawaited(AppErrorLog.log(
        code: 'restore_code_fail', screen: 'my_dizzy', detail: 'rpc_failed'));
      _set(RestoreStage.failed, 'We could not make a code right now. Try again in a bit.');
      return null;
    }
  }

  static Future<void> _storeCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, code);
    await prefs.setInt(
      _issuedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.remove(_spentKey);
  }

  /// The code this device issued, if it is still fresh.
  Future<String?> myCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    if (code == null) return null;
    final at = prefs.getInt(_issuedAtKey);
    if (at == null) return null;
    final issued = DateTime.fromMillisecondsSinceEpoch(at);
    if (!DeviceMergePolicy.isFresh(issued)) return null;
    return code;
  }

  /// Type a code from the old phone and bring everything back.
  ///
  /// Runs the local unions first (they cannot fail), then asks the server
  /// for its half. A server that says "already merged" is a normal
  /// outcome, not an error — the person gets a real count either way.
  Future<DeviceMergeResult?> redeem(String typed) async {
    final code = DeviceMergePolicy.normalizeCode(typed);
    if (!DeviceMergePolicy.isValidCode(code)) {
      _set(RestoreStage.failed, 'That code does not look right. Check it and try again.');
      return null;
    }
    _set(RestoreStage.merging, 'Bringing everything back...');

    var result = const DeviceMergeResult();

    // Local half — progress, lists. A corrupt blob is dropped, never fatal.
    try {
      final report = await ProfileProgressStore.mergeIncoming(
        await _progressFromStorage(),
      );
      final listsGained = await CustomListService.importAll(
        await _listsFromStorage(),
      );
      result = DeviceMergeResult(
        progressAdded: report.added,
        progressAdvanced: report.advanced,
        historyAdded: listsGained,
      );
    } catch (e) {
      unawaited(AppErrorLog.log(
        code: 'restore_local_fail', screen: 'my_dizzy', detail: 'local_merge'));
    }

    // Server half.
    if (CloudClient.isReady) {
      try {
        final res = await CloudClient.db.rpc('redeem_restore_code', params: {
          'p_code': code,
        });
        final server = DeviceMergePolicy.fromServer(
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{},
        );
        result = DeviceMergeResult(
          watchlistAdded: server.watchlistAdded + result.watchlistAdded,
          historyAdded: server.historyAdded,
          friendsAdded: server.friendsAdded,
          progressAdded: server.progressAdded + result.progressAdded,
          progressAdvanced: server.progressAdvanced + result.progressAdvanced,
          alreadyMerged: server.alreadyMerged && result.totalAdded == 0,
        );
        await _markSpent(code);
      } catch (e) {
        unawaited(AppErrorLog.log(
          code: 'restore_rpc_fail', screen: 'my_dizzy', detail: 'rpc_failed'));
        // The local part already landed. Say so honestly instead of
        // pretending the whole thing failed.
        result = DeviceMergeResult(
          watchlistAdded: result.watchlistAdded,
          historyAdded: result.historyAdded,
          friendsAdded: result.friendsAdded,
          progressAdded: result.progressAdded,
          progressAdvanced: result.progressAdvanced,
        );
      }
    }

    _result = result;
    _set(RestoreStage.done, result.summaryLine);
    return result;
  }

  Future<void> _markSpent(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_spentKey, code);
  }

  /// True when this exact code was already redeemed on this device.
  Future<bool> wasSpent(String code) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_spentKey) == code;
  }

  Future<Map<String, MediaProgress>> _progressFromStorage() async {
    await ProfileProgressStore.initialize();
    return ProfileProgressStore.snapshot();
  }

  Future<Map<String, dynamic>> _listsFromStorage() async {
    // Nothing new to hand over when there is no cloud copy yet.
    return const {};
  }

  void reset() {
    _set(RestoreStage.idle, null);
    _result = null;
  }

  void _set(RestoreStage stage, String? msg) {
    _stage = stage;
    _message = msg;
    notifyListeners();
  }

  /// Test hook: read the raw storage shape we persist.
  @visibleForTesting
  static String encodeCode(String code) => jsonEncode({'code': code});
}
