-- Dizzy v1.3.5 - nightly title-corpus sync (2026-11-14)
--
-- The resolver answers "which TMDB id is this title?" from the corpus
-- table, because TMDB's /search cannot see regional titles (measured:
-- 18 of 20 sampled Odia films return ZERO search hits) while
-- /discover does. The corpus therefore has to be kept warm, or the
-- resolver falls back to a name-only match - which is how a Spanish
-- "GAME OVER" answered a 2026 Odia request.
--
-- The job calls the `corpus-sync` edge function with the same cron token
-- the release-scan job uses (public.app_secrets.push_cron_token), so no
-- secret is hardcoded here.
--
-- APPLY ORDER:
--   1. deploy the function:  supabase functions deploy corpus-sync --no-verify-jwt
--   2. apply this file:      supabase db query --linked -f supabase/migrations/20261115_corpus_cron.sql
--      (never `supabase db push --include-all`)

-- The corpus sync reads TMDB (hi/te/ml/kn/or + ja for anime) and writes
-- public.title_corpus. It re-uses the existing edge-call helper, so the
-- job is a no-op when the token or the base URL is not configured yet.
do $$
declare
  v_job bigint;
begin
  for v_job in
    select jobid from cron.job
     where jobname in ('dizzy-corpus-sync', 'dizzy-corpus-sync-release')
  loop
    perform cron.unschedule(v_job);
  end loop;

  -- Two sweeps, two jobs, so neither run gets near the edge time limit:
  --   20:40 UTC (02:10 IST) - the most watched titles (the catalogue)
  --   21:10 UTC (02:40 IST) - the newest titles, by release date (the
  --                            films that came out this month; a new Odia
  --                            film has zero votes, so a popularity sort
  --                            never reaches it)
  -- Both write into the same table, so the rows accumulate.
  perform cron.schedule(
    'dizzy-corpus-sync',
    '40 20 * * *',
    $job$select public.call_edge_function('corpus-sync', '{"sweep":"popularity"}'::jsonb);$job$
  );
  perform cron.schedule(
    'dizzy-corpus-sync-release',
    '10 21 * * *',
    $job$select public.call_edge_function('corpus-sync', '{"sweep":"release"}'::jsonb);$job$
  );
end;
$$;
