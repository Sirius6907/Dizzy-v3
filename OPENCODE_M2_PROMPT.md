# OpenCode M2 continuation — Tasks 7+8 ONLY (short credit window)

You are continuing Dizzy v1.3.5 work in C:\Users\opcha\Downloads\Dizzy-v3,
branch prism/v2-reskin, Git Bash. M1 (VidFast embed + adblock engine + mpv
handoff) is DONE and device-proven — do NOT re-verify it, do NOT touch it.

READ (only these): docs/superpowers/plans/2026-11-16-v135-playback-milestones.md
(Tasks 7 and 8), OPENCODE_V135_HANDOFF_PROGRESS.md (context: what exists),
lib/services/scraper/sites/vidfast.dart (the embed-source pattern to copy).

DO, in order:

1. TASK 7 — audit the 13 active HTTP scrapers + Knaben. Reuse the existing
   harness pattern in test/live_probe_bulk_test.dart (PROBE_SET env). Corpus:
   10 mainstream new + 10 old titles. NO Odia/regional titles. For every
   0-yield site, ALSO check the live site in a normal HTTP fetch (does the
   site still exist and serve pages?) before any verdict. Write
   artifacts/audit-dsh/scraper_audit_2026-11.md: one table row per site —
   ALIVE-direct / EMBED-PORTABLE / PARSER-BROKEN / TRULY-DEAD + evidence line.
   Do NOT retire anything; verdicts only. Owner decides.

2. TASK 8 — for sites the audit marks EMBED-PORTABLE (expected: vidlink,
   vidup, kisskh, meowtv), rewrite each scraper exactly like vidfast.dart:
   externalUrl embed source, url null, behaviorHints['dizzyEmbed']=true,
   IMDb fallback, enc-dec chain deleted. TDD: one failing test per site
   (embed URL shape) then the rewrite. Copy the vidfast pattern — no new
   mechanisms. lmscript/a111477/rivestream stay untouched (ALIVE-direct).

TOKEN RULES (hard):
- Targeted tests only per task; ONE full suite run at the very end
  (flutter test --no-pub --name '^(?!bulk corpus probe$)') and one
  flutter analyze --no-pub.
- Probe runs: single batch, not per-site loops.
- No exploration outside the named files; no refactoring; no new dependencies.
- If a site's embed endpoint can't be confirmed from its page/docs, mark it
  PARSER-BROKEN with the evidence and move on — do not reverse-engineer
  protected players.

CONSTRAINTS: no commit/push/tag/deploy; no adb uninstall/clear-data; no
Supabase changes; secrets stay in .env. Append one line per task to
OPENCODE_V135_HANDOFF_PROGRESS.md with command evidence.

STOP when Tasks 7+8 are done and the final gates pass, and report the audit
table + ports in the ledger. Anything left (Task 9 repairs, Task 10 torrent,
Task 11 supabase) is the next agent's scope — list it in the ledger, don't
start it.
