-- Nudge cooldown for update campaigns.
--
-- push-send stamps this only on rows whose FCM send actually succeeded, so a
-- phone that read "please update" is skipped by later campaigns for seven
-- days. A failed delivery leaves the row untouched and stays eligible.
--
-- Nullable, no default, on purpose: every existing row means "never nudged",
-- which is exactly the state a fresh migration should leave behind.

alter table public.device_tokens
  add column if not exists last_nudged_at timestamptz;

comment on column public.device_tokens.last_nudged_at is
  'Last successful update-campaign push; campaigns skip rows younger than 7 days.';
