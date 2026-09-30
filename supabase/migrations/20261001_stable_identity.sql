-- Dizzy Phase H — stable device identity v2.   (2026-10-01)
-- Run ONCE: supabase db query --linked -f supabase/migrations/20261001_stable_identity.sql
--
-- Problem (plan §1b): hwid was sha256(random SharedPreferences code) —
-- uninstall wipes it, same phone returns as a NEW device forever.
-- Fix: hwid_hash = sha256(ANDROID_ID + fixed app salt), stable across
-- reinstalls (same app-signing key since v1.1.7). Raw ANDROID_ID never
-- reaches the server — only the salted hash.
--
-- Adds:
--   devices.hwid_legacy   old random-derived hash (dedupe helper)
--   devices.hwid_stable   false = weak anchor (null ANDROID_ID / fallback)
--   devices.activity      enum for live fleet (Phase L)
--   devices.last_heartbeat_at
--   unique index on hwid_hash (ONE physical device = ONE row forever)
--   device_boot RPC — upsert + reinstall auto-merge + revoked report
--     (replaces client-side RLS upsert; extends merge_devices intent:
--      hwid-keyed auto-merge at boot, not only OTP-link merge)

-- ═══════════ 1) new columns ═══════════
alter table public.devices
  add column if not exists hwid_legacy text,
  add column if not exists hwid_stable boolean not null default true,
  add column if not exists activity text not null default 'idle'
    check (activity in ('idle','watching','listening','reading',
                        'downloading','in_room','in_voice')),
  add column if not exists last_heartbeat_at timestamptz;

-- ═══════════ 2) dedupe BEFORE unique index (plan §H3) ═══════════
-- Rows sharing a stable hwid: keep newest by last_seen, re-parent the
-- loser's continue_watching (greatest progress wins), delete loser.
do $$
declare
  r record;
  v_keep uuid;
  v_dup record;
begin
  for r in
    select hwid_hash
    from public.devices
    where hwid_hash is not null and hwid_hash <> ''
    group by hwid_hash
    having count(*) > 1
  loop
    select device_id into v_keep
    from public.devices
    where hwid_hash = r.hwid_hash
    order by last_seen_at desc nulls last, created_at desc
    limit 1;

    for v_dup in
      select device_id, user_id
      from public.devices
      where hwid_hash = r.hwid_hash and device_id <> v_keep
    loop
      -- carry the loser's watch progress onto the keeper's owner
      insert into public.continue_watching
        (user_id, content_id, progress_ms, duration_ms, updated_at)
      select k.user_id, c.content_id, c.progress_ms, c.duration_ms, c.updated_at
      from public.continue_watching c
      cross join (select user_id from public.devices where device_id = v_keep) k
      where c.user_id = v_dup.user_id
      on conflict (user_id, content_id) do update
        set progress_ms = greatest(public.continue_watching.progress_ms,
                                   excluded.progress_ms),
            updated_at  = greatest(public.continue_watching.updated_at,
                                   excluded.updated_at);

      delete from public.continue_watching where user_id = v_dup.user_id;
      delete from public.devices where device_id = v_dup.device_id;
    end loop;
  end loop;
end $$;

-- ONE row per physical device, forever.
create unique index if not exists devices_hwid_hash_uq
  on public.devices (hwid_hash)
  where hwid_hash is not null and hwid_hash <> '';

