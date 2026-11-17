# Dizzy — Stress Test + Brand Battle + Eval Gate (2026-11-12, round 2 brief)

Follow-up to `VIBE_ENGINE_BRIEF.md`. Run this AFTER the vibe-engine round
finishes (its report section `## Vibe engine round (2026-11-12)` must exist
in `docs/audit/2026-11-09-music-creator.md` first). Same session, same hard
rules: NO git commit, NO git push, NO deploys, evidence for every claim,
stop on quota error.

The owner's standard: **Dizzy succeeds only if it matches the app logic and
system design of Netflix (home), Spotify (music) and Crunchyroll (anime) —
the current 2026 products, not their 2020 versions.** The bar is a rigorous
eval averaging **99.3% success rate**. Compare honestly: where Dizzy is
behind, say so and fix it; never inflate scores. Same-weight-class framing —
do not declare victory over a giant without evidence.

## Task 1 — Full-app stress test (edge cases, end to end)

Drive the app like a hostile real user on emulator-5554 (vision verification:
adb input + screenshot + downscale + READ the image). Cover at minimum:

- Cold start / offline start / airplane-mode mid-session / network flap
  (the emulator's DNS breaks sometimes — treat recovery as a feature).
- Home: refresh during load, refresh spam, rails mid-stream, hero rotation,
  chip switching mid-fetch, brand rail absent (addon down) — UI must not
  blank or error-screen.
- Details → Play for: movie, series (season/episode switch), anime, a
  rail card (tmdb:), a bestsimilar card, a catalog brand card. Resume from
  Continue Watching, resume-at-end guard, auto-skip guard at 0:00.
- Music: play, queue extend near end, skip/like steering, radio regenerate,
  onboarding wizard re-entry, download, FLAC/YouTube source switch.
- Books/Manga/Audiobooks/Live TV/Addons/Downloads/My List: open each,
  exercise one real flow, capture.
- Navigation stress: rapid dock switching, back-button mashing, theme
  Light↔Dark toggle mid-flow, rotate/resize, app kill+relaunch state restore.

Log every failure with screenshot + logcat excerpt; fix what is in app
scope; document what is not fixable this round.

## Task 2 — Brand battle (evidence-based teardown)

For each surface, walk the REAL competitor flow (from knowledge, current
2026 product behavior — no invented features) and compare Dizzy honestly:

1. **Home vs Netflix** — start-up speed to content, hero, rails, continue
   watching, profile-aware recommendations, offline behavior.
2. **Music vs Spotify** — onboarding, home personalization, queue/radio
   quality, search, library, now-playing UX, source switching.
3. **Anime vs Crunchyroll** — catalog depth per season, episode list UX,
   subs/dubs handling, watchlists, simulcast freshness.

Deliver a scorecard per surface in the report: criterion, Dizzy score /10,
competitor behavior, the ONE fix that closes the biggest gap. Score only
what you verified on-device; mark unverified criteria as unverified —
never guess scores.

## Task 3 — Eval gate (99.3% bar)

Build a repeatable eval harness saved as
`docs/superpowers/evals/2026-11-12-dizzy-eval.md`:

- Define the check matrix (every Task 1 flow + every Task 2 criterion),
  each check worth equal weight, pass/fail with evidence link.
- Run the full matrix; report average success rate. The target is 99.3%.
- Any failed check → fix in app scope → re-run until the measured rate is
  reported truthfully. If something CANNOT reach 99.3% this round (e.g.
  catalog depth is bounded by external addons), say it plainly with the
  measured number instead of padding the score.

## Deliverables

- Fixes + evidence screenshots (`stress-*.jpg`, `battle-*.jpg`).
- The eval doc + final measured score in the report.
- Append `## Stress + brand battle round (2026-11-12)` to
  `docs/audit/2026-11-09-music-creator.md` with VERIFIED / UNVERIFIED lists.
- No fake green: an unverified check counts as failed, not as pass.
