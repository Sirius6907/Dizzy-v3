# PHASE P2 — Backend 50x: the error pipeline that actually lands

**Date:** 2026-09-29
**Repo:** `C:/Users/opcha/Downloads/Dizzy-v3` · **Branch:** `main` (ahead of `origin/main` by 25)
**Mode:** backend + infra. No auth flows, no RLS edits on existing user tables, no player/stream/scraper logic, no design tokens, no pushes, no tags.
**Worker scope:** P0 → P10. Baseline is `PHASE_P1_COMPLETE.md`.

---

## 1. What landed

5 commits, **7 files** changed (+700 / −54).

| # | Hash | Commit | Files |
|---|---|---|---|
| 1 | `7ec11ca` | `feat(backend): device_logs table, report_error RPC and report-error edge` | 2 |
| 2 | `8cad69a` | `feat(backend): close the error-pipeline privacy hole and land server flags` | 2 |
| 3 | `cd94e53` | `feat(admin): device logs view in the control dashboard` | 2 |
| 4 | `9593849` | `test: error pipeline coverage (19 tests, first real suite signal)` | 1 |
| 5 | this file | `chore(p2): error pipeline complete` | 1 |

| File | ± |
|---|---|
| `supabase/migrations/20260929_error_pipeline.sql` | +164 (new) |
| `supabase/functions/report-error/index.ts` | +108 (new) |
| `lib/services/errors/app_error_log.dart` | +213 / −52 |
| `lib/services/config/feature_flags.dart` | +117 |
| `admin-dashboard/app.js` | +62 |
| `admin-dashboard/index.html` | +17 |
| `test/services/error_pipeline_test.dart` | +200 (new) |

Nothing outside the ownership list was touched. `git status` after landing shows
only `?? memory/2026-09-21.md`, the same personal note P1 deliberately left.

## 2. The headline finding: the contract was documented but never enforced

`app_error_log.dart` opened with a privacy contract — *"NEVER: URLs, magnets,
tokens, titles, stack traces, raw exception text"* — and then did not enforce a
single word of it. The `detail` field was capped at 64 characters, which is a
length limit, not a privacy control.

The callers proved the point:

```
lib/core/error_boundary.dart:20   detail: '${details.exception}'…
lib/core/error_boundary.dart:30   detail: '$error'…
```

Every framework error and every uncaught async error in the app was being
serialised into the `detail` column. Raw exception messages, hostnames, and any
URL embedded in a message all qualified. The 64-char cap made it *worse*,
because a truncated stack frame is still a data leak — it just leaks less
obviously.

`error_boundary.dart` is outside this phase's ownership, so the fix lands where
the phase does have authority: `buildPayload` is now the gate, and it is
load-bearing rather than advisory. Each free-form field is matched against its
allowlist **as a whole** and replaced when it does not match. Whole-string
matters — partial stripping is not a sanitiser, because
`"Bad state: no element"` becomes `"badstatenoelement"` and still leaks the
words. A rejected `detail` becomes the literal `redacted`, so a misbehaving
call site is *visible* in the new dashboard instead of silently discarded.

The same gate exists a second time in the edge function and a third time in the
RPC. Three layers is deliberate: the client is the one that can be bypassed by
a future caller, the server is the one that cannot be bypassed at all.

Codes also needed normalising. Three live call sites send uppercase —
`E_FLUTTER`, `E_ASYNC`, `E_USER_REPORT` — which the mandated
`^[a-z0-9_]{1,48}$` allowlist would have rejected outright. They are lowercased
at the gate, so those reports land instead of vanishing.

## 3. What now works end to end

Before: `AppErrorLog.log()` → local queue (cap 100) → `functions.invoke('report-error')` → **HTTP 404, forever**. Entries accumulated, drop-oldest silently discarded the oldest, and no telemetry ever existed. The header even said so: *"Until the edge + `app_logs` table exist, sends fail soft and stay queued."*

After: `log()` → queue → `drain()` → `report-error` edge → `report_error()` RPC → `device_logs` row → admin dashboard.

- **Storage** — one row per `(device_code, screen, code, detail)`; repeats fold
  into `count`, `last_at` bumps, `first_at` is preserved. 10 000 timeouts from
  one install cost one row, not 10 000.
- **Volume control** — the RPC rejects a 51st report event from a device inside
  a rolling 24h. This is the control that actually holds (§5).
- **Writes** — `report_error` is `SECURITY DEFINER` and the *only* writer. The
  table has no INSERT policy at all, and is revoked from `anon`.
- **Reads** — `SELECT` gated on `is_admin()`. The dashboard authenticates with
  the anon key, so without the policy the tab would simply be empty.
- **Rejections are consumed, not retried** — a bad code or a capped device
  answers `200 {ok:true, stored:false}`. Answering 4xx would have made the
  client hold the entry and retry it forever, pinning the queue at 100.

## 4. Gates

| Gate | Result |
|---|---|
| `flutter analyze` (whole repo) | **No issues found!** (39.8s) — matches P0/P1's 0/0/0 |
| `flutter analyze` (touched files) | **No issues found!** — 5 issues found and fixed on first pass |
| New tests | **19 passed**, 0 failed |
| **Full `flutter test`** | **646 passed · 24 skipped · 0 failed** (31s) |
| Full suite, P2 reverted (`git stash -u`) | **627 passed · 24 skipped · 0 failed** |
| Delta | **+19** — exactly the new file, **zero pre-existing tests disturbed** |
| `node --check admin-dashboard/app.js` | pass |
| Admin DOM contract (4 new IDs + nav + section present) | pass |
| Migration idempotency | `IF NOT EXISTS` / `CREATE OR REPLACE` / `DROP POLICY IF EXISTS` throughout |

