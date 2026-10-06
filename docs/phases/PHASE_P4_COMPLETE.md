# PHASE P4 COMPLETE — Logic + Wiring audit

## Audit (all verified, not assumed)
- **ensure\***: cloud anon, audiobook x2, mega server, genre prefs, addon
  builtins, yt-config, theme watchers — every def has live call sites.
- **sync\***: my-list (trakt+simkl+cloud), continue-watching cloud, profiles
  cloud, theme two-way, trakt/simkl actions — all wired.
- **Quarantine**: skip-on-scrape + markFailed/markSuccess + health-page
  badges + restoreAll — full loop live.
- **Party 6 fixes**: reconnect w/ backoff+toast, sameTitleResync (seek +
  play/pause match), guest auto-open w/ 20s timeout + 7-seg countdown UI,
  late-join (= auto-open + resync math), sync-parse silent-but-logged,
  chat fail-soft w/ toast. All wired.

## Fix (the one dead wire)
- **AV conflict was dead**: `GlobalMediaCoordinator.notifyVideoStarted`
  defined but ZERO callers — music kept playing under video. Now called on
  the main play path (player open success) + `notifyVideoStopped` on
  dispose. One sound at a time again.

## Gates
- Analyze on player_screen: clean. Party regression (7 files): **45/45**.
- No new tests needed (existing cover), no new deps, +6/-0 lines of logic.

## Top risk for P5
home_page (~2100 lines) + watch_screen (~3300 lines) splits are the big
surgery — parent-orchestrator cut must keep every Positioned overlay alive.
