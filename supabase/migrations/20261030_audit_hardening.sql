-- Dizzy v1.3.3 — pre-release audit hardening.
-- Run with: supabase db push   (or: supabase db query --linked -f <this file>)
--
-- Fixes verified against the live schema files:
--   1. dm_threads / dm_messages had SELECT-only RLS, so every DM send failed.
--   2. device_boot wrote to public.continue_watching, a table that has never
--      existed, so every boot raised "relation does not exist".
--   3. merge_devices(uuid, uuid) was executable by any signed-in user with two
--      arbitrary uids — a one-call account takeover / data wipe.
--   4. cloud_sessions / cloud_backups used `on conflict do nothing` and then
--      deleted the old rows, silently dropping watch progress.
--   5. take_token, claim_username and search_users were SECURITY DEFINER
--      without a pinned search_path; take_token was PUBLIC-executable.
--   6. dm_messages / friendships were missing from the realtime publication,
--      so live DMs and friend requests never arrived.
--   7. Hot foreign keys had no indexes (see section 7).
--   8. admin_find_user queried installs.user_id (no such column), so the
--      dashboard's device-code search crashed; admin_devices never selected
--      the activity column the panel renders.
--   9. The app's Restore page called issue_restore_code / redeem_restore_code,
--      which did not exist — the whole "new phone" flow was dead.

begin;

-- ═══════════ 1) Direct messages: writers were never allowed ═══════════
drop policy if exists "Participants create DM threads" on public.dm_threads;
create policy "Participants create DM threads"
  on public.dm_threads for insert
  with check (auth.uid() = user1_id or auth.uid() = user2_id);

-- The client upserts the thread on every send; the conflict branch is an
-- UPDATE and needs its own policy.
drop policy if exists "Participants touch their DM threads" on public.dm_threads;
create policy "Participants touch their DM threads"
  on public.dm_threads for update
  using (auth.uid() = user1_id or auth.uid() = user2_id)
  with check (auth.uid() = user1_id or auth.uid() = user2_id);

drop policy if exists "Participants send DM messages" on public.dm_messages;
create policy "Participants send DM messages"
  on public.dm_messages for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1
      from public.dm_threads t
      where t.thread_id = dm_messages.thread_id
        and (t.user1_id = auth.uid() or t.user2_id = auth.uid())
    )
  );

-- ═══════════ 2) device_boot: no phantom table, and fill the identity ledger ═══
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
  v_uid     uuid := auth.uid();
  v_row     public.devices%rowtype;
  v_merged  boolean := false;
  v_revoked boolean := false;
  v_adult   boolean := false;
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

  -- (b) pre-H legacy row (hash of old random code) → adopt under new hash
  if not found then
    select * into v_row from public.devices
    where hwid_legacy = p_hwid_legacy and p_hwid_legacy <> ''
      and (hwid_stable = false or hwid_hash is null or hwid_hash = '')
    order by last_seen_at desc nulls last
    limit 1
    for update;
    if found then
      update public.devices
      set hwid_hash = p_hwid_hash, hwid_stable = p_hwid_stable
      where device_id = v_row.device_id;
      v_row.hwid_hash := p_hwid_hash;
      v_merged := true;
    end if;
  end if;

  -- (c) row exists but belongs to another session (reinstall) → auto-merge
  if found and v_row.user_id is distinct from v_uid then
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

  -- (d) touch / insert
  if found then
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
        'adult_allowed', coalesce(v_adult, false));
    end;
  end if;

  select revoked_at is not null, coalesce(adult_allowed, false)
  into v_revoked, v_adult
  from public.devices where hwid_hash = p_hwid_hash;

  return jsonb_build_object(
    'success', true,
    'revoked', coalesce(v_revoked, false),
    'merged', v_merged,
    'adult_allowed', coalesce(v_adult, false));
end;
$$;
revoke all on function public.device_boot(text, text, boolean, text, text, text, text) from public;
revoke all on function public.device_boot(text, text, boolean, text, text, text, text) from anon;
grant execute on function public.device_boot(text, text, boolean, text, text, text, text)
  to authenticated;

-- Backfill the ledger for guests that booted before this migration.
insert into public.identities (user_id, kind, identifier_hash, verified_at)
select u.id, 'anon', left(u.id::text, 128), null
from auth.users u
where coalesce(u.is_anonymous, false)
on conflict (user_id, kind) do nothing;

