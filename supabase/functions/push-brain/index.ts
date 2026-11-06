// push-brain — picks one fresh title per user and sends it (v1.3.3 Phase 4).
// Deploy: supabase functions deploy push-brain --no-verify-jwt
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//      PUSH_CRON_TOKEN.
//
// POST (cron token OR admin user token)
//   {
//     dry_run?: boolean,       // preview only — nothing is claimed or sent
//     max_users?: number,      // default 200, cap 1000
//     user_ids?: string[],     // admin: target specific users
//     per_user?: number,       // default 1, cap 3
//     min_gap_hours?: number,  // default 20
//     per_day?: number,        // default 1
//     per_week?: number        // default 4
//   }
//   → { ok, users, sent, skipped, reasons, preview? }
//
// Order of checks, per user:
//   1. notification_settings — muted kind or quiet hours => skip;
//   2. pick_release_candidates() — taste match + this week's language balance;
//   3. claim_push() — atomic cadence gate (gap / day / week);
//   4. push-send — FCM delivery;
//   5. push_mark_sent() — sent rows count against cadence, failed rows do not.
//
// Everything is soft: one user's failure never stops the run.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const LANG_LABEL: Record<string, string> = {
  hi: "Hindi",
  en: "English",
  ta: "Tamil",
  te: "Telugu",
  ml: "Malayalam",
  kn: "Kannada",
  mr: "Marathi",
  bn: "Bengali",
  pa: "Punjabi",
};

