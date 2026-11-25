/**
 * Unit tests for the update campaign's version gate.
 *
 *   node --test supabase/functions/push-send/version_compare_test.ts
 *
 * The rule under test is the one that keeps a campaign honest: a phone that
 * already runs the target build must never be told to update to it. The fleet
 * still had four v1.3.6 Android tokens when the v1.3.7 campaign was prepared,
 * and before this filter they would have received "v1.3.6 -> v1.3.7".
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import { readFile } from "node:fs/promises";

import { compareVersions, shouldNudge, versionPair } from "./version_compare.ts";

test("dotted versions compare numerically, not as strings", () => {
  assert.equal(compareVersions("1.3.6", "1.3.7"), -1);
  assert.equal(compareVersions("1.3.7", "1.3.6"), 1);
  assert.equal(compareVersions("1.3.7", "1.3.7"), 0);
  // "1.3.10" is newer than "1.3.9"; a string compare would say the opposite.
  assert.equal(compareVersions("1.3.10", "1.3.9"), 1);
  assert.equal(compareVersions("1.10.0", "1.9.9"), 1);
});

test("a leading v and a build suffix are handled", () => {
  assert.equal(compareVersions("v1.3.5", "1.3.7"), -1);
  // The client writes PackageInfo.version (no suffix), but a token that does
  // report one is newer than the plain release, never older.
  assert.equal(compareVersions("1.3.7+1039", "1.3.7"), 1);
  assert.equal(compareVersions("1.3.6+1038", "1.3.7"), -1);
});

test("shouldNudge targets only phones below the campaign version", () => {
  assert.equal(shouldNudge("1.3.7", "1.3.7"), false);
  assert.equal(shouldNudge("1.3.7+1039", "1.3.7"), false);
  assert.equal(shouldNudge("1.4.0", "1.3.7"), false);
  assert.equal(shouldNudge("1.3.6", "1.3.7"), true);
  assert.equal(shouldNudge("1.3.5", "1.3.7"), true);
  assert.equal(shouldNudge("1.2.99", "1.3.0"), true);
});

test("a token with no reported version is treated as old", () => {
  // Such a token predates version reporting, so it cannot be current.
  assert.equal(shouldNudge("", "1.3.7"), true);
});

test("the body pair collapses to the destination when no version was reported", () => {
  assert.equal(versionPair("1.3.6", "1.3.7"), "v1.3.6 → v1.3.7");
  assert.equal(versionPair("v1.3.4", "v1.3.7"), "v1.3.4 → v1.3.7");
  assert.equal(versionPair("1.3.7+1039", "1.3.7"), "v1.3.7+1039 → v1.3.7");
  // The bug this exists for: a token with no app_version must never read
  // "v your version → v1.3.7", which is what building the pair in the
  // template ("v{from} → v{latest}") did once {from} fell back to "your
  // version".
  assert.equal(versionPair("", "1.3.7"), "v1.3.7");
  assert.equal(versionPair("  ", "1.3.7"), "v1.3.7");
  assert.equal(versionPair("unknown", "1.3.7"), "v1.3.7");
  assert.equal(versionPair("null", "1.3.7"), "v1.3.7");
});

// The four bodies live in index.ts, which cannot be imported here (Deno edge
// imports), so the guard reads the source and renders the real templates with
// the real helper. A body that hand-builds the pair fails this test before any
// phone can receive the broken line.
test("no campaign body can render a broken version pair", async () => {
  const src = await readFile(new URL("./index.ts", import.meta.url), "utf8");
  const block = src.match(/const UPDATE_PATTERNS: Pattern\[\] = (\[[\s\S]*?\n\]);/);
  assert.ok(block, "UPDATE_PATTERNS not found in index.ts");
  const patterns = new Function(`return ${block![1]}`)() as { body: string }[];
  assert.equal(patterns.length, 4);
  for (const p of patterns) {
    assert.ok(p.body.includes("{versions}"), p.body);
    assert.equal(/v\{from\}|\{latest\}/.test(p.body), false, p.body);
    for (const from of ["1.3.6", ""]) {
      const rendered = p.body.replace("{versions}", versionPair(from, "1.3.7"));
      assert.equal(/your version/.test(rendered), false, rendered);
      assert.equal(/v\s*→/.test(rendered), false, rendered);
    }
  }
});

test("a mixed fleet keeps the old phones and drops the updated ones", () => {
  // Shape of the enabled fleet measured on 2026-11-25: 1.3.3 x2, 1.3.4 x4,
  // 1.3.5 x6, 1.3.6 x4 — plus one phone that already updated to 1.3.7.
  const fleet = [
    ...Array(2).fill("1.3.3"),
    ...Array(4).fill("1.3.4"),
    ...Array(6).fill("1.3.5"),
    ...Array(4).fill("1.3.6"),
    "1.3.7",
  ];
  const targets = fleet.filter((v) => shouldNudge(v, "1.3.7"));
  assert.equal(targets.length, 16);
  assert.equal(targets.includes("1.3.7"), false);
});
