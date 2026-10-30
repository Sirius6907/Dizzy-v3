-- Dizzy v1.3.3 — notification brain (Phase 4, server half).
-- Run: supabase db query --linked -f supabase/migrations/20261037_push_brain.sql
-- then record the history row (never `db push`).
--
-- Four additive pieces:
--   1. release_candidates — fresh TMDB titles (IN + US windows, hi/en) that
--      `release-scan` keeps warm. Re-scans refresh `last_seen`, so a title
--      that leaves the window ages out instead of being deleted by hand.
--   2. push_send_log — one row per notification the brain decided to send.
--      It is both the cadence ledger (20 h gap, 1/day, 4/week) and the
--      server-backed history the Notification Center reads.
--   3. claim_push() — atomic cadence gate. The advisory lock makes the
--      check-and-insert safe when two runs overlap.
--   4. pick_release_candidates() — per-user taste match, personalisation is
--      the taste_profiles roll-up from Phase 2, with a light penalty for
--      languages that already filled this week's slots (Bollywood and
--      Hollywood stay balanced).
--
-- app_secrets + call_edge_function() let pg_cron call the edge functions
-- without a secret ever living in this repo. Populate the two rows once:
--   insert into public.app_secrets (name, value) values
--     ('functions_base', 'https://<ref>.supabase.co/functions/v1'),
--     ('push_cron_token', '<same value as the PUSH_CRON_TOKEN function secret>')
--   on conflict (name) do update set value = excluded.value, updated_at = now();
-- then re-run this file's scheduling block (it is idempotent).

-- ═══════════ 1) fresh releases ═══════════
create table if not exists public.release_candidates (
  id           bigserial primary key,
  media_type   text not null default 'movie',
  tmdb_id      bigint not null,
  title        text not null,
  lang         text not null default '',
  year         int,
  release_date date,
  popularity   numeric not null default 0,
  rating       numeric not null default 0,
  votes        int not null default 0,
  genres       text[] not null default '{}',
  poster       text,
  backdrop     text,
  source       text not null default '',
  first_seen   timestamptz not null default now(),
  last_seen    timestamptz not null default now(),
  notified_at  timestamptz,
  constraint release_candidates_type_chk check (media_type in ('movie', 'tv')),
  constraint release_candidates_title_chk check (length(title) between 1 and 300),
  constraint release_candidates_unique unique (media_type, tmdb_id)
);

create index if not exists release_candidates_recent_idx
  on public.release_candidates (last_seen desc, popularity desc);

alter table public.release_candidates enable row level security;

drop policy if exists "admins read release candidates" on public.release_candidates;
create policy "admins read release candidates" on public.release_candidates
  for select to authenticated using (public.is_admin());

revoke all on public.release_candidates from anon, authenticated;
revoke all on sequence public.release_candidates_id_seq from anon, authenticated;
grant select on public.release_candidates to authenticated;
grant all on public.release_candidates to service_role;
grant usage, select on sequence public.release_candidates_id_seq to service_role;

-- ═══════════ 2) send ledger ═══════════
create table if not exists public.push_send_log (
  id           bigserial primary key,
  user_id      uuid not null,
  kind         text not null default 'releases',
  title        text not null default '',
  body         text not null default '',
  entity_type  text not null default '',
  entity_id    text not null default '',
  dedupe_id    text not null default '',
  candidate_id bigint references public.release_candidates(id) on delete set null,
  status       text not null default 'queued',
  reason       text not null default '',
  error        text not null default '',
  sent_at      timestamptz,
  created_at   timestamptz not null default now(),
  constraint push_send_log_kind_chk check (kind in (
    'releases', 'updates', 'downloads', 'social', 'announcements'
  )),
  constraint push_send_log_status_chk check (status in (
    'queued', 'sent', 'failed', 'skipped'
  )),
  constraint push_send_log_title_chk check (length(title) <= 120),
  constraint push_send_log_body_chk check (length(body) <= 240)
);

create index if not exists push_send_log_user_time_idx
  on public.push_send_log (user_id, created_at desc);
create index if not exists push_send_log_time_idx
  on public.push_send_log (created_at desc);

-- A title can reach a user once. The claim RPC checks this; the index makes
-- the guarantee hold even if the check is ever bypassed. Failed/skipped rows
-- stay out of the index so a transient delivery error can retry later.
drop index if exists public.push_send_log_user_candidate_idx;
create unique index if not exists push_send_log_user_candidate_idx
  on public.push_send_log (user_id, candidate_id)
  where candidate_id is not null and status in ('queued', 'sent');

alter table public.push_send_log enable row level security;

drop policy if exists push_send_log_select_own on public.push_send_log;
create policy push_send_log_select_own on public.push_send_log
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "admins read push send log" on public.push_send_log;
create policy "admins read push send log" on public.push_send_log
  for select to authenticated using (public.is_admin());

