# DIZZY-V3 — OVERALL APP EXPERIENCE UPGRADE BLUEPRINT (UX1 - UX10)

## Current Status
- **Music Section (Phases M1 - M20):** 100% COMPLETE & VERIFIED (`flutter analyze` clean, 0 errors).
- **Overall App Experience (Phases UX1 - UX10):** ✅ COMPLETE — commit f3e7755 (analyze: 0 errors, tests 12+6 green). NOT pushed — user tests builds first.

---

## 📋 The 10 App Experience Phases:

### 🔍 UX1: Universal Spotlight Search
- Global Search modal/screen across Movies, TV Series, Anime, Music Tracks, Artists, and Playlists.
- Instant multi-category filter chips (`All`, `Movies`, `Anime`, `Music`, `People`).
- Keyboard shortcut: `Ctrl + K` / `Cmd + K` on Desktop, search icon on mobile header.
- Recent search query history with 1-tap replay & clear.

### 📦 UX2: Unified Master Download Hub
- Consolidated screen managing all offline downloads:
  - Video section: Movies & Series episodes with file size, resolution, and delete.
  - Music section: Offline downloaded tracks, albums, and playlists.
  - Unified Storage Gauge: Visual gradient bar showing Total Dizzy Storage vs Device Free Space.
  - 1-tap "Clean Cache" and "Export Downloads" options.

### ⚡ UX3: Adaptive Performance Engine & Low-End Device Mode
- Automatic device tier detection (budget, mid-tier, flagship/PC).
- Low-End Device Mode toggle:
  - Disables heavy Gaussian blurs (`liquid_glass` falls back to solid dark acrylic).
  - Enforces `ImageCaps` decode constraints to keep RAM strictly ≤ 1.5GB / ≤ 20% CPU.
  - Smooth 60fps animations on 2GB/3GB RAM Android phones.

### 🚀 UX4: First-Time Guided Onboarding & Superpower Cards
- 3-slide interactive onboarding carousel on first launch:
  1. "Everything in One Place" (Movies, Anime & Spotify-level Music).
  2. "Lossless Studio Audio & Zero Ads" (Offline downloads, karaoke lyrics, 5-band EQ).
  3. "Watch & Listen Together" (Real-time sync rooms with friends).
- Easy English, skip button, and smooth transition to home.

### 🎛️ UX5: Global Media Dock & Seamless Transition
- Bottom navigation dock with live audio wave pulse when music is playing.
- Seamless video-to-mini-player when navigating away from video player.
- Instant switch between video playback and music playback with conflict resolution.

### 🎨 UX6: Dynamic Theming & AMOLED Custom Accent Engine
- AppTheme enhancements:
  - AMOLED True Black mode (0x000000 for OLED battery saving).
  - Custom Hex Accent Color Picker.
  - Backdrop blur intensity slider.

### 💬 UX7: Humanized "Easy English" Error Handling & Offline State
- Replace any technical exception/error screens with friendly, calm Easy English messages.
- Clear retry action button and offline cached fallback banner.
- No cryptic error codes or crash dialogs.

### 👥 UX8: Unified Social Watch & Listen Together Hub
- Dedicated drawer/tab for Jam Sessions & Watch Parties.
- Active room status, connected avatars, and 1-tap invite link copying.
- Synchronized chat reaction emoji bubbles floating over video/music canvas.

### 🎮 UX9: TV / Gamepad & Keyboard Navigation Mode
- Full D-Pad controller navigation with glowing focus borders for Android TV / Gamepad.
- Desktop keyboard shortcuts: `Space` (Play/Pause), `M` (Mute), `F` (Fullscreen), `J/L` (Seek -10s/+10s).

### 🔄 UX10: Seamless In-App OTA Updater & Release Notes Studio
- Background version checker against GitHub releases.
- Beautiful "What's New" modal with feature breakdown.
- Seamless in-app download and update installation without leaving the app.

---
*Created on 2026-09-13. Ready to execute sequentially in the new session!*
