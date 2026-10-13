-- v1.3.3-T5 — seed typed hot-fix keys (defaults = fail-closed safe).
-- Values only; the app treats a missing key as "keep last-known".
insert into remote_config(key, value) values
  ('min_supported_build', ''),
  ('support_faq_bundle_version', 'v1'),
  ('music_shelves_layout', '{}'),
  ('music_endpoints.jiosaavn', ''),
  ('music_endpoints.ytmusic', ''),
  ('music_endpoints.spotify', ''),
  ('scraper_urls', '{}'),
  ('scraper_regex', '{}'),
  ('ranking_weights', '{}'),
  ('feature_flags', '{}'),
  ('announcements_feed', '[]')
on conflict (key) do nothing;
