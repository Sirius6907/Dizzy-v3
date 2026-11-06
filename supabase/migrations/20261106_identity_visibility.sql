-- v1.3.4 — usernames are canonical, and admins see changes live.
--
-- Apply: supabase db query --linked -f supabase/migrations/20261106_identity_visibility.sql
-- then record the history row (never `db push`).
--
-- 1. search_users read profiles.username, but every claim/rename since
--    20261034_username_gate writes usernames. A freshly renamed user was
--    therefore invisible to Friends search while an old migrated name kept
--    matching. Read the canonical table and join at most one profile for
--    display name/avatar.
-- 2. Two-character handles like "di" need prefix matching; trigram
--    similarity alone does not qualify them.
-- 3. admin_user_identity searched for "%@name%" although handles are
--    stored bare. Strip a leading @ like admin_find_user already does.
-- 4. Admin realtime needs SELECT policies and publication membership for
--    the identity tables, otherwise a rename never repaints the dashboard.

begin;

create or replace function public.search_users(
  p_query text,
  p_limit integer default 10
)
returns table(user_id uuid, username text, display_name text, avatar_url text)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_clean text := lower(trim(coalesce(p_query, '')));
  v_handle text;
begin
  -- Accept "@name" the same as "name".
  v_handle := lower(trim(regexp_replace(v_clean, '^@', '')));
  if length(v_handle) < 2 then
    return;
  end if;

  return query
  select u.user_id,
         u.username,
         coalesce(p.name, ''),
         p.avatar
  from public.usernames u
  left join lateral (
    select pr.name, pr.avatar
    from public.profiles pr
    where pr.user_id = u.user_id
    order by pr.updated_at desc nulls last, pr.profile_id desc
    limit 1
  ) p on true
  where u.user_id <> auth.uid()
    and (
      u.username_lower like v_handle || '%'
      or (length(v_handle) >= 3 and u.username_lower like '%' || v_handle || '%')
      or u.username_lower % v_handle
    )
  order by
    case
      when u.username_lower = v_handle then 0
      when u.username_lower like v_handle || '%' then 1
      when u.username_lower like '%' || v_handle || '%' then 2
      else 3
    end,
    similarity(u.username_lower, v_handle) desc,
    u.username_lower asc,
    u.user_id asc
  limit least(greatest(coalesce(p_limit, 10), 1), 20);
end;
$function$;

revoke all on function public.search_users(text, integer) from public;
grant execute on function public.search_users(text, integer) to authenticated;

-- Admin identity search: bare handles, optional @, same result shape.
create or replace function public.admin_user_identity(p_search text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_terms text := lower(trim(coalesce(p_search, '')));
  q text;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  v_terms := lower(trim(regexp_replace(v_terms, '^@', '')));
  q := '%' || v_terms || '%';

  return coalesce((
    select jsonb_agg(t order by t.last_change_at desc)
    from (
      select
        top.user_id, top.username, top.last_change_at,
        (select coalesce(jsonb_agg(jsonb_build_object(
            'profile_id', p.profile_id, 'name', p.name, 'avatar', p.avatar
          )), '[]'::jsonb)
         from public.profiles p where p.user_id = top.user_id) as profiles,
        (select coalesce(jsonb_agg(jsonb_build_object(
            'kind', h.kind, 'old_value', h.old_value, 'new_value', h.new_value,
            'profile_id', h.profile_id, 'at', h.created_at
          ) order by h.created_at desc), '[]'::jsonb)
         from public.identity_history h where h.user_id = top.user_id) as history
      from (
        select u.user_id, u.username, u.last_change_at
        from public.usernames u
        where v_terms = ''
           or u.username ilike q
           or u.user_id::text ilike q
           or exists (select 1 from public.devices d
                      where d.user_id = u.user_id and d.device_code ilike q)
           or exists (select 1 from public.profiles p
                      where p.user_id = u.user_id and p.name ilike q)
        order by u.last_change_at desc
        limit 20
      ) top
    ) t
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.admin_user_identity(text) from public;
grant execute on function public.admin_user_identity(text) to authenticated;

-- Admin realtime: read rows, then add to the publication once.
drop policy if exists "admins read usernames" on public.usernames;
create policy "admins read usernames" on public.usernames
  for select using (public.is_admin());

drop policy if exists "admins read identity history" on public.identity_history;
create policy "admins read identity history" on public.identity_history
  for select using (public.is_admin());

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'usernames'
  ) then
    alter publication supabase_realtime add table public.usernames;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'identity_history'
  ) then
    alter publication supabase_realtime add table public.identity_history;
  end if;
end
$$;

commit;
