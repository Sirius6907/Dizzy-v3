// resolve — title→TMDB/IMDb ID resolution for scrapers (v1.2.0-C3).
// Env: TMDB_API_KEY or TMDB_BEARER (same as tmdb-proxy).
// GET ?title=...&year=2024&type=movie|tv&imdbId=tt1234567
// Returns {tmdbId, imdbId, year, title}. Server-side so keys stay secret.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

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

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!Deno.env.get("TMDB_API_KEY") && !Deno.env.get("TMDB_BEARER")) {
      return json({ error: "server misconfigured" }, 500, 10);
    }
    const u = new URL(req.url);
    const title = (u.searchParams.get("title") ?? "").trim();
    const year = (u.searchParams.get("year") ?? "").trim();
    const type = u.searchParams.get("type") === "tv" ? "tv" : "movie";
    const imdbId = (u.searchParams.get("imdbId") ?? "").trim();
    if (!title && !imdbId) return json({ error: "title or imdbId required" }, 400, 60);

    // 1) IMDb → TMDB via /find
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
        });
      }
    }

    // 2) Title search
    const params: Record<string, string> = { query: title };
    if (/^\d{4}$/.test(year)) {
      params[type === "tv" ? "first_air_date_year" : "year"] = year;
    }
    const { data } = await tmdbFetch(`/search/${type}`, params);
    const arr = (data.results ?? []) as Record<string, unknown>[];
    if (arr.length === 0) return json({ error: "not found" }, 404, 3600);
    const best = arr[0];
    return json({
      tmdbId: best.id,
      imdbId: imdbId || null,
      year: String(best.release_date ?? best.first_air_date ?? "").slice(0, 4),
      title: best.title ?? best.name ?? title,
    });
  } catch (e) {
    return json({ error: String(e) }, 500, 10);
  }
});
