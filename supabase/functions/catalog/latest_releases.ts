/**
 * Latest-releases catalogue helper (2026-11-14).
 *
 * Goal: a release-date-driven "latest N" catalogue for India, so the Home
 * rails surface what actually came out this month instead of whatever is
 * most popular - and Ollywood (Odia) titles are not lost because TMDB's
 * Odia coverage is thin.
 *
 * Data sources, merged in this order of trust for the release date:
 *   1. TMDB  - primary_release_date, exact date, language buckets
 *   2. IMDb  - title search + release year, used for titles TMDB misses
 *   3. OMDb  - release date / imdb rating for titles only IMDb knows
 *
 * The pure functions (mergeLatest / sortByReleaseDate / normaliseTitle)
 * are unit tested in latest_releases_test.ts. This file is NOT wired into
 * index.ts yet: it needs `deno check`, a local run, and an owner-approved
 * deploy (see docs/audit/2026-11-14-approvals-and-eval-plan.md).
 */

export type Source = "tmdb" | "imdb" | "omdb";

export interface LatestTitle {
  id: string; // provider id, prefixed: "tmdb:656908" | "imdb:tt123" | "omdb:tt456"
  tmdbId?: string;
  imdbId?: string;
  title: string;
  originalTitle?: string;
  releaseDate: string; // YYYY-MM-DD, "" when unknown
  year?: string;
  lang: string; // original language / "or" for Odia
  rating?: number;
  votes?: number;
  poster?: string;
  source: Source;
  sources: Source[]; // every provider that knew this title
}

export const BOLLYWOOD_LANGS = ["hi", "te", "ml", "kn"] as const;
export const OLLYWOOD_LANGS = ["or"] as const;

