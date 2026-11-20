-- Dizzy v1.4.3 — device code registry: every telemetry row knows its device.
-- Run: supabase db query --linked -f supabase/migrations/20261121_device_code_registry.sql
--
-- Problem (Phase 1 of the telemetry plan): 4 519 of 5 062 error hits (89%)
-- could not be tied to a device. Two independent causes, both server-side:
--
--   1. `device_boot` OVERWRITES devices.device_code on every boot. The code
--      is minted per install, so a reinstall leaves the old code behind with
--      no row that remembers it — every error reported under the old code
--      becomes an orphan the moment the app boots again.
--   2. `report_error` accepts any well-formed 7-digit code and stores it
--      with no lookup at all, so it happily writes rows for codes that no
--      device row ever carried.
--
-- Fix, in one place:
--   * `device_codes` — a registry mapping code -> device_id/user_id. A code
--     is never deleted when the device row moves on; the registry is the
--     memory `devices.device_code` never had.
--   * `device_boot` records the OUTGOING code before it overwrites it, and
--     records the incoming one after. It also stops a `sid` collision from
--     aborting the whole boot (the app swallows that error, so a collision
--     used to mean the device silently stopped updating forever).
--   * `report_error` stamps `device_id`/`user_id` from the registry and
--     `auth.uid()`, and self-heals a code it has never seen by looking it
--     up on `devices`.
--
-- `device_logs.device_id` is deliberately NOT a foreign key: telemetry is an
-- append-only log and must survive a device row being merged or deleted.
-- `user_id` is not a FK for the same reason. Both are attribution, not
-- ownership.
--
-- Backfill of the existing orphans is a separate file
-- (20261121_device_logs_backfill.sql) because it is a data operation, not a
-- schema one, and it must be re-runnable on its own.
--
-- Idempotent: IF NOT EXISTS / CREATE OR REPLACE / DROP+CREATE throughout.

-- ═══════════ 1) device_codes registry ═══════════
create table if not exists public.device_codes (
  code          text primary key
                  check (code ~ '^[1-9][0-9]{6}$'),
  device_id     uuid,
  user_id       uuid,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  source        text not null default 'boot'
                  check (source in ('boot', 'report', 'backfill', 'admin'))
);

-- The panel asks "which codes did this device ever carry?".
create index if not exists device_codes_device_idx
  on public.device_codes (device_id, last_seen_at desc);

-- "what did this user's devices report?" — used by the admin device card.
create index if not exists device_codes_user_idx
  on public.device_codes (user_id, last_seen_at desc);

-- Pruning (Phase 5) walks oldest-first.
create index if not exists device_codes_last_seen_idx
  on public.device_codes (last_seen_at);

alter table public.device_codes enable row level security;
-- No policies: the registry is written only by SECURITY DEFINER functions
-- below, and read only through admin RPCs. A client has no business seeing
-- which codes belong to other people's devices.

comment on table public.device_codes is
  'Code -> device/user registry. Remembers every code a device ever carried so error telemetry stays attributable after a reinstall.';

-- ═══════════ 2) register helper ═══════════
-- First mapping wins: if two physical devices ever collide on the same
-- 7-digit code, the original owner keeps it. A later report from the
-- colliding device is still stored under the code, but attribution is not
-- stolen from the device that minted it.
create or replace function public.device_code_register(
  p_code      text,
  p_device_id uuid,
  p_user_id   uuid,
  p_source    text default 'boot'
) returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_code text := btrim(coalesce(p_code, ''));
  v_src  text := lower(btrim(coalesce(p_source, 'boot')));
  v_dev  uuid;
  v_usr  uuid;
begin
  if v_code !~ '^[1-9][0-9]{6}$' then return; end if;
  if v_src not in ('boot', 'report', 'backfill', 'admin') then
    v_src := 'admin';
  end if;

  select device_id, user_id into v_dev, v_usr
  from public.device_codes where code = v_code
  for update;

  if not found then
    insert into public.device_codes (code, device_id, user_id, source)
    values (v_code, p_device_id, p_user_id, v_src)
    on conflict (code) do nothing;
    return;
  end if;

  update public.device_codes
  set last_seen_at = now(),
      device_id = coalesce(v_dev, p_device_id),
      -- Only the owning device may move the user; a colliding device may
      -- fill a null but never overwrite a known owner.
      user_id = case
                  when v_dev is null or v_dev = p_device_id
                    then coalesce(p_user_id, v_usr)
                  else v_usr
                end,
      -- 'backfill' is a historical fact; do not relabel it on a later touch.
      source = case when source = 'backfill' then source else v_src end
  where code = v_code;
end;
$function$;

