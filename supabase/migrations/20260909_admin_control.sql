-- Dizzy Admin Control — backend migration (v1.2.0-ADMIN).
-- Run ONCE in Supabase SQL Editor AFTER all existing migrations
-- (latest: 20260909_wp_p5_hardening.sql).
--
-- Adds:
--  1) admins table (email allowlist; is_admin() helper)
--  2) remote_config KV (app reads: scraper kills, feature flags, notices)
--  3) announcements (in-app banner feed)
--  4) scraper_reports (crowdsourced dead-scraper votes from app)
--  5) admin_audit (every admin write, who+what+when)
--  6) admin_* RPCs (dashboard reads/writes; SECURITY DEFINER + is_admin gate)
--  7) rooms.admin_notes (mod note column)
--  8) room_reports admin read policy (admins see all reports)
--  9) public_rooms_safe rebuild (keep P5 shape; security_invoker)
--
-- Privacy: no PII anywhere. Admin sees device codes + counts, never emails.

-- ═══════════ 1) admins ═══════════
create table if not exists admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);
alter table admins enable row level security;

drop policy if exists "admins self-read" on admins;
create policy "admins self-read" on admins
  for select to authenticated using (auth.uid() = user_id);

create or replace function is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select exists (select 1 from admins where user_id = auth.uid()); $$;
revoke all on function is_admin() from public;
grant execute on function is_admin() to anon, authenticated;

-- ═══════════ 2) remote_config ═══════════
-- key/value store the app polls on startup (cheap, cached 1h client-side).
-- Reserved keys:
--   min_app_version        text  e.g. "1.2.0"  (below => force-update banner)
--   scraper_kill           json  e.g. {"vidfast": "dead site", "vidgod": "dead site"}
--   scraper_cooldown_days  int-as-text, default "7"
--   features               json  e.g. {"watch_party": true, "voice": true}
--   notice                 json  e.g. {"text": "...", "until": "2026-10-01"}
create table if not exists remote_config (
  key text primary key,
  value text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
alter table remote_config enable row level security;

drop policy if exists "anyone reads config" on remote_config;
create policy "anyone reads config" on remote_config
  for select to anon, authenticated using (true);

insert into remote_config(key, value) values
  ('min_app_version', '1.1.9'),
  ('scraper_kill', '{}'),
  ('scraper_cooldown_days', '7'),
  ('features', '{"watch_party": true, "voice": true}'),
  ('notice', '{}')
on conflict (key) do nothing;

-- ═══════════ 3) announcements ═══════════
create table if not exists announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  body text not null default '',
  url text,
  min_version text not null default '',
  max_version text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table announcements enable row level security;

drop policy if exists "anyone reads announcements" on announcements;
create policy "anyone reads announcements" on announcements
  for select to anon, authenticated using (true);

-- ═══════════ 4) scraper_reports (crowdsourced) ═══════════
-- App inserts {scraper, kind} when a scraper yields 0 sources repeatedly.
-- 5+ distinct reporters in 7d => dashboard flags it as likely-dead.
create table if not exists scraper_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  scraper text not null,
  kind text not null default 'empty' check (kind in ('empty','error','slow')),
  app_version text not null default '',
  created_at timestamptz not null default now()
);
alter table scraper_reports enable row level security;

drop policy if exists "anyone inserts scraper report" on scraper_reports;
create policy "anyone inserts scraper report" on scraper_reports
  for insert to anon, authenticated with check (true);

-- ═══════════ 5) admin_audit ═══════════
create table if not exists admin_audit (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid references auth.users(id) on delete set null,
  action text not null,
  target text not null default '',
  detail jsonb not null default '{}',
  created_at timestamptz not null default now()
);
alter table admin_audit enable row level security;
-- No direct client access at all; RPC-only (service role bypasses RLS anyway).

-- ═══════════ 6) rooms.admin_notes ═══════════
alter table rooms add column if not exists admin_notes text not null default '';

-- ═══════════ 7) room_reports: admins read all ═══════════
drop policy if exists "admin read all reports" on room_reports;
create policy "admin read all reports" on room_reports
  for select to authenticated using (is_admin());

-- ═══════════ 8) ADMIN RPCs ═══════════

-- Overview counters for the dashboard header.
create or replace function admin_overview()
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
    'installs',       (select count(*) from installs),
    'installs_7d',    (select count(*) from installs where last_seen_at > now() - interval '7 days'),
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
revoke all on function admin_overview() from public;
grant execute on function admin_overview() to authenticated;

-- Daily installs for the last N days (chart).
create or replace function admin_installs_daily(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(row ORDER BY row->>'d'), '[]'::jsonb) into v from (
    select jsonb_build_object('d', to_char(d, 'YYYY-MM-DD'),
      'n', (select count(*) from installs where created_at::date = d)) as row
    from (select (current_date - s) as d from generate_series(0, greatest(p_days,1)-1) s) days
  ) t;
  return v;
end;
$$;
revoke all on function admin_installs_daily(int) from public;
grant execute on function admin_installs_daily(int) to authenticated;

