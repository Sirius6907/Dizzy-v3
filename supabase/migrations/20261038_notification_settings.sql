-- Dizzy v1.3.3 — notification prefs, server-side mirror (Phase 4).
-- Run: supabase db query --linked -f supabase/migrations/20261038_notification_settings.sql
-- then record the history row (never `db push`).
--
-- The app already stores the gate locally (notification_gate_v1). The push
-- brain runs without the app awake, so it needs the same answer: the client
-- mirrors the gate here whenever a switch changes or the app boots, and the
-- brain skips muted kinds and quiet hours per user before spending a send.
--
-- No row = first run defaults: every kind on, quiet hours off — exactly the
-- client's NotificationGate() defaults, so behaviour never changes just
-- because the mirror has not synced yet.

create table if not exists public.notification_settings (
  user_id            uuid primary key,
  off_kinds          text[] not null default '{}',
  quiet_enabled      boolean not null default false,
  quiet_start_minute int not null default 1320,
  quiet_end_minute   int not null default 420,
  tz_offset_minutes  int not null default 330,
  updated_at         timestamptz not null default now(),
  constraint notification_settings_start_chk
    check (quiet_start_minute between 0 and 1439),
  constraint notification_settings_end_chk
    check (quiet_end_minute between 0 and 1439),
  constraint notification_settings_tz_chk
    check (tz_offset_minutes between -840 and 840)
);

alter table public.notification_settings enable row level security;

drop policy if exists notification_settings_select_own on public.notification_settings;
create policy notification_settings_select_own on public.notification_settings
  for select to authenticated using (user_id = auth.uid());

revoke all on public.notification_settings from anon, authenticated;
grant select on public.notification_settings to authenticated;
grant all on public.notification_settings to service_role;

create or replace function public.sync_notification_settings(
  p_off text[] default '{}',
  p_quiet_enabled boolean default false,
  p_quiet_start int default 1320,
  p_quiet_end int default 420,
  p_tz_offset int default 330
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_off text[];
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'auth');
  end if;

  -- Only the five real kinds; anything else is dropped rather than stored.
  select coalesce(array_agg(distinct k), '{}'::text[]) into v_off
  from unnest(coalesce(p_off, '{}'::text[])) k
  where k in ('updates', 'releases', 'downloads', 'social', 'announcements');

  insert into public.notification_settings as s
    (user_id, off_kinds, quiet_enabled, quiet_start_minute,
     quiet_end_minute, tz_offset_minutes, updated_at)
  values (
    v_uid,
    v_off,
    coalesce(p_quiet_enabled, false),
    least(1439, greatest(0, coalesce(p_quiet_start, 1320))),
    least(1439, greatest(0, coalesce(p_quiet_end, 420))),
    least(840, greatest(-840, coalesce(p_tz_offset, 330))),
    now()
  )
  on conflict (user_id) do update set
    off_kinds = excluded.off_kinds,
    quiet_enabled = excluded.quiet_enabled,
    quiet_start_minute = excluded.quiet_start_minute,
    quiet_end_minute = excluded.quiet_end_minute,
    tz_offset_minutes = excluded.tz_offset_minutes,
    updated_at = excluded.updated_at;

  return jsonb_build_object('success', true, 'off', v_off);
end;
$$;

revoke all on function public.sync_notification_settings(text[], boolean, int, int, int) from public;
grant execute on function public.sync_notification_settings(text[], boolean, int, int, int)
  to authenticated, service_role;

comment on table public.notification_settings is
  'Server mirror of the in-app notification gate; the push brain honours it.';