-- ═══════════ 3) merge_devices: caller-owned, guest-only, lossless ═══════════
create or replace function public.merge_devices(
  p_old_anon_uid uuid,
  p_canonical_uid uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_old_anon_uid is null or p_canonical_uid is null
     or p_old_anon_uid = p_canonical_uid then
    return jsonb_build_object('success', false, 'error', 'Invalid merger parameters');
  end if;

  -- Only the account that is receiving the data may start the merge. The
  -- edge function calls with the service role; the app calls with the
  -- canonical user's own JWT. Nobody else can name two uids.
  if auth.uid() is distinct from p_canonical_uid
     and coalesce(auth.role(), '') <> 'service_role' then
    return jsonb_build_object('success', false, 'error', 'Not allowed');
  end if;

  -- The old side must still be a guest session. A verified account can never
  -- be folded into another uid, even if its uuid leaks.
  if not exists (
    select 1 from auth.users u
    where u.id = p_old_anon_uid and coalesce(u.is_anonymous, false)
  ) then
    return jsonb_build_object('success', false, 'error', 'Old session is not a guest');
  end if;

  -- Devices → canonical user.
  update public.devices d
  set user_id = p_canonical_uid
  where d.user_id = p_old_anon_uid
    and not exists (select 1 from public.devices e
                    where e.user_id = p_canonical_uid
                      and e.hwid_hash = d.hwid_hash);
  delete from public.devices where user_id = p_old_anon_uid;

  -- Guarded: the table does not exist on this project today.
  if to_regclass('public.continue_watching') is not null then
    insert into public.continue_watching (user_id, content_id, progress_ms, duration_ms, updated_at)
    select p_canonical_uid, content_id, progress_ms, duration_ms, updated_at
    from public.continue_watching
    where user_id = p_old_anon_uid
    on conflict (user_id, content_id) do update
    set progress_ms = greatest(public.continue_watching.progress_ms, excluded.progress_ms),
        updated_at = greatest(public.continue_watching.updated_at, excluded.updated_at);
    delete from public.continue_watching where user_id = p_old_anon_uid;
  end if;

  -- Profiles: newer updated_at wins per profile_id.
  insert into public.profiles
    (user_id, profile_id, name, avatar, is_kids, pin_hash, created_at, updated_at, username, last_username_change_at)
  select p_canonical_uid, profile_id, name, avatar, is_kids, pin_hash, created_at, updated_at, username, last_username_change_at
  from public.profiles
  where user_id = p_old_anon_uid
  on conflict (user_id, profile_id) do update
  set name = case when excluded.updated_at >= public.profiles.updated_at then excluded.name else public.profiles.name end,
      avatar = case when excluded.updated_at >= public.profiles.updated_at then excluded.avatar else public.profiles.avatar end,
      is_kids = case when excluded.updated_at >= public.profiles.updated_at then excluded.is_kids else public.profiles.is_kids end,
      pin_hash = case when excluded.updated_at >= public.profiles.updated_at then excluded.pin_hash else public.profiles.pin_hash end,
      username = case when excluded.updated_at >= public.profiles.updated_at then excluded.username else public.profiles.username end,
      updated_at = greatest(public.profiles.updated_at, excluded.updated_at);
  delete from public.profiles where user_id = p_old_anon_uid;

  -- Usernames: one row per user; keep the canonical row.
  insert into public.usernames(user_id, username, last_change_at)
  select p_canonical_uid, username, last_change_at
  from public.usernames
  where user_id = p_old_anon_uid
  on conflict (user_id) do nothing;
  delete from public.usernames where user_id = p_old_anon_uid;

  update public.identity_history
  set user_id = p_canonical_uid
  where user_id = p_old_anon_uid;

  -- Cross-device sessions: newest row wins as a whole, never just updated_at,
  -- so an older episode can't overwrite newer progress and a newer one can.
  insert into public.cloud_sessions
    (user_id, media_id, title, media_type, poster_url, backdrop_url, year, season, episode, episode_title, position_seconds, total_duration_seconds, updated_at)
  select p_canonical_uid, media_id, title, media_type, poster_url, backdrop_url, year, season, episode, episode_title, position_seconds, total_duration_seconds, updated_at
  from public.cloud_sessions
  where user_id = p_old_anon_uid
  on conflict (user_id, media_id) do update
  set title = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.title else public.cloud_sessions.title end,
      media_type = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.media_type else public.cloud_sessions.media_type end,
      poster_url = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.poster_url else public.cloud_sessions.poster_url end,
      backdrop_url = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.backdrop_url else public.cloud_sessions.backdrop_url end,
      year = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.year else public.cloud_sessions.year end,
      season = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.season else public.cloud_sessions.season end,
      episode = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.episode else public.cloud_sessions.episode end,
      episode_title = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.episode_title else public.cloud_sessions.episode_title end,
      position_seconds = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.position_seconds else public.cloud_sessions.position_seconds end,
      total_duration_seconds = case when excluded.updated_at >= public.cloud_sessions.updated_at then excluded.total_duration_seconds else public.cloud_sessions.total_duration_seconds end,
      updated_at = greatest(public.cloud_sessions.updated_at, excluded.updated_at);
  delete from public.cloud_sessions where user_id = p_old_anon_uid;

  -- Backups: newest snapshot wins; a blank one never replaces a real one.
  insert into public.cloud_backups (user_id, profile_id, payload, app_version, updated_at)
  select p_canonical_uid, profile_id, payload, app_version, updated_at
  from public.cloud_backups
  where user_id = p_old_anon_uid
  on conflict (user_id, profile_id) do update
  set payload = case when excluded.updated_at >= public.cloud_backups.updated_at then excluded.payload else public.cloud_backups.payload end,
      app_version = case when excluded.updated_at >= public.cloud_backups.updated_at then excluded.app_version else public.cloud_backups.app_version end,
      updated_at = greatest(public.cloud_backups.updated_at, excluded.updated_at);
  delete from public.cloud_backups where user_id = p_old_anon_uid;

  insert into public.consents (owner_user_id, telemetry, genre_prefs, crash, watch_party, updated_at)
  select p_canonical_uid, telemetry, genre_prefs, crash, watch_party, updated_at
  from public.consents
  where owner_user_id = p_old_anon_uid
  on conflict (owner_user_id) do nothing;
  delete from public.consents where owner_user_id = p_old_anon_uid;

  insert into public.genre_prefs (owner_user_id, genre, score, updated_at)
  select p_canonical_uid, genre, score, updated_at
  from public.genre_prefs
  where owner_user_id = p_old_anon_uid
  on conflict (owner_user_id, genre) do nothing;
  delete from public.genre_prefs where owner_user_id = p_old_anon_uid;

  if exists (select 1 from public.installs
             where owner_user_id = p_canonical_uid) then
    update public.installs c
    set last_seen_at = greatest(c.last_seen_at, o.last_seen_at)
    from public.installs o
    where c.owner_user_id = p_canonical_uid
      and o.owner_user_id = p_old_anon_uid;
    delete from public.installs where owner_user_id = p_old_anon_uid;
  else
    update public.installs
    set owner_user_id = p_canonical_uid
    where owner_user_id = p_old_anon_uid;
  end if;

  insert into public.identities (user_id, kind, identifier_hash, verified_at, created_at)
  select p_canonical_uid, kind, identifier_hash, verified_at, created_at
  from public.identities
  where user_id = p_old_anon_uid
  on conflict (user_id, kind) do nothing;
  delete from public.identities where user_id = p_old_anon_uid;

  delete from public.friendships
  where (requester_id = p_old_anon_uid and addressee_id = p_canonical_uid)
     or (requester_id = p_canonical_uid and addressee_id = p_old_anon_uid);
  update public.friendships f
  set requester_id = p_canonical_uid
  where f.requester_id = p_old_anon_uid
    and not exists (select 1 from public.friendships e
                    where e.requester_id = p_canonical_uid
                      and e.addressee_id = f.addressee_id);
  delete from public.friendships where requester_id = p_old_anon_uid;
  update public.friendships f
  set addressee_id = p_canonical_uid
  where f.addressee_id = p_old_anon_uid
    and not exists (select 1 from public.friendships e
                    where e.requester_id = f.requester_id
                      and e.addressee_id = p_canonical_uid);
  delete from public.friendships where addressee_id = p_old_anon_uid;

  update public.dm_threads set user1_id = p_canonical_uid
  where user1_id = p_old_anon_uid;
  update public.dm_threads set user2_id = p_canonical_uid
  where user2_id = p_old_anon_uid;
  -- A thread re-keyed on both sides would become a self-thread.
  delete from public.dm_threads where user1_id = user2_id;
  update public.dm_messages set sender_id = p_canonical_uid
  where sender_id = p_old_anon_uid;

  return jsonb_build_object('success', true, 'canonical_uid', p_canonical_uid);
end;
$$;
revoke all on function public.merge_devices(uuid, uuid) from public;
revoke all on function public.merge_devices(uuid, uuid) from anon;
grant execute on function public.merge_devices(uuid, uuid) to authenticated;

-- ═══════════ 4) Pin search_path, close PUBLIC execute ═══════════
alter function public.take_token(text, integer, integer) set search_path = public;
alter function public.claim_username(text) set search_path = public;
alter function public.search_users(text, integer) set search_path = public;
alter function public.wipe_room_chat_on_close() set search_path = public;

