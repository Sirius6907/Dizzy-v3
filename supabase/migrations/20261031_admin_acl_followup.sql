-- Follow-up to 20261030_audit_hardening.
--
-- 1. search_users was dead on arrival. It selects `p.avatar_url`, but the
--    profiles column is called `avatar` — the function has raised
--    `column p.avatar_url does not exist` on every call since the rename.
--    The app's friend search (dizzy_social_service.searchUsers) hangs off
--    it, so username search never worked. The client reads `avatar_url`
--    from the row, so keep the alias and only fix the source column.
--
-- 2. Postgres grants EXECUTE on new functions to PUBLIC. The 20261030
--    loop did `revoke all ... from anon`, which cannot remove a PUBLIC
--    grant: anon kept execute by inheritance on twelve SECURITY DEFINER
--    functions. Removing PUBLIC does not break the app — every function
--    below also carries an explicit `authenticated` grant, and the app
--    signs in (anonymously) at boot, so its callers are `authenticated`.
--    report_error keeps its explicit anon grant and is left alone;
--    support_kb_lookup is anonymous by design and is left alone.

begin;

create or replace function public.search_users(p_query text, p_limit integer default 10)
returns table(user_id uuid, username text, display_name text, avatar_url text)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_clean text := lower(trim(p_query));
begin
  if length(v_clean) < 2 then
    return;
  end if;

  return query
  select p.user_id, p.username, p.name as display_name, p.avatar as avatar_url
  from public.profiles p
  where p.username is not null
    and p.user_id <> auth.uid()
    and p.username_lower % v_clean
  order by similarity(p.username_lower, v_clean) desc
  limit least(p_limit, 20);
end;
$function$;

revoke all on function public.admin_ban_user(uuid, text, integer, text) from public;
revoke all on function public.admin_unban_user(uuid) from public;
revoke all on function public.admin_user_reports(integer, text) from public;
revoke all on function public.admin_dismiss_user_reports(uuid) from public;
revoke all on function public.ban_appeal_decide(uuid, boolean, text) from public;
revoke all on function public.ban_appeals_pending() from public;
revoke all on function public.ban_appeal_submit(text) from public;
revoke all on function public.report_user(uuid, text, jsonb) from public;
revoke all on function public.search_users(text, integer) from public;
revoke all on function public.am_i_banned() from public;

commit;
