-- WP-P4: room chat + moderation (locked spec 2026-09-09).
-- 1) room_messages (500 chars, members-only, 24h TTL via close-trigger).
-- 2) send_room_message RPC: membership + length + 1msg/2s rate-limit, server-side.
-- 3) rooms.locked + join gate (locked: host + existing members only).
-- 4) Host can remove members (kick). Close wipes chat (TTL).
-- Run ONCE in Supabase SQL Editor after 20260909_wp_p1b_adult_filter.sql.
create table if not exists room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id text not null references rooms(room_id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_code char(7),
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table room_messages enable row level security;

-- Reads: members + host of the room only. No direct inserts
-- (writes go through send_room_message).
drop policy if exists "member read room chat" on room_messages;
create policy "member read room chat" on room_messages
  for select to authenticated
  using (
    exists (
      select 1 from room_members m
      where m.room_id = room_messages.room_id and m.user_id = auth.uid()
    )
    or exists (
      select 1 from rooms r
      where r.room_id = room_messages.room_id and r.host_user_id = auth.uid()
    )
  );
drop policy if exists "host delete room chat" on room_messages;
create policy "host delete room chat" on room_messages
  for delete to authenticated
  using (
    exists (
      select 1 from rooms r
      where r.room_id = room_messages.room_id and r.host_user_id = auth.uid()
    )
  );

create or replace function send_room_message(
  p_room_id text,
  p_body text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text := trim(both from coalesce(p_body, ''));
  v_code text;
  v_sender_code char(7);
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
  select device_code into v_sender_code from installs
    where owner_user_id = auth.uid();
  insert into room_messages(room_id, sender_id, sender_code, body)
    values (v_code, auth.uid(), v_sender_code, v_body);
  return true;
end;
$$;
revoke all on function send_room_message(text, text) from public;
grant execute on function send_room_message(text, text) to authenticated;

-- Lock flag: locked rooms admit host + existing members only.
alter table rooms
  add column if not exists locked boolean not null default false;

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
  insert into room_members(room_id, user_id, role)
    values (r.room_id, auth.uid(), case when auth.uid() = r.host_user_id then 'host' else 'member' end)
    on conflict (room_id, user_id) do nothing;
  return true;
end;
$$;
revoke all on function join_watch_room(text, text) from public;
grant execute on function join_watch_room(text, text) to authenticated;

-- Host kick: delete another member's membership.
drop policy if exists "host removes members" on room_members;
create policy "host removes members" on room_members
  for delete to authenticated
  using (
    auth.uid() = user_id
    or exists (
      select 1 from rooms r
      where r.room_id = room_members.room_id
        and r.host_user_id = auth.uid()
    )
  );

-- TTL: closing a room wipes its chat (24h conceptual TTL; rooms are
-- ephemeral and closed rooms vanish from the lobby immediately).
create or replace function wipe_room_chat_on_close()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'closed' and old.status <> 'closed' then
    delete from room_messages where room_id = new.room_id;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_wipe_room_chat_on_close on rooms;
create trigger trg_wipe_room_chat_on_close
  after update of status on rooms
  for each row execute function wipe_room_chat_on_close();
