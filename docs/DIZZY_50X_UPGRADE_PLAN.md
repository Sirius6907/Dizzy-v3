# Dizzy-v3 50x Upgrade Plan — v1.3.0 Zero-Tech Blast

**Date:** 2026-09-29
**Current:** v1.2.1+31, main ahead 8 commits, 48 dirty files, 466 dart files ~1.6L LOC
**Target:** v1.3.0 — backend, networking, logic, wiring, frontend, UI/UX, tutorial cards sab 50x
**Rules:** anonymous-first, adult-first (kids filter minimal/deferred), Easy English only, defaults ON, skipable guides, budgets ≤3GB RAM / ≤2.5GB VRAM / ≤20% CPU, no tag/push bina bole

---

## 🎯 Vision

Dizzy ko non-tech user ke liye 30-sec me samajh aane wala bana do. Backend silent-fail khatam, networking retry-smart, wiring 100% connected, UI tactile-OLED flagship, aur har feature pe cute skipable guide card. Watch Together 10x flawless + dead-easy rahega.

---

## 📦 Abhi ka haal (discovery)

- **Dirty tree:** 48 files changed (1999+/2008-), 8 commits ahead of origin/main — pehle freeze/commit bina aage kaam risky hai
- **Tutorial system chhota hai:** GuideService me sirf 5 keys (party_v2, downloads, cloud_sync, sources_health, subtitles), GuideCard simple dialog hai, Onboarding 3 slides only. Music studio, books, manga, anime, spotlight, my_list, EQ, offline, profiles, debrid, IPTV ke liye koi guide nahi
- **Networking silent hai:** 304 jagah `catch (_)` — error dab jaata hai, user ko pata nahi chalta, admin ko log nahi milta
- **Monolith screens:** home_page ~2000 lines, watch_screen ~3554 lines — split chahiye (views/widgets/modals)
- **Backend:** schema_v119 + 15 migrations, 20260920_social_sync wala migration dirty hai, admin-dashboard me realtime device-log view missing
- **Good news:** scraper names unique hain (koi collision nahi), 40-phase tactile system complete hai, RLS + anonymous-first verified hai

---

## 🏗️ 10 Blocks (P1-P10)

### P1 — Freeze + Health Gate (sabse pehle, 1 din)
- `git diff --stat` audit, 48 dirty files ko commit/stash, untracked tactile + social files ka faisla
- `flutter analyze` zero-issues, touched tests, full tests
- Koi feature code nahi — sirf clean base
- Done = clean tree + green analyze

### P2 — Backend 50x
- Supabase: device_logs table (per-device tech errors), error pipeline RPC, feature-flags table, catalog cache hardening
- Dirty migration `20260920_social_sync_foundation.sql` ko finalize + verify
- RLS re-verify (profiles, rooms, room_members, room_messages, dm_messages, friendships)
- Admin-dashboard me realtime device-log view (per-device filter)
- App user ko sirf Easy English, tech error sirf admin server pe
- Done = migration apply OK + admin me live log dikhe

### P3 — Networking 50x
- Ek `DizzyNet` client: retry + jitter + backoff, `onTimeout` synthetic response (Future.timeout Stack Overflow wala footgun hatao), offline queue, per-host circuit breaker
- Debrid 5 providers ka failover order (real-debrid → torbox → alldebrid → premiumize → debrid-link), swarm stats + port allocation tune
- Har provider `Future.wait` me apna error khud handle kare, ek fail to global fail nahi (`catch (_) => []` pattern)
- connectivity_plus auto-pause ko `offline_aware_scaffold` + `offline_banner` se har screen pe jodo
- 304 silent-catch ka triage: user-facing jagah pe Easy English toast + admin log, internal jagah pe debugPrint
- Done = airplane-mode test + slow-network test pass, koi silent dead screen nahi

### P4 — Logic + Wiring audit
- Har `ensure*` / `init*` / `sync*` ka call-site grep — bina call wala = dead code, turant jodo ya hatao
- AV conflict: WatchScreen → GlobalMediaCoordinator.notifyVideoStarted wiring verify
- Watch Together 10x: host failover, same-title resync, guest near-position open, late-join catch-up, 20s resolve countdown UI — sab pe integration test
- Scraper quarantine → settings health page wiring verify, dead scraper auto-quarantine + Easy English badge
- Done = zero dead wiring, party ke 6 recent fix pe regression test green

