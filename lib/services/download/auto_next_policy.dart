/// F2 — auto-next: should the next episode queue itself?
///
/// The brief in one line: "on WiFi queue the next episode by itself; on
/// mobile data *ask*; never auto-download on metered."
///
/// This file holds the whole decision and nothing else — no prefs, no
/// network, no files. The rules, in the order they are applied:
///
///  1. Toggle off ⇒ do nothing. The user asked for silence.
///  2. No link ⇒ do nothing. We must not spend the user's data guessing
///     what the link will look like when it comes back, and we must not
///     ask a question that cannot have an answer yet. The caller retries
///     when connectivity returns.
///  3. Already saved ⇒ do nothing. Double-queuing one episode wastes the
///     disk we are already short of.
///  4. No next episode ⇒ do nothing. End of season is not an error.
///  5. Unmetered ⇒ queue now. The toggle defaults ON, so this is the
///     normal, silent, expected path.
///  6. Metered ⇒ [AutoNextDecision.askFirst]. **The only** outcome a
///     metered link is allowed to reach. This is the rule the whole file
///     exists to protect.
///
/// Nothing here queues anything: [decide] returns a verdict and the caller
/// acts on it. That keeps "did we ask?" a question the tests can answer.
library;

import 'download_network.dart';

/// The one sentence shown when we must ask. Easy English, no jargon, no
/// plan names, no numbers to make the user do arithmetic.
const String kAutoNextMeteredPrompt = 'Download next on mobile data?';

/// The confirmation we show after the user says yes, so the decision is
/// visible rather than assumed.
const String kAutoNextMeteredQueued = 'Next episode queued.';

/// What [AutoNextPolicy.decide] concluded.
enum AutoNextDecision {
  /// The auto-next toggle is off. Nobody asked for this.
  off,

  /// No usable link right now. Retry when connectivity returns — do not ask.
  waitingForNetwork,

  /// This episode is already saved or already queued. Do not duplicate it.
  alreadySaved,

  /// End of the season (or a movie). Nothing to queue.
  nothingNext,

  /// Queue it now. Only ever reached on an unmetered link.
  queueNow,

  /// Ask the user first, in Easy English. The only metered outcome.
  askFirst;

  /// Whether the caller should start a download without asking anyone.
  bool get isAuto => this == AutoNextDecision.queueNow;

  /// Whether the caller must show [kAutoNextMeteredPrompt] and wait.
  bool get needsAsk => this == AutoNextDecision.askFirst;
}

abstract final class AutoNextPolicy {
  /// The one rule that is not negotiable: a metered link may only ever
  /// produce [AutoNextDecision.askFirst]. Exposed as a predicate so the
  /// test suite can assert the invariant directly, over every combination
  /// of inputs, instead of trusting the branch order.
  static bool isMeteredAutoDownloadAllowed(DownloadNetwork network) =>
      !network.needsConsent;

  /// Decide whether the episode after the one just saved should be queued.
  ///
  /// All four inputs are explicit so the decision is reproducible in a test
  /// and has no hidden dependency on app state:
  ///  - [autoNextEnabled] — the user's toggle (defaults ON).
  ///  - [network] — judged by [DownloadNetwork], not by raw transport.
  ///  - [hasNextEpisode] — false for a movie or the season finale.
  ///  - [alreadySaved] — the next episode is already downloaded or queued.
  static AutoNextDecision decide({
    required bool autoNextEnabled,
    required DownloadNetwork network,
    required bool hasNextEpisode,
    required bool alreadySaved,
  }) {
    if (!autoNextEnabled) return AutoNextDecision.off;
    if (network == DownloadNetwork.offline) {
      return AutoNextDecision.waitingForNetwork;
    }
    if (alreadySaved) return AutoNextDecision.alreadySaved;
    if (!hasNextEpisode) return AutoNextDecision.nothingNext;
    return network.needsConsent
        ? AutoNextDecision.askFirst
        : AutoNextDecision.queueNow;
  }
}
