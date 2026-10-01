-- Dizzy Phase I1 — rollout + update channel keys (2026-10-01)
-- Run ONCE: supabase db query --linked -f supabase/migrations/20261001_update_rollout_channel.sql
-- Semantics (UpdatePolicy):
--   rollout_percent  0..100. Device bucket = fnv1a(stable_hwid) % 100 must be
--                    < percent to be offered the soft update. 100 = everyone,
--                    0 = nobody. Missing key is treated as 100 by the app.
--   update_channel   'stable' (default) or 'beta'. beta reads GitHub
--                    /releases (prereleases included); stable keeps
--                    /releases/latest.
create or replace function admin_set_config(p_key text, p_value text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if p_key not in (
    'min_app_version','scraper_kill','scraper_cooldown_days',
    'features','notice','force_after','rollout_percent','update_channel'
  ) then
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

-- Seed defaults so the dashboard Config tab always has rows to edit.
insert into remote_config(key, value, updated_at, updated_by)
  values
    ('rollout_percent', '100', now(), null),
    ('update_channel', 'stable', now(), null)
  on conflict (key) do nothing;
