-- ─────────────────────────────────────────────────────────────────────────────
-- Dizzy-v3: Phase 0 Social & Multi-Sync Database Foundation
-- Migration: 20260920_social_sync_foundation.sql
--
-- Features:
-- 1. Central Token-Bucket Rate Limiter (take_token RPC)
-- 2. Devices & Progressive Identity Linking Ledger
-- 3. Case-Insensitive @username & GIN Trigram Search Index
-- 4. Mutual Friend Graph & Blocks
-- 5. Durable DMs & Group Chats with Idempotent Delivery
-- 6. Atomic Multi-Device Account Merger (merge_devices RPC)
-- ─────────────────────────────────────────────────────────────────────────────

-- Enable pg_trgm for lightning-fast sub-10ms user search
create extension if not exists pg_trgm;

-- ── 1. Central Token-Bucket Rate Limiter ──────────────────────────────────────
create table if not exists public.rate_buckets (
  key text primary key,
  tokens integer not null,
  last_refill timestamptz not null default now()
);

alter table public.rate_buckets enable row level security;
-- No client SELECT/INSERT directly; managed via SECURITY DEFINER function only

create or replace function public.take_token(
  p_key text,
  p_capacity integer,
  p_refill_per_min integer
)
returns boolean
language plpgsql
security definer
as $$
declare
  v_now timestamptz := now();
  v_tokens integer;
  v_last_refill timestamptz;
  v_elapsed_sec float;
  v_added integer;
begin
  select tokens, last_refill into v_tokens, v_last_refill
  from public.rate_buckets where key = p_key for update;

  if not found then
    insert into public.rate_buckets(key, tokens, last_refill)
    values (p_key, p_capacity - 1, v_now);
    return true;
  end if;

  v_elapsed_sec := extract(epoch from (v_now - v_last_refill));
  v_added := floor((v_elapsed_sec / 60.0) * p_refill_per_min)::integer;

  if v_added > 0 then
    v_tokens := least(p_capacity, v_tokens + v_added);
    v_last_refill := v_now;
  end if;

  if v_tokens >= 1 then
    update public.rate_buckets
    set tokens = v_tokens - 1, last_refill = v_last_refill
    where key = p_key;
    return true;
  else
    return false;
  end if;
end;
$$;

-- ── 2. Devices & Progressive Identity Ledger ──────────────────────────────────
create table if not exists public.devices (
  device_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_code char(7) not null,
  hwid_hash text not null,
  sid text not null unique,
  platform text not null,
  app_version text not null,
  last_seen_at timestamptz default now(),
  revoked_at timestamptz,
  created_at timestamptz default now(),
  unique(user_id, hwid_hash)
);

alter table public.devices enable row level security;

create policy "Users own their registered devices"
  on public.devices for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.identities (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('anon', 'phone', 'email')),
  identifier_hash text not null,
  verified_at timestamptz,
  created_at timestamptz default now(),
  primary key (user_id, kind)
);

alter table public.identities enable row level security;

create policy "Users own their identities"
  on public.identities for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── 3. @username Claim & GIN Trigram Search ───────────────────────────────────
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists username_lower text generated always as (lower(username)) stored;
alter table public.profiles add column if not exists last_username_change_at timestamptz;

create unique index if not exists idx_profiles_username_lower_uq
  on public.profiles(username_lower) where username is not null;

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin (username_lower gin_trgm_ops) where username is not null;

create or replace function public.claim_username(p_username text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(trim(p_username));
  v_last_change timestamptz;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Authentication required');
  end if;

  -- Regex format: 3 to 20 lowercase chars, digits or underscores
  if not (v_clean ~ '^[a-z0-9_]{3,20}$') then
    return jsonb_build_object('success', false, 'error', 'Username must be 3-20 letters, numbers, or underscores');
  end if;

  -- Reserved words check
  if v_clean in ('admin', 'dizzy', 'official', 'support', 'help', 'system', 'root') then
    return jsonb_build_object('success', false, 'error', 'This username is reserved');
  end if;

  -- Rate limit: 1 rename every 7 days
  select last_username_change_at into v_last_change from public.profiles where user_id = v_uid;
  if v_last_change is not null and v_last_change > now() - interval '7 days' then
    return jsonb_build_object('success', false, 'error', 'You can only change username once every 7 days');
  end if;

  -- Atomic claim with unique conflict guard
  begin
    update public.profiles
    set username = v_clean, last_username_change_at = now()
    where user_id = v_uid;

    return jsonb_build_object('success', true, 'username', v_clean);
  exception when unique_violation then
    return jsonb_build_object('success', false, 'error', 'This username is already taken');
  end;
end;
$$;

create or replace function public.search_users(p_query text, p_limit integer default 10)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text
)
language plpgsql
security definer
as $$
declare
  v_clean text := lower(trim(p_query));
