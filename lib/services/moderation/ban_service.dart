import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';

/// Ban levels. Decision locked (plan §0): only these two exist.
enum BanLevel { none, social, full }

/// Parsed `am_i_banned()` answer. Pure + testable (D2).
class BanState {
  final BanLevel level;
  final int daysLeft; // -1 = permanent, 0 = none/ended
  final String reason;

  const BanState({required this.level, this.daysLeft = 0, this.reason = ''});

  /// daysLeft semantics: -1 permanent, >=0 remaining days (0 = <24h left,
  /// still banned — server only returns `none` once expired).
  bool get isBanned => level != BanLevel.none;

  /// social = user can watch, but no party/DM/friends (D3).
  bool get blocksSocial => level == BanLevel.social && isBanned;
  bool get blocksEverything => level == BanLevel.full && isBanned;

  String get easyEnglish {
    if (!isBanned) return '';
    final until = daysLeft < 0
        ? 'permanently'
        : daysLeft == 0
            ? 'until review'
            : 'for $daysLeft more day${daysLeft == 1 ? '' : 's'}';
    if (level == BanLevel.full) {
      return 'This account is suspended $until.'
          '${reason.isEmpty ? '' : ' Reason: $reason'}';
    }
    return 'Friends and rooms are paused $until.'
        '${reason.isEmpty ? '' : ' Reason: $reason'}';
  }

  /// Server shape: {level, days_left, reason} — defensive parse, never throws.
  static BanState fromRpc(dynamic raw) {
    try {
      final m = raw is Map ? raw : (raw is Map<String, dynamic> ? raw : null);
      if (m == null) return const BanState(level: BanLevel.none);
      final lvl = (m['level'] ?? 'none').toString().toLowerCase();
      final level = switch (lvl) {
        'full' => BanLevel.full,
        'social' => BanLevel.social,
        _ => BanLevel.none,
      };
      final days = int.tryParse('${m['days_left'] ?? 0}') ?? 0;
      final reason = (m['reason'] ?? '').toString();
      return BanState(level: level, daysLeft: days, reason: reason);
    } catch (_) {
      return const BanState(level: BanLevel.none); // fail-soft
    }
  }
}

/// Boot-time ban check + long-press report (D3).
class BanService {
  static const _kAppealText = 'ban_appeal_text'; // last draft, offline-safe
  static final ValueNotifier<BanState> state =
      ValueNotifier<BanState>(const BanState(level: BanLevel.none));

  /// Boot gate: refresh from server. Never throws; offline → keep last state.
  static Future<BanState> refresh() async {
    try {
      if (!CloudClient.isReady) return state.value;
      final raw = await CloudClient.db.rpc('am_i_banned');
      final parsed = BanState.fromRpc(raw);
      state.value = parsed;
      return parsed;
    } catch (e) {
      debugPrint('[Ban] refresh fail-soft: $e');
      return state.value;
    }
  }

  /// Report a user (fail-soft: cloud off / error → false, no crash).
  static Future<bool> report(String targetId, String reason) async {
    try {
      if (!CloudClient.isReady) return false;
      if (reason.trim().length < 3) return false;
      await CloudClient.db.rpc('report_user', params: {
        'p_target_id': targetId,
        'p_reason': reason.trim(),
        'p_context': <String, dynamic>{},
      });
      return true;
    } catch (e) {
      debugPrint('[Ban] report fail-soft: $e');
      return false;
    }
  }

  /// Appeal submit (draft kept in prefs so a failed submit isn't lost).
  static Future<bool> submitAppeal(String text) async {
    try {
      final t = text.trim();
      if (t.length < 10) return false;
      if (!CloudClient.isReady) return false;
      await CloudClient.db.rpc('ban_appeal_submit', params: {'p_text': t});
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAppealText);
      await refresh();
      return true;
    } catch (e) {
      debugPrint('[Ban] appeal fail-soft: $e');
      return false;
    }
  }

  static Future<void> saveAppealDraft(String text) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAppealText, text);
    } catch (_) {}
  }

  static Future<String> loadAppealDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kAppealText) ?? '';
    } catch (_) {
      return '';
    }
  }
}
