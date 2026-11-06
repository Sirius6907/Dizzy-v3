-- Support assistant observability.
--
-- support_log_answer() derives the user from auth.uid(), but the Edge
-- Function logs with the service-role key, where auth.uid() is null — every
-- assistant answer was silently dropped. This adds an explicit-user variant
-- (service_role only) plus admin-readable recent answers.

alter table support_answers add column if not exists answer text;
alter table support_answers add column if not exists latency_ms integer;

create or replace function support_log_answer_for_user(
  p_user_id    uuid,
  p_question   text,
  p_matched    text,
  p_score      real,
  p_lang       text,
  p_tier       text,
  p_escalated  boolean default false,
  p_answer     text default '',
  p_latency_ms integer default 0
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then return; end if;
  insert into support_answers(
    user_id, question, matched_id, score, lang, tier, escalated, answer, latency_ms
  ) values (
    p_user_id,
    left(coalesce(p_question, ''), 500),
    left(coalesce(p_matched, ''), 64),
    coalesce(p_score, 0),
    left(coalesce(p_lang, 'en'), 2),
    coalesce(p_tier, 'local'),
    coalesce(p_escalated, false),
    left(coalesce(p_answer, ''), 1000),
    greatest(coalesce(p_latency_ms, 0), 0)
  );
end;
$$;

revoke all on function support_log_answer_for_user(uuid, text, text, real, text, text, boolean, text, integer)
  from public, anon, authenticated;
grant execute on function support_log_answer_for_user(uuid, text, text, real, text, text, boolean, text, integer)
  to service_role;

create or replace function admin_support_answers(p_limit integer default 100)
returns table (
  id bigint,
  user_id uuid,
  username text,
  question text,
  answer text,
  matched_id text,
  tier text,
  lang text,
  score real,
  latency_ms integer,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'not authorized';
  end if;
  return query
  select a.id,
         a.user_id,
         u.username,
         a.question,
         a.answer,
         a.matched_id,
         a.tier,
         a.lang,
         a.score,
         a.latency_ms,
         a.created_at
  from support_answers a
  left join public.usernames u on u.user_id = a.user_id
  order by a.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

revoke all on function admin_support_answers(integer) from public, anon;
grant execute on function admin_support_answers(integer) to authenticated;
