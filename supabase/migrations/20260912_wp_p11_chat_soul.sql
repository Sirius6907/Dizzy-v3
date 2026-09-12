-- WP-P11: chat soul — replies, reactions, host pin (locked spec 2026-09-12).
-- Run ONCE in Supabase SQL Editor after 20260912_wp_p5_safety.sql.
--
-- Ephemeral like all chat: close wipes messages AND clears the pin.
-- RLS UNCHANGED: same member-read / host-delete policies cover the new
-- columns (no new policies needed). Writes go through RPCs (membership +
-- host checks server-side, same as send_room_message).

-- 1) Reply link + denormalized quote preview (no N+1 on the live stream).
alter table room_messages
  add column if not exists reply_to_id uuid
    references room_messages(id) on delete set null;
alter table room_messages
  add column if not exists reply_preview text;
alter table room_messages
  add column if not exists reply_to_code char(7);

-- 2) Reactions: {emoji: [user_id, ...]} — counts derived client-side.
alter table room_messages
  add column if not exists reactions jsonb not null default '{}'::jsonb;

-- 3) Host pin: text snapshot on the room row (message may be deleted).
alter table rooms
  add column if not exists pinned_text text;
alter table rooms
  add column if not exists pinned_at timestamptz;

-- 4) send_room_message gains optional reply ref (default NULL: old
-- callers keep working). Reply must belong to the SAME room, else ignored.
drop function if exists send_room_message(text, text);
create function send_room_message(
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
  select device_code into v_sender_code from installs
    where owner_user_id = auth.uid();
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
revoke all on function send_room_message(text, text, uuid) from public;
grant execute on function send_room_message(text, text, uuid) to authenticated;

-- 5) Toggle one reaction (whitelisted emoji, member-only, capped).
create or replace function react_to_message(
  p_msg_id uuid,
  p_emoji text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_msg room_messages%rowtype;
  v_list jsonb;
  v_has boolean;
begin
  -- The 8 allowed reactions (client mirrors this list).
  if p_emoji not in ('❤️','😂','😮','😢','😡','👍','👏','🎉') then
    return false;
  end if;
  select * into v_msg from room_messages where id = p_msg_id;
  if not found then return false; end if;
  if not exists (
    select 1 from rooms r
    where r.room_id = v_msg.room_id and r.status <> 'closed'
  ) then
    return false;
  end if;
  if not exists (
    select 1 from room_members m
    where m.room_id = v_msg.room_id and m.user_id = auth.uid()
  ) then
    return false;
  end if;
  v_list := coalesce(v_msg.reactions -> p_emoji, '[]'::jsonb);
  v_has := v_list @> to_jsonb(auth.uid()::text);
  if v_has then
    v_list := (
      select coalesce(jsonb_agg(x), '[]'::jsonb)
      from jsonb_array_elements_text(v_list) as x
      where x <> auth.uid()::text
    );
  else
    -- Cap: 6 emoji kinds per message, 50 reactors per emoji.
    if (select count(*) from jsonb_object_keys(coalesce(v_msg.reactions, '{}'::jsonb))) >= 6
       and not (v_msg.reactions ? p_emoji) then
      return false;
    end if;
    if jsonb_array_length(v_list) >= 50 then return false; end if;
    v_list := v_list || to_jsonb(auth.uid()::text);
  end if;
  update room_messages
    set reactions = jsonb_set(
      coalesce(reactions, '{}'::jsonb), array[p_emoji], v_list
    )
    where id = p_msg_id;
  -- Prune emptied emoji keys so counts stay honest.
  update room_messages
    set reactions = reactions - p_emoji
    where id = p_msg_id
      and coalesce(jsonb_array_length(reactions -> p_emoji), 0) = 0;
  return true;
end;
$$;
revoke all on function react_to_message(uuid, text) from public;
grant execute on function react_to_message(uuid, text) to authenticated;

-- 6) Host pin / unpin (p_msg_id null = unpin). Text snapshot, 140 chars.
create or replace function pin_room_message(
  p_room_id text,
  p_msg_id uuid default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_msg room_messages%rowtype;
begin
  select room_id into v_code from rooms
    where room_id = upper(trim(p_room_id)) and status <> 'closed';
  if not found then return false; end if;
  if not exists (
    select 1 from rooms r
    where r.room_id = v_code and r.host_user_id = auth.uid()
  ) then
    return false; -- host only
  end if;
  if p_msg_id is null then
    update rooms set pinned_text = null, pinned_at = null
      where room_id = v_code;
    return true;
  end if;
  select * into v_msg from room_messages
    where id = p_msg_id and room_id = v_code;
  if not found then return false; end if;
  update rooms
    set pinned_text = left(v_msg.body, 140), pinned_at = now()
    where room_id = v_code;
  return true;
end;
$$;
revoke all on function pin_room_message(text, uuid) from public;
grant execute on function pin_room_message(text, uuid) to authenticated;

-- 7) Close wipes messages AND clears the pin (ephemeral, all of it).
create or replace function wipe_room_chat_on_close()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'closed' and old.status <> 'closed' then
    delete from room_messages where room_id = new.room_id;
    -- AFTER-trigger: clear the pin with an update (status untouched,
    -- so this never re-fires the status trigger).
    update rooms set pinned_text = null, pinned_at = null
      where room_id = new.room_id;
  end if;
  return new;
end;
$$;
