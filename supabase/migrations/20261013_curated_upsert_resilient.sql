-- 20261013_curated_upsert_resilient.sql
-- Resilient admin_curated_upsert:
-- 1) Auto-generates slug from title if empty.
-- 2) Normalises slug (spaces/symbols -> hyphens, lowercased, trimmed).
-- 3) Defensively parses p_tracks (wraps single objects into arrays, handles nulls).
-- 4) Prevents crash in jsonb_array_length on non-arrays.

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
declare
  v_id         uuid;
  v_slug       text := lower(btrim(coalesce(p_slug, '')));
  v_title      text := left(btrim(coalesce(p_title, '')), 120);
  v_tracks     jsonb;
  v_track_cnt  int;
begin
  perform require_role(array['owner', 'curator']);

  -- 1. Defend p_tracks: must be a jsonb array
  if p_tracks is null then
    v_tracks := '[]'::jsonb;
  elsif jsonb_typeof(p_tracks) = 'array' then
    v_tracks := p_tracks;
  elsif jsonb_typeof(p_tracks) = 'object' then
    v_tracks := jsonb_build_array(p_tracks);
  else
    v_tracks := '[]'::jsonb;
  end if;

  v_track_cnt := jsonb_array_length(v_tracks);

  -- 2. Auto-slug from title if slug not provided
  if v_slug = '' then
    if v_title != '' then
      v_slug := lower(regexp_replace(regexp_replace(v_title, '[^a-zA-Z0-9]+', '-', 'g'), '^-|-$', '', 'g'));
    else
      v_slug := 'curated-' || substr(md5(random()::text), 1, 6);
    end if;
  end if;

  -- Normalise slug: replace spaces, underscores, symbols with hyphens
  v_slug := lower(regexp_replace(regexp_replace(v_slug, '[^a-z0-9-]+', '-', 'g'), '-+', '-', 'g'));
  v_slug := regexp_replace(v_slug, '^-|-$', '', 'g');

  if length(v_slug) < 2 then
    v_slug := v_slug || '-list';
  end if;
  if length(v_slug) > 64 then
    v_slug := left(v_slug, 64);
  end if;

  if v_slug !~ '^[a-z0-9-]{2,64}$' then
    raise exception 'bad slug: must be 2-64 chars of lowercase letters, numbers, hyphens (got "%")', v_slug;
  end if;

  -- 3. Upsert into curated_playlists
  if nullif(p_id, '') is null then
    insert into curated_playlists(slug, title, subtitle, cover_url, rail, position, tracks, active)
      values (v_slug,
              case when v_title = '' then 'Curated Playlist' else v_title end,
              left(coalesce(p_subtitle, ''), 200),
              coalesce(p_cover, ''),
              coalesce(nullif(p_rail, ''), 'dizzy_pick'),
              coalesce(p_position, 100),
              v_tracks,
              coalesce(p_active, true))
      on conflict (slug) do update set
        title = excluded.title,
        subtitle = excluded.subtitle,
        cover_url = excluded.cover_url,
        rail = excluded.rail,
        position = excluded.position,
        tracks = excluded.tracks,
        active = excluded.active,
        updated_at = now()
      returning id into v_id;
  else
    v_id := p_id::uuid;
    update curated_playlists set
      slug = v_slug,
      title = case when v_title = '' then 'Curated Playlist' else v_title end,
      subtitle = left(coalesce(p_subtitle, ''), 200),
      cover_url = coalesce(p_cover, ''),
      rail = coalesce(nullif(p_rail, ''), 'dizzy_pick'),
      position = coalesce(p_position, 100),
      tracks = v_tracks,
      active = coalesce(p_active, true),
      updated_at = now()
      where id = v_id;
  end if;

  -- 4. Audit trail
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'curated:upsert', v_id::text,
            jsonb_build_object('slug', v_slug, 'rail', coalesce(nullif(p_rail, ''), 'dizzy_pick'), 'tracks', v_track_cnt));

  return v_id::text;
end;
$$;