-- Server-side helpers only; no client has a reason to mint buckets.
revoke all on function public.take_token(text, integer, integer) from public;
revoke all on function public.take_token(text, integer, integer) from anon;
revoke all on function public.take_token(text, integer, integer) from authenticated;

-- Every SECURITY DEFINER function in this schema was also reachable with the
-- bare anon key (no session). The app signs in anonymously, so anon never
-- needs any of them; signed-in guests keep working as `authenticated`.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('revoke all on function %s from anon', r.sig);
  end loop;
end
$$;

-- The one exception: crash telemetry must still land when anonymous sign-in
-- itself is what failed, so report_error stays callable without a session.
grant execute on function public.report_error(
  text, text, text, text, text, text, text) to anon;

-- ═══════════ 5) Realtime: live DMs and friend requests ═══════════
-- postgres_changes only fires for tables in the publication. The app
-- subscribes to both of these; without them the channels stay silent.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'dm_messages'
  ) then
    alter publication supabase_realtime add table public.dm_messages;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'friendships'
  ) then
    alter publication supabase_realtime add table public.friendships;
  end if;
end
$$;

-- ═══════════ 6) Missing indexes ═══════════
-- Only the ones a PK cannot serve: every user_id lookup below is already
-- covered by a primary-key prefix or a unique index.
create index if not exists idx_friendships_addressee on public.friendships(addressee_id);
create index if not exists idx_dm_threads_user1 on public.dm_threads(user1_id);
create index if not exists idx_dm_threads_user2 on public.dm_threads(user2_id);
create index if not exists idx_dm_messages_thread_created
  on public.dm_messages(thread_id, created_at desc);

