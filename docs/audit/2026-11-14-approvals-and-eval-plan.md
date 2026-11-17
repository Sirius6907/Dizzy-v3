# Dizzy - approvals + evaluation plan (2026-11-14)

Owner granted authority with one rule: **ask and explain before anything
critical**. Nothing below was executed against the live database or the
dashboard in this pass; it is the verified state plus the plan.

## 1. Supabase migration `20261113_username_device_continuity.sql` - VERIFIED, approve

Evidence (read-only):
- `supabase migration list --linked` (production `Dizzy-v3`,
  ref `tiasihuropxrbcxmxorj`): remote history row **20261113 exists**, but
  the local file is still marked *not applied* (`"local":"20261113",
  "remote":""`), plus `"local":"","remote":"20261113"`. The remote and the
  local ledger disagree.
- `GET /rest/v1/devices?select=previous_user_id` -> 200 (the column
  exists), and `claim_username` / `username_available` exist as functions
  (401 for anon = RLS doing its job). `device_boot` returns PGRST202 only
  because its parameter is named differently than I probed (and the
  PostgREST schema cache lags new functions).
- SQL review: every function is `security definer` with
  `set search_path = public`, `revoke all ... from public` +
  `grant execute ... to authenticated`, `username_available` explicitly
  revokes `anon`. DDL is idempotent (`add column if not exists`), and
  there are no table drops.

**Verdict: correct and safely written -> approve.** One behaviour to be
aware of: `device_boot` deletes `public.continue_watching` rows for the
transferred uid (line ~301). That is deliberate (a reinstalled device
must not inherit another session's history) but it does clear that user's
saved progress.

Action (ledger only, no SQL re-run):
`supabase migration repair --status applied 20261113` so a later
`db push` does not re-apply the file. The `20261112` local vs
`202611121` remote mismatch stays untouched (disclosed, not reconciled).

## 2. Admin dashboard on Netlify - VERIFIED, approve

`https://dizzy-s-admin.netlify.app` loads as "Dizzy Control - Admin
Console": Overview, Rooms, Moderation, Scrapers, Fleet, **Usernames**,
Announcements, Config, Audit, Device logs, Support, Curated, Admins.
The Usernames tab is exactly the new "who holds each @name / release or
move it" surface the migration's admin RPCs were written for, sign-in is
an allow-listed admin account with Supabase RLS, and every write is
audit-logged.

**Verdict: correct -> approve, no redeploy needed.**

## 3. Stranded usernames - differentiate real users from test users

Signal order (cheapest and most reliable first):
1. owner uid has **no live device row** -> not a real user (nobody can
   hold it) -> **Release**.
2. owner uid has a device row, but that device has a different
   `previous_user_id`/session -> a **real** user whose session changed ->
   **Reassign**, never release.
3. test signals for the ambiguous middle: app version containing
   `debug`/`beta`, install inside a known QA window, name pattern
   `dizzyqa*` (the local test account is `@dizzyqa1106xz`), region
   missing (emulator).

Plan: add `devices.is_test_device boolean` + `devices.classified_at` and
an owner-only RPC `admin_classify_devices()` that applies the rules and
reports the three buckets, then act only on bucket 1 (release). The
dashboard's Usernames tab gets a "Classify & release test names" action
that calls it. Nothing is released before the classification is shown to
the owner.

## 4. `installs` RLS 42501 + one-button permissions (approved)

- `installs` upsert fails with 42501. Approved fix: grant the anon/auth
  role the minimal `insert` on `public.installs` (no select, no update of
  other rows), via a migration, then verify the app stops logging the
  error. Also drop the historical `grant_is_admin to anon` exposure in
  the same pass (that was the earlier boundary mistake) - it should be
  replaced by the owner allow-list the dashboard already uses.

- **One button for everything.** Today a new user must find and toggle
  4-5 separate permissions, so most never do. Plan:
  1. inventory the consent/permission flags (notifications, diagnostics,
     crash reports, usage analytics, background media, ad-id) in one
     service;
  2. add `enableAll()` / `defaultsForFreshInstall()` so a fresh install
     starts with the diagnostic + runtime-data permissions ON (the data
     the app needs for crash/lag/stream analysis);
  3. one button in Settings -> Privacy & Diagnostics: **"Enable all for
     better app diagnostics"**, plus the same single button in the
     first-run consent sheet - one tap, not five;
  4. keep every individual toggle (users must still be able to turn
     things off);
  5. write the consent decision + a single `diagnostics_enabled` marker
     so support can tell "declined" from "never asked".

## 5. Latest-release catalogue + sources evaluation (new eval)

**Corrected spec (owner, 2026-11-14):**
- **Bollywood** = TMDB `region=IN`, original languages **hi, te, ml, kn**
- **Ollywood** = TMDB original language **'or' (Odia)**
- Latest **50 each**, ordered by release date; then per title:
  **catalogue present -> sources found (HTTP / P2R / Debrid) -> playable
  (bytes actually pulled, decoded frame AND right-content check, not just
  "a frame appeared")**, reported as 4 metrics: % catalogue, % sources,
  % playable, % right content - split by source type and by release age.

**Built so far (step 1 done):**
`artifacts/audit-dsh/scripts/build_latest_releases.py` ->
`artifacts/audit-dsh/eval/latest-releases.json`
- bollywood: 50 titles pinned (languages hi/te/ml/kn, 319 fetched)
- ollywood: 50 titles pinned (language 'or', 80 fetched)
- rebuilt by re-running the script; the pinned file + run date make the
  eval repeatable.

**Two facts that shaped the implementation:**
1. `api.themoviedb.org` is **not reachable from this machine** (direct
   calls fail), but the app's own catalogue edge function has TMDB access
   and supports the language filters - including `'or'`, which returns
   real Ollywood titles ("Dahaan", "Rakta Golapa"). So the reference list
   is pulled from the **same feed the Home rails render**, which is the
   right source for the user's actual question ("jo latest top 50 hain,
   Dizzy pe available hain ya nahi").
2. The feed exposes `year` but not an exact release date, and its
   ordering is the edge function's TMDB-backed "freshest first". The
   "by release date" order therefore comes from the catalogue's own
   recency, with `year` and `pop` as tiebreaks; exact dates can be added
   later from TMDB if a reachable path is opened.

**Remaining pipeline (steps 2-5):**
2. catalogue presence per title (already the source of the list -> mark
   present/absent against the rails the user sees);
3. source resolution per title through the app's resolver, counted by
   type (HTTP direct / P2R torrent / Debrid);
4. playable: pull bytes from a sample of each title's sources, require a
   decoded frame plus a content match (right title/episode, not just a
   frame);
5. score the 4 metrics, split by source type and release age, then the
   source-availability fixes the numbers point at.

**RESULT of steps 1-3 (2026-11-14, later pass):** the probe is done and
the diagnosis is sharper than "P2P sources often stall". On the owner's own
50 latest Odia movies the app's resolver answered 30 and **10 of those 30
were a completely different film** (a Spanish "GAME OVER" for a 2026 Odia
request, a Japanese "Monster", a Korean "Midnight"). Two defects, both
measured live:
- the app sent only `apikey` to a JWT-protected edge function, so its
  best resolver rung answered **401 on every call**;
- the resolver matched on the TITLE NAME alone, and the app never even sent
  the year.
And the reason regional titles could not be resolved at all: **TMDB's
/search returns ZERO hits for 18 of 20 sampled Odia films** - only
/discover sees them, so the fix is an index (the title corpus), not a
better query.

Full evidence, the fix and the measured before/after:
`docs/audit/2026-11-14-resolver-and-corpus.md`.

Diagnosis to feed the fix (the owner's observation: posters/catalogues
exist but few sources, and P2P sources often stall):
- separate "source listed" from "source works" - a torrent that seeds
  for 3 minutes is not a source, it is a placeholder;
- measure P2R seeding latency per source and HTTP-direct success rate;
- check the resolver's fallback order (currently it can settle on a P2R
  entry that never delivers);
