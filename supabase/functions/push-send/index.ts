// push-send — FCM v1 delivery for the device_tokens table (v1.3.3 Phase 3).
// Deploy: supabase functions deploy push-send --no-verify-jwt
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//      FIREBASE_SERVICE_ACCOUNT (the admin SDK JSON, stored as a secret —
//      never committed to the repo).
//
// POST (admin user token OR the service-role key in Authorization)
//   {
//     mode: "test" | "users" | "broadcast",
//     user_ids?: string[],        // mode=users
//     kind?: "releases" | "updates" | "downloads" | "social" | "announcements",
//     title: string,              // ≤120 chars, required
//     body?: string,              // ≤240 chars
//     id?: string,                // inbox dedupe id
//     data?: { entity_type, entity_id, poster, year, rating, lang,
//              sender_uid, sender_name, group_id, group_name, room_code,
//              avatar },
//     dry_run?: boolean
//   }
//   → { ok, tokens, sent, failed, disabled, errors }
//
// v1.3.6: `push_settings.sending_enabled = false` answers 409 push_disabled for
// every real send (dry runs still count), and FCM 429/503 answers are retried
// twice with a short backoff instead of being counted as dead sends.
//
// v1.3.7 — "update campaign" mode. A plain broadcast cannot say someone's
// name, so the app version nudge reads like spam. `mode: "update"` resolves
// each token's owner @username and each token's own reported app_version, then
// renders one of four short patterns per person (stable per campaign+user, so
// the same person always gets the same line and the four lines spread evenly).
// Only tokens whose reported version is BELOW `latest_version` are targeted,
// so a phone that already updated is never told to update to what it runs.
// Every message ends with the plain, unpunny truth: "v1.3.3 -> v1.3.7".
//   { mode: "update", campaign: "2026-11-26", latest_version: "1.3.7",
//     android_only: true, dry_run?: boolean }
// A `campaign` id is single-shot for 20 hours: re-sending the same id is
// refused (409 campaign_already_sent) so a double tap cannot spam the fleet.
//
// Tokens that FCM reports as UNREGISTERED / INVALID_ARGUMENT are disabled so
// the brain never pays for dead devices again.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { compareVersions, shouldNudge, versionPair } from "./version_compare.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const KINDS = new Set([
  "releases",
  "updates",
  "downloads",
  "social",
  "announcements",
]);

const MAX_TOKENS = 1000;

/// The four update-nudge lines. English only, 8–10 words once {name} is in,
/// hook first and the promotion second (the body). The body is also the plain
/// on-screen text: the version pair is never a joke and never a guess.
///
/// No body says "tap": the client has no route for kind=updates, so a tap
/// only foregrounds Dizzy and the promise would be a lie to the person who
/// believed it. The update itself lives where it always does — the in-app
/// update offer at launch and the Home banner.
///
/// The version pair is one {versions} placeholder, never a hand-built
/// "v{from} → v{latest}": a token that never reported a version would render
/// "v your version → v1.3.7". [versionPair] drops the left side instead.
type Pattern = { id: string; title: string; body: string };

const UPDATE_PATTERNS: Pattern[] = [
  {
    id: "a",
    title: "{name}, your Dizzy is wearing old socks 😅",
    body: "The new Dizzy is in the app — {versions}",
  },
  {
    id: "b",
    title: "{name}, something new just landed while you were watching",
    body: "Ready for you inside Dizzy — {versions}",
  },
  {
    id: "c",
    title: "{name}, don't let this old version hold you back",
    body: "Everything new is already here — {versions}",
  },
  {
    id: "d",
    title: "{name}, we saved you a spot on the new Dizzy",
    body: "Your update is waiting in the app — {versions}",
  },
];

/** FNV-1a. Small, stable, and the same answer on every runtime — a person
 *  must not get a different joke on a retry of the same campaign. */
