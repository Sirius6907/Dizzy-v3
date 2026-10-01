-- Dizzy Phase L1 — fleet heartbeat + live fleet view   (2026-10-01)
-- Run ONCE: supabase db query --linked -f supabase/migrations/20261001_heartbeat_fleet.sql
--
-- L1 adds:
--   devices.activity       idle|watching|listening|reading|downloading
--                          |in_room|in_voice   (what the fleet is doing NOW)
--   device_heartbeat()     app → server, 60s SERVER-side throttle so a
--                          chatty client cannot be a write faucet
--   admin_fleet_live()     one call for the dashboard: online / version
--                          histogram / activity histogram / banned+revoked
--   heartbeat_interval_s   client cadence (default 300 = 5 min), admin-tunable
--
-- Privacy: nothing here collects content — only coarse activity, version and
-- presence. The client may opt out (consent OFF): it then stops heartbeating
-- and only the boot-time last_seen_at ages, which is the designed degrade.

-- ═══════════ 1) devices: activity + heartbeat bookkeeping ═══════════
alter table public.devices
  add column if not exists activity text not null default 'idle';
alter table public.devices
  add column if not exists last_heartbeat_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'devices_activity_check'
  ) then
    alter table public.devices
      add constraint devices_activity_check
      check (activity in ('idle','watching','listening','reading',
                          'downloading','in_room','in_voice'));
  end if;
end $$;

create index if not exists devices_last_seen_idx
  on public.devices (last_seen_at desc);
create index if not exists devices_user_idx
  on public.devices (user_id);

-- ═══════════ 2) device_heartbeat — throttled presence + activity ═══════════
-- Identify the row the same way device_boot does: this caller's hwid_hash,
-- scoped to the signed-in user. Anything unexpected returns a JSON "no" and
-- never raises — a heartbeat must not be able to break the app.
create or replace function public.device_heartbeat(
  p_hwid_hash  text,
  p_activity   text default 'idle',
  p_app_version text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device record;
  v_activity text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;

  if p_hwid_hash is null or length(p_hwid_hash) < 8 then
    return jsonb_build_object('ok', false, 'reason', 'bad_hwid');
  end if;

  -- Unknown activity is normalised, never rejected: an old client sending a
  -- value we retired still keeps its presence alive.
  if p_activity in ('idle','watching','listening','reading',
                    'downloading','in_room','in_voice') then
    v_activity := p_activity;
  else
    v_activity := 'idle';
  end if;

  select device_id, revoked_at, last_heartbeat_at
    into v_device
    from public.devices
   where hwid_hash = p_hwid_hash
     and user_id = auth.uid()
   limit 1;

  if v_device.device_id is null then
    -- Never registered here (device_boot has not run / different user).
    return jsonb_build_object('ok', false, 'reason', 'unknown_device');
  end if;

  -- 60s server-side throttle, but ONLY for a no-op refresh. A real activity
  -- change (user opened a video, joined voice) must land immediately or the
  -- dashboard would show stale state; identical repeats are dropped so a
  -- chatty client still cannot turn this into a write faucet.
  if v_device.last_heartbeat_at is not null
     and v_device.last_heartbeat_at > now() - interval '60 seconds'
     and v_activity = (
       select activity from public.devices where device_id = v_device.device_id
     ) then
    return jsonb_build_object(
      'ok', true,
      'throttled', true,
      'revoked', v_device.revoked_at is not null
    );
  end if;

  update public.devices
     set last_seen_at = now(),
         last_heartbeat_at = now(),
         activity = v_activity,
         app_version = case
           when p_app_version is not null and length(p_app_version) between 1 and 40
             then p_app_version
           else app_version
         end
   where device_id = v_device.device_id;

  return jsonb_build_object(
    'ok', true,
    'throttled', false,
    'revoked', v_device.revoked_at is not null
  );
end;
$$;
revoke all on function public.device_heartbeat(text, text, text) from public;
grant execute on function public.device_heartbeat(text, text, text) to authenticated;

-- ═══════════ 3) admin_fleet_live — one call for the dashboard ═══════════
create or replace function public.admin_fleet_live()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;

  select jsonb_build_object(
    'generated_at', now(),
    'total',        count(*) filter (where true),
    'online',       count(*) filter (
                      where d.last_seen_at > now() - interval '10 minutes'),
    'revoked',      count(*) filter (where d.revoked_at is not null),
    'banned',       count(*) filter (
                      where b.user_id is not null
                        and (b.banned_until is null or b.banned_until > now())),
    'with_activity', count(*) filter (
                      where d.last_seen_at > now() - interval '10 minutes'
                        and d.activity <> 'idle'),
    'activity', coalesce((
      select jsonb_agg(x ORDER BY x.cnt desc)
      from (
        select d2.activity as key, count(*)::int as cnt
          from public.devices d2
         where d2.last_seen_at > now() - interval '10 minutes'
         group by d2.activity
      ) x (key, cnt)
    ), '[]'::jsonb),
    'versions', coalesce((
      select jsonb_agg(v2 ORDER BY v2.cnt desc, v2.key)
      from (
        select d2.app_version as key, count(*)::int as cnt
          from public.devices d2
         group by d2.app_version
      ) v2 (key, cnt)
    ), '[]'::jsonb),
    'platforms', coalesce((
      select jsonb_agg(p2 ORDER BY p2.cnt desc)
      from (
        select d2.platform as key, count(*)::int as cnt
          from public.devices d2
         group by d2.platform
      ) p2 (key, cnt)
    ), '[]'::jsonb)
  )
  into v
  from public.devices d
  left join public.user_bans b
    on b.user_id = d.user_id
   and (b.banned_until is null or b.banned_until > now());

  return v;
end;
$$;
revoke all on function public.admin_fleet_live() from public;
grant execute on function public.admin_fleet_live() to authenticated;

-- ═══════════ 4) admin_devices now carries activity + presence ═══════════
-- Same shape as before (Phase C), plus what the device is doing so the
-- Devices view can show a presence dot with a label.
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
           d.hwid_stable, d.activity, d.last_heartbeat_at,
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

-- ═══════════ 5) heartbeat_interval_s — client cadence, admin-tunable ═══════════
create or replace function admin_set_config(p_key text, p_value text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if p_key not in (
    'min_app_version','scraper_kill','scraper_cooldown_days',
    'features','notice','force_after','rollout_percent','update_channel',
    'heartbeat_interval_s'
  ) then
    raise exception 'bad key';
  end if;
  insert into remote_config(key, value, updated_at, updated_by)
    values (p_key, p_value, now(), auth.uid())
    on conflict (key) do update set value=excluded.value, updated_at=now(), updated_by=auth.uid();
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'config:set', p_key, jsonb_build_object('value', left(p_value, 2000)));
  return true;
end;
$$;
revoke all on function admin_set_config(text, text) from public;
grant execute on function admin_set_config(text, text) to authenticated;

insert into remote_config(key, value, updated_at, updated_by)
  values ('heartbeat_interval_s', '300', now(), null)
  on conflict (key) do nothing;
