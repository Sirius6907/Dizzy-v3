// WP-P3: mints short-lived LiveKit tokens for party voice.
// Env (supabase secrets set): LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.
// Body: { room_code: "K7Q2M9" }. Identity = auth uid, name = device code.
// Grants: every joined member can publish+subscribe (Discord-style:
// all can speak; host controls via party-voice-admin mute_user/mute_all).
// Subscribe-only members would see a dead mic button with zero feedback.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { AccessToken } from "npm:livekit-server-sdk@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

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

    const { room_code } = await req.json();
    const code = String(room_code ?? "").trim().toUpperCase();
    if (!/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/.test(code)) {
      return json({ error: "bad room code" }, 400);
    }

    // Must be host or joined member; closed rooms rejected.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: room } = await admin
      .from("rooms")
      .select("room_id, host_user_id, status")
      .eq("room_id", code)
      .single();
    if (!room || room.status === "closed") return json({ error: "no room" }, 404);
    const { data: member } = await admin
      .from("room_members")
      .select("role")
      .eq("room_id", code)
      .eq("user_id", user.id)
      .single();
    const isHost = room.host_user_id === user.id;
    if (!isHost && !member) return json({ error: "not a member" }, 403);

    const at = new AccessToken(
      Deno.env.get("LIVEKIT_API_KEY")!,
      Deno.env.get("LIVEKIT_API_SECRET")!,
      { identity: user.id, name: code, ttl: "2h" },
    );
    at.addGrant({
      room: code,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });
    return json({
      token: await at.toJwt(),
      url: Deno.env.get("LIVEKIT_URL")!,
      is_host: isHost,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
