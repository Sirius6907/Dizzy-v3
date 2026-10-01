-- Dizzy Phase E1 — allow admin to set force_after (2026-10-01)
-- Run ONCE: supabase db query --linked -f supabase/migrations/20261001_force_after_key.sql
-- Adds the blocking-deadline key to the whitelist. Semantics (UpdateGate):
--   min_app_version set + current < min → banner
--   + force_after passed → blocking screen (offline clients never block —
--   they never have this key unless the server reached them once).
create or replace function admin_set_config(p_key text, p_value text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if p_key not in ('min_app_version','scraper_kill','scraper_cooldown_days','features','notice','force_after') then
    raise exception 'bad key';
  end if;
  insert into remote_config(key, value, updated_at, updated_by)
    values (p_key, p_value, now(), auth.uid())
    on conflict (key) do update set value=excluded.value, updated_at=now(), updated_by=auth.uid();
  insert into admin_audit(admin_id, action, target, detail)
    values (auth.uid(), 'config:set', p_key, jsonb_build_object('value', left(p_value, 2000)));
  return true;
end;
$$;
revoke all on function admin_set_config(text, text) from public;
grant execute on function admin_set_config(text, text) to authenticated;
