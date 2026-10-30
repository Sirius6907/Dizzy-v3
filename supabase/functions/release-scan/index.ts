// release-scan — keeps fresh Bollywood + Hollywood titles warm
// (v1.3.3 Phase 4). Deploy: supabase functions deploy release-scan --no-verify-jwt
// Env: TMDB_API_KEY or TMDB_BEARER, SUPABASE_URL, SUPABASE_ANON_KEY,
//      SUPABASE_SERVICE_ROLE_KEY, PUSH_CRON_TOKEN.
//
// POST (cron token OR admin user token)
//   → { ok, scanned, upserted, by_lang, sources }
//
// Sources: India theatrical now-playing, plus hi/en movie and tv discover
// windows (last 45 / 30 days). Every row carries poster, rating, genres and
// language so the brain can match it to a taste profile without extra calls.
// Idempotent: rows upsert on (media_type, tmdb_id) and only refresh
// last_seen / metrics, so first_seen and notified_at survive re-scans.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const IMG = "https://image.tmdb.org/t/p/w500";
const DAY = 86_400_000;
const MOVIE_WINDOW_DAYS = 45;
const TV_WINDOW_DAYS = 30;
const MIN_POPULARITY = 4;
const MAX_PER_SOURCE = 40;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function ymd(d: Date) {
  return d.toISOString().slice(0, 10);
}

type GenreMap = { movie: Map<number, string>; tv: Map<number, string> };

type TmdbRow = Record<string, unknown>;

