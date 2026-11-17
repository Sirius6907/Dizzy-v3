-- Dizzy v1.3.5 — username continuity across app updates and reinstalls.
-- Run: supabase db query --linked -f supabase/migrations/20261113_username_device_continuity.sql
-- then record the history row (never `db push`).
--
-- Problem (seen live, 2026-11-13): every row in public.usernames was held by
-- an anonymous uid, and 10 of those names had NO device row at all. A
-- reinstall re-points the device row to the fresh anonymous uid, but the
-- name stayed behind on the dead uid. The person then typed their own name
-- in the gate and got "already taken" — forever.
--
-- Fix, three parts:
--   1. device_boot: the username row follows the device row. A reinstall
--      keeps the name; the gate never asks again.
--   2. reclaim_username: a session may take back a name that is stranded
--      on an anonymous uid which has no live device rows (or whose devices
--      now belong to this session). Verified accounts are never touched.
--   3. claim_username / username_available: report 'reclaimable' instead of
--      the dead-end 'taken', so the app can offer the reclaim.
-- Plus admin RPCs so the dashboard can list and repair username ownership.

-- The transfer is recorded on the device row, so a name that still gets
-- stranded can be proved and reclaimed by the same physical device.
alter table public.devices add column if not exists previous_user_id uuid;

-- Older device_boot rows stored the uid itself in identities.identifier_hash
-- instead of the device hash, so the ledger could never prove device
-- continuity. Backfill the rows that still hold the placeholder.
update public.identities i
set identifier_hash = left(d.hwid_hash, 128)
from public.devices d
where d.user_id = i.user_id
  and i.kind = 'anon'
  and i.identifier_hash = i.user_id::text
  and d.hwid_hash is not null;

-- ═══════════ 1) helper: is this name reclaimable? ═══════════
-- Proof of ownership, not "the owner looks abandoned": the name's owner must
-- be an anonymous guest whose device this session physically owns. The
-- transfer is recorded on the device row itself (previous_user_id), so a
-- stranger can never take a stranded name — only the same phone can.
create or replace function public.username_reclaimable(p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.usernames un
    join auth.users au on au.id = un.user_id
    join public.devices d on d.previous_user_id = un.user_id
    where un.user_id = p_owner
      and coalesce(au.is_anonymous, false)
      and d.user_id = auth.uid()
  );
$function$;
revoke all on function public.username_reclaimable(uuid) from public;
grant execute on function public.username_reclaimable(uuid) to authenticated;

-- ═══════════ 2) reclaim_username ═══════════
create or replace function public.reclaim_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid   uuid := auth.uid();
  v_clean text := lower(trim(coalesce(p_username, '')));
  v_owner uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'code', 'auth', 'error', 'Authentication required');
  end if;

  if not (v_clean ~ '^[a-z0-9_]{3,20}$') then
    return jsonb_build_object('success', false, 'code', 'format', 'error', 'Username must be 3-20 letters, numbers, or underscores');
  end if;

  select user_id into v_owner
  from public.usernames where username_lower = v_clean;

  if v_owner is null then
    return jsonb_build_object('success', false, 'code', 'free', 'error', 'Username is not taken');
  end if;

  if v_owner = v_uid then
    return jsonb_build_object('success', true, 'code', 'ok', 'username', v_clean);
  end if;

  if not public.username_reclaimable(v_owner) then
    return jsonb_build_object('success', false, 'code', 'taken', 'error', 'This username is already taken');
  end if;

  -- Move the name to this session. The unique index on username_lower is
  -- satisfied because the row itself is the one being re-keyed.
  update public.usernames
  set user_id = v_uid
  where user_id = v_owner;

  insert into public.identity_history(user_id, kind, old_value, new_value)
  values (v_uid, 'username', v_clean, v_clean);

  return jsonb_build_object('success', true, 'code', 'ok', 'username', v_clean);
end;
$function$;
revoke all on function public.reclaim_username(text) from public;
grant execute on function public.reclaim_username(text) to authenticated;

