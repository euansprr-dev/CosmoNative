// cosmo-cloud-agent/src/writing/codexPipeline.ts
// Full codex generation pipeline: background extraction → computed stats → Opus synthesis
// Runs independently of HTTP request lifecycle. Progress tracked in memory, pollable via API.

import { config } from '../config';
import { Atom, fetchAllByType, updateAtom, createAtom } from '../db/queries';
import { extractQuarkProfile } from './quarkExtractor';
import { computeCodex, saveCodexAtom, invalidateCodexCache } from './codex';
import { QuarkProfile } from './types';

// ============================================================
// Progress Tracking
// ============================================================

export interface CodexProgress {
  status: 'idle' | 'extracting' | 'computing_stats' | 'synthesizing' | 'saving' | 'complete' | 'failed';
  phase: string;
  current: number;
  total: number;
  extracted: number;
  skipped: number;
  failed: number;
  startedAt: string | null;
  completedAt: string | null;
  error: string | null;
  synthesisTokens: { input: number; output: number } | null;
}

let currentProgress: CodexProgress = {
  status: 'idle', phase: '', current: 0, total: 0,
  extracted: 0, skipped: 0, failed: 0,
  startedAt: null, completedAt: null, error: null, synthesisTokens: null,
};

export function getCodexProgress(): CodexProgress {
  return { ...currentProgress };
}

function updateProgress(updates: Partial<CodexProgress>): void {
  currentProgress = { ...currentProgress, ...updates };
  console.log(`  📊 Codex progress: ${currentProgress.status} — ${currentProgress.phase} (${currentProgress.current}/${currentProgress.total})`);
}

// ============================================================
// Main Pipeline (runs in background)
// ============================================================

export async function startCodexPipeline(options: { reExtractAll?: boolean } = {}): Promise<void> {
  if (currentProgress.status !== 'idle' && currentProgress.status !== 'complete' && currentProgress.status !== 'failed') {
    console.log(`  ⚠️ Codex pipeline already running (${currentProgress.status})`);
    return;
  }

  updateProgress({
    status: 'extracting', phase: 'Starting extraction...', current: 0, total: 0,
    extracted: 0, skipped: 0, failed: 0,
    startedAt: new Date().toISOString(), completedAt: null, error: null, synthesisTokens: null,
  });

  try {
    // STEP 1: Extract all swipes
    await runExtractionPhase(options.reExtractAll || false);

    // STEP 2: Compute stats codex
    updateProgress({ status: 'computing_stats', phase: 'Computing aggregate statistics...' });
    const { codexText: statsText, stats } = await computeCodex();
    await saveCodexAtom(statsText);
    invalidateCodexCache();
    console.log(`  📊 Stats codex computed: ${stats.totalProfiles} profiles`);

    // STEP 3: Opus synthesis (the big one)
    updateProgress({ status: 'synthesizing', phase: 'Running Opus synthesis across all profiles...' });
    await runOpusSynthesis(statsText);

    updateProgress({ status: 'complete', phase: 'Done', completedAt: new Date().toISOString() });
  } catch (err: any) {
    updateProgress({ status: 'failed', phase: 'Failed', error: err.message, completedAt: new Date().toISOString() });
    console.log(`  ❌ Codex pipeline failed: ${err.message}`);
  }
}

// ============================================================
// Phase 1: Batch Extraction (sequential with progress)
// ============================================================

async function runExtractionPhase(reExtractAll: boolean): Promise<void> {
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const swipes = allAtoms.filter(a =>
    a.metadata?.isSwipeFile &&
    a.body &&
    a.body.length > 50 &&
    (a.structured?.swipeAnalysis?.hookType || a.structured?.swipeAnalysis?.beatFingerprint)
  );

  updateProgress({ total: swipes.length, phase: `Extracting ${swipes.length} swipes...` });

  for (let i = 0; i < swipes.length; i++) {
    const atom = swipes[i];
    const hasProfile = !!atom.structured?.contentPhysics?.version;

    if (hasProfile && !reExtractAll) {
      updateProgress({ current: i + 1, skipped: currentProgress.skipped + 1 });
      continue;
    }

    updateProgress({ current: i + 1, phase: `[${i + 1}/${swipes.length}] ${atom.title?.substring(0, 40)}...` });

    const profile = await extractQuarkProfile(atom);
    if (profile) {
      const existing = atom.structured || {};
      await updateAtom(atom.uuid, { structured: { ...existing, contentPhysics: profile } });
      updateProgress({ extracted: currentProgress.extracted + 1 });
    } else {
      updateProgress({ failed: currentProgress.failed + 1 });
    }

    // Rate limit — 5s between calls for sustained batch
    if (i < swipes.length - 1) {
      await new Promise(r => setTimeout(r, 5000));
    }
  }
}

// ============================================================
// Phase 3: Opus Synthesis (ALL profiles → laws discovery)
// ============================================================

