-- Dizzy v1.3.5 — social fixes: friend names resolve, DMs become real.
--
-- Problem: friendships rows carry only uids. `profiles` is owner-only RLS,
-- so a client can never read a friend's @username by uid — the friends
-- list fell back to `friend_<6 chars of uid>` ("gibberish names").
--
-- Fix: `resolve_usernames(uuid[])` — the same read the app already trusts
-- from `search_users`, scoped to an explicit uid list. SECURITY DEFINER so
-- the join can read `usernames`/`profiles`, but only for the uids the
-- caller names, and only the three display fields leave the database.

create or replace function public.resolve_usernames(
  p_uids uuid[]
)
returns table(uid uuid, username text, display_name text, avatar_url text)
language sql
security definer
set search_path = public
stable
as $function$
  select u.user_id,
         u.username,
         coalesce(p.name, ''),
         p.avatar
  from unnest(
         coalesce(p_uids, '{}'::uuid[])
       ) as wanted(uid)
  join public.usernames u
    on u.user_id = wanted.uid
  left join lateral (
    select pr.name, pr.avatar
    from public.profiles pr
    where pr.user_id = u.user_id
    order by pr.updated_at desc nulls last, pr.profile_id desc
    limit 1
  ) p on true
  where wanted.uid <> auth.uid()
  limit 50;
$function$;

revoke all on function public.resolve_usernames(uuid[]) from public;
revoke all on function public.resolve_usernames(uuid[]) from anon;
grant execute on function public.resolve_usernames(uuid[]) to authenticated;
