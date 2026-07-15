// cosmo-cloud-agent/src/swipes/niche.ts
// Canonical niche resolution — a 1:1 port of the Mac's NicheMatcher +
// NicheRegistry (SwipeFile/NicheRegistry.swift). The shared store is
// taxonomy_value atoms (dimension "niche") in Supabase, the same atoms the
// Mac and iPhone sync; matching is exact → known alias → fuzzy(≥0.60) →
// create. On ANY storage failure the cleaned raw label passes through —
// niche resolution must never block swipe processing.

import { fetchAllByType, createAtom, updateAtom } from '../db/queries';

export interface CanonicalNiche {
  atomUUID: string;
  value: string;
  aliases: string[];
  usageCount: number;
  sortOrder: number;
}

export const NICHE_DIMENSION = 'niche';
export const FUZZY_THRESHOLD = 0.60;
const CACHE_TTL_MS = 60_000;

// ── Pure matching (mirrors NicheMatcher — change both together) ─────────────

/** Case/whitespace-insensitive comparison key. */
export function normalizeKey(raw: string): string {
  return raw.toLowerCase().replace(/\s+/g, ' ').trim();
}

/**
 * Cleaned display label for a brand-new canonical niche: trim, strip wrapping
 * quotes, collapse whitespace, hard-cap length on a word boundary.
 * Capitalization is preserved ("SaaS Marketing" must not become "Saas…").
 */
export function cleanedCanonicalLabel(raw: string): string {
  let label = raw.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim();
  while (
    label.length >= 2 &&
    ((label.startsWith('"') && label.endsWith('"')) ||
      (label.startsWith("'") && label.endsWith("'")))
  ) {
    label = label.slice(1, -1).trim();
  }
  if (label.length > 48) {
    const cut = label.slice(0, 48);
    label = cut.includes(' ') ? cut.split(' ').slice(0, -1).join(' ') : cut;
  }
  return label;
}

/**
 * Split a combo label ("X & Y", "X / Y", "X - Y", "X: Y") into candidate
 * segments, full label first — the historical fragmentation is dominated by
 * these mashups.
 */
export function candidateKeys(raw: string): string[] {
  const full = normalizeKey(raw);
  if (!full) return [];
  const keys = [full];
  const separators = [' & ', ' / ', '/', ' - ', ' – ', ' — ', ': ', ', '];
  let segments = [full];
  for (const separator of separators) {
    segments = segments.flatMap(s => s.split(separator));
  }
  for (const segment of segments) {
    const trimmed = segment.trim();
    if (trimmed.length >= 3 && !keys.includes(trimmed)) keys.push(trimmed);
  }
  return keys;
}

/** needle's tokens appear in order (not necessarily contiguous) in haystack's. */
export function isTokenSubsequence(needle: string[], haystack: string[]): boolean {
  if (needle.length === 0) return false;
  let index = 0;
  for (const token of haystack) {
    if (token === needle[index]) {
      index += 1;
      if (index === needle.length) return true;
    }
  }
  return false;
}

function bigrams(s: string): string[] {
  if (s.length < 2) return [s];
  const result: string[] = [];
  for (let i = 0; i < s.length - 1; i++) result.push(s.slice(i, i + 2));
  return result;
}

/**
 * Similarity between two normalized keys: token-subsequence containment
 * (word-boundary aware — "ai" must not match inside "air travel") with a
 * length-ratio bonus, else bigram Jaccard.
 */
