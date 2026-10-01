# Phase M — FCM Push Spec (NEXT RELEASE — spec only, do NOT build now)

> Status: **spec** · Plan: `.hermes/plans/2026-09-30_profile-hub-admin-control.md` §Phase M
> Owner: app + Supabase · Build gate: explicit go-ahead only

## 1. What this unlocks

| Today (app alive only) | With FCM push |
|---|---|
| DM / friend request / room invite → only while app is open (poll + DM outbox) | delivered while the app is **dead** |
| Announcement broadcast → in-app banner when the app next polls | heads-up instantly |
| Mandatory update (`min_app_version`) → banner at next launch | update-mandatory push |

Local notifications (Phase J) already render everything **while the app runs**. FCM is
the transport for when it does not.

## 2. Non-goals

- No iOS APNs work in this release beyond recording the secret slot (Android-first).
- No rich media / image push (text + tap-target only) — `NotificationService` renders it.
- No migration away from local notifications: push **feeds** the same renderer.

## 3. Data model — `push_tokens`

```sql
-- supabase/migrations/<next>_push_tokens.sql
create table if not exists public.push_tokens (
  token        text primary key,          -- FCM registration token
  user_id      uuid not null references auth.users(id) on delete cascade,
  device_id    uuid references public.devices(device_id) on delete set null,
  platform     text not null default 'android' check (platform in ('android','ios')),
  app_version  text not null default 'unknown',
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
alter table public.push_tokens enable row level security;

-- Users may manage ONLY their own tokens.
create policy "own push tokens: select"
  on public.push_tokens for select using (auth.uid() = user_id);
create policy "own push tokens: upsert"
  on public.push_tokens for insert with check (auth.uid() = user_id);
create policy "own push tokens: refresh"
  on public.push_tokens for update using (auth.uid() = user_id);
create policy "own push tokens: delete"
  on public.push_tokens for delete using (auth.uid() = user_id);
-- No client-side bulk read: only the send-push edge (service_role) scans it.
```

Rules:
- One row per token; `on conflict (token) do update` on every registration
  (token churn after reinstall is normal).
- `device_id` is soft-linked so `admin_device_revoke` can be extended later to
  drop that device's token.
- Deleting a token when FCM answers `UNREGISTERED` is mandatory — an empty
  cleanup loop means every send degrades forever.

## 4. Edge function — `supabase/functions/send-push/index.ts`

Pattern: same as `mint-livekit-token` (Deno `serve`, anon client + caller JWT,
then a **second** client with `SUPABASE_SERVICE_ROLE_KEY` for the write/scan).

```
POST /functions/v1/send-push
Authorization: Bearer <admin JWT>
{
  "kind": "social" | "announcements" | "updates" | "downloads",
  "scope": { "type": "user" | "topic", "target": "<uid>" | "announcements-all" },
  "payload": {
    "title": "...",            // ≤ 60 chars
    "body":  "...",            // ≤ 150 chars
    "route": "/dm/<id>",       // deep link, optional
    "data":  { ... }           // ≤ 2KB, string values only
  },
  "dry_run": false
}
```

### 4.1 Authorisation (order matters)

1. Reject non-`POST`, handle `OPTIONS`.
2. Verify caller JWT → `auth.getUser()`.
3. `is_admin()` check via the **service-role** client (the caller cannot be admin
   by asserting anything). Non-admin → `403`, and write an `admin_audit` row
   (`action='push:denied'`) so a probing admin is visible.
4. Validate `kind` against the four `NotificationKind` keys — an unknown kind
   must never reach the renderer.
5. Validate payload size/lengths (`400` on violation, list the field).

### 4.2 Topics vs device tokens

- **Broadcast** (`announcements-all`) → `POST /v1/projects/<proj>/messages:send`
  with `topic: announcements-all`. Devices subscribe at boot:
  `FirebaseMessaging.instance.subscribeToTopic('announcements-all')`.
- **Per-user** → topic `uid:<uuid>`, subscribed after login. No need to store a
  token to reach a user, which keeps the failure mode small (topic, not a token
  list) — but per-user targeting still benefits from `push_tokens` for
  token-level delivery receipts and dead-token pruning.

Both paths go through FCM **HTTP v1** (`firebase-admin` SDK or a direct OAuth2
JWT signed with the service account) — the legacy server key API is retired.

### 4.3 Delivery mode: data-only (this is the important decision)

Send **data messages**, not `notification` messages.

| | `notification` message (OS-rendered) | `data` message (app-rendered) |
|---|---|---|
| App dead, backgrounded, or killed | OS renders it directly | handler runs, then renders |
| Quiet hours (Phase J) | ❌ bypassed | ✅ respected |
| Per-kind toggles (Hub) | ❌ bypassed | ✅ respected |
| Inbox entry (Phase J) | ❌ never created | ✅ created |
| Language / Easy English copy | ❌ fixed at send time | ✅ localised at render time |

