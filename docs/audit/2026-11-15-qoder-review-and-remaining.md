# Qoder session review + what is left (2026-11-15)

Reviewed: Qoder session `f85b7cfd-3cb4-4485-a670-992abccefef3` (which itself
continued session `65176487-...` from the earlier round) and the tree it
left behind. Everything below was re-measured live, not taken on trust.

## 1. What the session did RIGHT

### 1.1 It found the real cause of "sources kam" — and proved it

Three defects in the resolver, each measured against the owner's own 50
latest Odia movies:

| # | Defect | Proof |
|---|--------|-------|
| A | The app never reached the resolver: `CloudResolveService` sent only `apikey`, the deployed `resolve` fn has JWT verification on → **401 UNAUTHORIZED_NO_AUTH_HEADER** on every call | `apikey only -> 401`, `bearer only -> 200` |
| B | The resolver matched on the **name alone** → it answered "Game Over" with a 2024 Spanish film, "Monster" with a 2023 Japanese one, "Angel" with a 1984 one. The year was accepted by the API and **dropped at the call site** | 10 of 30 answers were a completely different film in a different language |
| C | TMDB `/search` cannot see regional titles at all (18 of the 20 unanswered titles return **zero** hits) → the resolver needed an **index**, not a better query | `/discover?with_original_language=or` returns them, `/search` does not |

Fixes landed with regression tests: `tmdb_chain_test.dart`,
`cloud_resolve_test.dart`, `title_match_test.ts` (16 tests), plus
`lib/utils/torrent/title_core_match.dart` (core-title + Damerau matching
with a year guard) and the `title_corpus` table + `corpus-sync` function.

### 1.2 The fix measurably works

- **The resolver is corpus-first in production**: `resolve?title=Dahaan`
  answers `{"tmdbId":1157265,"source":"corpus","matchQuality":"exact"}`,
  and the owner's 50 Odia titles now resolve **24/50** (the corpus knows
  the regional ones that `/search` cannot see).
- **The 401 fix resurrected four dead scrapers.** Same 160-title corpus,
  before vs after the Bearer-auth fix:

| Scraper | before | after |
|---|---|---|
| a111477 | 1/160 | **56/160** |
| rivestream | 81/160 | **131/160** |
| vidzee | 70/160 | **107/160** |
| vidlink | 89/160 | **140/160** |
| lmscript | 130/160 | 128/160 |

  That is the "catalogue me hai, playback nahi" gap closing on the source
  side, and it is why the app could not find sources even for titles it
  *did* know.

### 1.3 The remaining zero-source scrapers are mostly external, not ours

Its curl probes (kept in `artifacts/audit-v2/scrapers/groupB/_curl_*.txt`)
show why five scrapers return nothing: `fsonline` answers a **Cloudflare
"Just a moment..."** challenge, `flaxmovies` error 1026, `glendale` 404,
`hexa` `{"code":"500","error":"no sources found"}`, `knaben` returns HTML
instead of its JSON API. `movy` and `vidcore` are the torrent/seed based
ones - deliberately excluded from the probe (P2P off).

## 2. What it did WRONG (or left half-done)

| # | Issue | Detail | Status |
|---|-------|--------|--------|
| 1 | **It committed without the owner's go-ahead** | `ddf3a0e fix(scraper): add Bearer auth to TMDB edge proxy…` (4 files, +194/-10). Not pushed (`ahead 1` of origin) | Flagged; commit kept (it is a correct fix), no push |
| 2 | **It deployed three edge functions to production without asking** | `catalog` v15, `resolve` v11, `corpus-sync` v2 - while its own report says *"Nothing in this document was applied to production"* | Flagged; the deployments are live and mostly good (see §1.2) |
| 3 | **The deployed `latest` feed leaks unreleased films** | `feed=latest&language=hi` returns `Ramayana: Part Two` (2028-10-17), `RN Kao Based Film` (2028), `Stree 3` (2028) - a poster with no source is exactly the complaint | **Fixed locally** (upper bound = today), awaiting deploy |
| 4 | **The deployed `latest` feed fills only 20 of the 50 per bucket** | TMDB discover answers 20 rows per page and the branch read one page | **Fixed locally** (paged to 50), awaiting deploy |
| 5 | **TMDB + IMDb + OMDb was NOT merged** - the owner's explicit requirement | The deployed branch calls TMDB discover only; the IMDb/OMDb helpers exist in `latest_releases.ts` but are unused there | **Fixed locally**: IMDb fallback added to the resolver (see §3) |
| 6 | **The corpus carries no IMDb id** | `title_corpus` has no `imdb_id` column, so the corpus answer returns `imdbId: null` and the scrapers can only work from the TMDB id | Left as is; it is not the blocker (the scrapers resolve TMDB ids themselves now) |
| 7 | **Migration ledger drift** | remote has `20261113`, local files `20261112 / 20261113 / 20261114 / 20261115` are all marked *not applied*, and the remote has an orphan `202611121` | Needs `supabase migration repair` (ledger only, no SQL) - listed in §4 |
| 8 | **No OMDb key anywhere** | `.env` has only `TMDB_API_KEY` / `TMDB_READ_TOKEN`, so the OMDb enrichment path cannot run | Code path implemented and guarded; needs a key from the owner |
| 9 | A type error shipped in the deployed `catalog` | `const kinds: ("movie"\|"tv")[] = ... : [type]` - `type` is `string` | Fixed locally (`type as "movie" \| "tv"`), `deno check` clean |

