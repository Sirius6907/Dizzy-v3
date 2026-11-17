/**
 * Unit tests for the resolver's title matcher.
 *
 * Runs on both toolchains:
 *   node --test supabase/functions/resolve/title_match_test.ts
 *   deno test supabase/functions/resolve/title_match_test.ts
 *
 * The rules under test are the ones that decide whether a title resolves to
 * the RIGHT film: a wrong match plays the wrong video (poster A, playback B)
 * across ~40 scrapers, so every relaxation is paid for with a year and/or
 * language guard.
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  baseTitle,
  cleanTitle,
  editDistance,
  pickCorpusMatch,
  pickImdbMatch,
  type CorpusRow,
} from "./title_match.ts";

const row = (over: Partial<CorpusRow>): CorpusRow => ({
  kind: "movie",
  tmdbId: 1,
  title: "Title",
  year: 2026,
  lang: "or",
  popularity: 1,
  ...over,
});

test("cleanTitle lowercases and strips punctuation", () => {
  assert.equal(cleanTitle("Bhai - The Opening Part"), "bhaitheopeningpart");
  assert.equal(cleanTitle("Dahaan: The Evil Within"), "dahaantheevilwithin");
});

test("baseTitle drops the subtitle and the stop words", () => {
  assert.equal(baseTitle("Dahaan: The Evil Within"), "dahaan");
  assert.equal(baseTitle("AWM (Agney Weds Minal)"), "awm");
  assert.equal(baseTitle("Bhai - The Opening Part"), "bhai");
  assert.equal(baseTitle("Rakta Golapa"), "raktagolapa");
});

test("editDistance counts a transposition as one edit", () => {
  assert.equal(editDistance("minal", "minall"), 1);
  assert.equal(editDistance("abc", "abc"), 0);
  assert.equal(editDistance("abc", "xyz"), 3);
});

test("an exact title match wins", () => {
  const m = pickCorpusMatch(
    "Kankana",
    [row({ tmdbId: 1733875, title: "Kankana", year: 2026 })],
    { kind: "movie", year: 2026 },
  );
  assert.ok(m);
  assert.equal(m.quality, "exact");
  assert.equal(m.row.tmdbId, 1733875);
});

test("a subtitle alias resolves to the core title", () => {
  const m = pickCorpusMatch(
    "Dahaan: The Evil Within",
    [row({ tmdbId: 1157265, title: "Dahaan", year: 2026 })],
    { kind: "movie", year: 2026 },
  );
  assert.ok(m);
  assert.equal(m.quality, "alias");
  assert.equal(m.row.tmdbId, 1157265);
});

test("a one-edit spelling match needs the year to agree", () => {
  const rows = [row({ tmdbId: 1133036, title: "AWM (Agney Weds Minal)", year: 2026 })];

  const withYear = pickCorpusMatch("AWM (Agney Weds Minall)", rows, {
    kind: "movie",
    year: 2026,
  });
  assert.ok(withYear);
  // "awm" is too short a core to stand on its own, so the one-edit
  // spelling is what carries the match.
  assert.equal(withYear.quality, "alias");
  assert.equal(withYear.row.tmdbId, 1133036);

  // No year to pin it â†’ too weak, the match is refused.
  const noYear = pickCorpusMatch("AWM (Agney Weds Minall)", rows, {
    kind: "movie",
  });
  assert.equal(noYear, null);
});

test("a wrong-year row never answers a year-pinned request", () => {
  const m = pickCorpusMatch(
    "Game Over",
    [row({ tmdbId: 1619085, title: "Game Over", year: 2024, lang: "es" })],
    { kind: "movie", year: 2026 },
  );
  assert.equal(m, null);
});

test("the kind is respected", () => {
  const rows = [row({ tmdbId: 5, title: "Kankana", kind: "tv", year: 2026 })];
  assert.equal(pickCorpusMatch("Kankana", rows, { kind: "movie" }), null);
  assert.ok(pickCorpusMatch("Kankana", rows, { kind: "tv" }));
});

test("among equal candidates the closest year wins", () => {
  const rows = [
    row({ tmdbId: 1, title: "Game Over", year: 2024, popularity: 900 }),
    row({ tmdbId: 2, title: "Game Over", year: 2026, popularity: 1 }),
  ];
  const m = pickCorpusMatch("Game Over", rows, { kind: "movie", year: 2026 });
  assert.ok(m);
  assert.equal(m.row.tmdbId, 2);
});

test("an unrelated title does not match", () => {
  const m = pickCorpusMatch(
    "Memshab",
    [row({ tmdbId: 9, title: "Rakta Golapa", year: 2026 })],
    { kind: "movie", year: 2026 },
  );
  assert.equal(m, null);
});

test("a one-edit match to a different film with no year is refused", () => {
  // THE wrong-content trap: "Murabi" is one edit away from "Murali", and
  // the row has no year to confirm it. A name is not an identity.
  const m = pickCorpusMatch(
    "Murabi",
    [row({ tmdbId: 77, title: "Murali", year: null, lang: "ta" })],
    { kind: "movie", year: 2026 },
  );
  assert.equal(m, null);
});

test("a one-edit match to a different film with a matching year is refused", () => {
  const m = pickCorpusMatch(
    "Murabi",
    [row({ tmdbId: 77, title: "Murali", year: 2026, lang: "ta" })],
    { kind: "movie", year: 2026 },
  );
  // The year agrees, so this one is allowed through: same year, one edit
  // apart. The language filter is the resolver's job, not the matcher's.
  assert.ok(m);
  assert.equal(m.quality, "fuzzy");
});

// --- IMDb fallback -------------------------------------------------------
// The titles TMDB has never heard of (measured: 25 of the owner's 26
// unresolved Odia titles DO exist on IMDb). The year guard is the whole
// point: the same name is often a completely different, older film.

test("the IMDb fallback accepts the film the year confirms", () => {
  const m = pickImdbMatch(
    "Danger Devdas",
    [{ imdbId: "tt50321085", title: "Danger Devdas", year: 2026 }],
    { year: 2026 },
  );
  assert.ok(m);
  assert.equal(m.imdbId, "tt50321085");
});

test("the IMDb fallback refuses an older film with the same name", () => {
  const m = pickImdbMatch(
    "Game Over",
    [{ imdbId: "tt3317234", title: "Game Over, Man!", year: 2018 }],
    { year: 2026 },
  );
  assert.equal(m, null);
});

test("the IMDb fallback refuses a different film that only looks similar", () => {
  const m = pickImdbMatch(
    "Diary",
    [{ imdbId: "tt1196141", title: "Diary of a Wimpy Kid", year: 2010 }],
    { year: 2026 },
  );
  assert.equal(m, null);
});

test("the IMDb fallback allows a one-edit spelling when the year agrees", () => {
  const m = pickImdbMatch(
    "Madhumallati",
    [{ imdbId: "tt0234164", title: "Madhumalati", year: 1957 }],
    { year: 1957 },
  );
  assert.ok(m);
  assert.equal(m.imdbId, "tt0234164");
});