async function runOpusSynthesis(computedStats: string): Promise<void> {
  // Load ALL profiles
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const profiledSwipes = allAtoms.filter(a =>
    a.metadata?.isSwipeFile &&
    a.structured?.contentPhysics?.version
  );

  console.log(`  🔬 Opus synthesis: ${profiledSwipes.length} profiles loaded`);

  // Build the complete data section — ALL full profiles
  const profilesText = profiledSwipes.map((atom, i) => {
    const profile = atom.structured!.contentPhysics as QuarkProfile;
    const hookScore = atom.structured?.swipeAnalysis?.hookScore ?? 'N/A';
    const format = atom.structured?.swipeAnalysis?.swipeContentFormat || atom.metadata?.contentSource || 'unknown';

    return `
════════════════════════════════════════
POST ${i + 1}/${profiledSwipes.length}: "${atom.title}" (hookScore: ${hookScore}/10, format: ${format})
════════════════════════════════════════
${JSON.stringify(profile, null, 1)}
`;
  }).join('\n');

  const N = profiledSwipes.length;

  // The synthesis prompt (from CODEX_SYNTHESIS_PROMPT.md)
  const systemPrompt = `You are a theoretical physicist. Your domain is not particles or spacetime — it is human attention in sequential media. You have received the most comprehensive dataset ever assembled on viral content: complete quark profiles for ${N} posts, each analyzed through 10 passes covering individual slide quarks, transition mechanisms, arc shapes, reader state simulations, long-range bonds, rhythm waveforms, interference effects, deliberate absences, callback chains, entanglement pairs, resonance frequencies, antimatter patterns, and deep fabric syntheses.

Your task is to discover the LAWS OF CONTENT PHYSICS — the fundamental, universal, quantifiable principles that govern why sequential content goes viral.

You are not summarizing. You are not pattern-matching. You are doing SCIENCE. Every claim must be:
- GROUNDED: cite specific posts by title and slide numbers as evidence
- QUANTIFIED: express frequency, correlation, standard deviation — numbers, not adjectives
- FALSIFIABLE: state the condition under which the law would be violated
- PREDICTIVE: state what would happen to a new post that violates this law

Do NOT impose categories from this prompt or from the quark extraction framework. Let the data speak. If our framework is wrong, say so.

Your output is THE CONTENT PHYSICS CODEX — the definitive document that will be studied, refined, and used to generate viral content. Precision matters more than eloquence. Evidence matters more than confidence.`;

  const userPrompt = `═══════════════════════════════════════════════════════════════
THE COMPLETE EXPERIMENTAL DATASET — ${N} POSTS WITH FULL QUARK PROFILES
═══════════════════════════════════════════════════════════════

${profilesText}

═══════════════════════════════════════════════════════════════
COMPUTED STATISTICS (from code, verified)
═══════════════════════════════════════════════════════════════

${computedStats}

═══════════════════════════════════════════════════════════════
YOUR ANALYSIS: DISCOVER THE LAWS
═══════════════════════════════════════════════════════════════

Work through these 9 phases IN ORDER. Each builds on the last.

PHASE 1 — RAW OBSERVATION: Read every profile. Catalog everything that appears across multiple posts. What appears in 90%+ of posts? What appears in top-scoring (8+) but not lower? What appears in one format but not others? What never appears together? What always appears together? What surprised you?
Additionally examine: What experiential distance patterns appear (zero/near/far distributions)? Do top-scoring posts have different distance distributions than lower-scoring ones? What craft techniques appear most frequently? Are there techniques that ONLY appear in high-scoring posts? What dominant frames exist in the dataset? Do some frames correlate with higher scores than others?

PHASE 2 — QUANTIFICATION: For every pattern, attach numbers. Frequency (X/${N}). Average hook score with vs without. Format distribution. Position stats (mean, σ, range). Co-occurrence.

PHASE 3 — TAXONOMY DISCOVERY: What is the natural taxonomy? Does the data support our 3 forces, 8 quark families, 4 physics events? Or does it suggest something different? What is the MINIMAL set of categories needed?

PHASE 4 — HIERARCHY: Which patterns are FUNDAMENTAL (cannot be explained by others), DERIVED (consequences of fundamentals), or EMERGENT (only appear when multiple fundamentals combine)? Find the SMALLEST set of principles from which everything else derives.

PHASE 5 — FORMAL LAW STATEMENTS: For each law: precise statement, frequency, score impact, mechanism, 3-5 evidence citations with slide numbers, exceptions, predictions, connections to other laws. Confidence: CONFIRMED (90%+) / PROBABLE (70-90%) / SUGGESTED (50-70%) / HYPOTHETICAL.

PHASE 6 — INTERACTION MAP: Which laws amplify each other? Compensate? Conflict? Are prerequisites? Critical combinations that produce outsized results?

PHASE 7 — THE DEEP STRUCTURE: Is there a single principle that generates multiple laws? A master variable that predicts virality? Conservation laws? Phase boundaries? What is the E=mc² of content?

PHASE 8 — TEST THESE HYPOTHESES (from our manual analysis of 3 posts):
1. Proxy Character: viral content needs objection-processing mechanism
2. Trojan Horse: 2+ functional layers with mismatched apparent vs actual purpose
3. Format Is Narrative: most powerful moments change the FORMAT itself
4. Compression Acceleration: meaning-per-word ratio accelerates through the post
5. Specificity-Credibility Proportionality: trust ∝ verifiable detail specificity
6. Omission Principle: reader's imagined version > explicit version
7. CTA-Proof Inverse: optimal CTA weight = 1/proof weight
8. Double Helix Required: every transition needs narrative + psychological causality
9. Credibility Bank: trust deposits/withdrawals with overdraw = antimatter
10. Sacrifice Concreteness: visualizable sacrifice >> abstract sacrifice
11. Descending Aspiration: closing number should match reader's achievable identity
12. Participatory Validation: reader-verified claims > all other proof types
13. Meaning Sandwich: FEELING → SUBSTANCE → FEELING universal structure
14. V=A/D: Virality = Reader Agency / Engineering Detectability
15. Experiential Distance: Viral content is predominantly written at zero or near distance. Far distance correlates with lower engagement.
16. Technique Transfer: The specific craft techniques a blueprint uses must be replicated in the draft — correct quarks with wrong techniques produce flat content.
17. Dominant Frame Consistency: Every slide in a viral post conforms to the post's dominant frame. Frame violations (a "success" slide in a "museum of failures") break the post's identity.
For each: CONFIRMED / MODIFIED / DENIED / INSUFFICIENT DATA with evidence.

PHASE 9 — THE LEXICON: Complete vocabulary of content physics. Every term with: definition, category, measurement method, example (post title + slide). Usable by someone who has never read our framework. Include experiential distance (zero/near/far), technique inventory (craft moves catalog), and dominant frame (post-level identity) as lexicon entries with definitions, measurements, and examples from the dataset.

Structure your output as 10 parts:
I. OBSERVATION LOG
II. QUANTIFIED PATTERNS
III. TAXONOMY
IV. HIERARCHY
V. THE LAWS (complete catalog)
VI. INTERACTION MAP
VII. DEEP STRUCTURE
VIII. HYPOTHESIS TEST RESULTS
IX. THE LEXICON
X. OPEN QUESTIONS

This is the foundational text of a new field. Cite everything. Discover what's real.`;

  // Call Opus via OpenRouter
  const apiKey = config.openRouterApiKey || config.anthropicApiKey;
  if (!apiKey) {
    throw new Error('No API key for synthesis');
  }

  console.log(`  🔬 Calling Opus for synthesis (${N} profiles, estimated ~${(profilesText.length / 4).toFixed(0)} input tokens)...`);

  const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: 'anthropic/claude-opus-4-6',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: 65536, // Maximum output for the full codex
      temperature: 0.3,
    }),
    signal: AbortSignal.timeout(3600_000), // 1 hour timeout
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Opus synthesis failed (${response.status}): ${errText.substring(0, 300)}`);
  }

  const data = await response.json() as any;
  const synthesisText = data.choices?.[0]?.message?.content || '';

  if (!synthesisText || synthesisText.length < 1000) {
    throw new Error(`Opus synthesis produced insufficient output (${synthesisText.length} chars)`);
  }

  // Track tokens
  const usage = data.usage;
  if (usage) {
    const inputTokens = usage.prompt_tokens || 0;
    const outputTokens = usage.completion_tokens || 0;
    updateProgress({ synthesisTokens: { input: inputTokens, output: outputTokens } });
    console.log(`  🔬 Synthesis complete: ${inputTokens} input, ${outputTokens} output tokens`);
  }

  console.log(`  🔬 Synthesis output: ${synthesisText.length} chars`);

  // Save synthesis as a dedicated atom (separate from stats codex)
  const allAtomsForSave = await fetchAllByType('research', { limit: 500 });
  const existingSynthesis = allAtomsForSave.find(a => a.metadata?.isCodexSynthesis);

  if (existingSynthesis) {
    await updateAtom(existingSynthesis.uuid, {
      body: synthesisText,
      metadata: { ...existingSynthesis.metadata, updatedAt: new Date().toISOString(), profileCount: N },
    });
    console.log(`  📊 Updated synthesis atom: ${existingSynthesis.uuid}`);
  } else {
    await createAtom({
      type: 'research',
      title: 'Content Physics Codex — Opus Synthesis',
      body: synthesisText,
      metadata: {
        isCodexSynthesis: true,
        isSwipeFile: false,
        profileCount: N,
        createdAt: new Date().toISOString(),
      },
      structured: {},
    });
    console.log(`  📊 Created new synthesis atom`);
  }
}
