# Scraper Status — v1.2.0 (2026-09-12)

## Identity (P1 fix verified)

- Site files: **50** in `lib/services/scraper/sites/`.
- Shared `name => 'DizzyHTTP'`: **0** (was 46 in v1.1.9).
- 2 torrent scrapers keep name `'Dizzy'` (P2P toggle depends on it — by design).
- Quarantine keys now match real site names → dead sites skip instead of spinning.
- Sources health dashboard (Settings → Sources) shows live status per site.

## Baseline (carried from v1.1.9 triage)

Full suite then: **+224 / -14**. All 14 failures reproduced on the
pre-fix baseline too (network-dependent or stale expectations) —
none introduced by app changes. v1.2.0 re-verifies in final test run.

| # | Test | Cause | Verdict |
|---|------|-------|---------|
| 1 | A111477Scraper movie+TV | site/network flaky | KEEP-FIX |
| 2 | FlaxMovies (Fight Club) | site down/changed | QUARANTINE |
| 3 | PeeStream (Fight Club) | site down/changed | QUARANTINE |
| 4 | VidFast (Fight Club) | site down/changed | QUARANTINE |
| 5 | VidGod (Fight Club) | site down/changed | QUARANTINE |
| 6 | VidUp (Fight Club) | site down/changed | QUARANTINE |
| 7 | Bcine master HLS | site changed | QUARANTINE |
| 8 | Vadapav movie+TV | network flaky | KEEP-FIX |
| 9 | MovyScraper decrypt live | cipher rotated | KEEP-FIX |
| 10 | Solo Leveling S2E1 anime | upstream flaky | KEEP-FIX |
| 11–12 | DownloadTask serialization, MyListItem uniqueKey ×4 | stale test expectations | KEEP-FIX (test-only) |

## New in v1.2.0

- `test/party_session_test.dart`: 8 tests (session, codes, backoff, policy, refs).
- `test/download_error_text_test.dart`: 11 tests (easy copy, net policy, throttle).
- v1.2.0 quarantine baseline (dead list) applies against unique names for
  the first time — expect 6+ skips on cold scrape vs 0 in v1.1.9.