export function similarity(a: string, b: string): number {
  if (a === b) return 1.0;
  if (!a || !b) return 0.0;

  const tokensA = a.split(' ').filter(Boolean);
  const tokensB = b.split(' ').filter(Boolean);
  const [shorter, longer] = tokensA.length <= tokensB.length ? [tokensA, tokensB] : [tokensB, tokensA];
  if (shorter.join('').length >= 3 && isTokenSubsequence(shorter, longer)) {
    const shortLen = shorter.join(' ').length;
    const longLen = longer.join(' ').length;
    return 0.6 + 0.4 * (shortLen / longLen);
  }

  const bigramsA = new Set(bigrams(a));
  const bigramsB = new Set(bigrams(b));
  if (bigramsA.size === 0 || bigramsB.size === 0) return 0;
  let intersection = 0;
  for (const gram of bigramsA) if (bigramsB.has(gram)) intersection += 1;
  const union = bigramsA.size + bigramsB.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

export type NicheMatch =
  | { tier: 'exact'; index: number }
  | { tier: 'alias'; index: number }
  | { tier: 'fuzzy'; index: number; score: number }
  | { tier: 'none' };

/** Three-tier match of a raw label against the canonical list. */
export function bestMatch(raw: string, niches: CanonicalNiche[]): NicheMatch {
  const keys = candidateKeys(raw);
  if (keys.length === 0 || niches.length === 0) return { tier: 'none' };

  for (const key of keys) {
    const index = niches.findIndex(n => normalizeKey(n.value) === key);
    if (index >= 0) return { tier: 'exact', index };
  }

  for (const key of keys) {
    const index = niches.findIndex(n => n.aliases.some(a => normalizeKey(a) === key));
    if (index >= 0) return { tier: 'alias', index };
  }

  let bestScore = 0;
  let bestIndex = -1;
  niches.forEach((niche, index) => {
    const candidates = [normalizeKey(niche.value), ...niche.aliases.map(normalizeKey)];
    for (const key of keys) {
      for (const candidate of candidates) {
        const score = similarity(key, candidate);
        if (score > bestScore) {
          bestScore = score;
          bestIndex = index;
        }
      }
    }
  });
  if (bestScore >= FUZZY_THRESHOLD && bestIndex >= 0) {
    return { tier: 'fuzzy', index: bestIndex, score: bestScore };
  }
  return { tier: 'none' };
}

/**
 * The niche instruction block for the classification prompt — wording kept in
 * sync with NicheRegistry.promptInstruction on the Mac.
 */
export function nichePromptInstruction(canonicalList: string): string {
  const lines = ['niche — the content\'s core vertical.'];
  if (canonicalList) {
    lines.push(`EXISTING NICHES (choose one of these whenever it fits — matching an existing niche is strongly preferred): ${canonicalList}`);
    lines.push('Only introduce a NEW niche when the content genuinely belongs to a vertical not represented above.');
  }
  lines.push('A niche is a CORE CATEGORY someone builds an audience in ("Fitness", "Content Creation", "Real Estate Wholesaling") — never a sub-topic, a combo ("X & Y", "X / Y"), or a hook-level description. If the content spans two verticals, pick the one the creator\'s audience follows them for.');
  return lines.join('\n');
}

// ── Registry (Supabase-backed, 60s cache) ───────────────────────────────────

let cache: { niches: CanonicalNiche[]; fetchedAt: number } | null = null;

export function invalidateNicheCache(): void {
  cache = null;
}

export async function fetchCanonicalNiches(): Promise<CanonicalNiche[]> {
  if (cache && Date.now() - cache.fetchedAt < CACHE_TTL_MS) return cache.niches;

  const atoms = await fetchAllByType('taxonomy_value', { limit: 500 });
  const niches: CanonicalNiche[] = [];
  for (const atom of atoms) {
    const meta = (atom.metadata ?? {}) as Record<string, unknown>;
    if (meta.dimension !== NICHE_DIMENSION) continue;
    const value = typeof meta.value === 'string' ? meta.value.trim() : '';
    if (!value) continue;
    niches.push({
      atomUUID: atom.uuid,
      value,
      aliases: Array.isArray(meta.aliases) ? (meta.aliases as string[]).filter(a => typeof a === 'string') : [],
      usageCount: typeof meta.usageCount === 'number' ? meta.usageCount : 0,
      sortOrder: typeof meta.sortOrder === 'number' ? meta.sortOrder : 0,
    });
  }
  cache = { niches, fetchedAt: Date.now() };
  return niches;
}

/** Usage-ordered canonical values for the classification prompt ('' when empty). */
export async function canonicalNicheList(): Promise<string> {
  try {
    const niches = await fetchCanonicalNiches();
    return [...niches]
      .sort((a, b) => b.usageCount - a.usageCount)
      .map(n => n.value)
      .join(', ');
  } catch {
    return '';
  }
}

/** Bump usage and (for fuzzy folds) record the raw variant as an alias. */
async function recordUsage(niche: CanonicalNiche, variant: string | null): Promise<void> {
  try {
    const aliases = [...niche.aliases];
    if (variant) {
      const key = normalizeKey(variant);
      const known = aliases.some(a => normalizeKey(a) === key) || normalizeKey(niche.value) === key;
      if (!known) aliases.push(variant);
    }
    // updateAtom shallow-merges metadata keys — usageCount/aliases replace cleanly.
    await updateAtom(niche.atomUUID, {
      metadata: { usageCount: niche.usageCount + 1, aliases },
    });
    if (cache) {
      const cached = cache.niches.find(n => n.atomUUID === niche.atomUUID);
      if (cached) {
        cached.usageCount += 1;
        if (variant && !cached.aliases.some(a => normalizeKey(a) === normalizeKey(variant))) {
          cached.aliases.push(variant);
        }
      }
    }
  } catch (error) {
    console.warn('⚠️ niche usage update failed:', error instanceof Error ? error.message : error);
  }
}

/**
 * Create a new canonical niche atom. Refetches and re-matches first — the
 * cache may hide a niche the Mac or another run just created (same accepted
 * race profile as creator resolution).
 */
async function createNiche(value: string): Promise<string | null> {
  invalidateNicheCache();
  const fresh = await fetchCanonicalNiches();
  const match = bestMatch(value, fresh);
  if (match.tier !== 'none') {
    await recordUsage(fresh[match.index], match.tier === 'fuzzy' ? value : null);
    return fresh[match.index].value;
  }

  const created = await createAtom({
    type: 'taxonomy_value',
    title: value,
    metadata: {
      dimension: NICHE_DIMENSION,
      value,
      sortOrder: fresh.length,
      isDefault: false,
      usageCount: 1,
    },
  });
  if (!created) return null;
  invalidateNicheCache();
  return value;
}

/**
 * Resolve a raw classifier label into a canonical niche value, creating a new
 * canonical only when nothing matches. Never throws.
 */
export async function resolveNiche(raw: string): Promise<string> {
  const cleaned = cleanedCanonicalLabel(raw);
  if (!cleaned) return raw;

  let niches: CanonicalNiche[];
  try {
    niches = await fetchCanonicalNiches();
  } catch (error) {
    console.warn('⚠️ niche registry fetch failed:', error instanceof Error ? error.message : error);
    return cleaned;
  }

  const match = bestMatch(cleaned, niches);
  switch (match.tier) {
    case 'exact':
    case 'alias':
      await recordUsage(niches[match.index], null);
      return niches[match.index].value;
    case 'fuzzy':
      await recordUsage(niches[match.index], cleaned);
      return niches[match.index].value;
    case 'none':
      try {
        return (await createNiche(cleaned)) ?? cleaned;
      } catch (error) {
        console.warn('⚠️ niche create failed:', error instanceof Error ? error.message : error);
        return cleaned;
      }
  }
}
