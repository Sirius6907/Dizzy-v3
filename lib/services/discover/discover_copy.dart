/// F5 — Discover Daily copy, in ONE file.
///
/// Rule: every new user-facing line for Discover lands here so the copy test
/// can read all of it at once. Easy English — short sentences, no tech words,
/// no error codes, nothing that sounds like a log.
library;

/// Lines for the Discover Daily screen.
abstract final class DiscoverCopy {
  const DiscoverCopy._();

  // ── Screen ────────────────────────────────────────────────────────────────
  static const String title = 'Discover Daily';
  static const String tagline = 'Picked from what you watch';

  /// Shown while the first rails are still being built.
  static const String loading = 'Finding something for you...';

  /// Shown when there is no catalog to draw from yet.
  static const String emptyTitle = 'Nothing to show yet';
  static const String emptyLine = 'Add a source and picks will appear here.';
  static const String emptyAction = 'Retry';

  // ── Rails ─────────────────────────────────────────────────────────────────
  static const String musicRailTitle = 'Smart Mix';
  static const String musicRailSubtitle = 'Your mixes, ready to play';
  static const String musicEmpty = 'Like a few songs and mixes will build here.';

  static const String quizRailTitle = 'What is your mood?';
  static const String quizRailSubtitle = 'Three taps, then tonight is sorted';
  static const String quizAction = 'Take the quiz';
  static const String quizEmpty = 'Play a quiz to get picks for tonight.';

  // ── Reminders ─────────────────────────────────────────────────────────────
  static const String remindersTitle = 'New episode alerts';
  static const String remindersSubtitle = 'A quiet nudge, no account needed';
  static const String remindersOn = 'Alerts are on';
  static const String remindersOff = 'Alerts are off';
  static const String remindersEmpty = 'No shows are being followed yet.';
  static const String remindersAction = 'Follow a show';
  static const String remindersSaved = 'Saved on this phone.';

  // ── Wrap ──────────────────────────────────────────────────────────────────
  static const String wrapTitle = 'Your Year in Stories';
  static const String wrapSubtitle = 'See what you watched this year';
  static const String wrapAction = 'Open my wrap';
  static const String wrapShareAction = 'Share my wrap';

  /// "Because you watched X" is handled by `RailCopy` in the rail policy.
  /// This is only the section label above every rail.
  static const String railsSection = 'Picked for you';

  // ── Error text ────────────────────────────────────────────────────────────
  /// A friendly line for anything that goes wrong while building rails.
  ///
  /// [raw] is accepted and ignored on purpose: a person cannot act on a
  /// failure string, and echoing one reads like a machine talking. The
  /// failure itself still reaches the app log — this is the screen's line,
  /// not the app's record.
  static String railError(String? raw) =>
      'We could not build your picks. Try again.';

  static String railCount(int n) {
    if (n <= 0) return 'No picks yet';
    if (n == 1) return '1 pick for you';
    return '$n picks for you';
  }
}
