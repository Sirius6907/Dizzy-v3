// release-latest — one cached source of release truth (Phase N).
// Auth: public GET (deploy with --no-verify-jwt). No cookies, no PII.
//
//   GET /functions/v1/release-latest
//     → { tag, name, published_at, assets:[{name,size,download_count,url}],
//         fetched_at }
//
// Serves the github_stats_cache row when it is <5 min old (12 GitHub calls
// per hour max — the unauthenticated limit is 60/hr per IP), otherwise fetches
// /releases/latest once, refreshes the cache, and serves that. If GitHub is
// down but a cached payload exists we serve the stale payload (marked by its
// old fetched_at) — the landing page must never go blank because of GitHub.
//
// Consumers: the landing page (version, sizes, direct GitHub links) and the
// admin dashboard (GitHub download counts). Cache-Control keeps dashboard
// 30s polling from turning into GitHub traffic.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const REPO = "Sirius6907/Dizzy-v3";
const GH_LATEST = `https://api.github.com/repos/${REPO}/releases/latest`;
const CACHE_TTL_MS = 5 * 60 * 1000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
};

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=120",
      ...extra,
    },
  });
}

function ghHeaders(): Record<string, string> {
  const h: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "Dizzy-release-latest-edge",
  };
  const tok = Deno.env.get("GITHUB_TOKEN");
  if (tok) h.Authorization = `Bearer ${tok}`;
  return h;
}

// deno-lint-ignore no-explicit-any
function toPayload(rel: any) {
  return {
    tag: String(rel?.tag_name ?? ""),
    name: String(rel?.name ?? ""),
    published_at: String(rel?.published_at ?? ""),
    // deno-lint-ignore no-explicit-any
    assets: (Array.isArray(rel?.assets) ? rel.assets : []).map((a: any) => ({
      name: String(a?.name ?? ""),
      size: Number(a?.size ?? 0),
      download_count: Number(a?.download_count ?? 0),
      url: String(a?.browser_download_url ?? ""),
    })),
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "GET" && req.method !== "HEAD") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const svc = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data, error } = await svc
      .from("github_stats_cache")
      .select("payload, fetched_at")
      .eq("id", true)
      .maybeSingle();

    const cached = error ? null : data;
    const payload = cached?.payload ?? null;
    const fetchedAt = cached?.fetched_at ?? null;
    const age = fetchedAt ? Date.now() - Date.parse(fetchedAt) : Infinity;
    const hasTag = Boolean(payload && payload.tag);

    if (hasTag && age < CACHE_TTL_MS) {
      return json({ ...payload, fetched_at: fetchedAt });
    }

    try {
      const res = await fetch(GH_LATEST, { headers: ghHeaders() });
      if (!res.ok) throw new Error(`github_${res.status}`);
      const fresh = toPayload(await res.json());
      if (fresh.tag === "") throw new Error("github_empty_tag");

      const now = new Date().toISOString();
      await svc
        .from("github_stats_cache")
        .upsert({ id: true, payload: fresh, fetched_at: now });

      return json({ ...fresh, fetched_at: now });
    } catch {
      // GitHub unreachable: serve stale cache rather than break the page.
      if (hasTag) return json({ ...payload, fetched_at: fetchedAt });
      return json({ error: "release_unavailable" }, 502);
    }
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
