-- Dizzy v1.3.3 T1.3 — missed-call phone verify (stub-first, key later).
-- Run: supabase db query --linked -f supabase/migrations/20261012_phone_links.sql
--
-- Design: provider key aane tak gateway_number is a PLACEHOLDER the admin
-- sets via remote_config (key: missedcall_gateway_number). App shows
-- number-save (unverified) immediately, verify goes pending → verified via
-- webhook (Edge fn `missedcall-webhook`, deployed with the key later).
-- request_phone_link RPC: creates/refreshes a pending row (rate-limited:
-- 1 request / 60s per user) and returns the gateway number to dial.

create table if not exists public.phone_links (
  user_id uuid primary key references auth.users(id) on delete cascade,
  phone_e164 text not null,
  status text not null default 'pending'
    check (status in ('pending', 'verified', 'failed')),
  attempts int not null default 0,
  last_request_at timestamptz not null default now(),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.phone_links enable row level security;
drop policy if exists "user rw own phone link" on public.phone_links;
create policy "user rw own phone link" on public.phone_links
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- App calls this instead of Supabase SMS OTP (costly + sender-ID friction).
-- Returns {success, gateway_number, status}. Status is 'verified' at once
-- when this number was verified before (re-link after reinstall).
create or replace function public.request_phone_link(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := regexp_replace(trim(coalesce(p_phone, '')), '[^0-9+]', '', 'g');
  v_row public.phone_links%rowtype;
  v_gateway text;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Authentication required');
  end if;
  if v_clean !~ '^\+[1-9][0-9]{7,14}$' then
    return jsonb_build_object('success', false, 'error', 'Enter a valid number with country code, e.g. +91…');
  end if;

  select * into v_row from public.phone_links where user_id = v_uid;

  -- Already verified this exact number: instant success, no new pending row.
  if found and v_row.status = 'verified' and v_row.phone_e164 = v_clean then
    return jsonb_build_object('success', true, 'status', 'verified',
      'gateway_number', '');
  end if;

  -- Cooldown: 1 request / 60s (protects the gateway bill later).
  if found and v_row.last_request_at > now() - interval '60 seconds' then
    select value into v_gateway from public.remote_config
    where key = 'missedcall_gateway_number';
    return jsonb_build_object('success', true, 'status', v_row.status,
      'gateway_number', coalesce(v_gateway, ''), 'cooldown', true);
  end if;

  insert into public.phone_links(user_id, phone_e164, status, attempts, last_request_at)
  values (v_uid, v_clean, 'pending', 1, now())
  on conflict (user_id) do update
  set phone_e164 = excluded.phone_e164,
      status = 'pending',
      attempts = public.phone_links.attempts + 1,
      last_request_at = now(),
      verified_at = null;

  select value into v_gateway from public.remote_config
  where key = 'missedcall_gateway_number';

  return jsonb_build_object('success', true, 'status', 'pending',
    'gateway_number', coalesce(v_gateway, ''));
end;
$$;
revoke all on function public.request_phone_link(text) from public;
grant execute on function public.request_phone_link(text) to authenticated;

-- Webhook (service-role / Edge) marks verified after the gateway confirms
-- the missed call from this number. Called by the Edge fn, not the app.
create or replace function public.confirm_phone_link(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.phone_links
  set status = 'verified', verified_at = now()
  where user_id = p_user_id and status = 'pending';
  if not found then
    return jsonb_build_object('success', false, 'error', 'no pending link');
  end if;
  return jsonb_build_object('success', true, 'status', 'verified');
end;
$$;
revoke all on function public.confirm_phone_link(uuid) from public;
-- No grant: Edge service-role bypasses RLS; app must never call this.

-- Gateway number placeholder (admin sets the real one with the key later).
insert into public.remote_config(key, value) values
  ('missedcall_gateway_number', '')
on conflict (key) do nothing;
