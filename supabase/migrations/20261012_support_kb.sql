-- v1.3.3-T4 — support knowledge base + answer logging.
--
-- Tier 2 of the support brain: the Edge `support-answer` function reads
-- this table, ranks rows against the question, and (if a cheap LLM key is
-- configured) asks it to phrase the answer. With no key it returns the
-- best-matching row verbatim — the feature works before any key exists.
--
-- v1: keyword + trigram matching. pgvector is deliberately deferred to
-- v1.3.4: 24-200 short docs do not need embeddings, and shipping a vector
-- extension plus an embedding pipeline before the KB has real traffic is
-- cost without signal.
--
-- Idempotent.

create extension if not exists pg_trgm;

-- ═══════════ 1) support_kb ═══════════
create table if not exists support_kb (
  id          text primary key,
  topic       text not null default 'other'
                check (topic ~ '^[a-z][a-z0-9_]{0,31}$'),
  title       text not null default '',
  body        text not null default '',
  body_hi     text not null default '',
  -- Space-separated trigger words, kept in one column so the trigram index
  -- can serve `query % triggers` directly.
  triggers    text not null default '',
  -- Which app builds this answer is valid for; '' = all.
  min_build   text not null default '',
  active      boolean not null default true,
  updated_at  timestamptz not null default now()
);
alter table support_kb enable row level security;

create index if not exists support_kb_trgm_idx
  on support_kb using gin (triggers gin_trgm_ops);

-- Any signed-in app user reads the KB; writes are admin-only via RPC
-- (no write policy at all = denied for anon/authenticated).
drop policy if exists "anyone reads support kb" on support_kb;
create policy "anyone reads support kb" on support_kb
  for select to anon, authenticated using (active);

-- ═══════════ 2) support_answers log (deflection measurement) ═══════════
-- One row per answered question. Powers the "deflection ≥60% on top-20
-- FAQs" target and shows which questions the KB still cannot answer.
create table if not exists support_answers (
  id          bigint generated always as identity primary key,
  user_id     uuid references auth.users(id) on delete set null,
  device_code text not null default 'unknown',
  question    text not null default '',
  matched_id  text not null default '',
  score       real not null default 0,
  lang        text not null default 'en',
  tier        text not null default 'local'
                check (tier in ('local', 'kb', 'llm', 'none')),
  escalated   boolean not null default false,
  created_at  timestamptz not null default now()
);
alter table support_answers enable row level security;

create index if not exists support_answers_unmatched_idx
  on support_answers (created_at desc) where matched_id = '';

-- The app records its own answers only.
drop policy if exists "users log own answer" on support_answers;
create policy "users log own answer" on support_answers
  for insert to authenticated with check (auth.uid() = user_id or user_id is null);

drop policy if exists "admins read answers" on support_answers;
create policy "admins read answers" on support_answers
  for select to authenticated using (is_admin());

-- Privacy: the question text is the USER'S OWN WORDS. It is stored so the
-- KB can be improved — and it is readable by admins only. The client
-- strips it entirely when telemetry consent is off.
create or replace function support_log_answer(
  p_question  text,
  p_matched   text,
  p_score     real,
  p_lang      text,
  p_tier      text,
  p_escalated boolean default false
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_consent_text boolean;
begin
  if auth.uid() is null then return; end if;
  -- Consent gate, server side too (defence in depth): the client passes
  -- '' as the question when telemetry consent is off.
  if coalesce(p_question, '') = '' then
    insert into support_answers(user_id, matched_id, score, lang, tier, escalated)
      values (auth.uid(), left(coalesce(p_matched,''),64), coalesce(p_score,0),
              left(coalesce(p_lang,'en'),2), coalesce(p_tier,'local'), coalesce(p_escalated,false));
    return;
  end if;
  insert into support_answers(user_id, question, matched_id, score, lang, tier, escalated)
    values (auth.uid(), left(p_question, 500), left(coalesce(p_matched,''),64),
            coalesce(p_score,0), left(coalesce(p_lang,'en'),2),
            coalesce(p_tier,'local'), coalesce(p_escalated,false));
end;
$$;
revoke all on function support_log_answer(text, text, real, text, text, boolean) from public;
grant execute on function support_log_answer(text, text, real, text, text, boolean) to authenticated;

-- ═══════════ 3) KB read for the Edge function ═══════════
-- Returns the top N candidate rows for a question. Trigram similarity on
-- triggers first, then a plain ILIKE sweep as fallback so a single-word
-- query still matches.
create or replace function support_kb_lookup(p_query text, p_limit int default 5)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q text := lower(btrim(coalesce(p_query, '')));
  v jsonb;
