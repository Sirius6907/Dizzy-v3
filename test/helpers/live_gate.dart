/// Gate for live third-party integration tests (scrapers, similar rows,
/// subtitle sites, addon manifests).
///
/// These hit real outside websites that change, rate-limit, or block
/// networks without notice — so they can NEVER be deterministic. Default:
/// skipped (suite stays green offline). Pass
/// `--dart-define=LIVE_TESTS=true` to exercise the live sites.
///
/// Usage: `test('...', skip: liveSkip, () async {...})` or
/// `group('...', skip: liveSkip, () {...})`.
const String? liveSkip = bool.fromEnvironment('LIVE_TESTS', defaultValue: false)
    ? null
    : 'Live third-party site — run with --dart-define=LIVE_TESTS=true.';
