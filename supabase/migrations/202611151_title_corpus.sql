-- Dizzy v1.3.5 - title corpus (2026-11-14)
--
-- Why this table exists
-- --------------------
-- Measured on 2026-11-14 against the owner's 50 latest Odia movies:
--
--   * the app's cloud resolver answered 30/50 (the other 20 -> 404)
--   * for 18 of those 20, TMDB's /search/movie returns ZERO hits
--     (not a near miss - a blank). TMDB simply will not surface these
--     regional titles through search.
--   * TMDB's /discover/movie?with_original_language=or DOES return them.
--
-- So a title -> TMDB id lookup cannot be a search. It has to be an index.
-- This table is that index: one row per (kind, TMDB id) with the names the
-- app might know the title by, plus a normalised "core" name (subtitle and
-- brackets removed) so "Dahaan: The Evil Within" finds the row titled
-- "Dahaan".
--
-- Anime is indexed in the same table (original_language ja / zh) with the
-- English name as the primary title, so an English/Romaji anime title from
-- the app's AniList catalogue can still reach a TMDB id.
--
-- Access: service role only. The resolver (edge function) reads it with the
-- service role key; RLS is enabled and no anon/authenticated policy exists,
-- so the table is invisible to the public API.
--
-- Apply with:  supabase db query --linked -f supabase/migrations/20261115_title_corpus.sql
-- (never `supabase db push --include-all`)

-- ── 1. the table ─────────────────────────────────────────────────────────
create table if not exists public.title_corpus (
  id             bigint generated always as identity primary key,
  kind           text        not null check (kind in ('movie', 'tv')),
  tmdb_id        integer     not null,
  title          text        not null,
  original_title text,
  title_norm     text        not null,   -- cleaned: lowercase, alnum only
  title_base     text        not null,   -- core: subtitle/brackets removed
  year           integer,
  lang           text,
  popularity     double precision not null default 0,
  source         text        not null default 'tmdb-discover',
  updated_at     timestamptz not null default now(),
  constraint title_corpus_kind_tmdb_uniq unique (kind, tmdb_id)
);

comment on table public.title_corpus is
  'Title -> TMDB id index for the resolver (regional + anime). Service role only.';

-- The resolver looks up by exact norm first, then by core name, then by
-- year for the fuzzy pass. These three indexes cover those lookups.
create index if not exists title_corpus_norm_idx
  on public.title_corpus (kind, title_norm);
create index if not exists title_corpus_base_idx
  on public.title_corpus (kind, title_base);
create index if not exists title_corpus_year_idx
  on public.title_corpus (kind, year);
create index if not exists title_corpus_lang_idx
  on public.title_corpus (lang);

-- ── 2. lock it down ─────────────────────────────────────────────────────
alter table public.title_corpus enable row level security;

-- No anon/authenticated policies on purpose: the edge function reads this
-- with the service role key, which bypasses RLS. A public SELECT would
-- hand the whole index to any visitor.
--
-- The resolver's lookup is a single indexed SELECT:
--   select ... from title_corpus
--    where kind = $1
--      and (title_norm = $norm or title_base = $base or title_base = $norm
--           or (year between $y - 1 and $y + 1))
-- The year window is the bounded candidate set for the one-edit pass.
