-- Dizzy v1.3.6 — admin push controls (Phase 4, operator half).
-- Run AFTER 20261122_admin_device_card.sql:
--   supabase db query --linked -f supabase/migrations/20261123_admin_push.sql
--
-- The notification brain already knows how to send. What was missing was the
-- part a human needs at 2 a.m.:
--
--   1. push_settings  — one row, one boolean. "Stop sending" has to be a
--      switch, not a redeploy. The edge function reads it on every call.
--   2. admin_push_audience()  — how many phones would this reach? Answering
--      "broadcast to everyone?" without a number is guessing.
--   3. admin_push_resolve()   — a support ticket names a device ("DIZ-1234567"),
--      not a uuid. This turns the paste into the user id push-send needs.
--   4. admin_push_events  — one row per human send: who, what, to how many,
--      and how it went. push_send_log is per-user and written by the brain;
--      this is the operator ledger and stays small.
--
-- Nothing here sends anything. The edge function does the sending; these are
-- the reads, the switch and the receipt.

-- ═══════════ 1) the switch ═══════════
create table if not exists public.push_settings (
  id             int primary key default 1,
  sending_enabled boolean not null default true,
  paused_reason  text not null default '',
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  constraint push_settings_single_row check (id = 1),
  constraint push_settings_reason_chk check (length(paused_reason) <= 200)
);

insert into public.push_settings (id) values (1)
on conflict (id) do nothing;

alter table public.push_settings enable row level security;

drop policy if exists "admins read push settings" on public.push_settings;
create policy "admins read push settings" on public.push_settings
  for select to authenticated using (public.is_admin());

-- Writes go through admin_push_set_enabled() only, so updated_by is never a
-- client-supplied lie.
revoke all on public.push_settings from anon, authenticated;
grant select on public.push_settings to authenticated;
grant all on public.push_settings to service_role;

-- ═══════════ 2) operator ledger ═══════════
create table if not exists public.admin_push_events (
  id          bigserial primary key,
  actor_id    uuid,
  event       text not null default 'send',
  mode        text not null default '',
  target      text not null default '',
  kind        text not null default 'releases',
  title       text not null default '',
  body        text not null default '',
  tokens      int not null default 0,
  sent        int not null default 0,
  failed      int not null default 0,
  dry_run     boolean not null default false,
  error       text not null default '',
  created_at  timestamptz not null default now(),
  constraint admin_push_events_event_chk check (event in (
    'send', 'pause', 'resume', 'test'
  )),
  constraint admin_push_events_title_chk check (length(title) <= 120),
  constraint admin_push_events_body_chk check (length(body) <= 240),
  constraint admin_push_events_target_chk check (length(target) <= 120),
  constraint admin_push_events_error_chk check (length(error) <= 300)
);

create index if not exists admin_push_events_time_idx
  on public.admin_push_events (created_at desc);

alter table public.admin_push_events enable row level security;

drop policy if exists "admins read push events" on public.admin_push_events;
create policy "admins read push events" on public.admin_push_events
  for select to authenticated using (public.is_admin());

revoke all on public.admin_push_events from anon, authenticated;
revoke all on sequence public.admin_push_events_id_seq from anon, authenticated;
grant select on public.admin_push_events to authenticated;
grant all on public.admin_push_events to service_role;
grant usage, select on sequence public.admin_push_events_id_seq to service_role;

-- ═══════════ 3) audience size ═══════════
-- One call, one card: is sending on, how many phones, how many people, and
-- how much went out in the last day. Fail-soft on an empty fleet.
create or replace function public.admin_push_audience()
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare
  v_enabled boolean;
  v_reason  text;
  v_since   timestamptz;
begin
  if not is_admin() then raise exception 'admin only'; end if;

  select sending_enabled, paused_reason, updated_at
    into v_enabled, v_reason, v_since
    from public.push_settings where id = 1;

  return jsonb_build_object(
    'sending_enabled', coalesce(v_enabled, true),
    'paused_reason', coalesce(v_reason, ''),
    'settings_updated_at', v_since,
    'phones', (
      select count(*) from public.device_tokens where enabled
    ),
    'people', (
      select count(distinct user_id) from public.device_tokens where enabled
    ),
    'android', (
      select count(*) from public.device_tokens
       where enabled and platform = 'android'
    ),
    'ios', (
      select count(*) from public.device_tokens
       where enabled and platform <> 'android'
    ),
    'sent_24h', (
      select count(*) from public.push_send_log
       where status = 'sent' and created_at > now() - interval '24 hours'
    ),
    'failed_24h', (
      select count(*) from public.push_send_log
       where status = 'failed' and created_at > now() - interval '24 hours'
    )
  );
end $$;

