-- Dizzy Phase N — download + usage telemetry   (2026-10-01)
-- Run ONCE: supabase db query --linked -f supabase/migrations/20261001_download_usage.sql
--
-- N adds:
--   download_counters       landing download clicks, aggregate day+source+file
--   device_activity_log     coarse activity transitions (enum only, 7-day ring)
--   github_stats_cache      one-row cache of /releases/latest (5 min TTL)
--   device_heartbeat()      also writes a transition row on a real change
--   bump_download_counter() atomic +1 (service-role only — the `dl` edge fn)
--   admin_usage_stats()     users / DAU-WAU-MAU / downloads in one call
--   admin_activity_feed()   last N transitions for the Fleet activity feed
--
-- COUNTING SEMANTICS (do not "fix" later): the landing CTAs 302 to the SAME
-- GitHub asset URL, so GitHub's download_count ALREADY includes landing
-- traffic. Landing = subset of GitHub total, GitHub-direct is derived
-- (total − landing). Never add the two as if they were independent.
--
-- Privacy: no PII, no titles/URLs — activity is an enum, counters are
-- file names only. Every new table: RLS on, zero client policies.

-- ═══════════ 1) download_counters — landing clicks ═══════════
create table if not exists public.download_counters (
  day        date not null default current_date,
  source     text not null check (source in ('landing')),
  file       text not null
             check (file ~ '^Dizzy-[A-Za-z0-9._-]+\.(apk|zip|exe|AppImage|tar\.gz)$'),
  count      bigint not null default 0,
  primary key (day, source, file)
);
alter table public.download_counters enable row level security;
-- no client policies at all: service-role (edge fn) writes, admin RPCs read.

-- ═══════════ 2) device_activity_log — transition ring buffer ═══════════
create table if not exists public.device_activity_log (
  id          bigint generated always as identity primary key,
  device_id   uuid not null references public.devices(device_id) on delete cascade,
  device_code char(7) not null,
  activity    text not null check (activity in
                ('idle','watching','listening','reading','downloading',
                 'in_room','in_voice')),
  at          timestamptz not null default now()
);
create index if not exists device_activity_log_at_idx
  on public.device_activity_log (at desc);
alter table public.device_activity_log enable row level security;
-- service-role/definer writes only; admin_activity_feed() reads.

-- ═══════════ 3) github_stats_cache — single row, id = true ═══════════
create table if not exists public.github_stats_cache (
  id         boolean primary key default true check (id),
  payload    jsonb not null default '{}'::jsonb,
  fetched_at timestamptz not null default now()
);
alter table public.github_stats_cache enable row level security;
insert into public.github_stats_cache (id) values (true) on conflict do nothing;
-- payload = {} means "never fetched yet" → admin_usage_stats reports null.

-- ═══════════ 4) device_heartbeat — now also logs transitions ═══════════
-- Identical to the Phase L version except: it captures the previous
-- activity/device_code and, when the activity REALLY changed, appends one
-- row to device_activity_log and prunes rows older than 7 days. The 60s
-- server throttle already keeps insert volume low (identical repeats are
-- dropped before we ever reach the write), so the prune is cheap.
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
  v_prev_activity text;
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

  select device_id, device_code, revoked_at, last_heartbeat_at, activity
    into v_device
    from public.devices
   where hwid_hash = p_hwid_hash
     and user_id = auth.uid()
   limit 1;

  if v_device.device_id is null then
    -- Never registered here (device_boot has not run / different user).
    return jsonb_build_object('ok', false, 'reason', 'unknown_device');
  end if;

  v_prev_activity := v_device.activity;

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

  -- Phase N: record the TRANSITION (enum + 7-char device code only — no PII,
  -- no content), then prune the 7-day ring. Presence refreshes with an
  -- unchanged activity write nothing here.
  if v_activity is distinct from v_prev_activity then
    insert into public.device_activity_log (device_id, device_code, activity)
      values (v_device.device_id, v_device.device_code, v_activity);
    delete from public.device_activity_log
     where at < now() - interval '7 days';
  end if;

  return jsonb_build_object(
    'ok', true,
    'throttled', false,
    'revoked', v_device.revoked_at is not null
  );
end;
$$;
revoke all on function public.device_heartbeat(text, text, text) from public;
grant execute on function public.device_heartbeat(text, text, text) to authenticated;