### P5 — Frontend modularization
- home_page + watch_screen ko todo: `views/` + `widgets/` + `modals/` me todo, parent sirf orchestrator
- Public constructors me `{super.key}` (use_key lint), relative imports check, orphan files delete (grep ke baad hi)
- Universal spotlight: multi-domain omnisearch, ID dedup via Set, Ctrl+K root shortcut
- Done = analyze clean + navigation smoke pass

### P6 — UI/UX 50x
- Tokens freeze: DizzyTokens + DizzyTactile single source, font family global unify, legacy hex grep-sweep
- Narrow-screen <420 compact contract har app-bar pe (flag-only pill, 36px buttons)
- Desktop: dragDevices + vertical-to-horizontal wheel wrapper har horizontal rail pe
- Empty states (DizzyEmptyState), skeleton loaders, Semantics labels, haptics, 120fps governor
- Music: ambient canvas (16x16 palette + HSL fallback), karaoke anti-jerk guard (3.5s pause on user scroll), queue reorder mapping, FLAC/HQ badges + hot-swap at position, Song Radio + Smart Mix
- Done = 360px emulator pe zero overflow, wheel/drag smooth

### P7 — Tutorial cards 50x (flagship)
- GuideService v2: ~25 keys — home, spotlight search, movie, anime, manga, music studio, EQ, books reader, audiobooks, downloads hub, offline mode, my_list, profiles/PIN, debrid, IPTV, calendar, stats, subtitles, sources health, cloud sync, party v2, DMs, social hub, accent studio, appearance
- GuideCard 2.0 tactile: max 3 steps, big icon + 1-line Easy English, dots, Next/Skip, Skip = kabhi mat dikhao, Settings → Help → Show again
- Onboarding 2.0: 5 slides (Everything one place, Lossless music, Watch together, Offline + downloads, Private + safe) — 30-sec tour, ek bar only
- Trigger: har screen ke initState post-frame `maybeShow`, barrierDismissible false, progress dots
- Copy rule: koi tech word nahi, 1 line = 1 kaam, emoji icon OK
- Done = fresh install pe har feature pehli bar card dikhaye, Skip dabane pe dobara kabhi na aaye, Help se wapas aaye

### P8 — Admin + observability
- Per-device logs realtime (device code → logs), tech-error feed, scraper quarantine dashboard, feature-flag toggles
- App me koi stacktrace nahi — sab admin pe
- Done = user ka crash admin me 10s me dikhe

### P9 — Perf + budgets
- Startup <2s, RAM ≤3GB, VRAM ≤2.5GB, CPU ≤20%, APK split-per-ABI (~50MB), live resource monitor on test launches
- Done = budget gate green

### P10 — Release prep
- CHANGELOG, version bump, copy-deck audit, full tests, release build verify — tag/push sirf tere "kar de" bolne pe
- Done = user tested EXE/APK OK

---

## 🌟 5 Feature Tracks (fully functional upgrades)

Ye 5 infra ke upar user ko dikhne wale, independently shippable, demo-ready features Hain. Har ek "adhoora-karcha" se "poora-kamaal" tak jayega.

### F1 — One-Tap Instant Play (playback jo bas chale)
- Tap → stream race → pehla valid source turant auto-play, koi server-picker rok nahi
- Smart quality: bandwidth meter se auto ladder, Data Saver 720p cap, weak device pe AV1 dodge (H264 pehle)
- Hindi-dub gate: audio language tag se preferred track auto-select
- Skip intro/credits auto-skip (settings me ON by default, skipable card ke saath)
- Failover: source mare to picker bina rukawat next pe, Easy English toast ("Trying next source…")
- Done = airplane-off se first-frame <5s, failover me playback ruke nahi

