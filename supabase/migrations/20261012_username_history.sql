-- Dizzy v1.3.3 T1.1 — username durability + identity history.
-- Run: supabase db query --linked -f supabase/migrations/20261012_username_history.sql
--
-- Fixes (audit 2026-10-12):
--   1) claimUsername only set in-memory state — reopen lost it. Fix: usernames
--      table (one row per user) + app persists + boot reloads.
--   2) old claim_username RPC returned success:true even when zero rows were
--      updated (no row existed). Fix: insert-if-missing + real rowcount logic.
--   3) cloud rows never reached the UI model. Fix: boot loader reads usernames.
-- Adds:
--   profiles.updated_at (last-write-wins for display-name/avatar sync)
--   identity_history (username/display_name/avatar changes, old -> new)
--   admin_user_identity + admin_identity_tail RPCs (is_admin gated)
--
-- ═══════════ 1) profiles.updated_at (LWW) ═══════════
alter table public.profiles
  add column if not exists updated_at timestamptz not null default now();

-- Backfill so last-write-wins starts fair: existing rows compare by their
-- real creation time, not by migration-run time.
update public.profiles set updated_at = created_at;

-- ═══════════ 2) usernames: one social identity per user ═══════════
create table if not exists public.usernames (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  username_lower text generated always as (lower(username)) stored,
  last_change_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create unique index if not exists idx_usernames_lower_uq
  on public.usernames(username_lower);
alter table public.usernames enable row level security;
drop policy if exists "user rw own username" on public.usernames;
create policy "user rw own username" on public.usernames
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Migrate existing claims from profiles.username (old RPC wrote all rows
-- of a user with the same value, so distinct on user_id is safe).
insert into public.usernames(user_id, username, last_change_at)
select distinct on (user_id)
  user_id, lower(trim(username)), coalesce(last_username_change_at, now())
from public.profiles
where username is not null and trim(username) <> ''
order by user_id
on conflict (user_id) do nothing;

-- ═══════════ 3) identity_history ═══════════
create table if not exists public.identity_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('username', 'display_name', 'avatar')),
  old_value text,
  new_value text,
  profile_id text,
  created_at timestamptz not null default now()
);
create index if not exists idx_identity_history_user
  on public.identity_history(user_id, created_at desc);
alter table public.identity_history enable row level security;
drop policy if exists "user read own history" on public.identity_history;
create policy "user read own history" on public.identity_history
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "user insert own history" on public.identity_history;
create policy "user insert own history" on public.identity_history
  for insert to authenticated with check (auth.uid() = user_id);

-- Seed: every migrated username gets a first history row so the admin
-- console shows "default (auto) -> claimed name" from day one.
insert into public.identity_history(user_id, kind, old_value, new_value)
select u.user_id, 'username', 'auto-generated', u.username
from public.usernames u
where not exists (
  select 1 from public.identity_history h
  where h.user_id = u.user_id and h.kind = 'username'
);

-- ═══════════ 4) claim_username rewrite ═══════════
-- Same rules as before (format, reserved, 1 rename / 7 days) PLUS:
-- insert-if-missing, same-name early success (no history spam, no limit
-- bump), history row on every real change, unique-race guard.
create or replace function public.claim_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(trim(p_username));
  v_old text;
  v_last timestamptz;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Authentication required');
  end if;

  if not (v_clean ~ '^[a-z0-9_]{3,20}$') then
    return jsonb_build_object('success', false, 'error', 'Username must be 3-20 letters, numbers, or underscores');
  end if;

  if v_clean in ('admin', 'dizzy', 'official', 'support', 'help', 'system', 'root') then
    return jsonb_build_object('success', false, 'error', 'This username is reserved');
  end if;

  select username, last_change_at into v_old, v_last
  from public.usernames where user_id = v_uid;

  -- Same name again: success, no history, no limit bump.
  if v_old = v_clean then
    return jsonb_build_object('success', true, 'username', v_clean);
  end if;

  -- Rate limit: 1 rename every 7 days (only when a row already exists).
  if v_last is not null and v_last > now() - interval '7 days' then
    return jsonb_build_object('success', false, 'error', 'You can only change username once every 7 days');
  end if;

  -- Taken by someone else?
  if exists (select 1 from public.usernames
             where username_lower = v_clean and user_id <> v_uid) then
    return jsonb_build_object('success', false, 'error', 'This username is already taken');
  end if;

  begin
    if v_old is null then
      insert into public.usernames(user_id, username)
      values (v_uid, v_clean);
    else
      update public.usernames
      set username = v_clean, last_change_at = now()
      where user_id = v_uid;
    end if;
  exception when unique_violation then
    return jsonb_build_object('success', false, 'error', 'This username is already taken');
  end;

  insert into public.identity_history(user_id, kind, old_value, new_value)
  values (v_uid, 'username', coalesce(v_old, 'auto-generated'), v_clean);

  return jsonb_build_object('success', true, 'username', v_clean);
end;
$$;
revoke all on function public.claim_username(text) from public;
grant execute on function public.claim_username(text) to authenticated;

-- ═══════════ 5) admin RPCs (is_admin gated) ═══════════
-- Lookup by @username, user_id, device code, or profile display name.
create or replace function public.admin_user_identity(p_search text default '')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
  q text := '%' || trim(coalesce(p_search, '')) || '%';
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t order by t.last_change_at desc), '[]'::jsonb)
  into v from (
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
      where q = '%%'
         or u.username ilike q
         or u.user_id::text ilike q
         or exists (select 1 from public.devices d
                    where d.user_id = u.user_id and d.device_code ilike q)
         or exists (select 1 from public.profiles p
                    where p.user_id = u.user_id and p.name ilike q)
      order by u.last_change_at desc
      limit 20
    ) top
  ) t;
  return v;
end;
$$;
revoke all on function public.admin_user_identity(text) from public;
grant execute on function public.admin_user_identity(text) to authenticated;

-- Newest identity changes across the fleet (audit-page feed).
create or replace function public.admin_identity_tail(p_limit int default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t order by t.at desc), '[]'::jsonb) into v from (
    select h.user_id, u.username, h.kind, h.old_value, h.new_value,
           h.profile_id, h.created_at as at
    from public.identity_history h
    left join public.usernames u on u.user_id = h.user_id
    order by h.created_at desc
    limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;
revoke all on function public.admin_identity_tail(int) from public;
grant execute on function public.admin_identity_tail(int) to authenticated;