-- ═══════════ 3) claim_username: report 'reclaimable' ═══════════
create or replace function public.claim_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(trim(coalesce(p_username, '')));
  v_old text;
  v_last timestamptz;
  v_owner uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'code', 'auth', 'error', 'Authentication required');
  end if;

  if not (v_clean ~ '^[a-z0-9_]{3,20}$') then
    return jsonb_build_object('success', false, 'code', 'format', 'error', 'Username must be 3-20 letters, numbers, or underscores');
  end if;

  if v_clean in ('admin', 'dizzy', 'official', 'support', 'help', 'system', 'root') then
    return jsonb_build_object('success', false, 'code', 'reserved', 'error', 'This username is reserved');
  end if;

  select username, last_change_at into v_old, v_last
  from public.usernames where user_id = v_uid;

  if v_old = v_clean then
    return jsonb_build_object('success', true, 'code', 'ok', 'username', v_clean);
  end if;

  if v_last is not null and v_last > now() - interval '7 days' then
    return jsonb_build_object('success', false, 'code', 'ratelimited', 'error', 'You can only change username once every 7 days');
  end if;

  select user_id into v_owner
  from public.usernames where username_lower = v_clean and user_id <> v_uid;

  if v_owner is not null then
    if public.username_reclaimable(v_owner) then
      return jsonb_build_object('success', false, 'code', 'reclaimable', 'error', 'This username was left behind on this device — reclaim it');
    end if;
    return jsonb_build_object('success', false, 'code', 'taken', 'error', 'This username is already taken');
  end if;

  begin
    if v_old is null then
      insert into public.usernames(user_id, username)
      values (v_uid, v_clean);
    else
      update public.usernames
      set username = v_clean, last_change_at = now()
      where user_id = v_uid;
    end if;
  exception when unique_violation then
    return jsonb_build_object('success', false, 'code', 'taken', 'error', 'This username is already taken');
  end;

  insert into public.identity_history(user_id, kind, old_value, new_value)
  values (v_uid, 'username', coalesce(v_old, 'auto-generated'), v_clean);

  return jsonb_build_object('success', true, 'code', 'ok', 'username', v_clean);
end;
$function$;
revoke all on function public.claim_username(text) from public;
grant execute on function public.claim_username(text) to authenticated;

-- ═══════════ 4) username_available: 'reclaimable' reason ═══════════
create or replace function public.username_available(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(trim(coalesce(p_username, '')));
  v_owner uuid;
begin
  if v_uid is null then
    return jsonb_build_object('available', false, 'reason', 'auth');
  end if;
  if not public.take_token('uname_check:' || v_uid::text, 60, 1) then
    return jsonb_build_object('available', null, 'reason', 'rate_limited');
  end if;
  if not (v_clean ~ '^[a-z0-9_]{3,20}$') then
    return jsonb_build_object('available', false, 'reason', 'format');
  end if;
  if v_clean in ('admin', 'dizzy', 'official', 'support', 'help', 'system', 'root') then
    return jsonb_build_object('available', false, 'reason', 'reserved');
  end if;
  select user_id into v_owner
  from public.usernames where username_lower = v_clean and user_id <> v_uid;
  if v_owner is not null then
    if public.username_reclaimable(v_owner) then
      return jsonb_build_object('available', true, 'reason', 'reclaimable');
    end if;
    return jsonb_build_object('available', false, 'reason', 'taken');
  end if;
  return jsonb_build_object('available', true, 'reason', 'ok');
end;
$function$;
revoke all on function public.username_available(text) from public;
revoke all on function public.username_available(text) from anon;
grant execute on function public.username_available(text) to authenticated;

-- ═══════════ 5) device_boot: the username follows the device ═══════════
drop function if exists public.device_boot(text, text, boolean, text, text, text, text);
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
         coalesce(nullif(p_sid,''), 'DIZ-' || substring(p_hwid_hash from 1 for 16)),
         p_platform, p_app_version, now());
    exception when unique_violation then
      update public.devices
      set user_id     = v_uid,
          previous_user_id = public.devices.user_id,
          device_code = coalesce(nullif(p_device_code,''), device_code),
          sid         = coalesce(nullif(p_sid,''), sid),
          app_version = coalesce(nullif(p_app_version,''), app_version),
          hwid_stable = p_hwid_stable,
          last_seen_at = now()
      where hwid_hash = p_hwid_hash
      returning revoked_at, adult_allowed into v_revoked, v_adult;
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