type Candidate = {
  id: number;
  media_type: string;
  tmdb_id: number;
  title: string;
  lang: string;
  year: number | null;
  rating: string | number | null;
  poster: string | null;
  genres: string[] | null;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function clip(s: string, max: number) {
  return s.replace(/\s+/g, " ").trim().slice(0, max);
}

export type PushTone = "warm" | "playful";

/** Same title, same message. A per-run random choice would make a retry
 *  look like a different notification in the log. */
function stableVariant(seed: string, count: number): number {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  return h % count;
}

export function copyFor(c: Candidate, tone: PushTone | string = "warm") {
  const playful = tone === "playful";
  const hinglish = c.lang === "hi";
  const lang = LANG_LABEL[c.lang] ?? (c.lang || "").toUpperCase();
  const rating = Number(c.rating ?? 0);
  const year = c.year ? String(c.year) : "";
  const genre = (c.genres ?? []).map((g) => String(g).trim()).find(Boolean) ?? "";
  const meta = [
    year,
    lang,
    rating > 0 ? `${rating.toFixed(1)}/10` : "",
  ].filter(Boolean).join(" · ");
  const variant = stableVariant(`${c.media_type}:${c.tmdb_id}:${c.title}`, 3);

  if (playful && c.media_type === "tv") {
    if (hinglish) {
      const titles = [
        `Aaj raat: ${c.title}`,
        `${c.title} — episode mood?`,
        `Aaj ka pick: ${c.title}`,
      ];
      const bodies = [
        `${genre ? `${genre} ka ` : ""}episode, tumhare liye. ${meta}`,
        `Ek episode se mood set karein? ${meta}`,
        `Aaj ${c.title}? Ek episode, jab time mile. ${meta}`,
      ];
      return { title: clip(titles[variant], 120), body: clip(bodies[variant], 240) };
    }
    return {
      title: clip(`Tonight: ${c.title}`, 120),
      body: clip(`An episode of your ${genre || "show"}? ${meta}`, 240),
    };
  }

  if (playful) {
    if (hinglish) {
      const titles = [
        `Aaj raat: ${c.title}`,
        `${c.title} — tumhare liye`,
        `Psst… ${c.title}`,
      ];
      const bodies = [
        `${genre ? `${genre} + ` : ""}tumhara taste = match. ${meta}`,
        `Movie night banti hai. ${meta}`,
        `Ek tap, ek movie. ${meta}`,
      ];
      return { title: clip(titles[variant], 120), body: clip(bodies[variant], 240) };
    }
    const titles = [
      `${c.title} just found you`,
      `Psst — ${c.title}`,
      `${c.title} is waiting`,
    ];
    const bodies = [
      `Aaj ${genre || "watch"} mood? ${meta}`,
      `Exactly your kind of ${genre || "story"}. One tap?`,
      `One tap. One movie night. ${meta}`,
    ];
    return { title: clip(titles[variant], 120), body: clip(bodies[variant], 240) };
  }

  if (c.media_type === "tv") {
    return {
      title: clip(hinglish ? `${c.title} — aaj dekh lein?` : `Tonight: ${c.title}`, 120),
      body: clip(
        hinglish
          ? `Ek ${lang} episode, jab time mile. ${meta}`
          : `An ${lang} episode when you have time. ${meta}`,
        240,
      ),
    };
  }

  return {
    title: clip(hinglish ? `${c.title} ab Dizzy par` : `New on Dizzy: ${c.title}`, 120),
    body: clip(
      hinglish
        ? `Naya ${lang} movie. Jab man kare, tap karo. ${meta}`
        : `A new ${lang} movie is ready when you are. ${meta}`,
      240,
    ),
  };
}

function isQuiet(
  settings: {
    quiet_enabled?: boolean;
    quiet_start_minute?: number;
    quiet_end_minute?: number;
    tz_offset_minutes?: number;
  } | null,
  at: Date,
) {
  if (!settings?.quiet_enabled) return false;
  const s = Number(settings.quiet_start_minute ?? 1320) % 1440;
  const e = Number(settings.quiet_end_minute ?? 420) % 1440;
  if (s === e) return false;
  const utc = at.getUTCHours() * 60 + at.getUTCMinutes();
  const local = (utc + Number(settings.tz_offset_minutes ?? 0) + 1440) % 1440;
  return s < e ? local >= s && local < e : local >= s || local < e;
}

async function pool<T, R>(
  items: T[],
  size: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(size, items.length) }, worker),
  );
  return out;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const cronToken = Deno.env.get("PUSH_CRON_TOKEN") ?? "";
    if (!url || !anon || !svc) {
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

    const body = await req.json().catch(() => ({}));
    const dryRun = body?.dry_run === true;
    const maxUsers = Math.min(Math.max(Number(body?.max_users ?? 200), 1), 1000);
    const perUser = Math.min(Math.max(Number(body?.per_user ?? 1), 1), 3);
    const gap = Number.isFinite(Number(body?.min_gap_hours))
      ? Math.max(0, Number(body.min_gap_hours))
      : 20;
    const perDay = Number.isFinite(Number(body?.per_day))
      ? Math.max(0, Number(body.per_day))
      : 1;
    const perWeek = Number.isFinite(Number(body?.per_week))
      ? Math.max(0, Number(body.per_week))
      : 4;

    const db = createClient(url, svc);
    const since = new Date(Date.now() - 120 * 86_400_000).toISOString();
    let tokensQuery = db
      .from("device_tokens")
      .select("user_id, updated_at")
      .eq("enabled", true)
      .gte("updated_at", since)
      .order("updated_at", { ascending: false })
      .limit(5000);
    const wanted = Array.isArray(body?.user_ids)
      ? body.user_ids.map((v: unknown) => String(v)).filter(Boolean)
      : [];
    if (wanted.length > 0) tokensQuery = tokensQuery.in("user_id", wanted);

    const { data: tokenRows, error: tokenErr } = await tokensQuery;
    if (tokenErr) return json({ error: `db:${tokenErr.message}` }, 500);

    const users: string[] = [];
    for (const row of tokenRows ?? []) {
      const uid = String(row.user_id ?? "");
      if (uid && !users.includes(uid)) users.push(uid);
      if (users.length >= maxUsers) break;
    }
    if (users.length === 0) {
      return json({ ok: true, users: 0, sent: 0, skipped: 0, reasons: {} });
    }

    const { data: settingsRows } = await db
      .from("notification_settings")
      .select(
        "user_id, off_kinds, quiet_enabled, quiet_start_minute, quiet_end_minute, tz_offset_minutes, tone",
      )
      .in("user_id", users);
    const settings = new Map<string, Record<string, unknown>>();
    for (const row of settingsRows ?? []) {
      settings.set(String(row.user_id), row);
    }

    const now = new Date();
    const reasons: Record<string, number> = {};
    const preview: unknown[] = [];
    const note = (r: string) => {
      reasons[r] = (reasons[r] ?? 0) + 1;
    };

    type Outcome = { sent: number; logIds: number[] };

    const outcomes = await pool(users, 8, async (uid): Promise<Outcome> => {
      try {
        const s = settings.get(uid) ?? null;
        const off = Array.isArray(s?.off_kinds)
          ? (s!.off_kinds as string[])
          : [];
        if (off.includes("releases")) {
          note("muted");
          return { sent: 0, logIds: [] };
        }
        if (isQuiet(s, now)) {
          note("quiet");
          return { sent: 0, logIds: [] };
        }

        const { data: picks, error: pickErr } = await db.rpc(
          "pick_release_candidates",
          { p_user_id: uid, p_limit: perUser },
        );
        if (pickErr) {
          note("pick_error");
          return { sent: 0, logIds: [] };
        }
        const list = (picks ?? []) as Candidate[];
        if (list.length === 0) {
          note("no_match");
          return { sent: 0, logIds: [] };
        }

        let sent = 0;
        const logIds: number[] = [];
        for (const c of list) {
          const text = copyFor(c, s?.tone === "warm" ? "warm" : "playful");
          const dedupe = `rel_${c.media_type}_${c.tmdb_id}`;

          if (dryRun) {
            preview.push({
              user_id: uid,
              title: text.title,
              body: text.body,
              entity_id: String(c.tmdb_id),
            });
            note("preview");
            continue;
          }

          const { data: claim, error: claimErr } = await db.rpc("claim_push", {
            p_user_id: uid,
            p_kind: "releases",
            p_title: text.title,
            p_body: text.body,
            p_entity_type: c.media_type,
            p_entity_id: String(c.tmdb_id),
            p_candidate_id: c.id,
            p_dedupe_id: dedupe,
            p_min_gap_hours: gap,
            p_per_day: perDay,
            p_per_week: perWeek,
          });
          if (claimErr) {
            note("claim_error");
            continue;
          }
          if (claim?.ok !== true) {
            note(String(claim?.reason ?? "claim_denied"));
            continue;
          }
          const logId = Number(claim.log_id);
          logIds.push(logId);

          let status = "failed";
          let errText = "";
          try {
            const res = await fetch(`${url}/functions/v1/push-send`, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${svc}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                mode: "users",
                user_ids: [uid],
                kind: "releases",
                title: text.title,
                body: text.body,
                id: dedupe,
                data: {
                  entity_type: c.media_type,
                  entity_id: String(c.tmdb_id),
                  poster: c.poster ?? "",
                  year: c.year ? String(c.year) : "",
                  rating: Number(c.rating ?? 0)
                    ? Number(c.rating).toFixed(1)
                    : "",
                  lang: c.lang ?? "",
                },
              }),
              signal: AbortSignal.timeout(25_000),
            });
            const out = await res.json().catch(() => ({}));
            if (res.ok && Number(out?.sent ?? 0) > 0) {
              status = "sent";
              sent++;
            } else if (res.ok && Number(out?.tokens ?? 0) === 0) {
              status = "skipped";
              errText = "no_tokens";
            } else {
              errText = JSON.stringify(out).slice(0, 280);
            }
          } catch (e) {
            errText = String(e).slice(0, 280);
          }

          await db.rpc("push_mark_sent", {
            p_id: logId,
            p_status: status,
            p_error: errText,
          });
          note(status);
        }
        return { sent, logIds };
      } catch (e) {
        note("error");
        console.error("[push-brain] user failed", uid, e);
        return { sent: 0, logIds: [] };
      }
    });

    const sent = outcomes.reduce((n, o) => n + o.sent, 0);
    const resp: Record<string, unknown> = {
      ok: true,
      users: users.length,
      sent,
      skipped: users.length - sent,
      reasons,
      dry_run: dryRun,
    };
    if (dryRun) resp.preview = preview;
    return json(resp);
  } catch (e) {
    return json({ error: String(e).slice(0, 300) }, 500);
  }
});