revoke all on function public.device_code_register(text, uuid, uuid, text) from public;
revoke all on function public.device_code_register(text, uuid, uuid, text) from anon;
revoke all on function public.device_code_register(text, uuid, uuid, text) from authenticated;

-- ═══════════ 3) device_logs gains attribution columns ═══════════
alter table public.device_logs
  add column if not exists device_id uuid,
  add column if not exists user_id   uuid;

create index if not exists device_logs_device_id_idx
  on public.device_logs (device_id, last_at desc);

create index if not exists device_logs_user_id_idx
  on public.device_logs (user_id, last_at desc);

-- `devices.device_code` is char(7), so every comparison in the RPCs below
-- trims it. Index the trimmed form or those lookups scan the table.
create index if not exists devices_device_code_trim_idx
  on public.devices (btrim(device_code));

-- ═══════════ 4) report_error: stamp the row with who and which device ═══
drop function if exists report_error(text, text, text, text, text, text);

create or replace function report_error(
  p_device_code text,
  p_platform    text,
  p_version     text,
  p_screen      text,
  p_code        text,
  p_detail      text,
  p_trail       text default ''
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device    text;
  v_platform  text;
  v_version   text;
  v_screen    text;
  v_code      text;
  v_detail    text;
  v_trail     text := '';
  v_tok       text;
  v_events    bigint;
  v_uid       uuid := auth.uid();
  v_device_id uuid;
  v_user_id   uuid;
  c_rate_cap constant int := 50; -- report events per device per 24h
begin
  -- Normalise: trim + lowercase, then validate against the allowlists.
  v_device := lower(btrim(coalesce(p_device_code, '')));
  if v_device !~ '^(unknown|[1-9][0-9]{6})$' then v_device := 'unknown'; end if;

  v_platform := lower(btrim(coalesce(p_platform, '')));
  if v_platform !~ '^(android|ios|windows|linux|macos|fuchsia|web|unknown)$'
    then v_platform := 'unknown'; end if;

  v_version := left(btrim(coalesce(p_version, '')), 32);

  v_screen := left(lower(btrim(coalesce(p_screen, ''))), 64);
  if v_screen !~ '^[a-z0-9_]{1,64}$' then v_screen := 'unknown'; end if;

  -- The code is the only field with no safe default: an unknown code is
  -- not telemetry, it is noise. Reject it.
  v_code := left(lower(btrim(coalesce(p_code, ''))), 48);
  if v_code !~ '^[a-z0-9_]{1,48}$' then return false; end if;

  v_detail := left(lower(btrim(coalesce(p_detail, ''))), 64);
  if v_detail !~ '^[a-z0-9_.-]*$' then v_detail := ''; end if;

  -- Trail: every token must be an enum, else the whole trail is dropped.
  v_trail := left(lower(btrim(coalesce(p_trail, ''))), 240);
  if v_trail <> '' then
    foreach v_tok in array string_to_array(v_trail, '>') loop
      if v_tok !~ '^[a-z][a-z0-9_]{0,31}$' then
        v_trail := '';
        exit;
      end if;
    end loop;
  end if;

  -- Attribution. The registry is the authority; `devices` is the fallback
  -- for a code minted before this migration that has not booted since.
  if v_device <> 'unknown' then
    select dc.device_id, dc.user_id into v_device_id, v_user_id
    from public.device_codes dc
    where dc.code = v_device;

    if v_device_id is null and v_user_id is null then
      select d.device_id, d.user_id into v_device_id, v_user_id
      from public.devices d
      where btrim(d.device_code) = v_device
      limit 1;
    end if;

    -- A signed-in reporter is a fact about the row even when the code was
    -- never registered; let the registry learn it.
    if v_user_id is null then v_user_id := v_uid; end if;
    if v_device_id is not null or v_user_id is not null then
      perform public.device_code_register(v_device, v_device_id, v_user_id, 'report');
    end if;
  else
    -- Crash before the code was minted: still attribute to the reporter so
    -- the row is not anonymous, and so the cap below is per-user.
    v_user_id := v_uid;
  end if;

  -- Per-device volume cap. The 'unknown' bucket used to share ONE global
  -- cap across every install on the planet; scope it to the reporter.
  if v_device = 'unknown' then
    select count(*) into v_events
      from device_logs
     where device_code = 'unknown'
       and user_id is not distinct from v_uid
       and last_at > now() - interval '24 hours';
  else
    select count(*) into v_events
      from device_logs
     where device_code = v_device
       and last_at > now() - interval '24 hours';
  end if;
  if v_events >= c_rate_cap then return false; end if;

  if v_device = 'unknown' then
    insert into device_logs(device_code, platform, app_version, screen, code,
                            detail, trail, device_id, user_id)
      values (v_device, v_platform, v_version, v_screen, v_code, v_detail,
              v_trail, v_device_id, v_user_id);
  else
    insert into device_logs(device_code, platform, app_version, screen, code,
                            detail, trail, device_id, user_id)
      values (v_device, v_platform, v_version, v_screen, v_code, v_detail,
              v_trail, v_device_id, v_user_id)
      on conflict (device_code, screen, code, detail, trail)
        where device_code <> 'unknown'
        do update set count = device_logs.count + 1,
                      last_at = now(),
                      app_version = excluded.app_version,
                      platform = excluded.platform,
                      -- a row first written before boot can gain its owner
                      -- on a later report; it never loses one.
                      device_id = coalesce(device_logs.device_id,
                                           excluded.device_id),
                      user_id = coalesce(device_logs.user_id,
                                         excluded.user_id);
  end if;
  return true;
end;
$$;

revoke all on function report_error(text, text, text, text, text, text, text) from public;
grant execute on function report_error(text, text, text, text, text, text, text)
  to authenticated;
-- Crash telemetry must still land when anonymous sign-in itself failed.
grant execute on function report_error(text, text, text, text, text, text, text)
  to anon;

-- ═══════════ 5) device_boot: remember the code it is about to replace ═══
-- No DROP: the signature and return type are unchanged, so CREATE OR REPLACE
-- swaps the body atomically. A DROP would leave a window where every boot in
-- flight fails.
create or replace function public.device_boot(
  p_hwid_hash   text,
  p_hwid_legacy text default '',
  p_hwid_stable boolean default true,
  p_device_code text default '',
  p_sid         text default '',
  p_platform    text default 'unknown',
  p_app_version text default 'unknown'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid       uuid := auth.uid();
  v_row       public.devices%rowtype;
  v_has_row   boolean := false;
  v_merged    boolean := false;
  v_revoked   boolean := false;
  v_adult     boolean := false;
  v_prev_uid  uuid;
  v_prev_name text;
  v_old_code  text;
  v_new_code  text;
  v_device_id uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'auth required');
  end if;
  if p_hwid_hash is null or length(p_hwid_hash) < 16 then
    return jsonb_build_object('success', false, 'error', 'bad hwid');
  end if;

  insert into public.identities (user_id, kind, identifier_hash, verified_at)
  values (v_uid, 'anon', left(p_hwid_hash, 128), null)
  on conflict (user_id, kind) do nothing;

  -- (a) exact stable-hwid match
  select * into v_row from public.devices
  where hwid_hash = p_hwid_hash
  for update;
  v_has_row := found;

  -- (b) pre-H legacy row → adopt under the new hash
  if not v_has_row and p_hwid_legacy <> '' then
    select * into v_row from public.devices
    where hwid_legacy = p_hwid_legacy
      and (hwid_stable = false or hwid_hash is null or hwid_hash = '')
    order by last_seen_at desc nulls last
    limit 1
    for update;
    v_has_row := found;
    if v_has_row then
      update public.devices
      set hwid_hash = p_hwid_hash, hwid_stable = p_hwid_stable
      where device_id = v_row.device_id;
      v_row.hwid_hash := p_hwid_hash;
      v_merged := true;
    end if;
  end if;

  -- A `sid` already owned by a different row must not be taken. Before this
  -- guard the UPDATE raised unique_violation, the whole RPC aborted, and the
  -- app's swallowed try/catch meant that device stopped updating forever.
  if btrim(coalesce(p_sid, '')) <> ''
     and exists (select 1 from public.devices
                  where sid = btrim(p_sid)
                    and device_id is distinct from v_row.device_id) then
    p_sid := '';
  end if;

  -- (c) row exists but belongs to another session (reinstall) → auto-merge.
  if v_has_row and v_row.user_id is distinct from v_uid then
    if exists (select 1 from auth.users u
               where u.id = v_row.user_id and coalesce(u.is_anonymous, false)) then
      v_prev_uid := v_row.user_id;
      select username into v_prev_name
      from public.usernames where user_id = v_prev_uid;
    end if;

    if v_row.hwid_stable and p_hwid_stable
       and to_regclass('public.continue_watching') is not null then
      insert into public.continue_watching
        (user_id, content_id, progress_ms, duration_ms, updated_at)
      select v_uid, content_id, progress_ms, duration_ms, updated_at
      from public.continue_watching
      where user_id = v_row.user_id
      on conflict (user_id, content_id) do update
        set progress_ms = greatest(public.continue_watching.progress_ms,
                                   excluded.progress_ms),
            updated_at  = greatest(public.continue_watching.updated_at,
                                   excluded.updated_at);
      delete from public.continue_watching where user_id = v_row.user_id;
      v_merged := true;
    end if;

    -- The name follows the device. Without this the username stayed on the
    -- dead anonymous uid and the owner could never claim it again.
    if v_prev_uid is not null
       and not exists (select 1 from public.usernames where user_id = v_uid) then
      update public.usernames
      set user_id = v_uid
      where user_id = v_prev_uid;
    end if;

    update public.devices
    set user_id = v_uid,
        previous_user_id = v_row.user_id
    where device_id = v_row.device_id;
    v_row.user_id := v_uid;
  end if;

  -- (d) touch / insert
  if v_has_row then
    v_device_id := v_row.device_id;
    v_old_code  := nullif(btrim(v_row.device_code), '');
    v_new_code  := nullif(btrim(coalesce(p_device_code, '')), '');

    -- Remember the code we are about to lose BEFORE losing it.
    if v_old_code is not null and v_old_code is distinct from v_new_code then
      perform public.device_code_register(v_old_code, v_device_id, v_uid, 'boot');
    end if;

    begin
      update public.devices
      set device_code  = coalesce(v_new_code, v_row.device_code),
          sid          = coalesce(nullif(p_sid, ''), v_row.sid),
          platform     = coalesce(nullif(p_platform, ''), v_row.platform),
          app_version  = coalesce(nullif(p_app_version, ''), v_row.app_version),
          hwid_stable  = p_hwid_stable,
          last_seen_at = now()
      where device_id = v_device_id;
    exception when unique_violation then
      -- Belt and braces: keep the boot alive even if a race took the sid
      -- between the guard above and this UPDATE.
      update public.devices
      set device_code  = coalesce(v_new_code, v_row.device_code),
          platform     = coalesce(nullif(p_platform, ''), v_row.platform),
          app_version  = coalesce(nullif(p_app_version, ''), v_row.app_version),
          hwid_stable  = p_hwid_stable,
          last_seen_at = now()
      where device_id = v_device_id;
    end;

    if v_new_code is not null then
      perform public.device_code_register(v_new_code, v_device_id, v_uid, 'boot');
    end if;
  else
    v_new_code := nullif(btrim(coalesce(p_device_code, '')), '');
    begin
      insert into public.devices
        (user_id, device_code, hwid_hash, hwid_legacy, hwid_stable,
         sid, platform, app_version, last_seen_at)
      values
        (v_uid,
         coalesce(v_new_code, '0000000'),
         p_hwid_hash, nullif(p_hwid_legacy, ''),
         p_hwid_stable,
         coalesce(nullif(p_sid, ''), 'DIZ-' || substring(p_hwid_hash from 1 for 16)),
         p_platform, p_app_version, now())
      returning device_id into v_device_id;

      if v_new_code is not null then
        perform public.device_code_register(v_new_code, v_device_id, v_uid, 'boot');
      end if;
    exception when unique_violation then
      update public.devices
      set user_id     = v_uid,
          previous_user_id = public.devices.user_id,
          device_code = coalesce(v_new_code, device_code),
          sid         = coalesce(nullif(p_sid, ''), sid),
          app_version = coalesce(nullif(p_app_version, ''), app_version),
          hwid_stable = p_hwid_stable,
          last_seen_at = now()
      where hwid_hash = p_hwid_hash
      returning device_id, revoked_at, adult_allowed
        into v_device_id, v_revoked, v_adult;

      if v_new_code is not null then
        perform public.device_code_register(v_new_code, v_device_id, v_uid, 'boot');
      end if;

      return jsonb_build_object(
        'success', true,
        'revoked', coalesce(v_revoked, false),
        'merged', v_merged,
        'adult_allowed', coalesce(v_adult, false),
        'previous_uid', null,
        'previous_username', null);
    end;
  end if;

  select revoked_at is not null, coalesce(adult_allowed, false)
  into v_revoked, v_adult
  from public.devices where hwid_hash = p_hwid_hash;

  return jsonb_build_object(
    'success', true,
    'revoked', coalesce(v_revoked, false),
    'merged', v_merged,
    'adult_allowed', coalesce(v_adult, false),
    'previous_uid', v_prev_uid,
    'previous_username', v_prev_name);
end;
$function$;
revoke all on function public.device_boot(text, text, boolean, text, text, text, text) from public;
revoke all on function public.device_boot(text, text, boolean, text, text, text, text) from anon;
grant execute on function public.device_boot(text, text, boolean, text, text, text, text)
  to authenticated;

comment on function public.device_boot(text, text, boolean, text, text, text, text) is
  'Boot upsert. Registers every code the device has carried in device_codes so telemetry stays attributable across reinstalls.';
