// WP-P3: host-only voice moderation (mute-all / kick).
// Env: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET (supabase secrets).
// Body: { room_code, action: "mute_all" | "kick", target_identity? }.
// Caller must be the room host (checked against rooms.host_user_id).
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { RoomServiceClient, TrackSource } from "npm:livekit-server-sdk@2";

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

    const { room_code, action, target_identity } = await req.json();
    const code = String(room_code ?? "").trim().toUpperCase();

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: room } = await admin
      .from("rooms")
      .select("room_id, host_user_id, status")
      .eq("room_id", code)
      .single();
    if (!room || room.host_user_id !== user.id || room.status === "closed") {
      return json({ error: "host only" }, 403);
    }

    const svc = new RoomServiceClient(
      Deno.env.get("LIVEKIT_URL")!,
      Deno.env.get("LIVEKIT_API_KEY")!,
      Deno.env.get("LIVEKIT_API_SECRET")!,
    );
    if (action === "mute_all") {
      const parts = await svc.listParticipants(code);
      for (const p of parts) {
        if (p.identity === user.id) continue; // never mute self
        await svc.mutePublishedTrack(code, p.identity, TrackSource.MICROPHONE, true);
      }
      return json({ ok: true, muted: parts.length });
    }
    if (action === "kick" && target_identity) {
      if (target_identity === user.id) return json({ error: "no self-kick" }, 400);
      await svc.removeParticipant(code, String(target_identity));
      return json({ ok: true });
    }
    return json({ error: "bad action" }, 400);
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
