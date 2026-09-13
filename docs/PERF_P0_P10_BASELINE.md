# Dizzy Perf P0–P20 — Soak Baseline & Before/After

## How to reproduce the 30–40min overheat (P0/P14)

1. Build the release APK / EXE from this tree.
2. Gate check first: `scripts/perf_audit.ps1` must print
   `All perf gates pass.` (fails the build on any regression:
   uncapped image, fast player timer, unpaired wakelock, …).
3. Start the monitor (Windows):
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/resource_monitor.ps1 -ProcessName Dizzy -Minutes 45 -OutCsv soak_after.csv`
4. Play a 1080p episode over WiFi, browse 2–3 catalog rows mid-play, leave
   it running 40 min. Note any OS heat warning + timestamp.
5. Compare `soak_after.csv` against the pre-fix expectations below.
   PASS = RAM flat (±150MB drift), no `BREACHx2` rows, no OS warning.

## Hard budgets (all phases)

- Phone RAM ≤ 1800MB RSS · Desktop ≤ 2800MB · CPU ≤ 20% · GPU ≤ 2560MB
- Probe race: 8 parallel / 120 queue · Scrapers: 10 parallel / 20 queue
- Addons: 10 parallel chunks · Downloads: 2 parallel
- Images: 200 entries / 150MB (phone), 500 / 300MB (desktop)

## Before → After (P0–P10)

| # | Area | Before | After |
|---|------|--------|-------|
| P0 | Monitoring | sampler only inside player | governor starts with app + `scripts/resource_monitor.ps1` soak harness |
| P1 | Image RAM | 500/300MB everywhere, ~51 uncapped decodes, whole-chapter precache | 200/150MB on phones, `DizzyImage` capped widget, wallpaper+music caps, manga precache = next 3 @960px |
| P2 | Ambient/glass | 12s infinite ticker + CustomPaint on 22 pages, glass always live | `PerformanceMode` gates: ticker stops + subtree unmounts on caution+, glass → flat fallback |
| P3 | Player buffers | 64MB/20s mobile, 150MB desktop, probe 32MB/20s, de-escalate re-forced 150MB | Eco/Medium/Max profiles (medium default 48MB/12s), probe 8MB/5s, de-escalate restores profile |
| P4 | Scrape fan-out | 40+ scrapers + all addons parallel (pre-play socket bomb) | 10-parallel scraper pool + 20 queue + shed, 10-chunk addon pool |
| P5 | Timers | quality 2s, progress 5s, stall 2s | quality 5s, progress 10s (+flush on pause/exit), stall 5s |
| P6 | Downloads | unbounded parallel | max 2 active, oldest-queued pump on terminal state |
| P7 | Music/manga | waveform tickers @display fps even paused, full-chapter precache | tickers play-gated, precache 3-ahead capped |
| P8 | Background | downloads+discord run while app hidden | auto-suspend on hide, auto-resume on return; **voice untouched (room-exit only)** |
| P9 | Governor | thresholds only drove player | also drives `PerformanceMode` (ambient/glass/buffers shed together) |
| P10 | Network | single-shot master fetch, probes already tight | `NetRetry` 3-attempt 1s/2s/4s+jitter on rendition fetch; probes intentionally retry-free (4s drain) |

## Files added

- `lib/utils/perf/performance_mode.dart` (+ `test/performance_mode_test.dart`, 5 tests)
- `lib/utils/net/net_retry.dart` (+ `test/net_retry_test.dart`, 8 tests)
- `lib/utils/perf/storage_guard.dart` (+ `test/storage_guard_test.dart`, 5 tests)
- `lib/widgets/common/dizzy_image.dart` (sanctioned capped image widget)
- `scripts/resource_monitor.ps1` (P0 soak harness)
- `scripts/perf_audit.ps1` (P14 gate: 6 checks, fails build on violation)
- `scripts/cap_images.py` (P12 codemod, idempotent, `--apply` to write)
- `docs/PERF_ROLLOUT.md` (P13 platform matrix + P19 staged rollout)

## P11–P20 before → after

| # | Area | Before | After |
|---|------|--------|-------|
| P11 | Storage | full disk = corrupt partials + stuck 0% tasks + buffer stalls; temp `.part` files never cleaned | `StorageGuard`: <500MB free or >90% used → downloads refuse (Easy English), prefetch stops, stale temps purged |
| P12 | Image leaks | 40+ uncapped decodes (quiz, music 22, audiobooks, manga full-chapter precache) | zero uncapped in lib (audit-enforced); manga pages capped 1280px (`kPage`); hero auto-rotation frozen on caution+ |
| P13 | Platform tuning | one-size-fits-all (150MB restore on phones, 2 downloads everywhere) | phone/desktop matrix enforced (see `docs/PERF_ROLLOUT.md`) |
| P14 | Soak proof | manual only | `perf_audit.ps1` gate + 45-min monitor procedure in this doc |
| P15 | Jank | poster bitmaps re-rastered on every row scroll/hover | `RepaintBoundary` on all 4 card image leaves |
| P16 | Wakelock | unaudited | audited: player/iptv/download(state-driven)/OTA all paired; audio needs none (audio focus) |
| P17 | UX | no user control over perf | Battery & Heat section: Smooth Mode switch + Eco/Balanced/Max cards, persisted, Easy English |
| P18 | Telemetry | blind after release | opt-in `perf_caution`/`perf_critical` logs (enums only) to admin dashboard |
| P19 | Rollout | — | staged 10% → 48h watch → 100%, rollback plan (`docs/PERF_ROLLOUT.md`) |
| P20 | (this report) | — | all 20 phases landed, verified below |

## Verification (this tree)

- `flutter analyze --no-pub lib` (entire lib): **clean**
- `scripts/perf_audit.ps1`: **all gates pass**
- Tests: storage 5 + perfmode 5 + netretry 8 + governor 7 + download/next_episode/image_caps 13 + scraper/stream 22 = **60 pass**
