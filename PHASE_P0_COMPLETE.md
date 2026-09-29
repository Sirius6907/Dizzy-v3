# PHASE P0 — Baseline Snapshot

**Date:** 2026-09-29
**Repo:** `C:/Users/opcha/Downloads/Dizzy-v3` · **Branch:** `main` · **Mode:** read-only (no code changes)
**Worker scope:** P0 → P10. This file is the only file created by this phase.

All numbers below were produced by commands run in this session. Nothing is
copied from prior reports except where explicitly labelled as a *claim* under
verification.

---

## 1. Git baseline

| Item | Value |
|---|---|
| Branch / upstream | `main` → `origin/main`, **ahead 8, behind 0** |
| Latest tag | `v1.2.1` @ `0aa85a3` ("chore(v1.2.1): version bump…") |
| Commits since `v1.2.1` | **8** |
| Uncommitted entries | **75** (47 `M`, 1 `D`, 27 `??`) |
| Tracked diffstat | **48 files changed, +1999 / −2008** |
| Pushed / tagged by this phase | none |

Commits ahead of `v1.2.1` (newest first):

```
e96f8f7 feat(party): zero-dep native share sheet for watch invites
ae1eb69 fix(party): host failover pushes immediate host_state so guest follows
cc744a2 test(party): pin late-join catch-up room-row contract
0a528fe fix(party): same-title host jumps resync guest instead of toast-only
96540a2 fix(party): guest opens near host position + auto-open chain tests
068480d fix(party): public-list join starts guest session like code join
7d31d85 feat(social-sync): tactile OLED theme, instagram profile, DMs & 3 rooms
962be14 fix(stability): download network auto-pause, stream probe race timer
```

Notable working-tree state: `lib/pages/settings/appearance/liquid_glass_settings_page.dart`
is **deleted but unstaged**; `lib/pages/settings/appearance/tactile_theme_settings_page.dart`
and `lib/pages/settings/download_settings_page.dart` are **new but untracked**.

## 2. Toolchain

| Item | Value |
|---|---|
| Flutter | **3.47.2** · stable · rev `d3b14c8769` (2026-08-26) |
| Dart | **3.13.2** (DevTools 2.60.0) |
| `pubspec.yaml` SDK constraint | `^3.11.5` (satisfied by 3.13.2) |
| SDK location | `C:\Users\opcha\flutter` — **not on `PATH`**, must be added per shell |

`flutter analyze --no-pub`:

```
Analyzing Dizzy-v3...
No issues found! (ran in 90.2s)
```

**Errors: 0 · Warnings: 0 · Info: 0. No offending files.**

Note: run with `--no-pub` (no network dependency resolution). Analyzer is clean
but this only proves the code *compiles*, not that it *runs* or *builds* — see
Risk R4.

## 3. Tests

| Item | Value |
|---|---|
| `test/**/*_test.dart` | **116 files** |
| Total lines under `test/` (all `.dart`) | **9,439** |
| Top-level test dirs | **11** |

```
copy  download  helpers  integration  models  security
services  share  utils  watchparty  widgets
```

The implementation report claims "115 `*_test.dart` files". Measured value is
**116** — the delta is `test/share/native_share_test.dart`, added by `e96f8f7`
(commit `e96f8f7` is ahead of the tag but the report was written against the
115-file state). The report is stale by exactly one file, not wrong in kind.

Test-to-LOC ratio: 9,439 test lines vs 161,687 lib lines ≈ **5.8%**.

## 4. Sizes

| Path | Lines |
|---|---|
| `lib/` total | **161,687** across **466** `.dart` files |
| `lib/pages/player/watch_screen.dart` | **3,554** |
| `lib/pages/home/home_page.dart` | **2,102** |
| `lib/main.dart` | **284** |

Largest files in `lib/` (god-file risk):

```
3554  lib/pages/player/watch_screen.dart
3191  lib/pages/player/player_screen.dart
2578  lib/pages/iptv/iptv_portal_browser_page.dart
2118  lib/pages/details/details_page.dart
2102  lib/pages/home/home_page.dart
1937  lib/pages/audiobooks/audiobook_player_screen.dart
1850  lib/services/trakt/trakt_service.dart
```

