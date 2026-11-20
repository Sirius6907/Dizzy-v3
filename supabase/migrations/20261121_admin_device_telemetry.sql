-- Dizzy v1.4.3 — Phase 3: the Fleet panel sees a device's WHOLE telemetry.
-- Run AFTER 20261121_device_logs_backfill.sql:
--   supabase db query --linked -f supabase/migrations/20261121_admin_device_telemetry.sql
--
-- Phase 1+2 gave every telemetry row a device_id and remembered every code a
-- device ever carried. This file makes that visible:
--
--   admin_devices(int, text)      same signature, plus
--     code_count                  how many codes this device has carried
--     codes                       newest-first [{code, first_seen_at,
--                                 last_seen_at, source, rows, hits}]
--     log_rows/log_hits/log_last_at
--                                 now cover ALL of the device's codes, not
--                                 only the one it currently wears
--     and p_search matches historical codes too, so support can paste an old
--     code and still land on the device.
--
--   admin_orphan_logs(int)        NEW — codes that no device can be proven
--                                 to own, with volume, first/last seen and
--                                 their worst offenders. This is the honest
--                                 remainder: grouped, not silently dropped.
--
-- Still never returns hwid_hash. Only is_admin() may call either.

-- ═══════════ 1) admin_devices ═══════════
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

           -- ── telemetry, across every code this device ever wore ──
           (select count(*)
              from public.device_logs l
             where l.device_id = d.device_id
                or l.device_code = btrim(d.device_code)) as log_rows,
           (select coalesce(sum(l.count), 0)
              from public.device_logs l
             where l.device_id = d.device_id
                or l.device_code = btrim(d.device_code)) as log_hits,
           (select max(l.last_at)
              from public.device_logs l
             where l.device_id = d.device_id
                or l.device_code = btrim(d.device_code)) as log_last_at,

           -- ── the codes themselves ──
           (select count(distinct c.code)
              from (select dc.code
                      from public.device_codes dc
                     where dc.device_id = d.device_id
                    union
                    select btrim(d.device_code)
                     where btrim(d.device_code) <> '') c) as code_count,
           (select coalesce(jsonb_agg(jsonb_build_object(
                     'code', c.code,
                     'first_seen_at', c.first_seen_at,
                     'last_seen_at', c.last_seen_at,
                     'source', c.source,
                     'current', c.code = btrim(d.device_code),
                     'rows', (select count(*) from public.device_logs l
                               where l.device_code = c.code),
                     'hits', (select coalesce(sum(l.count), 0)
                                from public.device_logs l
                               where l.device_code = c.code)
                   ) order by c.last_seen_at desc nulls last), '[]'::jsonb)
              from (
                -- one row per code: the registry may know the code already,
                -- and the current code is appended only if it is unknown.
                select dc.code,
                       min(dc.first_seen_at) as first_seen_at,
                       max(dc.last_seen_at) as last_seen_at,
                       max(dc.source) as source
                  from public.device_codes dc
                 where dc.device_id = d.device_id
                 group by dc.code
                union all
                select btrim(d.device_code), d.created_at, d.last_seen_at, 'boot'
                 where btrim(d.device_code) <> ''
                   and not exists (select 1 from public.device_codes dc2
                                    where dc2.code = btrim(d.device_code))
              ) c) as codes,

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
           or pun.username ilike '%' || p_search || '%'
           or exists (select 1 from public.device_codes dc
                       where dc.device_id = d.device_id
                         and dc.code ilike '%' || p_search || '%'))
    order by d.last_seen_at desc nulls last
    limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;

revoke all on function public.admin_devices(int, text) from public;
grant execute on function public.admin_devices(int, text) to authenticated;

comment on function public.admin_devices(int, text) is
  'Fleet devices for the admin dashboard: owner @username, username log, every code the device carried and the telemetry behind them. Never hwid_hash.';

-- ═══════════ 2) admin_orphan_logs ═══════════
-- A code is "unlinked" when no device can be proven to own it. That is not a
-- failure to hide: it is a real population (pre-registry installs whose
-- legacy hash is gone) and support deserves to see its shape and volume.
create or replace function public.admin_orphan_logs(p_limit integer default 200)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select jsonb_build_object(
    'totals', (
      select jsonb_build_object(
        'codes', count(*),
        'rows', coalesce(sum(x.rows), 0),
        'hits', coalesce(sum(x.hits), 0),
        'first_at', min(x.first_at),
        'last_at', max(x.last_at))
      from (
        select l.device_code,
               count(*) as rows,
               sum(l.count) as hits,
               min(l.first_at) as first_at,
               max(l.last_at) as last_at
        from public.device_logs l
        where l.device_code <> 'unknown'
          and l.device_id is null
        group by l.device_code
      ) x
    ),
    'codes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', x.device_code,
               'rows', x.rows,
               'hits', x.hits,
               'screens', x.screens,
               'first_at', x.first_at,
               'last_at', x.last_at,
               'platform', x.platform,
               'app_version', x.app_version,
               'top', x.top)
             order by x.hits desc)
      from (
        select l.device_code,
               count(*) as rows,
               sum(l.count) as hits,
               count(distinct l.screen) as screens,
               min(l.first_at) as first_at,
               max(l.last_at) as last_at,
               (array_agg(l.platform order by l.last_at desc))[1] as platform,
               (array_agg(l.app_version order by l.last_at desc))[1] as app_version,
               (select coalesce(jsonb_agg(jsonb_build_object(
                         'code', t.code, 'screen', t.screen,
                         'hits', t.hits, 'last_at', t.last_at)
                       order by t.hits desc), '[]'::jsonb)
                  from (select l2.code, l2.screen, sum(l2.count) as hits,
                               max(l2.last_at) as last_at
                          from public.device_logs l2
                         where l2.device_code = l.device_code
                           and l2.device_id is null
                         group by l2.code, l2.screen
                         order by sum(l2.count) desc
                         limit 3) t) as top
        from public.device_logs l
        where l.device_code <> 'unknown'
          and l.device_id is null
        group by l.device_code
        order by sum(l.count) desc
        limit greatest(p_limit, 1)
      ) x
    ), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

revoke all on function public.admin_orphan_logs(int) from public;
grant execute on function public.admin_orphan_logs(int) to authenticated;

comment on function public.admin_orphan_logs(int) is
  'Telemetry codes with no provable device owner, grouped with volume and worst offenders. Honest remainder, not a hidden bucket.';
