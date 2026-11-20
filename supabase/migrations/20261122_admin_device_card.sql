-- Dizzy v1.4.4 — Phase 6: one device, one card, from a single paste.
-- Run AFTER 20261121_legal_acceptance.sql:
--   supabase db query --linked -f supabase/migrations/20261122_admin_device_card.sql
--
-- Support tickets arrive as "DIZ-1234567". Before this, answering one meant
-- three tabs: Fleet search for the code, Device logs for the errors, Privacy
-- for whether the user had consented. And when a user reinstalled, the code
-- in the ticket was the RETIRED one, so Fleet showed nothing at all.
--
-- admin_device_card(text) takes whatever was pasted — DIZ-code (current or
-- retired), device id, user id, @username, or a plain code — and returns the
-- matching devices as self-contained cards:
--
--   identity     device_id, current code, every code ever worn, hwid_stable
--   ownership    user_id, @username, previous @username
--   build        platform, app_version
--   lifecycle    first seen (created_at), last seen, days_since_seen, stale,
--                online, revoked_at, adult_allowed, banned/ban_level
--   consent      telemetry / crash / genre_prefs, or null when the user never
--                made a choice (null and "all false" are different answers)
--   telemetry    log_rows, log_hits, log_screens, log_last_at across every code
--   history      username changes, newest first
--
-- Deliberately NOT here: hwid_hash. Still admin-only.

create or replace function public.admin_device_card(p_search text)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare
  v text := btrim(coalesce(p_search, ''));
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if v = '' then return '[]'::jsonb; end if;

  -- People paste the label, not the code: "DIZ-1234567" -> "1234567".
  if lower(v) like 'diz-%' then
    v := btrim(substr(v, 5));
  end if;
  -- ...or a handle with the sigil the UI shows: "@suman" -> "suman".
  if v like '@%' then
    v := btrim(substr(v, 2));
  end if;
  if v = '' then return '[]'::jsonb; end if;

  return (
    select coalesce(
             jsonb_agg(s.card order by s.last_seen_at desc nulls last),
             '[]'::jsonb)
      from (
        select
          jsonb_build_object(
            'device_id', d.device_id,
            'device_code', btrim(d.device_code),
            'hwid_stable', d.hwid_stable,
            'user_id', d.user_id,
            'username', un.username,
            'previous_username', pun.username,
            'platform', d.platform,
            'app_version', d.app_version,
            'first_seen_at', d.created_at,
            'last_seen_at', d.last_seen_at,
            'days_since_seen', case
              when d.last_seen_at is null then null
              else floor(extract(epoch from (now() - d.last_seen_at)) / 86400)::int
            end,
            'stale', (d.last_seen_at is null
                      or d.last_seen_at < now() - interval '30 days'),
            'online', (d.last_seen_at > now() - interval '10 minutes'),
            'activity', d.activity,
            'revoked_at', d.revoked_at,
            'adult_allowed', d.adult_allowed,
            'banned', (b.user_id is not null),
            'ban_level', b.level,

            -- null = never asked/answered; the dashboard must not read that
            -- as "said no".
            'consent', case
              when c.owner_user_id is null then null
              else jsonb_build_object(
                     'telemetry', c.telemetry,
                     'crash', c.crash,
                     'genre_prefs', c.genre_prefs,
                     'updated_at', c.updated_at)
            end,

            'log_rows', (select count(*)
                           from public.device_logs l
                          where l.device_id = d.device_id
                             or l.device_code = btrim(d.device_code)),
            'log_hits', (select coalesce(sum(l.count), 0)
                           from public.device_logs l
                          where l.device_id = d.device_id
                             or l.device_code = btrim(d.device_code)),
            'log_screens', (select count(distinct l.screen)
                              from public.device_logs l
                             where l.device_id = d.device_id
                                or l.device_code = btrim(d.device_code)),
            'log_last_at', (select max(l.last_at)
                              from public.device_logs l
                             where l.device_id = d.device_id
                                or l.device_code = btrim(d.device_code)),

            'codes', (select coalesce(jsonb_agg(jsonb_build_object(
                              'code', c2.code,
                              'current', c2.code = btrim(d.device_code),
                              'source', c2.source,
                              'first_seen_at', c2.first_seen_at,
                              'last_seen_at', c2.last_seen_at,
                              'rows', (select count(*)
                                         from public.device_logs l
                                        where l.device_code = c2.code),
                              'hits', (select coalesce(sum(l.count), 0)
                                         from public.device_logs l
                                        where l.device_code = c2.code))
                            order by c2.last_seen_at desc nulls last), '[]'::jsonb)
                         from (
                           select dc.code,
                                  min(dc.first_seen_at) as first_seen_at,
                                  max(dc.last_seen_at) as last_seen_at,
                                  max(dc.source) as source
                             from public.device_codes dc
                            where dc.device_id = d.device_id
                            group by dc.code
                           union all
                           select btrim(d.device_code), d.created_at,
                                  d.last_seen_at, 'boot'
                            where btrim(d.device_code) <> ''
                              and not exists (
                                select 1 from public.device_codes dc3
                                 where dc3.code = btrim(d.device_code))
                         ) c2),

            'username_history', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'old_value', h.old_value,
                                   'new_value', h.new_value,
                                   'at', h.created_at)
                                 order by h.created_at desc), '[]'::jsonb)
                              from (select h2.old_value, h2.new_value, h2.created_at
                                      from public.identity_history h2
                                     where h2.user_id = d.user_id
                                       and h2.kind = 'username'
                                     order by h2.created_at desc
                                     limit 20) h)
          ) as card,
          d.last_seen_at
        from public.devices d
        left join public.usernames un  on un.user_id  = d.user_id
        left join public.usernames pun on pun.user_id = d.previous_user_id
        left join public.consents c    on c.owner_user_id = d.user_id
        left join public.user_bans b
               on b.user_id = d.user_id
              and (b.banned_until is null or b.banned_until > now())
        where btrim(d.device_code) ilike '%' || v || '%'
           or d.device_id::text ilike '%' || v || '%'
           or d.user_id::text = v
           or un.username ilike '%' || v || '%'
           or pun.username ilike '%' || v || '%'
           or exists (select 1 from public.device_codes dc
                       where dc.device_id = d.device_id
                         and dc.code ilike '%' || v || '%')
        order by d.last_seen_at desc nulls last
        limit 20
      ) s
  );
end;
$$;

revoke all on function public.admin_device_card(text) from public;
revoke all on function public.admin_device_card(text) from anon;
grant execute on function public.admin_device_card(text) to authenticated;

comment on function public.admin_device_card(text) is
  'One-paste device lookup for support: identity, owner, build, lifecycle, consent state and telemetry across every code the device ever wore. Never hwid_hash.';
