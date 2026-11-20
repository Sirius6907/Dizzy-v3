-- Dizzy v1.4.3 — Phase 5: telemetry retention + retiring the dead `installs` table.
-- Run AFTER 20261121_admin_device_telemetry.sql:
--   supabase db query --linked -f supabase/migrations/20261121_retention_and_installs.sql
--
-- Two problems, one file, because they are the same problem: data that looks
-- collected but isn't, and data that is collected but never expires.
--
-- ── 1) `installs` has never held a single row ─────────────────────────────
-- The client upserts owner_user_id/anon_id/device_code/platform/version into
-- public.installs on every consented boot. But the live column is
-- `device_code character` — character(1), not the char(7) the migration
-- intended — so every upsert died with "value too long for type character(1)"
-- and was swallowed by a soft catch. Consequences, all live:
--   * the dashboard's Installs card, installs chart and overview counters
--     have read 0 since v1.1.9;
--   * send_room_message() resolves the sender's code from installs, so every
--     chat message has sender_code = null;
--   * party chat's member list reads installs under RLS with no SELECT
--     policy, so device codes never resolved there either.
-- devices already is the install ledger: one row per install, with the code,
-- platform, version, owner and timestamps, written by device_boot(). So the
-- five readers are repointed at devices and the empty table is dropped.
-- Installs are still counted — from the table that actually has them.
--
-- ── 2) device_logs grows forever ──────────────────────────────────────────
-- Rows fold per (device, screen, code, detail), so volume is modest, but
-- "modest" is not "bounded". device_logs_purge() rolls anything older than
-- the window into device_log_stats (day × code × screen, with hit totals)
-- and only then deletes the raw rows, so the shape of history survives the
-- purge. device_codes_prune() forgets registry codes that are old, not
-- current, and no longer referenced by any surviving log row.
--
-- Both are idempotent and safe to re-run.

-- ═══════════ 1) repoint the install readers at devices ═══════════

-- Overview counters. Keys keep their names so the panel cards keep working;
-- the numbers now come from the table that is actually written.
create or replace function public.admin_overview()
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select jsonb_build_object(
    'installs',       (select count(*) from devices),
    'installs_7d',    (select count(*) from devices where last_seen_at > now() - interval '7 days'),
    'rooms_live',     (select count(*) from rooms where status in ('lobby','live')),
    'rooms_total',    (select count(*) from rooms),
    'members_live',   (select count(*) from room_members m join rooms r on r.room_id = m.room_id where r.status in ('lobby','live')),
    'reports_pending',(select count(*) from room_reports),
    'scraper_votes_7d', (select count(*) from scraper_reports where created_at > now() - interval '7 days'),
    'announcements',  (select count(*) from announcements where active)
  ) into v;
  return v;
end;
$$;

revoke all on function public.admin_overview() from public;
grant execute on function public.admin_overview() to authenticated;

-- Daily install curve. A device row is created once per install, so
-- devices.created_at is the install date.
create or replace function public.admin_installs_daily(p_days int default 30)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(row order by row->>'d'), '[]'::jsonb) into v from (
    select jsonb_build_object('d', to_char(d, 'YYYY-MM-DD'),
      'n', (select count(*) from devices where created_at::date = d)) as row
    from (select (current_date - s) as d from generate_series(0, greatest(p_days,1)-1) s) days
  ) t;
  return v;
end;
$$;

revoke all on function public.admin_installs_daily(int) from public;
grant execute on function public.admin_installs_daily(int) to authenticated;

-- Platform / version mix.
create or replace function public.admin_breakdown()
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select jsonb_build_object(
    'platforms', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
      select platform as name, count(*) as n from devices group by platform order by n desc) t),
    'versions', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
      select app_version as name, count(*) as n from devices group by app_version order by n desc) t),
    'consents', (select jsonb_build_object(
      'telemetry', (select count(*) from consents where telemetry),
      'genre_prefs', (select count(*) from consents where genre_prefs),
      'crash', (select count(*) from consents where crash),
      'watch_party', (select count(*) from consents where watch_party),
      'total', (select count(*) from consents)))
  ) into v;
  return v;
end;
$$;

revoke all on function public.admin_breakdown() from public;
grant execute on function public.admin_breakdown() to authenticated;

