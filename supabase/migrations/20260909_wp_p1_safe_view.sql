-- WP-P1: public lobby safe view (locked spec 2026-09-09).
-- Exposes ONLY public, non-closed rooms. No pass_hash, no host_user_id,
-- no private rooms. Clients must read this view, never `rooms` directly.
-- Run ONCE in Supabase SQL Editor after 20260908_s3_rooms_secure_join.sql.
create or replace view public_rooms_safe
with (security_invoker = true)
as
select
  r.room_id,
  r.title,
  r.media_ref,
  r.status,
  r.created_at,
  (select count(*)::int from room_members m where m.room_id = r.room_id)
    as member_count
from rooms r
where r.visibility = 'public'
  and r.status in ('lobby', 'live');

grant select on public_rooms_safe to authenticated;
