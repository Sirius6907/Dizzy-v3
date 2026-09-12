-- v1.2.0 P5: room safety — 20-member cap, host-leave promotion, auto-close.
-- Defensive: works whether tables were made by migrations or dashboard.

alter table public.room_members
  add column if not exists joined_at timestamptz default now();

-- Backfill ordering for old rows (creation order approximates join order).
update public.room_members set joined_at = now() where joined_at is null;

-- 1) Cap: rooms hold max 20 members (host included).
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
  n int;
begin
  select * into r from rooms where room_id = upper(trim(p_room_id));
  if not found or r.status = 'closed' then return false; end if;
  if r.visibility = 'private' and
     (p_pass_hash is null or p_pass_hash <> r.pass_hash) then
    return false;
  end if;
  select count(*) into n from room_members where room_id = r.room_id;
  if n >= 20 then return false; end if; -- P5: room is full
  insert into room_members(room_id, user_id, role)
    values (r.room_id, auth.uid(), case when auth.uid() = r.host_user_id then 'host' else 'member' end)
    on conflict (room_id, user_id) do nothing;
  return true;
end;
$$;

-- 2) Leave with promotion: host leaves (not closes) → oldest member becomes
-- host. Last one out closes the room (lobby sweep hides it).
create or replace function leave_watch_room(p_room_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  code text := upper(trim(p_room_id));
  was_host boolean;
  next_host uuid;
begin
  select (host_user_id = auth.uid()) into was_host
    from rooms where room_id = code;
  delete from room_members where room_id = code and user_id = auth.uid();
  if not exists (select 1 from room_members where room_id = code) then
    update rooms set status = 'closed' where room_id = code;
    return true;
  end if;
  if coalesce(was_host, false) then
    select user_id into next_host from room_members
      where room_id = code order by joined_at nulls last, ctid limit 1;
    if next_host is not null then
      update rooms set host_user_id = next_host where room_id = code;
      update room_members set role = 'host'
        where room_id = code and user_id = next_host;
    end if;
  end if;
  return true;
end;
$$;

revoke all on function leave_watch_room(text) from public;
grant execute on function leave_watch_room(text) to authenticated;
