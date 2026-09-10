// tmdb-proxy — keyless TMDB for the app (v1.2.0-C1).
// Env (supabase secrets): TMDB_API_KEY or TMDB_BEARER.
// GET ?path=/search/movie&query=...&page=1  (allowlisted TMDB paths only)
// Caches 1h via Cache-Control; rate-limits per IP (60/min, in-memory best-effort).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const ALLOW = [
  /^\/search\/(movie|tv|multi)$/,
  /^\/movie\/\d+$/,
  /^\/movie\/\d+\/(credits|videos|similar|recommendations)$/,
  /^\/tv\/\d+$/,
  /^\/tv\/\d+\/(credits|videos|similar|recommendations|season\/\d+)$/,
  /^\/find\/[^/]+$/,
  /^\/genre\/(movie|tv)\/list$/,
  /^\/trending\/(movie|tv|all)\/(day|week)$/,
  /^\/movie\/(popular|top_rated|now_playing|upcoming)$/,
  /^\/tv\/(popular|top_rated|on_the_air|airing_today)$/,
  /^\/configuration$/,
];

const hits = new Map<string, number[]>();
function rateOk(ip: string): boolean {
  const now = Date.now();
  const arr = (hits.get(ip) ?? []).filter((t) => now - t < 60_000);
  arr.push(now);
  hits.set(ip, arr);
  return arr.length <= 60;
}

function json(body: unknown, status = 200, cacheSec = 3600) {
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
    const ip =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
    if (!rateOk(ip)) return json({ error: "rate limited" }, 429, 10);

    const u = new URL(req.url);
    const path = u.searchParams.get("path") ?? "";
    if (!ALLOW.some((re) => re.test(path))) {
      return json({ error: "path not allowed" }, 403, 60);
    }

    const apiKey = Deno.env.get("TMDB_API_KEY") ?? "";
    const bearer = Deno.env.get("TMDB_BEARER") ?? "";
    if (!apiKey && !bearer) return json({ error: "server misconfigured" }, 500, 10);

    const target = new URL("https://api.themoviedb.org/3" + path);
    u.searchParams.forEach((v, k) => {
      if (k !== "path") target.searchParams.set(k, v);
    });
    const headers: Record<string, string> = { Accept: "application/json" };
    if (bearer) headers["Authorization"] = `Bearer ${bearer}`;
    else target.searchParams.set("api_key", apiKey);

    const res = await fetch(target.toString(), { headers });
    const data = await res.json();
    return json(data, res.status);
  } catch (e) {
    return json({ error: String(e) }, 500, 10);
  }
});