- check whether the client probe treats "reachable" as "playable".

Improvement candidates to evaluate (then implement, smallest first):
1. prefer a verified HTTP-direct source over an unverified P2R one;
2. probe each candidate for a decodable byte range, not just a reachable
   host, and drop the ones that fail;
3. surface per-source health in the player (seeders / speed / "not
   seeding") instead of a bare list;
4. raise/parallelise source discovery so 7 sources become more than 7
   (the watch list showed 6 torrent + 1 direct);
5. cache verified-good sources per title for 24h so a re-open does not
   re-probe dead ones.

## Execution order

1. `supabase migration repair` (ledger) + `installs` grant migration.
2. `devices.is_test_device` + `admin_classify_devices` -> show the
   buckets -> release only the test bucket.
3. One-button permissions (settings + first-run) + tests.
4. Latest-release eval script + first measured run + score in the eval
   doc, then the source-availability fixes it points at.
5. Audiobook HTML-entity defect (already found, one-line fix + rebuild).
6. Remaining matrix rows (A10-A15 entry points, A8, A9, A17-A18, A20,
   A21, A23, A26/A28-A30, A25 Books addon).
7. v1.3.5 resolver + corpus (2026-11-14, prepared - needs approval):
   apply `20261115_title_corpus.sql` + `20261115_corpus_cron.sql`, deploy
   `resolve` / `corpus-sync` / `catalog`, store the Vault key, run the
   corpus sync once, re-probe, then build the 1.3.5 artifacts.
