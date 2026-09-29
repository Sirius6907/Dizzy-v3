// report-error — error telemetry ingest (v1.2.0-T2.2, P2).
// Auth: any signed-in app user (anon session ok). Server re-validates the
// privacy contract, then calls the report_error() RPC, which is the only
// writer to device_logs.
// Body: { device_code, platform, app_version, screen, code, detail }
//
// PRIVACY CONTRACT: enum tokens only. No URLs, magnets, tokens, titles,
// stack traces or raw exception text. Anything outside the allowlists is
// dropped before it can reach the database. The client
// (lib/services/errors/app_error_log.dart) enforces the same contract, so
// this layer is defence in depth, not the primary gate.
//
// A rejected report returns {ok:true,stored:false}: the report was
// consumed, not retried. Answering 4xx here would make the client hold
// the entry in its 100-slot queue and retry forever.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const PLATFORMS = [
  "android", "ios", "windows", "linux", "macos", "fuchsia", "web", "unknown",
];
const CODE_MAX = 48;
const SCREEN_MAX = 64;
const DETAIL_MAX = 64;
const VERSION_MAX = 32;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

/**
 * Lowercase + trim, then require the WHOLE value to match [pattern].
 * A partial strip is not a sanitiser: "Bad state: no element" would become
 * "badstatenoelement" and still leak the words. Non-matching values are
 * dropped, so free text can never ride along in an enum column.
 */
function strict(raw: unknown, max: number, pattern: RegExp): string {
  const v = String(raw ?? "").trim().toLowerCase();
  if (v.length === 0) return "";
  if (v.length > max || !pattern.test(v)) return "";
  return v;
}

/**
 * Validate the wire payload. Returns null when `code` cannot be trusted —
 * an unusable code is noise, not telemetry, so the report is dropped.
 * `device_code` falls back to "unknown" so a crash before the install code
 * is minted is still counted.
 */
function normalize(body: Record<string, unknown>) {
  const code = strict(body?.code, CODE_MAX, /^[a-z0-9_]+$/);
  if (code === "") return null;

  const device = strict(body?.device_code, 7, /^(unknown|[1-9][0-9]{6})$/);
  const platform = strict(body?.platform, 8, /^[a-z0-9]+$/);
  const screen = strict(body?.screen, SCREEN_MAX, /^[a-z0-9_]+$/) || "unknown";

  return {
    device_code: device || "unknown",
    platform: PLATFORMS.includes(platform) ? platform : "unknown",
    app_version: strict(body?.app_version, VERSION_MAX, /^[a-z0-9_.+-]+$/),
    screen,
    code,
    detail: strict(body?.detail, DETAIL_MAX, /^[a-z0-9_.-]+$/),
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const p = normalize(body);
    if (!p) return json({ ok: true, stored: false });

    // Called on the user-scoped client so the RPC runs as `authenticated`
    // (it is SECURITY DEFINER, so the write still bypasses RLS).
    const { data, error } = await supabase.rpc("report_error", {
      p_device_code: p.device_code,
      p_platform: p.platform,
      p_version: p.app_version,
      p_screen: p.screen,
      p_code: p.code,
      p_detail: p.detail,
    });
    if (error) throw error;

    return json({ ok: true, stored: data === true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