### F2 — Smart Offline Hub (downloads jo khud samajhdar Hain)
- Auto-next: WiFi pe agla episode khud download, mobile data pe sirf poochhe
- Storage guard: jagah kam to purana-watched auto-delete (poochh ke, 1-tap undo)
- Quality profiles: WiFi-1080p / Data-720p / Saver-480p, per-network auto
- Har download pe progress + pause/resume + retry, HLS + torrent + HTTP sab pe
- Done = 10-episode season 1-tap me offline, storage full kabhi error na de

### F3 — My Dizzy (kabhi jagah mat bhoolo)
- Continue Watching cross-device: max(progress) merge, reinstall pe wapas
- My List + custom lists per-profile, PIN lock (adult-first — kids filter minimal, deferred)
- merge_devices RPC: purana anon data + naya device, watchlist/history/friends bina overwrite jude
- Done = naya phone lo, code dalo, sab kuch wapas — zero-tech user bhi kar le

### F4 — Together Cinema (flagship, 10x flawless + dead-easy)
- 1-tap room code + native share sheet, guest khule to host ke paas auto-open
- Queue voting (add/move/remove op-log), emoji reactions, LiveKit voice + chat
- Late-join catch-up: beech me aao to current position pe seedha
- DM me media card bhejo → tap → dono seedha sync room me (Watch/Listen/Read)
- Done = 4 dost, 3 network, 0 drift complaint, dadi bhi join kar le

### F5 — Discover Daily (roz kuch naya)
- Personalized rails: "Kyunki tumne X dekha", Smart Mix music, mood quiz → tonight's picks
- New-episode alerts + calendar reminders (local notification, login bina)
- Yearly Wrapped: binge stats, streaks, shareable card
- Done = roz home kholo to kuch naya mile, 7-day retention up

---

## 📊 Success metrics

| Metric | Abhi (v1.2.1) | Target (v1.3.0) |
|---|---|---|
| Guide coverage | 5 keys | ~25 keys + onboarding 2.0 |
| Silent catch | 304 | 0 user-facing silent (sab logged + Easy toast) |
| Monolith screens | home 2000, watch 3554 lines | split views/widgets/modals |
| Dead wiring | unknown | 0 (grep verified) |
| Narrow-screen overflow | risky | 0 on 360px |
| Startup | unmeasured | <2s |
| Party sync drift | low | ~zero + countdown UI |

---

## 🚨 Breaking changes

**None.** Anonymous-first, guest-mode, local prefs sab same rahenge. Purane guide_seen flags migrate honge, dobara nag nahi hoga.

---

## 🛡️ Risks

| Risk | Impact | Plan |
|---|---|---|
| 48 dirty files bina freeze aage badhna | High | P1 me commit/stash pehle, rollback base ready |
| Networking refactor se playback tutna | High | Scrapers/resolvers ko wrap mat karo, sirf client layer badlo + playback smoke har step pe |
| Scope creep (55 screens ek saath) | Med | Phase 1 me 8 daily screens, baaki Phase 2 |
| Parallel edits me file collision | Med | Ek file ek worker, shared tokens serialize + analyze har batch pe |

---

## ✅ Done matlab

- [x] P1 clean tree + green analyze
- [x] Har feature pe guide card + Help se wapas
- [x] Koi silent dead screen nahi, admin me live logs (P8 residual: consent default ON 2026-10-06)
- [x] 360px pe zero overflow, desktop wheel/drag smooth
- [x] Party 10x flawless + countdown UI
- [x] Budgets green, user tested build OK, tag sirf bolne pe (v1.3.1)

**Status:** EXECUTED — P1-P10 shipped across v1.3.0 (2026-09-29) & v1.3.1 (2026-10-02).
Remaining residuals now tracked in `.hermes/plans/2026-10-06_105652-dizzy-full-proof-roadmap.md`:
P3 partial (DizzyNet adoption = Phase 4 of that plan), P8 partial (error pipeline live,
consent default ON 2026-10-06). Superseded for planning purposes by that roadmap.
**Approval:** @Sirius

---

## 🤖 Delegation — 2 workers, phase by phase (steered + monitored)

