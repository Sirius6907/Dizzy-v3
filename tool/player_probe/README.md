# Source Probe

A single player screen, built as its own Windows exe, that answers one question:

> Does **this** scraper give a playable video for **this** TMDB id?

It has no home, no feed, no failover chain — just resolve → scrape → open in mpv.
It reuses the shipped scrapers, `PlayerSettings` and media_kit, so what it
reports is the app's real behaviour, not a reimplementation of it.

## Build

```powershell
flutter build windows --release -t tool/player_probe/main.dart
```

The Windows build needs `nuget.exe` on `PATH` (the `flutter_inappwebview_windows`
plugin fetches three native packages at build time). If the build dies with
`Nuget.exe not found`, download it once and prepend its folder:

```powershell
$nugetDir = 'C:\Users\opcha\AppData\Local\Temp\opencode'
Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile "$nugetDir\nuget.exe"
$env:PATH = "$nugetDir;$env:PATH"
```

Then copy the bundle somewhere it can find `.env` (the env loader walks up to 8
parent folders from the exe, so anywhere inside the repo works):

```powershell
Copy-Item build\windows\x64\runner\Release artifacts\player_probe -Recurse -Force
Rename-Item artifacts\player_probe\dizzy.exe DizzySourceProbe.exe
```

## Test recipe

1. Pick a scraper (the dropdown marks scrapers retired in the app).
2. Enter a TMDB id — movie `550`, series `1399`.
3. Series: set season + episode, e.g. `1` / `1`.
4. **Resolve + Scrape** → the left list is what that scraper returned.
5. Click a row (or its ▶) → the player opens that source exactly like the app.

Read the result as:

| what you see | what it means |
| --- | --- |
| `0 sources` | the scraper, not the player: it returned nothing for that target |
| `ERROR …` | the scraper threw or timed out (45 s cap) |
| `OPEN OK` + a picture | this scraper is good for this target |
| `OPEN FAILED · No video after 25s` | a URL came back but mpv never got a frame |
| `MPV · …` in the log | mpv's own message — readable cause, e.g. 403 |

`HLS`, `DASH`, `MP4` rows open in mpv. `EMBED` and `TORRENT` rows are labelled
and disabled on purpose: they need the app's ad-blocked webview and TorrServer,
which is app plumbing the probe does not reimplement.

Every run also appends to `probe_results.log` next to the exe, and
**Copy report** puts the whole run on the clipboard for pasting into chat.

## What it deliberately does not do

- No torrent auto-quality, no failover, no health probe — those are app
  behaviour, already covered by the app's own tests.
- No sign-in: TMDB resolve uses the keyless-first chain (`EnvService` key →
  keyless speedrace), so the probe works from a bare exe.
- No ad-blocking in the embed webview (`dizzy_adblock.dll` is not built in this
  configuration), which does not matter because embeds are not played here.