revoke all on public.push_send_log from anon, authenticated;
revoke all on sequence public.push_send_log_id_seq from anon, authenticated;
grant select on public.push_send_log to authenticated;
grant all on public.push_send_log to service_role;
grant usage, select on sequence public.push_send_log_id_seq to service_role;

-- ═══════════ 3) cadence gate ═══════════
-- Returns {ok, log_id} or {ok:false, reason} where reason is one of
-- auth|kind|empty|duplicate|gap|daily|weekly. Pass 0 to any cadence limit
-- to bypass it (e.g. a security announcement).
create or replace function public.claim_push(
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_entity_type text default '',
  p_entity_id text default '',
  p_candidate_id bigint default null,
  p_dedupe_id text default '',
  p_min_gap_hours int default 20,
  p_per_day int default 1,
  p_per_week int default 4
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text := lower(coalesce(p_kind, 'releases'));
  v_title text := left(regexp_replace(coalesce(p_title, ''), '\s+', ' ', 'g'), 120);
  v_body text := left(regexp_replace(coalesce(p_body, ''), '\s+', ' ', 'g'), 240);
  v_last timestamptz;
  v_day int;
  v_week int;
  v_id bigint;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'auth');
  end if;
  if v_kind not in ('releases', 'updates', 'downloads', 'social', 'announcements') then
    return jsonb_build_object('ok', false, 'reason', 'kind');
  end if;
  if v_title = '' and v_body = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty');
  end if;

  -- Serialise claims per user; the lock is released with the transaction.
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  if p_candidate_id is not null and exists (
    select 1 from public.push_send_log
    where user_id = p_user_id and candidate_id = p_candidate_id
      and status in ('queued', 'sent')
  ) then
    return jsonb_build_object('ok', false, 'reason', 'duplicate');
  end if;

  if p_min_gap_hours > 0 then
    select max(created_at) into v_last
    from public.push_send_log
    where user_id = p_user_id and status in ('queued', 'sent');
    if v_last is not null
       and v_last > now() - make_interval(hours => p_min_gap_hours) then
      return jsonb_build_object('ok', false, 'reason', 'gap');
    end if;
  end if;

  if p_per_day > 0 then
    select count(*) into v_day
    from public.push_send_log
    where user_id = p_user_id and status in ('queued', 'sent')
      and created_at > now() - interval '24 hours';
    if v_day >= p_per_day then
      return jsonb_build_object('ok', false, 'reason', 'daily');
    end if;
  end if;

  if p_per_week > 0 then
    select count(*) into v_week
    from public.push_send_log
    where user_id = p_user_id and status in ('queued', 'sent')
      and created_at > now() - interval '7 days';
    if v_week >= p_per_week then
      return jsonb_build_object('ok', false, 'reason', 'weekly');
    end if;
  end if;

  insert into public.push_send_log
    (user_id, kind, title, body, entity_type, entity_id, dedupe_id, candidate_id)
  values (
    p_user_id, v_kind, v_title, v_body,
    left(coalesce(p_entity_type, ''), 16),
    left(coalesce(p_entity_id, ''), 64),
    left(coalesce(p_dedupe_id, ''), 80),
    p_candidate_id
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'log_id', v_id);
end;
$$;

create or replace function public.push_mark_sent(
  p_id bigint,
  p_status text,
  p_error text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_candidate bigint;
begin
  if p_status not in ('sent', 'failed', 'skipped') then
    return jsonb_build_object('success', false, 'error', 'status');
  end if;

  update public.push_send_log
  set status = p_status,
      error = left(coalesce(p_error, ''), 300),
      sent_at = case when p_status = 'sent' then now() else sent_at end
  where id = p_id and status = 'queued'
  returning candidate_id into v_candidate;

  if not found then
    return jsonb_build_object('success', false, 'error', 'not_queued');
  end if;

  if p_status = 'sent' and v_candidate is not null then
    update public.release_candidates
    set notified_at = now()
    where id = v_candidate;
  end if;

  return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.claim_push(uuid, text, text, text, text, text, bigint, text, int, int, int) from public;
revoke all on function public.push_mark_sent(bigint, text, text) from public;
grant execute on function public.claim_push(uuid, text, text, text, text, text, bigint, text, int, int, int)
  to service_role;
grant execute on function public.push_mark_sent(bigint, text, text) to service_role;

-- ═══════════ 4) taste-matched picker ═══════════
-- New users (no taste_profiles row) get the most popular fresh titles, which
-- is exactly the "latest Bollywood + Hollywood" feed the home screen shows.
-- Users with signal get genre/language overlap first. A language that filled
-- this week's slots is penalised so both industries keep getting turns.
create or replace function public.pick_release_candidates(
  p_user_id uuid,
  p_limit int default 5
)
returns setof public.release_candidates
language sql
stable
security definer
set search_path = public
as $$
  with taste as (
    select
      coalesce(
        (select jsonb_agg(g ->> 'name')
         from jsonb_array_elements(coalesce(top_genres, '[]'::jsonb)) g
         where coalesce((g ->> 'score')::numeric, 0) > 0.5),
        '[]'::jsonb
      ) as genres,
      coalesce(
        (select jsonb_agg(g ->> 'lang')
         from jsonb_array_elements(coalesce(top_langs, '[]'::jsonb)) g),
        '[]'::jsonb
      ) as langs,
      coalesce(event_count, 0) as n
    from public.taste_profiles
    where user_id = p_user_id
  )
  select c.*
  from public.release_candidates c
  left join taste t on true
  left join lateral (
    select count(*) as same_lang
    from public.push_send_log l
    join public.release_candidates c2 on c2.id = l.candidate_id
    where l.user_id = p_user_id
      and l.created_at > now() - interval '7 days'
      and c2.lang = c.lang
  ) recent on true
  where c.last_seen > now() - interval '30 days'
    and not exists (
      select 1 from public.push_send_log l
      where l.user_id = p_user_id and l.candidate_id = c.id
        and l.status in ('queued', 'sent')
    )
  order by
    (
      case
        when coalesce(t.n, 0) = 0 then 0
        when coalesce(t.langs, '[]'::jsonb) ? c.lang then 3
        else 0
      end
      + coalesce(
          (select count(*)
           from unnest(c.genres) g
           where coalesce(t.genres, '[]'::jsonb) ? g),
          0
        )
      - least(coalesce(recent.same_lang, 0), 4) * 2
    ) desc,
    c.popularity desc
  limit greatest(1, least(20, p_limit));
