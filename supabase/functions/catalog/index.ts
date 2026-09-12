// catalog — ready-made browse feeds for the app (v1.2.0-C2, warm-cache P22).
// Env: TMDB_API_KEY or TMDB_BEARER (same as tmdb-proxy).
//   + SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (warm-row read-through).
// GET ?feed=trending|popular|top_rated&type=movie|tv|all&page=1
// Returns slim cards: {id, title, poster, backdrop, year, rating, media_type}
// + warm:true when served from catalog_cache (fresh <6h, refreshed by the
// noon-IST scheduled run — see Dashboard → Edge Functions → catalog →
// Schedules, cron `30 6 * * *` UTC).
//
// A cold edge (no secrets/table yet) behaves exactly like C2 (warm:false).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const IMG = "https://image.tmdb.org/t/p/w500";

function json(body: unknown, status = 200, cacheSec = 1800) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": `public, max-age=${cacheSec}`,
    },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const u = new URL(req.url);
    const feed = u.searchParams.get("feed") ?? "trending";
    const type = u.searchParams.get("type") ?? "all";
    const page = u.searchParams.get("page") ?? "1";

    let path = "";
    if (feed === "trending") {
      const t = type === "movie" || type === "tv" ? type : "all";
      path = `/trending/${t}/week`;
    } else if (feed === "popular") {
      path = type === "tv" ? "/tv/popular" : "/movie/popular";
    } else if (feed === "top_rated") {
      path = type === "tv" ? "/tv/top_rated" : "/movie/top_rated";
    } else {
      return json({ error: "bad feed" }, 400, 60);
    }

    const apiKey = Deno.env.get("TMDB_API_KEY") ?? "";
    const bearer = Deno.env.get("TMDB_BEARER") ?? "";
    if (!apiKey && !bearer) return json({ error: "server misconfigured" }, 500, 10);

    // P22: read-through warm cache (6h fresh). Any cache fault → cold path.
    const cacheKey = `${feed}|${type}|${page}`;
    try {
      const url = Deno.env.get("SUPABASE_URL") ?? "";
      const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
      if (url && svc) {
        const db = createClient(url, svc);
        const { data: row } = await db
          .from("catalog_cache")
          .select("items,updated_at")
          .eq("cache_key", cacheKey)
          .maybeSingle();
        const at = row ? Date.parse(row.updated_at as string) : NaN;
        if (row && !Number.isNaN(at) && Date.now() - at < 6 * 3600 * 1000) {
          return json({ page: Number(page), total_pages: 1, items: row.items, warm: true });
        }
      }
    } catch (_) {
      /* cold path below */
    }

    const target = new URL("https://api.themoviedb.org/3" + path);
    target.searchParams.set("page", page);
    const headers: Record<string, string> = { Accept: "application/json" };
    if (bearer) headers["Authorization"] = `Bearer ${bearer}`;
    else target.searchParams.set("api_key", apiKey);

    const res = await fetch(target.toString(), { headers });
    const data = await res.json();
    const items = ((data.results ?? []) as unknown[]).map((r) => {
      const m = r as Record<string, unknown>;
      const mt = (m.media_type as string) ?? (path.startsWith("/tv") ? "tv" : "movie");
      return {
        id: m.id,
        title: m.title ?? m.name ?? "",
        poster: m.poster_path ? IMG + m.poster_path : null,
        backdrop: m.backdrop_path
          ? (IMG + m.backdrop_path).replace("w500", "w780")
          : null,
        year: String(m.release_date ?? m.first_air_date ?? "").slice(0, 4),
        rating: m.vote_average ?? 0,
        media_type: mt,
      };
    });
    // P22: write the fresh feed back (best-effort — feeds work without it).
    try {
      const url = Deno.env.get("SUPABASE_URL") ?? "";
      const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
      if (url && svc) {
        const db = createClient(url, svc);
        await db.from("catalog_cache").upsert(
          {
            cache_key: cacheKey,
            feed,
            type,
            page: Number(page),
            items,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "cache_key" },
        );
      }
    } catch (_) {
      /* feed still served cold below */
    }
    return json({ page: data.page ?? 1, total_pages: data.total_pages ?? 1, items, warm: false });
  } catch (e) {
    return json({ error: String(e) }, 500, 10);
  }
});
