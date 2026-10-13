-- v1.3.3-T2.4 — support inbox + curated publish + announcements feed.
--
-- Three things the dashboard has been missing:
--   1) support_tickets: AI-escalated conversations become a queue an
--      admin can assign/close, with the device-log trail auto-attached.
--   2) curated_playlists: admin-published playlists (T3.4 reads these).
--   3) music_shelves_config already rides remote_config — no new table.
--
-- Privacy: a ticket carries the coarse trail + enum codes from T2.3,
-- never conversation text. The user's own words stay on the device; the
-- admin reply travels as an announcement/notice.
--
-- Idempotent.

-- ═══════════ 1) support_tickets ═══════════
create table if not exists support_tickets (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete set null,
  device_code   text not null default 'unknown'
                  check (device_code ~ '^(unknown|[1-9][0-9]{6})$'),
  platform      text not null default 'unknown',
  app_version   text not null default '',
  -- Coarse classification only: which support topic tree the AI matched.
  topic         text not null default 'other'
                  check (topic ~ '^[a-z][a-z0-9_]{0,31}$'),
  -- Enum codes the AI attached (T2.3 codes), never free text.
  codes         jsonb not null default '[]'::jsonb,
  trail         text not null default ''
                  check (trail = '' or trail ~ '^[a-z][a-z0-9_]{0,31}(>[a-z][a-z0-9_]{0,31})*$'),
  -- Deflection bookkeeping: did the AI answer close it, or did a human?
  ai_answered   boolean not null default false,
  status        text not null default 'open'
                  check (status in ('open', 'assigned', 'closed')),
  assigned_to   uuid references auth.users(id) on delete set null,
  resolution    text not null default ''
                  check (resolution in ('', 'ai_resolved', 'replied', 'fixed', 'duplicate', 'wontfix')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table support_tickets enable row level security;

create index if not exists support_tickets_status_idx
  on support_tickets (status, created_at desc);
create index if not exists support_tickets_user_idx
  on support_tickets (user_id, created_at desc);

-- The app may OPEN a ticket (its own row) but never read the queue.
drop policy if exists "users open own ticket" on support_tickets;
create policy "users open own ticket" on support_tickets
  for insert to authenticated with check (auth.uid() = user_id or user_id is null);

drop policy if exists "users see own ticket" on support_tickets;
create policy "users see own ticket" on support_tickets
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "admins manage tickets" on support_tickets;
create policy "admins manage tickets" on support_tickets
  for select to authenticated using (is_admin());

drop policy if exists "admins update tickets" on support_tickets;
create policy "admins update tickets" on support_tickets
  for update to authenticated using (is_admin());

-- ═══════════ 2) ticket RPCs ═══════════
-- App-side open (deflection path): ai_answered marks a solved-in-chat case
-- so the dashboard's deflection metric has a denominator.
create or replace function support_open_ticket(
  p_topic       text,
  p_device_code text default 'unknown',
  p_platform    text default 'unknown',
  p_version     text default '',
  p_codes       jsonb default '[]'::jsonb,
  p_trail       text default '',
  p_ai_answered boolean default false
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id    uuid;
  v_dev   text := left(lower(btrim(coalesce(p_device_code, ''))), 7);
  v_topic text := lower(btrim(coalesce(p_topic, 'other')));
  v_trail text := lower(btrim(coalesce(p_trail, '')));
  v_tok   text;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if v_dev !~ '^(unknown|[1-9][0-9]{6})$' then v_dev := 'unknown'; end if;
  if v_topic !~ '^[a-z][a-z0-9_]{0,31}$' then v_topic := 'other'; end if;

  -- Same trail discipline as the error pipeline.
  if v_trail <> '' then
    v_trail := left(v_trail, 240);
    if v_trail !~ '^[a-z][a-z0-9_]{0,31}(>[a-z][a-z0-9_]{0,31})*$' then
      v_trail := '';
    end if;
  end if;

  insert into support_tickets(user_id, device_code, platform, app_version,
                              topic, codes, trail, ai_answered)
    values (auth.uid(), v_dev, left(lower(btrim(coalesce(p_platform,''))), 8), left(btrim(coalesce(p_version,'')), 32),
            v_topic, coalesce(p_codes, '[]'::jsonb), v_trail, coalesce(p_ai_answered, false))
    returning id into v_id;
  return v_id;
end;
$$;
revoke all on function support_open_ticket(text, text, text, text, jsonb, text, boolean) from public;
grant execute on function support_open_ticket(text, text, text, text, jsonb, text, boolean) to authenticated;

-- Dashboard queue read (support + owner), newest first, filterable.
create or replace function admin_support_tickets(
  p_status text default '',
  p_limit  int default 50
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb; v_status text := lower(btrim(coalesce(p_status, '')));
begin
  perform require_role(array['owner', 'support']);
  select coalesce(jsonb_agg(t order by t.created_at desc), '[]'::jsonb) into v
    from (
      select s.id, s.device_code, s.platform, s.app_version, s.topic,
             s.codes, s.trail, s.ai_answered, s.status, s.resolution,
             s.created_at, s.updated_at,
             (select username from usernames w where w.user_id = s.user_id) as username,
             s.user_id
        from support_tickets s
       where (v_status = '' or s.status = v_status)
       order by s.created_at desc
       limit greatest(least(p_limit, 200), 1)
    ) t;
  return coalesce(v, '[]'::jsonb);
end;
$$;
revoke all on function admin_support_tickets(text, int) from public;
grant execute on function admin_support_tickets(text, int) to authenticated;

-- Assign / close / resolve (support + owner).
create or replace function admin_ticket_action(
  p_id         uuid,
  p_action     text,
  p_resolution text default ''
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_status text; v_res text := lower(btrim(coalesce(p_resolution, '')));
begin
  perform require_role(array['owner', 'support']);
  if p_action = 'assign' then
    v_status := 'assigned';
  elsif p_action = 'close' then
    v_status := 'closed';
    if v_res = '' then v_res := 'replied'; end if;
    if v_res not in ('ai_resolved','replied','fixed','duplicate','wontfix') then
      raise exception 'bad resolution';
    end if;
  elsif p_action = 'reopen' then
    v_status := 'open';
    v_res := '';
  else
    raise exception 'bad action';
  end if;

  update support_tickets
     set status = v_status,
         assigned_to = case when p_action = 'assign' then auth.uid()
                            when p_action = 'reopen' then null
                            else assigned_to end,
         resolution = case when p_action = 'close' then v_res else resolution end,
         updated_at = now()
   where id = p_id;
  if not found then return false; end if;

  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'ticket:' || p_action, p_id::text,
            jsonb_build_object('resolution', v_res));
  return true;
end;
$$;
revoke all on function admin_ticket_action(uuid, text, text) from public;
grant execute on function admin_ticket_action(uuid, text, text) to authenticated;

-- Deflection metric for the overview (support + owner).
create or replace function admin_support_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  perform require_role(array['owner', 'support']);
  select jsonb_build_object(
    'open',      count(*) filter (where status = 'open'),
    'assigned',  count(*) filter (where status = 'assigned'),
    'closed',    count(*) filter (where status = 'closed'),
    'total_30d', count(*) filter (where created_at > now() - interval '30 days'),
    'ai_solved', count(*) filter (where ai_answered and resolution = 'ai_resolved'),
    'human',     count(*) filter (where resolution in ('replied','fixed'))
  ) into v from support_tickets;
  return coalesce(v, '{}'::jsonb);
end;
$$;
revoke all on function admin_support_stats() from public;
grant execute on function admin_support_stats() to authenticated;

-- ═══════════ 3) curated_playlists (T3.4 publishes here) ═══════════
create table if not exists curated_playlists (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique
                check (slug ~ '^[a-z0-9-]{2,64}$'),
  title       text not null default '',
  subtitle    text not null default '',
  cover_url   text not null default '',
  -- Rail placement (T3.1 shelves read this).
  rail        text not null default 'dizzy_pick',
  position    int not null default 100,
  -- Ordered track refs: [{id, title, artist, coverUrl, source}] — resolved
  -- by the app against its own resolvers, so no audio URLs live here.
  tracks      jsonb not null default '[]'::jsonb,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table curated_playlists enable row level security;

create index if not exists curated_playlists_rail_idx
  on curated_playlists (rail, position) where active;

-- Everyone reads active playlists; only admins write.
drop policy if exists "anyone reads curated playlists" on curated_playlists;
create policy "anyone reads curated playlists" on curated_playlists
  for select to anon, authenticated using (active or is_admin());

create or replace function admin_curated_upsert(
  p_id       text,
  p_slug     text,
  p_title    text,
  p_subtitle text,
  p_cover    text,
  p_rail     text,
  p_position int,
  p_tracks   jsonb,
  p_active   boolean
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_slug text := lower(btrim(coalesce(p_slug, '')));
begin
  perform require_role(array['owner', 'curator']);
  if v_slug !~ '^[a-z0-9-]{2,64}$' then raise exception 'bad slug'; end if;
  if nullif(p_id, '') is null then
    insert into curated_playlists(slug, title, subtitle, cover_url, rail, position, tracks, active)
      values (v_slug, left(coalesce(p_title,''),120), left(coalesce(p_subtitle,''),200),
              coalesce(p_cover,''), coalesce(nullif(p_rail,''),'dizzy_pick'),
              coalesce(p_position, 100), coalesce(p_tracks,'[]'::jsonb), coalesce(p_active,true))
      on conflict (slug) do update set title=excluded.title, subtitle=excluded.subtitle,
        cover_url=excluded.cover_url, rail=excluded.rail, position=excluded.position,
        tracks=excluded.tracks, active=excluded.active, updated_at=now()
      returning id into v_id;
  else
    v_id := p_id::uuid;
    update curated_playlists set slug=v_slug, title=left(coalesce(p_title,''),120),
      subtitle=left(coalesce(p_subtitle,''),200), cover_url=coalesce(p_cover,''),
      rail=coalesce(nullif(p_rail,''),'dizzy_pick'), position=coalesce(p_position,100),
      tracks=coalesce(p_tracks,'[]'::jsonb), active=coalesce(p_active,true), updated_at=now()
      where id = v_id;
  end if;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'curated:upsert', v_id::text,
            jsonb_build_object('slug', v_slug, 'rail', p_rail,
                               'tracks', coalesce(jsonb_array_length(p_tracks), 0)));
  return v_id::text;
end;
$$;
revoke all on function admin_curated_upsert(text, text, text, text, text, text, int, jsonb, boolean) from public;
grant execute on function admin_curated_upsert(text, text, text, text, text, text, int, jsonb, boolean) to authenticated;

create or replace function admin_curated_delete(p_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform require_role(array['owner', 'curator']);
  delete from curated_playlists where id = p_id::uuid;
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'curated:delete', p_id, '{}');
  return found;
end;
$$;
revoke all on function admin_curated_delete(text) from public;
grant execute on function admin_curated_delete(text) to authenticated;

create or replace function admin_curated_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  perform require_role(array['owner', 'curator']);
  select coalesce(jsonb_agg(t order by t.rail, t.position), '[]'::jsonb) into v
    from (select id, slug, title, subtitle, rail, position, active,
                 coalesce(jsonb_array_length(tracks), 0) as track_count, updated_at
            from curated_playlists) t;
  return coalesce(v, '[]'::jsonb);
end;
$$;
revoke all on function admin_curated_list() from public;
grant execute on function admin_curated_list() to authenticated;