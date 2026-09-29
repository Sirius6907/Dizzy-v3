/// F2 — quality profiles: one rung per link, overridable by the user.
///
/// The promise the product makes is "it just works, and it doesn't burn my
/// data". That needs a *default* per link and an *escape hatch*:
///
///  | Profile   | Link            | Rung  |
///  |-----------|-----------------|-------|
///  | WiFi 1080p| WiFi / wired    | 1080p |
///  | Data 720p | Mobile data     | 720p  |
///  | Saver 480p| Anything we     | 480p  |
///  |           | cannot judge    |       |
///
/// Two decisions live here, both pure:
///
///  1. Which profile applies right now ([pick]). An explicit override in
///     Settings always wins; `auto` hands the choice back to the link.
///  2. What that profile actually means ([DownloadQualityProfile.choice]) —
///     resolved through the *player's* [QualityChoice], never a second
///     definition of "720p". F1's hard-won lesson: two services that each
///     own a quality ladder will drift, and the user sees a 480p file
///     labelled 720p.
///
/// [DownloadNetwork.unknown] deliberately falls to Saver rather than Data.
/// A queued download runs on whatever link exists *later*; guessing high
/// there is how a phone bill gets a surprise line item.
library;

import '../player/quality_service.dart';
import 'download_network.dart';

/// The three rungs, named for the link they belong to.
enum DownloadQualityProfile {
  wifi1080(
    label: 'WiFi — best quality',
    choice: QualityChoice.q1080,
  ),
  data720(
    label: 'Mobile data — balanced',
    choice: QualityChoice.q720,
  ),
  saver480(
    label: 'Save data — small file',
    choice: QualityChoice.q480,
  );

  /// Easy English name for the settings row. No codec names.
  final String label;

  /// The player's rung, so "720p" means one thing in the whole app.
  final QualityChoice choice;

  const DownloadQualityProfile({required this.label, required this.choice});

  /// Vertical height in pixels, for the "about this big" hint.
  int get heightPx => choice.index >= 3 ? 1080 : (choice.index + 1) * 360;
}

/// What the user picked in Settings.
enum DownloadQualityOverride {
  /// Follow the link automatically. The default.
  auto('Automatic', null),

  /// Always 1080p, on any link. For people on an unlimited plan.
  wifi1080('Always best (1080p)', DownloadQualityProfile.wifi1080),

  /// Always 720p. The safe middle.
  data720('Always balanced (720p)', DownloadQualityProfile.data720),

  /// Always 480p. Small files, any link.
  saver480('Always small (480p)', DownloadQualityProfile.saver480);

  /// Easy English label for the settings control.
  final String label;

  /// The pinned profile, or null when the link should decide.
  final DownloadQualityProfile? profile;

  const DownloadQualityOverride(this.label, this.profile);

  /// Persisted form. Enum names are stable API; a typo in storage must not
  /// throw at startup, it must fall back to Automatic.
  static DownloadQualityOverride fromName(String? name) {
    for (final v in DownloadQualityOverride.values) {
      if (v.name == name) return v;
    }
    return DownloadQualityOverride.auto;
  }
}

abstract final class DownloadQualityPolicy {
  /// The profile that applies to [network] right now.
  ///
  /// An [override] other than [DownloadQualityOverride.auto] wins outright
  /// — the user's explicit choice is never second-guessed by a flaky
  /// connectivity reading, which is exactly the kind of flip-flop that
  /// makes a settings screen feel broken.
  static DownloadQualityProfile pick({
    required DownloadNetwork network,
    required DownloadQualityOverride override,
  }) {
    final pinned = override.profile;
    if (pinned != null) return pinned;
    switch (network) {
      case DownloadNetwork.wifi:
        return DownloadQualityProfile.wifi1080;
      case DownloadNetwork.mobile:
        return DownloadQualityProfile.data720;
      // A queued download lands on a link we have not seen yet. Take the
      // cheap rung rather than betting the user's data plan on a guess.
      case DownloadNetwork.offline:
      case DownloadNetwork.unknown:
        return DownloadQualityProfile.saver480;
    }
  }

  /// Convenience: pick straight from the live link with no override.
  static DownloadQualityProfile autoFor(DownloadNetwork network) =>
      pick(network: network, override: DownloadQualityOverride.auto);

  /// The rung as the player's own enum, for the resolve step.
  static QualityChoice choiceFor({
    required DownloadNetwork network,
    required DownloadQualityOverride override,
  }) =>
      pick(network: network, override: override).choice;
}
