# PHASE P3 COMPLETE — Networking 50x

## Landed (main)
- **P3-base** `c562cf0`: DizzyNet client (retry+jitter+backoff, completer-based
  timeout race, per-host circuit breaker, offline queue) + DebridResolver +
  5 callers migrated (anilist, catalog, debrid, metadata, deezer-search).
  29 net tests pass, scoped analyze clean.
- **P3-remainder** (this commit): offline wiring + triage + fixes (below).

## Offline wiring — 8 daily screens on OfflineAwareScaffold
home, discover, search, details, my_list, downloads, player, party.
+ `extendBodyBehindAppBar` passthrough on the wrapper (search needs it).
Previously only 4 settings pages had it. Banner copy stays Easy English.

## Silent-catch triage (6 paths)
1. **HLS ladder** — brain is pure sync (no throws possible); player surfaces
   Easy English + source picker. No change needed.
2. **guest auto-open** — toast + AppErrorLog already. No change.
3. **TMDB fetch** — FIXED: both `_edgeGet` + `_directGet` moved off bare
   `.timeout()` onto shared `raceTimeout` (`lib/services/net/timeout_race.dart`);
   DizzyNet's private racer now delegates to the same helper (no dup logic).
4. **party sync parse** — silent-but-logged (parse class). No change.
5. **quality switch** — HUD toast for user action; bg asset/dir catches stay
   silent. No change.
6. **chat send** — FIXED x2: room send adds `room_chat_send` admin log (UI
   already toasted); DM send dropped the fake "Sent locally" echo — fail now
   keeps text in the box + warn toast (server realtime is source of truth);
   `dm_send` admin log added.

## Fixes found while landing
- deezer_api_client had a half-migration (DizzyNet import, raw http calls) —
  reverted to plain http (its proxy-retry flow is custom, out of P3 scope).
  This was breaking 13 test files at load; full suite green after.

## Gates
- Scoped analyze on all touched files: clean. `flutter analyze lib/`: clean.
- New: 4 auto-pause tests + 29 net = 33. Full suite: **679 passed / 24
  skipped / 0 failed** (P2 baseline 646/24/0 → +33, zero regressions).
- No new dependencies. No file over ~600 lines (largest touched: player
  swap only, 1 line).

## Top risk for P4
WatchScreen/GlobalMediaCoordinator AV wiring + party regression tests are
still unverified — P4's audit should start there.
