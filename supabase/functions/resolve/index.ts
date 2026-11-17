// resolve — title→TMDB/IMDb ID resolution for scrapers (v1.2.0-C3).
// Env: TMDB_API_KEY or TMDB_BEARER (same as tmdb-proxy).
//      SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (optional: enables the
//      title corpus, which is how regional titles resolve at all).
// GET ?title=...&year=2024&type=movie|tv&imdbId=tt1234567&lang=or
// Returns {tmdbId, imdbId, year, title, source, matchQuality}.
//
// v1.3.5 (2026-11-14) — the "few sources" fix.
//
// Measured on the owner's 50 latest Odia movies, the OLD resolver answered
// 30/50 and 10 of those 30 were a COMPLETELY different film (a Spanish
// "GAME OVER", a Japanese "Monster", a Korean "Midnight"), because the
// exact-title gate matches on the NAME alone: TMDB search answers with
// whatever popular film carries that name. 20/50 were not answered at all,
// because TMDB's /search returns ZERO hits for most regional titles.
//
// So the resolver now:
//   1. asks the title CORPUS first (an index built from TMDB /discover,
//      which does see regional titles, and which carries the language and
//      the year - so a match is scoped, not just name-equal);
//   2. falls back to TMDB search with the same year + language guards;
//   3. admits a one-edit spelling difference ("Minall" / "Minal") only when
//      the year agrees.
//
// Wrong content is still the one thing that must never happen: every
// relaxation below is paid for with a year and/or language guard.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  baseTitle,
  cleanTitle,
  editDistance,
  pickCorpusMatch,
  pickImdbMatch,
  type CorpusRow,
} from "./title_match.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

function json(body: unknown, status = 200, cacheSec = 86400) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": `public, max-age=${cacheSec}`,
    },
  });
}

async function tmdbFetch(
  path: string,
  params: Record<string, string>,
): Promise<{ status: number; data: Record<string, unknown> }> {
  const apiKey = Deno.env.get("TMDB_API_KEY") ?? "";
  const bearer = Deno.env.get("TMDB_BEARER") ?? "";
  const target = new URL("https://api.themoviedb.org/3" + path);
  for (const [k, v] of Object.entries(params)) target.searchParams.set(k, v);
  const headers: Record<string, string> = { Accept: "application/json" };
  if (bearer) headers["Authorization"] = `Bearer ${bearer}`;
  else target.searchParams.set("api_key", apiKey);
  const res = await fetch(target.toString(), { headers });
  return { status: res.status, data: (await res.json()) as Record<string, unknown> };
}

/** The corpus is optional: without the DB secrets the resolver still works. */
type CorpusRowRaw = {
  kind: string;
  tmdb_id: number;
  title: string;
  original_title: string | null;
  year: number | null;
  lang: string | null;
  popularity: number | null;
};

async function loadCorpusCandidates(
  kind: "movie" | "tv",
  title: string,
  year: number | null,
): Promise<CorpusRow[]> {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !svc) return [];
  try {
    const { createClient } = await import(
      "https://esm.sh/@supabase/supabase-js@2"
    );
    const db = createClient(url, svc);
    const norm = cleanTitle(title);
    const base = baseTitle(title);
    const cols =
      "kind,tmdb_id,title,original_title,year,lang,popularity";

    // TWO queries on purpose.
    //
    // 1. The exact/alias lookup: narrow, indexed, always complete.
    // 2. The fuzzy candidate set: the year window, ordered by popularity.
    //
    // They must not be one query. The year window matches hundreds of
    // rows, and a LIMIT would then hand back an arbitrary slice that
    // often does NOT contain the row we came for - the exact match was
    // lost in the crowd.
    const exact = await db
      .from("title_corpus")
      .select(cols)
      .eq("kind", kind)
      .or(
        [
          `title_norm.eq.${norm}`,
          `title_base.eq.${base}`,
          `title_base.eq.${norm}`,
        ].join(","),
      )
      .limit(50);

    const rows: CorpusRow[] = [];
    const seen = new Set<number>();
    const push = (r: CorpusRowRaw) => {
      if (seen.has(Number(r.tmdb_id))) return;
      seen.add(Number(r.tmdb_id));
      rows.push({
        kind: r.kind === "tv" ? "tv" : "movie",
        tmdbId: Number(r.tmdb_id),
        title: String(r.title ?? ""),
        originalTitle: r.original_title ?? null,
        year: r.year ?? null,
        lang: r.lang ?? null,
        popularity: r.popularity ?? 0,
      });
    };
    for (const r of (exact.data ?? []) as CorpusRowRaw[]) push(r);

    if (year != null) {
      const near = await db
        .from("title_corpus")
        .select(cols)
        .eq("kind", kind)
        .gte("year", year - 1)
        .lte("year", year + 1)
        .order("popularity", { ascending: false })
        .limit(50);
      for (const r of (near.data ?? []) as CorpusRowRaw[]) push(r);
    }

    return rows;
  } catch (_) {
    // A corpus fault must never take the resolver down.
    return [];
  }
}

