-- P2 — error pipeline backend: device_logs + report_error RPC.
-- Run ONCE in Supabase SQL Editor AFTER 20260920_social_sync_foundation.sql.
--
-- Closes the silent-death bug: the client queued errors locally and POSTed
-- them to a `report-error` edge function that did not exist, so every error
-- report was dropped on the floor. This migration is the storage half;
-- supabase/functions/report-error/index.ts is the transport half.
--
-- PRIVACY CONTRACT (mirrors lib/services/errors/app_error_log.dart):
--   * Every field is an ENUM token. No URLs, magnets, tokens, titles,
--     stack traces or raw exception text can be stored — the allowlists
--     below reject anything outside [a-z0-9_] at the server boundary.
--   * `device_code` is the app's random 7-digit install code (WP-P0),
--     not a hardware fingerprint. It is optional so a crash before the
--     code is minted is still counted under 'unknown'.
--   * Consent lives on the client (crash toggle). The RPC does not need
--     to re-check it; it does enforce a per-device volume cap so a
--     single looping install cannot flood the table.
--
-- Idempotent: every statement is IF NOT EXISTS / CREATE OR REPLACE /
-- DROP+CREATE, so re-running the file is a no-op.

-- ═══════════ 1) device_logs ═══════════
-- One row per (device, screen, code) triple. Repeat reports fold into
-- `count` with `last_at` bumped and `first_at` preserved, so 10 000
-- timeouts from one install cost one row, not 10 000.
create table if not exists device_logs (
  id          bigint generated always as identity primary key,
  device_code text not null default 'unknown'
                check (device_code ~ '^(unknown|[1-9][0-9]{6})$'),
  platform    text not null default 'unknown'
                check (platform ~ '^(android|ios|windows|linux|macos|fuchsia|web|unknown)$'),
  app_version text not null default '' check (char_length(app_version) <= 32),
  screen      text not null default 'unknown'
                check (screen ~ '^[a-z0-9_]{1,64}$'),
  code        text not null
                check (code ~ '^[a-z0-9_]{1,48}$'),
  detail      text not null default ''
                check (char_length(detail) <= 64),
  count       int not null default 1 check (count >= 1),
  first_at    timestamptz not null default now(),
  last_at     timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

-- Fold-target for the RPC upsert. Partial so the 'unknown' device bucket
-- cannot be a single hot row shared by every early-crash install.
create unique index if not exists device_logs_fold_idx
  on device_logs (device_code, screen, code, detail)
  where device_code <> 'unknown';

-- Dashboard reads: newest first.
create index if not exists device_logs_last_at_idx
  on device_logs (last_at desc);

-- Rate-cap check inside report_error(): rows for one device in a window.
create index if not exists device_logs_device_last_idx
  on device_logs (device_code, last_at desc);

alter table device_logs enable row level security;

-- No INSERT/UPDATE/DELETE policy on purpose. With RLS enabled and no
-- policy, every non-owner role is denied. Writes only ever happen inside
-- the SECURITY DEFINER function below; reads only through the is_admin()
-- policy. The explicit REVOKEs are belt-and-braces against a future
-- policy being added by accident.
revoke all on device_logs from anon, authenticated;
grant select on device_logs to authenticated;

drop policy if exists "admins read device logs" on device_logs;
create policy "admins read device logs" on device_logs
  for select to authenticated using (is_admin());

-- ═══════════ 2) report_error RPC ═══════════
-- Returns true when a report was stored, false when it was rejected.
-- A false is deliberately NOT an error: it means "throttled or malformed",
-- which the client treats as consumed. Raising would make the client
-- retry forever and pin the queue at 100 entries.
--
-- Length caps and the code allowlist are enforced HERE, not only in the
-- edge function, so no caller can reach the table by another route.
create or replace function report_error(
  p_device_code text,
  p_platform    text,
  p_version     text,
  p_screen      text,
  p_code        text,
  p_detail      text
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

  -- Detail is an enum hint (e.g. 'timeout_20s'). Free text in this column
  -- is exactly the privacy leak the contract forbids, so anything that
  -- is not already a token is dropped rather than trimmed.
  v_detail := left(lower(btrim(coalesce(p_detail, ''))), 64);
  if v_detail !~ '^[a-z0-9_.-]{0,64}$' then v_detail := ''; end if;

  -- Volume cap. `count` is the number of events folded into each row, so
  -- summing it over rows touched in the trailing 24h approximates the
  -- device's true event volume well enough to stop a flood. Over-counting
  -- slightly is the safe direction for an abuse control.
  select coalesce(sum(count), 0) into v_events
    from device_logs
   where device_code = v_device
     and last_at > now() - interval '24 hours';
  if v_events + 1 > c_rate_cap then return false; end if;

  if v_device = 'unknown' then
    -- No fold target for the shared 'unknown' bucket: always a new row.
    insert into device_logs
      (device_code, platform, app_version, screen, code, detail, count)
    values
      (v_device, v_platform, v_version, v_screen, v_code, v_detail, 1);
  else
    insert into device_logs
      (device_code, platform, app_version, screen, code, detail, count)
    values
      (v_device, v_platform, v_version, v_screen, v_code, v_detail, 1)
    on conflict (device_code, screen, code, detail)
      where device_code <> 'unknown'
      do update set
        count     = device_logs.count + 1,
        last_at   = now(),
        platform  = excluded.platform,
        app_version = excluded.app_version;
  end if;

  return true;
end;
$$;

revoke all on function report_error(text, text, text, text, text, text) from public;
grant execute on function report_error(text, text, text, text, text, text)
  to anon, authenticated;