function toRow(
  r: TmdbRow,
  kind: "movie" | "tv",
  source: string,
  genres: GenreMap,
) {
  if (r.adult === true || r.adult === "true") return null;
  const title = String(r.title ?? r.name ?? "").replace(/\s+/g, " ").trim();
  if (!title) return null;
  const date = String(
    r.release_date ?? r.first_air_date ?? "",
  ).trim();
  const popularity = Number(r.popularity ?? 0);
  const votes = Number(r.vote_count ?? 0);
  const isTheatrical = source === "now_playing";
  if (!isTheatrical && popularity < MIN_POPULARITY) return null;
  if (!isTheatrical && kind === "movie" && votes < 5) return null;
  const ids = Array.isArray(r.genre_ids) ? r.genre_ids : [];
  const names = ids
    .map((id) => genres[kind].get(Number(id)))
    .filter((v): v is string => Boolean(v));
  return {
    media_type: kind,
    tmdb_id: Number(r.id),
    title: title.slice(0, 300),
    lang: String(r.original_language ?? "").slice(0, 8),
    year: date ? Number(date.slice(0, 4)) || null : null,
    release_date: date || null,
    popularity: Math.round(popularity * 100) / 100,
    rating: Math.round(Number(r.vote_average ?? 0) * 10) / 10,
    votes,
    genres: names,
    poster: r.poster_path ? IMG + r.poster_path : null,
    backdrop: r.backdrop_path
      ? (IMG + r.backdrop_path).replace("w500", "w780")
      : null,
    source,
    last_seen: new Date().toISOString(),
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const apiKey = Deno.env.get("TMDB_API_KEY") ?? "";
    const bearer = Deno.env.get("TMDB_BEARER") ?? "";
    const cronToken = Deno.env.get("PUSH_CRON_TOKEN") ?? "";
    if (!url || !anon || !svc || (!apiKey && !bearer)) {
      return json({ error: "server_misconfigured" }, 500);
    }

    const auth = req.headers.get("Authorization") ?? "";
    const isCron = cronToken.length > 0 && auth === `Bearer ${cronToken}`;
    const isService = auth === `Bearer ${svc}`;
    if (!isCron && !isService) {
      const userClient = createClient(url, anon, {
        global: { headers: { Authorization: auth } },
      });
      const { data } = await userClient.auth.getUser();
      if (!data?.user) return json({ error: "unauthorized" }, 401);
      const { data: adminFlag } = await userClient.rpc("is_admin");
      if (adminFlag !== true) return json({ error: "admin_only" }, 403);
    }

    const tmdb = async (path: string, params: Record<string, string> = {}) => {
      const qs = new URLSearchParams({ language: "en-US", ...params });
      if (apiKey) qs.set("api_key", apiKey);
      const res = await fetch(`https://api.themoviedb.org/3${path}?${qs}`, {
        headers: bearer ? { Authorization: `Bearer ${bearer}` } : {},
        signal: AbortSignal.timeout(12_000),
      });
      if (!res.ok) throw new Error(`${path} ${res.status}`);
      return await res.json();
    };

    const today = new Date();
    const movieFrom = ymd(new Date(today.getTime() - MOVIE_WINDOW_DAYS * DAY));
    const tvFrom = ymd(new Date(today.getTime() - TV_WINDOW_DAYS * DAY));
    const todayStr = ymd(today);

    const [movieGenres, tvGenres] = await Promise.all([
      tmdb("/genre/movie/list").then((d) => d.genres ?? []),
      tmdb("/genre/tv/list").then((d) => d.genres ?? []),
    ]);
    const genres: GenreMap = {
      movie: new Map(movieGenres.map((g: TmdbRow) => [g.id, g.name])),
      tv: new Map(tvGenres.map((g: TmdbRow) => [g.id, g.name])),
    };

    const sources: {
      name: string;
      kind: "movie" | "tv";
      path: string;
      params: Record<string, string>;
    }[] = [
      {
        name: "now_playing",
        kind: "movie",
        path: "/movie/now_playing",
        params: { region: "IN", page: "1" },
      },
      {
        name: "hi_movies",
        kind: "movie",
        path: "/discover/movie",
        params: {
          with_original_language: "hi",
          sort_by: "popularity.desc",
          "primary_release_date.gte": movieFrom,
          "primary_release_date.lte": todayStr,
          region: "IN",
          page: "1",
        },
      },
      {
        name: "hi_movies",
        kind: "movie",
        path: "/discover/movie",
        params: {
          with_original_language: "hi",
          sort_by: "popularity.desc",
          "primary_release_date.gte": movieFrom,
          "primary_release_date.lte": todayStr,
          region: "IN",
          page: "2",
        },
      },
      {
        name: "en_movies",
        kind: "movie",
        path: "/discover/movie",
        params: {
          with_original_language: "en",
          sort_by: "popularity.desc",
          "primary_release_date.gte": movieFrom,
          "primary_release_date.lte": todayStr,
          region: "IN",
          page: "1",
        },
      },
      {
        name: "en_movies",
        kind: "movie",
        path: "/discover/movie",
        params: {
          with_original_language: "en",
          sort_by: "popularity.desc",
          "primary_release_date.gte": movieFrom,
          "primary_release_date.lte": todayStr,
          region: "IN",
          page: "2",
        },
      },
      {
        name: "hi_series",
        kind: "tv",
        path: "/discover/tv",
        params: {
          with_original_language: "hi",
          sort_by: "popularity.desc",
          "first_air_date.gte": tvFrom,
          "first_air_date.lte": todayStr,
          page: "1",
        },
      },
      {
        name: "en_series",
        kind: "tv",
        path: "/discover/tv",
        params: {
          with_original_language: "en",
          sort_by: "popularity.desc",
          "first_air_date.gte": tvFrom,
          "first_air_date.lte": todayStr,
          page: "1",
        },
      },
    ];

    const results = await Promise.allSettled(
      sources.map((s) => tmdb(s.path, s.params)),
    );

    const byKey = new Map<string, Record<string, unknown>>();
    const sourceErrors: string[] = [];
    let scanned = 0;

    results.forEach((res, i) => {
      const src = sources[i];
      if (res.status === "rejected") {
        sourceErrors.push(`${src.name}:${String(res.reason).slice(0, 80)}`);
        return;
      }
      const list = Array.isArray(res.value?.results) ? res.value.results : [];
      scanned += list.length;
      let taken = 0;
      for (const raw of list) {
        if (taken >= MAX_PER_SOURCE) break;
        const row = toRow(raw as TmdbRow, src.kind, src.name, genres);
        if (!row) continue;
        byKey.set(`${row.media_type}:${row.tmdb_id}`, row);
        taken++;
      }
    });

    const rows = [...byKey.values()];
    if (rows.length === 0) {
      return json({ ok: true, scanned, upserted: 0, by_lang: {}, sourceErrors });
    }

    const db = createClient(url, svc);
    const { error } = await db
      .from("release_candidates")
      .upsert(rows, { onConflict: "media_type,tmdb_id" });
    if (error) return json({ error: `db:${error.message}` }, 500);

    const byLang: Record<string, number> = {};
    for (const r of rows) {
      const lang = String(r.lang || "unknown");
      byLang[lang] = (byLang[lang] ?? 0) + 1;
    }

    return json({
      ok: true,
      scanned,
      upserted: rows.length,
      by_lang: byLang,
      sourceErrors,
    });
  } catch (e) {
    return json({ error: String(e).slice(0, 300) }, 500);
  }
});
