// scraper-ingest — crowdsourced dead-scraper votes (ADMIN backend).
// Auth: any signed-in app user (anon auth ok). Server validates + dedupes.
// Body: { scraper: "vidfast", kind: "empty"|"error"|"slow", app_version: "1.2.0" }
// Rules: 1 vote per reporter+scraper per 24h (soft dedupe, returns ok:true anyway).

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

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: ***"Authorization")! } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);

    const { scraper, kind, app_version } = await req.json();
    const name = String(scraper ?? "").trim().toLowerCase().slice(0, 40);
    if (!/^[a-z0-9_-]{2,40}$/.test(name)) return json({ error: "bad scraper" }, 400);
    const k = ["empty", "error", "slow"].includes(String(kind)) ? String(kind) : "empty";

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    // Soft dedupe: same reporter+scraper within 24h => skip insert, still ok.
    const { data: recent } = await admin
      .from("scraper_reports")
      .select("id")
      .eq("reporter_id", user.id)
      .eq("scraper", name)
      .gt("created_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString())
      .limit(1);
    if (!recent || recent.length === 0) {
      await admin.from("scraper_reports").insert({
        reporter_id: user.id,
        scraper: name,
        kind: k,
        app_version: String(app_version ?? "").slice(0, 20),
      });
    }
    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
