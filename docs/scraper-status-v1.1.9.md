# Scraper Status — v1.1.9 (2026-09-08)

Full suite: **+224 / -14**. All 14 failures reproduced on the
pre-fix baseline too (network-dependent or stale expectations) —
none introduced by v1.1.9 changes.

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
| 11–12 | DownloadTask serialization, MyListItem uniqueKey ×4 | stale test expectations (model format drifted, e.g. `tmdb:movie:789` vs `tmdb:789`, speed not round-tripped) | KEEP-FIX (test-only, app unaffected) |

**QUARANTINE** = auto-skip in ScraperManager with 7-day retry,
no spinner for dead ones (planned Task 4 follow-up).
**KEEP-FIX** = live scrapers / test-only fixes, no quarantine.
