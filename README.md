<p align="center">
  <img src="assets/icon.png" alt="Dizzy" width="140"/>
</p>

<h1 align="center">Dizzy</h1>

<p align="center">
  <b>The Universal Entertainment Client</b><br/>
  Movies, TV Series, Anime, Manga, Audiobooks, Music & IPTV — All in One.
</p>

<p align="center">
  <img height="20" src="https://img.shields.io/badge/version-v1.3.1-7C5CFF?style=flat" alt="Version"/>
  <img height="20" src="https://img.shields.io/badge/developer-Sirius-00E5FF?style=flat" alt="Developer"/>
  <img height="20" src="https://img.shields.io/badge/license-GPL--3.0-4169A1?style=flat" alt="License"/>
  <img height="20" src="https://img.shields.io/badge/Flutter-3.47-02569B?style=flat&logo=flutter&logoColor=white" alt="Flutter"/>
  <a href="https://dizzy-by-sirius.netlify.app"><img height="20" src="https://img.shields.io/badge/site-dizzy--by--sirius-E8912A?style=flat" alt="Website"/></a>
</p>

---

## About

**Dizzy** is a unified, high-performance streaming client built with Flutter. It brings together movies, series, anime, live IPTV, music, manga, and audiobooks into one fluid interface with hardware-accelerated playback — and works without an account (anonymous-first).

Developed and maintained by **[Sirius](https://github.com/Sirius6907)**.

## Highlights

- ⚡ **Instant Auto-Play:** 1-second auto playback with intelligent source selection.
- 🛡️ **Pre-Stream Health Probe:** Discards dead, 403, and unreachable links before playback.
- 🍪 **Accept Cookies & Direct Stream Engine:** Native session cookie handling for high-speed CDNs.
- 🎬 **Movies & Series:** Multi-source VOD scrapers, Real-Debrid, and Stremio addon integration.
- ⛩️ **Anime Hub:** Native Japanese and multi-language providers with automatic skip-intro support.
- 📖 **Manga & Comics:** Responsive reader with continuous vertical and horizontal reading modes.
- 🎧 **Lossless Music & Audiobooks:** FLAC/lossless audio streaming and integrated audiobook player.
- 📺 **Live IPTV:** Fast M3U8 IPTV streaming with categories and EPG support.
- 👥 **Watch Together:** One-tap rooms, queue voting, voice + chat, late-join catch-up.
- 📡 **Resilient by default:** DizzyNet retries/circuit-breaker/offline queue, silent-fail → admin log.

## Downloads

Download the latest releases from the [Releases](https://github.com/Sirius6907/Dizzy-v3/releases) page — the [landing page](https://dizzy-by-sirius.netlify.app) picks the right build for your OS/ABI automatically:

| Platform | Format |
|:---------|:-------|
| **Android** | Per-ABI APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`) + Universal APK + legacy-signature mirrors |
| **Windows** | Portable ZIP & Inno Setup Installer |
| **Linux** | AppImage & Portable Tarball |

Updates roll out in-app: Android updates itself (sha256-verified OTA), desktop builds update from the release feed.

## Operations

- **Landing:** https://dizzy-by-sirius.netlify.app
- **Admin dashboard:** https://dizzy-s-admin.netlify.app (device fleet, crash log feed, downloads)
- **CI:** every push runs `flutter analyze` + full test suite (1095+ tests) + gitleaks secret scan (`.github/workflows/ci.yml`); releases build on tag push (`.github/workflows/build.yml`)

## Building from Source

Requirements: Flutter 3.47.x (Dart 3.11+)

```bash
git clone https://github.com/Sirius6907/Dizzy-v3.git
cd Dizzy-v3
flutter pub get
flutter analyze   # zero issues
flutter test      # full suite
flutter run
```

> Local-only product docs (`PRD.md`, `TRD.md`, `UIUX.md`, `Backend.md`) and session `memory/` live on the developer machine by design and are gitignored.

---

<p align="center">
  Crafted with ❤️ by <b><a href="https://github.com/Sirius6907">Sirius</a></b>
</p>
