# Dizzy — Marketing & Promotion Strategy

> Working doc for the Dizzy launch push. No secrets in here. Last updated: 2026-10-02 (post v1.3.1, landing v2 live).
> Rule of the whole plan: **lead with "Watch Together"** — it is the only feature nobody else does in one app, and the only one that spreads by itself.

---

## 1. Positioning (the one sentence everything repeats)

**"Send one link. Everyone hits play at the same second."**

Everything downstream — posts, README, video clips, directory listings — repeats this first, then
the supporting trio: *free & open source · Android + Windows + Linux · no account, no ads.*

### Message house

| Level | Line |
|---|---|
| Headline | Watch together. Your media, your rules. |
| Sub | One app for movies, shows, anime, live TV, music, audiobooks and manga — sync watch rooms, voice chat, offline downloads. |
| Proof | 100% open source (GPL-3.0) · CI-built signed releases · no ads, no trackers, no account |
| Differentiator | One shared timeline: pause anywhere, the whole room pauses there. |
| CTA | Download for your device (OS auto-detected on the landing page) |

### Audience segments (in priority order)

1. **Friend groups / long-distance pairs** — the sync-room hook. Non-technical; needs Easy English, big buttons (already the product direction).
2. **Anime & manga communities** — Discord servers, Telegram groups. They already watch "together" badly via voice + screen share.
3. **Stremio/Real-Debrid power users** — Dizzy speaks their language (Debrid + Stremio addons + IPTV). Sceptical crowd, they trust GitHub + source.
4. **FOSS / privacy-curious Android users** — F-Droid, r/FOSS, It's FOSS. They install for the license and stay for the polish.
5. **Windows/Linux desktop users** — AppImage/Setup users who hate browser players.

---

## 2. Channel matrix

### Tier 0 — Evergreen assets (set up once, compounding forever)

| Item | Status | Action |
|---|---|---|
| Landing page (SEO + JSON-LD + FAQ schema) | ✅ live v2 | Submit sitemap |
| GitHub repo as homepage | ⚠️ partial | Add **topics** (`flutter`, `media-player`, `watch-together`, `anime`, `iptv`, `real-debrid`, `electron-alternative`…), GIF demo at top of README, badges (version/license/platform), star-history chart |
| Google Search Console + Bing Webmaster | ❌ | Verify domain, submit `sitemap.xml` |
| AlternativeTo listing | ❌ | List as alternative to Stremio / Plex / Kodi — this page ranks for "apps like X" queries for years |
| **Winget** (`winget install Dizzy`) | ❌ | PR to `microsoft/winget-pkgs` — one command for Windows users, permanent directory |
| **AUR** | ❌ | `PKGBUILD` for the AppImage — Arch users live here |
| **IzzyOnDroid** (F-Droid-compatible repo) | ❌ | They accept **developer-signed APKs** + do a reproducibility check → fastest path to an F-Droid-shaped install. Submit via their GitLab. |
| **F-Droid main repo** | ❌ | Needs an `fdroiddata` recipe (GitLab submission queue), FOSS license ✅ GPL-3.0. Slower, but it is the trust badge of the FOSS world. Start after IzzyOnDroid. |
| Flathub / Snap | ⏸ | Only if a Linux package (not just AppImage) is worth maintaining |
| Alternative directories | ❌ | Uneed, Fazier, Dev Hunt, Tiny Startups, It's FOSS news, FOSS Post — 10 min each |
| Obtaium compatibility | ✅ implicit | Mention in README: "install via Obtaium from GitHub releases" — auto-updates without Play Store |

### Tier 1 — Launch bursts (surgically timed, one per week max)

Order matters: **warm-up → Show HN → niche communities → Product Hunt last.**

1. **Show HN** — best ROI for an open-source project. HN rewards technical honesty + source.
2. **Niche subreddits** (one post each, days apart, never cross-posted same day).
3. **Dev Hunt / Uneed** — indie directories that still convert.
4. **Product Hunt** — only after there are real reviews/screenshots; needs a hunter + 100-person warm-up list. PH is the *last* swing, not the first.

### Tier 2 — Ongoing (30 min/day for 2 weeks after each release)

Short-form video (the actual growth engine for a media app), X/threads, Discord/Telegram community
drops, dev-content posts (Dev.to / Hashnode / Medium) that link back.

