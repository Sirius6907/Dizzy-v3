-- Dizzy v1.3.3 T1.2 — full account merge on email/phone link.
-- Run: supabase db query --linked -f supabase/migrations/20261012_full_merge.sql
--
-- Problem: old merge_devices only moved devices + continue_watching.
-- Profiles, usernames, identity_history, sessions, backups, consents,
-- genre prefs, installs, friends, DMs stayed on the dead anon uid —
-- so an email link silently "lost" the user's name and friends.
-- New merge_moves EVERYTHING (canonical row wins on conflict), then deletes
-- the old rows. DMs/friend edges are re-keyed only when they don't collide;
-- colliding PK rows stay readable on the old uid rather than erroring.

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

  -- Devices → canonical user. Guarded: same physical device on both uids
  -- would collide on unique(user_id, hwid_hash) — move the rest, drop dupes
  -- (the canonical row already carries this device's state).
  update public.devices d
  set user_id = p_canonical_uid
  where d.user_id = p_old_anon_uid
    and not exists (select 1 from public.devices e
                    where e.user_id = p_canonical_uid
                      and e.hwid_hash = d.hwid_hash);
  delete from public.devices where user_id = p_old_anon_uid;

  -- NOTE: public.continue_watching does NOT exist on this project (no
  -- migration ever created it; watch progress lives in cloud_sessions
  -- below). Old code referenced it — guarded out, never delete this block:
  -- if the table appears one day, this merge must cover it too.
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

  -- Usernames: keep the canonical row when both exist (one row per user).
  -- The loser's names are preserved in identity_history below.
  insert into public.usernames(user_id, username, last_change_at)
  select p_canonical_uid, username, last_change_at
  from public.usernames
  where user_id = p_old_anon_uid
  on conflict (user_id) do nothing;
  delete from public.usernames where user_id = p_old_anon_uid;

  -- Identity history: re-parent everything (PK is a surrogate id, no clash).
  update public.identity_history
  set user_id = p_canonical_uid
  where user_id = p_old_anon_uid;

  -- Cross-device sessions: merge by (user_id, media_id).
  insert into public.cloud_sessions
    (user_id, media_id, title, media_type, poster_url, backdrop_url, year, season, episode, episode_title, position_seconds, total_duration_seconds, updated_at)
  select p_canonical_uid, media_id, title, media_type, poster_url, backdrop_url, year, season, episode, episode_title, position_seconds, total_duration_seconds, updated_at
  from public.cloud_sessions
  where user_id = p_old_anon_uid
  on conflict (user_id, media_id) do nothing;
  delete from public.cloud_sessions where user_id = p_old_anon_uid;

  -- Backups: merge by (user_id, profile_id).
  insert into public.cloud_backups (user_id, profile_id, payload, app_version, updated_at)
  select p_canonical_uid, profile_id, payload, app_version, updated_at
  from public.cloud_backups
  where user_id = p_old_anon_uid
  on conflict (user_id, profile_id) do nothing;
  delete from public.cloud_backups where user_id = p_old_anon_uid;

  -- Consents: canonical row wins when both exist.
  insert into public.consents (owner_user_id, telemetry, genre_prefs, crash, watch_party, updated_at)
  select p_canonical_uid, telemetry, genre_prefs, crash, watch_party, updated_at
  from public.consents
  where owner_user_id = p_old_anon_uid
  on conflict (owner_user_id) do nothing;
  delete from public.consents where owner_user_id = p_old_anon_uid;

  -- Genre prefs: merge by (owner, genre).
  insert into public.genre_prefs (owner_user_id, genre, score, updated_at)
  select p_canonical_uid, genre, score, updated_at
  from public.genre_prefs
  where owner_user_id = p_old_anon_uid
  on conflict (owner_user_id, genre) do nothing;
  delete from public.genre_prefs where owner_user_id = p_old_anon_uid;

  -- Installs: one row per owner. anon_id is UNIQUE per row, so a blind
  -- re-parent insert would collide — merge last_seen when the canonical
  -- row exists, else move the old row over.
  -- NOTE: installs has no updated_at — created/last_seen drive the choice.
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

  -- Identities ledger (anon/phone/email links): re-key, ignore PK clash.
  insert into public.identities (user_id, kind, identifier_hash, verified_at, created_at)
  select p_canonical_uid, kind, identifier_hash, verified_at, created_at
  from public.identities
  where user_id = p_old_anon_uid
  on conflict (user_id, kind) do nothing;
  delete from public.identities where user_id = p_old_anon_uid;

  -- Friendships: drop old↔canonical edges first (re-keying them would make
  -- a self-edge and trip the requester<>addressee check), then move the
  -- rest only where they don't collide, and drop leftovers.
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

  -- DM threads: re-key user slots (thread_id text stays; old threads remain
  -- readable via the canonical uid once re-keyed).
  update public.dm_threads set user1_id = p_canonical_uid
  where user1_id = p_old_anon_uid;
  update public.dm_threads set user2_id = p_canonical_uid
  where user2_id = p_old_anon_uid;
  update public.dm_messages set sender_id = p_canonical_uid
  where sender_id = p_old_anon_uid;

  return jsonb_build_object('success', true, 'canonical_uid', p_canonical_uid);
end;
$$;
revoke all on function public.merge_devices(uuid, uuid) from public;
grant execute on function public.merge_devices(uuid, uuid) to authenticated;
