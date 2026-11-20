# Dizzy v1.4 Vision — "One App" Production Roadmap
Date: 2026-11-17 · Owner: Sirius · Branch: `prism/v2-reskin`

## The thesis

One app that feels like **Netflix + Spotify + Crunchyroll + Instagram combined** —
a single Prism home where every vertical (movies, series, music, manga,
audiobooks, live TV, social) is production-grade: fast, robust, and consistent.
Not four apps glued together — one design system, one player, one identity.

### Non-negotiable quality bars
- **One player** for everything (video: DASH/HLS + mpv; audio: system-integrated).
- **Every failure degrades gracefully** — a dead source removes one tile, never
  breaks the page (existing music-source discipline, applied app-wide).
- **Realtime, offline, and lock-screen are first-class**, not extras.
- Tests are the spec; new modules get service-level tests before UI.

## Vertical matrix (production bar per vertical)

| Vertical | Today | Production bar |
|---|---|---|
| Movies/Series | working | prefetch metadata, resume everywhere, download counters |
| Music | live (edge fixed) | fix repeated-tap ghost taps (debounce player actions), lock-screen controls |
| Manga | working | reading progress sync + download packs |
| Audiobooks | present | chapter resume, background playback, sleep timer |
| Live TV | basic | **cricket-priority engine** (below) |
| 18+ Heaven | present | age-gate + curation (below) |
| Social | DM/friends live | Groups UI (in progress), notifications, polish |

## P0 — the two killer gaps (owner's top pain)

### 1. Background audio + lock-screen controls
- Android: `audio_service` integration — media notification with
  play/pause/next, seek bar on the lock screen, headphone-button control,
  `MediaSession` metadata (title/artist/cover), survives app-in-background.
- Native playback (mpv/video player) must hand audio to the service so the
  **notification bar persists when the app is backgrounded**.
- Persist last-playing queue; auto-resume on cold start (one tile row).
- iOS later (audience is Android-first) — keep the service abstraction portable.

### 2. Notifications end-to-end
- Consolidate existing `device_tokens` / `push_send_log` into a real pipeline:
  FCM (Android) for **DM/group messages, friend requests, watch-party invites,
  room cards, new releases on followed titles**.
- Deep links: tapping a notification lands on the exact screen (chat thread,
  room, title). Rich style (sender name + avatar).
- Settings page: per-category toggles + global mute; respect DND.
- Server-side triggers from Supabase (edge fn `push-dispatch`) — no client-side
  polling. Idempotent send-log to prevent duplicate pushes.

## P1 — social stack to production UX

1. **Groups UI** (in progress): list + chat + Watch-Together cards, roster,
   join codes. Realtime already live.
2. **Name resolution everywhere** — `resolve_usernames` is live; make every
   surface (rosters, notifications, chat headers) show real names, never
   `friend_<uid>`.
3. **Social Hub v2** — DMs, Groups, friends, rooms, Listen Together as one
   hub with unread badges; badge counts sourced from a `last_read` cursor.
4. **Watch Party end-to-end polish** — invite from chat directly, room cards
   render media thumbnails, sync drift indicator, voice-mode quality setting.

## P2 — vertical tuning

### Live TV — Indian audience priority engine
- Ranked channel list: **cricket first** — if an Indian team match or a match
  hosted in India is live, that feed is pinned to slot #1 with a LIVE badge.
- Source of truth: curated `live_tv_priority` remote-config (no hardcode),
  refreshed on app start + every 15 min.
- Fallback order: cricket > India-relevant sports > news > general.
- Repeated-tap hardening on channel switch (debounce 500 ms + pending-switch
  coalescing so taps during buffering don't queue zombie switches).

### 18+ Heaven — production grade
- Hard age gate (birth-year confirm, remembered per device), off by default.
- **Well-categorized**: category chips (by genre/language/region), curated
  rows, search scoped to the section only, no cross-leak into normal home.
- Private mode: hides the section from the home bar + app switcher preview
  ("content hidden" placeholder in recents on Android).
- All playback through the same secure proxy discipline; never leak adult
  upstreams into logs, telemetry, or recommendation caches.

### Music — repeated-tap fix
- Debounce every player action (play/pause/next/prev) with a single-flight
  command queue; visual pressed-state lock so double-taps can't fire twice.
- Applies to: mini bar, full player, list rows, lock-screen controls.

### UI bug — home bottom bar
- Home page bottom bar sits **mispositioned / slightly higher** than other
  pages' bars. Fix: unify one `NavigationBar` widget (single component,
  identical insets/height/SafeArea padding on every tab), add a golden test
  comparing heights across pages.

## P3 — architecture & maintainability
- Module boundaries: `services/<vertical>` each own folder, no cross-imports
  except through `app/` facade; keeps scraper/edge failures contained.
- Feature flags via existing `remote_config` table (already in realtime).
- Error pipeline: extend `app_error_log` categories for each new P0/P1 path.
- Performance budget: cold start < 2.5 s mid-tier Android, home scroll jank
  < 1%, APK < 45 MB per ABI slice.

## Delivery order (owner-approved queue)
1. Groups UI (Phase A — already in flight)
2. Bottom-bar unification bug fix (small, high-visibility)
3. Background audio + lock-screen (audio_service integration)
4. Repeated-tap debounce (music + live TV switch)
5. Notifications pipeline (FCM + deep links + settings)
6. Live TV cricket-priority engine
7. 18+ categorization + private mode + hard age gate
8. Social Hub v2 polish
9. Manga/audiobook background-play parity
10. v1.4.0 release: tag, CI, site generator sync