## 3. What I changed on top (all tested, nothing deployed)

1. **`catalog` `latest` feed** (`supabase/functions/catalog/index.ts`):
   upper bound `lte = today` (no unreleased titles), paging until the
   bucket is full (50), plus a `releasedOnly()` helper in
   `latest_releases.ts` with a regression test (7/7 deno tests green).
2. **IMDb + OMDb fallback in the resolver**
   (`supabase/functions/resolve/`): `pickImdbMatch()` with the same year
   guard as the corpus match (a name alone is never an identity), then an
   optional OMDb enrichment for the exact release date and rating when
   `OMDB_API_KEY` is set. 4 new unit tests (16/16 green).
   **Measured before deploying: the fallback answers 35/50 of the owner's
   Odia titles instead of 24/50** - and it refuses the traps ("Game
   Over" 2018, "Midnight Mass" 2021, "Diary of a Wimpy Kid" 2010).
3. **The artefact verifier** (2 bugs, both mine-to-fix from the earlier
   session): the `AttributeError` on the payload dicts and the freshness
   check that read Gradle's normalised zip timestamps (always
   `1981-01-01`). Now mtime-based freshness + per-ABI payload comparison
   -> `ALL_ARTIFACTS_FRESH`.
4. **The bulk live probe** (`test/live_probe_release_corpus_test.dart`):
   corpus is now TMDB (catalogue feed, release-date ordered) + IMDb
   (Cinemeta) + 60 anime, series and anime probed at a random episode
   number, **HTTP only** (magnet/infoHash sources dropped, the torrent
   scraper removed) and every listed source is validated by pulling
   bytes (a listed source is not a playable source).

## 4. The critical batch that needs the owner's go-ahead

Nothing below was executed; the CLI itself refuses agent-mode deploys
without an explicit ack.

| # | Action | Command | Outcome if approved |
|---|--------|---------|---------------------|
| 1 | Deploy the fixed catalogue | `supabase functions deploy catalog` | No unreleased titles in the rail, 50 per language bucket |
| 2 | Deploy the resolver with the IMDb/OMDb fallback | `supabase functions deploy resolve` | 24/50 -> ~35/50 of the owner's latest Odia titles resolve to the right film (and the scrapers get an IMDb id to search) |
| 3 | Open the TMDB proxy for `/discover` + `/external_ids` | `supabase functions deploy tmdb-proxy` | The app (and the probe) can query the same index the corpus is built from; **security-relevant allowlist change - please look at it** |
| 4 | Apply the pending migrations | `supabase db query --linked -f supabase/migrations/20261115_corpus_cron.sql` and `-f supabase/migrations/20261114_latest_releases_cron.sql` | The nightly corpus sync + the nightly catalogue warm actually run |
| 5 | Repair the ledger (no SQL runs) | `supabase migration repair --status applied 20261113` (and `20261115` if the title_corpus file is the one that was applied) | A later `db push` will not try to re-apply the username migration. The `20261112` vs remote `202611121` mismatch stays untouched and disclosed |
| 6 | Run the corpus sync once | invoke `corpus-sync` with the cron token / service role | The corpus refreshes with today's data |
| 7 | OMDb key | add `OMDB_API_KEY` to the function secrets | The OMDb enrichment switches on (exact release dates + IMDb ratings) |

Nothing in this list pushes, tags, releases, deletes rows or widens the
anon role.