function rowYear(r: Record<string, unknown>): number | null {
  const d = String(r.release_date ?? r.first_air_date ?? "");
  return /^\d{4}/.test(d) ? Number(d.slice(0, 4)) : null;
}

function rowLang(r: Record<string, unknown>): string {
  return String(r.original_language ?? "");
}

function rowTitle(r: Record<string, unknown>): string {
  return String(r.title ?? r.name ?? "");
}

/**
 * IMDb title suggestions (the public suggestion endpoint, no key).
 *
 * Returns every candidate that could be the requested film; the YEAR
 * guard in pickImdbMatch decides which one is safe to answer with.
 */
async function imdbCandidates(title: string) {
  const url =
    `https://v3.sg.media-imdb.com/suggestion/x/${encodeURIComponent(title)}.json`;
  try {
    const res = await fetch(url, {
      headers: { Accept: "application/json", "User-Agent": "Mozilla/5.0" },
    });
    if (!res.ok) return [];
    const data = (await res.json()) as { d?: Record<string, unknown>[] };
    return (data.d ?? [])
      .filter((d) => typeof d.id === "string" && /^tt\d+$/.test(String(d.id)))
      .map((d) => ({
        imdbId: String(d.id),
        title: String(d.l ?? d.s ?? ""),
        year: typeof d.y === "number" ? d.y : null,
      }));
  } catch {
    return [];
  }
}

/**
 * OMDb enrichment: the exact release date and the IMDb rating for an
 * IMDb id. Only runs when OMDb_API_KEY is configured on the function -
 * without a key this returns null and the answer still works.
 */