begin
  if v_q = '' then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(t order by t.rank desc), '[]'::jsonb) into v
    from (
      select k.id, k.topic, k.title, k.body, k.body_hi, k.triggers,
             greatest(similarity(lower(k.triggers), v_q),
                      similarity(lower(k.title), v_q)) as rank
        from support_kb k
       where k.active
         and (lower(k.triggers) % v_q
              or lower(k.title) % v_q
              or lower(k.triggers) like '%' || v_q || '%'
              or lower(k.title) like '%' || v_q || '%'
              or exists (
                   select 1 from unnest(string_to_array(v_q, ' ')) w
                    where length(w) >= 4 and lower(k.triggers) like '%' || w || '%'))
       order by rank desc
       limit greatest(least(p_limit, 20), 1)
    ) t;
  return coalesce(v, '[]'::jsonb);
end;
$$;
grant execute on function support_kb_lookup(text, int) to anon, authenticated;

-- ═══════════ 4) seed the KB from the bundled FAQ ═══════════
-- Keeps tier 2 in step with the offline bundle so a question the bundle
-- misses is at least answerable online.
insert into support_kb(id, topic, title, body, body_hi, triggers) values
  ('faq_play_not_working','playback','Video not playing','Try another source: on the player, open Sources and pick the next one. The first source can be down while others work.','Doosra source try karo: player me Sources kholo aur agla chuno. Pehla source down ho sakta hai, baaki chalte hain.','video not playing movie wont play play button not working stream fails kuch play nahi ho raha video nahi chal raha player stuck'),
  ('faq_buffering','playback','Buffering','Tap the quality icon and choose a lower option, or switch source. Slow internet also buffers at high quality.','Quality icon dabao aur kam quality chuno, ya source badlo. Slow internet pe high quality buffering karti hai.','buffering loading forever spinner stuck video keeps stopping buffering ho raha load ho raha hai'),
  ('faq_no_sources_found','playback','No sources found','This title may not be available yet. Check the spelling in Search, or try the same title a bit later.','Ye title abhi available nahi ho sakta. Search me spelling check karo, ya thodi der baad try karo.','no sources found no stream nothing found for this sources empty source nahi mila'),
  ('faq_download_fails','downloads','Download not working','Check free storage: downloads stop when the phone is nearly full. Also make sure Wi-Fi is on.','Storage khaali hai ya nahi dekho: phone bhara ho to download ruk jaata hai. Wi-Fi on rakho.','download not working download stuck download fails download 0 percent download nahi ho raha'),
  ('faq_download_paused','downloads','Download paused','Downloads pause on mobile data. Open Settings and turn on Download on mobile data, or switch to Wi-Fi.','Mobile data pe download rukta hai. Settings me Download on mobile data on karo, ya Wi-Fi pe aao.','download paused stuck at 0 not downloading on data download ruk gaya'),
  ('faq_no_sound','playback','No sound','Tap the player once and use the volume gesture on the right side. Also check the audio track in the player menu.','Player pe ek baar tap karo aur right side pe volume gesture use karo. Player menu me audio track bhi dekho.','no sound audio not working volume issue sound nahi aa raha awaaz nahi'),
  ('faq_subtitles','playback','Subtitles missing','Open the player menu and pick Subtitles, then choose a language. If the list is empty, try another source.','Player menu me Subtitles kholo aur language chuno. List khaali ho to doosra source try karo.','subtitles not showing no subtitles subtitle language subtitle nahi aa rahe'),
  ('faq_hindi_dub','playback','Hindi audio','Set your audio language in Settings, Playback, Audio language. The app then prefers Hindi-dub sources.','Settings Playback Audio language me apni language set karo. App phir Hindi-dub sources prefer karega.','hindi audio hindi dub how to get hindi hindi me kaise hindi audio nahi'),
  ('faq_username_reset','account','Username resets','Update to the latest version. Your name is saved on the device and synced to your account.','Latest version me update karo. Naam device pe save hota hai aur account se sync hota hai.','username changed my name resets username gone name saved but gone naam badal gaya'),
  ('faq_otp_not_arriving','account','Email code not arriving','Check your spam folder too, and wait a minute before tapping Resend.','Spam folder bhi dekho, aur Resend dabane se pehle ek minute ruko.','otp not received code not coming email code otp nahi aaya'),
  ('faq_link_phone','account','Link phone number','Open your profile, tap Link phone, and give the missed call shown.','Profile kholo, Link phone dabao, aur dikhaya gaya number pe missed call do.','link phone number verify phone missed call verify phone kaise link kare'),
  ('faq_watch_together','social','Watch Together','Both devices need internet. If it drifts, tap Sync in the room.','Dono devices me internet chahiye. Sync toot jaye to room me Sync dabao.','watch together not syncing party not working sync issue watch party'),
  ('faq_voice_not_working','social','Voice chat','Allow microphone permission when asked. Voice works inside a Watch Together room.','Puche jaane pe microphone permission do. Voice Watch Together room me chalta hai.','voice chat not working mic not working cant hear friends voice nahi aa rahi'),
  ('faq_music_no_play','music','Song not playing','If one song fails, tap it again. Offline songs play from your downloads first.','Ek gaana fail ho to dobara tap karo. Offline gaane pehle downloads se chalte hain.','song not playing music not working music stuck gaana nahi chal raha'),
  ('faq_music_search_wrong','music','Wrong song in search','Type the full song name with the artist for the best match.','Best match ke liye poora gaana naam artist ke saath likho.','wrong song in search search shows wrong odia song not found galat gaana'),
  ('faq_addons','setup','Addons','Open Settings, Addons, Store and add the ones you want.','Settings Addons Store kholo aur jo chahiye add karo.','how to add addons addon install sources missing addon kaise add kare'),
  ('faq_update','setup','Updating','Open Settings, Updates, Check for updates.','Settings Updates Check for updates kholo.','how to update new version update not showing update kaise kare'),
  ('faq_storage_full','downloads','Storage full','Open Downloads and remove what you have watched, or clear the image cache in Settings.','Downloads kholo aur dekh liye items hata do, ya Settings me image cache clear karo.','storage full phone full not enough space storage bhar gaya'),
  ('faq_adult_section','setup','18+ section','The 18+ section needs your age confirmed in Settings, Content.','18+ section ke liye Settings Content me age confirm karni hoti hai.','adult section missing 18 plus not showing adult not visible adult section nahi'),
  ('faq_data_usage','setup','Data usage','Set a lower streaming quality in Settings, Playback, and turn on Data saver.','Settings Playback me kam streaming quality set karo, aur Data saver on karo.','data usage high how much data data saving data bachana'),
  ('faq_continue_watching','playback','Continue Watching','Continue Watching syncs after you sign in. Play a minute of a title, then it appears.','Continue Watching sign in ke baad sync hota hai. Ek minute chalao, phir dikhega.','continue watching missing resume not working where i left off continue watching nahi'),
  ('faq_app_slow','setup','App slow','Close other apps, then clear the image cache in Settings, Storage.','Baaki apps band karo, phir Settings Storage me image cache clear karo.','app slow lagging hangs app slow chal raha app hang'),
  ('faq_crash','setup','App crashes','Update to the latest version first. If it still happens, send a report from Settings, Help.','Pehle latest version me update karo. Phir bhi ho to Settings Help se report bhejo.','app crashes app closes itself app band ho jaata keeps closing'),
  ('faq_torrent','setup','Torrent/P2P','Turn P2P off in Settings, Playback if a torrent source hangs, or pick a different source.','Torrent source hang ho to Settings Playback me P2P off karo, ya doosra source chuno.','torrent not working p2p slow torrent warning torrent nahi chal raha')
on conflict (id) do update set
  topic = excluded.topic, title = excluded.title, body = excluded.body,
  body_hi = excluded.body_hi, triggers = excluded.triggers, updated_at = now();