begin
  if length(v_clean) < 2 then
    return;
  end if;

  return query
  select p.user_id, p.username, p.name as display_name, p.avatar_url
  from public.profiles p
  where p.username is not null
    and p.user_id <> auth.uid()
    and p.username_lower % v_clean
  order by similarity(p.username_lower, v_clean) desc
  limit least(p_limit, 20);
end;
$$;

-- ── 4. Friendships & Mutual Graph ─────────────────────────────────────────────
create table if not exists public.friendships (
  requester_id uuid references auth.users(id) on delete cascade,
  addressee_id uuid references auth.users(id) on delete cascade,
  status text not null check (status in ('pending', 'accepted', 'blocked')),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

alter table public.friendships enable row level security;

create policy "Users see their own friendships"
  on public.friendships for select
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- INSERT: requester must be auth.uid(), cannot friend self,
-- status must be pending or blocked (enforced by table CHECK).
create policy "Users send friend requests as requester"
  on public.friendships for insert
  with check (auth.uid() = requester_id
              and requester_id <> addressee_id
              and status in ('pending', 'blocked'));

-- UPDATE: user is either requester or addressee.
create policy "Users update their own friendship rows"
  on public.friendships for update
  using (auth.uid() = requester_id or auth.uid() = addressee_id)
  with check (auth.uid() = requester_id or auth.uid() = addressee_id);

-- DELETE: user is either requester or addressee.
create policy "Users delete their own friendship rows"
  on public.friendships for delete
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- ── 5. Durable DMs & Group Chats with Idempotency ──────────────────────────────
create table if not exists public.dm_threads (
  thread_id text primary key, -- 'dm:sha256(min_uid:max_uid)'
  user1_id uuid not null references auth.users(id) on delete cascade,
  user2_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);

alter table public.dm_threads enable row level security;

create policy "Users access their own DM threads"
  on public.dm_threads for select
  using (auth.uid() = user1_id or auth.uid() = user2_id);

create table if not exists public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id text not null references public.dm_threads(thread_id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  client_msg_id uuid not null unique,
  kind text not null default 'text' check (kind in ('text', 'media_card', 'action')),
  body text not null check (char_length(body) between 1 and 2000),
  media_ref text,
  created_at timestamptz default now()
);

alter table public.dm_messages enable row level security;

create policy "Thread participants read DM messages"
  on public.dm_messages for select
  using (
    exists (
      select 1 from public.dm_threads t
      where t.thread_id = dm_messages.thread_id
        and (t.user1_id = auth.uid() or t.user2_id = auth.uid())
    )
  );

-- ── 6. Atomic Multi-Device Account Merger (merge_devices RPC) ──────────────────
create or replace function public.merge_devices(
  p_old_anon_uid uuid,
  p_canonical_uid uuid
)
returns jsonb
language plpgsql
security definer
as $$
begin
  if p_old_anon_uid is null or p_canonical_uid is null or p_old_anon_uid = p_canonical_uid then
    return jsonb_build_object('success', false, 'error', 'Invalid merger parameters');
  end if;

  -- Re-link devices to canonical user
  update public.devices
  set user_id = p_canonical_uid
  where user_id = p_old_anon_uid;

  -- Re-parent continue_watching without data loss (max progress wins on conflict)
  insert into public.continue_watching (user_id, content_id, progress_ms, duration_ms, updated_at)
  select p_canonical_uid, content_id, progress_ms, duration_ms, updated_at
  from public.continue_watching
  where user_id = p_old_anon_uid
  on conflict (user_id, content_id) do update
  set progress_ms = greatest(public.continue_watching.progress_ms, excluded.progress_ms),
      updated_at = greatest(public.continue_watching.updated_at, excluded.updated_at);

  delete from public.continue_watching where user_id = p_old_anon_uid;

  return jsonb_build_object('success', true, 'canonical_uid', p_canonical_uid);
end;
$$;
