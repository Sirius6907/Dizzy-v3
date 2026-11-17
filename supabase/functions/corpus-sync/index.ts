// corpus-sync — fills the title corpus the resolver reads (v1.3.5, 2026-11-14).
// Deploy: supabase functions deploy corpus-sync --no-verify-jwt
// Env: TMDB_API_KEY or TMDB_BEARER, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
//      PUSH_CRON_TOKEN (optional), CORPUS_LANGS (optional).
//
// POST (cron token OR service role OR admin user token)
//   → { ok, scanned, upserted, by_lang, by_kind, pages }
//
// What it does
// ------------
// TMDB's /search cannot see regional titles (measured: 18 of 20 sampled
// Odia films return ZERO search hits), but /discover with
// with_original_language=<lang> returns them. So the resolver needs an
// INDEX, not a better search. This function builds that index.
//
// One row per (kind, TMDB id):
//   title          the localised title the app shows (English for anime)
//   original_title the original-language title (alias for lookups)
//   title_norm     cleaned title (lowercase, alnum only)
//   title_base     core title (subtitle + brackets removed)
//   year / lang / popularity
//
// Languages default to the app's catalogue languages:
//   hi, te, ml, kn  Bollywood buckets
//   or              Ollywood (Odia)
//   ja              anime (original_language ja, English names)
// TV is indexed for ja only; movies for the rest.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const DEFAULT_MOVIE_LANGS = ["hi", "te", "ml", "kn", "or"];
const DEFAULT_TV_LANGS = ["ja"];
const DEFAULT_PAGES = 25;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function ymd(d: Date) {
  return d.toISOString().slice(0, 10);
}

