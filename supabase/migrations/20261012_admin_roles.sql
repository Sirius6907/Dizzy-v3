-- v1.3.3-T2.0 — per-admin accounts + roles.
--
-- Roles: owner (all) > support (tickets/announcements) > curator
-- (playlists/shelves/music remote-config) > viewer (read-only).
--
-- Back-compat: legacy `admins` allowlist rows are backfilled as owners.
-- `is_admin()` now covers BOTH tables so every existing RLS policy and
-- RPC keeps working unchanged. New role-gated writes use require_role().
--
-- Idempotent: IF NOT EXISTS / CREATE OR REPLACE / ON CONFLICT DO NOTHING.

-- ═══════════ 1) admin_users ═══════════
create table if not exists admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'viewer'
    check (role in ('owner', 'support', 'curator', 'viewer')),
  created_at timestamptz not null default now()
);
alter table admin_users enable row level security;

drop policy if exists "admin_users self-read" on admin_users;
create policy "admin_users self-read" on admin_users
  for select to authenticated using (auth.uid() = user_id);

-- Legacy admins become owners (first owner must exist before the old
-- single-password model can be retired — see plan T2.0 lockout rule).
insert into admin_users(user_id, role)
select user_id, 'owner' from admins
on conflict (user_id) do nothing;

-- ═══════════ 2) role helpers ═══════════
-- Own role: admin_users first, legacy admins table falls back to owner.
create or replace function admin_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from admin_users where user_id = auth.uid()),
    (select 'owner' from admins where user_id = auth.uid()),
    null);
$$;
revoke all on function admin_role() from public;
grant execute on function admin_role() to authenticated;

-- is_admin() now covers both tables (existing policies/RPCs untouched).
create or replace function is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from admins where user_id = auth.uid())
      or exists (select 1 from admin_users where user_id = auth.uid());
$$;
revoke all on function is_admin() from public;
grant execute on function is_admin() to anon, authenticated;

-- Gate: raise unless caller holds one of the allowed roles.
create or replace function require_role(allowed text[])
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_role text;
begin
  v_role := admin_role();
  if v_role is null then raise exception 'admin only'; end if;
  if not (v_role = any (allowed)) then raise exception 'role denied'; end if;
  return v_role;
end;
$$;
revoke all on function require_role(text[]) from public;
grant execute on function require_role(text[]) to authenticated;

-- Dashboard calls this once after login (role badge + tab gating).
create or replace function my_admin_role()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  return coalesce(admin_role(), 'owner');
end;
$$;
revoke all on function my_admin_role() from public;
grant execute on function my_admin_role() to authenticated;

-- ═══════════ 3) role-gate the existing write RPCs ═══════════
-- Config: owner full; curator music/scraper/ranking/feature keys only;
-- support/viewer denied. Single allowlist — no stacked checks (an earlier
-- draft had two sequential curator gates, so their INTERSECTION silently
-- locked out keys the first list allowed). Fail-closed: a key matching
-- neither the exact list nor a curator prefix stays owner-only.
create or replace function admin_set_config(p_key text, p_value text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role  text;
  v_key   text := lower(btrim(coalesce(p_key, '')));
  -- Curator-editable exact keys + prefixes (values only, never app code).
  c_curator_exact text[] := array[
    'music_shelves_layout', 'music_endpoints',
    'scraper_urls', 'scraper_regex', 'ranking_weights',
    'feature_flags', 'support_faq_bundle_version'
  ];
begin
  v_role := require_role(array['owner', 'curator']);

  if v_key = '' or v_key !~ '^[a-z0-9_.]+$' or char_length(v_key) > 64 then
    raise exception 'bad key';
  end if;

  if v_role = 'curator'
     and not (v_key = any (c_curator_exact))
     and v_key !~ '^(music|scraper|ranking|feature)_' then
    raise exception 'role denied';
  end if;

  insert into remote_config(key, value, updated_at, updated_by)
    values (v_key, p_value, now(), auth.uid())
    on conflict (key) do update set value=excluded.value, updated_at=now(), updated_by=auth.uid();
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'config:set', v_key, jsonb_build_object('value', left(p_value, 2000)));
  return true;
end;
$$;
revoke all on function admin_set_config(text, text) from public;
grant execute on function admin_set_config(text, text) to authenticated;

-- Announcements: owner + support.
create or replace function admin_announce_upsert(
  p_id text, p_title text, p_body text, p_url text,
  p_min_version text, p_max_version text, p_active boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  perform require_role(array['owner', 'support']);
  if nullif(p_id,'') is null then
    insert into announcements(title, body, url, min_version, max_version, active)
      values (p_title, p_body, nullif(p_url,''), p_min_version, p_max_version, p_active)
      returning id into v_id;
  else
    v_id := p_id::uuid;
    update announcements set title=p_title, body=p_body, url=nullif(p_url,''),
      min_version=p_min_version, max_version=p_max_version, active=p_active
      where id = v_id;
  end if;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'announce:upsert', v_id::text,
            jsonb_build_object('title', left(p_title,200), 'active', p_active));
  return v_id::text;
end;
$$;
revoke all on function admin_announce_upsert(text, text, text, text, text, text, boolean) from public;
grant execute on function admin_announce_upsert(text, text, text, text, text, text, boolean) to authenticated;

create or replace function admin_announce_delete(p_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform require_role(array['owner', 'support']);
  delete from announcements where id = p_id::uuid;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'announce:delete', p_id, '{}');
  return found;
end;
$$;
revoke all on function admin_announce_delete(text) from public;
grant execute on function admin_announce_delete(text) to authenticated;

-- ═══════════ 4) owner-only admin membership management ═══════════
-- Add/change/remove admin_users rows. First owner comes from the
-- backfill above; old single-password removal happens only after an
-- owner login is proven (plan T2.0 lockout rule).
create or replace function admin_user_upsert(p_email text, p_role text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid;
begin
  perform require_role(array['owner']);
  if p_role not in ('owner', 'support', 'curator', 'viewer') then
    raise exception 'bad role';
  end if;
  select id into v_uid from auth.users where email = lower(btrim(p_email));
  if v_uid is null then raise exception 'no such user'; end if;
  insert into admin_users(user_id, role)
    values (v_uid, p_role)
    on conflict (user_id) do update set role = excluded.role;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'admin:upsert', v_uid::text, jsonb_build_object('role', p_role));
  return v_uid;
end;
$$;
revoke all on function admin_user_upsert(text, text) from public;
grant execute on function admin_user_upsert(text, text) to authenticated;

create or replace function admin_user_remove(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform require_role(array['owner']);
  if p_user_id = auth.uid() then raise exception 'cannot remove self'; end if;
  delete from admin_users where user_id = p_user_id;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'admin:remove', p_user_id::text, '{}');
  return found;
end;
$$;
revoke all on function admin_user_remove(uuid) from public;
grant execute on function admin_user_remove(uuid) to authenticated;

create or replace function admin_user_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  perform require_role(array['owner']);
  select coalesce(jsonb_agg(t order by t.created_at), '[]'::jsonb) into v
    from (select u.user_id, u.role, u.created_at,
                 (select email from auth.users a where a.id = u.user_id) as email
          from admin_users u) t;
  return v;
end;
$$;
revoke all on function admin_user_list() from public;
grant execute on function admin_user_list() to authenticated;
