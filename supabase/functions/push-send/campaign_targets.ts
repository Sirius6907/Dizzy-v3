// Target selection for a version-aware update campaign.
//
// Two jobs live here, both pure so `node --test` can exercise them without a
// Deno runtime or a database:
//
//   1. ledgerKey() — a canary is a *separate* claim on the ledger. Without it,
//      trialling two phones would consume the campaign's 20-hour single-shot
//      guard and the real, whole-fleet send would be refused as "already sent".
//   2. pickCanary() — a trial has to hit the phones most likely to break, i.e.
//      the oldest reported builds, and it has to pick the same phones on a
//      retry, so the order is version-then-id, never the database's order.

import { compareVersions } from "./version_compare.ts";

export type CampaignTarget = {
  id: string;
  token: string;
  userId: string;
  platform: string;
  from: string;
};

/** The ledger `target` string a campaign claims. Empty campaign = no claim. */
export function ledgerKey(campaign: string, canary: boolean): string {
  if (!campaign) return "";
  return canary ? `${campaign}#canary` : campaign;
}

/** Narrow a list to `limit` phones, oldest build first.
 *
 *  limit <= 0 (or >= the list length) means "all of them", so a normal send is
 *  untouched. A phone that never reported a version is treated as the oldest:
 *  it predates version reporting, which makes it the most interesting canary,
 *  not the least.
 */
export function pickCanary<T extends { id: string; from: string }>(
  rows: T[],
  limit: number,
): T[] {
  const n = Math.floor(Number(limit));
  if (!Number.isFinite(n) || n <= 0 || n >= rows.length) return rows.slice();
  const sorted = rows.slice().sort((a, b) => {
    const av = a.from || "0";
    const bv = b.from || "0";
    const cmp = compareVersions(av, bv);
    if (cmp !== 0) return cmp;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return sorted.slice(0, n);
}

/** Ids from a JSON body field. Deduplicated, bounded, empty-safe — an
 *  operator pasting a list with spaces and newlines must not silently target
 *  nobody. */
export function asIds(raw: unknown, max = 1000): string[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  for (const v of raw) {
    const id = String(v ?? "").trim();
    if (id) seen.add(id);
    if (seen.size >= max) break;
  }
  return [...seen];
}
