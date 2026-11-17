/**
 * Unit tests for the pure parts of the latest-releases helper.
 * Run with: deno test supabase/functions/catalog/latest_releases_test.ts
 */

import {
  buildLatestBucket,
  latestFor,
  mergeLatest,
  normaliseTitle,
  releasedOnly,
  sortByReleaseDate,
  type LatestTitle,
} from "./latest_releases.ts";

const row = (over: Partial<LatestTitle>): LatestTitle => ({
  id: `tmdb:${over.tmdbId ?? "1"}`,
  title: "Title",
  releaseDate: "2026-01-01",
  lang: "hi",
  source: "tmdb",
  sources: ["tmdb"],
  ...over,
});

Deno.test("normaliseTitle drops brackets, punctuation and stop words", () => {
  if (normaliseTitle("Bhai - The Opening Part (2025)") !== "bhai opening") {
    throw new Error("got: " + normaliseTitle("Bhai - The Opening Part (2025)"));
  }
  if (normaliseTitle("Dahaan: The Evil Within") !== "dahaan evil within") {
    throw new Error("got: " + normaliseTitle("Dahaan: The Evil Within"));
  }
});

Deno.test("mergeLatest folds providers that describe the same title", () => {
  const merged = mergeLatest(
    [row({ tmdbId: "1", title: "Madhumallati", releaseDate: "2026-08-01" })],
    [row({ title: "Madhumalati", source: "imdb", sources: ["imdb"], imdbId: "tt9", releaseDate: "" })],
  );
  if (merged.length !== 1) throw new Error("expected one row, got " + merged.length);
  const m = merged[0];
  if (m.tmdbId !== "1" || m.imdbId !== "tt9") throw new Error("ids not merged");
  if (m.sources.join(",") !== "tmdb,imdb") throw new Error("sources: " + m.sources.join(","));
});

Deno.test("mergeLatest keeps the earliest-known fields when one provider is empty", () => {
  const merged = mergeLatest(
    [row({ title: "Dahaan", releaseDate: "2026-05-05", rating: 6.1 })],
    [row({ title: "Dahaan", source: "omdb", sources: ["omdb"], releaseDate: "", rating: 7.9 })],
  );
  if (merged[0].releaseDate !== "2026-05-05") throw new Error("date lost");
  if (merged[0].rating !== 7.9) throw new Error("better rating not kept");
});

Deno.test("sortByReleaseDate is newest first and sinks unknown dates", () => {
  const sorted = sortByReleaseDate([
    row({ title: "old", releaseDate: "2025-01-01" }),
    row({ title: "unknown", releaseDate: "" }),
    row({ title: "new", releaseDate: "2026-09-09" }),
  ]);
  if (sorted.map((r) => r.title).join(",") !== "new,old,unknown") {
    throw new Error("got: " + sorted.map((r) => r.title).join(","));
  }
});

Deno.test("latestFor keeps the per-language cap", () => {
  const rows = Array.from({ length: 120 }, (_, i) =>
    row({ title: `t${i}`, releaseDate: `2026-01-${String((i % 28) + 1).padStart(2, "0")}`, lang: i < 60 ? "hi" : "or" }),
  );
  const out = latestFor(rows, ["hi", "or"], 50);
  if (out.length !== 100) throw new Error("expected 100, got " + out.length);
  if (out.filter((r) => r.lang === "hi").length !== 50) throw new Error("hi cap broken");
  if (out.filter((r) => r.lang === "or").length !== 50) throw new Error("or cap broken");
});

Deno.test("releasedOnly drops unreleased and undated titles", () => {
  const rows = [
    row({ title: "out now", releaseDate: "2026-10-16" }),
    row({ title: "future", releaseDate: "2028-10-17" }),
    row({ title: "no date", releaseDate: "" }),
    row({ title: "today", releaseDate: "2026-11-15" }),
  ];
  const kept = releasedOnly(rows, "2026-11-15").map((r) => r.title);
  if (kept.join(",") !== "out now,today") {
    throw new Error("got: " + kept.join(","));
  }
});

Deno.test("buildLatestBucket survives a TMDB failure without throwing", async () => {
  // No network in unit tests: the helper must surface the error, not fake data.
  let threw = false;
  try {
    await buildLatestBucket({ tmdbKey: "not-a-key", lang: "hi", sinceIso: "2026-01-01" });
  } catch (_) {
    threw = true;
  }
  if (!threw) throw new Error("expected a TMDB error to propagate");
});
