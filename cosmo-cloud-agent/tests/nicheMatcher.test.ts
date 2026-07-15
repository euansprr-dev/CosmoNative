// Niche matcher parity tests — 1:1 mirrors of the Mac's NicheRegistryTests
// (Tests/CosmoOSTests/NicheRegistryTests.swift). The matching contract
// (exact → alias → fuzzy(≥0.60) → none) must behave identically on both
// sides; keep both suites in sync.
// Run: SUPABASE_SERVICE_ROLE_KEY=test-dummy COSMO_USER_ID=test-user npx tsx tests/nicheMatcher.test.ts

import assert from 'node:assert/strict';
import {
  bestMatch, candidateKeys, CanonicalNiche, cleanedCanonicalLabel,
  FUZZY_THRESHOLD, isTokenSubsequence, nichePromptInstruction, normalizeKey, similarity,
} from '../src/swipes/niche';

let counter = 0;
function niche(value: string, aliases: string[] = [], usageCount = 0, sortOrder = 0): CanonicalNiche {
  counter += 1;
  return { atomUUID: `UUID-${counter}`, value, aliases, usageCount, sortOrder };
}

// ── normalizeKey / cleanedCanonicalLabel ────────────────────────────────────

assert.equal(normalizeKey('  Real   Estate\nWholesaling '), 'real estate wholesaling');
assert.equal(normalizeKey('FITNESS'), 'fitness');

assert.equal(cleanedCanonicalLabel('"SaaS Marketing"'), 'SaaS Marketing');
assert.equal(cleanedCanonicalLabel('  Health  &\nWellness '), 'Health & Wellness');
assert.equal(cleanedCanonicalLabel('SaaS'), 'SaaS');

const long = 'Extremely Long Niche Label That Keeps Going And Going Forever';
const cleaned = cleanedCanonicalLabel(long);
assert.ok(cleaned.length <= 48);
assert.ok(!cleaned.endsWith(' '));
assert.ok(long.startsWith(cleaned));

// ── candidateKeys (combo splitting) ─────────────────────────────────────────

assert.deepEqual(
  candidateKeys('Tax Strategy & Vending Machines'),
  ['tax strategy & vending machines', 'tax strategy', 'vending machines']
);
assert.deepEqual(
  candidateKeys('Real Estate / Sober Living'),
  ['real estate / sober living', 'real estate', 'sober living']
);
assert.deepEqual(
  candidateKeys('Real Estate Investing - Airbnb'),
  ['real estate investing - airbnb', 'real estate investing', 'airbnb']
);
assert.deepEqual(candidateKeys('Fitness'), ['fitness']);

// ── similarity ──────────────────────────────────────────────────────────────

assert.equal(similarity('fitness', 'fitness'), 1.0);
assert.ok(similarity('real estate investing', 'airbnb real estate investing') >= FUZZY_THRESHOLD);
assert.ok(similarity('ai', 'air travel') < FUZZY_THRESHOLD);
assert.ok(similarity('fitness', 'finance') < FUZZY_THRESHOLD);
// The core requirement: wholesaling and investing never fold into each other.
assert.ok(similarity('real estate wholesaling', 'real estate investing') < FUZZY_THRESHOLD);

assert.ok(isTokenSubsequence(['real', 'estate'], ['real', 'estate', 'investing']));
assert.ok(isTokenSubsequence(['ai', 'agency'], ['ai', 'automation', 'agency']));
assert.ok(!isTokenSubsequence(['estate', 'real'], ['real', 'estate']));
assert.ok(!isTokenSubsequence([], ['real']));

// ── bestMatch tiers ─────────────────────────────────────────────────────────

{
  const niches = [niche('Real Estate Wholesaling'), niche('Fitness')];
  assert.deepEqual(bestMatch('real estate wholesaling', niches), { tier: 'exact', index: 0 });
  assert.deepEqual(bestMatch('FITNESS', niches), { tier: 'exact', index: 1 });
}

{
  const niches = [
    niche('Health & Wellness', ['Mental Health & Wellness', 'Spiritual Wellness']),
    niche('Fitness'),
  ];
  assert.deepEqual(bestMatch('mental health & wellness', niches), { tier: 'alias', index: 0 });
}

{
  const niches = [niche('Real Estate Investing'), niche('Fitness')];
  const match = bestMatch('Real Estate Investment', niches);
  assert.equal(match.tier, 'fuzzy');
  if (match.tier === 'fuzzy') {
    assert.equal(match.index, 0);
    assert.ok(match.score >= FUZZY_THRESHOLD);
  }
}

{
  const match = bestMatch('Fitness Coaching', [niche('Fitness')]);
  assert.equal(match.tier, 'fuzzy');
  if (match.tier === 'fuzzy') assert.equal(match.index, 0);
}

{
  const niches = [niche('Vending Machine Business'), niche('Real Estate Investing')];
  assert.deepEqual(bestMatch('Tax Strategy & Vending Machine Business', niches), { tier: 'exact', index: 0 });
  assert.deepEqual(bestMatch('Real Estate Investing - Airbnb', niches), { tier: 'exact', index: 1 });
}

{
  // When both the combo and a segment exist as canonicals, the combo wins.
  const niches = [niche('Tax Strategy'), niche('Tax Strategy & Vending Machine Business')];
  assert.deepEqual(bestMatch('tax strategy & vending machine business', niches), { tier: 'exact', index: 1 });
}

{
  const niches = [niche('Real Estate Wholesaling'), niche('Fitness'), niche('Content Creation')];
  assert.deepEqual(bestMatch('Quantum Computing', niches), { tier: 'none' });
  assert.deepEqual(bestMatch('Real Estate Investing', niches), { tier: 'none' });
}

assert.deepEqual(bestMatch('', [niche('Fitness')]), { tier: 'none' });
assert.deepEqual(bestMatch('Fitness', []), { tier: 'none' });

// ── prompt instruction ──────────────────────────────────────────────────────

const withList = nichePromptInstruction('Fitness, Content Creation');
assert.ok(withList.includes('EXISTING NICHES'));
assert.ok(withList.includes('Fitness, Content Creation'));
const withoutList = nichePromptInstruction('');
assert.ok(!withoutList.includes('EXISTING NICHES'));
assert.ok(withoutList.includes('CORE CATEGORY'));

console.log('✅ nicheMatcher.test.ts — all assertions passed');
