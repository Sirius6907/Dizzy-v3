import 'dart:async';

import '../errors/app_error_log.dart';
import 'models/debrid_file.dart';
import 'providers/alldebrid_service.dart';
import 'providers/debrid_link_service.dart';
import 'providers/premiumize_service.dart';
import 'providers/real_debrid_service.dart';
import 'providers/torbox_service.dart';

/// One link in the failover chain.
class DebridAttempt {
  /// The display name, matching what the settings page stores.
  final String label;

  /// Whether the user has a key saved for this provider. A provider
  /// with no key is skipped without a network round trip — that is the
  /// common case, since most installs configure exactly one.
  final Future<bool> Function() hasKey;

  final Future<List<DebridFile>> Function(
    String magnet, {
    int? fileIndex,
    String? filename,
    int? season,
    int? episode,
    String? episodeTitle,
  }) resolve;

  const DebridAttempt(this.label, this.hasKey, this.resolve);
}

/// Why a failover chain ended. Returned instead of thrown so callers
/// can pick their own wording — a player and a download queue do not
/// want the same message.
enum DebridFailoverOutcome {
  /// A provider returned files.
  resolved,

  /// At least one provider was tried and every one of them failed.
  allProvidersFailed,

  /// No provider had a key, so nothing was even attempted.
  noProviderConfigured,
}

class DebridFailoverResult {
  final DebridFailoverOutcome outcome;

  /// Populated only when [outcome] is [DebridFailoverOutcome.resolved].
  final List<DebridFile> files;

  /// Which provider answered, in the user's own vocabulary.
  final String? provider;

  /// Providers actually tried, in order. Empty when nothing had a key.
  final List<String> attempted;

  const DebridFailoverResult._({
    required this.outcome,
    required this.files,
    required this.provider,
    required this.attempted,
  });

  const DebridFailoverResult.resolved(String who, List<DebridFile> f)
      : this._(
          outcome: DebridFailoverOutcome.resolved,
          files: f,
          provider: who,
          attempted: const [],
        );

  const DebridFailoverResult.failed(List<String> tried)
      : this._(
          outcome: DebridFailoverOutcome.allProvidersFailed,
          files: const [],
          provider: null,
          attempted: tried,
        );

  const DebridFailoverResult.noneConfigured()
      : this._(
          outcome: DebridFailoverOutcome.noProviderConfigured,
          files: const [],
          provider: null,
          attempted: const [],
        );

  bool get isResolved => outcome == DebridFailoverOutcome.resolved;
}

/// P3 — one debrid call, five chances.
///
/// Before this, `DebridService.resolveMagnet` dispatched to exactly the
/// one provider the user had selected, and a 503 from it ended the
/// attempt. The user saw "could not play" and had no idea that four
/// other services, with keys already saved, could have answered.
///
/// The order below is fixed, not a preference list, so the behaviour is
/// the same on every install:
///
///   Real-Debrid → TorBox → AllDebrid → Premiumize → Debrid-Link
///
/// First-valid-wins. A provider that throws is contained and the chain
/// moves on; the failure is logged under `debrid_failover` so the
/// dashboard shows which one is actually broken. If every provider
/// throws, the result is [DebridFailoverOutcome.allProvidersFailed] —
/// never a partial answer.
class DebridResolver {
  DebridResolver({
    RealDebridService? realDebrid,
    TorBoxService? torBox,
    AllDebridService? allDebrid,
    PremiumizeService? premiumize,
    DebridLinkService? debridLink,
  })  : _realDebrid = realDebrid ?? RealDebridService(),
        _torBox = torBox ?? TorBoxService(),
        _allDebrid = allDebrid ?? AllDebridService(),
        _premiumize = premiumize ?? PremiumizeService(),
        _debridLink = debridLink ?? DebridLinkService();

  final RealDebridService _realDebrid;
  final TorBoxService _torBox;
  final AllDebridService _allDebrid;
  final PremiumizeService _premiumize;
  final DebridLinkService _debridLink;

  /// The failover order. Also the order the settings page displays, so
  /// a user can read the chain and understand which service will try
  /// first.
  List<DebridAttempt> chain() => <DebridAttempt>[
        DebridAttempt(
          'Real-Debrid',
          _realDebrid.hasKey,
          _realDebrid.resolveMagnet,
        ),
        DebridAttempt('TorBox', _torBox.hasKey, _torBox.resolveMagnet),
        DebridAttempt('AllDebrid', _allDebrid.hasKey, _allDebrid.resolveMagnet),
        DebridAttempt(
          'Premiumize',
          _premiumize.hasKey,
          _premiumize.resolveMagnet,
        ),
        DebridAttempt(
          'Debrid-Link',
          _debridLink.hasKey,
          _debridLink.resolveMagnet,
        ),
      ];

  /// Try each configured provider in order until one returns files.
  ///
  /// Never throws. Every provider failure is contained — that is the
  /// entire contract, because the alternative is that one flaky
  /// provider eats the whole chain.
  Future<DebridFailoverResult> resolve({
    required String magnet,
    int? fileIndex,
    String? filename,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    final trimmed = magnet.trim();
    if (trimmed.isEmpty) {
      return const DebridFailoverResult.noneConfigured();
    }

    final tried = <String>[];

    for (final attempt in chain()) {
      final configured = await _hasKeySafely(attempt);
      if (!configured) continue;

      tried.add(attempt.label);
      try {
        final files = await attempt.resolve(
          trimmed,
          fileIndex: fileIndex,
          filename: filename,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
        );
        if (files.isNotEmpty) {
          return DebridFailoverResult.resolved(attempt.label, files);
        }
        // Empty is a failure, not a win: an empty answer would strand
        // the player with nothing to open.
        unawaited(_log(detail: 'empty_result', provider: attempt.label));
      } catch (_) {
        unawaited(_log(detail: 'provider_failed', provider: attempt.label));
      }
    }

    if (tried.isEmpty) return const DebridFailoverResult.noneConfigured();
    unawaited(_log(detail: 'all_failed'));
    return DebridFailoverResult.failed(tried);
  }

  /// `hasKey()` reads SharedPreferences. If that read itself throws the
  /// provider is treated as unconfigured — skipping it is strictly
  /// better than letting the exception abort the chain.
  Future<bool> _hasKeySafely(DebridAttempt attempt) async {
    try {
      return await attempt.hasKey();
    } catch (_) {
      return false;
    }
  }

  /// Detail is a fixed vocabulary, never a provider's error text — the
  /// P2 privacy gate would redact it anyway, and a redacted report is
  /// a useless report.
  ///
  /// The provider label is appended, not free text. Every label is a
  /// fixed set of five product names, all of which survive the gate's
  /// `^[a-z0-9_.\-]+$` allowlist (it lowercases first), so the report
  /// survives *and* says which service is actually broken — which is
  /// the only question anyone has when a debrid chain fails.
  Future<void> _log({required String detail, String? provider}) =>
      AppErrorLog.log(
        code: 'debrid_failover',
        screen: 'debrid',
        detail: provider == null ? detail : '$detail.$provider',
      );
}
