-- P22: catalog warm-cache (run ONCE in Supabase SQL Editor).
--
-- `catalog_cache` holds the last-good browse feeds written by the `catalog`
-- edge function (read-through: fresh <6h served warm; cold TMDB fetch
-- upserts). Public read so keyless devices browse; only the service role
-- (edge fn) writes — enforced by RLS (no write policy for anon/auth).
--
-- After this: Dashboard → Edge Functions → catalog → Schedules → New:
--   cron `30 6 * * *` (= 12:00 IST) hitting the trending/popular URLs
--   (any HTTP ping works — each hit refreshes the warm rows).

create table if not exists catalog_cache (
  cache_key text primary key,          -- 'feed|type|page'
  feed text not null,
  type text not null default 'all',
  page int not null default 1,
  items jsonb not null default '[]',
  updated_at timestamptz not null default now()
);

alter table catalog_cache enable row level security;

drop policy if exists "anyone reads warm catalog" on catalog_cache;
create policy "anyone reads warm catalog"
  on catalog_cache for select
  using (true);
-- NOTE: no insert/update/delete policies → only service_role writes.
