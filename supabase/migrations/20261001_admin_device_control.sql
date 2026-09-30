-- Dizzy Phase C — device revoke, end-to-end.   (2026-10-01)
-- Run ONCE: supabase db query --linked -f supabase/migrations/20261001_admin_device_control.sql
--
-- Admin powers (SECURITY DEFINER + is_admin() + admin_audit):
--   admin_devices(p_limit, p_search)  — fleet list, NO sensitive hashes
--   admin_device_revoke(p_device_id, p_revoke) — revoke/unrevoke + audit
-- App side: device_boot already reports revoked=true → notice screen
-- (Phase C3), never a silent logout (decision locked 2026-09-30).

-- Forward-ready: user_bans lands fully in Phase D (20261001_user_bans_reports).
-- Created here so the banned-join below resolves even if C is applied first.
create table if not exists public.user_bans (
  user_id uuid primary key references auth.users(id) on delete cascade,
  level text not null default 'social' check (level in ('social','full')),
  reason text not null default '',
  banned_until timestamptz,
  offence_count int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.user_bans enable row level security;
-- No client read/write: RPC-only (am_i_banned / admin_ban_user).

-- ═══════════ 1) admin_devices — fleet list (privacy: no hwid bytes) ═══════════
create or replace function public.admin_devices(
  p_limit int default 100,
  p_search text default ''
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select coalesce(jsonb_agg(t ORDER BY t.last_seen_at desc nulls last), '[]'::jsonb)
  into v
  from (
    select d.device_id, d.device_code, d.platform, d.app_version,
           d.last_seen_at, d.revoked_at, d.created_at,
           d.hwid_stable,
           (d.last_seen_at > now() - interval '10 minutes') as online,
           (b.user_id is not null) as banned,
           b.level as ban_level
    from public.devices d
    left join public.user_bans b
      on b.user_id = d.user_id
     and (b.banned_until is null or b.banned_until > now())
    where (p_search = ''
           or d.device_code ilike '%' || p_search || '%'
           or d.platform ilike '%' || p_search || '%'
           or d.app_version ilike '%' || p_search || '%')
    order by d.last_seen_at desc nulls last
    limit greatest(p_limit, 1)
  ) t;
  return v;
end;
$$;
revoke all on function public.admin_devices(int, text) from public;
grant execute on function public.admin_devices(int, text) to authenticated;

-- ═══════════ 2) admin_device_revoke — audited revoke/unrevoke ═══════════
-- Revoked device shows the notice screen at next boot (device_boot returns
-- revoked=true). Unrevoke clears it — the OTP re-link path.
create or replace function public.admin_device_revoke(
  p_device_id uuid,
  p_revoke boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_now boolean;
begin
  if not is_admin() then raise exception 'admin only'; end if;

  update public.devices
  set revoked_at = case when p_revoke then now() else null end
  where device_id = p_device_id
  returning device_code, (p_revoke) into v_code, v_now;

  if not found then
    raise exception 'device not found';
  end if;

  insert into public.admin_audit(admin_id, action, target, detail)
  values (auth.uid(),
          case when p_revoke then 'device:revoke' else 'device:unrevoke' end,
          v_code,
          jsonb_build_object('device_id', p_device_id));
  return true;
end;
$$;
revoke all on function public.admin_device_revoke(uuid, boolean) from public;
grant execute on function public.admin_device_revoke(uuid, boolean) to authenticated;
