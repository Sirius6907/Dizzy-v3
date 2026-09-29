/// F5 — follows a show, then remembers when the next episode lands.
///
/// Two rules that make this trustworthy:
///
///  1. **No login.** A follow list lives on the phone. Someone who never
///     signs in still gets the alert they asked for.
///  2. **Unfollow really stops it.** The row leaves the store *and* the
///     schedule, so an alert can never outlive the decision to cancel it.
///
/// The scheduling arithmetic lives in [ReminderSchedule] — pure, so the
/// "does it fire, and when" question is answered without a platform channel.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_schedule.dart';

/// One stored follow: a show, plus how early to nudge.
class FollowedShow {
  final String showTitle;
  final int season;
  final int episode;

  /// Minutes before air time. Defaults to 30.
  final int leadMinutes;

  const FollowedShow({
    required this.showTitle,
    required this.season,
    required this.episode,
    this.leadMinutes = defaultLeadMinutes,
  });

  static const int defaultLeadMinutes = 30;

  ReminderRequest toRequest() => ReminderRequest(
        showTitle: showTitle,
        season: season,
        episode: episode,
        leadMinutes: leadMinutes,
      );

  /// Stable key, so following the same episode twice is one follow.
  String get key =>
      ReminderSchedule.slotId(showTitle, season, episode);

  bool get isValid => showTitle.trim().isNotEmpty && season > 0 && episode > 0;

  Map<String, dynamic> toJson() => {
        'showTitle': showTitle,
        'season': season,
        'episode': episode,
        'leadMinutes': leadMinutes,
      };

  static FollowedShow? fromJson(Map<dynamic, dynamic> json) {
    final title = json['showTitle']?.toString() ?? '';
    final season = json['season'];
    final episode = json['episode'];
    final lead = json['leadMinutes'];
    final s = season is int ? season : int.tryParse(season?.toString() ?? '');
    final e = episode is int ? episode : int.tryParse(episode?.toString() ?? '');
    if (title.trim().isEmpty || s == null || e == null) return null;
    return FollowedShow(
      showTitle: title,
      season: s,
      episode: e,
      leadMinutes: lead is int
          ? lead
          : (int.tryParse(lead?.toString() ?? '') ??
              FollowedShow.defaultLeadMinutes),
    );
  }
}

/// The follow list and the schedule built from it.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const String _storageKey = 'followed_episodes_v1';

  final ValueNotifier<List<FollowedShow>> follows =
      ValueNotifier<List<FollowedShow>>(const []);

  final ValueNotifier<List<ReminderSlot>> schedule =
      ValueNotifier<List<ReminderSlot>>(const []);

  static bool _loaded = false;

  /// True when at least one show is being followed.
  bool get isOn => follows.value.isNotEmpty;

  Future<void> initialize() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = <FollowedShow>[];
      for (final row in decoded) {
        if (row is! Map) continue;
        // A corrupt row is skipped, never thrown on: one bad line must not
        // take the whole list away.
        final f = FollowedShow.fromJson(row);
        if (f == null || !f.isValid) continue;
        if (parsed.any((p) => p.key == f.key)) continue;
        parsed.add(f);
      }
      follows.value = parsed;
    } catch (_) {
      // Unreadable blob = a fresh start, never a crash on launch.
      follows.value = const [];
    }
  }

  /// Start or stop following one episode. Returns the new state.
  Future<bool> toggle(FollowedShow show) async {
    if (!show.isValid) return isOn;
    final current = List<FollowedShow>.from(follows.value);
    final at = current.indexWhere((f) => f.key == show.key);
    if (at >= 0) {
      current.removeAt(at);
    } else {
      current.add(show);
    }
    await _persist(current);
    return isOn;
  }

  /// Follow without the toggle dance. Used when the person taps "remind me"
  /// on an episode they are not following yet.
  Future<void> follow(FollowedShow show) async {
    if (!show.isValid) return;
    final current = List<FollowedShow>.from(follows.value);
    if (current.any((f) => f.key == show.key)) return;
    current.add(show);
    await _persist(current);
  }

  Future<void> unfollow(String showTitle, {int? season, int? episode}) async {
    final target = showTitle.trim().toLowerCase();
    final current = follows.value.where((f) {
      final sameShow = f.showTitle.trim().toLowerCase() == target;
      if (!sameShow) return true;
      if (season != null && f.season != season) return true;
      if (episode != null && f.episode != episode) return true;
      return false;
    }).toList();
    await _persist(current);
  }

  Future<void> _persist(List<FollowedShow> next) async {
    follows.value = next;

    // Drop every slot whose episode is no longer followed. Unfollowing has to
    // silence the alert immediately — a row that keeps firing after you
    // cancelled it is worse than never having offered it. Slots that survive
    // keep their existing fire time, because re-deriving it would need the
    // calendar rows we already fetched once.
    final kept = next.map((f) => f.key).toSet();
    schedule.value = schedule.value
        .where((s) => kept.contains(s.id))
        .toList(growable: false);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(next.map((f) => f.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[ReminderService] persist failed: $e');
    }
  }

  /// Rebuild the fire times from the current follows and the calendar rows.
  void rebuildSchedule({
    required List<CalendarAiring> airings,
    required DateTime now,
  }) {
    schedule.value = ReminderSchedule.build(
      follows.value.map((f) => f.toRequest()).toList(),
      airings,
      now: now,
    );
  }

  /// Slots that should fire in the window, soonest first.
  List<ReminderSlot> dueIn({
    required DateTime now,
    Duration window = const Duration(hours: 1),
  }) =>
      ReminderSchedule.due(
        schedule.value,
        from: now,
        to: now.add(window),
      );

  /// The next alert, or `null`.
  ReminderSlot? get next => ReminderSchedule.next(schedule.value);

  /// True when this exact episode is already followed.
  bool isFollowing(String showTitle, int season, int episode) {
    final key = ReminderSchedule.slotId(showTitle, season, episode);
    return follows.value.any((f) => f.key == key);
  }

  /// Show titles being followed, for the "following N shows" line.
  Set<String> get followedShowTitles =>
      follows.value.map((f) => f.showTitle).toSet();
}
