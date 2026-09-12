# Copy Deck (Polish P20) — frozen user words

Release-ready bundle ka shabd-kosh. Ye file + `copy_deck_test.dart`
dono ek saath badalte hain — copy change = test update.

## Voice rules (har screen, har toast)

1. Easy English, max ~10 words per line.
2. Koi tech shabd nahi: error codes (E_*), exception names,
   "failed", "null", "timeout" raw kabhi screen pe nahi.
3. Har khaali/dead state me ek action (Try again / Explore / Clear).
4. Button order: Cancel (left, ghost) → confirm (right, filled, red if danger).
5. Toasts 3s (DizzyNotify), player auto-hide 4s (DizzyMotion).

## Frozen surfaces (source of truth = code, ye list map hai)

| Surface | Source | Tone |
|---|---|---|
| Guides (party/downloads/cloud/sources/subs) | AppGuides | 1-line, emoji icon |
| Co-watch overlay | PartyCoWatchOverlay | "Catching up…", "Host paused." |
| Search no-result | search_page | spelling hint + Clear |
| Downloads lines | DownloadProgressText + DownloadErrorText | % honest, easy errors |
| Errors | StateViewCopy | net/login/gone/generic |
| Profiles | KidsMode | gold kids, PIN state |
| Wrap | WrapCopy | cheer tiers, streak |
| Confirms | DizzyDialogs | Cancel left, confirm right |
| Party code sheet | watch_together_button | "Room ready! Friend ko code bhejo." |

## Banned words (test enforces)

exception, stacktrace/stack trace, nullptr/nullpointer,
E_NET_, E_HTTP_, E_HLS_, E_P2P_, E_DEBRID_, E_SPACE_, E_FILE_,
E_UNKNOWN, SocketException, TimeoutException, HttpException,
FormatException.

## Store assets (manual, release se pehle)

- Icon set: `assets/` freeze — naya icon to review ke baad.
- Screenshots (user ke phone se, 1080×2400): Home, Details,
  Player, Party code card, Downloads, Wrap.
- Feature graphic: hero art + "Watch Together" + Dizzy logo.
- Tag push SIRF user ke explicit OK ke baad (rule).
