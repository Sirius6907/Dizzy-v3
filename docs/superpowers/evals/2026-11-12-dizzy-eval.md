# Dizzy eval harness — 2026-11-12 (round 2, updated 2026-11-14)

Purpose: repeatable check matrix for the stress-test + brand-battle round.
Every check is worth 1 point; pass/fail only, with evidence link.
Rule: an unverified check counts as FAIL, never as pass. The measured
average success rate is reported truthfully at the bottom.

Actual protocol: emulator-5554 (x86_64 debug APK, `app-debug.apk` built
2026-11-13 12:46), adb input + screenshot (540 px JPEG) + read-back, plus
`dumpsys media_session` / `dumpsys audio` / logcat for playback truth; the
packaged Windows release bundle was driven through its real window and
captured with a screen grab. The existing debug signing identity was
preserved; the release arm64 APK was never executed, so release-on-device
coverage is UNVERIFIED. Evidence lives in `artifacts/audit-dsh/`
(`handoff-*.jpg`, `pb-*.jpg`, `windows-hero-*.png`).

This is a bounded acceptance run, not a claim that all flows were exercised.
Unit tests and screenshots of only part of a compound check do not turn the
whole check into a pass. Competitor parity was NOT verified: no current
2026 competitor source was retrieved, so every Matrix B row scores only the
Dizzy side of the criterion and no /10 parity rating is claimed.

Scoring rule used below: a check passes only when the described behaviour was
observed on-device in this round. "Open + one real flow" requires the surface
to open AND one interactive flow inside it to be executed and observed.

## Matrix A — stress (edge cases, end to end)