-- ═══════════ 7) Admin dashboard RPC repairs ═══════════
-- admin_find_user searched `installs.user_id`, a column that does not exist
-- (the table keys on owner_user_id). Device-code lookup — the very hint the
-- dashboard prints — raised 42703 on every call.
create or replace function public.admin_find_user(p_search text)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare
  v_q     text := lower(btrim(coalesce(p_search, '')));
  v_uid   uuid;
  v_dev   text;
  v_out   jsonb;
begin
  perform require_role(array['owner', 'support']);
  if v_q = '' then return '[]'::jsonb; end if;

  if v_q ~ '^diz-?[1-9][0-9]{6}$' then
    v_dev := regexp_replace(v_q, '^diz-?', '');
  elsif v_q ~ '^[1-9][0-9]{6}$' then
    v_dev := v_q;
  end if;

  begin
    v_uid := v_q::uuid;
  exception when others then
    v_uid := null;
  end;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_out from (
    select
      u.user_id,
      (select username from usernames w where w.user_id = u.user_id) as username,
      (select jsonb_agg(jsonb_build_object('name', p.name, 'avatar', p.avatar))
         from profiles p where p.user_id = u.user_id) as profiles,
      (select count(*) from cloud_sessions c where c.user_id = u.user_id) as sessions,
      (select max(d.last_heartbeat_at) from devices d where d.user_id = u.user_id) as last_seen,
      (select coalesce(jsonb_agg(jsonb_build_object('device_code', d.device_code, 'platform', d.platform)), '[]'::jsonb)
         from devices d where d.user_id = u.user_id) as installs,
      (select coalesce(jsonb_agg(jsonb_build_object('kind', h.kind, 'old_value', h.old_value, 'new_value', h.new_value, 'at', h.created_at)
                order by h.created_at desc), '[]'::jsonb)
         from (select * from identity_history ih
               where ih.user_id = u.user_id order by ih.created_at desc limit 10) h) as history
    from auth.users u
    where (v_uid is not null and u.id = v_uid)
       or (v_uid is null and (
             exists (select 1 from usernames w2
                     where w2.user_id = u.user_id and lower(w2.username) = ltrim(v_q, '@'))
          or exists (select 1 from profiles p2
                     where p2.user_id = u.user_id and lower(p2.name) = v_q)
       ))
       or (v_dev is not null and exists (
             select 1 from installs i2
             where i2.owner_user_id = u.user_id and i2.device_code = v_dev))
    limit 20
  ) t;

  return coalesce(v_out, '[]'::jsonb);
end;
$$;

-- The devices table already carries `activity`; the dashboard renders it but
-- the RPC never selected it.
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
           (d.last_seen_at > now() - interval '10 minutes') as online,
           (b.user_id is not null) as banned,
           b.level as ban_level
    from public.devices d
    left join public.user_bans b
      on b.user_id = d.user_id
     and (b.banned_until is null or b.banned_until > now())
    where (p_search = ''
           or d.device_code ilike '%' || p_search || '%'
           or d.platform ilike '%' || p_search || '%'
           or d.app_version ilike '%' || p_search || '%')
    order by d.last_seen_at desc nulls last
    limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;

