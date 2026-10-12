// missedcall-webhook — STUB (v1.3.3-T1.3). Deploy on gateway-key day.
//
// The missed-call provider calls this when the user rings the gateway
// number. We match the caller number to a pending phone_links row and
// mark it verified via confirm_phone_link().
//
// PROVIDER SETUP (key day, admin does this once):
//   1. Get a virtual number from MSG91 / 2Factor / Exotel (missed-call plan).
//   2. Set remote_config.missedcall_gateway_number = the number (E.164).
//   3. Set this fn's secrets: PROVIDER_SECRET (webhook signing key),
//      SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (auto-available).
//   4. supabase functions deploy missedcall-webhook
//   5. Register this fn's URL as the provider's webhook.
//
// POST / { "from": "+91…", "signature": "…" }
// 200  { "success": true }  (always 200 — providers disable hooks on 4xx)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function cleanNumber(raw: unknown): string {
  const v = String(raw ?? "").replace(/[^0-9+]/g, "");
  return /^\+[1-9][0-9]{7,14}$/.test(v) ? v : "";
}

serve(async (req) => {
  if (req.method === "OPTIONS") return json({ ok: true });
  if (req.method !== "POST") return json({ success: false }, 405);

  // TODO(key day): verify HMAC signature with PROVIDER_SECRET.
  // const secret = Deno.env.get("PROVIDER_SECRET") ?? "";
  // …compare against req.headers / body signature…

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ success: false, error: "bad json" });
  }

  const from = cleanNumber(body.from);
  if (!from) return json({ success: false, error: "bad number" });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Find the pending row for this caller number (any user, newest first).
  const { data: row } = await sb
    .from("phone_links")
    .select("user_id")
    .eq("phone_e164", from)
    .eq("status", "pending")
    .order("last_request_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!row) return json({ success: false, error: "no pending link" });

  const { data, error } = await sb.rpc("confirm_phone_link", {
    p_user_id: (row as { user_id: string }).user_id,
  });
  if (error) return json({ success: false, error: "confirm failed" });
  return json({ success: true, result: data });
});
