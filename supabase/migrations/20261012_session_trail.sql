-- v1.3.3-T2.3 — rich log pipeline: session trail on device_logs.
--
-- The old pipeline stored one enum code per (device, screen, code) triple
-- with zero context: a crash arrived with no idea what the user was doing.
-- This adds a bounded, enum-only `trail` (nav/playback/net tokens joined
-- by '>') so the dashboard can render a session timeline.
--
-- PRIVACY: the trail is validated token-by-token here, not only in the
-- client. Any non-enum token voids the whole trail (never partially
-- forwarded — that is how free text leaks into telemetry).
--
-- Idempotent.

-- ═══════════ 1) column ═══════════
alter table device_logs
  add column if not exists trail text not null default '';

-- Whole trail must stay small; the client trims to 240.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'device_logs_trail_len'
  ) then
    alter table device_logs
      add constraint device_logs_trail_len check (char_length(trail) <= 240);
  end if;
end $$;

-- Fold key must include the trail, or two different crash paths collapse
-- into one row and the timeline of the second is lost.
drop index if exists device_logs_fold_idx;
create unique index if not exists device_logs_fold_idx
  on device_logs (device_code, screen, code, detail, trail)
  where device_code <> 'unknown';

-- ═══════════ 2) report_error with trail ═══════════
-- The old 6-arg function is DROPPED: keeping both would leave two bodies
-- that silently diverge (an older caller would write rows with no trail
-- while looking perfectly healthy). The 7th argument carries a DEFAULT,
-- so every existing 6-arg call — positional or named, from the edge
-- function or a direct REST probe — resolves here unchanged.
drop function if exists report_error(text, text, text, text, text, text);

create or replace function report_error(
  p_device_code text,
  p_platform    text,
  p_version     text,
  p_screen      text,
  p_code        text,
  p_detail      text,
  p_trail       text default ''
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device   text;
  v_platform text;
  v_version  text;
  v_screen   text;
  v_code     text;
  v_detail   text;
  v_trail    text := '';
  v_tok      text;
  v_events   bigint;
  c_rate_cap constant int := 50; -- report events per device per 24h
begin
  -- Normalise: trim + lowercase, then validate against the allowlists.
  v_device := lower(btrim(coalesce(p_device_code, '')));
  if v_device !~ '^(unknown|[1-9][0-9]{6})$' then v_device := 'unknown'; end if;

  v_platform := lower(btrim(coalesce(p_platform, '')));
  if v_platform !~ '^(android|ios|windows|linux|macos|fuchsia|web|unknown)$'
    then v_platform := 'unknown'; end if;

  v_version := left(btrim(coalesce(p_version, '')), 32);

  v_screen := left(lower(btrim(coalesce(p_screen, ''))), 64);
  if v_screen !~ '^[a-z0-9_]{1,64}$' then v_screen := 'unknown'; end if;

  -- The code is the only field with no safe default: an unknown code is
  -- not telemetry, it is noise. Reject it.
  v_code := left(lower(btrim(coalesce(p_code, ''))), 48);
  if v_code !~ '^[a-z0-9_]{1,48}$' then return false; end if;

  v_detail := left(lower(btrim(coalesce(p_detail, ''))), 64);
  if v_detail !~ '^[a-z0-9_.-]*$' then v_detail := ''; end if;

  -- Trail: every token must be an enum, else the whole trail is dropped.
  v_trail := left(lower(btrim(coalesce(p_trail, ''))), 240);
  if v_trail <> '' then
    foreach v_tok in array string_to_array(v_trail, '>') loop
      if v_tok !~ '^[a-z][a-z0-9_]{0,31}$' then
        v_trail := '';
        exit;
      end if;
    end loop;
  end if;

  -- Per-device volume cap (unchanged): a looping install cannot flood.
  select count(*) into v_events
    from device_logs
   where device_code = v_device
     and last_at > now() - interval '24 hours';
  if v_events >= c_rate_cap then return false; end if;

  if v_device = 'unknown' then
    insert into device_logs(device_code, platform, app_version, screen, code, detail, trail)
      values (v_device, v_platform, v_version, v_screen, v_code, v_detail, v_trail);
  else
    insert into device_logs(device_code, platform, app_version, screen, code, detail, trail)
      values (v_device, v_platform, v_version, v_screen, v_code, v_detail, v_trail)
      on conflict (device_code, screen, code, detail, trail)
        where device_code <> 'unknown'
        do update set count = device_logs.count + 1,
                      last_at = now(),
                      app_version = excluded.app_version,
                      platform = excluded.platform;
  end if;
  return true;
end;
$$;
revoke all on function report_error(text, text, text, text, text, text, text) from public;
grant execute on function report_error(text, text, text, text, text, text, text) to authenticated;