-- ═══════════ 8) Restore codes: "naya phone, sab wapas" ═══════════
-- The app's Restore page issued real RPC calls to functions that never
-- existed, so every tap failed. Codes are 6 chars from a look-alike-free
-- alphabet, live 15 minutes, and are single-use.
create table if not exists public.restore_codes (
  code       text primary key,
  user_id    uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz,
  used_by    uuid
);
create index if not exists idx_restore_codes_user on public.restore_codes(user_id);
alter table public.restore_codes enable row level security;
revoke all on table public.restore_codes from anon, authenticated;

create or replace function public.issue_restore_code()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_alpha text := '34679ACDEFGHJKMNPQRTUVWXY';
  v_code  text;
  v_try   int := 0;
  v_exp   timestamptz := now() + interval '15 minutes';
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if not public.take_token('restore_issue:' || v_uid::text, 5, 1) then
    raise exception 'too many codes, wait a minute';
  end if;

  -- One live code per session: retire the previous ones.
  update public.restore_codes set expires_at = now()
  where user_id = v_uid and used_at is null and expires_at > now();

  loop
    v_try := v_try + 1;
    select string_agg(substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1),
                      '' order by g)
      into v_code
      from generate_series(1, 6) g;
    begin
      insert into public.restore_codes(code, user_id, expires_at)
      values (v_code, v_uid, v_exp);
      exit;
    exception when unique_violation then
      if v_try >= 8 then raise exception 'could not allocate code'; end if;
    end;
  end loop;

  return jsonb_build_object('code', v_code, 'expires_at', v_exp);
end;
$$;
revoke all on function public.issue_restore_code() from public;
revoke all on function public.issue_restore_code() from anon;
grant execute on function public.issue_restore_code() to authenticated;

create or replace function public.redeem_restore_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_code         text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_row          public.restore_codes%rowtype;
  v_merge        jsonb;
  v_friends      int := 0;
  v_progress     int := 0;
  v_progress_adv int := 0;
  v_zero         jsonb := jsonb_build_object(
    'watchlist_added', 0, 'history_added', 0, 'friends_added', 0,
    'progress_added', 0, 'progress_advanced', 0, 'already_merged', true);
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if length(v_code) <> 6 then raise exception 'code must be 6 characters'; end if;
  if not public.take_token('restore_redeem:' || v_uid::text, 8, 2) then
    raise exception 'too many attempts, wait a minute';
  end if;

  select * into v_row from public.restore_codes where code = v_code for update;
  if not found then raise exception 'unknown code'; end if;
  if v_row.used_at is not null then return v_zero; end if;
  if v_row.expires_at <= now() then raise exception 'code expired'; end if;
  if v_row.user_id = v_uid then return v_zero; end if;

  -- Count what the merge will actually add before it runs.
  select count(*) into v_friends
  from public.friendships
  where (requester_id = v_row.user_id and addressee_id <> v_uid)
     or (addressee_id = v_row.user_id and requester_id <> v_uid);

  select count(*) filter (where not exists (
           select 1 from public.cloud_sessions c
           where c.user_id = v_uid and c.media_id = s.media_id)),
         count(*) filter (where exists (
           select 1 from public.cloud_sessions c
           where c.user_id = v_uid and c.media_id = s.media_id
             and s.updated_at >= c.updated_at))
  into v_progress, v_progress_adv
  from public.cloud_sessions s
  where s.user_id = v_row.user_id;

  v_merge := public.merge_devices(v_row.user_id, v_uid);
  if not coalesce((v_merge ->> 'success')::boolean, false) then
    return jsonb_build_object(
      'success', false,
      'error', coalesce(v_merge ->> 'error', 'merge failed'),
      'watchlist_added', 0, 'history_added', 0, 'friends_added', 0,
      'progress_added', 0, 'progress_advanced', 0, 'already_merged', false);
  end if;

  update public.restore_codes
  set used_at = now(), used_by = v_uid
  where code = v_code;

  return jsonb_build_object(
    'success', true,
    'watchlist_added', 0,
    'history_added', 0,
    'friends_added', v_friends,
    'progress_added', v_progress,
    'progress_advanced', v_progress_adv,
    'already_merged', false);
end;
$$;
revoke all on function public.redeem_restore_code(text) from public;
revoke all on function public.redeem_restore_code(text) from anon;
grant execute on function public.redeem_restore_code(text) to authenticated;

commit;