export function normaliseTitle(value: string): string {
  return value
    .toLowerCase()
    .replace(/\([^)]*\)/g, " ")
    .replace(/[^a-z0-9 ]+/g, " ")
    .replace(/\b(the|a|an|of|and|part|ka|ki|ke)\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Damerau-Levenshtein distance (transpositions count as one edit).
 *
 * Needed because the same film arrives spelled differently across
 * providers: "Madhumallati" / "Madhumalati", "Memshab" / "Memsaab",
 * "Chhi Re Nani" / "Chi Re Nani", "Apekhya" / "Apeksha". Without this the
 * merge keeps both rows and the catalogue shows duplicates.
 */
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

/** Titles within this many edits of each other are the same film. */
export function isSameTitle(a: string, b: string): boolean {
  const ka = normaliseTitle(a);
  const kb = normaliseTitle(b);
  if (!ka || !kb) return false;
  if (ka === kb) return true;
  const limit = ka.length <= 8 ? 1 : 2;
  return editDistance(ka, kb) <= limit;
}

/** Merge provider rows into one list, keyed by normalised title. */
export function mergeLatest(
  ...groups: LatestTitle[][]
): LatestTitle[] {
  const byKey = new Map<string, LatestTitle>();
  const keys: string[] = [];
  const findKey = (title: string, lang: string): string | null => {
    const key = normaliseTitle(title) || normaliseTitle(title);
    if (byKey.has(key)) return key;
    for (const existing of keys) {
      const row = byKey.get(existing)!;
      if (row.lang !== lang) continue;
      if (isSameTitle(row.title, title) || isSameTitle(row.originalTitle ?? "", title)) {
        return existing;
      }
    }
    return null;
  };
  for (const group of groups) {
    for (const row of group) {
      const key = normaliseTitle(row.title) || normaliseTitle(row.originalTitle ?? "");
      if (!key) continue;
      const target = findKey(row.title, row.lang) ?? findKey(row.originalTitle ?? "", row.lang);
      if (target === null) {
        byKey.set(key, { ...row, sources: [row.source] });
        keys.push(key);
        continue;
      }
      // Keep the richest field per provider, and remember every provider.
      const existing = byKey.get(target)!;
      const merged: LatestTitle = { ...existing };
      if (!merged.tmdbId && row.tmdbId) merged.tmdbId = row.tmdbId;
      if (!merged.imdbId && row.imdbId) merged.imdbId = row.imdbId;
      if (!merged.releaseDate && row.releaseDate) merged.releaseDate = row.releaseDate;
      if (!merged.year && row.year) merged.year = row.year;
      if (!merged.poster && row.poster) merged.poster = row.poster;
      if ((row.rating ?? 0) > (merged.rating ?? 0)) merged.rating = row.rating;
      if ((row.votes ?? 0) > (merged.votes ?? 0)) merged.votes = row.votes;
      if (row.source === "tmdb") merged.source = "tmdb";
      merged.sources = Array.from(new Set([...merged.sources, row.source]));
      byKey.set(target, merged);
    }
  }
  return Array.from(byKey.values());
}

/** Newest first; unknown dates sink to the bottom, then title order. */
export function sortByReleaseDate(rows: LatestTitle[]): LatestTitle[] {
  return [...rows].sort((a, b) => {
    if (a.releaseDate && b.releaseDate && a.releaseDate !== b.releaseDate) {
      return a.releaseDate < b.releaseDate ? 1 : -1;
    }
    if (a.releaseDate && !b.releaseDate) return -1;
    if (!a.releaseDate && b.releaseDate) return 1;
    return a.title.localeCompare(b.title);
  });
}

/**
 * Keep only the titles that are actually out.
 *
 * A film with a poster and a future release date has no source yet, so
 * putting it in the rail is what makes the app look like it has the
 * content and then fail to play it.
 */
export function releasedOnly(
  rows: LatestTitle[],
  untilIso: string,
): LatestTitle[] {
  return rows.filter((r) => !!r.releaseDate && r.releaseDate <= untilIso);
}

/** The final "latest N" slice per language bucket. */
export function latestFor(
  rows: LatestTitle[],
  langs: readonly string[],
  perLang = 50,
): LatestTitle[] {
  const out: LatestTitle[] = [];
  for (const lang of langs) {
    const bucket = sortByReleaseDate(rows.filter((r) => r.lang === lang));
    out.push(...bucket.slice(0, perLang));
  }
  return sortByReleaseDate(out);
}

// --- provider adapters -----------------------------------------------------

const TMDB = "https://api.themoviedb.org/3";
const OMDB = "https://www.omdbapi.com/";

/**
 * Injected TMDB reader. The catalogue edge function already has one (it
 * supports a bearer token), so this helper does not have to own the key.
 * `apiKey` stays for the standalone use.
 */
export type TmdbFetch = (
  path: string,
  params: Record<string, string>,
) => Promise<Record<string, unknown>>;

export async function tmdbLatest(
  apiKey: string,
  lang: string,
  sinceIso: string,
  limit = 100,
  fetchJson?: TmdbFetch,
  kind: "movie" | "tv" = "movie",
): Promise<LatestTitle[]> {
  const dateField = kind === "tv" ? "first_air_date.gte" : "primary_release_date.gte";
  const params: Record<string, string> = {
    region: "IN",
    language: "en-IN",
    with_original_language: lang,
    with_origin_country: "IN",
    [dateField]: sinceIso,
    sort_by: kind === "tv" ? "first_air_date.desc" : "primary_release_date.desc",
    include_adult: "false",
    include_video: "false",
    page: "1",
  };
  let data: { results?: Record<string, unknown>[] };
  if (fetchJson) {
    data = (await fetchJson(`/discover/${kind}`, params)) as {
      results?: Record<string, unknown>[];
    };
  } else {
    const url = new URL(`${TMDB}/discover/${kind}`);
    url.searchParams.set("api_key", apiKey);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`tmdb ${lang} ${res.status}`);
    data = (await res.json()) as { results?: Record<string, unknown>[] };
  }
  return (data.results ?? []).slice(0, limit).map((r) => {
    const date = String(
      kind === "tv" ? r.first_air_date ?? "" : r.release_date ?? "",
    );
    return {
      id: `tmdb:${r.id}`,
      tmdbId: String(r.id),
      title: String(r.title ?? r.name ?? r.original_title ?? ""),
      originalTitle: r.original_title ? String(r.original_title) : undefined,
      releaseDate: date,
      year: date ? date.slice(0, 4) : undefined,
      lang,
      rating: typeof r.vote_average === "number" ? r.vote_average : undefined,
      votes: typeof r.vote_count === "number" ? r.vote_count : undefined,
      poster: r.poster_path
        ? `https://image.tmdb.org/t/w500${r.poster_path}`
        : undefined,
      source: "tmdb" as Source,
      sources: ["tmdb" as Source],
    };
  });
}

