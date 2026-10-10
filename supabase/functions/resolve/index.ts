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
    // 2) Title search — EXACT-title gate (2026-10-10): TMDB ranks by
    // popularity, not exactness. Blind arr[0] returned the WRONG video
    // (poster A, playback B) for ~40 app scrapers that trust this answer.
    // Require a cleaned exact title hit (year-pinned when a year is given);
    // else 404 so the client falls through to its next chain rung.
    const { data } = await tmdbFetch(`/search/${type}`, params);
    const arr = (data.results ?? []) as Record<string, unknown>[];
    if (arr.length === 0) return json({ error: "not found" }, 404, 3600);
    const clean = (s: unknown) =>
      String(s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
    const want = clean(title);
    const wantYear = /^\d{4}$/.test(year) ? year : "";
    const hit = (arr as Record<string, unknown>[]).find((r) => {
      const t = clean(r["title"] ?? r["name"] ?? "");
      if (!t || t !== want) return false;
      if (wantYear) {
        const y = String(
          r["release_date"] ?? r["first_air_date"] ?? "",
        ).slice(0, 4);
        if (y && Math.abs(parseInt(y) - parseInt(wantYear)) > 1) return false;
      }
      return true;
    });
    if (!hit) return json({ error: "not found" }, 404, 3600);
    return json({
      tmdbId: hit.id,
      imdbId: imdbId || null,
      year: String(hit.release_date ?? hit.first_air_date ?? "").slice(0, 4),
      title: hit.title ?? hit.name ?? title,
    });
  } catch (e) {
    return json({ error: String(e) }, 500, 10);
  }
});
