-- Dizzy v1.1.9 cloud schema — run once in Supabase SQL Editor.
-- RLS owner-only. No PII columns anywhere (region_code like 'IN' is max granularity).

-- ── installs: one row per app install ──
create table if not exists installs (
  id uuid primary key default gen_random_uuid(),
  -- Supabase anonymous-auth user UUID; no email/name/PII.
  owner_user_id uuid unique not null references auth.users(id) on delete cascade,
  anon_id text unique not null,
  platform text not null default 'unknown',
  app_version text not null default '1.1.9',
  region_code text not null default '--',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
alter table installs enable row level security;
drop policy if exists "anon insert own install" on installs;
create policy "anon insert own install" on installs
  for insert to anon, authenticated with check (auth.uid() = owner_user_id);
drop policy if exists "owner update own install" on installs;
create policy "owner update own install" on installs
  for update to anon, authenticated
  using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);
drop policy if exists "owner delete own install" on installs;
create policy "owner delete own install" on installs
  for delete to anon, authenticated using (auth.uid() = owner_user_id);

-- ── consents: privacy toggles per install/user ──
create table if not exists consents (
  owner_user_id uuid primary key references auth.users(id) on delete cascade,
  telemetry boolean not null default false,
  genre_prefs boolean not null default false,
  crash boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table consents enable row level security;
drop policy if exists "owner rw consents" on consents;
create policy "owner rw consents" on consents
  for all to anon, authenticated
  using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);

-- ── genre_prefs: taste scores (no titles) ──
create table if not exists genre_prefs (
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  genre text not null,
  score double precision not null default 0 check (score >= 0 and score <= 1),
  updated_at timestamptz not null default now(),
  primary key (owner_user_id, genre)
);
alter table genre_prefs enable row level security;
drop policy if exists "owner rw genre_prefs" on genre_prefs;
create policy "owner rw genre_prefs" on genre_prefs
  for all to anon, authenticated
  using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);

-- ── profiles: cloud-synced user profiles (local PIN enforced offline too) ──
create table if not exists profiles (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id text not null,
  name text not null default 'Profile',
  avatar text not null default 'default',
  is_kids boolean not null default false,
  pin_hash text,
  created_at timestamptz not null default now(),
  primary key (user_id, profile_id)
);
alter table profiles enable row level security;
drop policy if exists "user rw own profiles" on profiles;
create policy "user rw own profiles" on profiles
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── cloud_backups: BackupRestoreService payload per user/profile ──
create table if not exists cloud_backups (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id text not null default 'default',
  payload jsonb not null default '{}',
  app_version text not null default '1.1.9',
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id)
);
alter table cloud_backups enable row level security;
drop policy if exists "user rw own backups" on cloud_backups;
create policy "user rw own backups" on cloud_backups
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── rooms: watch-party rooms (media_ref = tmdb/imdb ids only, no URLs) ──
create table if not exists rooms (
  room_id text primary key,
  host_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Watch Party',
  media_ref text,
  visibility text not null default 'public' check (visibility in ('public','private')),
  pass_hash text,
  status text not null default 'lobby' check (status in ('lobby','live','closed')),
  created_at timestamptz not null default now()
);
alter table rooms enable row level security;
drop policy if exists "auth read public rooms" on rooms;
create policy "auth read public rooms" on rooms
  for select to authenticated using (visibility = 'public' or auth.uid() = host_user_id);
drop policy if exists "auth create rooms" on rooms;
create policy "auth create rooms" on rooms
  for insert to authenticated with check (auth.uid() = host_user_id);
drop policy if exists "host update rooms" on rooms;
create policy "host update rooms" on rooms
  for update to authenticated
  using (auth.uid() = host_user_id) with check (auth.uid() = host_user_id);
drop policy if exists "host delete rooms" on rooms;
create policy "host delete rooms" on rooms
  for delete to authenticated using (auth.uid() = host_user_id);

create table if not exists room_members (
  room_id text not null references rooms(room_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('host','member')),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
alter table room_members enable row level security;
drop policy if exists "member rw own membership" on room_members;
create policy "member rw own membership" on room_members
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- room_events travel over Realtime Broadcast (ephemeral, not stored).
-- Enable Realtime for rooms table (lobby status changes):
--   Dashboard → Database → Replication → enable `rooms`.
