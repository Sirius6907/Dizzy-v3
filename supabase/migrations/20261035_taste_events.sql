-- Dizzy v1.3.3 — taste pipeline (Phase 2, server half).
-- Run: supabase db query --linked -f supabase/migrations/20261035_taste_events.sql
-- then record the history row (never `db push`).
--
-- Three additive pieces:
--   1. user_events  — append-only behaviour log, one row per in-app action.
--      Written only by its owner (RLS insert/select/delete own). The client
--      batches, so a day of browsing is a handful of inserts, not hundreds.
--   2. taste_profiles — one rolled-up row per user (top genres / languages /
--      titles with decaying scores). Derived data: always rebuildable from
--      user_events, never the source of truth.
--   3. refresh_taste_profile() — SECURITY DEFINER roll-up. Weights favour
--      actions that prove intent (complete > add_list > play > view > search),
--      and decay by age so last week beats last quarter. Anonymous uids work
--      the same as signed-in ones.

-- ═══════════ 1) event log ═══════════
create table if not exists public.user_events (
  id          bigserial primary key,
  user_id     uuid not null default auth.uid(),
  kind        text not null,
  entity_type text not null default 'movie',
  entity_id   text not null default '',
  title       text not null default '',
  lang        text not null default '',
  genres      text[] not null default '{}',
  meta        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  constraint user_events_kind_chk check (kind in (
    'play', 'view', 'complete', 'add_list', 'remove_list',
    'search', 'rate', 'notif_open'
  )),
  constraint user_events_entity_chk check (length(entity_id) <= 200),
  constraint user_events_title_chk check (length(title) <= 300),
  constraint user_events_meta_chk check (pg_column_size(meta) <= 4096)
);

create index if not exists user_events_user_time_idx
  on public.user_events (user_id, created_at desc);
create index if not exists user_events_user_entity_idx
  on public.user_events (user_id, entity_type, entity_id);

alter table public.user_events enable row level security;

drop policy if exists user_events_insert_own on public.user_events;
create policy user_events_insert_own on public.user_events
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_events_select_own on public.user_events;
create policy user_events_select_own on public.user_events
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists user_events_delete_own on public.user_events;
create policy user_events_delete_own on public.user_events
  for delete to authenticated
  using (user_id = auth.uid());

-- ═══════════ 2) rolled-up taste ═══════════
create table if not exists public.taste_profiles (
  user_id     uuid primary key,
  top_genres  jsonb not null default '[]'::jsonb,
  top_langs   jsonb not null default '[]'::jsonb,
  top_titles  jsonb not null default '[]'::jsonb,
  event_count int not null default 0,
  updated_at  timestamptz not null default now()
);

alter table public.taste_profiles enable row level security;

drop policy if exists taste_profiles_select_own on public.taste_profiles;
create policy taste_profiles_select_own on public.taste_profiles
  for select to authenticated
  using (user_id = auth.uid());

-- ═══════════ 3) roll-up ═══════════
-- p_uid defaults to the caller; the edge function passes a uid explicitly
-- after authenticating the JWT, so it can never read someone else's log.
create or replace function public.refresh_taste_profile(p_uid uuid default auth.uid())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := coalesce(p_uid, auth.uid());
  v_genres jsonb;
  v_langs jsonb;
  v_titles jsonb;
  v_count int;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Authentication required');
  end if;

  -- Callers may only refresh themselves; service role may refresh anyone.
  if auth.uid() is distinct from v_uid
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    return jsonb_build_object('success', false, 'error', 'Not allowed');
  end if;

  with weighted as (
    select e.*,
           case e.kind
             when 'complete'   then 5.0
             when 'add_list'   then 4.0
             when 'play'       then 3.0
             when 'notif_open' then 2.0
             when 'rate'       then 2.0
             when 'view'       then 1.0
             else 1.0
           end
           * greatest(0.2, 1.0 - extract(epoch from (now() - e.created_at)) / (90 * 86400.0))
           as w
    from public.user_events e
    where e.user_id = v_uid
      and e.created_at > now() - interval '90 days'
  ),
  genre_scores as (
    select g as genre, sum(w) as score
    from weighted, unnest(genres) as g
    where coalesce(g, '') <> ''
    group by g
    order by score desc
    limit 8
  ),
  lang_scores as (
    select lang, sum(w) as score
    from weighted
    where lang <> ''
    group by lang
    order by score desc
    limit 4
  ),
  title_scores as (
    select entity_type, entity_id, max(title) as title, max(lang) as lang,
           sum(w) as score
    from weighted
    where entity_id <> '' and kind in ('complete', 'add_list', 'play', 'rate')
    group by entity_type, entity_id
    order by score desc
    limit 12
  )
  select
    coalesce((select jsonb_agg(jsonb_build_object('name', genre, 'score', round(score::numeric, 3)))
              from genre_scores), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('lang', lang, 'score', round(score::numeric, 3)))
              from lang_scores), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
                'type', entity_type, 'id', entity_id, 'title', title,
                'lang', lang, 'score', round(score::numeric, 3)))
              from title_scores), '[]'::jsonb),
    coalesce((select count(*) from weighted), 0)
  into v_genres, v_langs, v_titles, v_count;

  insert into public.taste_profiles as t
    (user_id, top_genres, top_langs, top_titles, event_count, updated_at)
  values (v_uid, v_genres, v_langs, v_titles, v_count, now())
  on conflict (user_id) do update set
    top_genres = excluded.top_genres,
    top_langs = excluded.top_langs,
    top_titles = excluded.top_titles,
    event_count = excluded.event_count,
    updated_at = excluded.updated_at;

  return jsonb_build_object(
    'success', true,
    'event_count', v_count,
    'genres', v_genres,
    'langs', v_langs
  );
end;
$$;

revoke all on function public.refresh_taste_profile(uuid) from public;
grant execute on function public.refresh_taste_profile(uuid) to authenticated, service_role;

-- The edge function runs as service_role; it must never see rows for uids it
-- did not authenticate, so RLS stays on and it filters explicitly.
-- Supabase's defaults hand anon table-level rights; strip them so only the
-- owning user (RLS-checked) can touch the log.
revoke all on public.user_events from anon, authenticated;
revoke all on public.taste_profiles from anon, authenticated;
revoke all on sequence public.user_events_id_seq from anon, authenticated;
grant select, insert, delete on public.user_events to authenticated;
grant select on public.taste_profiles to authenticated;
grant usage, select on sequence public.user_events_id_seq to authenticated;
grant all on public.user_events to service_role;
grant all on public.taste_profiles to service_role;

comment on table public.user_events is
  'Append-only behaviour log for personalisation. Consent-gated on the client.';
comment on function public.refresh_taste_profile(uuid) is
  'Rebuilds the caller''s taste_profiles row from the last 90 days of user_events.';