/** Cleaned title: lowercase, letters and digits only. */
function cleanTitle(value: string): string {
  return String(value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

/** Core title: brackets, subtitle and stop words removed. */
function baseTitle(value: string): string {
  let s = String(value ?? "").toLowerCase();
  s = s.replace(/\([^)]*\)/g, " ");
  s = s.replace(/:\s*[^:]*$/g, " ");
  s = s.replace(/[–—\-]\s*[^–—\-]*$/g, " ");
  s = s.replace(/\b(the|a|an|of|and|part|ka|ki|ke|with)\b/g, " ");
  s = s.replace(/[^a-z0-9]+/g, "");
  return s;
}

function envList(raw: string | undefined, fallback: string[]): string[] {
  const v = (raw ?? "").split(",").map((s) => s.trim().toLowerCase())
    .filter((s) => /^[a-z]{2}$/.test(s));
  return v.length ? Array.from(new Set(v)).slice(0, 12) : fallback;
}

type Row = Record<string, unknown>;

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
    if (!url || !svc || (!apiKey && !bearer)) {
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

    // Which slice of the catalogue to index:
    //   popularity - the most watched titles (the historical catalogue)
    //   release    - the newest titles, by release date (the films that
    //                came out this month, which a popularity sort never
    //                reaches: a new Odia film has zero votes)
    //   both       - both sweeps in one run
    // The cron runs them as two jobs so neither run gets near the edge
    // time limit; the rows accumulate in the table either way.
    let sweep = "popularity";
    try {
      const body = await req.json();
      const s = String((body as { sweep?: string })?.sweep ?? "").toLowerCase();
      if (s === "release" || s === "both" || s === "popularity") sweep = s;
    } catch (_) {
      /* no body: the popularity sweep */
    }
    const sweeps = sweep === "both" ? ["popularity", "release"] : [sweep];

    const movieLangs = envList(
      Deno.env.get("CORPUS_MOVIE_LANGS"),
      DEFAULT_MOVIE_LANGS,
    );
    const tvLangs = envList(Deno.env.get("CORPUS_TV_LANGS"), DEFAULT_TV_LANGS);
    const maxPages = Math.max(
      1,
      Math.min(60, Number(Deno.env.get("CORPUS_PAGES") ?? DEFAULT_PAGES) ||
        DEFAULT_PAGES),
    );

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

    const rows: Row[] = [];
    const byLang: Record<string, number> = {};
    const byKind: Record<string, number> = {};
    const errors: string[] = [];
    let scanned = 0;
    let pages = 0;

    const jobs: { kind: "movie" | "tv"; lang: string }[] = [
      ...movieLangs.map((lang) => ({ kind: "movie" as const, lang })),
      ...tvLangs.map((lang) => ({ kind: "tv" as const, lang })),
    ];

    // The newest slice: a film that came out this month has no votes yet,
    // so a popularity sort never reaches it. This is the slice the owner's
    // "latest releases" list lives in.
    const since = new Date(Date.now() - 540 * 86_400_000)
      .toISOString()
      .slice(0, 10);

    for (const sweepMode of sweeps) {
      for (const job of jobs) {
        const dateField = job.kind === "tv" ? "first_air_date" : "primary_release_date";
        for (let page = 1; page <= maxPages; page++) {
          pages++;
          const extra: Record<string, string> = {
            with_original_language: job.lang,
            include_adult: "false",
            page: String(page),
          };
          if (sweepMode === "release") {
            extra.sort_by = job.kind === "tv"
              ? "first_air_date.desc"
              : "primary_release_date.desc";
            extra[`${dateField}.gte`] = since;
            extra[`${dateField}.lte`] = new Date().toISOString().slice(0, 10);
          } else {
            extra.sort_by = "popularity.desc";
          }
          try {
            const data = await tmdb(`/discover/${job.kind}`, extra);
            const list = Array.isArray(data?.results) ? data.results : [];
            if (!list.length) break;
            scanned += list.length;
            for (const r of list as Row[]) {
              const title = String(r.title ?? r.name ?? "").trim();
              const id = Number(r.id);
              if (!title || !Number.isFinite(id)) continue;
              const original = String(r.original_title ?? r.original_name ?? "").trim();
              const date = String(r.release_date ?? r.first_air_date ?? "").trim();
              const year = date.length >= 4 ? Number(date.slice(0, 4)) : null;
              const titleNorm = cleanTitle(title);
              const titleBase = baseTitle(title) || titleNorm;
              if (!titleNorm) continue;
              rows.push({
                kind: job.kind,
                tmdb_id: id,
                title: title.slice(0, 300),
                original_title: original ? original.slice(0, 300) : null,
                title_norm: titleNorm,
                title_base: titleBase,
                year: Number.isFinite(year as number) ? year : null,
                lang: String(r.original_language ?? job.lang).slice(0, 8),
                popularity: Number(r.popularity ?? 0),
                source: `tmdb-discover:${job.lang}:${sweepMode}`,
                updated_at: new Date().toISOString(),
              });
              byLang[job.lang] = (byLang[job.lang] ?? 0) + 1;
              byKind[job.kind] = (byKind[job.kind] ?? 0) + 1;
            }
          } catch (e) {
            errors.push(
              `${sweepMode}/${job.kind}/${job.lang}@p${page}: ${String(e).slice(0, 80)}`,
            );
            break;
          }
        }
      }
    }

    // Deduplicate on (kind, tmdb_id) before writing: the same TMDB id can
    // surface in several language buckets.
    const unique = new Map<string, Row>();
    for (const r of rows) unique.set(`${r.kind}:${r.tmdb_id}`, r);
    const finalRows = [...unique.values()];

    const db = createClient(url, svc);
    const { error } = await db
      .from("title_corpus")
      .upsert(finalRows, { onConflict: "kind,tmdb_id" });
    if (error) return json({ error: `db:${error.message}` }, 500);

    return json({
      ok: true,
      sweep,
      scanned,
      pages,
      upserted: finalRows.length,
      by_lang: byLang,
      by_kind: byKind,
      errors,
      refreshed_at: ymd(new Date()),
    });
  } catch (e) {
    return json({ error: String(e).slice(0, 300) }, 500);
  }
});