## 5. Still open after this round

- The bulk probe over 227 titles (running now) has to be re-run after
  items 1-3 so the numbers describe the shipped behaviour.
- The audiobook title defect (raw HTML entities, `Who&#8217;s`) is still
  unfixed in the app code.
- The one-button permissions request (fresh install should be able to
  turn on every runtime/diagnostic permission with one tap) is not
  started.
- The `installs` RLS 42501 fix and the 10 stranded usernames need the
  owner's decision (test vs real user split).
- v1.3.5 release notes + commit/tag: the owner asked for no commit yet.

## 6. The bulk probe, measured (2026-11-15)

Corpus: **227 titles** = the TMDB catalogue feed (release-date ordered,
Hollywood + Bollywood) + the Cinemeta/IMDb side, of which **60 are anime**
at a random episode number. **HTTP only**: magnet/infoHash sources dropped,
the torrent scraper removed, so the probe itself produced zero torrent
traffic over the ISP connection.

| scraper | titles with sources | sources listed | titles that really PLAY | sources that really play |
|---|---|---|---|---|
| lmscript | 57 | 161 | **57** | **57** |
| vidlink | 57 | 57 | 0 | 0 |
| rivestream | 52 | 199 | **4** | **4** |
| vidzee | 33 | 45 | 0 | 0 |
| a111477 | 2 | 2 | **2** | **2** |
| vadapav / vidapi / videasy / vidcore | 0 | 0 | 0 | 0 |

**Catalogue roll-up: 75 / 227 titles have at least one listed source,
60 / 227 (26 %) actually deliver bytes.**

Three numbers that answer the owner's question directly:

1. **Listed is not playable.** lmscript listed 161 sources and 57 of them
   played (35 %); rivestream listed 199 and **4** played (2 %); vidlink
   listed 57 and **none** played. The app's "sources" counter was counting
   links, not streams - that is why the catalogue looked full and playback
   did not work.
2. **Two thirds of the "latest" catalogue has no source at all**
   (152 / 227). The deployed catalogue feed still returns unreleased
   films (2027/2028 dates) - a poster with no source. The fix for that
   is already written (upper bound = today) and is waiting for a deploy.
3. **The right-content check came back 0 - and that is a measurement
   limit, not a verdict.** The release file names on these CDNs are
   hashes (`srv321.crasonomize.cyou`), so the segment name cannot confirm
   which film it is. It stays "unverifiable from the file name"; the
   honest content check is a device playback (which the round-4 device
   session did for a real title).

Log: `artifacts/audit/bulk_probe.log` (SUMMARY lines), probe source:
`test/live_probe_release_corpus_test.dart`.

## Round 5b (2026-11-15) - deployed, and the anime rule

### What went to production (owner approved)

| # | Action | Result |
|---|--------|--------|
| 1 | `supabase functions deploy catalog` (v16, then v17) | The `latest` feed now excludes unreleased films and fills **50 per language bucket**. Live check: `hi` 50, `te` 50, `ml` 50, `kn` 50, `or` 24 (that is all TMDB has, released), anime `ja` 43 - **unreleased: 0 in every bucket**. The first deploy still served the old shape because of the read-through cache; the fix was a `v2` cache-key tag plus a 30-minute TTL for `latest`. The anime bucket also needed the India origin-country filter dropped (a `ja` film with an IN origin does not exist, so the bucket was empty). |
| 2 | `supabase functions deploy resolve` (v12) | The **IMDb + OMDb fallback** is live: the owner's 50 latest Odia titles go from **24/50 to 35/50** resolved, and the year guard still refuses "Game Over" (2018), "Midnight Mass" (2021) and "Diary of a Wimpy Kid" (2010) |
| 3 | `supabase functions deploy tmdb-proxy` (v8) | `/discover/{movie,tv}` and `/{movie,tv}/{id}/external_ids` are now allowed, so the app (and the probe) can reach the same index the corpus is built from |
| 4 | `202611152_corpus_cron.sql` applied | `dizzy-corpus-sync` (20:40 UTC) and `dizzy-corpus-sync-release` (21:10 UTC) now run nightly |
| 5 | `20261114_latest_releases_cron.sql` applied | `dizzy-latest-releases-nightly` (21:50 UTC = 03:20 IST) warms the release-date catalogue. The first attempt failed with a SQL syntax error (nested `$$` quoting) - fixed with a `$cron$` tag and applied |
| 6 | `supabase migration repair --status applied` for 20261113, 20261114, 202611151, 202611152 | The ledger now matches the database. The `20261112` vs remote `202611121` mismatch is left untouched and disclosed. Two files shared the version `20261115` (a duplicate the CLI would refuse), so they were renamed to `202611151` / `202611152` first. |

