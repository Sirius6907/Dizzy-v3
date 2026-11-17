# Dizzy v1.3.5 - "sources kam": the resolver, measured (2026-11-14)

Owner question: *the posters and the catalogue are there, but there are
almost no sources. Find the root cause.*

Answer: **the resolver.** Two separate defects in it, both measured live
against the owner's own 50 latest Odia movies, plus a third defect in the
torrent filter that threw away the correct releases it did find.

Nothing in this document was applied to production. The code, the migration
and the functions are written and tested locally; the deploy/apply steps are
listed at the end and still need the owner's approval.

---

## 1. The measurement set

The owner's ground truth: the 50 latest Odia (Ollywood) movies, with their
release windows (`artifacts/audit-dsh/scripts/match_ollywood_catalogue.py`).

| probe | script | result |
|---|---|---|
| catalogue feed (what the Home rails render) | `match_ollywood_catalogue.py` | **13/50** in the feed |
| app search (Cinemeta) | `match_ollywood_search.py` | **41/50** findable |
| resolver (deployed edge fn, live) | `probe_resolve.py` | **30/50** answered |
| is the answer the RIGHT film? | `probe_right_content.py` | **15 correct / 15 wrong / 20 unanswered** |

## 2. Defect A - the app never reached the resolver (401, every call)

`CloudResolveService.resolveIds` sent only the `apikey` header. The
deployed `resolve` edge function has JWT verification ON, so it answered:

```
apikey only  -> 401 {"code":"UNAUTHORIZED_NO_AUTH_HEADER"}
bearer only  -> 200 {"tmdbId":1291608,"title":"Dhurandhar"}
both         -> 200
```

So the app's best resolver rung - the server-key, year-pinned one - was
**dead in production for every title**, and the app silently fell through
to the weaker local chain.

Fix: `buildHeaders()` now sends `Authorization: Bearer <anon key>` (the
anon key is a valid JWT, role=anon). Regression:
`test/cloud_resolve_test.dart` ("the request carries a bearer token").

## 3. Defect B - the resolver matched on the NAME alone

The resolver required an exact cleaned-title match against TMDB's search
results. For a generic regional name that is not an identity:

| requested | resolver answered | reality |
|---|---|---|
| Game Over | 1619085 GAME OVER | 2024, **es** - a different film |
| Monster | 1050035 Monster | 2023, **ja** - a different film |
| Angel | 1803 Angel | 1984, **en** - a different film |
| Midnight | 628704 Midnight | 2021, **ko** - a different film |
| Diary | 807598 Diary | 2022, **ta** - a different film |
| Pratha | 764672 Pratha | 2002, **hi** - a different film |
| Murabi | (2026) | **en** - a different film |
| Ananta | (2018) | **id** - a different film |
| Adrushya | (2022) | **mr** - a different film |
| Vaastav | 146270 Vaastav | 1999 - the wrong film |

10 of the 30 answers were a completely different film in a different
language. That is the "poster A, playback B" bug the exact-title gate was
built to stop - it only ever guarded the NAME, never the year or the
language, and the app never sent the year at all (the year was accepted by
the API and dropped at the call site in `tmdb_helper.dart`).

Fixes:
- the year now travels with the request (`tmdb_helper.dart` -> `resolveIds`);
- the resolver applies a year guard (±1) and an optional language guard to
  every search hit;
- a one-edit spelling difference is allowed only when the year agrees.

## 4. Defect C - TMDB /search cannot see regional titles

For the 20 titles the resolver did not answer, `probe_tmdb_lookup.py`
asked TMDB (through the keyless `tmdb-proxy` edge) what it actually knows:

```
MISSING_IN_TMDB 18   (TMDB /search returns ZERO results for the title)
SPELLING_DIFFERS 1   (Parichaya / Parichayam - one letter)
OTHER_TITLE       1   (Misiri -> "Kid Millions")
```

A better query does not fix it: `probe_resolve_strategy.py` tried the full
title and the core title for all 20 and only **1/20** was recoverable that
way.

The reason is the endpoint, not the query string: TMDB's
`/discover/movie?with_original_language=or` returns these films, `/search`
does not. Measured with the real feed:

| corpus size (discover, language 'or') | owner titles covered |
|---|---|
| 176 rows | 17/50 |
| 616 rows | 25/50 |

**So the resolver needs an index, not a better search.** That index is the
title corpus.

## 5. The fix

### 5.1 The corpus (new)

