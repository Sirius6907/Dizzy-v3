/// F5 — new-episode reminders, built without asking anyone to log in.
///
/// A reminder is a **schedule row**, not a push: show, episode code, and the
/// minute it should fire. Building that list is pure arithmetic over the
/// calendar entries we already fetched, so it can be tested with a frozen
/// clock and no platform channel.
///
/// Why no account: the person who follows a show is on the device that shows
/// the alert. Tying it to a login would mean a person who never signs in
/// never gets a nudge about the show they asked us to remember.
library;

/// One episode the person asked to be reminded about.
class ReminderRequest {
  /// Show title, as the calendar spells it.
  final String showTitle;

  final int season;
  final int episode;

  /// Fires this many minutes before air time. Anything ≤0 means "at air
  /// time", which is still useful — some people want to be there on the dot.
  final int leadMinutes;

  const ReminderRequest({
    required this.showTitle,
    required this.season,
    required this.episode,
    this.leadMinutes = 30,
  });

  bool get isValid => showTitle.trim().isNotEmpty && season > 0 && episode > 0;
}

/// A scheduled reminder, ready to fire.
class ReminderSlot {
  /// Stable id so re-building the schedule never double-fires a row.
  final String id;

  final String showTitle;

  /// `S02E05`
  final String episodeCode;

  final String episodeTitle;

  /// When it airs.
  final DateTime airsAt;

  /// When the reminder fires. Always ≤ [airsAt].
  final DateTime remindAt;

  /// Easy English body line.
  final String line;

  const ReminderSlot({
    required this.id,
    required this.showTitle,
    required this.episodeCode,
    required this.episodeTitle,
    required this.airsAt,
    required this.remindAt,
    required this.line,
  });
}

/// How a schedule is built from calendar entries.
abstract final class ReminderSchedule {
  /// Never schedule further out than this. A reminder three weeks ahead is
  /// not a reminder, it is a to-do list nobody reads.
  static const int horizonDays = 14;

  /// Fire no later than this long before air time, however early the person
  /// asked. Two days' notice is a plan, not an alert.
  static const int maxLeadMinutes = 60 * 24;

  /// Minimum lead. Zero would mean "tell me at the exact second it starts",
  /// which arrives too late to do anything about.
  static const int minLeadMinutes = 0;

  /// Cap on rows per schedule, oldest first, so a season dump cannot build a
  /// thousand reminders.
  static const int maxSlots = 50;

  /// Stable, human-readable id for one episode of one show.
  static String slotId(String showTitle, int season, int episode) {
    final show = showTitle.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return 'reminder::$show::$season::$episode';
  }

  /// `S02E05`
  static String episodeCode(int season, int episode) =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

  /// Clamp a requested lead into the range the app will honour.
  static int clampLead(int requested) {
    if (requested < minLeadMinutes) return minLeadMinutes;
    if (requested > maxLeadMinutes) return maxLeadMinutes;
    return requested;
  }

  /// The moment a reminder should fire.
  ///
  /// A reminder in the past is moved to [now] rather than dropped: the person
  /// asked to be told, and a row that silently disappears is how a feature
  /// starts feeling broken.
  static DateTime remindAtFor(DateTime airsAt, int leadMinutes, DateTime now) {
    final lead = Duration(minutes: clampLead(leadMinutes));
    final at = airsAt.subtract(lead);
    return at.isBefore(now) ? now : at;
  }

  /// Build one slot, or `null` when the request cannot be scheduled.
  static ReminderSlot? slotFor(
    ReminderRequest request,
    DateTime airsAt, {
    required DateTime now,
    String episodeTitle = '',
  }) {
    if (!request.isValid) return null;

    final code = episodeCode(request.season, request.episode);
    final title = episodeTitle.trim().isEmpty
        ? 'A new episode is ready.'
        : episodeTitle.trim();

    return ReminderSlot(
      id: slotId(request.showTitle, request.season, request.episode),
      showTitle: request.showTitle.trim(),
      episodeCode: code,
      episodeTitle: episodeTitle.trim(),
      airsAt: airsAt,
      remindAt: remindAtFor(airsAt, request.leadMinutes, now),
      line: '${request.showTitle.trim()} $code is on soon. $title',
    );
  }

