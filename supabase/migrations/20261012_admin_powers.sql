-- v1.3.3-T2.1 — remote powers: user lookup (support) + data reset (owner).
--
-- Deliberately narrow: only the two powers QA can break, so they ship with
-- audit rows. Remote-wipe, per-user feature overrides and live screen view
-- stay OUT (v1.3.4 backlog).
--
-- Lookup returns device codes + counts + identity trail — never emails or
-- raw content. Reset is scoped: progress/continue-watching rows only, and
-- always audited with the exact count deleted.
--
-- Idempotent.

-- ═══════════ 1) find_user: search by @username / user_id / device code ═══════════
create or replace function admin_find_user(p_search text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q     text := lower(btrim(coalesce(p_search, '')));
  v_uid   uuid;
  v_dev   text;
  v_out   jsonb;
begin
  perform require_role(array['owner', 'support']);
  if v_q = '' then return '[]'::jsonb; end if;

  -- A bare 7-digit number is a device code (DIZ-xxxxxxx in the UI).
  if v_q ~ '^diz-?[1-9][0-9]{6}$' then
    v_dev := regexp_replace(v_q, '^diz-?', '');
  elsif v_q ~ '^[1-9][0-9]{6}$' then
    v_dev := v_q;
  end if;

  -- user_id (uuid) direct, else @username / profile name.
  begin
    v_uid := v_q::uuid;
  exception when others then
    v_uid := null;
  end;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_out from (
    select
      u.user_id,
      (select username from usernames w where w.user_id = u.user_id) as username,
      (select jsonb_agg(jsonb_build_object('name', p.name, 'avatar', p.avatar))
         from profiles p where p.user_id = u.user_id) as profiles,
      (select count(*) from cloud_sessions c where c.user_id = u.user_id) as sessions,
      (select max(d.last_heartbeat_at) from devices d where d.user_id = u.user_id) as last_seen,
      (select coalesce(jsonb_agg(jsonb_build_object('device_code', d.device_code, 'platform', d.platform)), '[]'::jsonb)
         from devices d where d.user_id = u.user_id) as installs,
      (select coalesce(jsonb_agg(jsonb_build_object('kind', h.kind, 'old_value', h.old_value, 'new_value', h.new_value, 'at', h.created_at)
                order by h.created_at desc), '[]'::jsonb)
         from (select * from identity_history ih
               where ih.user_id = u.user_id order by ih.created_at desc limit 10) h) as history
    from auth.users u
    where (v_uid is not null and u.id = v_uid)
       or (v_uid is null and (
             exists (select 1 from usernames w2
                     where w2.user_id = u.user_id and lower(w2.username) = ltrim(v_q, '@'))
          or exists (select 1 from profiles p2
                     where p2.user_id = u.user_id and lower(p2.name) = v_q)
       ))
       or (v_dev is not null and exists (
             select 1 from installs i2
             where i2.user_id = u.user_id and i2.device_code = v_dev))
    limit 20
  ) t;

  return coalesce(v_out, '[]'::jsonb);
end;
$$;
revoke all on function admin_find_user(text) from public;
grant execute on function admin_find_user(text) to authenticated;

-- ═══════════ 2) data reset: progress rows only, audited ═══════════
-- p_scope: 'progress' (continue-watching / cloud sessions) | 'profile'
-- (profiles + usernames, i.e. a full identity re-onboard). Both are
-- recoverable by re-sync; neither touches purchases or device binding.
create or replace function admin_reset_user(p_user_id uuid, p_scope text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n_sessions int := 0;
  v_n_profiles int := 0;
  v_n_names    int := 0;
begin
  perform require_role(array['owner']);   -- destructive ⇒ owner only
  if p_scope not in ('progress', 'profile') then raise exception 'bad scope'; end if;
  if p_user_id is null then raise exception 'user required'; end if;

  if p_scope = 'progress' then
    delete from cloud_sessions where user_id = p_user_id;
    get diagnostics v_n_sessions = row_count;
  else
    delete from cloud_sessions where user_id = p_user_id;
    get diagnostics v_n_sessions = row_count;
    delete from profiles where user_id = p_user_id;
    get diagnostics v_n_profiles = row_count;
    delete from usernames where user_id = p_user_id;
    get diagnostics v_n_names = row_count;
  end if;

  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'user:reset:' || p_scope, p_user_id::text,
            jsonb_build_object('sessions', v_n_sessions,
                               'profiles', v_n_profiles,
                               'usernames', v_n_names));
  return jsonb_build_object('sessions', v_n_sessions,
                            'profiles', v_n_profiles,
                            'usernames', v_n_names);
end;
$$;
revoke all on function admin_reset_user(uuid, text) from public;
grant execute on function admin_reset_user(uuid, text) to authenticated;