`watch_screen.dart` at 3,554 lines is 2.2% of the codebase in one file and is
already touched by 3 of the 8 unpushed commits.

## 5. Documentation — top 5 known blockers/risks

Sourced from `docs/DIZZY_40_PHASE_MASTER_BLUEPRINT.md` (Part D), then each one
**independently re-verified against the code**. Three of the five claims in the
docs did not survive verification.

1. **`liquid_glass_easy` removal incomplete** — blueprint Part D.1: "imported by
   ~15 files". **Verified: 16 files still import it** (incl. `watch_screen.dart:9`),
   and the dependency is still declared at `pubspec.yaml:61`.
2. **`glass_settings.dart` not deprecated** — blueprint Part D.3 says ~20
   references. **Verified: file still live (317 LOC), 8 referencing files.**
3. **Watch Together guest autoplay not integration-tested** — Part D.4. **Verified:
   the Phase 10 deliverable `test/media/conflict_resolution_test.dart` and the
   whole `test/media/` directory do not exist.**
4. **Light theme needs a hardcoded-colour sweep** — Part D.6, unquantified.
5. **Phase 39 release build verification never run** — report §1 marks it
   "Out of scope (not run) / left for user". No APK or Windows artifact has ever
   been produced in this repo's recorded history.

### 5a. Claims that FAILED verification

| Report claim | Measured reality |
|---|---|
| Phase 1 "Kill GPU shader blurs — Complete" | **39 live `BackdropFilter` usages across 27 files.** 16 files import `liquid_glass_easy`; `pubspec.yaml:61` keeps the dep. |
| Phase 23 "Discover `BackdropFilter` fix — Complete" | **TRUE.** `discover_page.dart` has zero `BackdropFilter`/`ImageFilter`. |
| Phase 21 / 1 (Home) "Complete" | **TRUE.** `home_page.dart` has zero `liquid_glass_easy` and zero `AnimatedAmbientBackground`. |
| Phase 10 "AV conflict wiring — Complete (`attach` in `main.dart`)" | **FALSE.** `main.dart:136` calls `GlobalMediaCoordinator.instance.attach()` only. `notifyVideoStarted()` / `notifyVideoStopped()` are **defined at `global_media_coordinator.dart:55,77` and have zero call sites in `lib/`**. Music never pauses when video starts. |
| Phase 29 "Deprecate `glass_settings.dart`" | **FALSE.** No `@Deprecated`. `lib/services/music/music_settings.dart:20` still ships a user-facing preset named **"Liquid Glass Sanctuary"** whose description reads *"Deep optical refraction glass sheets powered by liquid_glass_easy"* — the banned term is still shown to end users. |

The Phase 1 status is the material finding: the report marks it "Complete
(prior work)" in the same table where the blueprint's own Part D lists the same
work as a blocker. Both cannot be true, and the code says the report is wrong.

**Doc path discrepancy (minor):** the blueprint (Phase 40, Part F) points at
`docs/DIZZY_40_PHASE_IMPLEMENTATION_REPORT.md` and `docs/DIZZY_TACTILE_GUIDELINES.md`,
but both files actually live at **repo root**. No `docs/DIZZY_TACTILE_GUIDELINES.md` exists.

**Silent-catch triage (`docs/silent-catch-triage.md`):** the policy itself is
sound and enforced — network/parse catches stay silent-but-logged with enum codes
only, state/payment/auth catches surface Easy English. No action needed. The one
exposure it names is 179 extractor files deliberately left un-instrumented; that
is a accepted, documented trade-off, not a defect.

## 6. Risks

