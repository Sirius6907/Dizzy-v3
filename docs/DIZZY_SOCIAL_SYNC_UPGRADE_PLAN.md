# DIZZY V3: SOCIAL & MULTI-SYNC MASTER UPGRADE PLAN (BATTLE-PROOF)
**Document Version:** 1.0.0  
**Architectural Baseline:** Dizzy-v3 (Flutter 3.x, Supabase, LiveKit Cloud, media_kit)  
**Status:** Approved & Saved (Ready for Phased Execution)

---

## Executive Summary
This document defines the production-grade, 100x upgrade architecture for Dizzy-v3, incorporating findings from autonomous deep-dive architectural audits. It establishes an unshakeable backend foundation, zero-login-wall progressive identity, Instagram-tier profile/social discovery, high-throughput DMs/groups, and a unified cross-media Realtime Sync Engine (Watch, Listen, Read Together), while strictly enforcing a budget of ≤3GB RAM and ≤20% CPU on low-tier mobile hardware.

---

## Phase 0: Security Foundation & Database Hardening (The Groundwork)
*Must be deployed before exposing any social or linking APIs to prevent SMS pumping, spam, or DB saturation.*

1. **Central Token-Bucket Rate Limiter (`rate_buckets` & `take_token` RPC):**
   - Central table tracking `(key, tokens, updated_at)`.
   - Hard limits enforced server-side:
     - `boot_device`: 10/hr per HWID hash + 5/hr per IP.
     - `claim_username`: 3 attempts/day, 1 rename per 7 days.
     - `search_users`: 30 queries/min/user, minimum 2 characters.
     - `dm_send` / `group_send`: 1 msg/sec, 500 msgs/day/user.
     - `host_state` Realtime Broadcast: throttled to 2Hz max.
2. **Strict RLS & Leak-Free RPCs:**
   - Client direct `SELECT` on sensitive telemetry/logs/tables disabled.
   - Access to chat messages gated via `is_convo_member()` `SECURITY DEFINER` function.
   - Idempotency via unique `client_msg_id UUID` per message to guarantee zero duplicates on unstable networks.
3. **Optimized Trigram Search Index:**
   - `pg_trgm + GIN` index on `profiles.username_lower` for sub-10ms fuzzy matching across 100k+ accounts.

---

## Phase 1: Anonymous-First Identity & Progressive Cross-Device Linking

1. **Zero Login Wall Boot:**
   - Fresh install executes `boot_device(p_hwid_hash, p_platform, p_version)` on startup.
   - Automatically issues anonymous `auth.uid()` + friendly 7-digit device code (e.g. `DIZ-7842`).
   - Binge watching, scrapers, and local history work 100% login-free.
2. **Optional Progressive Linking Sheet:**
   - In Settings/Profile: *"Link Phone or Gmail to sync across devices"*.
   - Uses native Supabase OTP challenge (`signInWithOtp`).
3. **Atomic Multi-Device Account Merger (`merge_devices` RPC):**
   - Solves the `linkIdentity` re-parenting race.
   - When an existing phone/email is linked to a fresh install:
     - Merges `continue_watching` using `max(progress_ms)` and `latest(updated_at)`.
     - Preserves all Watchlist, custom preferences, and friend graphs without data overwrite.
     - Safely cascades old anonymous records.

---

## Phase 2: Instagram-Grade Profile & Social Discovery

1. **Profile Studio:**
   - Unique `@username` validation (`^[a-z0-9_]{3,20}$`, lowercase normalized, reservation TTL).
   - Visual Avatar studio (remote avatar caching via `DizzyImage` + fallback local emoji ring).
   - Binge stats row: Total Hours Watched, Anime Completed, Manga Chapters Read, Audio Streak.
   - 3-Column Sliver Grid Tabs: `[Watching | Bookmarks | Read History]`.
2. **Friend Graph & Discovery:**
   - Mutual follow/friend system (`friendships` table: pending, accepted, blocked).
   - In-app Search bar: instantaneous prefix matching for `@username` and DIZ device code.
   - Granular privacy toggles: Public, Friends Only, or Private Binge Mode.

---

## Phase 3: High-Performance DMs & Group Chats with Media Cards

1. **Durable vs Ephemeral Transport Split:**
   - Message history persisted in Postgres (`dm_messages` / `group_messages`) for permanent recovery across reinstalls.
   - Typing status, active presence, and read-receipts routed exclusively through ephemeral Realtime Broadcast (zero DB IOPS).
2. **Modern Interactive Chat Bubbles:**
   - 60fps virtualized `ListView.builder` with date separators, delivery ticks, and swipe-to-reply.
   - Native image share with micro-thumbnails (`DizzyImage`).
3. **Interactive Media Launch Cards:**
   - Share any Movie, Series, Song, or Manga directly into DM or Group.
   - Renders as a rich media card with poster, title, and action badges:
     - `[🎬 Watch Together]`
     - `[🎧 Listen Together]`
     - `[📖 Read Together]`
   - Tapping the card seamlessly routes both users into the dedicated synchronized room.

---

## Phase 4: Unified Multi-Sync Co-Experience Rooms (1 Engine, 3 Modes)

*Consolidates Watch, Listen, and Read into a single polymorphic `RoomEngine(mode)`.*

1. **🎬 Mode 1: Watch Together (Movies / Series / Anime):**
   - Pure-math clock offset calculation (<50ms drift tolerance).
   - Adaptive Heartbeat: 1Hz during steady playback, 4Hz for 5s during seeks/pauses, then backoff (60% network traffic savings).
   - Server-side epoch fencing: prevents split-brain host takeovers during network partitions.
   - LiveKit HD Voice strip + floating PiP overlay for multitasking.
2. **🎧 Mode 2: Listen Together (Music & Audiobooks):**
   - Synchronized audio playback with word/line-level lyric scrolling (`line_id` matching).
   - Collaborative Queue using an Append-Only Op-Log (`add`, `move`, `remove` events) preventing track overwrite.
3. **📖 Mode 3: Read Together (Manga & Light Novels):**
   - Discrete `(chapter_index, page_index, anchor_pct)` event-driven sync (zero continuous scroll pixel spam).
   - Dual-page and vertical webtoon lock.
   - Interactive "Presenter" pointer indicator.

---

## Phase 5: Hardware Resource Budget & Low-Spec Hardening

1. **Thermal & RAM Rules (Budget Devices ≤3GB RAM / ≤20% CPU):**
   - Cap maximum glass lenses to 1 on budget devices.
   - Freeze shader repaint loops on 90Hz/120Hz displays when video is paused.
   - 100% universal migration of all raw network images to `DizzyImage` with strict downscale constraints (`memCacheWidth`).
   - Adaptive Resource Governor sampling rate: 2s during active media/LiveKit, 10s idle.
2. **Zero-Tech Easy English Guarantee:**
   - All notifications, error dialogs, and toasts adhere strictly to Dizzy Copy Deck (no technical words like "socket", "timeout", "debrid", "scraper").
