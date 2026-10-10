-- 18+ Heaven: per-device admin kill-switch for the adult section.
-- Run ONCE: supabase db query --linked -f supabase/migrations/20261010_adult_section_flag.sql
--
-- Design (locked 2026-10-10):
--   devices.adult_allowed (default FALSE) — admin flips per device.
--   device_boot returns adult_allowed alongside revoked (fail-closed: any
--     fault keeps the section hidden; offline uses last-known value).
--   admin_devices exposes adult_allowed; admin_device_adult flips + audits.
--   Follows the revoke pattern (20261001_admin_device_control.sql).

alter table public.devices
  add column if not exists adult_allowed boolean not null default false;

-- 1) device_boot: return adult_allowed (drop + recreate: return shape changes).
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
    where device_id = v_row.device_id
    returning * into v_row;
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
         p_platform, p_app_version, now())
      returning * into v_row;
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
      returning * into v_row;
    end;
  end if;

  v_revoked := coalesce(v_row.revoked_at is not null, false);

  return jsonb_build_object(
    'success', true,
    'revoked', v_revoked,
    'merged', v_merged,
    'adult_allowed', coalesce(v_row.adult_allowed, false));
end;
$$;
revoke all on function public.device_boot(text, text, boolean, text, text, text, text) from public;
grant execute on function public.device_boot(text, text, boolean, text, text, text, text)
  to authenticated;

-- 2) admin_devices: expose adult_allowed in the fleet list.
create or replace function public.admin_devices(
  p_limit int default 100,
  p_search text default ''
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t ORDER BY t.last_seen_at desc nulls last), '[]'::jsonb)
  into v
  from (
    select d.device_id, d.device_code, d.platform, d.app_version,
           d.last_seen_at, d.revoked_at, d.created_at,
           d.hwid_stable,
           d.adult_allowed,
           (d.last_seen_at > now() - interval '10 minutes') as online,
           (b.user_id is not null) as banned,
           b.level as ban_level
    from public.devices d
    left join public.user_bans b
      on b.user_id = d.user_id
     and (b.banned_until is null or b.banned_until > now())
    where (p_search = ''
           or d.device_code ilike '%' || p_search || '%'
           or d.platform ilike '%' || p_search || '%'
           or d.app_version ilike '%' || p_search || '%')
    order by d.last_seen_at desc nulls last
    limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;
revoke all on function public.admin_devices(int, text) from public;
grant execute on function public.admin_devices(int, text) to authenticated;

-- 3) admin_device_adult — audited allow/block, mirrors admin_device_revoke.
create or replace function public.admin_device_adult(
  p_device_id uuid,
  p_allow boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not is_admin() then raise exception 'admin only'; end if;

  update public.devices
  set adult_allowed = p_allow
  where device_id = p_device_id
  returning device_code into v_code;

  if not found then
    raise exception 'device not found';
  end if;

  insert into public.admin_audit(admin_id, action, target, detail)
  values (auth.uid(),
          case when p_allow then 'device:adult_allow' else 'device:adult_block' end,
          v_code,
          jsonb_build_object('device_id', p_device_id));
  return true;
end;
$$;
revoke all on function public.admin_device_adult(uuid, boolean) from public;
grant execute on function public.admin_device_adult(uuid, boolean) to authenticated;
