/**
 * Title matching shared by the resolver and the corpus sync.
 *
 * Pure functions only - no network, no Supabase - so they can be unit
 * tested in isolation (node --test / deno test).
 *
 * Why this exists (2026-11-14):
 * TMDB's /search endpoint cannot see most regional titles. Measured against
 * the owner's 50 latest Odia movies, 20 of them 404 on the resolver, and
 * for 18 of those 20 TMDB's /search returns ZERO hits - not a near miss, a
 * blank. /discover with with_original_language=or does return them. So the
 * resolver needs an INDEX (the corpus), not a better search.
 *
 * The matching rules below are deliberately conservative. A wrong match
 * plays the wrong film (poster A, playback B) across ~40 scrapers, so every
 * relaxation has to be paid for with a year/language guard.
 */

/** Lowercase, strip everything that is not a letter or digit. */
export function cleanTitle(value: string): string {
  return String(value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

/**
 * The "core" of a title: bracketed and subtitled parts removed, stop words
 * dropped.
 *
 *   "Dahaan: The Evil Within"  -> "dahaan"
 *   "AWM (Agney Weds Minal)"   -> "awm"
 *   "Bhai - The Opening Part"  -> "bhai"
 *
 * The stop-word list keeps the remaining words ("dahaan evil within" ->
 * "dahaan") because Indian titles often put the subtitle BEFORE the colon
 * marker or inside brackets.
 */
const STOP = /\b(the|a|an|of|and|part|ka|ki|ke|with)\b/g;

export function baseTitle(value: string): string {
  let s = String(value ?? "").toLowerCase();
  s = s.replace(/\([^)]*\)/g, " ");
  s = s.replace(/:\s*[^:]*$/g, " ");
  s = s.replace(/[–—\-]\s*[^–—\-]*$/g, " ");
  s = s.replace(STOP, " ");
  s = s.replace(/[^a-z0-9]+/g, "");
  return s;
}

/** Damerau-Levenshtein distance (a transposition counts as one edit). */
export function editDistance(a: string, b: string): number {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  const d: number[][] = Array.from({ length: a.length + 1 }, () =>
    new Array(b.length + 1).fill(0));
  for (let i = 0; i <= a.length; i++) d[i][0] = i;
  for (let j = 0; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
      }
    }
  }
  return d[a.length][b.length];
}

export interface ImdbCandidate {
  imdbId: string;
  title: string;
  year?: number | null;
}

/**
 * Pick the IMDb candidate that identifies the requested film.
 *
 * The same rule as the corpus match, and for the same reason: a NAME is
 * not an identity. "Game Over" is a 2026 Odia film AND a 2018 one, so a
 * candidate whose year disagrees by more than one year is rejected even
 * when the title matches exactly. What survives is a candidate that the
 * year CONFIRMS - those are the titles TMDB has never heard of, and
 * without this step the resolver answers 404 for them and no scraper can
 * find a source.
 */
export function pickImdbMatch(
  request: string,
  candidates: ImdbCandidate[],
  opts: { year?: number | null } = {},
): ImdbCandidate | null {
  const year = opts.year ?? null;
  const want = cleanTitle(request);
  const wantBase = baseTitle(request);
  if (!want && !wantBase) return null;

  const rank: MatchQuality[] = ["exact", "alias", "fuzzy"];
  let best: { c: ImdbCandidate; q: MatchQuality } | null = null;

  for (const c of candidates) {
    if (!c.imdbId) continue;
    const have = cleanTitle(c.title);
    const haveBase = baseTitle(c.title);
    if (!have && !haveBase) continue;

    let quality: MatchQuality | null = null;
    let needsYear = false;

    if (want && have === want) {
      quality = "exact";
    } else if (wantBase && haveBase && wantBase === haveBase) {
      if (wantBase.length >= 5) {
        quality = "alias";
      } else {
        const d = Math.min(
          want ? editDistance(want, have) : Infinity,
          wantBase ? editDistance(wantBase, haveBase) : Infinity,
        );
        if (d <= 2) {
          quality = "alias";
          needsYear = true;
        }
      }
    } else {
      const d = Math.min(
        want ? editDistance(want, have) : Infinity,
        wantBase ? editDistance(wantBase, haveBase) : Infinity,
      );
      if (d <= 1) {
        quality = "fuzzy";
        needsYear = true;
      }
    }

    if (!quality) continue;

    // The year guard, for every quality.
    if (year != null && c.year != null) {
      if (Math.abs(c.year - year) > 1) continue;
    } else if (needsYear) {
      // A fuzzy (or too-short core) match with no year to confirm it is
      // not safe - that is how "Murabi" ends up playing "Murali".
      continue;
    }

    if (!best) {
      best = { c, q: quality };
      continue;
    }
    const byQuality = rank.indexOf(quality) - rank.indexOf(best.q);
    if (byQuality !== 0) {
      if (byQuality < 0) best = { c, q: quality };
      continue;
    }
    const gap = (x: ImdbCandidate) =>
      year != null && x.year != null ? Math.abs(x.year - year) : 99;
    if (gap(c) < gap(best.c)) best = { c, q: quality };
  }

  return best ? best.c : null;
}

