# OpenCode brief — Music section redesign + human notifications (creator mode)

You are a CREATOR/BUILDER agent on the Dizzy Flutter app (`C:\Users\opcha\Downloads\Dizzy-v3`, branch `prism/v2-reskin`). Your predecessor audits are done; now you BUILD. Work autonomously, test-first where the logic is pure, and verify UI on the `dizzy_test` Android emulator (already booted, device id `emulator-5554`, package `com.sirius6907.dizzyv3`).

## Hard rules (violating any = failed run)

1. NO `git commit`, `git push`, `git tag`, no Supabase deploy, no Netlify deploy, no `adb uninstall` / clear-data.
2. Do NOT touch or revert other uncommitted work in the tree (player/home/support/theme files are mid-flight from another agent — edit only music + notification files listed below).
3. Exactly two themes exist: Light Clay / Dark Clay (`AppThemeService.currentPalette`, tokens in `lib/design/prism_tokens.dart`). No raw `Colors.white`/`Colors.black` in new UI — use palette tokens (`palette.silverAccent` is the ink color: black on light, white on dark). No new theme pickers, no per-module theme grids.
4. No hardcoded API keys, no new .env entries. Music sources already exist as clients (deezer, jiosaavn, qobuz, youtube) — reuse them.
5. Never break the existing player/queue contracts in `lib/services/music/music_player_controller.dart` and `music_queue_ops.dart` — extend, don't rewrite.
6. Every claim you make in your report needs evidence: a passing test, `flutter analyze` output, or an emulator screenshot saved under `artifacts/audit-dsh/` (downscale screenshots to ~540px JPEG with ffmpeg before viewing).
7. If you hit a free-quota error, stop immediately and write what's done + what remains in your report file. Do not retry in a loop.

## Task 1 — Music section redesign (views: Complete + Explore)

Current code: `lib/pages/music/music_page.dart` + `lib/pages/music/views/` (home, browse, library, radio, search) + `lib/pages/music/widgets/` (~30 widgets).

First, self-review as an unbiased user against the best award-winning music app screens (Apple Music, Spotify, Tidal, Awwwards-winning music web concepts): typography scale, hero/billboard usage, whitespace rhythm, color saturation of artwork-derived gradients (`music_artwork_palette_service.dart` exists), section transition, discoverability of modes/moods, empty states.

Then redesign:
- Complete restyle of the Music home + library + explore/browse views. Keep navigation structure (mobile bottom nav + sidebar) but restyle surfaces.
- Color saturation: artwork-derived backgrounds must feel rich, not washed out. Tune `music_dynamic_canvas_background.dart` + `music_artwork_palette_service.dart` (contrast/saturation curve), verify on both Light Clay and Dark Clay.
- "Vast library": surface more content per view — more rails (trending artists exist; add moods/modes/decades/regional rails from existing clients; no new providers).
- "Modes preference song types": add a mode/mood selector (e.g. Focus / Workout / Romance / Party / Chill / Late Night) that filters/curates the queue or rails. Store preference in `music_settings.dart`.
- Similar-songs next-up: for the currently playing track, show a selectable "similar songs" list (next-up rail). `music_smart_mix_service.dart` + `music_radio_service.dart` + `music_match_policy.dart` are the building blocks — wire a clean UI into the expanded player / queue drawer, user can tap any song to play it next or jump.

## Task 2 — Notifications: human, flirty, taste-driven

Current: `supabase/functions/push-brain/index.ts` generates the copy (Hinglish templates) and `lib/services/notification/` handles delivery/inbox/history.

- Rewrite push-brain copy so it reads like a friend flirting over taste, not a bot: playful Hinglish, light emoji use (1–2, not spam), reference the user's actual taste signal (genre/lang/streak), vary sentence structure. Keep title ≤40 chars-ish, body ≤100. Keep the stable-variant retry logic.
- Image cards: FCM big-picture style — attach poster/backdrop from the picked title so the notification renders an image card (check current payload keys in `notification_service.dart` / `push_send` fn and wire the image field end-to-end).
- Correct deep-link wiring: tapping the notification must land on the exact title's details page (payload must carry type + tmdb/imdb id; the app's tap handler must route to details, not just home). Trace the current tap path and fix the gap.
- Add tests for any pure copy/routing logic you touch.

## Report

Write findings + what you changed + what's verified + what's left to `docs/audit/2026-11-09-music-creator.md`. End the file with a VERIFIED (with evidence) vs UNVERIFIED split.

## Emulator quick reference

- Screenshots: `adb -s emulator-5554 exec-out screencap -p > artifacts/audit-dsh/x.png` then `ffmpeg -y -i x.png -vf scale=400:-1 x.jpg` and Read the jpg.
- Logs: `adb -s emulator-5554 logcat -d | grep -i flutter`.
- Rebuild + install: `export PATH="/c/Users/opcha/flutter/bin:/c/tools/platform-tools:$PATH"` then `flutter build apk --debug --target-platform android-x64 --dart-define-from-file=.env` and `adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`.
- The emulator's network is flaky — if requests time out, re-check net before blaming the app.
