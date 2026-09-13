# Dizzy Perf — Platform Matrix (P13) & Rollout (P19)

## P13 — per-platform hard budgets (enforced in code, not docs)

| Knob | Android / iOS | Desktop (Win/Linux/macOS) | Where |
|---|---|---|---|
| Image mem cache | 200 entries / 150MB | 500 / 300MB | `main.dart` |
| Demuxer (Balanced) | 48MB / 12s | 120MB / 12s | `PlayerSettings` |
| Demuxer (Eco) | 32MB / 8s | 64MB / 8s | `PlayerSettings` |
| Demuxer (Max) | 64MB / 20s | 150MB / 20s | `PlayerSettings` |
| Torrent buffer | 64MB (DS 32MB) | 120MB | `PlayerSettings` |
| RAM budget | 1800MB | 2800MB | `ResourceGovernor` |
| Downloads parallel | 2 | 3 | `DownloadService` |
| Anime4K | allowed (user pref) | blocked ≤4GB VRAM | `PlayerSettings` |
| Smooth Mode default | ON if ≤3GB RAM | OFF | `main.dart` |

Rules: phone values NEVER exceed the mobile column even after
governor de-escalation (P3 bug fixed). Desktop keeps full quality.

## P19 — rollout (no tag without manual test — standing rule)

1. **Internal soak (this tree):** 45-min monitor run
   `scripts/resource_monitor.ps1 -Minutes 45` → zero `BREACHx2`,
   zero OS heat warnings. `scripts/perf_audit.ps1` must pass.
2. **10% staged rollout:** Play release with staged rollout 10%.
   Watch admin `perf_caution` / `perf_critical` (opt-in) counts for
   48h. Spike vs baseline = halt, rollback to previous release.
3. **Full rollout:** 100% after 48h clean. Keep previous APK/AAB
   + installer EXE archived for one-click rollback.
4. **Post-release:** weekly admin perf review (P18 telemetry);
   any device family >5% critical rate gets a profile retune
   (Eco default for that RAM class).

## Rollback

- Code: every phase is additive + gated (old behavior = gates open).
  `git revert` per phase, or full-tree rollback to the pre-perf tag.
- Runtime: Smooth Mode + Eco profile give users an instant local
  fallback without waiting for a release.
