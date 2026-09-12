-- P22 cron doc (the LIVE job was created via CLI, not this file, because the
-- edge fn needs the anon apikey header — never commit keys to git).
-- Live job: 'catalog-noon-refresh', cron '30 6 * * *' (= 12:00 IST),
-- hits catalog?feed=trending + ?feed=popular with apikey header.
-- Recreate via: supabase db query --linked --file <tmpfile-with-key>
select cron.schedule(
  'catalog-noon-refresh',
  '30 6 * * *',
  'select 1;'
);
