-- Update adoption: how much of the fleet actually moved to the target build.
--
-- The admin panel can read this from nothing else: device_tokens has RLS on
-- with no client policies, so only a SECURITY DEFINER function can aggregate
-- it. Read-only, admin-gated, no writes.
--
-- Version comparison is numeric, not textual: "1.3.10" is newer than "1.3.7".
-- version_key() zero-pads each dotted part to five digits so plain text
-- ordering is correct, and treats an empty or junk version as 0.0.0.0.

create or replace function public.version_key(p_version text)
returns text
language sql
immutable
as $$
  with m as (
    select regexp_match(
      coalesce(btrim(p_version), ''),
      '^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.(\d+))?'
    ) as a
  )
  select format(
    '%s.%s.%s.%s',
    lpad(coalesce(a[1], '0'), 5, '0'),
    lpad(coalesce(a[2], '0'), 5, '0'),
    lpad(coalesce(a[3], '0'), 5, '0'),
    lpad(coalesce(a[4], '0'), 5, '0')
  )
  from m;
$$;

create or replace function public.admin_update_adoption(p_target text default '')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_target text := btrim(coalesce(p_target, ''));
  v_key text;
  v_out jsonb;
begin
  if not is_admin() then raise exception 'admin only'; end if;

  -- No explicit target: fall back to what the gate enforces, then to the
  -- release endpoint's mirrored version, then say so honestly with ''.
  if v_target = '' then
    select value into v_target
      from public.remote_config where key = 'min_app_version';
    v_target := btrim(coalesce(v_target, ''));
  end if;
  if v_target = '' then
    select value into v_target
      from public.remote_config where key = 'latest_version';
    v_target := btrim(coalesce(v_target, ''));
  end if;
  v_key := public.version_key(v_target);

  select jsonb_build_object(
    'target', v_target,
    'total', count(*),
    'android', count(*) filter (where platform = 'android'),
    'updated', case when v_target = '' then 0 else
      count(*) filter (where public.version_key(app_version) >= v_key)
    end,
    'pending', case when v_target = '' then count(*) else
      count(*) filter (where public.version_key(app_version) < v_key)
    end,
    -- Phones that already read one reminder and are inside the 7-day quiet
    -- period. Without this the operator cannot tell "ignored us" from
    -- "deliberately left alone".
    'cooling', case when v_target = '' then 0 else
      count(*) filter (
        where public.version_key(app_version) < v_key
          and last_nudged_at > now() - interval '7 days'
      )
    end,
    'versions', coalesce((
      select jsonb_agg(jsonb_build_object('name', v, 'n', n) order by k desc)
      from (
        select coalesce(nullif(app_version, ''), '?') as v,
               public.version_key(app_version) as k,
               count(*) as n
        from public.device_tokens
        where enabled
        group by 1, 2
      ) x
    ), '[]'::jsonb),
    'last_campaign', (
      select jsonb_build_object(
        'target', target,
        'sent', sent,
        'tokens', tokens,
        'created_at', created_at
      )
      from public.admin_push_events
      where event = 'send'
        and mode = 'update'
        and coalesce(target, '') not like '%#canary'
      order by created_at desc
      limit 1
    )
  ) into v_out
  from public.device_tokens
  where enabled;

  return v_out;
end $$;

revoke all on function public.version_key(text) from public;
revoke all on function public.admin_update_adoption(text) from public, anon;
grant execute on function public.admin_update_adoption(text) to authenticated;

comment on function public.admin_update_adoption(text) is
  'Read-only adoption snapshot for update campaigns: updated vs pending vs cooling.';
