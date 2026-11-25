// Version comparison for the v1.3.7 update campaign.
//
// Kept in its own module (like resolve/title_match.ts) so the one rule that
// decides whether a phone is nudged can be tested without Deno:
// a "please update" line must never reach a phone that already runs the
// target build — "v1.3.7 -> v1.3.7" is the definition of spam.

/** Numeric compare of dotted versions ("1.3.10" > "1.3.9"). A build suffix is
 *  compared numerically too, so "1.3.7+1039" ranks above "1.3.7". */
export function compareVersions(a: string, b: string): number {
  const parts = (v: string) =>
    v.replace(/^v/i, "").split(/[.+-]/).map((p) => parseInt(p, 10))
      .filter((n) => !Number.isNaN(n));
  const pa = parts(a);
  const pb = parts(b);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const x = pa[i] ?? 0;
    const y = pb[i] ?? 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

/** The version pair the campaign body carries: "v1.3.6 -> v1.3.7".
 *
 *  A token with no reported app_version used to fall back to the literal
 *  string "your version", which the body then wrapped in a `v`: every such
 *  phone read "v your version -> v1.3.7". Unknown has no honest left side, so
 *  the pair collapses to the destination alone — one true fact, no broken
 *  arrow. Placeholders arriving as "unknown"/"none"/"null" are treated as
 *  missing for the same reason. */
export function versionPair(from: string, latest: string): string {
  const dest = (latest ?? "").trim().replace(/^v/i, "");
  const src = (from ?? "").trim().replace(/^v/i, "");
  if (!dest) return "";
  if (!src || /^(unknown|none|null|n\/a|-)$/i.test(src)) return `v${dest}`;
  return `v${src} → v${dest}`;
}

/** True when a token's reported app_version is older than the campaign
 *  target. A token with no reported version predates version reporting, so it
 *  is treated as old rather than skipped. */
export function shouldNudge(appVersion: string, latestVersion: string): boolean {
  if (!appVersion) return true;
  return compareVersions(appVersion, latestVersion) < 0;
}