**Split:** opencode CLI → P0-P10 infra (main tree). kilo CLI → F1-F5 features (worktree `../Dizzy-v3-F`, branch `f-track`).
**Models:** opencode = `opencode/space-bunny-free` (smoke OK). kilo = `kilo/stealth/space-bunny-alpha` (roll-call OK 1.2s).
**P0** = baseline read-only (versions, analyze tally, test inventory, report — no code). Then P1-P10 as planned.
**Launch:** one-shot `run` per phase (background + notify). Fresh context each run → prompt file carries full scope + ownership + quality gates.
**Monitor loop (me):** run completes → poll logs → scoped `flutter analyze` + touched tests MYSELF → pass = next phase, fail/drift = steer message + re-run. Never trust self-reports for side effects.
**Collision guard:** strict file ownership per prompt; shared files = additive-only or forbidden. Merge `main` → `f-track` before kilo F5 (discover/ai pages owned by opencode freeze).
**Iron rules (every prompt):** highest quality (strict null-safety, zero new lints, super.key, const), Easy English UI only, anonymous-first, adult-first (kids filter deferred), no tag/push, no wrapping scrapers/resolvers, commit per phase, budgets ≤3GB/≤2.5GB/≤20%.

**Agent:** kilo CLI v7.7.9, auth = Kilo Gateway oauth (balance $0 — sirf free models).
**Best free model (benchmarked 2026-09-29, roll-call + Dart retry code test):**
- Primary: `kilo/inclusionai/ling-3.0-flash-sante:free` — hello 1.4s, clean idiomatic code 7.7s
- Backup (code-specialist): `kilo/poolside/laguna-s-2.1:free` — hello 2.4s, solid code 7s
- Heavy backup: `kilo/nvidia/nemotron-3-super-120b-a12b:free` — best code quality, slow 16s (bade refactors only)
- Dead/avoid: qwen3.8-27b, inkling-small, laguna-xs (rate-limited), nemotron-lightning (timeout), north-mini-code (slow + buggy return)
**Command pattern:** `kilo run '<phase prompt>' -m kilo/inclusionai/ling-3.0-flash-sante:free --dir <worktree>`
**Worktrees:** `kilo worktree create batch-<x>` — har worker apne worktree me, shared files serialize.
**Collision guard:** ek file ek worker. Har run ke baad scoped `flutter analyze <touched files>` + touched tests (full analyze parallel me RAM phodega — budget ≤3GB, max 3 parallel workers).
**No tag/push:** agent commit kare, tag/release nahi. Playback scrapers ko wrap nahi — sirf client layer.
**Adult-first:** kids filter minimal/deferred — F3 me sirf PIN + profiles, koi adult-filter lock-in nahi.

### Option C batches (P1 serial, phir parallel)

- **Batch 0 (serial, 1 worker):** P1 freeze — 48 dirty files audit, commit/stash, green analyze baseline. Iske bina kuch nahi.
- **Batch A (parallel ×3):** A1=P2 backend (owns supabase/, admin-dashboard/, error pipeline) · A2=P3 networking (owns lib/services/net NEW, debrid providers, download net layer) · A3=F3 my-dizzy (owns models/my_list, continue_watching, profiles, pages/my_list)
- **Batch B (parallel ×3):** B1=P4 wiring (owns media coordinator, main.dart wiring, party engine, tests/watchparty) · B2=F2 offline hub (owns services/download, pages/downloads) · B3=P9 perf (owns services/system, utils/perf)
- **Batch C (serial, watch_screen collision):** C1=P5 split (2 workers disjoint: home vs player) → phir C2=F1 instant play (player logic + stream, no scraper wrap)
- **Batch D (parallel ×3):** D1=P6 UI/UX (owns design/, widgets/common, music widgets) · D2=F4 together cinema (owns party pages/widgets, queue voting, media cards — engine B1 ka, UI D2 ka) · D3=F5 discover (owns pages/discover, services/ai quiz, calendar)
- **Batch E (serial last):** E1=P7 guides (services/guide, widgets/guide, onboarding + per-screen triggers — screens stable hone ke baad) → E2=P8 admin (admin-dashboard realtime logs, P2 ke baad) → E3=P10 release (version, changelog, copy audit — tag sirf bolne pe)
