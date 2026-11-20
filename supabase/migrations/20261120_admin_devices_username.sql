-- Dizzy v1.4.3 — Fleet devices carry their owner's @username and username log.
-- Run: supabase db query --linked -f supabase/migrations/20261120_admin_devices_username.sql
-- then record the history row (never `db push`).
--
-- Problem: the Fleet → Devices table identified a row by the 7-char device
-- code only. Support had to copy the code into the Usernames tab to learn who
-- the device belongs to, and there was no way to see a device's name changes
-- (or the name a reinstall left behind on `previous_user_id`).
--
-- This keeps the same signature and every existing field, and adds:
--   user_id                 current owner (already implied, now explicit)
--   previous_user_id        prior owner kept by device_boot on a reinstall
--   username                current @name of the owner (null = never claimed)
--   username_changed_at     when that @name last changed
--   previous_username       @name the previous owner left on this device
--   username_change_count   how many username rows exist for the owner
--   username_history        newest-first [{old_value,new_value,at}] (max 20)
--   log_rows / log_hits / log_last_at
--                           error telemetry folded into this device (the
--                           Device logs tab can then be opened already
--                           filtered to the code, so support never has to
--                           copy a code between tabs)
--
-- Still never returns hwid_hash. Only is_admin() may call it.

-- Self-sufficient: 20261113 added this column, but the join below must not
-- fail if this file is run on a database that skipped that step.
alter table public.devices add column if not exists previous_user_id uuid;

create or replace function public.admin_devices(
  p_limit integer default 100,
  p_search text default ''
)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t order by t.last_seen_at desc nulls last), '[]'::jsonb)
  into v
  from (
    select d.device_id, d.device_code, d.platform, d.app_version,
           d.last_seen_at, d.revoked_at, d.created_at,
           d.hwid_stable,
           d.adult_allowed,
           d.activity,
           d.user_id,
           d.previous_user_id,
           un.username,
           un.last_change_at as username_changed_at,
           pun.username as previous_username,
           (select count(*)
              from public.identity_history h
             where h.user_id = d.user_id
               and h.kind = 'username') as username_change_count,
           (select coalesce(jsonb_agg(jsonb_build_object(
                     'old_value', h.old_value,
                     'new_value', h.new_value,
                     'at', h.created_at
                   ) order by h.created_at desc), '[]'::jsonb)
              from (select h2.old_value, h2.new_value, h2.created_at
                      from public.identity_history h2
                     where h2.user_id = d.user_id
                       and h2.kind = 'username'
                     order by h2.created_at desc
                     limit 20) h) as username_history,
           (select count(*)
              from public.device_logs l
             where l.device_code = d.device_code) as log_rows,
           (select coalesce(sum(l.count), 0)
              from public.device_logs l
             where l.device_code = d.device_code) as log_hits,
           (select max(l.last_at)
              from public.device_logs l
             where l.device_code = d.device_code) as log_last_at,
           (d.last_seen_at > now() - interval '10 minutes') as online,
           (b.user_id is not null) as banned,
           b.level as ban_level
    from public.devices d
    left join public.usernames un
      on un.user_id = d.user_id
    left join public.usernames pun
      on pun.user_id = d.previous_user_id
    left join public.user_bans b
      on b.user_id = d.user_id
     and (b.banned_until is null or b.banned_until > now())
    where (p_search = ''
           or d.device_code ilike '%' || p_search || '%'
           or d.device_id::text ilike '%' || p_search || '%'
           or d.platform ilike '%' || p_search || '%'
           or d.app_version ilike '%' || p_search || '%'
           or un.username ilike '%' || p_search || '%'
           or pun.username ilike '%' || p_search || '%')
    order by d.last_seen_at desc nulls last
    limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;

revoke all on function public.admin_devices(int, text) from public;
grant execute on function public.admin_devices(int, text) to authenticated;

comment on function public.admin_devices(int, text) is
  'Fleet devices for the admin dashboard: code, owner @username, username change log, previous-owner name. Never hwid_hash.';
