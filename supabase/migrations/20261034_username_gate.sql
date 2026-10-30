-- Dizzy v1.3.3 — first-run @username gate (server half).
-- Run: supabase db query --linked -f supabase/migrations/20261034_username_gate.sql
-- then record the history row (never `db push`).
--
-- Three changes, all additive to behaviour:
--   1. claim_username returns a machine `code` so the app can say the right
--      thing without matching English prose. Rules are unchanged: 3-20
--      [a-z0-9_], reserved words, first claim free, 1 rename / 7 days.
--   2. username_available(): the client cannot read other users' usernames
--      (RLS is own-row), so live "is this free?" needs a server answer.
--   3. device_boot reports the previous owner of this physical device
--      (guest only, name only when one exists) so a reinstall can offer
--      "Welcome back, @name?" instead of forcing a second, duplicate claim
--      and leaving the first one on an unreachable anonymous uid.
--      The data move itself stays in the audited merge_devices RPC.

-- ═══════════ 1) claim_username: same rules, machine codes ═══════════
create or replace function public.claim_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(trim(coalesce(p_username, '')));
  v_old text;
  v_last timestamptz;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'code', 'auth', 'error', 'Authentication required');
  end if;

  if not (v_clean ~ '^[a-z0-9_]{3,20}$') then
    return jsonb_build_object('success', false, 'code', 'format', 'error', 'Username must be 3-20 letters, numbers, or underscores');
  end if;

  if v_clean in ('admin', 'dizzy', 'official', 'support', 'help', 'system', 'root') then
    return jsonb_build_object('success', false, 'code', 'reserved', 'error', 'This username is reserved');
  end if;

  select username, last_change_at into v_old, v_last
  from public.usernames where user_id = v_uid;

  -- Same name again: success, no history, no limit bump.
  if v_old = v_clean then
    return jsonb_build_object('success', true, 'code', 'ok', 'username', v_clean);
  end if;

  -- Rate limit: 1 rename every 7 days (only when a row already exists, so
  -- the very first claim is always free).
  if v_last is not null and v_last > now() - interval '7 days' then
    return jsonb_build_object('success', false, 'code', 'ratelimited', 'error', 'You can only change username once every 7 days');
  end if;

  if exists (select 1 from public.usernames
             where username_lower = v_clean and user_id <> v_uid) then
    return jsonb_build_object('success', false, 'code', 'taken', 'error', 'This username is already taken');
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
    return jsonb_build_object('success', false, 'code', 'taken', 'error', 'This username is already taken');
  end;

  insert into public.identity_history(user_id, kind, old_value, new_value)
  values (v_uid, 'username', coalesce(v_old, 'auto-generated'), v_clean);

  return jsonb_build_object('success', true, 'code', 'ok', 'username', v_clean);
end;
$$;
revoke all on function public.claim_username(text) from public;
grant execute on function public.claim_username(text) to authenticated;