  /// The full schedule for [airings], soonest first.
  ///
  /// `airings` is anything with a show title and an air time; a plain
  /// `DateTime` keyed by show is enough, which is why this takes the narrow
  /// [CalendarAiring] shape instead of the calendar service's own model.
  static List<ReminderSlot> build(
    List<ReminderRequest> requests,
    List<CalendarAiring> airings, {
    required DateTime now,
  }) {
    if (requests.isEmpty || airings.isEmpty) return const [];

    final horizon = now.add(const Duration(days: horizonDays));
    final slots = <ReminderSlot>[];

    for (final r in requests) {
      if (!r.isValid) continue;
      CalendarAiring? airing;
      for (final a in airings) {
        if (a.matches(r)) {
          airing = a;
          break;
        }
      }
      if (airing == null) continue;
      if (airing.airsAt.isBefore(now)) continue;
      if (airing.airsAt.isAfter(horizon)) continue;

      final slot = slotFor(
        r,
        airing.airsAt,
        now: now,
        episodeTitle: airing.episodeTitle,
      );
      if (slot == null) continue;
      slots.add(slot);
    }

    // Dedupe by id, keeping the earliest fire time: a follow tapped twice
    // must not turn into two alerts for the same episode.
    final byId = <String, ReminderSlot>{};
    for (final s in slots) {
      final existing = byId[s.id];
      if (existing == null || s.remindAt.isBefore(existing.remindAt)) {
        byId[s.id] = s;
      }
    }

    final out = byId.values.toList()
      ..sort((a, b) {
        final byTime = a.remindAt.compareTo(b.remindAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    return out.take(maxSlots).toList();
  }

  /// Slots that should fire between [from] and [to].
  static List<ReminderSlot> due(
    List<ReminderSlot> slots, {
    required DateTime from,
    required DateTime to,
  }) {
    if (to.isBefore(from)) return const [];
    return slots.where((s) {
      if (s.remindAt.isBefore(from)) return false;
      if (s.remindAt.isAfter(to)) return false;
      return true;
    }).toList();
  }

  /// The next slot, or `null` when the schedule is empty.
  static ReminderSlot? next(List<ReminderSlot> slots) =>
      slots.isEmpty ? null : slots.first;

  /// Drop slots for shows the person stopped following.
  ///
  /// Unfollowing must actually silence the row — a reminder that keeps
  /// arriving after you unfollowed is worse than never having it.
  static List<ReminderSlot> without(
    List<ReminderSlot> slots,
    Set<String> unfollowedShowTitles,
  ) {
    if (unfollowedShowTitles.isEmpty) return slots;
    final drop = unfollowedShowTitles
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();
    if (drop.isEmpty) return slots;
    return slots
        .where((s) => !drop.contains(s.showTitle.trim().toLowerCase()))
        .toList();
  }
}

/// The narrow view of a calendar row this file needs.
///
/// Deliberately not the calendar service's own model: this policy must stay
/// testable without a network, and the service can build these in one line.
class CalendarAiring {
  final String showTitle;
  final int season;
  final int episode;
  final String episodeTitle;
  final DateTime airsAt;

  const CalendarAiring({
    required this.showTitle,
    required this.season,
    required this.episode,
    required this.episodeTitle,
    required this.airsAt,
  });

  /// Air time used when the show and episode are unknown. Year 1, so any
  /// comparison against "now" reads as long past.
  static final DateTime unknownAirTime = DateTime(1);

  bool get isEmpty => showTitle.trim().isEmpty || season <= 0 || episode <= 0;

  /// The row that means "no such episode on the calendar".
  static CalendarAiring missing() => CalendarAiring(
        showTitle: '',
        season: 0,
        episode: 0,
        episodeTitle: '',
        airsAt: unknownAirTime,
      );

  /// True when [other] is the same episode of the same show, whatever
  /// spelling of the title and whatever air time.
  bool matches(ReminderRequest r) =>
      showTitle.trim().toLowerCase() == r.showTitle.trim().toLowerCase() &&
      season == r.season &&
      episode == r.episode;
}

/// Copy for the reminders surface, kept next to the schedule so the copy
/// test can read both.
abstract final class ReminderCopy {
  const ReminderCopy._();

  static const String title = 'New episode alerts';
  static const String subtitle = 'A quiet nudge, no account needed';
  static const String on = 'Alerts are on';
  static const String off = 'Alerts are off';
  static const String empty = 'No shows are being followed yet.';
  static const String action = 'Follow a show';
  static const String saved = 'Saved on this phone.';

  /// "Following 3 shows"
  static String following(int n) {
    if (n <= 0) return 'Not following anything yet';
    if (n == 1) return 'Following 1 show';
    return 'Following $n shows';
  }

  /// "Next alert: Stranger Things S01E03, tomorrow at 21:00"
  static String nextLine(ReminderSlot? slot) {
    if (slot == null) return 'No alerts scheduled.';
    final d = slot.remindAt;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return 'Next alert: ${slot.showTitle} ${slot.episodeCode}, at $hh:$mm';
  }
}
