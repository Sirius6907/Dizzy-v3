-- WP-P12: lobby shows WHAT each room watches (locked spec 2026-09-12).
-- Run ONCE in Supabase SQL Editor (any order vs P11 file — independent).
--
-- Rebuilds public_rooms_safe on the P1 shape: + current_media_ref,
-- + current_title (host's live event writes them via updateCurrentMedia).
-- No RLS/policy change (same view, same grants, two extra columns).
-- Speaker dots need no column: voice presence is LiveKit-ephemeral; the
-- app renders dots from the live speaker feed of the JOINED room only.

drop view if exists public_rooms_safe;
create view public_rooms_safe
with (security_invoker = true)
as
select
  r.room_id,
  r.title,
  r.media_ref,
  r.current_media_ref,
  r.current_title,
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
