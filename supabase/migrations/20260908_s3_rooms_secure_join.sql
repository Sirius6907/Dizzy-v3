-- Dizzy v1.1.9 S3C — secure Watch Party joining.
-- Run ONCE after schema_v119.sql. Uses room ID + optional hashed 6-digit pass.
-- No media URL, stream source, chat history, or playback bytes are stored.

create extension if not exists pgcrypto;

-- Never allow direct room_members inserts: members must join through this RPC.
drop policy if exists "member rw own membership" on room_members;
drop policy if exists "member read own membership" on room_members;
drop policy if exists "member leave own membership" on room_members;
create policy "member read own membership" on room_members
  for select to authenticated using (auth.uid() = user_id);
create policy "member leave own membership" on room_members
  for delete to authenticated using (auth.uid() = user_id);

-- A user may see public rooms, rooms they host, or rooms they joined.
drop policy if exists "auth read public rooms" on rooms;
create policy "member read eligible rooms" on rooms
  for select to authenticated
  using (
    visibility = 'public'
    or auth.uid() = host_user_id
    or exists (
      select 1 from room_members rm
      where rm.room_id = rooms.room_id and rm.user_id = auth.uid()
    )
  );

-- Joins public rooms pass-less. Private room pass_hash comparison stays server-side.
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
begin
  select * into r from rooms where room_id = upper(trim(p_room_id));
  if not found or r.status = 'closed' then return false; end if;
  if r.visibility = 'private' and
     (p_pass_hash is null or p_pass_hash <> r.pass_hash) then
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

-- Explicitly expose rooms in Realtime for lobby/status updates.
alter publication supabase_realtime add table rooms;
-- If it says relation already exists in publication, that message is harmless.

-- Recommended: Authentication → CAPTCHA protection enable before public release.
-- Test/dev can stay without CAPTCHA to avoid mobile provider setup friction.
