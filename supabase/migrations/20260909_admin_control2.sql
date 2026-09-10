-- Dizzy Admin Control — part 2: installs explorer (v1.2.0-ADMIN).
-- Run ONCE in Supabase SQL Editor AFTER 20260909_admin_control.sql.

-- Recent installs (device codes, platform, version — no PII).
create or replace function admin_installs(p_limit int default 50, p_search text default '')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb; q text := '%' || trim(coalesce(p_search,'')) || '%';
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t ORDER BY t.last_seen_at DESC), '[]'::jsonb) into v from (
    select anon_id, platform, app_version, region_code, created_at, last_seen_at
    from installs
    where q = '%%'
       or platform ilike q or app_version ilike q or region_code ilike q
       or anon_id ilike q
    order by last_seen_at desc
    limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;
revoke all on function admin_installs(int, text) from public;
grant execute on function admin_installs(int, text) to authenticated;

-- Platform + version breakdown (pie chart data).
create or replace function admin_breakdown()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select jsonb_build_object(
    'platforms', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
      select platform as name, count(*) as n from installs group by platform order by n desc) t),
    'versions', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
      select app_version as name, count(*) as n from installs group by app_version order by n desc) t),
    'consents', (select jsonb_build_object(
      'telemetry', (select count(*) from consents where telemetry),
      'genre_prefs', (select count(*) from consents where genre_prefs),
      'crash', (select count(*) from consents where crash),
      'watch_party', (select count(*) from consents where watch_party),
      'total', (select count(*) from consents)))
  ) into v;
  return v;
end;
$$;
revoke all on function admin_breakdown() from public;
grant execute on function admin_breakdown() to authenticated;
