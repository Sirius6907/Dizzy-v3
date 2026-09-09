-- WP-P1b: 18+ filter pipeline (locked spec 2026-09-09).
-- 1) rooms.is_adult stored at create (TMDB flag + keywords + host declare).
-- 2) room_reports with 3-report auto-hide enforced inside the safe view.
-- 3) Safe view exposes is_adult so clients can default-exclude adult.
-- Run ONCE in Supabase SQL Editor after 20260909_wp_p1_safe_view.sql.
alter table rooms
  add column if not exists is_adult boolean not null default false;

create table if not exists room_reports (
  room_id text not null references rooms(room_id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (room_id, reporter_id)
);
alter table room_reports enable row level security;
drop policy if exists "reporter insert own report" on room_reports;
create policy "reporter insert own report" on room_reports
  for insert to authenticated with check (auth.uid() = reporter_id);
drop policy if exists "reporter read own reports" on room_reports;
create policy "reporter read own reports" on room_reports
  for select to authenticated using (auth.uid() = reporter_id);

-- Rebuild safe view: same leak-proof columns + is_adult, auto-hides
-- rooms with 3+ reports (server-side, clients cannot bypass).
-- DROP+CREATE (not OR REPLACE): Postgres forbids reordering/inserting
-- view columns mid-list via OR REPLACE (error 42P16).
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
  (select count(*)::int from room_members m where m.room_id = r.room_id)
    as member_count,
  r.is_adult,
  (select count(*)::int from room_reports rep where rep.room_id = r.room_id)
    as report_count
from rooms r
where r.visibility = 'public'
  and r.status in ('lobby', 'live')
  and (select count(*) from room_reports rep where rep.room_id = r.room_id) < 3;

grant select on public_rooms_safe to authenticated;
