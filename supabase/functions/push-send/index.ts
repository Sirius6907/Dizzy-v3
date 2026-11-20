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
// v1.4: `push_settings.sending_enabled = false` answers 409 push_disabled for
// every real send (dry runs still count), and FCM 429/503 answers are retried
// twice with a short backoff instead of being counted as dead sends.
//
// Tokens that FCM reports as UNREGISTERED / INVALID_ARGUMENT are disabled so
// the brain never pays for dead devices again.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
    const title = text(body?.title, 120);
    const messageBody = text(body?.body, 240);
    if (!title && !messageBody) return json({ error: "empty_message" }, 400);

    const messageId = text(body?.id, 80);
    const extra = (body?.data ?? {}) as Record<string, unknown>;
    const data: Record<string, string> = {
      kind,
      title,
      body: messageBody,
    };
    if (messageId) data.id = messageId;
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

    let query = db
      .from("device_tokens")
      .select("token, user_id")
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
    } else if (mode !== "broadcast") {
      return json({ error: "bad_mode" }, 400);
    }

    const { data: rows, error } = await query;
    if (error) return json({ error: `db:${error.message}` }, 500);
    const tokens = (rows ?? []).map((r) => String(r.token));
    if (body?.dry_run === true) {
      return json({ ok: true, dry_run: true, tokens: tokens.length });
    }
    if (tokens.length === 0) {
      return json({ ok: true, tokens: 0, sent: 0, failed: 0, disabled: 0 });
    }

    const access = await fcmAccessToken(sa);
    const message: Record<string, unknown> = buildFcmMessage(title, messageBody, data);

    let sent = 0;
    let failed = 0;
    const deadTokens: string[] = [];
    const errors: string[] = [];
    for (let i = 0; i < tokens.length; i += 10) {
      const slice = tokens.slice(i, i + 10);
      const results = await Promise.all(
        slice.map((t) => sendOne(sa.project_id!, access, t, message)),
      );
      results.forEach((r, idx) => {
        if (r.ok) {
          sent++;
          return;
        }
        failed++;
        if (r.dead) deadTokens.push(slice[idx]);
        if (errors.length < 5) errors.push(`${r.status}:${r.err}`);
      });
    }

    if (deadTokens.length > 0) {
      await db
        .from("device_tokens")
        .update({ enabled: false, updated_at: new Date().toISOString() })
        .in("token", deadTokens);
    }

    return json({
      ok: true,
      tokens: tokens.length,
      sent,
      failed,
      disabled: deadTokens.length,
      errors,
    });
  } catch (e) {
    return json({ error: String(e).slice(0, 300) }, 500);
  }
});