`supabase/migrations/20261115_title_corpus.sql` - `public.title_corpus`:
one row per (kind, TMDB id) with the title, the original title, the
cleaned name, the CORE name (subtitle and brackets removed), the year and
the language. RLS on, no public policy: only the service role reads it.

`supabase/functions/corpus-sync/index.ts` fills it from TMDB discover:
`hi, te, ml, kn, or` for movies and `ja` for anime (the anime bucket is
indexed with the English name, so an English/Romaji anime title can reach a
TMDB id). Nightly at 20:40 UTC via the existing `call_edge_function` helper
(`supabase/migrations/20261115_corpus_cron.sql`).

### 5.2 The resolver (corpus first)

`supabase/functions/resolve/index.ts` now:
1. asks the corpus first (exact name -> core name -> one-edit, each with
   the year guard);
2. falls back to TMDB search with the year and language guards;
3. answers `{tmdbId, imdbId, year, title, source, matchQuality}` so the
   client knows HOW it matched.

Two implementation details that mattered, both found by the live re-probe:

- **The corpus lookup is TWO queries, not one.** The exact/alias lookup
  (`title_norm` / `title_base`) is narrow and indexed; the fuzzy candidate
  set is the year window. Merging them into one query with a LIMIT hands
  back an arbitrary slice of the year window, and the row we came for is
  lost in the crowd - measured: 22/50 answered with one query, 27/50 with
  two.
- **The corpus needs a RELEASE-DATE sweep, not only a popularity sweep.**
  A new Odia film has zero votes, so a popularity sort never reaches it -
  and "what came out this month" is exactly the question. The release
  sweep added 1,706 rows and is what put "Dahaan", "Kankana", "Chakranta"
  and "Rakta Golapa" into the corpus.

The matching rules live in `supabase/functions/resolve/title_match.ts`
(pure, unit tested: `title_match_test.ts`, 12/12).

### 5.3 The app

- `cloud_resolve_service.dart`: the bearer header, the `lang` pass-through,
  the `source`/`matchQuality` gate (v3), and the cache key bumped so the
  old, wrongly-poisoned v2 answers expire.
- `tmdb_helper.dart`: the year now travels with the request.

## 6. What the fix is worth (MEASURED LIVE, after the deploy)