**This is the first time the suite has ever been run.** P0 and P1 both recorded
"tests were never run" as a carry-forward. 646 pass and 0 fail means the risk
P1 flagged as an *assumption* is now a fact: 24 tests are skipped, and the 627
pre-existing tests that do run are green.

## 5. Two tests that failed first and caught real defects

Worth recording, because both were mine and both were caught before commit:

1. **`drain()` leaked the transport exception.** My first refactor moved the
   try/catch out to `flush()`. Production behaviour was unchanged, but `drain`
   is `@visibleForTesting` API with a documented return value, and it threw
   instead of returning `false`. Fixed by catching inside the loop, breaking,
   and persisting — restoring the original control flow exactly.
2. **`ServerFlags.isOn()` returned `true` for unknown keys.** The docstring
   claimed "unknown keys are OFF, never true"; the implementation was
   `current.value[key] ?? false`, so any key present in the map won. Fixed by
   checking membership against the shipped key set. An unrecognised flag name
   is a typo, and a typo must not enable a feature nobody built.

A third failure was my test being wrong, not the code: I asserted
`isOn('watch_party')` was `false` after blanking the map, but `watch_party`
ships as `true`. Corrected the expectation.

## 6. Risks for P3

**1. The client-side 24h throttle is cosmetic (Medium — carried, not fixed).**
P2 was told to keep throttle behaviour identical, so it is unchanged. But the
throttle only gates the *immediate* flush trigger; the entry is queued either
way, and `schedulePeriodicFlush()` runs every 15 minutes and drains the whole
queue regardless. So a looping install can push up to 100 entries per 15 minutes
client-side. What actually bounds it is the server-side 50-events-per-24h cap.
The throttle should either be reworked to gate the queue itself, or deleted as
misleading. **It is not a security control and should not be documented as one.**

**2. `device_code` is client-supplied and therefore spoofable (Low).** The rate
cap is keyed on it, so a caller can rotate codes to bypass the 50/day cap. The
table stores no PII, so the worst case is log pollution. Worth noting because
the cap looks stronger than it is; binding it to `auth.uid()` instead would
close it, at the cost of losing the "unknown" bucket for early crashes.

**3. Three live `AppErrorLog` call sites pass raw text, and P2 could not fix
them (Medium — needs an owner).** `error_boundary.dart:20,30` are the two
found by grep. The gate neutralises them, so nothing leaks, but the detail is
now the useless string `redacted` for every framework and async crash — the
highest-value reports in the system are the ones carrying the least
information. Whoever owns `lib/core/` should replace them with a real enum
(`framework_error`, `async_error`, `state_error`) and keep the exception text
in a local-only log.

**4. `flush()` has never executed against a live Supabase (Medium).** It is
type-checked, unit-tested against an injected transport, and its server half is
written to the same shape as the six sibling edge functions — but no request
has crossed a network. Deploying requires: apply the migration, then
`supabase functions deploy report-error`. Until then the client behaves exactly
as it did before, which is the correct failure mode.

**5. The migration is unverified SQL (Medium — same as P1's dirty migration).**
It is 164 lines of hand-written plpgsql and has never been executed. Two spots
deserve a second pair of eyes before it is run:

- The `ON CONFLICT (device_code, screen, code, detail) WHERE device_code <> 'unknown'`
  inference must match the partial unique index *exactly*, predicate included.
  A mismatch is a runtime error on the first real report, not at apply time.
- The rate cap sums `count` over rows whose `last_at` is inside the window. That
  is an approximation — a row folded 40 times over 3 days counts as 40. It
  over-counts, which is the safe direction for an abuse control, and the
  comment in the file says so.

**6. R6 wider than P1 measured (carry-forward, untouched).** P1 recorded 12
user-facing "Liquid Glass" strings. Out of P2 scope; P6.

## 7. Also worth carrying

- `ServerFlags` is a skeleton by design. The `feature_flags` table is P8. Until
  it exists every `isOn()` returns the fallback, and the fetch is skipped
  because the table is missing. This is intended, not broken.
- The dashboard device-logs tab polls `device_logs` directly rather than
  through an `admin_*` RPC. That matches how `announcements` and
  `remote_config` are already read, and RLS carries the authorisation. If a
  P8 audit log needs to know who read device logs, this will need an RPC.
- `dart:io` `Platform.isFuchsia` was added to `_platform()` so the client and
  the DB platform allowlist agree; the DB list was written from the client's.

## 8. Command log

| # | Command | Result |
|---|---|---|
| 1 | `git log --oneline -8` | baseline at `221b3d9` |
| 2 | `ls supabase/functions/` | 6 functions, **no report-error** — confirms the brief |
| 3 | `grep -rn "AppErrorLog.log" lib/ -A5 \| grep -oE "(code\|screen\|detail): '…'"` | 3 uppercase codes, **2 raw-text details** |
| 4 | `flutter test test/services/error_pipeline_test.dart` | 3 failures — `String(x)` invalid, drain threw, isOn wrong |
| 5 | `flutter analyze` (touched) | 5 issues → all fixed |
| 6 | `flutter analyze` (repo) | **No issues found!** (39.8s) |
| 7 | `flutter test test/services/error_pipeline_test.dart` | **19 passed** |
| 8 | `flutter test` | **646 passed · 24 skipped · 0 failed** |
| 9 | `git stash -u` + `flutter test` | **627 passed · 24 skipped** — baseline |
| 10 | `git stash pop` | tree restored |
| 11 | `node --check admin-dashboard/app.js` | pass |
| 12 | node DOM-contract check | 4 IDs + nav + section present |
| 13 | `git status --short` | only `?? memory/2026-09-21.md` |
