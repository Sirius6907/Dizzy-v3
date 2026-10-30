// recommend — personal rail from the taste pipeline (v1.3.3 Phase 2).
// Env: TMDB_API_KEY or TMDB_BEARER, SUPABASE_URL, SUPABASE_ANON_KEY,
//      SUPABASE_SERVICE_ROLE_KEY.
// GET (Authorization: Bearer <user access token>)
//   → { personal: bool, items: [{...catalog card, reason_code}] }
//
// Read path: taste_profiles (rolled up by refresh_taste_profile) → TMDB
// discover by top genres/languages → rank → dedupe → 20 cards.
// Fails to an empty list, never an error: the home rail simply hides.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const IMG = "https://image.tmdb.org/t/p/w500";
const DAY_MS = 86_400_000;

function json(body: unknown, status = 200, cacheSec = 0) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": cacheSec > 0 ? `private, max-age=${cacheSec}` : "no-store",
    },
  });
}

function slim(r: Record<string, unknown>, kind: "movie" | "tv") {
  return {
    id: r.id,
    title: r.title ?? r.name ?? "",
    poster: r.poster_path ? IMG + r.poster_path : null,
    backdrop: r.backdrop_path
      ? (IMG + r.backdrop_path).replace("w500", "w780")
      : null,
    year: String(r.release_date ?? r.first_air_date ?? "").slice(0, 4),
    rating: r.vote_average ?? 0,
    media_type: r.media_type ?? kind,
    lang: r.original_language ?? "",
    votes: Number(r.vote_count ?? 0),
  };
}

function popScore(c: Record<string, unknown>) {
  return Number(c.rating ?? 0) * Math.log10(1 + Number(c.votes ?? 0));
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const apiKey = Deno.env.get("TMDB_API_KEY") ?? "";
    const bearer = Deno.env.get("TMDB_BEARER") ?? "";
    if (!url || !anon || !svc || (!apiKey && !bearer)) {
      return json({ error: "server misconfigured" }, 500);
    }

    const auth = req.headers.get("Authorization") ?? "";
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: auth } },
    });
    const { data: authData } = await userClient.auth.getUser();
    const user = authData?.user;
    if (!user) return json({ personal: false, items: [], reason: "auth" });

    const db = createClient(url, svc);
    type Profile = {
      top_genres?: { name: string; score: number }[];
      top_langs?: { lang: string; score: number }[];
      top_titles?: { type: string; id: string; title: string; lang: string }[];
      event_count?: number;
      updated_at?: string;
    };
    let profile: Profile | null = null;
    const read = async () => {
      const { data } = await db
        .from("taste_profiles")
        .select("top_genres,top_langs,top_titles,event_count,updated_at")
        .eq("user_id", user.id)
        .maybeSingle();
      return (data as Profile | null) ?? null;
    };
    profile = await read();
    const stale = !profile ||
      Date.now() - Date.parse(profile.updated_at ?? "") > 6 * 3_600_000;
    if (stale) {
      await db.rpc("refresh_taste_profile", { p_uid: user.id });
      profile = await read();
    }

    const events = Number(profile?.event_count ?? 0);
    if (events < 3) return json({ personal: false, items: [], reason: "cold" });

    const tmdbHeaders: Record<string, string> = { Accept: "application/json" };
    if (bearer) tmdbHeaders["Authorization"] = `Bearer ${bearer}`;
    const tmdb = async (path: string, params: Record<string, string> = {}) => {
      const target = new URL("https://api.themoviedb.org/3" + path);
      if (!bearer) target.searchParams.set("api_key", apiKey);
      for (const [k, v] of Object.entries(params)) target.searchParams.set(k, v);
      const res = await fetch(target.toString(), { headers: tmdbHeaders });
      return await res.json();
    };

    // Genre names from the roll-up → TMDB ids (one call per media type).
    const [movieGenres, tvGenres] = await Promise.all([
      tmdb("/genre/movie/list"),
      tmdb("/genre/tv/list"),
    ]);
    const gid = new Map<string, number>();
    for (const g of [...(movieGenres.genres ?? []), ...(tvGenres.genres ?? [])]) {
      const name = String(g.name ?? "").toLowerCase();
      if (name && !gid.has(name)) gid.set(name, Number(g.id));
    }

    const wantedGenres = (profile?.top_genres ?? [])
      .map((g) => ({ name: String(g.name), id: gid.get(String(g.name).toLowerCase()) }))
      .filter((g) => !!g.id)
      .slice(0, 2);
    const wantedLangs = (profile?.top_langs ?? [])
      .map((l) => String(l.lang))
      .filter((l) => /^[a-z]{2}$/.test(l))
      .slice(0, 2);

    const thisYear = new Date().getUTCFullYear();
    const modernFrom = `${thisYear - 3}-01-01`;
    const calls: Promise<unknown>[] = [];
    for (const g of wantedGenres) {
      for (const kind of ["movie", "tv"] as const) {
        const p: Record<string, string> = {
          sort_by: "popularity.desc",
          with_genres: String(g.id),
          "vote_count.gte": "40",
          "vote_average.gte": "6",
          include_adult: "false",
        };
        if (kind === "movie") p["primary_release_date.gte"] = modernFrom;
        else p["first_air_date.gte"] = modernFrom;
        calls.push(tmdb(`/discover/${kind}`, p).then((d) => ({ kind, g: g.name, d })));
      }
    }
    for (const lang of wantedLangs) {
      calls.push(
        tmdb("/discover/movie", {
          sort_by: "popularity.desc",
          with_original_language: lang,
          "vote_count.gte": "40",
          "vote_average.gte": "6",
          "primary_release_date.gte": modernFrom,
          include_adult: "false",
        }).then((d) => ({ kind: "movie", g: null, d, lang })),
      );
    }

    const results = await Promise.all(calls);
    const watched = new Set(
      (profile?.top_titles ?? []).map((t) => `${t.type}:${t.id}`),
    );
    const seenId = new Set<string>();
    const seenTitle = new Set<string>();
    const items: Record<string, unknown>[] = [];

    for (const r of results as {
      kind: "movie" | "tv";
      g: string | null;
      lang?: string;
      d: { results?: Record<string, unknown>[] };
    }[]) {
      for (const raw of r.d.results ?? []) {
        const c = slim(raw, r.kind);
        const idKey = `${c.media_type}:${c.id}`;
        const titleKey = `${String(c.title).toLowerCase()}|${c.year}`;
        if (watched.has(idKey) || seenId.has(idKey) || seenTitle.has(titleKey)) {
          continue;
        }
        seenId.add(idKey);
        seenTitle.add(titleKey);
        const langMatch = wantedLangs.includes(String(c.lang));
        const year = Number(c.year) || 0;
        const recency = year >= thisYear ? 1.3 : year >= thisYear - 1 ? 1.15 : 1;
        const score =
          popScore(c) * (r.g ? 1.45 : 1) * (langMatch ? 1.25 : 1) * recency;
        items.push({
          ...c,
          reason_code: r.g ? `genre:${r.g}` : `lang:${c.lang}`,
          score: Math.round(score * 100) / 100,
        });
      }
    }

    items.sort((a, b) => Number(b.score) - Number(a.score));
    return json({ personal: true, items: items.slice(0, 20) }, 200, 900);
  } catch (e) {
    return json({ personal: false, items: [], error: `${e}`.slice(0, 200) });
  }
});
