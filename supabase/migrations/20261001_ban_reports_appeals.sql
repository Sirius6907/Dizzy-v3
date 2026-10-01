-- Dizzy Phase D — escalating ban + reports + appeals.   (2026-10-01)
-- Run ONCE: supabase db query --linked -f supabase/migrations/20261001_ban_reports_appeals.sql
--
-- user_bans was forward-created in 20261001_admin_device_control.sql without
-- banned_by; add it + touch trigger now (create or replace makes this idempotent).
alter table public.user_bans add column if not exists banned_by uuid;
create or replace function public.touch_bans_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists trg_bans_touch on public.user_bans;
create trigger trg_bans_touch before update on public.user_bans
  for each row execute function public.touch_bans_updated_at();

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null,          -- could be anon uid
  target_id uuid not null,
  reason text not null check (char_length(reason) between 3 and 500),
  context jsonb not null default '{}'::jsonb,   -- room_id / dm_id / profile ref (no message bodies)
  status text not null default 'open' check (status in ('open','dismissed')),
  handled_by uuid,
  handled_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_reports_status on public.user_reports(status, created_at desc);

create table if not exists public.ban_appeals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  text text not null check (char_length(text) between 10 and 1000),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_appeals_status on public.ban_appeals(status, created_at desc);

alter table public.user_reports enable row level security;
alter table public.ban_appeals enable row level security;

drop policy if exists "report self insert" on public.user_reports;
create policy "report self insert" on public.user_reports
  for insert to authenticated, anon with check (reporter_id = auth.uid());

drop policy if exists "appeal self insert" on public.ban_appeals;
create policy "appeal self insert" on public.ban_appeals
  for insert to authenticated, anon with check (user_id = auth.uid());

-- ── am_i_banned ───────────────────────────────────────────────
create or replace function public.am_i_banned()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.user_bans%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('level', 'none', 'days_left', 0, 'reason', '');
  end if;
  select * into v_row from user_bans where user_id = v_uid;
  if not found then
    return jsonb_build_object('level', 'none', 'days_left', 0, 'reason', '');
  end if;
  if v_row.banned_until is not null and v_row.banned_until < now() then
    return jsonb_build_object('level', 'none', 'days_left', 0, 'reason', '');
  end if;
  return jsonb_build_object(
    'level', v_row.level,
    'days_left', case when v_row.banned_until is null then -1
                      else greatest(0, floor(extract(epoch from (v_row.banned_until - now())) / 86400))::int end,
    'reason', coalesce(v_row.reason, '')
  );
end;
$$;
grant execute on function public.am_i_banned() to anon, authenticated;

-- ── admin: list reported users w/ offence history ─────────────
create or replace function public.admin_user_reports(p_limit int default 100, p_search text default '')
returns setof jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return query
  select jsonb_build_object(
    'user_id', r.target_id,
    'reports_open', count(*) filter (where r.status = 'open'),
    'reports_total', count(*),
    'last_reason', (select reason from user_reports x where x.target_id = r.target_id
                    order by x.created_at desc limit 1),
    'last_at', max(r.created_at),
    'level', b.level,
    'offence_count', coalesce(b.offence_count, 0),
    'banned_until', b.banned_until
  )
  from user_reports r
  left join user_bans b on b.user_id = r.target_id
  where (p_search = '' or r.target_id::text ilike '%' || p_search || '%'
                or r.reason ilike '%' || p_search || '%')
  group by r.target_id, b.level, b.offence_count, b.banned_until
  order by count(*) filter (where r.status = 'open') desc, max(r.created_at) desc
  limit least(greatest(p_limit, 1), 500);
end;
$$;
grant execute on function public.admin_user_reports(int, text) to authenticated;

-- ── admin: ban with escalating levels ─────────────────────────
-- p_days: 0 = permanent. offence_count++ on every new ban.
-- p_level: 'social' = no party/DMs/friends; 'full' = boot notice screen.
create or replace function public.admin_ban_user(
  p_user_id uuid, p_level text default 'full',
  p_days int default 0, p_reason text default '')
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_admin uuid := auth.uid();
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  if p_level not in ('social', 'full') then raise exception 'bad level'; end if;
  if p_days < 0 or p_days > 3650 then raise exception 'bad days'; end if;

  insert into user_bans (user_id, level, reason, banned_until, offence_count, banned_by)
  values (p_user_id, p_level, nullif(p_reason, ''),
          case when p_days = 0 then null else now() + make_interval(days => p_days) end,
          1, v_admin)
  on conflict (user_id) do update set
    level = excluded.level,
    reason = excluded.reason,
    banned_until = excluded.banned_until,
    offence_count = user_bans.offence_count + 1,
    banned_by = excluded.banned_by,
    updated_at = now();

  -- a full ban blocks this device on next boot
  if p_level = 'full' then
    update devices set revoked_at = now(), revoke_reason = 'Account banned'
    where user_id = p_user_id and revoked_at is null;
  end if;

  insert into admin_audit (admin_id, action, target, detail) values
    (v_admin, 'ban_user', p_user_id::text,
     jsonb_build_object('level', p_level, 'days', p_days, 'reason', p_reason));
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.admin_ban_user(uuid, text, int, text) to authenticated;

