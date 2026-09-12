# P15 — Silent-catch triage (2026-09-12)

Rule: **network/parse catches stay silent-but-logged** (`AppErrorLog`, consent-gated,
no URLs/titles/raw text — enum codes only). **State/payment/auth catches MUST
surface** an Easy-English message. Top user paths touched; everything else
documented below. No blind rewrite.

## Touched (top paths)

| Path | Catch class | Handling |
|---|---|---|
| Player HLS ladder fetch (`_maybeFetchRenditions`) | network | silent + `renditions_fetch` / `player` |
| Next-ep rendition attach (`withRenditions`) | network | silent + `prefetch_renditions` / `next_episode` |
| Guest auto-open timeout/error | state (user waiting) | **easy toast shown** + `guest_open` / `party` (`timeout_20s`) |
| Guest prewarm | network (background) | silent + `guest_prewarm` / `party` |
| TMDB edge + direct fetch | network | silent + `tmdb_fetch` / `tmdb` (`edge`/`direct`) |
| Party sync message parse | parse | silent + `sync_msg_parse` / `party` |
| Party send/announce failure | state (room sync) | **reconnect + "Reconnecting…" toast** (P2, unchanged) |
| Quality switch failure | state (user action) | **"Could not switch quality. Keep watching."** (P7, unchanged) |
| Player critical error | state (playback) | **failover → easy message + picker** (P6, unchanged) |
| Chat send/react/pin failure | state (user action) | **toast on false** (P4/P11, unchanged) |

## Deliberately untouched

- **179 extractor files**: per-site network/parse catches are already silent and
  correct (a dead site must not toast). No rewrite; codes would add noise at
  179× scale. Revisit only if admin dashboard shows a site flapping.
- **Voice service catches** (token join, mic toggles): token failure returns
  false → existing UI toasts; mic toggles are best-effort hardware calls.
  Behavior kept; logging deferred to keep the voice path stable.
- **Download service catches**: covered by `download_error_text` easy-text
  mapping (user-visible) — no change.
- **Auth/payment catches**: none found swallowing — `CloudAuthService` errors
  propagate to UI sheets (verified by inspection, no edit needed).

## Codes registry (enum strings only — never raw errors)

`renditions_fetch`, `prefetch_renditions`, `guest_open` (+`timeout_20s`),
`guest_prewarm`, `tmdb_fetch` (+`edge`/`direct`), `sync_msg_parse`.
All throttled (1 send / 24h / code+screen) and consent-gated inside `AppErrorLog`.