-- ═══════════ 4) the switch, with a receipt ═══════════
create or replace function public.admin_push_set_enabled(
  p_enabled boolean,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := left(btrim(coalesce(p_reason, '')), 200);
begin
  if not is_admin() then raise exception 'admin only'; end if;

  update public.push_settings
     set sending_enabled = coalesce(p_enabled, true),
         paused_reason   = case when coalesce(p_enabled, true) then '' else v_reason end,
         updated_at      = now(),
         updated_by      = auth.uid()
   where id = 1;

  insert into public.admin_push_events (actor_id, event, mode, target, error)
  values (
    auth.uid(),
    case when coalesce(p_enabled, true) then 'resume' else 'pause' end,
    'switch',
    '',
    v_reason
  );

  return public.admin_push_audience();
end $$;

-- ═══════════ 5) paste a code, get a user ═══════════
-- Delegates the messy part (current code, retired code, device id, user id,
-- @username) to admin_device_card() so there is exactly one resolver in the
-- database, then projects it down to what the push panel needs.
create or replace function public.admin_push_resolve(p_search text)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare
  v_cards jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if btrim(coalesce(p_search, '')) = '' then return '[]'::jsonb; end if;

  v_cards := public.admin_device_card(p_search);

  return coalesce((
    select jsonb_agg(
             jsonb_build_object(
               'user_id', uid,
               'username', username,
               'device_code', device_code,
               'app_version', app_version,
               'last_seen_at', last_seen_at,
               'tokens', (
                 select count(*) from public.device_tokens dt
                  where dt.enabled and dt.user_id = uid
               )
             )
             order by device_code
           )
      from (
        select distinct on (e->>'user_id')
               case
                 when coalesce(e->>'user_id', '') ~
                      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                 then (e->>'user_id')::uuid
               end as uid,
               coalesce(e->>'username', '')   as username,
               coalesce(e->>'device_code', '') as device_code,
               coalesce(e->>'app_version', '') as app_version,
               (e->>'last_seen_at')::timestamptz as last_seen_at
          from jsonb_array_elements(v_cards) e
         where coalesce(e->>'user_id', '') <> ''
         order by e->>'user_id', (e->>'last_seen_at')::timestamptz desc nulls last
      ) s
     where uid is not null
  ), '[]'::jsonb);
end $$;

-- ═══════════ 6) write the receipt ═══════════
-- Called by the panel after push-send answers. Deliberately tolerant: a
-- missing count is 0, not an error, because a failed send still deserves a
-- line in the ledger.
create or replace function public.admin_push_log(
  p_mode text,
  p_target text,
  p_kind text,
  p_title text,
  p_body text,
  p_tokens int,
  p_sent int,
  p_failed int,
  p_dry_run boolean default false,
  p_error text default ''
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if not is_admin() then raise exception 'admin only'; end if;

  insert into public.admin_push_events (
    actor_id, event, mode, target, kind, title, body,
    tokens, sent, failed, dry_run, error
  ) values (
    auth.uid(),
    case when coalesce(p_dry_run, false) then 'test' else 'send' end,
    left(btrim(coalesce(p_mode, '')), 32),
    left(btrim(coalesce(p_target, '')), 120),
    case when p_kind in ('releases','updates','downloads','social','announcements')
         then p_kind else 'releases' end,
    left(btrim(coalesce(p_title, '')), 120),
    left(btrim(coalesce(p_body, '')), 240),
    greatest(coalesce(p_tokens, 0), 0),
    greatest(coalesce(p_sent, 0), 0),
    greatest(coalesce(p_failed, 0), 0),
    coalesce(p_dry_run, false),
    left(btrim(coalesce(p_error, '')), 300)
  )
  returning id into v_id;

  return v_id;
end $$;

-- ═══════════ 7) lock the doors ═══════════
revoke all on function public.admin_push_audience() from public, anon;
revoke all on function public.admin_push_set_enabled(boolean, text) from public, anon;
revoke all on function public.admin_push_resolve(text) from public, anon;
revoke all on function public.admin_push_log(
  text, text, text, text, text, int, int, int, boolean, text
) from public, anon;

grant execute on function public.admin_push_audience() to authenticated, service_role;
grant execute on function public.admin_push_set_enabled(boolean, text) to authenticated, service_role;
grant execute on function public.admin_push_resolve(text) to authenticated, service_role;
grant execute on function public.admin_push_log(
  text, text, text, text, text, int, int, int, boolean, text
) to authenticated, service_role;

comment on table public.push_settings is
  'v1.3.6 — one-row kill switch for device push. Read by push-send on every call.';
comment on table public.admin_push_events is
  'v1.3.6 — one row per human push action (send / pause / resume). push_send_log stays per-user.';
comment on function public.admin_push_resolve(text) is
  'v1.3.6 — DIZ-code, device id, user id or @username -> user ids the push panel can send to.';
