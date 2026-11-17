-- Dizzy v1.3.5 — nightly warm of the release-date-driven "latest releases"
-- catalogue feed (2026-11-14).
--
-- Owner decision: the nightly refresh runs as a pg_cron job in the
-- database, so the catalogue rows the Home rails read are already warm
-- when users open the app (no cold, slow first paint in the morning).
--
-- What it does, every night:
--   1. calls the `catalog` edge function with feed=latest for the
--      Bollywood buckets (hi, te, ml, kn) and the Ollywood bucket (or),
--      for movie and tv;
--   2. the edge function's own read-through cache stores the result, so
--      the app then reads warm rows.
--
-- PRECONDITION: the `catalog` function must already be deployed with the
-- `latest` feed wired in (supabase/functions/catalog/latest_releases.ts +
-- the feed branch in index.ts). Until then these jobs would call a feed
-- that does not exist yet, so apply this AFTER that deploy.
--
-- APPLY ORDER:
--   1. deploy the edge function:  supabase functions deploy catalog
--   2. store the call key once:    python artifacts/audit-dsh/scripts/store_vault_secret.py
--   3. apply this file:           supabase db query --linked -f supabase/migrations/20261114_latest_releases_cron.sql
--      (never `supabase db push --include-all`)
--
-- The call key is the project's publishable/anon key (the same one the
-- app already sends as `apikey`); it is stored in Vault, never in this
-- file, never in git.

-- ── 1. extensions ────────────────────────────────────────────────────────
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- ── 2. the call key lives in Vault ───────────────────────────────────────
-- Stored by artifacts/audit-dsh/scripts/store_vault_secret.py as
-- 'catalog_anon_key'. The job reads it from there; nothing is hardcoded.

-- ── 3. helper: build the job list ───────────────────────────────────────
create or replace function public.refresh_latest_releases_catalogue()
returns void
language plpgsql
security definer
set search_path = public, extensions, vault, pg_catalog
as $$
declare
  v_url text;
  v_key text;
  v_edge text;
  v_lang text;
  v_type text;
  v_body jsonb;
begin
  select decrypted_secret into v_key
    from vault.decrypted_secrets
   where name = 'catalog_anon_key'
   limit 1;

  if v_key is null then
    raise warning 'catalog_anon_key missing from vault; skipping nightly warm';
    return;
  end if;

  select coalesce(current_setting('app.settings.project_url', true), '')
    into v_url;

  if v_url is null or v_url = '' then
    raise warning 'app.settings.project_url is not set; skipping nightly warm';
    return;
  end if;

  v_edge := v_url || '/functions/v1/catalog?feed=latest&region=IN&type=';

  foreach v_lang in array array['hi', 'te', 'ml', 'kn', 'or'] loop
    foreach v_type in array array['movie', 'tv'] loop
      v_body := jsonb_build_object(
        'headers', jsonb_build_object(
          'apikey', v_key,
          'Content-Type', 'application/json'
        ),
        'body', jsonb_build_object('page', '1')
      );

      perform net.http_post(
        url     := v_edge || v_type || '&language=' || v_lang,
        headers := (v_body ->> 'headers')::jsonb,
        body    := (v_body ->> 'body')::jsonb,
        timeout_milliseconds := 20000
      );
    end loop;
  end loop;
end;
$$;

comment on function public.refresh_latest_releases_catalogue() is
  'Nightly warm of the release-date-driven latest-releases catalogue feed (owner-approved 2026-11-14).';

-- ── 4. the schedule ──────────────────────────────────────────────────────
-- 03:20 IST = 21:50 UTC the previous day. pg_cron runs on UTC.
do $$
declare
  v_job bigint;
begin
  select jobid into v_job
    from cron.job
   where jobname = 'dizzy-latest-releases-nightly';

  if v_job is null then
    perform cron.schedule(
      'dizzy-latest-releases-nightly',
      '50 21 * * *',
      $cron$select public.refresh_latest_releases_catalogue();$cron$
    );
  else
    perform cron.unschedule(v_job);
    perform cron.schedule(
      'dizzy-latest-releases-nightly',
      '50 21 * * *',
      $cron$select public.refresh_latest_releases_catalogue();$cron$
    );
  end if;
end;
$$;
