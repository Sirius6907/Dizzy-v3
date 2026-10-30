-- Admin user-management repair.
--
-- 1. admin_find_user selected `u.user_id` from auth.users. That table's
--    primary key is `id`; `user_id` never existed, so every lookup raised
--    `column u.user_id does not exist` — the panel's user search (by
--    @username, user id, or DIZ- device code) has never returned a row.
--
--    The device lookup also read `installs`, which no longer receives
--    writes (0 rows against 22 live rows in `devices`), so even with the
--    column fixed a DIZ- code could not match. Devices are the live
--    record; that is what the panel lists and what this now searches.
--
-- 2. admin_ban_user(level => 'full') and admin_unban_user both write
--    `devices.revoke_reason`, which was never created. A full ban raised
--    before it could revoke anything, and unban raised on every call, so
--    the ban/unban buttons in the panel could not work. The column is
--    what the code already assumes; adding it keeps unban scoped to
--    devices revoked by a ban instead of reviving every revoked device.

begin;

alter table public.devices add column if not exists revoke_reason text;

create or replace function public.admin_find_user(p_search text)
returns jsonb
language plpgsql
stable
security definer
set search_path to public
as $function$
declare
  v_q     text := lower(btrim(coalesce(p_search, '')));
  v_uid   uuid;
  v_dev   text;
  v_out   jsonb;
begin
  perform require_role(array['owner', 'support']);
  if v_q = '' then return '[]'::jsonb; end if;

  if v_q ~ '^diz-?[1-9][0-9]{6}$' then
    v_dev := regexp_replace(v_q, '^diz-?', '');
  elsif v_q ~ '^[1-9][0-9]{6}$' then
    v_dev := v_q;
  end if;

  begin
    v_uid := v_q::uuid;
  exception when others then
    v_uid := null;
  end;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_out from (
    select
      u.id as user_id,
      (select username from usernames w where w.user_id = u.id) as username,
      (select jsonb_agg(jsonb_build_object('name', p.name, 'avatar', p.avatar))
         from profiles p where p.user_id = u.id) as profiles,
      (select count(*) from cloud_sessions c where c.user_id = u.id) as sessions,
      (select max(d.last_heartbeat_at) from devices d where d.user_id = u.id) as last_seen,
      (select coalesce(jsonb_agg(jsonb_build_object('device_code', d.device_code, 'platform', d.platform)), '[]'::jsonb)
         from devices d where d.user_id = u.id) as installs,
      (select coalesce(jsonb_agg(jsonb_build_object('kind', h.kind, 'old_value', h.old_value, 'new_value', h.new_value, 'at', h.created_at)
                order by h.created_at desc), '[]'::jsonb)
         from (select * from identity_history ih
               where ih.user_id = u.id order by ih.created_at desc limit 10) h) as history
    from auth.users u
    where (v_uid is not null and u.id = v_uid)
       or (v_uid is null and (
             exists (select 1 from usernames w2
                     where w2.user_id = u.id and lower(w2.username) = ltrim(v_q, '@'))
          or exists (select 1 from profiles p2
                     where p2.user_id = u.id and lower(p2.name) = v_q)
       ))
       or (v_dev is not null and exists (
             select 1 from devices d
             where d.user_id = u.id and d.device_code = v_dev))
    limit 20
  ) t;

  return coalesce(v_out, '[]'::jsonb);
end;
$function$;

revoke all on function public.admin_find_user(text) from public;
grant execute on function public.admin_find_user(text) to authenticated;

commit;