export interface CorpusRow {
  kind: "movie" | "tv";
  tmdbId: number;
  title: string;
  originalTitle?: string | null;
  year?: number | null;
  lang?: string | null;
  popularity?: number | null;
}

export type MatchQuality = "exact" | "alias" | "fuzzy";

export interface CorpusMatch {
  row: CorpusRow;
  quality: MatchQuality;
  /**
   * Safe = the match is strong enough to hand to the scrapers:
   *   exact - the cleaned titles are identical
   *   alias - the request's core title is identical (subtitle dropped)
   *   fuzzy - one edit apart AND the year agrees
   */
  safe: boolean;
  distance: number;
}

/**
 * Pick the best corpus row for a requested title.
 *
 * Order of preference (first match wins):
 *   1. exact   - cleaned title identical
 *   2. alias   - the request's CORE title equals the row's core title
 *   3. fuzzy   - one edit apart
 *
 * The YEAR GUARD applies to every quality, exact included. That is the
 * whole point: a name alone is not an identity. "Game Over" is a 2026 Odia
 * film and also a 2024 Spanish one, and the old name-only resolver answered
 * with the Spanish film. A request that names a year is never answered by
 * a row whose year is more than one year away.
 */
export function pickCorpusMatch(
  request: string,
  rows: CorpusRow[],
  opts: { kind?: "movie" | "tv"; year?: number | null } = {},
): CorpusMatch | null {
  const kind = opts.kind;
  const year = opts.year ?? null;
  const pool = kind ? rows.filter((r) => r.kind === kind) : rows;
  if (!pool.length) return null;

  const want = cleanTitle(request);
  const wantBase = baseTitle(request);
  if (!want && !wantBase) return null;

  const yearOk = (row: CorpusRow) => {
    if (year == null || row.year == null) return true;
    return Math.abs(row.year - year) <= 1;
  };

  /**
   * A match that rests on the NAME ALONE needs the year to CONFIRM it.
   * A row with no year at all cannot confirm anything, so it cannot answer
   * such a request - otherwise "Murabi" would happily answer with a
   * different film called "Murali".
   */
  const yearConfirms = (row: CorpusRow) => {
    if (year == null || row.year == null) return false;
    return Math.abs(row.year - year) <= 1;
  };

  let best: CorpusMatch | null = null;

  for (const row of pool) {
    const names = [row.title, row.originalTitle].filter(Boolean) as string[];
    let distance = Infinity;
    let quality: MatchQuality | null = null;
    // A match that rests on the NAME ALONE (a short core, or a one-edit
    // spelling) needs the year to pin it down; a specific core title
    // ("dahaan") identifies the film on its own.
    let needsYear = false;

    for (const name of names) {
      const have = cleanTitle(name);
      const haveBase = baseTitle(name);
      if (want && have === want) {
        distance = 0;
        quality = "exact";
        break;
      }
      const d = Math.min(
        want ? editDistance(want, have) : Infinity,
        wantBase ? editDistance(wantBase, haveBase) : Infinity,
      );
      if (d < distance) distance = d;
      if (wantBase && haveBase && wantBase === haveBase) {
        // A shared CORE title is only an alias when the core is specific
        // enough to identify a film ("dahaan") or the full titles are
        // nearly the same ("awm" is too short on its own).
        const coreSpecific = wantBase.length >= 5;
        if (coreSpecific) {
          quality = "alias";
          distance = 0;
          break;
        }
        if (d <= 2) {
          quality = "alias";
          needsYear = true;
          distance = 0;
          break;
        }
      }
    }

    if (!quality) {
      if (distance <= 1) {
        quality = "fuzzy";
        needsYear = true;
      } else {
        continue;
      }
    }

    // The year guard, for every quality.
    if (needsYear && !yearConfirms(row)) continue;
    if (!yearOk(row)) continue;

    const candidate: CorpusMatch = {
      row,
      quality,
      safe: true,
      distance: quality === "fuzzy" ? distance : 0,
    };

    if (best === null) {
      best = candidate;
      continue;
    }
    // Prefer a better quality, then a closer year, then popularity.
    const rank: MatchQuality[] = ["exact", "alias", "fuzzy"];
    const byQuality = rank.indexOf(candidate.quality) - rank.indexOf(best.quality);
    if (byQuality !== 0) {
      if (byQuality < 0) best = candidate;
      continue;
    }
    const candYearGap = year != null && candidate.row.year != null
      ? Math.abs(candidate.row.year - year)
      : 99;
    const bestYearGap = year != null && best.row.year != null
      ? Math.abs(best.row.year - year)
      : 99;
    if (candYearGap !== bestYearGap) {
      if (candYearGap < bestYearGap) best = candidate;
      continue;
    }
    if ((candidate.row.popularity ?? 0) > (best.row.popularity ?? 0)) {
      best = candidate;
    }
  }

  return best;
}