-- ═══════════ 2) username_available ═══════════
-- `available` is null (not false) when we refused to answer, so the UI
-- never blocks a real name on a slow client. 60 checks/min is generous for
-- debounced typing and cheap for a token bucket.
create or replace function public.username_available(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(trim(coalesce(p_username, '')));
begin
  if v_uid is null then
    return jsonb_build_object('available', false, 'reason', 'auth');
  end if;
  if not public.take_token('uname_check:' || v_uid::text, 60, 1) then
    return jsonb_build_object('available', null, 'reason', 'rate_limited');
  end if;
  if not (v_clean ~ '^[a-z0-9_]{3,20}$') then
    return jsonb_build_object('available', false, 'reason', 'format');
  end if;
  if v_clean in ('admin', 'dizzy', 'official', 'support', 'help', 'system', 'root') then
    return jsonb_build_object('available', false, 'reason', 'reserved');
  end if;
  if exists (select 1 from public.usernames
             where username_lower = v_clean and user_id <> v_uid) then
    return jsonb_build_object('available', false, 'reason', 'taken');
  end if;
  return jsonb_build_object('available', true, 'reason', 'ok');
end;
$$;
revoke all on function public.username_available(text) from public;
revoke all on function public.username_available(text) from anon;
grant execute on function public.username_available(text) to authenticated;

-- ═══════════ 3) device_boot: report the previous owner ═══════════
-- Return shape changes, so drop + recreate (same pattern as 20261010).
drop function if exists public.device_boot(text, text, boolean, text, text, text, text);
create or replace function public.device_boot(
  p_hwid_hash   text,
  p_hwid_legacy text default '',
  p_hwid_stable boolean default true,
  p_device_code text default '',
  p_sid         text default '',
  p_platform    text default 'unknown',
  p_app_version text default 'unknown'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_row       public.devices%rowtype;
  v_has_row   boolean := false;
  v_merged    boolean := false;
  v_revoked   boolean := false;
  v_adult     boolean := false;
  v_prev_uid  uuid;
  v_prev_name text;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'auth required');
  end if;
  if p_hwid_hash is null or length(p_hwid_hash) < 16 then
    return jsonb_build_object('success', false, 'error', 'bad hwid');
  end if;

  -- Identity ledger: a guest session is recorded as an unverified 'anon'
  -- identity. merge_devices uses this to prove the old side was a guest.
  insert into public.identities (user_id, kind, identifier_hash, verified_at)
  values (v_uid, 'anon', left(p_hwid_hash, 128), null)
  on conflict (user_id, kind) do nothing;

  -- (a) exact stable-hwid match
  select * into v_row from public.devices
  where hwid_hash = p_hwid_hash
  for update;
  v_has_row := found;

  -- (b) pre-H legacy row (hash of old random code) → adopt under new hash
  if not v_has_row and p_hwid_legacy <> '' then
    select * into v_row from public.devices
    where hwid_legacy = p_hwid_legacy
      and (hwid_stable = false or hwid_hash is null or hwid_hash = '')
    order by last_seen_at desc nulls last
    limit 1
    for update;
    v_has_row := found;
    if v_has_row then
      update public.devices
      set hwid_hash = p_hwid_hash, hwid_stable = p_hwid_stable
      where device_id = v_row.device_id;
      v_row.hwid_hash := p_hwid_hash;
      v_merged := true;
    end if;
  end if;

  -- (c) row exists but belongs to another session (reinstall) → auto-merge.
  -- Before re-pointing the row, remember who owned it. A verified account
  -- is never offered as "welcome back" (it can sign in); only guests are.
  if v_has_row and v_row.user_id is distinct from v_uid then
    if exists (select 1 from auth.users u
               where u.id = v_row.user_id and coalesce(u.is_anonymous, false)) then
      v_prev_uid := v_row.user_id;
      select username into v_prev_name
      from public.usernames where user_id = v_prev_uid;
    end if;

    if v_row.hwid_stable and p_hwid_stable
       and to_regclass('public.continue_watching') is not null then
      insert into public.continue_watching
        (user_id, content_id, progress_ms, duration_ms, updated_at)
      select v_uid, content_id, progress_ms, duration_ms, updated_at
      from public.continue_watching
      where user_id = v_row.user_id
      on conflict (user_id, content_id) do update
        set progress_ms = greatest(public.continue_watching.progress_ms,
                                   excluded.progress_ms),
            updated_at  = greatest(public.continue_watching.updated_at,
                                   excluded.updated_at);
      delete from public.continue_watching where user_id = v_row.user_id;
      v_merged := true;
    end if;
    update public.devices set user_id = v_uid
    where device_id = v_row.device_id;
    v_row.user_id := v_uid;
  end if;

  -- (d) touch / insert. Uses the row handle, not FOUND, because the
  -- username lookup above deliberately changes FOUND.
  if v_has_row then
    update public.devices
    set device_code  = coalesce(nullif(p_device_code, ''), v_row.device_code),
        sid          = coalesce(nullif(p_sid, ''), v_row.sid),
        platform     = coalesce(nullif(p_platform, ''), v_row.platform),
        app_version  = coalesce(nullif(p_app_version, ''), v_row.app_version),
        hwid_stable  = p_hwid_stable,
        last_seen_at = now()
    where device_id = v_row.device_id;
  else
    begin
      insert into public.devices
        (user_id, device_code, hwid_hash, hwid_legacy, hwid_stable,
         sid, platform, app_version, last_seen_at)
      values
        (v_uid,
         coalesce(nullif(p_device_code,''), '0000000'),
         p_hwid_hash, nullif(p_hwid_legacy,''),
         p_hwid_stable,
         coalesce(nullif(p_sid,''), 'DIZ-' || substring(p_hwid_hash from 1 for 16)),
         p_platform, p_app_version, now());
    exception when unique_violation then
      update public.devices
      set user_id     = v_uid,
          device_code = coalesce(nullif(p_device_code,''), device_code),
          sid         = coalesce(nullif(p_sid,''), sid),
          app_version = coalesce(nullif(p_app_version,''), app_version),
          hwid_stable = p_hwid_stable,
          last_seen_at = now()
      where hwid_hash = p_hwid_hash
      returning revoked_at, adult_allowed into v_revoked, v_adult;
      return jsonb_build_object(
        'success', true,
        'revoked', coalesce(v_revoked, false),
        'merged', v_merged,
        'adult_allowed', coalesce(v_adult, false),
        'previous_uid', null,
        'previous_username', null);
    end;
  end if;

  select revoked_at is not null, coalesce(adult_allowed, false)
  into v_revoked, v_adult
  from public.devices where hwid_hash = p_hwid_hash;

  return jsonb_build_object(
    'success', true,
    'revoked', coalesce(v_revoked, false),
    'merged', v_merged,
    'adult_allowed', coalesce(v_adult, false),
    'previous_uid', v_prev_uid,
    'previous_username', v_prev_name);
end;
$$;
revoke all on function public.device_boot(text, text, boolean, text, text, text, text) from public;
revoke all on function public.device_boot(text, text, boolean, text, text, text, text) from anon;
grant execute on function public.device_boot(text, text, boolean, text, text, text, text)
  to authenticated;
