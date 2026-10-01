// dl — counted download redirect (Phase N).
// Auth: public GET (deploy with --no-verify-jwt). No cookies, no PII.
//
//   GET /functions/v1/dl?src=landing&os=android&file=Dizzy-v3-arm64-v8a.apk
//     1. HARD validation (400): file must match the release-asset pattern,
//        must NOT be one of the legacy debug-key mirrors, src/os allowlists.
//     2. Resolve the latest tag from github_stats_cache (5-min TTL, one GH
//        call at most per TTL — the unauthenticated GitHub limit is 60/hr).
//     3. Count the click (+1, atomic RPC) — landing source only.
//     4. 302 to the fixed GitHub release asset URL.
//
// No open redirect is possible: the file name is pattern-locked and the
// repo prefix is a constant. Tracking must NEVER break a download — if the
// counter write fails we still redirect, and if GitHub is unreachable but a
// cached tag exists we redirect with the stale tag.
//
// Counting note: GitHub's own download_count includes these hits (same
// asset URL), so the landing number is a SUBSET of the GitHub total.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const REPO = "Sirius6907/Dizzy-v3";
const FILE_RE = /^Dizzy-[A-Za-z0-9._-]+\.(apk|zip|exe|AppImage|tar\.gz)$/;
const SOURCES = ["landing", "qr", "social"] as const;
const PLATFORMS = ["android", "windows", "linux"] as const;
const CACHE_TTL_MS = 5 * 60 * 1000;
const GH_LATEST = `https://api.github.com/repos/${REPO}/releases/latest`;

const cors = { "Access-Control-Allow-Origin": "*" };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function ghHeaders(): Record<string, string> {
  const h: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "Dizzy-dl-edge",
  };
  const tok = Deno.env.get("GITHUB_TOKEN");
  if (tok) h.Authorization = `Bearer ${tok}`;
  return h;
}

/** What the cache row holds — same shape release-latest serves. */
type CacheRow = {
  payload: {
    tag?: string;
    name?: string;
    published_at?: string;
    assets?: { name: string; size: number; download_count: number; url: string }[];
  } | null;
  fetched_at: string;
} | null;

/** Map a GitHub release to the payload both edge functions share. */
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

/**
 * Fresh tag from the 5-min cache; otherwise fetch GitHub once and refresh
 * the cache. GitHub failure falls back to the stale cached tag (download
 * still works), and only a completely empty cache fails the request.
 */
async function resolveTag(
  // deno-lint-ignore no-explicit-any
  svc: any,
): Promise<string | null> {
  const { data, error } = await svc
    .from("github_stats_cache")
    .select("payload, fetched_at")
    .eq("id", true)
    .maybeSingle();
  const row: CacheRow = error ? null : data;
  const age = row ? Date.now() - Date.parse(row.fetched_at) : Infinity;
  const tag = row?.payload?.tag ?? "";

  if (tag !== "" && age < CACHE_TTL_MS) return tag;

  try {
    const res = await fetch(GH_LATEST, { headers: ghHeaders() });
    if (res.ok) {
      const payload = toPayload(await res.json());
      if (payload.tag !== "") {
        await svc
          .from("github_stats_cache")
          .upsert({ id: true, payload, fetched_at: new Date().toISOString() });
        return payload.tag;
      }
    }
  } catch {
    /* fall through to the stale tag */
  }

  return tag !== "" ? tag : null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  // HEAD is accepted so `curl -I` can verify the redirect chain.
  if (req.method !== "GET" && req.method !== "HEAD") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const url = new URL(req.url);
  const src = url.searchParams.get("src") ?? "";
  const os = url.searchParams.get("os") ?? "";
  const file = url.searchParams.get("file") ?? "";

  const okSrc = (SOURCES as readonly string[]).includes(src);
  const okOs = (PLATFORMS as readonly string[]).includes(os);
  const okFile =
    FILE_RE.test(file) && !file.toLowerCase().includes("legacy");

  if (!okSrc || !okOs || !okFile) return json({ error: "bad_request" }, 400);

  try {
    const svc = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const tag = await resolveTag(svc);
    if (!tag) return json({ error: "release_unavailable" }, 503);

    // Counting: only the landing source is a tracked download in the
    // dashboard; qr/social are accepted for future use but uncounted for
    // now (the counters table's allowlist is landing-only).
    if (src === "landing") {
      try {
        await svc.rpc("bump_download_counter", {
          p_source: src,
          p_file: file,
        });
      } catch {
        // Never let a counter hiccup eat a download.
      }
    }

    return new Response(null, {
      status: 302,
      headers: {
        ...cors,
        Location: `https://github.com/${REPO}/releases/download/${tag}/${file}`,
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
