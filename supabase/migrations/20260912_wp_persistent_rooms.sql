-- v1.2.0 P1: persistent rooms — media_ref optional, live "now watching" columns.
-- Rooms are spaces; media is an event. Old rows keep working (backfilled).

ALTER TABLE public.rooms ALTER COLUMN media_ref DROP NOT NULL;

ALTER TABLE public.rooms
  ADD COLUMN IF NOT EXISTS current_media_ref text;
ALTER TABLE public.rooms
  ADD COLUMN IF NOT EXISTS current_title text;

-- Backfill: existing rooms keep showing what they were created for.
UPDATE public.rooms
SET current_media_ref = media_ref
WHERE current_media_ref IS NULL AND media_ref IS NOT NULL;
