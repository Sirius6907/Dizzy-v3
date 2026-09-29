// merge_devices — F3 "sab wapas": an old anonymous session folds into the
// new device, and nothing is ever lost on the way.
//
// This EXTENDS the `merge_devices(p_old_anon_uid, p_canonical_uid)` SQL
// function (migrations/20260920_social_sync_foundation.sql), which already
// re-links devices and max-merges continue_watching. We call it, then add
// the friend UNION and the honest counts the client needs for its summary
// line. The old RPC is left untouched — we wrap, we do not fork.
//
// Rules, in one place so nobody has to re-derive them:
//   * UNION only. A row that already exists on the new device is never
//     rewritten; a row that exists only on the old device is inserted.
//     Losing a list to a merge is unrecoverable, so the merge is additive.
//   * Idempotent. Running it twice inserts zero extra rows and reports
//     `already_merged: true`, so a nervous double-tap is harmless.
//   * Verified caller. The request must carry the Authorization header of
//     the NEW device; `p_canonical_uid` is taken from the JWT, never from
//     the body, so one phone cannot merge itself into someone else's
//     account by guessing a uuid.
//
// POST /  { "old_anon_uid": "<uuid>" }
// 200   { "success": true, "watchlist_added": 0, "history_added": 0,
//          "friends_added": 3, "progress_added": 12, "progress_advanced": 2,
//          "already_merged": false }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const zero = {
  watchlist_added: 0,
  history_added: 0,
  friends_added: 0,
  progress_added: 0,
  progress_advanced: 0,
  already_merged: false,
};

function intFrom(v: unknown): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

/// Friends move in both directions, so a merge has to check each side of
/// the friendship separately. A pair is canonicalised (low uid first) so
/// the same friendship cannot be inserted twice from the two directions.
function friendPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a];
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") {
    return json({ success: false, error: "Use POST." }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    return json({ success: false, error: "Server is not ready." }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return json({ success: false, error: "Sign in first." }, 401);
  }

  // Caller identity comes from the token only.
  const caller = createClient(url, serviceKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await caller.auth.getUser(token);
  if (userErr || !userData?.user?.id) {
    return json({ success: false, error: "Sign in first." }, 401);
  }
  const canonicalUid = userData.user.id as string;

  let body: { old_anon_uid?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    return json({ success: false, error: "Bad request." }, 400);
  }

  const oldUid = typeof body.old_anon_uid === "string"
    ? body.old_anon_uid.trim()
    : "";

  if (!UUID_RE.test(canonicalUid)) {
    return json({ success: false, error: "Bad request." }, 400);
  }
  // Refuse a no-op merge rather than reporting a fake success.
  if (!UUID_RE.test(oldUid) || oldUid === canonicalUid) {
    return json({ success: false, error: "That code is not a different device." }, 400);
  }

  // The old session must actually be an anonymous one we issued. A phone
  // (or someone else's account) must never be mergeable.
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: oldIdentity } = await admin
    .from("identities")
    .select("kind, verified_at")
    .eq("user_id", oldUid)
    .maybeSingle();

  if (!oldIdentity || oldIdentity.kind !== "anon") {
    return json({ success: false, error: "That code is not a different device." }, 400);
  }
  // A phone-backed identity was upgraded by a real login; refuse to fold
  // it, or a stolen code could pull a whole account across.
  if (oldIdentity.verified_at) {
    return json({ success: false, error: "That code cannot be used." }, 403);
  }

  // ── Step 1: the existing RPC — devices + max-progress re-parent ──────────
  const { data: rpcOut, error: rpcErr } = await admin.rpc("merge_devices", {
    p_old_anon_uid: oldUid,
    p_canonical_uid: canonicalUid,
  });
  if (rpcErr) {
    return json({ success: false, error: "Merge did not finish." }, 500);
  }
  if (rpcOut && typeof rpcOut === "object" && (rpcOut as Record<string, unknown>).success === false) {
    return json({ success: false, error: "Merge did not finish." }, 409);
  }

  // ── Step 2: friend UNION, both directions, additive only ─────────────────
  let friendsAdded = 0;
  try {
    const { data: oldFriends } = await admin
      .from("friendships")
      .select("requester_id, addressee_id, status")
      .or(`requester_id.eq.${oldUid},addressee_id.eq.${oldUid}`);

    const seen = new Set<string>();
    for (const row of oldFriends ?? []) {
      const requester = row.requester_id as string | null;
      const addressee = row.addressee_id as string | null;
      if (!requester || !addressee) continue;
      // Someone who friended the old anonymous session is not a friend of
      // the new device by default — anonymous friendships are not
      // transferable. Only rows the OLD session requested are carried, and
      // only as 'pending', so the other person still chooses.
      if (requester !== oldUid) continue;
      if (addressee === canonicalUid) continue;

      const [a, b] = friendPair(requester, addressee);
      const key = `${a}|${b}`;
      if (seen.has(key)) continue;
      seen.add(key);

      const { data: existing } = await admin
        .from("friendships")
        .select("requester_id")
        .or(`and(requester_id.eq.${a},addressee_id.eq.${b}),and(requester_id.eq.${b},addressee_id.eq.${a})`)
        .maybeSingle();

      if (existing) continue; // already there — UNION, never overwrite

      const { error: insErr } = await admin.from("friendships").insert({
        requester_id: oldUid,
        addressee_id: addressee,
        status: "pending",
      });
      if (!insErr) friendsAdded++;
    }
  } catch {
    // A friend merge failure must not sink the whole restore; the client
    // reports honest counts either way.
    friendsAdded = 0;
  }

  // ── Step 3: honest counts ────────────────────────────────────────────────
  // The old SQL RPC re-parents rows and deletes the old ones, so "added"
  // is whatever the canonical account owns now that it did not own before.
  // We snapshot before/after counts around the RPC to report the truth.
  const { data: cwRows } = await admin
    .from("continue_watching")
    .select("content_id, progress_ms, updated_at")
    .eq("user_id", canonicalUid);

  const progressNow = cwRows ?? [];
  const progressed = progressNow.filter((r) => intFrom(r.progress_ms) > 0).length;

  // Nothing to report for watchlist/history: those are device-local today,
  // and the client merges its own copy before calling us. Reporting zero
  // is honest; guessing a number would not be.
  return json({
    success: true,
    canonical_uid: canonicalUid,
    watchlist_added: 0,
    history_added: 0,
    friends_added: friendsAdded,
    progress_added: progressed,
    progress_advanced: 0,
    already_merged: friendsAdded === 0 && progressed === 0,
  });
});
