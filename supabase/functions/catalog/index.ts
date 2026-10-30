// catalog — ready-made browse feeds for the app (v1.2.0-C2, warm-cache P22).
// Env: TMDB_API_KEY or TMDB_BEARER (same as tmdb-proxy).
//   + SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (warm-row read-through).
// GET ?feed=trending|popular|top_rated|discover|fresh
//     &type=movie|tv|all&page=1
//     &region=IN&language=hi,en&providers=8,9&window=45
// Returns slim cards: {id, title, poster, backdrop, year, rating, media_type, lang}
// + warm:true when served from catalog_cache.
//
// v1.3.3-F1: India-first.
//   `discover` filters by origin country (default IN) + original language.
//   `fresh` is the home feed with no manual curation: it asks TMDB for titles
//   released inside a rolling window that is computed from `now` on every
//   request (so "current year" advances by itself), then interleaves the
//   languages 1:1 so Hindi and English get equal slots. Its cache row is only
//   fresh for 30 minutes, so a title TMDB has just indexed reaches the app
//   on the next call — no daily edit anywhere.
//
// A cold edge (no secrets/table yet) behaves exactly like C2 (warm:false).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const IMG = "https://image.tmdb.org/t/p/w500";
const DAY_MS = 86_400_000;

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

/** Two letters, uppercase; anything else falls back to IN. */
function cleanRegion(raw: string | null): string {
  const v = (raw ?? "").trim().toUpperCase();
  return /^[A-Z]{2}$/.test(v) ? v : "IN";
}