-- ═══════════ 6) admin: see and repair username ownership ═══════════
create or replace function public.admin_usernames(p_search text default '', p_limit int default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_q text := lower(btrim(coalesce(p_search, '')));
begin
  perform require_role(array['owner', 'support']);
  return coalesce((
    select jsonb_agg(t) from (
      select
        u.username,
        u.user_id,
        coalesce(au.is_anonymous, false) as is_anonymous,
        (select count(*) from public.devices d where d.user_id = u.user_id) as device_count,
        (select max(d.last_seen_at) from public.devices d where d.user_id = u.user_id) as last_seen,
        (select coalesce(jsonb_agg(jsonb_build_object('device_code', d.device_code, 'platform', d.platform, 'hwid_stable', d.hwid_stable)
                  order by d.last_seen_at desc nulls last), '[]'::jsonb)
          from public.devices d where d.user_id = u.user_id) as devices
      from public.usernames u
      join auth.users au on au.id = u.user_id
      where v_q = '' or lower(u.username) like '%' || v_q || '%'
      order by u.username
      limit greatest(1, least(coalesce(p_limit, 100), 500))
    ) t
  ), '[]'::jsonb);
end;
$function$;
revoke all on function public.admin_usernames(text, int) from public;
grant execute on function public.admin_usernames(text, int) to authenticated;

create or replace function public.admin_release_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_clean text := lower(trim(coalesce(p_username, '')));
  v_owner uuid;
begin
  perform require_role(array['owner']);
  select user_id into v_owner from public.usernames where username_lower = v_clean;
  if v_owner is null then
    return jsonb_build_object('success', false, 'error', 'Username not found');
  end if;
  delete from public.usernames where user_id = v_owner;
  insert into public.identity_history(user_id, kind, old_value, new_value)
  values (v_owner, 'username', v_clean, 'released-by-admin');
  return jsonb_build_object('success', true, 'username', v_clean, 'released_from_uid', v_owner);
end;
$function$;
revoke all on function public.admin_release_username(text) from public;
grant execute on function public.admin_release_username(text) to authenticated;

create or replace function public.admin_reassign_username(p_username text, p_target_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_clean text := lower(trim(coalesce(p_username, '')));
  v_owner uuid;
begin
  perform require_role(array['owner']);
  if p_target_uid is null then
    return jsonb_build_object('success', false, 'error', 'Target user id required');
  end if;
  select user_id into v_owner from public.usernames where username_lower = v_clean;
  if v_owner is null then
    return jsonb_build_object('success', false, 'error', 'Username not found');
  end if;
  if not exists (select 1 from auth.users u where u.id = p_target_uid) then
    return jsonb_build_object('success', false, 'error', 'Target user does not exist');
  end if;
  if exists (select 1 from public.usernames where user_id = p_target_uid) then
    return jsonb_build_object('success', false, 'error', 'Target user already has a username');
  end if;
  update public.usernames set user_id = p_target_uid where user_id = v_owner;
  insert into public.identity_history(user_id, kind, old_value, new_value)
  values (p_target_uid, 'username', v_clean, v_clean);
  return jsonb_build_object('success', true, 'username', v_clean, 'previous_uid', v_owner);
end;
$function$;
revoke all on function public.admin_reassign_username(text, uuid) from public;
grant execute on function public.admin_reassign_username(text, uuid) to authenticated;