-- ═══════════ 5) bump_download_counter — atomic +1 for the dl edge fn ═══════════
-- A read-then-write in the edge fn would race; this is one statement.
-- Validated here as well as at the edge: pattern-locked file names, source
-- allowlist, and NO legacy APKs (those are the debug-key mirrors for old
-- installs and must never be offered or counted as a landing download).
create or replace function public.bump_download_counter(
  p_source text,
  p_file   text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v bigint;
begin
  if p_source is null or p_source <> 'landing' then
    raise exception 'bad source';
  end if;
  if p_file is null
     or p_file !~ '^Dizzy-[A-Za-z0-9._-]+\.(apk|zip|exe|AppImage|tar\.gz)$'
     or position('legacy' in p_file) > 0 then
    raise exception 'bad file';
  end if;

  insert into public.download_counters (day, source, file, count)
    values (current_date, p_source, p_file, 1)
  on conflict (day, source, file)
    do update set count = public.download_counters.count + 1
  returning count into v;

  return v;
end;
$$;
revoke all on function public.bump_download_counter(text, text) from public;
grant execute on function public.bump_download_counter(text, text) to service_role;

-- ═══════════ 6) admin_usage_stats — one call for the Overview tab ═══════════
-- Series note (honest limitation): `active` per past day is derived from
-- devices.last_seen_at only (there is no per-day presence history), so a
-- device shows up on the day it was LAST seen. Today's number is exact;
-- older days understate activity. DAU/WAU/MAU use the same window rule.
create or replace function public.admin_usage_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;

  select jsonb_build_object(
    'total_devices', (select count(*) from public.devices),
    -- "users" for the fleet row; Windows/Linux clients may not register
    -- (device_boot is Android-shaped) → this count is Android-skewed.
    'accounts',      (select count(*) from auth.users),
    'active_now',    (select count(*) from public.devices
                       where last_seen_at > now() - interval '10 minutes'),
    'dau',           (select count(*) from public.devices
                       where last_seen_at > now() - interval '1 day'),
    'wau',           (select count(*) from public.devices
                       where last_seen_at > now() - interval '7 days'),
    'mau',           (select count(*) from public.devices
                       where last_seen_at > now() - interval '30 days'),
    'new_today',     (select count(*) from public.devices
                       where created_at >= current_date),
    'series_30d', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', to_char(d.day, 'YYYY-MM-DD'),
               'active', d.act,
               'new', d.nw,
               'dl_landing', d.dl) order by d.day)
      from (
        select gs::date as day,
               (select count(*) from public.devices x
                 where x.last_seen_at >= gs
                   and x.last_seen_at <  gs + interval '1 day')::int as act,
               (select count(*) from public.devices x
                 where x.created_at >= gs
                   and x.created_at <  gs + interval '1 day')::int as nw,
               (select coalesce(sum(c.count), 0) from public.download_counters c
                 where c.source = 'landing' and c.day = gs::date)::int as dl
        from generate_series(
               (current_date - 29)::timestamp, current_date::timestamp,
               interval '1 day') gs
      ) d
    ), '[]'::jsonb),
    'downloads', jsonb_build_object(
      'landing_today', coalesce((
        select sum(count) from public.download_counters
         where source = 'landing' and day = current_date), 0),
      'landing_total', coalesce((
        select sum(count) from public.download_counters
         where source = 'landing'), 0),
      -- all-time split by file: which APK/zip people actually take.
      'landing_by_file', coalesce((
        select jsonb_agg(jsonb_build_object('file', b.file, 'count', b.n)
                         order by b.n desc, b.file)
        from (select file, sum(count)::bigint as n
                from public.download_counters
               where source = 'landing'
               group by file) b), '[]'::jsonb),
      -- served from the 5-min cache; the dashboard merges with the
      -- release-latest edge fn for freshness. Never fetched → null.
      'github_cached', (
        select case when g.payload ? 'tag'
                    then jsonb_build_object('tag',     g.payload->>'tag',
                                            'fetched_at', g.fetched_at)
                    else null end
          from public.github_stats_cache g
         where g.id)
    )
  ) into v;

  return v;
end;
$$;
revoke all on function public.admin_usage_stats() from public;
grant execute on function public.admin_usage_stats() to authenticated;

-- ═══════════ 7) admin_activity_feed — Fleet activity panel ═══════════
-- device_code (7-char, already visible inside the dashboard) + enum + time.
-- No hwid, no user_id, no titles — the privacy floor.
create or replace function public.admin_activity_feed(
  p_limit int default 50
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

  select coalesce(jsonb_agg(jsonb_build_object(
           'device_code', t.device_code,
           'activity',    t.activity,
           'at',          t.at) order by t.at desc), '[]'::jsonb)
    into v
  from (
    select d.device_code, l.activity, l.at
      from public.device_activity_log l
      join public.devices d on d.device_id = l.device_id
     order by l.at desc
     limit greatest(coalesce(p_limit, 50), 1)
  ) t;

  return v;
end;
$$;
revoke all on function public.admin_activity_feed(int) from public;
grant execute on function public.admin_activity_feed(int) to authenticated;