Both columns are live measurements of the DEPLOYED resolver on the owner's
50 latest Odia movies, read with the same probe
(`probe_resolve.py` for the answers, `probe_right_content.py` for "is it
the right film?").

A row with no release date in TMDB cannot be disproved, so it counts as
right when the LANGUAGE is right (that is what a "wrong film" means here -
a different film in a different language).

| | before (old resolver) | after (v1.3.5 resolver + corpus) |
|---|---|---|
| right film | 20 | **22** |
| wrong film | **10** | **5** |
| unanswered | 20 | 23 |

Read it carefully, because "unanswered" went UP and that is the point: the
year guard now REFUSES five answers that used to be handed out (a 2024
Spanish "GAME OVER" for a 2026 request, a 1999 "Vaastav" for a 2025 one).
A wrong id plays the wrong film, so refusing is better than answering.

**Where the answers come from now** (the corpus is doing the work):

```
ollywood_latest50   corpus exact 19 | corpus alias 2 | tmdb exact 5 | tmdb fuzzy 1
bollywood_latest50  corpus exact 50   (all 50 match the catalogue id)
```

**The 5 remaining wrong answers, read honestly:** they are the same-name,
same-year ENGLISH films - "Game Over" (2026, en), "Monster" (2026, en),
"Midnight 3" (2026, en), "Murabi" (2026, en), "Angel" (2025, en). TMDB has
no Odia row for any of those five, so the corpus cannot answer them.

And here is the thing about those five: **the app's own search already
matched a different film before the resolver ever saw the request.**

```
Cinemeta search: what the app actually finds
Game Over      -> tt0338459  Spy Kids 3: Game Over
Midnight       -> tt1605783  Midnight in Paris
Angel          -> tt0808151  Angels & Demons
Kankana        -> tt0956256  Veera Kankanam
```

So for an ambiguous name the app opens "Midnight in Paris" for the Odia
"Midnight" whatever the resolver does. The resolver can no longer make it
worse (that was its job) but it cannot fix a wrong INPUT either.

**The remaining wrong-content lever is the app's search ranking, not the
resolver:** a search hit whose name matches the request but whose language
or year does not should lose to a regional catalogue row. The resolver
already carries the language guard (`?lang=or`) - the app just does not
know the language of a search result yet.

Also worth recording: Cinemeta carries a TMDB id for only **8 of the 41**
searchable Odia titles (`probe_cinemeta_moviedb.py`), so for the other 33
the resolver IS the only way to a TMDB id. That is why this fix matters.

## 7. A second, independent "sources kam" cause: the torrent filter

`knaben.dart` searched the FULL catalogue title and compared the release
name VERBATIM. A release is indexed under its core name
("Dahaan (2026) [Odia]"), so every correctly indexed release of a
subtitled title was thrown away, and the search itself matched nothing.

Fix: `lib/utils/torrent/title_core_match.dart` - search and compare on the
core name, with the release year as the guard ("Murabi" can never be
answered by "Murali"; a short core never gets the one-edit allowance).
Regression: `test/title_core_match_test.dart` (8/8).

## 8. Verification done locally

| check | result |
|---|---|
| `flutter analyze --no-pub` | No issues found (28.1 s) |
| `flutter test --no-pub --name '^(?!bulk corpus probe$)'` | **1606 passed, 26 skipped, 0 failed** |
| `node --test supabase/functions/resolve/title_match_test.ts` | 12/12 |
| `node artifacts/audit-dsh/scripts/run_deno_style_test.mjs .../latest_releases_test.ts` | 6/6 (Deno is not installed here; the shim runs the Deno-style file under Node) |
| `node --check` on all touched edge functions | clean |
| live re-probe of the deployed resolver | see section 6 |

The slow live-network test `bulk corpus probe` is still excluded, exactly
as in the previous rounds - this is not an unqualified full-suite pass.

## 9. What was applied (owner approved, 2026-11-14)

The owner approved the full pass. Executed:

1. `supabase db query --linked -f supabase/migrations/20261115_title_corpus.sql`
   -> `public.title_corpus` exists, RLS on, 6 indexes, no public policy.
2. `supabase functions deploy resolve` -> the corpus-first resolver.
3. `supabase functions deploy corpus-sync --no-verify-jwt`.
4. `supabase functions deploy catalog --no-verify-jwt` -> `feed=latest`.
5. `python artifacts/audit-dsh/scripts/store_vault_secret.py` ->
   `catalog_anon_key` in Vault (value never printed; the script now uses
   the linked project instead of the REST RPC that was always going to be
   denied).
6. `supabase db query --linked -f supabase/migrations/20261115_corpus_cron.sql`
   -> two nightly jobs (20:40 UTC popularity sweep, 21:10 UTC release
   sweep), both `active`.
7. Corpus warm: **4,297 rows** over 6 languages (hi, te, ml, kn, or, ja),
   1,706 of them from the release sweep, 501 Odia rows.

The release sweep matters: the popularity sort never reaches a new Odia
film (zero votes), so the newest titles were invisible to the corpus
before it.

Two fixes came out of the live re-probe and are deployed too:
- the corpus lookup was one query with a LIMIT, which drowned the exact
  row (22/50 -> 27/50 answered after splitting it in two);
- the corpus needed a release-date sweep (the popularity sort never
  reaches a zero-vote new film).

Still open, for the owner:
- the 1.3.5 artifacts (Windows + APKs) and the owner's own test;
- nothing pushed or tagged;
- the app's SEARCH ranking (prefer a regional row over a same-name
  popular film) - the last wrong-content lever, in the app rather than in
  the resolver;
- the app does not send `lang` yet, so the resolver's language guard is
  idle.

## 10. Files

```
supabase/functions/resolve/index.ts              resolver: corpus first + year/lang guards
supabase/functions/resolve/title_match.ts         the matching rules (pure)
supabase/functions/resolve/title_match_test.ts    12 unit tests
supabase/functions/corpus-sync/index.ts           fills the corpus from TMDB discover
supabase/migrations/20261115_title_corpus.sql     the corpus table
supabase/migrations/20261115_corpus_cron.sql      nightly corpus sync
supabase/functions/catalog/index.ts               feed=latest wired in
supabase/functions/catalog/latest_releases.ts     injected TMDB reader (bearer support)
lib/services/cloud/cloud_resolve_service.dart     bearer header + provenance gate
lib/services/scraper/sites/tmdb_helper.dart       the year travels with the request
lib/services/scraper/sites/knaben.dart             core-name search + match
lib/utils/torrent/title_core_match.dart           the core-name rules
test/cloud_resolve_test.dart                      10 tests
test/title_core_match_test.dart                   8 tests
artifacts/audit-dsh/scripts/probe_*.py            the probes behind every number above
artifacts/audit-dsh/scripts/simulate_*.ts         the before/after simulation
artifacts/audit-dsh/eval/*.json                   the raw probe output
```