-- ═══════════ 3) device_boot RPC ═══════════
-- Called by the app at boot (replaces the direct upsert). SECURITY DEFINER
-- so it may re-parent rows across anon uids (reinstall auto-merge) while
-- RLS stays owner-only for reads/self-revoke.
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
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.devices%rowtype;
  v_merged  boolean := false;
  v_revoked boolean := false;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'auth required');
  end if;
  if p_hwid_hash is null or length(p_hwid_hash) < 16 then
    return jsonb_build_object('success', false, 'error', 'bad hwid');
  end if;

  -- (a) exact stable-hwid match
  select * into v_row from public.devices
  where hwid_hash = p_hwid_hash
  for update;

  -- (b) pre-H legacy row (hash of old random code) → adopt under new hash
  if not found then
    select * into v_row from public.devices
    where hwid_legacy = p_hwid_legacy and p_hwid_legacy <> ''
      and (hwid_stable = false or hwid_hash is null or hwid_hash = '')
    order by last_seen_at desc nulls last
    limit 1
    for update;
    if found then
      update public.devices
      set hwid_hash = p_hwid_hash, hwid_stable = p_hwid_stable
      where device_id = v_row.device_id;
      v_row.hwid_hash := p_hwid_hash;
      v_merged := true;
    end if;
  end if;

  -- (c) row exists but belongs to another session (reinstall) → auto-merge
  if found and v_row.user_id is distinct from v_uid then
    if v_row.hwid_stable and p_hwid_stable then
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
    update public.devices set user_id = v_uid
    where device_id = v_row.device_id;
    v_row.user_id := v_uid;
  end if;

  -- (d) touch / insert
  if found then
    update public.devices
    set device_code  = coalesce(nullif(p_device_code, ''), v_row.device_code),
        sid          = coalesce(nullif(p_sid, ''), v_row.sid),
        platform     = coalesce(nullif(p_platform, ''), v_row.platform),
        app_version  = coalesce(nullif(p_app_version, ''), v_row.app_version),
        hwid_stable  = p_hwid_stable,
        last_seen_at = now()
    where device_id = v_row.device_id;
  else
    begin
      insert into public.devices
        (user_id, device_code, hwid_hash, hwid_legacy, hwid_stable,
         sid, platform, app_version, last_seen_at)
      values
        (v_uid,
         coalesce(nullif(p_device_code,''), '0000000'),
         p_hwid_hash, nullif(p_hwid_legacy,''),
         p_hwid_stable,
         -- sid is NOT NULL + unique: derive a per-device fallback so a
         -- blank client value can never collide across devices.
         coalesce(nullif(p_sid,''), 'DIZ-' || substring(p_hwid_hash from 1 for 16)),
         p_platform, p_app_version, now());
    exception when unique_violation then
      -- race: same hwid inserted concurrently (or sid clash) → touch instead
      update public.devices
      set user_id     = v_uid,
          device_code = coalesce(nullif(p_device_code,''), device_code),
          sid         = coalesce(nullif(p_sid,''), sid),
          app_version = coalesce(nullif(p_app_version,''), app_version),
          hwid_stable = p_hwid_stable,
          last_seen_at = now()
      where hwid_hash = p_hwid_hash
      returning revoked_at into v_revoked;
      return jsonb_build_object(
        'success', true,
        'revoked', coalesce(v_revoked, false),
        'merged', v_merged);
    end;
  end if;

  select revoked_at is not null into v_revoked
  from public.devices where hwid_hash = p_hwid_hash;

  return jsonb_build_object(
    'success', true,
    'revoked', coalesce(v_revoked, false),
    'merged', v_merged);
end;
$$;
revoke all on function public.device_boot(text, text, boolean, text, text, text, text) from public;
grant execute on function public.device_boot(text, text, boolean, text, text, text, text)
  to authenticated;

-- ═══════════ 4) merge_devices: also clear superseded legacy rows ═══════════
-- (OTP-link merge stays uid-keyed; reinstall auto-merge now lives in
--  device_boot above — both paths covered.)
create or replace function public.merge_devices(
  p_old_anon_uid uuid,
  p_canonical_uid uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_old_anon_uid is null or p_canonical_uid is null
     or p_old_anon_uid = p_canonical_uid then
    return jsonb_build_object('success', false, 'error', 'Invalid merger parameters');
  end if;

  -- Re-link devices to canonical user
  update public.devices
  set user_id = p_canonical_uid
  where user_id = p_old_anon_uid;

  -- Re-parent continue_watching without data loss (max progress wins)
  insert into public.continue_watching (user_id, content_id, progress_ms, duration_ms, updated_at)
  select p_canonical_uid, content_id, progress_ms, duration_ms, updated_at
  from public.continue_watching
  where user_id = p_old_anon_uid
  on conflict (user_id, content_id) do update
  set progress_ms = greatest(public.continue_watching.progress_ms, excluded.progress_ms),
      updated_at = greatest(public.continue_watching.updated_at, excluded.updated_at);

  delete from public.continue_watching where user_id = p_old_anon_uid;

  return jsonb_build_object('success', true, 'canonical_uid', p_canonical_uid);
end;
$$;
