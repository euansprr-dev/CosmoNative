// cosmo-cloud-agent/src/writing/codexLoader.ts
// Loads and caches the full Exemplar Codex body from Supabase.
// The Codex is the complete formal language of Content Physics (~486K chars, ~170K tokens).
// Used by: codexExtractor (for extraction context), writing engine (for full language injection).

import { fetchAllByType } from '../db/queries';

// ============================================================
// In-Memory Cache
// ============================================================

let cachedExemplarCodex: { body: string; loadedAt: number } | null = null;
const EXEMPLAR_CODEX_CACHE_TTL = 3600_000; // 1 hour

/**
 * Load the full Exemplar Codex body from Supabase.
 * Caches in memory for 1 hour. Returns null if no Codex atom found.
 */
export async function loadExemplarCodex(): Promise<string | null> {
  // Return cached if fresh
  if (cachedExemplarCodex && Date.now() - cachedExemplarCodex.loadedAt < EXEMPLAR_CODEX_CACHE_TTL) {
    return cachedExemplarCodex.body;
  }

  // Load from Supabase — the Exemplar Codex is a research atom with isCodexSynthesis=true
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const codexAtom = allAtoms.find(a => a.metadata?.isCodexSynthesis);

  if (codexAtom?.body && codexAtom.body.length > 10000) {
    cachedExemplarCodex = { body: codexAtom.body, loadedAt: Date.now() };
    console.log(`  📚 Loaded Exemplar Codex: ${codexAtom.body.length} chars (~${Math.round(codexAtom.body.length / 4)} tokens)`);
    return codexAtom.body;
  }

  console.log('  ⚠️ Exemplar Codex not found or too small');
  return null;
}

/**
 * Force-reload the Codex on next access (e.g., after a Codex pipeline run).
 */
export function invalidateExemplarCodexCache(): void {
  cachedExemplarCodex = null;
}

/**
 * Get the cached Codex body without hitting the database.
 * Returns null if not yet loaded. Call loadExemplarCodex() first.
 */
export function getCachedExemplarCodex(): string | null {
  if (cachedExemplarCodex && Date.now() - cachedExemplarCodex.loadedAt < EXEMPLAR_CODEX_CACHE_TTL) {
    return cachedExemplarCodex.body;
  }
  return null;
}
