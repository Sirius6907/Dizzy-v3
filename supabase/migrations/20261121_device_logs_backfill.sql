-- Dizzy v1.4.3 — Phase 2: backfill the orphaned telemetry.
-- Run AFTER 20261121_device_code_registry.sql:
--   supabase db query --linked -f supabase/migrations/20261121_device_logs_backfill.sql
--
-- This is a DATA migration, deliberately separate from the schema file so it
-- can be re-run on its own and so its blast radius is obvious. It is
-- idempotent: every statement only fills a NULL or corrects a timestamp, and
-- never overwrites a fact.
--
-- What it does:
--   1. Registers every code a current `devices` row still carries.
--   2. For every code that only exists in `device_logs`, tries to prove which
--      physical device minted it. A pre-Phase-H install derived its legacy
--      hwid as sha256('dizzy_hwid_<code>_salt') — that value is still on
--      `devices.hwid_legacy`, so the match is a proof, not a guess.
--   3. Codes that cannot be proven are still registered with a NULL
--      device_id. They stop being "orphans" and become "unlinked": the panel
--      can group them, show their volume and first/last seen, and a future
--      boot that presents the same code attaches them automatically.
--   4. Stamps `device_logs.device_id` / `user_id` from the registry.
--
-- Nothing is deleted. A row whose owner cannot be proven keeps its code and
-- simply has no device_id — the honest answer.

-- ═══════════ 1) current device codes ═══════════
-- first/last seen come from the device row, not from `now()`, or the registry
-- would claim every code was active on migration day and Phase 5's pruning
-- would never be able to retire anything.
insert into public.device_codes
  (code, device_id, user_id, first_seen_at, last_seen_at, source)
select btrim(d.device_code), d.device_id, d.user_id,
       coalesce(d.created_at, now()),
       coalesce(d.last_seen_at, now()),
       'boot'
from public.devices d
where btrim(d.device_code) ~ '^[1-9][0-9]{6}$'
on conflict (code) do nothing;

-- ═══════════ 2) orphan codes: prove the owner where possible ═══════════
insert into public.device_codes
  (code, device_id, user_id, first_seen_at, last_seen_at, source)
select
  o.code,
  d.device_id,
  d.user_id,
  coalesce(o.first_at, now()),
  coalesce(o.last_at, now()),
  'backfill'
from (
  select l.device_code as code,
         min(l.first_at) as first_at,
         max(l.last_at)  as last_at
  from public.device_logs l
  where l.device_code <> 'unknown'
  group by l.device_code
) o
left join lateral (
  -- sha256('dizzy_hwid_' || code || '_salt') is the legacy hwid the client
  -- sent before the stable-identity migration. Unique by construction; the
  -- LIMIT only guards against a duplicated legacy hash.
  select dv.device_id, dv.user_id
  from public.devices dv
  where dv.hwid_legacy =
        encode(extensions.digest('dizzy_hwid_' || o.code || '_salt', 'sha256'), 'hex')
  order by dv.last_seen_at desc nulls last
  limit 1
) d on true
on conflict (code) do nothing;

-- A registry row that was created unlinked by an earlier run (or by a
-- report that arrived before its device booted) gets its owner filled in
-- the moment the proof exists.
update public.device_codes dc
set device_id = d.device_id,
    user_id   = coalesce(dc.user_id, d.user_id)
from public.devices d
where dc.device_id is null
  and d.hwid_legacy =
      encode(extensions.digest('dizzy_hwid_' || dc.code || '_salt', 'sha256'), 'hex');

-- ═══════════ 3) honest activity windows ═══════════
-- Rows written by a first run of this file (or by a live touch) may carry a
-- `now()` timestamp. Replace it with the window the telemetry actually
-- proves, so "first seen / last seen" means something.
update public.device_codes dc
set first_seen_at = x.first_at,
    last_seen_at  = x.last_at
from (
  select l.device_code as code,
         min(l.first_at) as first_at,
         max(l.last_at)  as last_at
  from public.device_logs l
  where l.device_code <> 'unknown'
  group by l.device_code
) x
where dc.code = x.code
  and dc.source = 'backfill';

update public.device_codes dc
set first_seen_at = least(dc.first_seen_at,
                          coalesce(d.created_at, dc.first_seen_at)),
    last_seen_at  = greatest(
                      coalesce(d.last_seen_at, dc.last_seen_at),
                      coalesce((select max(l.last_at)
                                  from public.device_logs l
                                 where l.device_code = dc.code), dc.last_seen_at))
from public.devices d
where btrim(d.device_code) = dc.code
  and dc.source <> 'backfill';

-- ═══════════ 4) stamp the telemetry ═══════════
update public.device_logs l
set device_id = dc.device_id,
    user_id   = coalesce(l.user_id, dc.user_id)
from public.device_codes dc
where dc.code = l.device_code
  and l.device_id is null
  and (dc.device_id is not null or dc.user_id is not null);

-- ═══════════ 5) report ═══════════
select
  (select count(*) from public.device_codes) as registry_codes,
  (select count(*) from public.device_codes where device_id is not null) as linked_codes,
  (select count(*) from public.device_codes where device_id is null) as unlinked_codes,
  (select count(*) from public.device_logs where device_id is null
     and device_code <> 'unknown') as rows_still_unlinked,
  (select coalesce(sum(count), 0) from public.device_logs where device_id is null
     and device_code <> 'unknown') as hits_still_unlinked,
  (select count(*) from public.device_logs where device_id is not null) as rows_linked,
  (select coalesce(sum(count), 0) from public.device_logs where device_id is not null) as hits_linked;
