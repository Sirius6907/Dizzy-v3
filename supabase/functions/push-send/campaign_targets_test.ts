/**
 * Unit tests for canary targeting.
 *
 *   node --test supabase/functions/push-send/campaign_targets_test.ts
 *
 * The rules under test are the two that make a two-phone trial safe:
 * a canary must not consume the real campaign's single-shot key, and it must
 * always land on the oldest builds — the phones where a broken copy shows up
 * first — in the same order on every retry.
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import { asIds, isCoolingDown, ledgerKey, pickCanary } from "./campaign_targets.ts";

const t = (id: string, from: string) => ({ id, from, token: `tok-${id}`, userId: `u-${id}`, platform: "android" });

test("a canary claims its own ledger key, so the real send stays available", () => {
  assert.equal(ledgerKey("2026-11-26", true), "2026-11-26#canary");
  assert.equal(ledgerKey("2026-11-26", false), "2026-11-26");
  assert.notEqual(ledgerKey("2026-11-26", true), ledgerKey("2026-11-26", false));
  assert.equal(ledgerKey("", false), "");
  assert.equal(ledgerKey("", true), "");
});

test("pickCanary keeps the oldest builds, not the database's order", () => {
  const rows = [t("a", "1.3.6"), t("b", "1.3.3"), t("c", "1.3.5"), t("d", "")];
  const picked = pickCanary(rows, 2).map((r) => r.id);
  // "" means no version ever reported: older than 1.3.3, so it leads.
  assert.deepEqual(picked, ["d", "b"]);
});

test("the same fleet picks the same canaries on a retry", () => {
  const rows = [t("z", "1.3.4"), t("y", "1.3.4"), t("x", "1.3.4")];
  assert.deepEqual(pickCanary(rows, 2).map((r) => r.id), pickCanary(rows.slice().reverse(), 2).map((r) => r.id));
});

test("1.3.10 sorts newer than 1.3.9, not older", () => {
  const rows = [t("new", "1.3.10"), t("old", "1.3.9")];
  assert.deepEqual(pickCanary(rows, 1).map((r) => r.id), ["old"]);
});

test("no limit, zero limit or a limit past the fleet means everyone", () => {
  const rows = [t("a", "1.3.6"), t("b", "1.3.4")];
  assert.equal(pickCanary(rows, 0).length, 2);
  assert.equal(pickCanary(rows, -3).length, 2);
  assert.equal(pickCanary(rows, 99).length, 2);
  assert.equal(pickCanary(rows, 1).length, 1);
  // The caller's array is never mutated: the whole fleet is still available
  // for the real send after a canary picked from it.
  assert.equal(rows.length, 2);
});

test("device ids are trimmed, deduplicated and bounded", () => {
  assert.deepEqual(asIds([" a ", "b", "a", "", null]), ["a", "b"]);
  assert.deepEqual(asIds("a,b"), []);
  assert.equal(asIds(["1", "2", "3"], 2).length, 2);
});

// The quiet period is what stops two releases in one week from becoming two
// notifications in one week. The boundary matters: exactly seven days old is
// eligible again, six days and 23 hours is not.
const NOW = new Date("2026-11-26T12:00:00Z");

test("a phone nudged today is cooling down", () => {
  assert.equal(isCoolingDown("2026-11-26T03:09:07Z", NOW), true);
});

test("a phone nudged seven days ago is eligible again", () => {
  assert.equal(isCoolingDown("2026-11-19T12:00:00Z", NOW), false);
  assert.equal(isCoolingDown("2026-11-19T12:00:01Z", NOW), true);
});

test("never-nudged phones are eligible", () => {
  assert.equal(isCoolingDown("", NOW), false);
  assert.equal(isCoolingDown(undefined, NOW), false);
  assert.equal(isCoolingDown(null, NOW), false);
  assert.equal(isCoolingDown("not a date", NOW), false);
});

test("a future timestamp (clock skew) counts as cooling down", () => {
  assert.equal(isCoolingDown("2026-11-27T12:00:00Z", NOW), true);
});

test("the window is configurable and zero disables it", () => {
  assert.equal(isCoolingDown("2026-11-25T12:00:00Z", NOW, 1), false);
  assert.equal(isCoolingDown("2026-11-25T12:00:00Z", NOW, 7), true);
  assert.equal(isCoolingDown("2026-11-26T11:59:00Z", NOW, 0), false);
});