| # | Check | Result | Evidence / reason |
|---|-------|--------|-------------------|
| A1 | Cold start to interactive home (time to content) | PASS | `handoff-31` (skeleton state), `handoff-32` (full Home) |
| A2 | Offline start: UI explains itself, cached content where possible | PASS | `handoff-72`, `handoff-73` — airplane mode, cold start, cached hero + rails, no error screen |
| A3 | Airplane-mode mid-session: no crash, honest error/retry states | PASS | `handoff-96` — airplane on with the app running, Home stayed stable |
| A4 | Network flap recovery: reconnect resumes streams | PASS | `handoff-74` — airplane off + pull-to-refresh, live content back |
| A5 | Home refresh during load: no blank/error screen | PASS | `handoff-74`, `handoff-96` — three refreshes, no blank state |
| A6 | Home refresh spam: no duplicate rails / state corruption | PASS | `handoff-96` — three rapid pull-to-refreshes, single set of rails, no crash |
| A7 | Rails render mid-stream (partial data shown, fills in) | PASS | `handoff-31` → `handoff-32` |
| A8 | Hero rotation + chip switching mid-fetch: no stuck loader | FAIL | Hero rotation verified (`handoff-32/37/46/70`: Heart of the Beast, Gajab Raat, Mookuthi Amman 2, Ramayana: Rise of a Legend) but the language chips were never switched → check not fully verified |
| A9 | Brand rail absent when addon down: rail hidden, no dead tile | FAIL | Not exercised — no addon was disabled |
| A10 | Details → Play: movie | FAIL | The details page resolves **7 sources (6 torrent + 1 direct HTTP 1080p)** with filters (`pb-29`, `pb-34`), but that 2026 title's sources never delivered: position stayed `0:00`, duration `--:--` after ~2.5 min on both source kinds (`pb-30`…`pb-33`). The **video pipeline itself is proven** — a movie launched from a Home Continue Watching card decoded and advanced frames (`pb-37`, `pb-39`) — but the *Details → Play* entry point on a title with live sources was not re-run, so the check stays failed |
| A11 | Details → Play: series with season/episode switch | FAIL | Not exercised |
| A12 | Details → Play: anime | FAIL | Anime surface, 26-episode grid and SUB/DUB control verified (`handoff-78/81`); playback not exercised |
| A13 | Details → Play: tmdb: rail card | FAIL | tmdb: cards resolve to the right details (`handoff-35` Ramayana, `handoff-52` A Story of Derry); playback of such a card not exercised |
| A14 | Details → Play: bestsimilar card | FAIL | bestsimilar cards render (`handoff-80` "Franchise & Relations", `pb-34`), none opened |
| A15 | Details → Play: catalog brand card | FAIL | Netflix brand tile → catalog → title details verified (`handoff-54/55`); playback not exercised |
| A16 | Continue Watching resume | PASS | Tapping a Continue Watching card opened the player and the movie **decoded and advanced frames** (`pb-37` first frame, `pb-39` a later frame of the same scene). The stored offset itself was not read from the scrubber, so the position value is not part of the evidence |
| A17 | Resume-at-end guard (finished title doesn't loop) | FAIL | Not exercised |
| A18 | Auto-skip guard at 0:00 (no skip loop at intro boundary) | FAIL | Not exercised |
| A19 | Music play + queue extend near track end | PASS | **Decoded playback**: the platform reports the app's audio player as `state:started` (OpenSL ES AudioPlayer, app pid) and AudioFlinger created a track at play time, and the extractor resolved a full audio stream (`pb-logcat.txt`). Position advanced 02:28 → 02:43 in 15 s (`pb-04`/`pb-05`). **Queue extend**: "Kesariya (Pritam)" was added via the track sheet and appears in Queue & Up Next (`pb-12` → `pb-15`). **Near track end**: the queue auto-advanced when "Heat Waves" reached its end (`pb-06`, `pb-10`) |
| A20 | Music skip/like steering changes radio direction | FAIL | The actions work — the heart turned solid red (`pb-22`) and skip jumped to the next radio track with the queue continuing (`pb-23`) — but a steering-driven **direction change** was not observed, so the check is not fully verified |
| A21 | Radio regenerate / Song Radio reseed | FAIL | Stations render (8 mood stations, `pb-17`), a station opens a live mood query (`pb-18` "Romantic Bollywood Hits"), the track sheet offers "Song Radio" and the drawer shows an "UP NEXT · FOR THIS SONG" radio rail (`pb-12`/`pb-15`) — but no regenerate/reseed control was exercised |
| A22 | Onboarding wizard re-entry from settings (taste edit) | PASS | `handoff-10`–`handoff-18` + `test/music_onboarding_wizard_test.dart` |
| A23 | Music download flow | FAIL | "Download Track Offline" was tapped and the row showed a download progress indicator (`pb-24`), but completion and the downloaded item in the library were not confirmed → not fully verified |
| A24 | FLAC/YouTube source switch | PASS | The source sheet offers "FLAC Lossless (Qobuz Hi-Res) / LOSSLESS" and "YouTube Audio / FAST" (`pb-20`); switching to FLAC triggered a Qobuz lookup that returned **HTTP 404**, and the player then labelled the stream **"YouTube HQ"**, not "LOSSLESS" — the fallback is honest (`pb-21` + logcat) |
| A25 | Books: open + one real flow | FAIL | Surface opens with an honest empty state; a real search ran (`handoff-56/57`) but the catalog answers "No books found" for every query, so no book can be opened |
| A26 | Manga: open + one real flow | FAIL | Surface opens with live titles (`handoff-60`); no title opened |
| A27 | Audiobooks: open + one real flow | PASS | The surface opens with the "Audiobook Hub" and a genre filter was applied in-app (Fantasy) -> the catalogue re-queried and returned **61 titles** with covers and source badges (`pb-41`). One defect was found here: titles still carry raw HTML entities (`The Baker Who&#8217;s 40% ...`, `Alyson Belle &#8211; ...`) |
| A28 | Live TV: open + one real flow | FAIL | Surface opens with live channels (`handoff-71`); no channel opened |
| A29 | Addons: open + one real flow | FAIL | Surface opens with 7 providers and working function chips (`handoff-82`); no addon action executed |
| A30 | Downloads: open + one real flow | FAIL | Surface opens with a storage meter and actions (`handoff-68`); no download action executed |
| A31 | My List: open + one real flow | PASS | Title saved from a details page, list shows "1 saved title" (`handoff-75` → `handoff-76`) |
| A32 | Rapid dock switching (no state bleed) | PASS | Home→Music→Addons→Downloads→My List→Live TV→Home in quick succession, no bleed or crash (`handoff-63`–`handoff-71`) |
| A33 | Back-button mashing (no crash, sane stack) | PASS | Repeated backs walked player → details → home → launcher and the app was re-entered cleanly several times, no crash (`handoff-63`, `pb-25`/`pb-26` relaunch) |
| A34 | Light↔Dark theme toggle mid-flow | PASS | Settings → Appearance → Dark Clay applies live, then restored to Light Clay (`handoff-92`–`handoff-96`) |
| A35 | App kill + relaunch: state restore | PASS | force-stop + relaunch restored Home with the same Continue Watching (`handoff-37`, `handoff-72`); after a full reinstall the identity also survived (`handoff-98/99`) |

## Matrix B — brand battle criteria (verified-on-device only)

| # | Surface | Criterion | Result | Evidence / reason |
|---|---------|-----------|--------|-------------------|
| B1 | Music vs Spotify | Onboarding to first content | PASS | Wizard → personalised Music home (`handoff-10`–`handoff-18`, `handoff-87`) |
| B2 | Music vs Spotify | Home personalization rails | PASS | Your Artists order, Late-Night mood mixes, India charts (`handoff-87`, `handoff-86`) |
| B3 | Music vs Spotify | Queue/radio quality | PASS | Queue & Up Next drawer: now-playing card with a "Playing" badge, up-next list with per-track remove + "Drag handles to reorder", a per-song radio rail and "Played Recently (3)" (`pb-07`, `pb-15`); mood stations open live queries (`pb-17/18`) |
| B4 | Music vs Spotify | Search | PASS | `Kesariya` returned real matches (`handoff-20`, `pb-11`) |
| B5 | Music vs Spotify | Now-playing UX | PASS | Expanded player: artwork, title/artist, waveform seek bar with 02:28/03:55, shuffle/prev/pause/next/repeat, source badge, lyrics/queue/theme, up-next row (`pb-04`, `pb-05`, `pb-21`) |
| B6 | Music vs Spotify | Source switching | PASS | Source sheet + honest fallback labelling (`pb-20`, `pb-21`) — see A24 |
| B7 | Home vs Netflix | Cold-start-to-content speed | PASS | `handoff-31` → `handoff-32` |
| B8 | Home vs Netflix | Hero + rails | PASS | Hero with rating/year/runtime/description/CTA and 8+ rails (`handoff-32`, `handoff-39`, `handoff-53`); Windows hero (`windows-home-01.png`, `windows-hero-short-780.png`) |
| B9 | Home vs Netflix | Continue watching | PASS | Nine items with progress and remaining time (`handoff-96`, `windows-hero-short-scrolled.png`) |
| B10 | Home vs Netflix | Profile-aware recommendations | PASS | "Because you're watching", "For You", "Made For You" mood mixes (`handoff-33`, `handoff-48`, `handoff-87`) |
| B11 | Home vs Netflix | Offline behavior | PASS | Airplane-mode cold start served cached Home with no error screen (`handoff-72/73`) |
| B12 | Anime vs Crunchyroll | Episode list UX | PASS | "Episodes (26 total)" grid + jump-to control (`handoff-81`) |
| B13 | Anime vs Crunchyroll | Subs/dubs handling | FAIL | SUB/DUB control rendered with SUB active (`handoff-81`); switching/dub playback not exercised |
| B14 | Anime vs Crunchyroll | Watchlists | PASS | "ADD TO LIST" on the anime sheet + My List save flow (`handoff-79`, `handoff-76`) |
| B15 | Anime vs Crunchyroll | Simulcast freshness | FAIL | No simulcast dataset verified |

Catalog depth per season (B16, external-addon-bounded) is reported
separately: one anime exposed a 26-episode season list, but depth per season
across the catalog was not measured, so B16 is UNVERIFIED and is not counted
as a pass.

## Score

- Matrix A: 16 / 35 pass
- Matrix B: 13 / 15 pass
- **50-check result: 29 / 50 = 58.0 %**
- 51-check result (including B16): 29 / 51 = 56.9 %

Target was 99.3 %. The measured result is far below it and is reported as
measured. The gap is dominated by checks this round did not exercise, not by
28 reproduced defects:

- **Video playback (A10–A15)**: sources resolve (7 found for the movie,
  HTTP 1080p + P2R torrents) but no stream ever delivered a frame on this
  emulator, so no video check could be counted.
- **Unverified in-surface flows (A26–A30)**: the surfaces open with live
  content, but no item was opened inside them.
- **Steering/radio specifics (A20, A21)** and **A23 download completion**:
  the actions were exercised and observed, but the specific end-state the
  checks ask for was not.
- **A16–A18 resume guards, A9 addon-off, A8 chip switching, A25 Books**
  (the books addon answers "No books found" for every query).
- Competitor parity was not verified (no current-2026 sources retrievable),
  so no parity rating is claimed.

No score was inflated by counting partial evidence as a pass.

## Round 5 (2026-11-15) - "sources kam" measured end to end

New work: a second agent (Qoder) continued the resolver work; this round
re-measured everything live and closed the remaining gaps. Full review:
`docs/audit/2026-11-15-qoder-review-and-remaining.md`.

### Measured (live, production)

| Check | Result | Evidence |
|-------|--------|----------|
| Resolver answers the owner's 50 latest Odia titles | **24/50** (corpus-first, `source:"corpus"`) | `artifacts/audit-dsh/eval/resolve-probe.json` |
| With the IMDb fallback (year-guarded) - measured locally, deploy pending the owner's ack | **35/50** | `artifacts/audit-dsh/scripts/probe_imdb_fallback.ts` (the fallback refuses "Game Over" 2018, "Midnight Mass" 2021, "Diary of a Wimpy Kid" 2010) |
| Titles IMDb AND TMDB both never heard of | **1/50** ("Mohangiri: Sapanara Gaon") | `artifacts/audit-dsh/eval/imdb-coverage.json` |
| HTTP scrapers that were dead because of the resolver 401 | **4 of 10 revived** (a111477 1->56, rivestream 81->131, vidzee 70->107, vidlink 89->140, per 160 titles) | `probe-release-corpus2.log` |
| Scrapers that stay at 0 - cause is external, not ours | 5 (Cloudflare challenge, 404, upstream 500, HTML instead of the JSON API, and the torrent one that is deliberately out because P2P is off) | `artifacts/audit-v2/scrapers/groupB/_curl_*.txt` |
| Catalogue feed coverage of the owner's 50 Odia titles | 13/50 in the feed, 41/50 searchable, ~45/50 with spelling tolerance | `artifacts/audit-dsh/eval/ollywood-*.json` |

### Fixed in this round (tests green, deploy pending the owner's ack)

- `catalog` `latest` feed: no unreleased titles (the deployed version
  answered with 2028-dated films - a poster with no source is the
  complaint), and 50 per language bucket instead of 20.
- `resolve`: IMDb + OMDb fallback with the year guard.
- Audiobook titles/author: HTML entities decoded (`Who&#8217;s` -> `Who’s`).
- The artefact verifier: two real bugs (the `AttributeError` and the
  Gradle-1981 freshness check).

### Bulk probe (227 titles: TMDB catalogue + IMDb/Cinemeta, 60 of them anime
### at a random episode number, HTTP only, P2P off)

Per-scraper: sources listed, sources that really deliver bytes, and how
often the release file name matched the title - the four numbers the owner
asked for. Results in `artifacts/audit/bulk_probe.log` (SUMMARY lines)
and summarised in `docs/audit/2026-11-15-qoder-review-and-remaining.md`.

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

### Later round (2026-11-15, playback takeover)

Five playback defects were fixed in code after the score above was measured:
the liveness probe no longer kills sources whose HEAD answers with an HTML
player page, the failover chain skips sources already proven dead, the source
ranking is now codec- and size-aware (HEVC/AV1 and large files are penalised),
the torrent file index is part of the source identity, and the probe was
rewritten on `package:http` so the rules are unit-tested
(`test/playback_source_selection_test.dart`).

**The score is unchanged: 29 / 50 = 58.0 %** (29 / 51 = 56.9 % with B16).
A repaired check only counts as a pass once it is verified on a device, and
the owner runs that verification. Details:
`docs/audit/2026-11-09-music-creator.md`, section "Round 5".
