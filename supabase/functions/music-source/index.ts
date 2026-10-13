// music-source — Edge proxy for third-party music providers (v1.3.3-T3.0).
//
// Why a proxy: provider endpoints, query shapes and any future API keys are
// NEVER bundled into the APK (standing secure-edge-proxy rule). The app
// calls this function; only the function knows the upstreams.
//
// Providers (v1.3.3):
//   jiosaavn  — desi backbone (Hindi/Punjabi/Bollywood/Odia depth).
//               Public web API, verified live: search + trending.
//   ytmusic   — reserved: charts/playlist browse (same shape, added when a
//               stable endpoint is pinned; returns empty today, never errors).
//   spotify   — reserved: editorial metadata only. Audio never comes from
//               Spotify; the app resolves playback on Deezer/Saavn/YT.
//
// Fan-out discipline: one upstream call per request, hard 10s timeout, and
// EVERY failure returns an empty result set — a dead provider must never
// break the music page (the app simply shows one less source).
//
// Body: { provider, op, query?, id?, limit? }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36";

const UPSTREAM_TIMEOUT_MS = 10000;
const MAX_LIMIT = 50;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function clampLimit(raw: unknown, fallback = 20): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(Math.floor(n), MAX_LIMIT);
}

/** Trim + cap free text before it goes upstream. */
function cleanQuery(raw: unknown): string {
  return String(raw ?? "").replace(/\s+/g, " ").trim().slice(0, 120);
}

/** HTML entities appear in Saavn titles (`&quot;`, `&amp;`). */
function unescapeHtml(s: string): string {
  return s
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, "&")
    .replace(/&#0?39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

const SAAVN_BASE = "https://www.jiosaavn.com/api.php";
const SAAVN_COMMON =
  "_format=json&_marker=0&api_version=4&ctx=web6dot0";

type Track = {
  id: string;
  title: string;
  artist: string;
  album: string;
  coverUrl: string;
  durationSeconds: number;
  language: string;
  year: string;
  source: string;
  previewUrl: string;
};

/**
 * Normalise one Saavn song row. The API is inconsistent across endpoints
 * (search returns `more_info.*`, some rows expose flat fields), so every
 * field is read defensively — one malformed row must not kill the batch.
 */
function saavnTrack(raw: Record<string, unknown>): Track | null {
  const info = (raw?.more_info ?? {}) as Record<string, unknown>;
  const id = String(raw?.id ?? "").trim();
  const title = unescapeHtml(String(raw?.title ?? "").trim());
  if (id === "" || title === "") return null;

  const subtitle = unescapeHtml(String(raw?.subtitle ?? "").trim());
  const artistMap = (info?.artistMap ?? {}) as Record<string, unknown>;
  const primaryArtists = Array.isArray(artistMap?.primary_artists)
    ? (artistMap.primary_artists as Array<Record<string, unknown>>)
        .map((a) => String(a?.name ?? "").trim())
        .filter(Boolean)
        .join(", ")
    : "";

  const musicField = typeof info?.music === "string" ? info.music.trim() : "";
  const artist =
    musicField ||
    primaryArtists ||
    subtitle.split(" - ")[0].split(",")[0].trim() ||
    "Unknown Artist";

  // Saavn serves 150x150 in the row; request a bigger render of the same asset.
  const cover = String(raw?.image ?? "").trim().replace("150x150", "500x500");

  const dur = Number(info?.duration ?? raw?.duration ?? 0);
  const mediaUrl = String(info?.media_url ?? raw?.media_url ?? "").trim();
  const preview = String(info?.preview_url ?? raw?.preview_url ?? "").trim();

  return {
    id,
    title,
    artist,
    album: unescapeHtml(String(info?.album ?? raw?.album ?? "").trim()) || "Single",
    coverUrl: cover,
    durationSeconds: Number.isFinite(dur) && dur > 0 ? Math.floor(dur) : 0,
    language: String(raw?.language ?? "").trim(),
    year: String(raw?.year ?? "").trim(),
    source: "jiosaavn",
    // Playback: prefer the full media url, else the 30s preview. The app
    // re-resolves on its own chain; this is only a hint.
    previewUrl: mediaUrl || preview,
  };
}

async function saavnSearch(query: string, limit: number): Promise<Track[]> {
  const url = `${SAAVN_BASE}?__call=search.getResults&q=${
    encodeURIComponent(query)
  }&n=${limit}&p=1&${SAAVN_COMMON}`;
  const r = await fetch(url, {
    headers: { "User-Agent": UA, Accept: "application/json" },
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });
  if (!r.ok) return [];
  const d = await r.json().catch(() => null);
  const rows = (d?.results ?? []) as Record<string, unknown>[];
  const out: Track[] = [];
  for (const row of rows) {
    if (String(row?.type ?? "song") !== "song") continue;
    const t = saavnTrack(row);
    if (t) out.push(t);
  }
  return out;
}

async function saavnTrending(limit: number): Promise<Track[]> {
  // Saavn's search.getResults with 'trending' reliably yields song rows
  const tracks = await saavnSearch("trending hits", limit);
  if (tracks.length > 0) return tracks;
  return saavnSearch("hindi top", limit);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const apiKeyHeader = req.headers.get("apikey") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    // Allow if caller carries the project's anonKey OR a valid user JWT.
    const isProjectKey = apiKeyHeader === anonKey || authHeader === `Bearer ${anonKey}`;
    if (!isProjectKey) {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        anonKey,
        { global: { headers: { Authorization: authHeader } } },
      );
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return json({ error: "unauthorized" }, 401);
    }

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const provider = String(body?.provider ?? "").trim().toLowerCase();
    const op = String(body?.op ?? "").trim().toLowerCase();
    const query = cleanQuery(body?.query);
    const limit = clampLimit(body?.limit, 20);

    let tracks: Track[] = [];

    if (provider === "jiosaavn") {
      if (op === "search") {
        if (query === "") return json({ provider, op, tracks: [] });
        tracks = await saavnSearch(query, limit);
      } else if (op === "trending") {
        tracks = await saavnTrending(limit);
      }
    }
    // ytmusic / spotify: reserved, empty response by design (the app then
    // renders one fewer source instead of an error).

    return json({ provider, op, count: tracks.length, tracks });
  } catch (_e) {
    // Never fail the music page: an empty result is the correct degradation.
    return json({ provider: "", op: "", count: 0, tracks: [] });
  }
});