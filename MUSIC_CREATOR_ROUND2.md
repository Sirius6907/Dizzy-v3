# MUSIC CREATOR — Round 2 (post-user-testing fixes + dynamic library)

Round 1 (`docs/audit/2026-11-09-music-creator.md`) is done and the user TESTED it on the emulator. His verdict: the redesign is in, but the CONTENT LOGIC is weak. Your job now is content logic, not styling. All hard rules from `MUSIC_CREATOR_BRIEF.md` still apply (no commit/push/deploy, two-clay theme tokens only, no hardcoded keys, evidence for every claim, stop immediately on quota error). Emulator `emulator-5554` is running.

## Complaint 1 — Albums are broken (top priority)

The home shows album cards whose albums contain only 1–2 songs. That is incomplete data being presented as an album.

- Find where album/playlist cards come from (JioSaavn / Deezer clients, curated lists). Fetch the FULL tracklist of an album (JioSaavn album endpoint / Deezer `/album/{id}` tracks) before showing it as an album card.
- Minimum-completeness gate: a card may only present itself as an album if the full tracklist resolved (≥5 tracks, or the album's real count from the API). Otherwise render it as a song card or drop it.
- Tapping an album must open the album with ALL its tracks playable, not a stub list.
- Unit tests: completeness gate + full-tracklist mapping.

## Complaint 2 — Up-next must be taste-continuation of the CURRENT song

When a song is playing, the user opens the queue to see "what's next". Today whatever is there is not related to the current song.

- Build "Up Next (for this song)": the next-up list is auto-generated from the currently playing track — same artist's other tracks, same/matching genre + language + mood + tempo bucket, blended with the user's taste profile (play history, likes, mood usage from `music_stats_service.dart` / existing taste engine).
- The list must visibly change when the currently playing song changes (different seed → different next-up). Make it selectable: user taps any song to play it next or jump (the queue drawer work from round 1 is the base — extend `music_queue_drawer.dart` / `music_smart_mix_service.dart` / `music_radio_service.dart`, don't rewrite the player contracts).
- No fixed/fallback track lists. If the taste signal is cold, use the current song's own metadata as the seed.
- Unit tests: seed → next-up ordering, seed-change → list-change, cold-start behavior.

## Complaint 3 — Trending is flat

The "Trending" hero + list is one flat list. Make it a live, multi-surface surface:

- Trending = daily-refreshed rails (today's top tracks, trending artists, viral albums, trending per mood chip). Rotate the hero daily.
- Everything must refresh: cache TTL for music feeds = 24h with date-seeded variation (same day stable, next day different), so the app never looks frozen.

## Complaint 4 — NOTHING fixed, everything dynamic

The user explicitly said: no song may be hardcoded and shown on the app. Everything must be dynamic, refreshed daily, with NEW types of playlists/mixes/albums generated ("albums that handpick thousands of songs" = large auto-curated mega-mixes).

- Audit ALL music code for hardcoded track/album/playlist lists (grep for literal song titles/ids in `lib/services/music/` and `lib/pages/music/`) and replace them with generated content. The ONLY allowed constants are source endpoints/config.
- Implement a Daily Mix generator: N mixes per day, generated from (taste profile × mood × language × decade), with date-seeded selection so each day's set is fresh and each mix has 30–100+ tracks (mega-mixes allowed and encouraged). Playlists/mixes regenerate daily; the generator must never hardcode titles.
- Unit tests: date-seed stability within a day, change across days, no-hardcode audit is a test (scan source for forbidden literals in the generator path).

## Complaint 5 — The engagement engine (how Spotify/YT Music keep you listening)

The user's real ask: someone opens the app for ONE song and ends up listening to 10–20 songs — because Spotify/YT Music make every next action mood-and-time-correct. Study how those apps do it, then build it:

- **Seed-based radio by default:** when a song starts, a radio queue is silently generated from that seed (artist → similar artists → genre/lang/mood matches, tempo bucket). The queue never runs dry — when it nears the end it extends itself using the songs the user actually played/skipped this session (skip = signal against, replay/like = signal for). This is Spotify's autoplay behavior.
- **Next-up chooser:** the queue drawer's next-up must be the radio continuation of the CURRENT song (this merges with Complaint 2 — same mechanism, one implementation).
- **Time-and-mood aware home:** home content is assembled from the user's local time-of-day (morning/afternoon/late-night), current mood chip, and what's trending NOW — not from static lists. A user opening the app at 11pm sees late-night/chill surfaces, not the same rail as their morning.
- **Real-time trending from sources, not guesses:** trending must come from live chart endpoints of the existing clients (JioSaavn charts/weekly-top, Deezer editorial charts) — if a client can't provide a chart, that surface hides; never fake it with a hardcoded list.
- **Friction-free next actions:** every playing screen always shows the next obvious action (Play radio for this song / Play next / Add to a mix) so the user never dead-ends.
- **Session learning:** within a session, positive signals steer the generator (same-artist boost, mood affinity); it must be observable in tests via a signal → next-up order change.
- Unit tests: radio generation from seed, auto-extension on queue nearing end, skip/like steering, time-of-day bucket → home assembly, chart-source hiding when absent.

## Verification bar

- `flutter analyze --no-pub` clean on all touched files.
- All new tests + existing music tests pass.
- Emulator screenshots: an album card opening with full tracklist; queue showing next-up different for two different currently-playing songs; today's mixes (then prove date-seed change via unit test, not by waiting for tomorrow).
- Append a "## Round 2" section to `docs/audit/2026-11-09-music-creator.md` with the same VERIFIED / UNVERIFIED discipline.
