-- 20261033_admin_realtime
-- The admin panel polled every 10-30 s and still needed a manual refresh for
-- tables it never read directly. Realtime postgres_changes is gated by RLS,
-- so each watched table needs an admin SELECT policy before it can stream.
-- Every policy here is additive (OR-ed with the existing ones) and limited
-- to is_admin(), which is SECURITY DEFINER on the allowlist.

begin;

-- 1. Admin SELECT policies -------------------------------------------------
-- devices: only the owner could read a row, so admins saw nothing directly.
drop policy if exists "admins read devices" on public.devices;
create policy "admins read devices" on public.devices
  for select to authenticated using (public.is_admin());

-- user_reports: insert-only, admins read it through a definer RPC.
drop policy if exists "admins read user reports" on public.user_reports;
create policy "admins read user reports" on public.user_reports
  for select to authenticated using (public.is_admin());

-- admin_audit: no policies at all (definer RPC only).
drop policy if exists "admins read admin audit" on public.admin_audit;
create policy "admins read admin audit" on public.admin_audit
  for select to authenticated using (public.is_admin());

-- ban_appeals: insert-only, admins read it through a definer RPC.
drop policy if exists "admins read ban appeals" on public.ban_appeals;
create policy "admins read ban appeals" on public.ban_appeals
  for select to authenticated using (public.is_admin());

-- rooms: members read eligible rooms only; admins need every room row.
drop policy if exists "admins read all rooms" on public.rooms;
create policy "admins read all rooms" on public.rooms
  for select to authenticated using (public.is_admin());

-- 2. Realtime publication ------------------------------------------------
-- Idempotent: only add tables that are not already streamed.
do $do$
declare
  t text;
begin
  foreach t in array array[
    'devices',
    'device_logs',
    'user_reports',
    'room_reports',
    'support_tickets',
    'announcements',
    'remote_config',
    'admin_audit',
    'curated_playlists',
    'ban_appeals'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end
$do$;

commit;
