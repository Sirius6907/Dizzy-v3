-- WP-P5: hardening (locked spec 2026-09-09).
-- 1) consents.watch_party (4th toggle, default OFF like the rest).
-- 2) room_members.last_seen + touch_membership RPC (presence prune input).
-- 3) 20-member cap enforced in join_watch_room (server-side, unbypassable).
-- 4) sweep_stale_rooms RPC: closes 0-member rooms older than 30 min and
--    any room older than 12h (marathon-safe). Clients call it after
--    create/join; the lobby view also hides rotting rooms.
-- 5) Safe view rebuild: same 8 columns + hide 0-member rooms older than 30m.
-- Run ONCE in Supabase SQL Editor after 20260909_wp_p4_chat.sql.
alter table consents
  add column if not exists watch_party boolean not null default false;

alter table room_members
  add column if not exists last_seen timestamptz not null default now();

create or replace function touch_membership(p_room_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update room_members set last_seen = now()
    where room_id = upper(trim(p_room_id)) and user_id = auth.uid();
  return found;
end;
$$;
revoke all on function touch_membership(text) from public;
grant execute on function touch_membership(text) to authenticated;

create or replace function join_watch_room(
  p_room_id text,
  p_pass_hash text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  r rooms%rowtype;
  v_member boolean;
  v_count int;
begin
  select * into r from rooms where room_id = upper(trim(p_room_id));
  if not found or r.status = 'closed' then return false; end if;
  if r.visibility = 'private' and
     (p_pass_hash is null or p_pass_hash <> r.pass_hash) then
    return false;
  end if;
  select exists (
    select 1 from room_members
    where room_id = r.room_id and user_id = auth.uid()
  ) into v_member;
  if r.locked and auth.uid() <> r.host_user_id and not v_member then
    return false;
  end if;
  -- 20-member cap (v1 room size). Rejoining members always pass.
  if not v_member then
    select count(*) into v_count from room_members where room_id = r.room_id;
    if v_count >= 20 then return false; end if;
  end if;
  insert into room_members(room_id, user_id, role, last_seen)
    values (r.room_id, auth.uid(), case when auth.uid() = r.host_user_id then 'host' else 'member' end, now())
    on conflict (room_id, user_id) do update set last_seen = now();
  return true;
end;
$$;
revoke all on function join_watch_room(text, text) from public;
grant execute on function join_watch_room(text, text) to authenticated;

create or replace function sweep_stale_rooms()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_closed int := 0;
begin
  -- Empty rooms rotting over 30 minutes.
  with gone as (
    update rooms r set status = 'closed'
    where r.status <> 'closed'
      and r.created_at < now() - interval '30 minutes'
      and not exists (
        select 1 from room_members m where m.room_id = r.room_id
      )
    returning 1
  )
  select count(*) into v_closed from gone;
  -- Marathon cap: nothing lives past 12h (chat wipe trigger fires on close).
  with old as (
    update rooms set status = 'closed'
    where status <> 'closed'
      and created_at < now() - interval '12 hours'
    returning 1
  )
  select v_closed + count(*) into v_closed from old;
  return v_closed;
end;
$$;
revoke all on function sweep_stale_rooms() from public;
grant execute on function sweep_stale_rooms() to authenticated;

-- Same 8 columns, plus rot-hiding. DROP+CREATE (proven pattern here).
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
  and (select count(*) from room_reports rep where rep.room_id = r.room_id) < 3
  and not (
    r.created_at < now() - interval '30 minutes'
    and not exists (
      select 1 from room_members m where m.room_id = r.room_id
    )
  );

grant select on public_rooms_safe to authenticated;
