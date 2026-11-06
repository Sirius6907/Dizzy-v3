-- v1.3.4 — notification tone preference.
--
-- Recommendation pushes already respect quiet hours and frequency caps.
-- This adds a copy voice the user controls: "warm" is plain and friendly,
-- "playful" is a little cheeky. It changes wording only — never who gets
-- a notification or how often.
--
-- Apply: supabase db query --linked -f supabase/migrations/20261106_notification_tone.sql
-- then record the history row (never `db push`).

begin;

alter table public.notification_settings
  add column if not exists tone text not null default 'playful';

alter table public.notification_settings
  drop constraint if exists notification_settings_tone_chk;
alter table public.notification_settings
  add constraint notification_settings_tone_chk
  check (tone in ('warm', 'playful'));

create or replace function public.set_notification_tone(p_tone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_tone text := lower(trim(coalesce(p_tone, '')));
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'reason', 'auth');
  end if;
  if v_tone not in ('warm', 'playful') then
    v_tone := 'playful';
  end if;

  insert into public.notification_settings as s (user_id, tone)
  values (v_uid, v_tone)
  on conflict (user_id) do update
    set tone = excluded.tone,
        updated_at = now();

  return jsonb_build_object('success', true, 'tone', v_tone);
end;
$$;

revoke all on function public.set_notification_tone(text) from public;
grant execute on function public.set_notification_tone(text) to authenticated;

commit;