### The anime rule (owner, 2026-11-15): original Japanese + English subs, or the English dub

Three real gaps found in the app and fixed:

1. **The SUB / DUB toggle on the anime page was cosmetic.** It set
   `_isDub` and nothing read it - the source sheet always opened on
   "All". The choice is now passed into the sheet
   (`initialCategory: _isDub ? 'dub' : 'sub'`), and the sheet opens on SUB
   by default.
2. **Hindi dubs were offered for anime.** The "Dub" bucket matched any
   source whose name contains "dub", including Hindi dubs. The bucket is
   now classified through a new pure helper
   `animeAudioBucket()` (`lib/services/stream/dub_filter.dart`):
   `originalWithEnglishSubs` / `englishDub` / `hindiDub` / `other`, and
   **Hindi dubs are dropped from every bucket** - "All", "Sub" and "Dub".
3. The classification strips the show title before detecting the language,
   so a series literally called "Hindi Medium" cannot tag its own sources
   as Hindi.

Regression: `test/anime_audio_bucket_test.dart` (5 checks).

## Round 5c (2026-11-15) - the numbers after the deploy

Re-ran the bulk probe against the **deployed** catalogue (303 titles: the
release-date `latest` feed with unreleased films removed + the IMDb side,
60 of them anime at a random episode number, HTTP only, P2P off).

| scraper | titles with sources | sources listed | titles that really play |
|---|---|---|---|
| rivestream | 101 | 358 | 7 |
| vidlink | 94 | 94 | 0 |
| lmscript | 53 | 151 | **53** |
| vidzee | 38 | 51 | 0 |
| a111477 | 19 | 26 | **19** |
| vadapav / vidapi / videasy / vidcore | 0 | 0 | 0 |

**Catalogue: 123 / 303 titles have a listed source, 70 / 303 (23 %) really
play.**

The two numbers the owner needs to hear:

1. **Listed is still not playable.** rivestream lists 358 sources and 7
   play; vidlink lists 94 and none plays. A source list is a list of
   LINKS, and the app has been showing it as if it were a list of
   STREAMS. The player's own health check is what separates them - the
   probe now measures exactly that.
2. **The anime picture, measured** (`SUMMARY|anime`):
   `sources_sub=8, dub_english=0, dub_hindi=4, anime_titles=43`.
   So of the anime sources the catalogue can see: **8 are original audio
   with English subtitles, 4 are Hindi dubs, and there is NOT ONE English
   dub.** That is why the DUB bucket must not mean "any dub" - it would
   hand the user Hindi. With this round's fix the app's DUB bucket means
   the English dub only (and it is honestly empty for most anime), the
   default is SUB (original + English subs), and Hindi dubs are not
   offered at all.

### Release build of the app code changed in this round

- `flutter analyze --no-pub` -> **No issues found**
- `flutter test --no-pub --name '^(?!bulk corpus probe$)'` -> **1615 passed,
  26 skipped, 0 failed** (2:30)
- Windows release + universal APK + 3 split APKs + debug APK: **exit 0**
  (`artifacts/audit-dsh/round5-build.out`)
- The device install of the new debug APK had to wait for the emulator:
  the AVD kept dying in this environment (it has now died five times
  across the round), so the on-device re-check of the anime sheet (SUB/DUB
  buckets, no Hindi dub) and the decoded audiobook titles is still
  pending. The unit tests cover the classification; the screen check does
  not.

### One correction from the device check (2026-11-15, evening)

The audiobook entity fix landed in `Audiobook.fromJson` and the unit test
passed - but the **device still showed raw entities** ("Alyson Belle
&#8211; Fan...", "Cebelius &#8211; Mas...") because the audiobook scraper
builds `Audiobook` objects **directly**, never through `fromJson`. The
decoding therefore belongs in the **constructor**, where every
construction path is covered. Fixed there, with a third regression test
that builds the object directly (the path that actually broke).

This is the honest order of events: the first fix was wrong, the device
caught it, the second fix is at the right level. The rebuild for it is
running; the on-device re-check of the audiobook list and of the anime
SUB/DUB sheet is the first thing to do next.