---

## 3. Phased plan

### Phase A — Setup (1–2 days, mostly mechanical)

- [ ] Repo topics + README hero GIF (6–10s screen recording of a room syncing) + badges
- [ ] Submit sitemap to Google Search Console + Bing Webmaster
- [ ] AlternativeTo listing (category: media players / streaming)
- [ ] Winget manifest PR + AUR PKGBUILD
- [ ] IzzyOnDroid submission
- [ ] In-app / landing **attribution**: every outbound share carries a source tag (see §6)
- [ ] Repo health: `SECURITY.md`, DMCA/takedown contact, a short `CONTENT-POLICY.md`
      (see §7 — this protects the GitHub repo, which is the whole distribution channel)
- [ ] Record 3 clips now (see §5): sync demo, voice room, install-in-60-seconds

### Phase B — Launch week (staggered, one channel per day)

| Day | Channel | Notes |
|---|---|---|
| D-2 | X/Twitter thread + Discord/Telegram own groups | warm-up, collect first reactions |
| D-1 | r/opensource + r/FOSS (check each sub's self-promo rules first) | text post: story + screenshots, not just a link |
| **D0** | **Show HN** | 12:00–14:00 IST works well (US evening overlap) |
| D+1 | r/AndroidApps, r/anime (check rules), r/RealDebrid, r/Stremio, r/Piracy-adjacent subs → **skip piracy subs**, see §7 | one post each, no cross-linking |
| D+2 | Dev Hunt / Uneed listing | |
| D+3 | YouTube Short / Instagram Reel / Reddit video | 20–30s sync demo (§5) |
| D+5 | Dev.to + Hashnode article: *"How we built a shared timeline across 3 platforms with Flutter"* | technical story, links to repo |
| D+7 | Product Hunt (only if D0→D+5 produced real users/issues) | |

**Rules for Reddit/HN:** answer every comment for 48h; disclose you're the author in line 1;
never post the same link to two subs the same day; r/AndroidApps allows dev posts with disclosure.

### Phase C — Ongoing growth loop (after launch)

- **Ship a visible release every 2–3 weeks** and post the changelog (r/opensource tolerates
  periodic updates if you also participate). v1.3.1 → v1.4 is the next natural beat.
- **One 20–30s vertical clip per release** (feature → 1 problem → proof → link). Media apps
  grow on video, not on text posts.
- **Dev-logs**: 1 technical article per month (sync protocol, Flutter on desktop, edge-function
  download counting). Each is an SEO asset that links to the landing page.
- **Community**: own Discord server with a `#watch-together` channel; put the invite in-app and
  in the README footer. This is where the friend-group segment converts.
- **Directory re-check quarterly** (AlternativeTo, Slant, awesome-Flutter / awesome lists PRs).

---

## 4. What makes this launch *convert* (product-side, not just posts)

1. **Room links are the growth loop.** A friend receives a link → they need the app → the
   link lands on a page that says *"Your friend is waiting — get Dizzy for {OS}"*. Add
   `?ref=room` on room links and surface it on the landing page. This is the single highest
   leverage change in this whole document.
2. **Install-in-60-seconds clip** answers the #1 objection (sideload fear) before it is asked.
3. **Social proof thresholds**: downloads only shown when ≥25 (already implemented), GitHub stars
   chip only when >0 (already implemented). Never show a number that reads as "nobody uses this".
4. **Press kit** in `/press`: logo, 3 screenshots, 50-word blurb, founder one-liner. Blogs copy
   whatever is easiest — make it easy.

---

## 5. Copy-paste templates

### Show HN
```
Show HN: Dizzy – open-source "watch together" media player (Android/Win/Linux)
https://dizzy-by-sirius.netlify.app

I built a media player where you send one link and everyone plays/pauses on the same
second — no screen-sharing, no "ok 3..2..1". It does movies, series, anime, live IPTV,
music, audiobooks and manga in one Flutter app, plus voice rooms and offline downloads.

Why it exists: every "watch together" hack I tried was a browser extension glued to a
streaming site. I wanted something my non-technical friends could install once.

Fully open source (GPL-3.0), releases built and signed by GitHub Actions, no ads/analytics
or account needed. Desktop (Windows/Linux) and Android share one codebase.

Repo: https://github.com/Sirius6907/Dizzy-v3
Would love feedback on the sync protocol — the interesting part is how a room stays
locked when one player buffers.
```

### Reddit (r/opensource or r/AndroidApps)
```
Title: I built Dizzy – a free, open-source media player where a whole room stays in sync
Disclosure: I'm the developer.

Most "watch together" tools are a screen share plus a chat message saying "pause now!".
Dizzy instead keeps one shared timeline: pause anywhere and everyone's player pauses there.
It also plays music/audiobooks/manga and downloads for offline.

- Android (split APKs), Windows installer, Linux AppImage
- No ads, no tracking, no account to start
- Every release is built in the open by GitHub Actions

Link: https://github.com/Sirius6907/Dizzy-v3
Happy to answer anything, and bug reports from real users are gold right now.
```

### X/Threads thread (opener)
```
1/ I built a media player where you send ONE link and everyone plays on the same second.
No screen share. No "3..2..1". Free + open source, Android/Windows/Linux. 🧵
[6–10s silent autoplay clip of two devices syncing]
```

### YouTube Short / Reel script (20–25s)
0–3s: "Stop screen-sharing movie night." (text over two phones)
3–10s: one person taps play → other phone plays in sync, pause → both pause.
10–16s: quick swipe through voice room + offline download.
16–22s: "Dizzy — free & open source. Link in bio."
Caption: `#opensource #flutter #anime #watchtogether`

### Press/dev-news pitch (It's FOSS / FOSS Post / Linux news)
```
Subject: Open-source media player that keeps a whole room on the same second

Hi — Dizzy is a GPL-3.0 media player (Android, Windows, Linux) that syncs playback across
everyone in a room instead of screen-sharing. It bundles anime/manga sources, live IPTV with
EPG, Real-Debrid/Stremio support, voice rooms and offline downloads — with no ads or account.

Everything is built by GitHub Actions from public source: [repo]. Screenshots and a press
kit: [link]. Happy to write something specific for your readers or do a quick Q&A.
```

---

## 6. Attribution & metrics (so we know what worked)

- The `dl` edge function already counts downloads. **Add per-channel `src` values** so every
  shared link/button can be tagged: `?src=showhn`, `src=reddit-os`, `src=fdroid`, `src=room`,
  `src=yt-short`. Then the dashboard shows which channel actually installs.
- Landing metrics to watch (privacy-friendly, CSP must allow it): unique visits, CTA click rate,
  which OS tab is chosen. If adding a beacon, extend `connect-src` in `_headers` for that origin.
- Weekly scoreboard: downloads (by src), GitHub stars/forks, installs from winget/F-Droid,
  room links created, Discord joins.
- **North-star:** *rooms created per week* — it proves the differentiator is being used, not
  just installed.

---

## 7. Legal & trust guardrails (read before posting anywhere)

1. **Position Dizzy as a player for content you have the rights to** + your own IPTV
   subscription. Never market it as a way to get free movies/series. This keeps the GitHub
   repo (our entire distribution channel) safe and keeps posts up.
2. **Do not post in piracy-focused communities.** The traffic looks tempting; the DMCA/abuse
   reports and Reddit removals are not worth it, and it attracts the wrong users who never
   star or contribute.
3. Keep a working **takedown / abuse contact** in the repo (`CONTENT-POLICY.md` + GitHub
   security contact). Hosts and GitHub respond much better to projects that have one.
4. Never claim fake numbers (users, ratings, "10k downloads"). The landing page shows real
   release data only, and that discipline is what makes the rest of the copy believable.
5. Every community has self-promo rules — read them before the first post, disclose authorship,
   participate before you promote.

---

## 8. What NOT to do

- ❌ Launch on 5 platforms the same day (looks like spam, burns the accounts).
- ❌ Buy followers/upvotes or run engagement groups (PH/Reddit will bury you).
- ❌ Google Play launch right now — sideload/streaming policy risk + $25 + review overhead for
   an audience that already installs APKs. Revisit only if the app grows past the FOSS crowd.
- ❌ Run paid ads before the room-link loop exists (you'd be paying for installs that don't
  invite anyone).
- ❌ Write a launch post and disappear — the 48h comment window is the actual launch.