/** IMDb title search (the public suggestion endpoint) for titles TMDB missed. */
export async function imdbSearch(
  title: string,
  lang: string,
  limit = 5,
): Promise<LatestTitle[]> {
  const url = `https://v3.sg.media-imdb.com/suggestion/x/${encodeURIComponent(title)}.json`;
  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (!res.ok) return [];
  const data = (await res.json()) as { d?: Record<string, unknown>[] };
  return (data.d ?? [])
    .filter((r) => String(r.id ?? "").startsWith("tt"))
    .slice(0, limit)
    .map((r) => ({
      id: `imdb:${r.id}`,
      imdbId: String(r.id),
      title: String(r.l ?? r.s ?? ""),
      releaseDate: typeof r.y === "number" ? `${r.y}-01-01` : "",
      year: typeof r.y === "number" ? String(r.y) : undefined,
      lang,
      source: "imdb" as Source,
      sources: ["imdb" as Source],
    }));
}

/** OMDb gives an exact release date + rating for an imdb id. */
export async function omdbByImdbId(
  apiKey: string,
  imdbId: string,
  lang: string,
): Promise<LatestTitle | null> {
  const url = new URL(OMDB);
  url.searchParams.set("apikey", apiKey);
  url.searchParams.set("i", imdbId);
  const res = await fetch(url);
  if (!res.ok) return null;
  const data = (await res.json()) as Record<string, unknown>;
  if (data.Response !== "True") return null;
  const released = String(data.Released ?? "");
  const iso = /^\d{4}-\d{2}-\d{2}$/.test(released) ? released : "";
  return {
    id: `omdb:${imdbId}`,
    imdbId,
    title: String(data.Title ?? ""),
    releaseDate: iso,
    year: iso ? iso.slice(0, 4) : undefined,
    lang,
    rating: typeof data.imdbRating === "string"
      ? Number(data.imdbRating) || undefined
      : undefined,
    source: "omdb" as Source,
    sources: ["omdb" as Source],
  };
}

/** Full pipeline for one language bucket. */
export async function buildLatestBucket(
  opts: {
    tmdbKey: string;
    omdbKey?: string;
    lang: string;
    sinceIso: string;
    untilIso?: string;
    perLang?: number;
    imdbTitles?: string[];
    fetchJson?: TmdbFetch;
    kind?: "movie" | "tv";
  },
): Promise<LatestTitle[]> {
  const kind = opts.kind ?? "movie";
  const tmdbRows = await tmdbLatest(
    opts.tmdbKey,
    opts.lang,
    opts.sinceIso,
    100,
    opts.fetchJson,
    kind,
  );
  const missing = (opts.imdbTitles ?? []).filter(
    (t) => !tmdbRows.some((r) => normaliseTitle(r.title) === normaliseTitle(t)),
  );
  const imdbRows: LatestTitle[] = [];
  for (const title of missing) {
    imdbRows.push(...(await imdbSearch(title, opts.lang)));
  }
  const omdbRows: LatestTitle[] = [];
  if (opts.omdbKey) {
    for (const row of imdbRows) {
      if (!row.imdbId) continue;
      const omdb = await omdbByImdbId(opts.omdbKey, row.imdbId, opts.lang);
      if (omdb) omdbRows.push(omdb);
    }
  }
  const merged = mergeLatest(tmdbRows, imdbRows, omdbRows);
  // Unreleased titles have a poster but no source - keep them out.
  const released = opts.untilIso
    ? releasedOnly(merged, opts.untilIso)
    : merged;
  return latestFor(released, [opts.lang], opts.perLang ?? 50);
}