-- Live rooms with member counts + report counts + host device code.
create or replace function admin_rooms(p_limit int default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t ORDER BY t.created_at DESC), '[]'::jsonb) into v from (
    select r.room_id, r.title, r.visibility, r.status, r.media_ref, r.is_adult,
           r.locked, r.admin_notes, r.created_at,
           (select count(*) from room_members m where m.room_id = r.room_id) as members,
           (select count(*) from room_reports rr where rr.room_id = r.room_id) as reports
    from rooms r
    order by r.created_at desc
    limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;
revoke all on function admin_rooms(int) from public;
grant execute on function admin_rooms(int) to authenticated;

-- Room detail: members + recent chat + reports.
create or replace function admin_room_detail(p_room_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb; v_id text := upper(trim(p_room_id));
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select jsonb_build_object(
    'room', (select to_jsonb(r) from rooms r where r.room_id = v_id),
    'members', (select coalesce(jsonb_agg(m ORDER BY m.joined_at), '[]'::jsonb)
                  from room_members m where m.room_id = v_id),
    'chat', (select coalesce(jsonb_agg(c ORDER BY c.created_at DESC), '[]'::jsonb)
               from (select * from room_messages where room_id = v_id
                     order by created_at desc limit 50) c),
    'reports', (select count(*) from room_reports where room_id = v_id)
  ) into v;
  return v;
end;
$$;
revoke all on function admin_room_detail(text) from public;
grant execute on function admin_room_detail(text) to authenticated;

-- Moderate a room: close | lock | unlock | adult | not_adult | note.
create or replace function admin_room_action(p_room_id text, p_action text, p_note text default '')
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_id text := upper(trim(p_room_id)); v_me uuid := auth.uid();
begin
  if not is_admin() then raise exception 'admin only'; end if;
  case p_action
    when 'close'     then update rooms set status='closed' where room_id=v_id;
    when 'lock'      then update rooms set locked=true where room_id=v_id;
    when 'unlock'    then update rooms set locked=false where room_id=v_id;
    when 'adult'     then update rooms set is_adult=true where room_id=v_id;
    when 'not_adult' then update rooms set is_adult=false where room_id=v_id;
    when 'note'      then update rooms set admin_notes=left(coalesce(p_note,''),500) where room_id=v_id;
    else raise exception 'bad action';
  end case;
  insert into admin_audit(admin_id, action, target, detail)
    values (v_me, 'room:'||p_action, v_id, jsonb_build_object('note', left(coalesce(p_note,''),500)));
  return found;
end;
$$;
revoke all on function admin_room_action(text, text, text) from public;
grant execute on function admin_room_action(text, text, text) to authenticated;

-- Dismiss all reports for a room (after handling).
create or replace function admin_clear_reports(p_room_id text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_id text := upper(trim(p_room_id)); v_n int := 0;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  delete from room_reports where room_id = v_id;
  get diagnostics v_n = row_count;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'room:clear_reports', v_id, jsonb_build_object('cleared', v_n));
  return v_n;
end;
$$;
revoke all on function admin_clear_reports(text) from public;
grant execute on function admin_clear_reports(text) to authenticated;

-- Scraper votes: per-scraper counts last 7d + remote kill map passthrough.
create or replace function admin_scraper_votes()
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
    'votes', (select coalesce(jsonb_agg(t ORDER BY t.n DESC), '[]'::jsonb) from (
      select scraper, count(*) as n,
             count(distinct reporter_id) as reporters,
             max(created_at) as last_seen
      from scraper_reports where created_at > now() - interval '7 days'
      group by scraper) t),
    'kill', (select value from remote_config where key='scraper_kill')
  ) into v;
  return v;
end;
$$;
revoke all on function admin_scraper_votes() from public;
grant execute on function admin_scraper_votes() to authenticated;

-- Set a remote_config key (audited).
create or replace function admin_set_config(p_key text, p_value text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if p_key not in ('min_app_version','scraper_kill','scraper_cooldown_days','features','notice') then
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

-- Announcements CRUD (audited).
create or replace function admin_announce_upsert(
  p_id text, p_title text, p_body text, p_url text,
  p_min_version text, p_max_version text, p_active boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if nullif(p_id,'') is null then
    insert into announcements(title, body, url, min_version, max_version, active)
      values (p_title, p_body, nullif(p_url,''), p_min_version, p_max_version, p_active)
      returning id into v_id;
  else
    v_id := p_id::uuid;
    update announcements set title=p_title, body=p_body, url=nullif(p_url,''),
      min_version=p_min_version, max_version=p_max_version, active=p_active
      where id = v_id;
  end if;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'announce:upsert', v_id::text,
            jsonb_build_object('title', left(p_title,200), 'active', p_active));
  return v_id::text;
end;
$$;
revoke all on function admin_announce_upsert(text, text, text, text, text, text, boolean) from public;
grant execute on function admin_announce_upsert(text, text, text, text, text, text, boolean) to authenticated;

create or replace function admin_announce_delete(p_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  delete from announcements where id = p_id::uuid;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'announce:delete', p_id, '{}');
  return found;
end;
$$;
revoke all on function admin_announce_delete(text) from public;
grant execute on function admin_announce_delete(text) to authenticated;

-- Audit tail.
create or replace function admin_audit_tail(p_limit int default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t ORDER BY t.created_at DESC), '[]'::jsonb) into v from (
    select * from admin_audit order by created_at desc limit greatest(p_limit,1)) t;
  return v;
end;
$$;
revoke all on function admin_audit_tail(int) from public;
grant execute on function admin_audit_tail(int) to authenticated;

-- ═══════════ 9) keep safe view on P5 shape ═══════════
drop view if exists public_rooms_safe;
create view public_rooms_safe
with (security_invoker = true)
as
select
  r.room_id,
  r.title,
  r.media_ref,
  r.status,
  r.created_at,
  r.is_adult,
  (select count(*)::int from room_members m where m.room_id = r.room_id)
    as member_count
from rooms r
where r.visibility = 'public'
  and r.status in ('lobby', 'live')
  and not ( -- 3+ reports auto-hide
    (select count(*) from room_reports rr where rr.room_id = r.room_id) >= 3)
  and not ( -- rot filter: 0-member rooms older than 30m
    (select count(*) from room_members m where m.room_id = r.room_id) = 0
    and r.created_at < now() - interval '30 minutes');

grant select on public_rooms_safe to anon, authenticated;