| ID | Risk | Severity | Evidence | Impact if unaddressed |
|---|---|---|---|---|
| **R1** | OLED rule violated: 39 `BackdropFilter` + 16 `liquid_glass_easy` imports + live pubspec dep | **High** | `grep` sweep, 27 files | The design system's central constraint is unmet on 27 screens; 120 FPS goal (Phase 33) is unverifiable |
| **R2** | AV conflict resolution is dead code | **High** | zero call sites for `notifyVideoStarted`/`notifyVideoStopped` | Video and music play simultaneously; report claims this shipped |
| **R3** | Unbacked work: 75 uncommitted entries + 8 unpushed commits | **High** | `git status`, `git log v1.2.1..HEAD` | Two layers of unrecoverable work; a bad `reset`/checkout loses the social-sync + tactile work |
| **R4** | Zero release-build evidence | **High** | report §1 marks Phase 39 "not run"; no build artifacts | 161k LOC has never produced an APK/EXE; analyzer-clean ≠ ships. Every other claim rests on this untested foundation |
| **R5** | Docs contradict code on 3 of 5 spot-checks | **Medium** | §5a table | Planning is built on a false completion map; P1–P10 sequencing will be misdirected |
| **R6** | `glass_settings.dart` live + user-visible "Liquid Glass" preset | **Medium** | `music_settings.dart:20` | Banned jargon + a dead settings engine ship to end users |
| **R7** | Test coverage 5.8% of LOC, no AV/media test dir | **Medium** | 116 files / 9,439 lines | Regressions in the 3.5k-line player are caught only manually |
| **R8** | `watch_screen.dart` 3,554 lines, hot in 3 unpushed commits | **Medium** | LOC sweep | High merge-conflict and regression blast radius for P1–P10 |
| **R9** | Flutter not on `PATH` | **Low** | `flutter: command not found` at `C:\Users\opcha\flutter\bin` | Every worker will burn time rediscovering the SDK path |

## 7. Recommended first action for P1

**Run a real release build before any code changes — `flutter build apk --split-per-abi` — and treat it as a gate.**

Rationale: `flutter analyze` is clean and 116 test files exist, but this repo has
**never produced a release artifact**. R4 sits underneath every other risk —
while there is no build, "Phase N is complete" is a statement about type-checking,
not about the app. One build pass either (a) clears the foundation and makes
P1–P10 planning trustworthy, or (b) surfaces a first-run failure that invalidates
the entire 40-phase completion map, which is cheap to learn and expensive to
discover at P9.

Immediately after, in order: close **R2** (wire `notifyVideoStarted`/`Stopped`
into `WatchScreen` + add the missing `test/media/` test — small, self-contained,
and currently a silently broken feature), then **R1** (finish the
`liquid_glass_easy` removal: 16 files, dependency already being deleted from
settings, so the tail is shorter than the history suggests), then **R3**
(land the 75 uncommitted entries behind a commit before touching anything else).

---

## Command log

| # | Command | Result |
|---|---|---|
| 1 | `git status --short --branch` | ahead 8; 47 M / 1 D / 27 ?? |
| 2 | `git diff --stat \| tail -5` | 48 files, +1999 / −2008 |
| 3 | `git log origin/main..HEAD --oneline` | 8 commits |
| 4 | `git tag --sort=-creatordate \| head -5` | `v1.2.1, v1.2.0, v1.1.9, v1.1.8, v1.1.7` |
| 5 | `git log v1.2.1..HEAD --oneline` | 8 commits (listed §1) |
| 6 | `flutter --version` | 3.47.2 stable, Dart 3.13.2 |
| 7 | `flutter analyze --no-pub` | **No issues found!** (90.2s) |
| 8 | `find test -name "*_test.dart" \| wc -l` | 116 |
| 9 | `find lib -name "*.dart" -exec cat {} + \| wc -l` | 161,687 (466 files) |
| 10 | `wc -l` on 3 key files | 2102 / 3554 / 284 |
| 11 | `grep -rl "liquid_glass_easy" lib/` | 16 files; `pubspec.yaml:61` |
| 12 | `grep -rn "BackdropFilter" lib/` | 44 raw → **39 real** (5 in comments) across 27 files |
| 13 | `grep -rn "notifyVideoStarted(" lib/` | definition only, **0 call sites** |
| 14 | `ls test/media` | **does not exist** |
