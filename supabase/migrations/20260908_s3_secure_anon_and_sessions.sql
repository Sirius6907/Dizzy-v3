-- Dizzy v1.1.9 S3 migration — run ONCE in Supabase SQL Editor.
-- PRE-RELEASE ONLY: drops the three empty v1.1.9 telemetry tables created by
-- the initial schema and recreates them with auth.uid()-bound RLS. It does NOT
-- touch auth.users, profiles, cloud_backups, rooms, or room_members.

-- These tables hold no production user data yet. Safe before first public build.
drop table if exists genre_prefs;
drop table if exists consents;
drop table if exists installs;

create table installs (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid unique not null references auth.users(id) on delete cascade,
  anon_id text unique not null,
  platform text not null default 'unknown',
  app_version text not null default '1.1.9',
  region_code text not null default '--',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
alter table installs enable row level security;
create policy "anon insert own install" on installs
  for insert to anon, authenticated with check (auth.uid() = owner_user_id);
create policy "owner update own install" on installs
  for update to anon, authenticated
  using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);
create policy "owner delete own install" on installs
  for delete to anon, authenticated using (auth.uid() = owner_user_id);

create table consents (
  owner_user_id uuid primary key references auth.users(id) on delete cascade,
  telemetry boolean not null default false,
  genre_prefs boolean not null default false,
  crash boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table consents enable row level security;
create policy "owner rw consents" on consents
  for all to anon, authenticated
  using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);

create table genre_prefs (
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  genre text not null,
  score double precision not null default 0 check (score >= 0 and score <= 1),
  updated_at timestamptz not null default now(),
  primary key (owner_user_id, genre)
);
alter table genre_prefs enable row level security;
create policy "owner rw genre_prefs" on genre_prefs
  for all to anon, authenticated
  using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);

-- Sanitized cross-device progress only: no stream URLs, magnets, headers,
-- tokens, source/addon labels, or other device-specific playback data.
create table if not exists cloud_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  media_id text not null,
  title text not null,
  media_type text not null default 'movie',
  poster_url text,
  backdrop_url text,
  year text,
  season integer,
  episode integer,
  episode_title text,
  position_seconds integer not null default 0,
  total_duration_seconds integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, media_id)
);
alter table cloud_sessions enable row level security;
drop policy if exists "user rw own cloud sessions" on cloud_sessions;
create policy "user rw own cloud sessions" on cloud_sessions
  for all to anon, authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Dashboard: Database → Replication → enable `cloud_sessions` only if you
-- later want live updates. Pull-on-open/manual sync does not require it.
