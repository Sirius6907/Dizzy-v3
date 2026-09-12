# Design QA Harness (Polish P16)

Har phase ke baad visual diff green — manual + auto, dono.

## Auto gate (CI, har commit pe)

```sh
flutter test test/design_contract_test.dart
```

Ye test saare polish contracts ek saath pakadta hai:
tokens ladder, motion freeze, P23 image caps, overscan == spacing,
200% font rail, kids gold, co-watch copy, settings search, guide
persistence. Koi contract toota = test chillayega, phase wapas karo.

## Manual matrix (release se pehle, user testing)

| Device | RAM | Check |
|---|---|---|
| 3GB Android phone | ≤3GB | cold open <1s, scroll jank zero, OOM zero |
| Tablet 10" | 4GB | hero 520px, rows 3-col, no overflow |
| Windows desktop | 8GB | hover states, arrows, search shortcuts |
| Firestick / Android TV | 2GB | DPAD full flow, focus ring visible, overscan safe |
| 200% font | — | koi toot-foot nahi (P12 rail) |
| Reduced motion ON | — | snap, no sweeps (P11 gate) |

## Screens (har ek ka screenshot lo, pichle se compare karo)

1. Home (hero + Trending Now + rows)
2. Details (backdrop, action row, cast)
3. Player (controls, quality/speed/aspect sheets)
4. Watch Party lobby + code card + co-watch overlay
5. Search (history chips, no-result, results)
6. Downloads (active %, paused, completed shelf)
7. Settings (search, tiles) + Profiles (kids ring)
8. Guides (3-card flow) + Error trio

## Golden files (follow-up)

`flutter test --update-goldens` se `test/goldens/` me capture karo,
phir CI me `--update-goldens` ke bina run = visual diff gate.
Headless CI me fonts alag hote hain — goldens hamesha same device
(user ka phone) se capture karo.