create or replace function public.admin_unban_user(p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_admin uuid := auth.uid();
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  delete from user_bans where user_id = p_user_id;
  update devices set revoked_at = null, revoke_reason = null
  where user_id = p_user_id and revoke_reason = 'Account banned';
  insert into admin_audit (admin_id, action, target, detail) values
    (v_admin, 'unban_user', p_user_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.admin_unban_user(uuid) to authenticated;

-- ── user: report (fail-soft in app; insert only) ──────────────
create or replace function public.report_user(p_target_id uuid, p_reason text, p_context jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if p_target_id = v_uid then raise exception 'cannot report yourself'; end if;
  insert into user_reports (reporter_id, target_id, reason, context)
  values (v_uid, p_target_id, left(trim(p_reason), 500), coalesce(p_context, '{}'::jsonb));
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.report_user(uuid, text, jsonb) to anon, authenticated;

create or replace function public.admin_dismiss_user_reports(p_target_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_admin uuid := auth.uid();
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  update user_reports set status = 'dismissed', handled_by = v_admin, handled_at = now()
  where target_id = p_target_id and status = 'open';
  insert into admin_audit (admin_id, action, target, detail) values
    (v_admin, 'dismiss_reports', p_target_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.admin_dismiss_user_reports(uuid) to authenticated;

-- ── appeals ───────────────────────────────────────────────────
create or replace function public.ban_appeal_submit(p_text text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_open int;
begin
  if v_uid is null then raise exception 'auth required'; end if;
  select count(*) into v_open from ban_appeals where user_id = v_uid and status = 'pending';
  if v_open > 0 then raise exception 'appeal already pending'; end if;
  insert into ban_appeals (user_id, text) values (v_uid, left(trim(p_text), 1000));
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.ban_appeal_submit(text) to anon, authenticated;

create or replace function public.ban_appeals_pending()
returns setof jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return query
  select jsonb_build_object(
    'id', a.id, 'user_id', a.user_id, 'text', a.text,
    'status', a.status, 'created_at', a.created_at,
    'level', b.level, 'offence_count', coalesce(b.offence_count, 0)
  )
  from ban_appeals a
  left join user_bans b on b.user_id = a.user_id
  order by (a.status = 'pending') desc, a.created_at desc
  limit 200;
end;
$$;
grant execute on function public.ban_appeals_pending() to authenticated;

create or replace function public.ban_appeal_decide(p_appeal_id uuid, p_approve bool, p_note text default '')
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_admin uuid := auth.uid(); v_row public.ban_appeals%rowtype;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  select * into v_row from ban_appeals where id = p_appeal_id for update;
  if not found then raise exception 'appeal not found'; end if;
  update ban_appeals set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = v_admin, decided_at = now(), decision_note = left(p_note, 500)
  where id = p_appeal_id;
  if p_approve then
    delete from user_bans where user_id = v_row.user_id;
    update devices set revoked_at = null, revoke_reason = null
    where user_id = v_row.user_id and revoke_reason = 'Account banned';
  end if;
  insert into admin_audit (admin_id, action, target, detail) values
    (v_admin, 'appeal_decide', p_appeal_id::text,
     jsonb_build_object('approve', p_approve, 'note', p_note));
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.ban_appeal_decide(uuid, bool, text) to authenticated;

-- ── hardened join path: full-ban blocks rooms ─────────────────
-- Signature must match live (text, text default null) from 20260912_wp_p5_safety.
-- social-level ban is enforced app-side for interactive features (D3).
create or replace function join_watch_room(
  p_room_id text,
  p_pass_hash text default null
) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  r rooms%rowtype;
  n int;
  v_ban jsonb;
begin
  v_ban := public.am_i_banned();
  if v_ban->>'level' = 'full' then
    raise exception 'This account is suspended. Appeal from the notice screen.';
  end if;
  select * into r from rooms where room_id = upper(trim(p_room_id));
  if not found or r.status = 'closed' then return false; end if;
  if r.visibility = 'private' and
     (p_pass_hash is null or p_pass_hash <> r.pass_hash) then
    return false;
  end if;
  select count(*) into n from room_members where room_id = r.room_id;
  if n >= 20 then return false; end if;
  insert into room_members(room_id, user_id, role)
    values (r.room_id, auth.uid(), case when auth.uid() = r.host_user_id then 'host' else 'member' end)
    on conflict (room_id, user_id) do nothing;
  return true;
end;
$$;
revoke all on function join_watch_room(text, text) from public;
grant execute on function join_watch_room(text, text) to authenticated;
