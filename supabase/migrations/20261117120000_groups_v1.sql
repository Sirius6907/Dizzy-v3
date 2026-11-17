-- Groups v1.3.6 (Part G1): persistent group threads — text chat +
-- Watch Together media cards. Mirrors the DM round (dm_threads /
-- dm_messages) shape so the client service stays symmetric.

create table if not exists group_threads (
  group_id   text primary key,                      -- 'grp:<12 hex>' doubles as join code
  name       text not null check (char_length(name) between 1 and 60),
  owner_id   uuid not null,
  created_at timestamptz not null default now()
);

create table if not exists group_members (
  group_id  text not null references group_threads (group_id) on delete cascade,
  user_id   uuid not null,
  role      text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists group_messages (
  id            uuid primary key default gen_random_uuid(),
  group_id      text not null references group_threads (group_id) on delete cascade,
  sender_id     uuid not null,
  client_msg_id uuid not null,                       -- client idempotency (DM pattern)
  kind          text not null default 'text' check (kind in ('text', 'media_card')),
  body          text not null check (char_length(body) <= 2000),
  media_ref     text,                                -- serialized Watch Together card payload
  created_at    timestamptz not null default now(),
  unique (group_id, client_msg_id)
);

create index if not exists group_messages_group_time
  on group_messages (group_id, created_at desc);

alter table group_threads  enable row level security;
alter table group_members  enable row level security;
alter table group_messages enable row level security;

-- ── group_threads ────────────────────────────────────────────────
create policy "Owners create groups"
  on group_threads for insert to authenticated
  with check (owner_id = auth.uid());

create policy "Members read their groups"
  on group_threads for select to authenticated
  using (
    exists (
      select 1 from group_members m
      where m.group_id = group_threads.group_id and m.user_id = auth.uid()
    )
  );

create policy "Owners update their groups"
  on group_threads for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "Owners delete their groups"
  on group_threads for delete to authenticated
  using (owner_id = auth.uid());

-- ── group_members ────────────────────────────────────────────────
-- Owner can add anyone; anyone may self-join via the group code.
create policy "Owners add members or self-join"
  on group_members for insert to authenticated
  with check (
    user_id = auth.uid()
    or exists (
      select 1 from group_threads t
      where t.group_id = group_members.group_id and t.owner_id = auth.uid()
    )
  );

create policy "Members read their group roster"
  on group_members for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from group_members me
      where me.group_id = group_members.group_id and me.user_id = auth.uid()
    )
  );

-- Leave freely; owners can kick.
create policy "Members leave or owners remove"
  on group_members for delete to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from group_threads t
      where t.group_id = group_members.group_id and t.owner_id = auth.uid()
    )
  );

-- ── group_messages ───────────────────────────────────────────────
create policy "Members read group messages"
  on group_messages for select to authenticated
  using (
    exists (
      select 1 from group_members m
      where m.group_id = group_messages.group_id and m.user_id = auth.uid()
    )
  );

create policy "Members send group messages"
  on group_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from group_members m
      where m.group_id = group_messages.group_id and m.user_id = auth.uid()
    )
  );

-- ── Realtime ─────────────────────────────────────────────────────
alter publication supabase_realtime add table group_messages;

-- ── RPCs ─────────────────────────────────────────────────────────
create or replace function create_group(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  g  text;
  my uuid := auth.uid();
begin
  if my is null then
    return jsonb_build_object('success', false, 'error', 'not_signed_in');
  end if;
  p_name := btrim(coalesce(p_name, ''));
  if char_length(p_name) not between 1 and 60 then
    return jsonb_build_object('success', false, 'error', 'invalid_name');
  end if;
  g := 'grp:' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  insert into group_threads (group_id, name, owner_id) values (g, p_name, my);
  insert into group_members (group_id, user_id, role) values (g, my, 'owner');
  return jsonb_build_object('success', true, 'group_id', g, 'name', p_name);
end
$$;

create or replace function join_group(p_group_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  code text := btrim(coalesce(p_group_id, ''));
  my   uuid := auth.uid();
  name text;
begin
  if my is null then
    return jsonb_build_object('success', false, 'error', 'not_signed_in');
  end if;
  select t.name into name from group_threads t where t.group_id = code;
  if not found then
    return jsonb_build_object('success', false, 'error', 'group_not_found');
  end if;
  insert into group_members (group_id, user_id, role)
    values (code, my, 'member')
    on conflict (group_id, user_id) do nothing;
  return jsonb_build_object('success', true, 'group_id', code, 'name', name);
end
$$;

create or replace function my_groups()
returns table (
  group_id         text,
  name             text,
  owner_id         uuid,
  member_count     bigint,
  last_message     text,
  last_kind        text,
  last_message_at  timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select
    t.group_id,
    t.name,
    t.owner_id,
    (select count(*) from group_members m2 where m2.group_id = t.group_id) as member_count,
    lm.body,
    lm.kind,
    lm.created_at
  from group_threads t
  join group_members me
    on me.group_id = t.group_id and me.user_id = auth.uid()
  left join lateral (
    select gm.body, gm.kind, gm.created_at
    from group_messages gm
    where gm.group_id = t.group_id
    order by gm.created_at desc
    limit 1
  ) lm on true
  order by lm.created_at desc nulls last, t.created_at desc
$$;

create or replace function leave_group(p_group_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  my uuid := auth.uid();
begin
  if my is null then
    return jsonb_build_object('success', false, 'error', 'not_signed_in');
  end if;
  if exists (
    select 1 from group_threads t
    where t.group_id = btrim(p_group_id) and t.owner_id = my
  ) then
    -- Owners delete the whole thread instead of leaving.
    delete from group_threads where group_id = btrim(p_group_id) and owner_id = my;
    return jsonb_build_object('success', true, 'deleted', true);
  end if;
  delete from group_members
  where group_id = btrim(p_group_id) and user_id = my;
  return jsonb_build_object('success', true, 'deleted', false);
end
$$;
