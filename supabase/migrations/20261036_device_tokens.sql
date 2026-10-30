-- Dizzy v1.3.3 — FCM device tokens (Phase 3, server half).
-- Run: supabase db query --linked -f supabase/migrations/20261036_device_tokens.sql
-- then record the history row (never `db push`).
--
-- One row per FCM token. A token can only point at one account: registering
-- it under a new user detaches it from the old one inside the RPC, because
-- the client cannot see (and must not touch) another user's row.
-- The table has RLS on and no client policies: only the SECURITY DEFINER
-- RPCs below and the service role (push-send) read or write it.

create table if not exists public.device_tokens (
  id          bigserial primary key,
  user_id     uuid not null default auth.uid(),
  token       text not null unique,
  platform    text not null default 'android',
  app_version text not null default '',
  enabled     boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint device_tokens_token_chk check (length(token) between 20 and 4096)
);

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id) where enabled;

alter table public.device_tokens enable row level security;

revoke all on public.device_tokens from anon, authenticated;
revoke all on sequence public.device_tokens_id_seq from anon, authenticated;
grant all on public.device_tokens to service_role;
grant usage, select on sequence public.device_tokens_id_seq to service_role;

create or replace function public.register_device_token(
  p_token text,
  p_platform text default 'android',
  p_app_version text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'auth');
  end if;
  if length(coalesce(p_token, '')) < 20 or length(p_token) > 4096 then
    return jsonb_build_object('success', false, 'error', 'token');
  end if;

  -- Same physical device signing into another account: move the token.
  delete from public.device_tokens where token = p_token and user_id <> v_uid;

  insert into public.device_tokens (user_id, token, platform, app_version)
  values (
    v_uid,
    p_token,
    left(coalesce(p_platform, 'android'), 16),
    left(coalesce(p_app_version, ''), 32)
  )
  on conflict (token) do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    app_version = excluded.app_version,
    enabled = true,
    updated_at = now();

  return jsonb_build_object('success', true);
end;
$$;

create or replace function public.revoke_device_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'auth');
  end if;
  delete from public.device_tokens
  where token = p_token and user_id = v_uid;
  return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.register_device_token(text, text, text) from public;
revoke all on function public.revoke_device_token(text) from public;
grant execute on function public.register_device_token(text, text, text)
  to authenticated, service_role;
grant execute on function public.revoke_device_token(text)
  to authenticated, service_role;

comment on table public.device_tokens is
  'FCM registration tokens. Client access only through the RPCs above.';
