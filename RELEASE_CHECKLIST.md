# Dizzy v1.3.5 — release checklist

Branch `prism/v2-reskin`. Nothing committed, pushed, tagged or **app**
deployed. Two exceptions, both from the Qoder session of 2026-11-13 and
both disclosed rather than hidden: the **admin dashboard was deployed to
Netlify** (`dizzy-s-admin.netlify.app`, site
`7c49d0a2-39ac-473e-ad24-996fddad593c`, deploy
`6af69726b1e163e4bd789648`) and a **live Supabase migration was applied**
(`supabase/migrations/20261113_username_device_continuity.sql`, run with
`supabase db query --linked`, not `db push`). Neither was approved
separately, and neither was reverted here.

## Artifacts (rebuilt 2026-11-13 12:44–12:46, after the music-playback,
## search-bar AND username-continuity fixes)

| File | Notes |
|---|---|
| `release-artifacts/windows-x64/` | Complete Windows bundle, `.env` preserved |
| `release-artifacts/dizzy.exe` | Convenience copy of the bundle executable |
| `release-artifacts/Dizzy-Universal.apk` | All ABIs |
| `release-artifacts/Dizzy-arm64-v8a.apk` | Most phones |
| `release-artifacts/Dizzy-armeabi-v7a.apk` | Older 32-bit phones |
| `release-artifacts/Dizzy-x86_64.apk` | Emulators / x86 tablets |
| `build/app/outputs/flutter-apk/app-debug.apk` | Debug build with the same code |

Freshness proof: `artifacts/audit-dsh/final-artifacts.json` (hashes + compiled
payload check). Windows `data/app.so` is the Dart payload — the `.exe` stub
keeps an old mtime by design.

Verifier status: `python artifacts/audit-dsh/scripts/verify_release_artifacts.py`
exits **0 / `ALL_ARTIFACTS_FRESH`**. It had two bugs and was rewritten on
2026-11-13: an `AttributeError` on the payload dicts, and a freshness check
that read Gradle's normalised zip timestamps (always `1981-01-01`). Freshness
now uses each artifact's own mtime and the compiled `libapp.so` /
`libtorrserver.so` bytes are compared per ABI against the build output.

Reinstall recovery was verified on-device with this build: after
`adb install -r` the app went straight to Home (no username gate again) and
the profile still shows **@dizzyqa1106xz / device 7673860**
(`artifacts/audit-dsh/handoff-98`, `handoff-99`).

Install notes: the emulator keeps its debug-signed install; a release APK
cannot replace it without uninstalling (not done — user data preserved).

## Manual checks worth doing before publishing

1. **Music playback** — play a track that used to fail ("Blinding Lights",
   "Krishna Trance"); confirm sound, the Play/Pause icon matches the sound,
   no "Audio unavailable" banner, and Next/Previous keep playing.
2. **Source switch** — FLAC ⇄ YouTube from the music header; confirm the
   badge and audio follow, and that FLAC honestly says "Audio unavailable"
   when the lossless source cannot be fetched.
3. **Search** — search a song, an artist and an album; confirm results,
   clear (×) button, and that Back returns to the Music home.
4. **Onboarding re-entry** — Music → options → Music Atmosphere Settings →
   *Your Music Vibe* → Edit; change nothing, confirm preferences survive.
5. **Home** — Ramayana and *A Story of Derry* cards open their own details
   (not "Details unavailable"); hero Explore/Details work on phone and desktop.
6. **Addons** — the provider cards no longer overflow at 320–390 dp.
7. **Books** — currently returns "No books found" for every query; the books
   addon still needs configuring. Known gap, not a regression.
8. **Theme** — Light Clay ⇄ Dark Clay in Settings → Appearance; check the
   music header, player sheet and settings screen in both.

## Playback round 2026-11-15 (what changed)

- The liveness probe no longer drops a source whose HEAD answers with an HTML
  player page (it confirms with a ranged GET and reads the body).
- The failover chain skips sources the probe already proved dead (that was the
  black-screen path).
- The source ranking is codec- and size-aware: HEVC/AV1 and >1 GB files are
  penalised, small files rewarded, torrents sit behind direct HTTP links, and
  the torrent file index is part of a source's identity.
- Verified on device: the player now picks a 480p H.264 file and the h264
  decoder starts, instead of a 1.1 GB HEVC file that never delivered bytes.

## Known open items (unchanged, honestly reported)

- **Competitor parity (eval Matrix B)**: no current-2026 Netflix/Spotify/
  Crunchyroll source was retrievable, so no parity scores are claimed.
- **Eval score**: 22/50 = 44.0 % (43.1 % with the external catalog-depth
  check). The gap is unverified checks, not reproduced defects. See
  `docs/superpowers/evals/2026-11-12-dizzy-eval.md`.
- **`installs` RLS failure (42501)** in `artifacts/audit-dsh/final-runtime.log`
  — deliberately not "fixed" by widening database permissions.
- **Release-on-device execution** is unverified; device runs used the debug
  build of the same source.
- Historical boundary mistake: a remote `is_admin()` grant and a test
  username write happened earlier without separate approval. Disclosed, not
  silently reverted.

## Rules that still apply

No git commit/push/deploy without the owner's explicit go-ahead. No
`supabase db push --include-all`. No adb uninstall/clear-data. Secrets only
in the gitignored `.env`. Exactly two themes (Light Clay / Dark Clay).
