/// F1 — which skip segments jump on their own.
///
/// One predicate, no screen state, no platform calls — so the rule is
/// unit-testable and the player widget only has to ask.
///
/// Policy (Easy English rules, no jargon):
///  - Intro   → auto-skip ON by default (this is the "one tap" promise:
///    nobody wants the opening titles again).
///  - Recap   → auto-skip ON by default ("previously on…" replays).
///  - Credits → auto-skip ON by default; the player turns that into the
///    next-episode hand-off (or seeks past the credits), never a dead end.
///  - Preview → NEVER auto-skips. A preview is the tail of a movie; a
///    wrong guess there ruins the ending, so we always wait for the user.
///
/// Every auto-skip stays cancellable: the user can always seek back, and
/// the manual skip button is unaffected by these flags.
library;

abstract final class AutoSkipPolicy {
  static const String _intro = 'intro';
  static const String _recap = 'recap';
  static const String _credits = 'credits';

  /// Credits cannot auto-jump during the opening minute. A provider that
  /// omits a start time would otherwise match at 0:00 and seek to the end,
  /// which looks like "the episode started at the ending".
  static const Duration creditsMinPosition = Duration(seconds: 60);

  /// Position-aware variant used by the player tick.
  static bool shouldAutoSkipAt(
    String type,
    Duration position, {
    required bool autoSkipIntro,
    required bool autoSkipRecap,
    required bool autoSkipCredits,
  }) {
    if (type.trim().toLowerCase() == _credits &&
        position < creditsMinPosition) {
      return false;
    }
    return shouldAutoSkip(
      type,
      autoSkipIntro: autoSkipIntro,
      autoSkipRecap: autoSkipRecap,
      autoSkipCredits: autoSkipCredits,
    );
  }

  /// True when a segment of [type] should jump without user input.
  ///
  /// Only three types are ever auto-skipped. A preview, a trailer, or any
  /// type a provider invents later is never auto-skipped — a wrong guess
  /// at the tail of a movie ruins the ending, so we always wait for the
  /// user there.
  static bool shouldAutoSkip(
    String type, {
    required bool autoSkipIntro,
    required bool autoSkipRecap,
    required bool autoSkipCredits,
  }) {
    switch (type.trim().toLowerCase()) {
      case _intro:
        return autoSkipIntro;
      case _recap:
        return autoSkipRecap;
      case _credits:
        return autoSkipCredits;
      default:
        return false;
    }
  }
}
