# Watch Together — Protocol v2 (2026-09-12, Dizzy v1.2.0)

Transport: **Supabase Realtime broadcast** (`WatchPartyService.sendControl`).
One channel per room; every frame is event `'control'` with payload:

```json
{ "type": "<host_state|media_switch>",
  "position_ms": 12345,
  "text": "<WatchSyncMessage JSON>",
  "sent_at": "2026-09-12T10:00:00.000Z" }
```

## Message types (row `type`)

| Type | Sender | Meaning |
|---|---|---|
| `host_state` | host, 2 Hz heartbeat | "I am here, at this position, playing/paused" |
| `media_switch` | host, on pick | "We now watch this — open it" (+ guest auto-open) |

Legacy `play/pause/seek/chat` rows may still arrive from old clients; the
v2 parser reads only `host_state`/`media_switch` and ignores the rest.

## `WatchSyncMessage` JSON (`text` field)

`v` (protocol version, current **2**), `type` (always `host_state` inside the
JSON), `media_ref` (`tmdb:…`/`tt…`/plugin id — the ONLY switch key),
`media_title`, `season`, `episode`, `position_ms`, `playing`, `speed`,
`audio_track`, `sub_track`, `host_sent_at` (ms epoch — guest clock-skew math),
`prefetch_ready` (host pre-verified a playable source).

## Guest rules (locked 2026-09-12)

1. **Version guard**: `v` outside 1–2 → message dropped (`isUsable == false`).
   A v3 host never hijacks a v2 guest.
2. **Empty ref** → dropped (no wrong-title switch, ever).
3. **Heartbeat**: guest re-aligns silently when drift > 1.5 s; shows
   "Catching up…" past 5 s. 2 Hz host / 500 ms guest tick.
4. **Media switch**: guest auto-opens the new title (prefetch metadata first
   when `prefetch_ready`, title-search fallback when resolution fails).
5. **Control lock**: while in a party, play/pause/seek follow the host.
   Guests keep volume, mic, chat. Leaving restores full control.
6. **Malformed JSON** → dropped + counted (`sync_msg_parse`, throttled).
   The party never dies because of one bad frame.

## Rooms (Supabase `rooms` table)

Persistent: name + pass only at create. Host's current title flows through
`updateCurrentMedia` (RPC, host-only) → `rooms.current_media_ref` /
`current_title` → public lobby view `public_rooms_safe` (+`speaker` dots are
client-side LiveKit state, never in the DB). Private rooms: 6-digit pass
(SHA-256 stored). v1 cap: **20 members** (server-enforced, client mirrors).
Stale empty rooms are swept by the lobby pull-refresh.

## Voice (separate rail)

Voice is **LiveKit**, not Realtime broadcast: join-muted, deafen = Discord
rules (hear nobody, mic forced off, undeafen keeps mic off until tapped).
Voice tokens come from the `party-voice-admin` edge function (host-gated).

## Chat (separate rail)

Chat is **DB-backed** (`chat_messages` + realtime row stream): send/react/pin
by host, timestamps, host badges, Easy-English toasts on failure.