async function omdbDetail(imdbId: string) {
  const key = Deno.env.get("OMDB_API_KEY");
  if (!key) return null;
  try {
    const url = new URL("https://www.omdbapi.com/");
    url.searchParams.set("apikey", key);
    url.searchParams.set("i", imdbId);
    const res = await fetch(url, { headers: { Accept: "application/json" } });
    if (!res.ok) return null;
    const data = (await res.json()) as Record<string, unknown>;
    if (data.Response !== "True") return null;
    const released = String(data.Released ?? "");
    const iso = /^\d{4}-\d{2}-\d{2}$/.test(released) ? released : "";
    const rating = Number(data.imdbRating);
    return {
      releaseDate: iso,
      rating: Number.isFinite(rating) && rating > 0 ? rating : null,
    };
  } catch {
    return null;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!Deno.env.get("TMDB_API_KEY") && !Deno.env.get("TMDB_BEARER")) {
      return json({ error: "server misconfigured" }, 500, 10);
    }
    const u = new URL(req.url);
    const title = (u.searchParams.get("title") ?? "").trim();
    const yearRaw = (u.searchParams.get("year") ?? "").trim();
    const type = u.searchParams.get("type") === "tv" ? "tv" : "movie";
    const imdbId = (u.searchParams.get("imdbId") ?? "").trim();
    const lang = (u.searchParams.get("lang") ?? "").trim().toLowerCase();
    const year = /^\d{4}$/.test(yearRaw) ? Number(yearRaw) : null;
    if (!title && !imdbId) return json({ error: "title or imdbId required" }, 400, 60);

    // 1) IMDb → TMDB via /find (exact by IMDb id - always safe).
    if (/^tt\d+$/.test(imdbId)) {
      const { data } = await tmdbFetch(`/find/${imdbId}`, {
        external_source: "imdb_id",
      });
      const arr = (data[type === "tv" ? "tv_results" : "movie_results"] ?? []) as Record<
        string,
        unknown
      >[];
      if (arr.length > 0) {
        return json({
          tmdbId: arr[0].id,
          imdbId,
          year: String(arr[0].release_date ?? arr[0].first_air_date ?? "").slice(0, 4),
          title: arr[0].title ?? arr[0].name ?? title,
          source: "imdb",
          matchQuality: "exact",
        });
      }
    }

    // 2) The corpus. An index built from TMDB /discover, so it sees the
    //    regional titles /search cannot, and it carries the language and
    //    the year - which is what keeps a generic name ("Game Over") from
    //    resolving to a Spanish film.
    if (title) {
      const candidates = await loadCorpusCandidates(type, title, year);
      if (candidates.length) {
        const scoped = lang
          ? candidates.filter((c) => !c.lang || c.lang === lang)
          : candidates;
        const match = pickCorpusMatch(title, scoped, { kind: type, year });
        if (match && match.safe) {
          return json({
            tmdbId: match.row.tmdbId,
            imdbId: imdbId || null,
            year: match.row.year != null ? String(match.row.year) : "",
            title: match.row.title,
            source: "corpus",
            matchQuality: match.quality,
          });
        }
      }
    }

    // 3) Title search — EXACT-title gate (2026-10-10): TMDB ranks by
    //    popularity, not exactness. Blind arr[0] returned the WRONG video
    //    (poster A, playback B) for ~40 app scrapers that trust this
    //    answer. Require a cleaned exact title hit (year-pinned when a year
    //    is given); else 404 so the client falls through to its next chain
    //    rung.
    const params: Record<string, string> = { query: title };
    if (year != null) {
      params[type === "tv" ? "first_air_date_year" : "year"] = String(year);
    }
    const { data } = await tmdbFetch(`/search/${type}`, params);
    const arr = (data.results ?? []) as Record<string, unknown>[];
    if (arr.length === 0) return json({ error: "not found" }, 404, 3600);
    const want = cleanTitle(title);
    const wantYear = year != null ? String(year) : "";

    const yearOk = (r: Record<string, unknown>) => {
      if (!wantYear) return true;
      const y = String(r.release_date ?? r.first_air_date ?? "").slice(0, 4);
      if (!y) return true; // TMDB has no date for it - do not punish it.
      return Math.abs(parseInt(y) - parseInt(wantYear)) <= 1;
    };
    const langOk = (r: Record<string, unknown>) => {
      if (!lang) return true;
      const l = rowLang(r);
      return !l || l === lang;
    };

    const hit = arr.find((r) => {
      const t = cleanTitle(rowTitle(r));
      if (!t || t !== want) return false;
      if (!yearOk(r)) return false;
      if (!langOk(r)) return false;
      return true;
    });
    if (hit) {
      return json({
        tmdbId: hit.id,
        imdbId: imdbId || null,
        year: String(hit.release_date ?? hit.first_air_date ?? "").slice(0, 4),
        title: hit.title ?? hit.name ?? title,
        source: "tmdb",
        matchQuality: "exact",
      });
    }

    // 3b) One-edit spelling difference ("Minall" / "Minal"), still pinned
    //     to the requested year and language.
    const near = arr.find((r) => {
      const t = cleanTitle(rowTitle(r));
      if (!t) return false;
      if (editDistance(want, t) > 1) return false;
      if (!yearOk(r)) return false;
      if (!langOk(r)) return false;
      return true;
    });
    if (near) {
      return json({
        tmdbId: near.id,
        imdbId: imdbId || null,
        year: String(near.release_date ?? near.first_air_date ?? "").slice(0, 4),
        title: near.title ?? near.name ?? title,
        source: "tmdb",
        matchQuality: "fuzzy",
      });
    }

    // 4) IMDb fallback for the titles TMDB has never heard of.
    //
    //    Measured against the owner's 50 latest Odia movies: TMDB knows
    //    24 of them, and for 25 of the remaining 26 IMDb DOES know the
    //    film - the year guard is what keeps the answer correct ("Game
    //    Over" 2018, "Midnight Mass" 2021 and "Diary of a Wimpy Kid" 2010
    //    are rejected; "Danger Devdas" 2026, "Mehermunda" 2026, "Aafaa"
    //    2026 are accepted). An IMDb id is enough for the app's scrapers:
    //    they search by IMDb id as well as by TMDB id.
    if (title) {
      const candidates = await imdbCandidates(title);
      const match = pickImdbMatch(title, candidates, { year });
      if (match) {
        const omdb = await omdbDetail(match.imdbId);
        return json({
          tmdbId: null,
          imdbId: match.imdbId,
          year: match.year != null ? String(match.year) : "",
          title: match.title,
          releaseDate: omdb?.releaseDate ?? "",
          rating: omdb?.rating ?? null,
          source: "imdb",
          matchQuality: "exact",
        });
      }
    }

    return json({ error: "not found" }, 404, 3600);
  } catch (e) {
    return json({ error: String(e) }, 500, 10);
  }
});