A push that ignores the user's own switch is the single loudest way to lose
trust, so: **data-only, always**, rendered through `NotificationService`.
Cost: delivery while the app is force-stopped depends on OEM background limits —
exactly the constraint the Phase K4 OEM-kill detector already measures.

## 5. App side

```yaml
# pubspec.yaml — Phase M only
firebase_core: ^3.x
firebase_messaging: ^15.x
```

```
lib/services/push/push_registration.dart   # token lifecycle
lib/services/push/push_background.dart     # @pragma('vm:entry-point') handler
```

- `initialize()`:
  1. `Firebase.initializeApp()` (needs `google-services.json` at build time).
  2. `requestPermission()` → on grant, `getToken()` → `upsert push_tokens`.
  3. `onTokenRefresh` → same upsert (FCM rotates tokens).
  4. subscribe: `announcements-all` always; `uid:<id>` after auth.
  5. `onMessage` (foreground) → **skip** — Phase J local notifications already
     handle the foreground path; ignore to avoid double rendering.
- Background handler (`@pragma('vm:entry-point')` so it survives AOT tree-shaking):

  ```dart
  @pragma('vm:entry-point')
  Future<void> firebaseMessagingBackgroundHandler(RemoteMessage m) async {
    final data = m.data;
    final kind = NotificationKind.fromKey(data['kind'] as String?);
    if (kind == null) return;                     // unknown kind → drop
    final gate = await NotificationGate.load();   // Phase J prefs
    if (!gate.allows(kind)) return;               // user turned it off
    if (gate.inQuietHours(DateTime.now())) return; // do not wake anyone
    await NotificationService.instance.showFromPush(kind, data); // existing renderer
  }
  ```
- `NotificationService` gains one method, `showFromPush(kind, data)`, that maps
  `title/body/route` onto the existing channel map — **no new channels**.

### 5.1 Kill-the-app semantics

- App force-stopped by the user → Android delivers nothing (OS rule, not ours).
  The dashboard's OEM-kill detector (Phase K4) already surfaces these devices.
- App killed by LRU → FCM data message wakes the process for the handler.
- Cold boot with no saved `NotificationGate` → defaults ON (Phase J default),
  then quiet hours are re-checked at render time.

## 6. Secrets — build-time, never in the repo

| Secret | Where | Rule |
|---|---|---|
| `google-services.json` | `android/app/` (gitignored) | injected by CI from a secret; **never committed** |
| FCM service account JSON | Supabase secret `FCM_SERVER_KEY_JSON` | `supabase secrets set` from the operator's machine |
| APNs key (`.p8`) | Supabase secret `APNS_KEY_P8` | iOS only; not used in this release |

CI step (release workflow): decode `GOOGLE_SERVICES_JSON_B64` →
`android/app/google-services.json` before `flutter build`. The build must
**fail loudly** if the file is absent for a release build, and must still
succeed for PR/CI builds that only run analyze + test.

## 7. Delivery contract (payload keys)

```json
{
  "kind": "social",          // one of: social | announcements | updates | downloads
  "title": "New message from KiteRunner",
  "body":  "Open to reply",
  "route": "/dm/<conversation_id>",
  "collapse_key": "dm:<conversation_id>",
  "ttl_s": "86400"           // string (FCM data values are strings)
}
```

- `collapse_key` → FCM `collapse_key` so a burst of DMs collapses to one.
- Update-mandatory push uses `kind: "updates"` and the existing
  `min_app_version` gate — the push never decides, it only points at the gate.

## 8. Rollout order (each step verifiable before the next)

1. Migration `push_tokens` + RLS → verify: user A cannot read user B's rows.
2. `send-push` edge with `dry_run: true` → verify: admin 200, non-admin 403 +
   `admin_audit` row.
3. App: token registration + topics (no rendering yet) → verify tokens appear in
   `push_tokens` after a fresh install.
4. Enable rendering through `NotificationService` → verify quiet hours and a
   switched-off kind **suppress** the push (the whole point of data-only).
5. Dashboard: "Send test push" button on the Announcements tab (admin-gated,
   audited) → verify end-to-end on a real device with the app killed.
6. Prune job: tokens answering `UNREGISTERED` are deleted.

## 9. Acceptance checklist

- [ ] Quiet hours respected for a push received with the app **killed**
- [ ] Per-kind OFF in Hub suppresses that kind's push
- [ ] Non-admin call to `send-push` → 403 + audit row
- [ ] `google-services.json` absent from `git ls-files`
- [ ] Announcement broadcast reaches every subscribed device exactly once
      (collapse on retry)
- [ ] DM push with the app killed opens the right conversation (`route`)
- [ ] Dead-token cleanup runs and `push_tokens` has no stale rows after it