function fnv1a(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** Replace {name}/{versions}, then repair the grammar a missing name
 *  leaves behind ("{name}, your…" -> "Your…"). */
export function renderPattern(tpl: string, vars: Record<string, string>): string {
  let out = tpl;
  for (const [k, v] of Object.entries(vars)) {
    out = out.split(`{${k}}`).join(v);
  }
  out = out
    .replace(/\{\w+\}/g, "")            // any var we did not supply
    .replace(/^\s*[,:—-]\s*/, "")        // leading ", "
    .replace(/\s{2,}/g, " ")
    .replace(/\s+([,.:;!?])/g, "$1")
    .trim();
  if (out) out = out[0].toUpperCase() + out.slice(1);
  return out;
}

/** Stable spread across the four lines, skewed by the campaign id so two
 *  campaigns in a row do not hit the same people with the same joke. */
export function pickPattern(campaign: string, userId: string): Pattern {
  const i = fnv1a(`${campaign}:${userId}`) % UPDATE_PATTERNS.length;
  return UPDATE_PATTERNS[i];
}


function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function text(raw: unknown, max: number): string {
  return String(raw ?? "").replace(/\s+/g, " ").trim().slice(0, max);
}

/** FCM v1 message shape. When the payload carries a poster URL it rides as
 *  the notification image (both the top-level notification and the
 *  android-specific override accept an `image` field per the FCM v1
 *  reference); a missing or empty poster sends no image key at all. */
export function buildFcmMessage(
  title: string,
  body: string,
  data: Record<string, string>,
): Record<string, unknown> {
  const notification: Record<string, unknown> = { title: title || "Dizzy", body };
  const androidNotification: Record<string, unknown> = {
    channel_id: String(data.kind ?? "releases"),
    sound: "default",
  };
  const poster = String(data.poster ?? "").trim();
  if (poster) {
    notification.image = poster;
    androidNotification.image = poster;
  }
  return {
    notification,
    data,
    android: {
      priority: "high",
      notification: androidNotification,
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: { aps: { sound: "default" } },
    },
  };
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

type ServiceAccount = {
  client_email?: string;
  private_key?: string;
  project_id?: string;
};

let cachedToken: { token: string; exp: number } | null = null;

async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.token;
  const enc = (o: unknown) =>
    b64url(new TextEncoder().encode(JSON.stringify(o)));
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${enc(header)}.${enc(claims)}`;
  const pem = String(sa.private_key ?? "")
    .replace(/-----[^-]+-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${b64url(new Uint8Array(sig))}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`oauth_${res.status}: ${JSON.stringify(data).slice(0, 200)}`);
  }
  cachedToken = {
    token: String(data.access_token),
    exp: now + Number(data.expires_in ?? 3600),
  };
  return cachedToken.token;
}

type SendResult = { ok: boolean; dead?: boolean; status: number; err: string };

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Send one message, surviving FCM's own throttling.
 *
 *  A 429 from FCM is a quota answer, not a verdict on the token: the old code
 *  counted it as a failed send and moved on, so a broadcast that tripped the
 *  per-project limit quietly lost the tail of the audience. 429 and 503 now
 *  get up to two more attempts with a short pause (honouring Retry-After when
 *  FCM sends one), and only the final answer is counted. */
async function sendOne(
  projectId: string,
  access: string,
  token: string,
  message: Record<string, unknown>,
): Promise<SendResult> {
  let last: SendResult = { ok: false, status: 0, err: "not_sent" };
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${access}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ message: { token, ...message } }),
        },
      );
      if (res.ok) return { ok: true, status: 200, err: "" };
      const err = (await res.text()).slice(0, 300);
      if (res.status === 429 || res.status === 503) {
        last = { ok: false, status: res.status, err };
        const retryAfter = Number(res.headers.get("retry-after") ?? "0");
        const wait = retryAfter > 0
          ? Math.min(retryAfter * 1000, 4000)
          : 400 * (attempt + 1);
        await sleep(wait);
        continue;
      }
      const dead =
        res.status === 404 ||
        err.includes("UNREGISTERED") ||
        err.includes("INVALID_ARGUMENT");
      return { ok: false, dead, status: res.status, err };
    } catch (e) {
      last = { ok: false, status: 0, err: String(e).slice(0, 200) };
      await sleep(300 * (attempt + 1));
    }
  }
  return last;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const svcKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";
    if (!url || !anon || !svcKey || !saRaw) {
      return json({ error: "server_misconfigured" }, 500);
    }
    let sa: ServiceAccount;
    try {
      sa = JSON.parse(saRaw);
    } catch {
      return json({ error: "firebase_secret_unparsable" }, 500);
    }
    if (!sa.client_email || !sa.private_key || !sa.project_id) {
      return json({ error: "firebase_secret_incomplete" }, 500);
    }

    const auth = req.headers.get("Authorization") ?? "";
    const isService = svcKey.length > 0 && auth === `Bearer ${svcKey}`;
    let callerId = "";
    if (!isService) {
      const userClient = createClient(url, anon, {
        global: { headers: { Authorization: auth } },
      });
      const { data } = await userClient.auth.getUser();
      if (!data?.user) return json({ error: "unauthorized" }, 401);
      callerId = data.user.id;
      const { data: adminFlag } = await userClient.rpc("is_admin");
      if (adminFlag !== true) return json({ error: "admin_only" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const mode = String(body?.mode ?? "test");
    const kind = KINDS.has(String(body?.kind)) ? String(body.kind) : "releases";
    const isUpdate = mode === "update";
    const campaign = text(body?.campaign, 64);
    const latestVersion = text(body?.latest_version, 32);
    const androidOnly = body?.android_only === true;
    if (isUpdate && !latestVersion) {
      return json({ error: "update_needs_latest_version" }, 400);
    }
    const title = text(body?.title, 120);
    const messageBody = text(body?.body, 240);
    if (!isUpdate && !title && !messageBody) {
      return json({ error: "empty_message" }, 400);
    }

    const messageId = text(body?.id, 80);
    const extra = (body?.data ?? {}) as Record<string, unknown>;
    const data: Record<string, string> = {
      kind,
      title,
      body: messageBody,
    };
    if (messageId) data.id = messageId;
    if (isUpdate) {
      data.latest_version = latestVersion;
      data.kind = kind === "releases" ? "updates" : kind;
    }
    for (const k of [
      "entity_type",
      "entity_id",
      "poster",
      "year",
      "rating",
      "lang",
      // v1.4 item 5 — social routing so a tap lands on the exact screen.
      "sender_uid",
      "sender_name",
      "group_id",
      "group_name",
      "room_code",
      "avatar",
    ]) {
      const v = text(extra[k], k === "poster" || k === "avatar" ? 500 : 64);
      if (v) data[k] = v;
    }

    const db = createClient(url, svcKey);

    // v1.4 kill switch. Read on every call, so "stop sending" is a switch in
    // the panel rather than a redeploy. A dry run still passes — counting
    // tokens is not sending — and a missing table (older project) fails open
    // so this can never break delivery on its own.
    const { data: settings } = await db
      .from("push_settings")
      .select("sending_enabled, paused_reason")
      .eq("id", 1)
      .maybeSingle();
    if (settings?.sending_enabled === false && body?.dry_run !== true) {
      return json({
        ok: false,
        error: "push_disabled",
        message: settings?.paused_reason ||
          "Push sending is paused in the admin panel.",
      }, 409);
    }

    // A campaign id is single-shot for 20 hours. The panel asks for a dry run
    // first; this stops the real send being repeated by a double click, a
    // refreshed tab, or a retry loop that only saw a timeout.
    if (isUpdate && campaign && body?.dry_run !== true) {
      const { data: prior } = await db
        .from("admin_push_events")
        .select("id, created_at")
        .eq("event", "send")
        .eq("target", campaign)
        .gt("created_at", new Date(Date.now() - 20 * 3600_000).toISOString())
        .limit(1);
      if (prior && prior.length > 0) {
        return json({
          ok: false,
          error: "campaign_already_sent",
          message: `Campaign ${campaign} was already sent at ${prior[0].created_at}.`,
        }, 409);
      }
    }

    let query = db
      .from("device_tokens")
      .select("token, user_id, platform, app_version")
      .eq("enabled", true)
      .limit(MAX_TOKENS);
    if (mode === "test") {
      if (!callerId) return json({ error: "test_needs_admin_user" }, 400);
      query = query.eq("user_id", callerId);
    } else if (mode === "users") {
      const ids = Array.isArray(body?.user_ids)
        ? body.user_ids.map((v: unknown) => String(v)).filter(Boolean)
        : [];
      if (ids.length === 0) return json({ error: "no_user_ids" }, 400);
      query = query.in("user_id", ids.slice(0, MAX_TOKENS));
    } else if (mode !== "broadcast" && mode !== "update") {
      return json({ error: "bad_mode" }, 400);
    }
    if (isUpdate && androidOnly) {
      // D2: the Windows portable ZIP has no updater, so a "please update" nudge
      // to it is a dead end. Android installs come from the release APK.
      query = query.eq("platform", "android");
    }

    const { data: rows, error } = await query;
    if (error) return json({ error: `db:${error.message}` }, 500);
    const targets = (rows ?? []).map((r) => ({
      token: String(r.token),
      userId: String(r.user_id ?? ""),
      from: text(r.app_version, 32),
    }));
    const considered = targets.length;
    const truncated = (rows ?? []).length >= MAX_TOKENS;

    // A "please update" line must never reach a phone that is already on the
    // target build — "v1.3.7 -> v1.3.7" is the definition of spam. Filter in
    // JS because PostgREST cannot compare dotted versions. A token with no
    // reported version is kept: it predates version reporting, so it is old.
    // The comparison itself lives in version_compare.ts, with a test.
    if (isUpdate) {
      const before = targets.length;
      const current = targets.filter((t) => shouldNudge(t.from, latestVersion));
      targets.splice(0, targets.length, ...current);
      console.log(
        `update campaign ${campaign || "(no id)"}: ${current.length}/${before} tokens below v${latestVersion}`,
      );
    }

    // device_tokens.app_version only moves when a phone re-registers its push
    // token, and registerToken() skips a token that has not changed. `devices`
    // is written by device_boot on every launch, so it is the fresher evidence.
    //
    // One map, two jobs. `freshest` is the newest version this user's own boots
    // report (never older than the token column), and it decides both whether a
    // nudge is still warranted AND which version the message prints — on the
    // live fleet one token says 1.3.3 while that phone's boot says 1.3.6, and
    // the body has to say 1.3.6. Soft: a failed read keeps the token (one extra
    // nudge beats silently dropping the whole fleet).
    const freshest = new Map<string, string>();
    if (isUpdate) {
      for (const t of targets) {
        if (t.from) freshest.set(t.userId, t.from);
      }
      const ids = [...new Set(targets.map((t) => t.userId).filter(Boolean))];
      if (ids.length > 0) {
        let bootsQuery = db
          .from("devices")
          .select("user_id, app_version, platform")
          .in("user_id", ids);
        if (androidOnly) bootsQuery = bootsQuery.eq("platform", "android");
        const { data: boots, error: bootErr } = await bootsQuery;
        if (bootErr) {
          console.error("devices freshness skipped:", bootErr.message);
        } else {
          for (const b of boots ?? []) {
            const uid = String(b.user_id ?? "");
            const v = text(b.app_version, 32);
            if (!uid || !v) continue;
            const prev = freshest.get(uid) ?? "";
            if (!prev || compareVersions(v, prev) > 0) freshest.set(uid, v);
          }
        }
      }
      const before = targets.length;
      const fresh = targets.filter((t) => {
        const v = freshest.get(t.userId) || t.from;
        return !v || shouldNudge(v, latestVersion);
      });
      targets.splice(0, targets.length, ...fresh);
      console.log(
        `campaign ${campaign || "(no id)"}: ${fresh.length}/${before} still below v${latestVersion}`,
      );
    }

    if (body?.dry_run === true) {
      return json({
        ok: true,
        dry_run: true,
        tokens: targets.length,
        considered,
        truncated,
        ...(isUpdate
          ? {
            latest_version: latestVersion,
            versions: [...new Set(targets.map((t) => t.from || "?"))].sort(),
          }
          : {}),
      });
    }
    if (targets.length === 0) {
      return json({ ok: true, tokens: 0, sent: 0, failed: 0, disabled: 0 });
    }

    // One username read for the whole fleet, never one query per phone.
    const names = new Map<string, string>();
    if (isUpdate) {
      const ids = [...new Set(targets.map((t) => t.userId).filter(Boolean))];
      if (ids.length > 0) {
        const { data: un } = await db
          .from("usernames")
          .select("user_id, username")
          .in("user_id", ids);
        for (const row of un ?? []) {
          const name = text(row.username, 24);
          if (name) names.set(String(row.user_id), name);
        }
      }
    }

    const fallbackFrom = text(body?.from_version, 32);

    /// What one phone would read. Split out of [messageFor] so a preview can
    /// return the exact strings with no FCM access token and no network call:
    /// the operator reads the 16 messages before any phone does.
    const textFor = (t: { userId: string; from: string }) => {
      const pattern = pickPattern(campaign || latestVersion, t.userId);
      const from = freshest.get(t.userId) || t.from || fallbackFrom;
      const vars = {
        name: names.get(t.userId) ?? "",
        versions: versionPair(from, latestVersion),
      };
      return {
        pattern: pattern.id,
        from,
        title: text(renderPattern(pattern.title, vars), 120),
        body: text(renderPattern(pattern.body, vars), 240),
      };
    };

    // Preview: every rendered message, nothing sent, nothing written. This is
    // the answer to "what exactly will land on these phones?" — a dry run only
    // counts tokens, which cannot catch a broken name, a bad pattern or a
    // stale version read.
    if (body?.preview === true) {
      return json({
        ok: true,
        preview: true,
        tokens: targets.length,
        considered,
        truncated,
        latest_version: latestVersion,
        messages: isUpdate
          ? targets.map((t) => ({
            user_id: t.userId,
            name: names.get(t.userId) ?? "",
            ...textFor(t),
          }))
          : [{ title, body: messageBody }],
      });
    }

    const access = await fcmAccessToken(sa);
    const plainMessage: Record<string, unknown> = buildFcmMessage(
      title,
      messageBody,
      data,
    );

    /// One message per phone in campaign mode: the joke carries the owner's
    /// own @username and the body carries that phone's own reported version.
    const messageFor = (t: { userId: string; from: string }) => {
      if (!isUpdate) return plainMessage;
      const { title: tTitle, body: tBody, from } = textFor(t);
      const payload: Record<string, string> = {
        ...data,
        title: tTitle,
        body: tBody,
      };
      if (from) payload.from_version = from;
      return buildFcmMessage(tTitle, tBody, payload);
    };

    // The receipt goes in BEFORE the first send. The old order wrote it after
    // the loop, so a timeout mid-loop left no row, the 20-hour guard had
    // nothing to see, and a retry could nudge people who had already been
    // nudged. A push cannot be recalled, so the claim comes first and the
    // numbers are filled in afterwards.
    let ledgerId: string | null = null;
    if (isUpdate && campaign) {
      const versionsUpFront = [...new Set(targets.map((t) => t.from).filter(Boolean))]
        .sort()
        .join(", ");
      const { data: claim, error: claimError } = await db
        .from("admin_push_events")
        .insert({
          actor_id: callerId || null,
          event: "send",
          mode: "update",
          target: campaign.slice(0, 120),
          kind: "updates",
          title: `Update campaign ${campaign}`.slice(0, 120),
          body: `sending v${versionsUpFront || "?"} -> v${latestVersion}`.slice(0, 240),
          tokens: targets.length,
          sent: 0,
          failed: 0,
          dry_run: false,
          error: ""
        })
        .select("id")
        .maybeSingle();
      if (claimError) console.error("push ledger claim:", claimError.message);
      ledgerId = claim?.id ? String(claim.id) : null;
    }

    let sent = 0;
    let failed = 0;
    const deadTokens: string[] = [];
    const errors: string[] = [];
    for (let i = 0; i < targets.length; i += 10) {
      const slice = targets.slice(i, i + 10);
      const results = await Promise.all(
        slice.map((t) =>
          sendOne(sa.project_id!, access, t.token, messageFor(t))
        ),
      );
      results.forEach((r, idx) => {
        if (r.ok) {
          sent++;
          return;
        }
        failed++;
        if (r.dead) deadTokens.push(slice[idx].token);
        if (errors.length < 5) errors.push(`${r.status}:${r.err}`);
      });
    }

    if (deadTokens.length > 0) {
      await db
        .from("device_tokens")
        .update({ enabled: false, updated_at: new Date().toISOString() })
        .in("token", deadTokens);
    }

    // Close out the receipt claimed before the loop. If the claim itself failed
    // (a cold project with no ledger table), fall back to the old write-after
    // order so the send is still recorded. Soft-fail either way: a missing
    // ledger must never hide a send that already happened.
    if (isUpdate && campaign) {
      const versions = [...new Set(targets.map((t) => t.from).filter(Boolean))]
        .sort()
        .join(", ");
      const receipt = {
        body: `v${versions || "?"} -> v${latestVersion}`.slice(0, 240),
        tokens: targets.length,
        sent,
        failed,
        error: errors.join(" ").slice(0, 300),
      };
      const { error: ledgerError } = ledgerId
        ? await db.from("admin_push_events").update(receipt).eq("id", ledgerId)
        : await db.from("admin_push_events").insert({
          actor_id: callerId || null,
          event: "send",
          mode: "update",
          target: campaign.slice(0, 120),
          kind: "updates",
          title: `Update campaign ${campaign}`.slice(0, 120),
          dry_run: false,
          ...receipt,
        });
      if (ledgerError) console.error("push ledger:", ledgerError.message);
    }

    return json({
      ok: true,
      tokens: targets.length,
      considered,
      truncated,
      sent,
      failed,
      disabled: deadTokens.length,
      errors,
      ...(isUpdate
        ? { campaign: campaign || null, latest_version: latestVersion }
        : {}),
    });
  } catch (e) {
    return json({ error: String(e).slice(0, 300) }, 500);
  }
});