/** Comma list of ISO 639-1 codes. Empty = no language filter. */
function parseLanguages(raw: string | null): string[] {
  return (raw ?? "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter((s) => /^[a-z]{2}$/.test(s))
    .slice(0, 6);
}

/** Comma list of TMDB watch-provider ids (positive ints). */
function cleanProviders(raw: string | null): string {
  return (raw ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => /^\d{1,6}$/.test(s))
    .slice(0, 8)
    .join("|");
}

function isoDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function slim(r: unknown, fallbackType: string): Record<string, unknown> {
  const m = r as Record<string, unknown>;
  return {
    id: m.id,
    title: m.title ?? m.name ?? "",
    poster: m.poster_path ? IMG + m.poster_path : null,
    backdrop: m.backdrop_path
      ? (IMG + m.backdrop_path).replace("w500", "w780")
      : null,
    year: String(m.release_date ?? m.first_air_date ?? "").slice(0, 4),
    rating: m.vote_average ?? 0,
    media_type: (m.media_type as string) ?? fallbackType,
    lang: (m.original_language as string) ?? "",
    votes: Number(m.vote_count ?? 0),
    pop: Number(m.popularity ?? 0),
  };
}

/** Popularity proxy for merged rows: TMDB `vote_average` alone over-ranks
 *  obscure 10.0 titles, so weight the score by how many people voted. */
function popScore(c: Record<string, unknown>): number {
  const votes = Number(c.votes ?? 0);
  const rating = Number(c.rating ?? 0);
  return rating * Math.log10(1 + votes);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const u = new URL(req.url);
    const feed = u.searchParams.get("feed") ?? "trending";
    const type = u.searchParams.get("type") ?? "all";
    const page = u.searchParams.get("page") ?? "1";
    const region = cleanRegion(u.searchParams.get("region"));
    const languages = parseLanguages(u.searchParams.get("language"));
    const languageExpr = languages.join("|");
    const providers = cleanProviders(u.searchParams.get("providers"));
    const windowDays = Math.min(
      365,
      Math.max(1, Number(u.searchParams.get("window") ?? 45) || 45),
    );

    let path = "";
    if (feed === "trending") {
      const t = type === "movie" || type === "tv" ? type : "all";
      path = `/trending/${t}/week`;
    } else if (feed === "popular") {
      path = type === "tv" ? "/tv/popular" : "/movie/popular";
    } else if (feed === "top_rated") {
      path = type === "tv" ? "/tv/top_rated" : "/movie/top_rated";
    } else if (feed === "discover") {
      if (type === "all") path = "discover:all";
      else if (type === "movie" || type === "tv") path = `/discover/${type}`;
      else return json({ error: "bad type" }, 400, 60);
    } else if (feed === "fresh") {
      if (type !== "movie" && type !== "tv" && type !== "all") {
        return json({ error: "bad type" }, 400, 60);
      }
    } else {
      return json({ error: "bad feed" }, 400, 60);
    }

    const apiKey = Deno.env.get("TMDB_API_KEY") ?? "";
    const bearer = Deno.env.get("TMDB_BEARER") ?? "";
    if (!apiKey && !bearer) return json({ error: "server misconfigured" }, 500, 10);

    // P22/F1: read-through warm cache. Any cache fault → cold path.
    // The key carries every filter so one region never serves another's row.
    // `fresh` is 30 minutes: new TMDB titles must land without a cron edit.
    const cacheKey =
      `${feed}|${type}|${page}|${region}|${languageExpr}|${providers}` +
      (feed === "fresh" ? `|w${windowDays}` : "");
    const ttlMs = feed === "fresh" ? 30 * 60 * 1000 : 6 * 3600 * 1000;
    const headers: Record<string, string> = { Accept: "application/json" };
    if (bearer) headers["Authorization"] = `Bearer ${bearer}`;

    const tmdbGet = async (tmdbPath: string, extra: Record<string, string> = {}) => {
      const target = new URL("https://api.themoviedb.org/3" + tmdbPath);
      target.searchParams.set("page", page);
      for (const [k, v] of Object.entries(extra)) target.searchParams.set(k, v);
      if (!bearer) target.searchParams.set("api_key", apiKey);
      const res = await fetch(target.toString(), { headers });
      return await res.json();
    };

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
        if (row && !Number.isNaN(at) && Date.now() - at < ttlMs) {
          return json({ page: Number(page), total_pages: 1, items: row.items, warm: true });
        }
      }
    } catch (_) {
      /* cold path below */
    }

    const discoverParams = (kind: "movie" | "tv", lang: string) => {
      const p: Record<string, string> = {
        sort_by: "popularity.desc",
        with_origin_country: region,
        include_adult: "false",
      };
      if (lang) p.with_original_language = lang;
      if (providers) {
        p.with_watch_providers = providers;
        p.watch_region = region;
      }
      return p;
    };

    let items: Record<string, unknown>[] = [];
    let totalPages = 1;
    let tmdbPage: unknown = 1;

    if (feed === "fresh") {
      // Rolling window computed per request — no hardcoded year anywhere.
      const nowMs = Date.now();
      const lte = isoDate(nowMs);
      const gte = isoDate(nowMs - windowDays * DAY_MS);
      const wanted = languages.length ? languages : ["hi", "en"];
      const kinds: ("movie" | "tv")[] = type === "all" ? ["movie", "tv"] : [type];

      const raw = new Map<string, Record<string, unknown>[]>();
      for (const lang of wanted) raw.set(lang, []);

      const dated = (kind: "movie" | "tv", r: Record<string, unknown>) =>
        String(kind === "movie" ? r.release_date : r.first_air_date ?? "");

      await Promise.all(
        wanted.flatMap((lang) =>
          kinds.map(async (kind) => {
            const p = discoverParams(kind, lang);
            // `en` means Hollywood, not just Indian-origin English titles —
            // without this the English bucket is ~7 films and the 1:1
            // interleave collapses into an all-Hindi tail.
            if (lang === "en") delete p.with_origin_country;
            if (kind === "movie") {
              p["primary_release_date.gte"] = gte;
              p["primary_release_date.lte"] = lte;
            } else {
              p["first_air_date.gte"] = gte;
              p["first_air_date.lte"] = lte;
            }
            const data = await tmdbGet(`/discover/${kind}`, p);
            const rows = ((data.results ?? []) as Record<string, unknown>[])
              .filter((r) => {
                const d = dated(kind, r);
                return d >= gte && d <= lte;
              })
              .map((r) => ({ ...r, media_type: kind }));
            raw.get(lang)!.push(...rows);
          }),
        ),
      );

      // What India is actually watching right now — theatrical releases plus
      // this week's trending titles. Anything older than the window is dropped
      // so "trending" never re-surfaces a 2009 classic.
      const [nowPlaying, trendMovie, trendTv] = await Promise.all([
        tmdbGet("/movie/now_playing", { region }),
        tmdbGet("/trending/movie/week"),
        tmdbGet("/trending/tv/week"),
      ]);
      const audience: [Record<string, unknown>, "movie" | "tv"][] = [
        ...((nowPlaying.results ?? []) as Record<string, unknown>[]).map(
          (r) => [r, "movie"] as [Record<string, unknown>, "movie"],
        ),
        ...((trendMovie.results ?? []) as Record<string, unknown>[]).map(
          (r) => [r, "movie"] as [Record<string, unknown>, "movie"],
        ),
        ...((trendTv.results ?? []) as Record<string, unknown>[]).map(
          (r) => [r, "tv"] as [Record<string, unknown>, "tv"],
        ),
      ];
      for (const [r, kind] of audience) {
        if (!kinds.includes(kind)) continue;
        const d = dated(kind, r);
        if (!d || d < gte || d > lte) continue;
        const lang = String(r.original_language ?? "");
        if (!raw.has(lang)) continue;
        raw.get(lang)!.push({ ...r, media_type: kind });
      }

      // TMDB returns a lot of zero-buzz day-one uploads; keep rows with a
      // real audience signal, then rank by popularity weighted by vote count
      // so a rated title beats an unrated one with the same buzz, and cap
      // each bucket so one language can't flood the rail.
      const minPop = 3;
      const titleKey = (c: Record<string, unknown>) =>
        String(c.title ?? "").toLowerCase().replace(/[^a-z0-9]/g, "") +
        "|" + String(c.year ?? "");
      const bucket = (lang: string) => {
        const seenId = new Set<string>();
        const seenTitle = new Set<string>();
        return (raw.get(lang) ?? [])
          .map((r) => slim(r, String(r.media_type ?? "movie")))
          .filter((c) => {
            if (Number(c.votes ?? 0) < 2 && Number(c.pop ?? 0) < minPop) {
              return false;
            }
            const k = `${c.media_type}:${c.id}`;
            const t = titleKey(c);
            if (seenId.has(k) || seenTitle.has(t)) return false;
            seenId.add(k);
            seenTitle.add(t);
            return true;
          })
          .sort((a, b) =>
            Number(b.pop ?? 0) * Math.log10(2 + Number(b.votes ?? 0)) -
            Number(a.pop ?? 0) * Math.log10(2 + Number(a.votes ?? 0))
          )
          .slice(0, 20);
      };

      // 1:1 interleave so Hindi and English share the top of the rail.
      const lists = wanted.map(bucket);
      const seen = new Set<string>();
      const seenTitle = new Set<string>();
      const maxLen = lists.reduce((n, l) => Math.max(n, l.length), 0);
      for (let i = 0; i < maxLen && items.length < 60; i++) {
        for (const list of lists) {
          const c = list[i];
          if (!c) continue;
          const k = `${c.media_type}:${c.id}`;
          const t = titleKey(c);
          if (seen.has(k) || seenTitle.has(t)) continue;
          seen.add(k);
          seenTitle.add(t);
          items.push(c);
        }
      }
      totalPages = 1;
    } else if (path === "discover:all") {
      // `all` has no single discover endpoint — merge movies and TV, dedupe,
      // then rank by popularity so the first row is genuinely the hottest.
      const [movies, tv] = await Promise.all([
        tmdbGet("/discover/movie", discoverParams("movie", languageExpr ? languages[0] ?? "" : "")),
        tmdbGet("/discover/tv", discoverParams("tv", languageExpr ? languages[0] ?? "" : "")),
      ]);
      const seen = new Set<string>();
      items = [
        ...((movies.results ?? []) as unknown[]).map((r) => slim(r, "movie")),
        ...((tv.results ?? []) as unknown[]).map((r) => slim(r, "tv")),
      ]
        .filter((c) => {
          const k = `${c.media_type}:${c.id}`;
          if (seen.has(k)) return false;
          seen.add(k);
          return true;
        })
        .sort((a, b) => popScore(b) - popScore(a));
    } else {
      const extra: Record<string, string> = {};
      if (path.startsWith("/discover")) {
        Object.assign(extra, discoverParams(
          path.startsWith("/discover/tv") ? "tv" : "movie",
          languageExpr,
        ));
      } else if (feed === "popular" || feed === "top_rated") {
        extra.region = region;
      }
      const data = await tmdbGet(path, extra);
      const fallback = path.startsWith("/tv") || path.startsWith("/discover/tv")
        ? "tv"
        : "movie";
      items = ((data.results ?? []) as unknown[]).map((r) => slim(r, fallback));
      totalPages = data.total_pages ?? 1;
      tmdbPage = data.page ?? 1;
    }

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
    return json({ page: tmdbPage, total_pages: totalPages, items, warm: false });
  } catch (e) {
    return json({ error: String(e) }, 500, 10);
  }
});
