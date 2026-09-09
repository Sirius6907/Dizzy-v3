-- WP-P0: 7-digit device code per install (locked spec 2026-09-09).
-- Random code, not a fingerprint. Reinstall = new row after TTL cleanup.
alter table installs
  add column if not exists device_code char(7) unique;