$$;

revoke all on function public.pick_release_candidates(uuid, int) from public;
grant execute on function public.pick_release_candidates(uuid, int) to service_role;

-- ═══════════ 5) scheduled calls without committed secrets ═══════════
create table if not exists public.app_secrets (
  name       text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;
revoke all on public.app_secrets from public;
grant all on public.app_secrets to service_role;

create or replace function public.call_edge_function(
  p_name text,
  p_body jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text;
  v_token text;
  v_req bigint;
begin
  select value into v_base from public.app_secrets where name = 'functions_base';
  select value into v_token from public.app_secrets where name = 'push_cron_token';
  if coalesce(v_base, '') = '' or coalesce(v_token, '') = '' then
    return null;
  end if;

  select net.http_post(
    url := rtrim(v_base, '/') || '/' || p_name,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_token
    ),
    body := coalesce(p_body, '{}'::jsonb),
    timeout_milliseconds := 30000
  ) into v_req;
  return v_req;
end;
$$;

revoke all on function public.call_edge_function(text, jsonb) from public, anon, authenticated;
-- Old one-argument overload from the first apply; the default covers it.
drop function if exists public.call_edge_function(text);

create or replace function public.push_brain_purge()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_candidates int;
  v_log int;
begin
  delete from public.release_candidates
  where last_seen < now() - interval '120 days';
  get diagnostics v_candidates = row_count;

  delete from public.push_send_log
  where created_at < now() - interval '180 days';
  get diagnostics v_log = row_count;

  return jsonb_build_object(
    'success', true, 'candidates', v_candidates, 'log', v_log
  );
end;
$$;

revoke all on function public.push_brain_purge() from public, anon, authenticated;

-- Hourly scan + brain. Both are cheap no-ops when there is nothing new.
do $do$
declare
  r record;
begin
  if not exists (
    select 1 from public.app_secrets where name = 'push_cron_token'
  ) then
    return;
  end if;

  for r in
    select jobid from cron.job
    where jobname in (
      'dizzy-release-scan', 'dizzy-push-brain', 'dizzy-push-cleanup'
    )
  loop
    perform cron.unschedule(r.jobid);
  end loop;

  perform cron.schedule(
    'dizzy-release-scan', '11 * * * *',
    $job$select public.call_edge_function('release-scan');$job$
  );
  perform cron.schedule(
    'dizzy-push-brain', '26 * * * *',
    $job$select public.call_edge_function('push-brain');$job$
  );
  perform cron.schedule(
    'dizzy-push-cleanup', '5 4 * * *',
    $job$select public.push_brain_purge();$job$
  );
end
$do$;

comment on table public.release_candidates is
  'Fresh TMDB titles kept warm by release-scan; aged out by push_brain_purge.';
comment on table public.push_send_log is
  'Cadence ledger and server-backed notification history. Owner and admins can read.';
comment on function public.claim_push(uuid, text, text, text, text, text, bigint, text, int, int, int) is
  'Atomic cadence gate: 20 h gap, 1/day, 4/week by default. service_role only.';
comment on function public.pick_release_candidates(uuid, int) is
  'Taste-matched fresh titles for one user; balances languages over a week.';

-- Realtime send-log for the admin push tab (gated by its admin SELECT policy).
do $do$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'push_send_log'
  ) then
    alter publication supabase_realtime add table public.push_send_log;
  end if;
end
$do$;
