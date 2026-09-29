/// F2 — what kind of link are we on?
///
/// `connectivity_plus` reports the *transport*, not whether the user's data
/// plan is capped. There is no "is this metered" flag on any platform API we
/// can reach without a paid dependency, so we do not pretend to have one.
/// Instead we collapse the transport down to the only question the download
/// rules actually ask:
///
///   "is spending the user's data something we may do without asking?"
///
/// Mobile data answers "no" and is therefore treated as metered. A hotspot
/// that arrives as WiFi answers "yes", which is what users mean when they
/// read the word "WiFi". Every other transport — VPN, Bluetooth, anything a
/// future OS invents — lands in [DownloadNetwork.unknown] and is treated the
/// same as metered, because guessing wrong in the user's favour is how an
/// app spends money nobody authorised.
///
/// Pure Dart apart from the one `connectivity_plus` import, so the mapping
/// is unit-tested without a device.
library;

import 'package:connectivity_plus/connectivity_plus.dart';

/// The link, judged only by what it costs the user.
enum DownloadNetwork {
  /// Home/office WiFi or a wired link. Free to spend.
  wifi,

  /// Cellular. The user's data plan — ask before spending it.
  mobile,

  /// No link at all. Nothing can be downloaded right now.
  offline,

  /// A transport we cannot judge. Treated exactly like metered data.
  unknown;

  /// True only when spending bytes is definitely free.
  ///
  /// Note the deliberate one-way door: [unknown] is NOT unmetered. A VPN
  /// that is really riding a phone hotspot is the case this protects.
  bool get isUnmetered => this == DownloadNetwork.wifi;

  /// True when the user should be asked before any bytes are spent.
  bool get needsConsent => this == mobile || this == unknown;

  /// Easy English name for settings and prompts. No jargon, no plan names.
  String get label {
    switch (this) {
      case DownloadNetwork.wifi:
        return 'WiFi';
      case DownloadNetwork.mobile:
        return 'Mobile data';
      case DownloadNetwork.offline:
        return 'No internet';
      case DownloadNetwork.unknown:
        return 'Other network';
    }
  }
}

/// Collapse one `connectivity_plus` sample into a [DownloadNetwork].
///
/// The sample is a *list* because an Android device can report several
/// transports at once (WiFi + cellular, WiFi + VPN). The rule is "spend
/// freely if ANY active transport is unmetered", which is what the user
/// experiences: the bytes will flow over WiFi.
///
/// Ordered most-specific first:
///  - no transports at all, or only `none` → offline
///  - any WiFi/ethernet → wifi
///  - otherwise any cellular → mobile
///  - otherwise (vpn/bluetooth/other only) → unknown
///  - an empty list means the check failed → unknown, never offline, so a
///    failed probe cannot masquerade as "no internet" and stall the queue.
DownloadNetwork classifyConnectivity(List<ConnectivityResult> results) {
  if (results.isEmpty) return DownloadNetwork.unknown;
  if (results.every((r) => r == ConnectivityResult.none)) {
    return DownloadNetwork.offline;
  }
  const unmetered = {ConnectivityResult.wifi, ConnectivityResult.ethernet};
  if (results.any(unmetered.contains)) return DownloadNetwork.wifi;
  if (results.contains(ConnectivityResult.mobile)) return DownloadNetwork.mobile;
  return DownloadNetwork.unknown;
}
