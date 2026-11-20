-- Dizzy v1.4.3 — legal acceptance is recorded, not just remembered locally.
-- Run: supabase db query --linked -f supabase/migrations/20261121_legal_acceptance.sql
--
-- Problem: the onboarding sheet had no agreement step at all, and the
-- "onboarded" flag is a local bool with no version. So there was no answer to
-- "which privacy text did this person actually agree to, and when?" — and a
-- privacy-text change could never re-prompt anyone.
--
-- This adds an append-only acceptance ledger:
--   * one row per (user, version) — re-accepting the same version is a no-op,
--     so the timestamp stays the FIRST time they agreed, which is the one that
--     matters as evidence;
--   * the device code, platform and app version travel with the row so an
--     acceptance can still be attributed after a reinstall rotates the uid;
--   * no IP address, no user agent, no free text — nothing that turns a
--     consent record into a tracking record.
--
-- Rows are never purged: an acceptance is the evidence, and retention jobs must
-- not delete it. Only the person themselves can erase it, via
-- delete_my_legal_acceptance() — the erasure right has to win over the record.

create table if not exists public.legal_acceptances (
  id bigserial primary key,
  user_id uuid not null default auth.uid(),
  device_code text,
  version text not null,
  terms_version text,
  privacy_version text,
  platform text,
  app_version text,
  accepted_at timestamptz not null default now(),
  constraint legal_acceptances_once unique (user_id, version)
);

create index if not exists legal_acceptances_recent_idx
  on public.legal_acceptances (accepted_at desc);

create index if not exists legal_acceptances_device_idx
  on public.legal_acceptances (device_code, accepted_at desc);

alter table public.legal_acceptances enable row level security;

-- Read your own acceptances (Settings → Privacy shows the date; a reinstall on
-- a new uid still sees the record once it signs back in).
drop policy if exists legal_acceptances_read_own on public.legal_acceptances;
create policy legal_acceptances_read_own on public.legal_acceptances
  for select to authenticated
  using (user_id = auth.uid());

-- Admins read everything (support: "did they accept v2 before they signed up?").
drop policy if exists legal_acceptances_read_admin on public.legal_acceptances;
create policy legal_acceptances_read_admin on public.legal_acceptances
  for select to authenticated
  using (is_admin());

-- No insert/update/delete policy on purpose: rows are written only by
-- record_acceptance() (security definer) and removed only by an admin delete,
-- so a client cannot backdate or forge its own acceptance.

create or replace function public.record_acceptance(
  p_version text,
  p_terms_version text default null,
  p_privacy_version text default null,
  p_device_code text default null,
  p_platform text default null,
  p_app_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ver text := nullif(btrim(coalesce(p_version, '')), '');
  v_row public.legal_acceptances;
begin
  if v_ver is null then
    raise exception 'version required';
  end if;
  if v_uid is null then
    raise exception 'sign-in required';
  end if;

  insert into public.legal_acceptances (
    user_id, device_code, version, terms_version, privacy_version,
    platform, app_version
  )
  values (
    v_uid,
    nullif(btrim(coalesce(p_device_code, '')), ''),
    v_ver,
    nullif(btrim(coalesce(p_terms_version, '')), ''),
    nullif(btrim(coalesce(p_privacy_version, '')), ''),
    nullif(btrim(coalesce(p_platform, '')), ''),
    nullif(btrim(coalesce(p_app_version, '')), '')
  )
  on conflict (user_id, version) do nothing;

  select * into v_row
    from public.legal_acceptances
   where user_id = v_uid
     and version = v_ver;

  return jsonb_build_object(
    'version', v_row.version,
    'terms_version', v_row.terms_version,
    'privacy_version', v_row.privacy_version,
    'accepted_at', v_row.accepted_at
  );
end;
$$;

revoke all on function public.record_acceptance(text, text, text, text, text, text) from public;
grant execute on function public.record_acceptance(text, text, text, text, text, text) to authenticated;

comment on function public.record_acceptance(text, text, text, text, text, text) is
  'Records this user''s acceptance of a legal text version. Idempotent per (user, version); keeps the first accepted_at.';

-- Latest acceptance for the signed-in user — Settings → Privacy reads this so
-- the date shown is the server's, not a local guess.
create or replace function public.my_legal_acceptance()
returns jsonb
language sql
stable security definer
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object(
              'version', a.version,
              'terms_version', a.terms_version,
              'privacy_version', a.privacy_version,
              'accepted_at', a.accepted_at,
              'device_code', a.device_code
            )
       from public.legal_acceptances a
      where a.user_id = auth.uid()
      order by a.accepted_at desc
      limit 1),
    'null'::jsonb
  );
$$;

revoke all on function public.my_legal_acceptance() from public;
grant execute on function public.my_legal_acceptance() to authenticated;

comment on function public.my_legal_acceptance() is
  'Newest legal acceptance for auth.uid(), or null. Powers Settings → Privacy.';

-- Panel: who agreed to what, newest first.
create or replace function public.admin_legal_acceptances(
  p_limit integer default 100,
  p_search text default ''
)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare
  v jsonb;
  v_search text := btrim(coalesce(p_search, ''));
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t order by t.accepted_at desc), '[]'::jsonb)
    into v
    from (
      select a.id,
             a.user_id,
             a.device_code,
             a.version,
             a.terms_version,
             a.privacy_version,
             a.platform,
             a.app_version,
             a.accepted_at,
             un.username,
             (select count(*)
                from public.legal_acceptances a2
               where a2.user_id = a.user_id) as acceptance_count
        from public.legal_acceptances a
        left join public.usernames un
          on un.user_id = a.user_id
       where (v_search = ''
              or a.version ilike '%' || v_search || '%'
              or coalesce(a.device_code, '') ilike '%' || v_search || '%'
              or coalesce(a.platform, '') ilike '%' || v_search || '%'
              or coalesce(un.username, '') ilike '%' || v_search || '%'
              or a.user_id::text ilike '%' || v_search || '%')
       order by a.accepted_at desc
       limit greatest(p_limit, 1)
    ) t;
  return v;
end;
$$;

revoke all on function public.admin_legal_acceptances(int, text) from public;
grant execute on function public.admin_legal_acceptances(int, text) to authenticated;

comment on function public.admin_legal_acceptances(int, text) is
  'Admin dashboard: legal acceptance ledger with @username and device code.';

-- Erasure: "delete my cloud data" must really delete it. Kept as a function
-- (not a delete policy) so the only way in is a signed-in caller acting on
-- their own uid — nobody can delete someone else's acceptance, and nothing can
-- backdate one.
create or replace function public.delete_my_legal_acceptance()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer := 0;
begin
  if v_uid is null then
    raise exception 'sign-in required';
  end if;
  delete from public.legal_acceptances where user_id = v_uid;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.delete_my_legal_acceptance() from public;
grant execute on function public.delete_my_legal_acceptance() to authenticated;

comment on function public.delete_my_legal_acceptance() is
  'Deletes auth.uid()''s own legal acceptances (GDPR erasure). Returns rows removed.';