-- Install history table. Same function name and signature; `anon_id` is the
-- anonymous 7-digit install code (never a hardware id), and the region
-- column is gone because devices never had one — a blank column is worse
-- than no column.
create or replace function public.admin_installs(p_limit int default 50, p_search text default '')
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare
  v jsonb;
  q text := '%' || trim(coalesce(p_search, '')) || '%';
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t order by t.last_seen_at desc), '[]'::jsonb) into v from (
    select btrim(d.device_code) as anon_id,
           d.platform,
           d.app_version,
           d.created_at,
           d.last_seen_at,
           un.username
      from devices d
      left join usernames un on un.user_id = d.user_id
     where q = '%%'
        or d.device_code ilike q
        or d.platform ilike q
        or d.app_version ilike q
        or d.device_id::text ilike q
        or un.username ilike q
     order by d.last_seen_at desc
     limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;

revoke all on function public.admin_installs(int, text) from public;
grant execute on function public.admin_installs(int, text) to authenticated;

-- Chat sender code: the newest device row this user owns. Previously read a
-- table that was always empty, so sender_code was always null.
create or replace function public.send_room_message(
  p_room_id text,
  p_body text,
  p_reply_to_id uuid default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text := trim(both from coalesce(p_body, ''));
  v_code text;
  v_sender_code char(7);
  v_parent room_messages%rowtype;
begin
  if char_length(v_body) < 1 or char_length(v_body) > 500 then
    return false;
  end if;
  select room_id into v_code from rooms
    where room_id = upper(trim(p_room_id)) and status <> 'closed';
  if not found then return false; end if;
  if not exists (
    select 1 from room_members
    where room_id = v_code and user_id = auth.uid()
  ) then
    return false;
  end if;
  -- 1 message per 2 seconds per sender.
  if exists (
    select 1 from room_messages
    where room_id = v_code and sender_id = auth.uid()
      and created_at > now() - interval '2 seconds'
  ) then
    return false;
  end if;
  -- Reply target must be a live message of THIS room.
  if p_reply_to_id is not null then
    select * into v_parent from room_messages
      where id = p_reply_to_id and room_id = v_code;
    if not found then
      p_reply_to_id := null;
    end if;
  end if;
  select device_code into v_sender_code from devices
    where user_id = auth.uid()
    order by last_seen_at desc
    limit 1;
  insert into room_messages(
    room_id, sender_id, sender_code, body,
    reply_to_id, reply_preview, reply_to_code
  )
  values (
    v_code, auth.uid(), v_sender_code, v_body,
    p_reply_to_id,
    case when v_parent.id is null then null
         else left(v_parent.body, 80) end,
    v_parent.sender_code
  );
  return true;
end;
$$;

revoke all on function public.send_room_message(text, text, uuid) from public;
grant execute on function public.send_room_message(text, text, uuid) to authenticated;

-- ═══════════ 2) retention ═══════════

-- Rolled-up history: one row per (day, code, screen). Keeps the shape of old
-- telemetry after the raw rows are gone, at a cost of one row per day per
-- code/screen rather than one per device.
create table if not exists public.device_log_stats (
  day         date        not null,
  device_code text        not null,
  code        text        not null,
  screen      text        not null,
  platform    text        not null default 'unknown',
  hits        bigint      not null default 0,
  first_at    timestamptz not null,
  last_at     timestamptz not null,
  primary key (day, device_code, code, screen)
);

create index if not exists device_log_stats_code_day_idx
  on public.device_log_stats (code, day desc);

alter table public.device_log_stats enable row level security;

revoke all on public.device_log_stats from anon, authenticated;
grant select on public.device_log_stats to authenticated;

drop policy if exists "admins read device log stats" on public.device_log_stats;
create policy "admins read device log stats" on public.device_log_stats
  for select to authenticated using (is_admin());

-- Purge raw telemetry older than p_days, rolling it into device_log_stats
-- first. p_days is floored at 30: a maintenance typo must not delete the
-- week the support team is investigating.
create or replace function public.device_logs_purge(
  p_days int default 90,
  p_dry_run boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days int := greatest(coalesce(p_days, 90), 30);
  v_cutoff timestamptz := now() - make_interval(days => v_days);
  v_rows bigint := 0;
  v_hits bigint := 0;
  v_deleted bigint := 0;
begin
  select count(*), coalesce(sum(l.count), 0)
    into v_rows, v_hits
    from public.device_logs l
   where l.last_at < v_cutoff;

  if p_dry_run then
    return jsonb_build_object(
      'dry_run', true, 'days', v_days, 'cutoff', v_cutoff,
      'would_roll_rows', v_rows, 'would_roll_hits', v_hits);
  end if;

  insert into public.device_log_stats as s
    (day, device_code, code, screen, platform, hits, first_at, last_at)
  select l.last_at::date, l.device_code, l.code, l.screen,
         max(l.platform), sum(l.count), min(l.first_at), max(l.last_at)
    from public.device_logs l
   where l.last_at < v_cutoff
   group by l.last_at::date, l.device_code, l.code, l.screen
  on conflict (day, device_code, code, screen) do update
    set hits     = s.hits + excluded.hits,
        first_at = least(s.first_at, excluded.first_at),
        last_at  = greatest(s.last_at, excluded.last_at),
        platform = excluded.platform;

  delete from public.device_logs l where l.last_at < v_cutoff;
  get diagnostics v_deleted = row_count;

  return jsonb_build_object(
    'dry_run', false, 'days', v_days, 'cutoff', v_cutoff,
    'rolled_rows', v_rows, 'rolled_hits', v_hits, 'deleted_rows', v_deleted);
end;
$$;

revoke all on function public.device_logs_purge(int, boolean) from public, anon, authenticated;
grant execute on function public.device_logs_purge(int, boolean) to service_role;

comment on function public.device_logs_purge(int, boolean) is
  'Roll raw device_logs older than p_days into device_log_stats, then delete them. p_days floors at 30.';

-- Forget registry codes that are old, not the device's current code, and not
-- referenced by any surviving telemetry. A code still worn or still carrying
-- logs is never pruned.
create or replace function public.device_codes_prune(p_days int default 180)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days int := greatest(coalesce(p_days, 180), 90);
  v_cutoff timestamptz := now() - make_interval(days => v_days);
  v_deleted bigint := 0;
begin
  delete from public.device_codes dc
   where dc.last_seen_at < v_cutoff
     and not exists (select 1 from public.devices d
                      where btrim(d.device_code) = dc.code)
     and not exists (select 1 from public.device_logs l
                      where l.device_code = dc.code);
  get diagnostics v_deleted = row_count;

  return jsonb_build_object(
    'days', v_days, 'cutoff', v_cutoff, 'deleted_codes', v_deleted);
end;
$$;

revoke all on function public.device_codes_prune(int) from public, anon, authenticated;
grant execute on function public.device_codes_prune(int) to service_role;

comment on function public.device_codes_prune(int) is
  'Drop registry codes older than p_days that are neither current nor referenced by surviving telemetry.';

-- Nightly at 03:20 UTC (08:50 IST) — after the corpus sweeps, before the
-- morning support shift. Guarded: a database without pg_cron still gets the
-- functions and can run them from the SQL editor.
do $$
declare v_job bigint;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    for v_job in select jobid from cron.job where jobname = 'dizzy-telemetry-retention' loop
      perform cron.unschedule(v_job);
    end loop;
    perform cron.schedule(
      'dizzy-telemetry-retention',
      '20 3 * * *',
      $job$select public.device_logs_purge(90, false), public.device_codes_prune(180);$job$
    );
  else
    raise notice 'pg_cron absent: run device_logs_purge(90) and device_codes_prune(180) manually';
  end if;
end;
$$;

-- ═══════════ 3) drop the dead table ═══════════
-- Only when it is genuinely empty and nothing still reads it. If a future
-- migration reintroduces a dependency, the table simply stays and this block
-- prints why instead of failing the file.
do $$
declare v_refs int;
begin
  if to_regclass('public.installs') is null then
    return;
  end if;
  select count(*) into v_refs
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosrc ~* '\m(from|join|into|table)\s+installs\M';
  if v_refs > 0 then
    raise notice 'installs kept: % function(s) still reference it', v_refs;
    return;
  end if;
  if exists (select 1 from public.installs limit 1) then
    raise notice 'installs kept: table is not empty';
    return;
  end if;
  drop table public.installs;
  raise notice 'dropped empty legacy installs table';
end;
$$;
