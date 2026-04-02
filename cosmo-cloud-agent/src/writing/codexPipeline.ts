// cosmo-cloud-agent/src/writing/codexPipeline.ts
// Full codex generation pipeline: background extraction → computed stats → Opus synthesis
// Runs independently of HTTP request lifecycle. Progress tracked in memory, pollable via API.

import { config } from '../config';
import { Atom, fetchAllByType, updateAtom, createAtom } from '../db/queries';
import { extractQuarkProfile } from './quarkExtractor';
import { computeCodex, saveCodexAtom, invalidateCodexCache } from './codex';
import { prepareExemplarData } from './exemplarCodex';
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

export async function startCodexPipeline(options: { reExtractAll?: boolean; skipExtraction?: boolean } = {}): Promise<void> {
  if (currentProgress.status !== 'idle' && currentProgress.status !== 'complete' && currentProgress.status !== 'failed') {
    console.log(`  ⚠️ Codex pipeline already running (${currentProgress.status})`);
    return;
  }

  updateProgress({
    status: 'extracting', phase: 'Starting...', current: 0, total: 0,
    extracted: 0, skipped: 0, failed: 0,
    startedAt: new Date().toISOString(), completedAt: null, error: null, synthesisTokens: null,
  });

  try {
    // STEP 1: Extract all swipes (skip if requested — use existing profiles)
    if (options.skipExtraction) {
      console.log(`  ⏭️ Skipping extraction — using existing profiles`);
    } else {
      await runExtractionPhase(options.reExtractAll || false);
    }

    // STEP 2: Compute stats codex (legacy, kept for backward compat)
    updateProgress({ status: 'computing_stats', phase: 'Computing aggregate statistics...' });
    const { codexText: statsText, stats } = await computeCodex();
    await saveCodexAtom(statsText);
    invalidateCodexCache();
    console.log(`  📊 Stats codex computed: ${stats.totalProfiles} profiles`);

    // STEP 2b: Prepare exemplar data (full slide text + grouped by concept type)
    updateProgress({ status: 'computing_stats', phase: 'Preparing exemplar data with full slide text...' });
    const { codexText: prepText } = await prepareExemplarData();
    console.log(`  📊 Exemplar prep data: ${prepText.length} chars (~${Math.round(prepText.length / 4)} tokens)`);

    // STEP 3: Opus Exemplar Synthesis (the big one — unified language + real examples)
    updateProgress({ status: 'synthesizing', phase: 'Running Opus Exemplar Synthesis across all profiles...' });
    await runExemplarSynthesis(prepText, statsText);

    updateProgress({ status: 'complete', phase: 'Done', completedAt: new Date().toISOString() });
  } catch (err: any) {
    updateProgress({ status: 'failed', phase: 'Failed', error: err.message, completedAt: new Date().toISOString() });
    console.log(`  ❌ Codex pipeline failed: ${err.message}`);
  }
}

// ============================================================
// Phase 1: Parallel Extraction (all non-extracted at once)
// ============================================================

async function runExtractionPhase(reExtractAll: boolean): Promise<void> {
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const swipes = allAtoms.filter(a =>
    a.metadata?.isSwipeFile &&
    a.body &&
    a.body.length > 50 &&
    (a.structured?.swipeAnalysis?.hookType || a.structured?.swipeAnalysis?.beatFingerprint)
  );

  // Split into already-extracted and needs-extraction
  const needsExtraction = swipes.filter(a => reExtractAll || !a.structured?.contentPhysics?.version);
  const alreadyDone = swipes.length - needsExtraction.length;

  updateProgress({
    total: swipes.length,
    skipped: alreadyDone,
    phase: `${needsExtraction.length} swipes need extraction (${alreadyDone} already done)...`,
  });

  if (needsExtraction.length === 0) {
    console.log(`  ✅ All ${swipes.length} swipes already extracted`);
    return;
  }

  const BATCH_SIZE = 10; // Railway drops connections when too many long-lived requests run concurrently
  const totalBatches = Math.ceil(needsExtraction.length / BATCH_SIZE);
  console.log(`  🚀 Extracting ${needsExtraction.length} swipes in ${totalBatches} batches of ${BATCH_SIZE}...`);

  for (let batchIdx = 0; batchIdx < totalBatches; batchIdx++) {
    const batch = needsExtraction.slice(batchIdx * BATCH_SIZE, (batchIdx + 1) * BATCH_SIZE);
    console.log(`  📦 Batch ${batchIdx + 1}/${totalBatches}: ${batch.length} swipes`);

    const results = await Promise.allSettled(
      batch.map(async (atom) => {
        try {
          const profile = await extractQuarkProfile(atom);
          if (profile) {
            const existing = atom.structured || {};
            await updateAtom(atom.uuid, { structured: { ...existing, contentPhysics: profile } });
            updateProgress({
              current: alreadyDone + currentProgress.extracted + currentProgress.failed + 1,
              extracted: currentProgress.extracted + 1,
              phase: `[${currentProgress.extracted + currentProgress.failed + 1}/${needsExtraction.length}] ✅ ${atom.title?.substring(0, 40)}`,
            });
            return { uuid: atom.uuid, success: true };
          } else {
            updateProgress({
              current: alreadyDone + currentProgress.extracted + currentProgress.failed + 1,
              failed: currentProgress.failed + 1,
            });
            return { uuid: atom.uuid, success: false, error: 'No profile returned' };
          }
        } catch (err: any) {
          updateProgress({
            current: alreadyDone + currentProgress.extracted + currentProgress.failed + 1,
            failed: currentProgress.failed + 1,
          });
          console.log(`  ❌ Extraction failed for "${atom.title?.substring(0, 40)}": ${err.message}`);
          return { uuid: atom.uuid, success: false, error: err.message };
        }
      })
    );

    const batchSucceeded = results.filter(r => r.status === 'fulfilled' && (r as any).value?.success).length;
    const batchFailed = results.filter(r => r.status === 'rejected' || (r.status === 'fulfilled' && !(r as any).value?.success)).length;
    console.log(`  📦 Batch ${batchIdx + 1} done: ${batchSucceeded} succeeded, ${batchFailed} failed`);

    // Wait 30s between batches to let TPM rate limit reset
    if (batchIdx < totalBatches - 1) {
      console.log(`  ⏳ Waiting 30s before next batch (TPM cooldown)...`);
      await new Promise(r => setTimeout(r, 30_000));
    }
  }

  console.log(`  📊 Extraction complete: ${currentProgress.extracted} succeeded, ${currentProgress.failed} failed, ${alreadyDone} were already done`);
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

// ============================================================
// Phase 3b: Exemplar Synthesis (pre-processed data → unified Codex)
// ============================================================

async function runExemplarSynthesis(preparedData: string, computedStats: string): Promise<void> {
  const apiKey = config.openRouterApiKey || config.anthropicApiKey;
  if (!apiKey) {
    throw new Error('No API key for Exemplar synthesis');
  }

  // Count approximate profile count from prep data header
  const profileCountMatch = preparedData.match(/(\d+) analyzed viral posts/);
  const N = profileCountMatch ? parseInt(profileCountMatch[1]) : 0;

  console.log(`  🔬 Exemplar synthesis: sending ${preparedData.length} chars of prep data (~${Math.round(preparedData.length / 4)} tokens)`);

  const systemPrompt = `You are creating THE EXEMPLAR CODEX — the complete, unified language of Content Physics derived from ${N} viral posts. This is the definitive document a writing AI will use to understand and replicate every dimension of viral content.

You have two inputs:
1. PRE-PROCESSED DATA: Every viral post individually — full slide-by-slide text + complete Content Physics quark profile (10-pass analysis including per-slide quarks, transitions, arc, RSV trajectory, physics events, long-range interactions, rhythm, reader simulation, antimatter, and deep fabric). PLUS aggregated voice DNA metrics and all slide-to-slide bridge text across all posts. NOTE: Each post was analyzed independently by a different Sonnet call, so naming may be inconsistent across posts (e.g., "confession" in one post vs "vulnerable-admission" in another for the same concept). YOUR JOB is to read ALL posts, unify the taxonomy into one consistent language, and discover the patterns.

2. COMPUTED STATISTICS: Frequency distributions and format-specific patterns.

CRITICAL RULES:
- Every example MUST be a REAL slide or sentence copied EXACTLY from one of the posts in the data. Quote the actual text as it appears. Do NOT rewrite, paraphrase, summarize, or invent examples. If you can't find a real example, say so — never fabricate one.
- Include 15-20 real examples per concept when available. Fall back to 10 if there aren't enough distinct examples. More examples = the writing model learns better.
- Every claim, pattern, law, or principle MUST be backed by multiple real examples from specific posts (cite post title + slide number). Never state a pattern without showing the actual text that proves it.
- When two independent extractions use different names for the same concept (e.g., "confession" vs "vulnerable-admission"), MERGE them under one unified name and combine their examples.
- When a concept has sub-types, organize them hierarchically under the parent.
- If the data reveals concepts NOT in our framework, NAME THEM and add them with examples.
- All swipes are curated high-quality viral content — present for variety, not ranked by score.
- The output is the COMPLETE LANGUAGE. A writing AI reading ONLY this codex must understand every dimension of viral content and be able to replicate it using real sentence structures from these examples.

FORMAT-SPECIFIC PHYSICS:
The data contains both REELS (≤2 sentences/slide, shorter text per slide, more slides) and CAROUSELS (≥3 sentences/slide, denser text per slide, fewer slides). Both are text-based — reels are text overlays on images/video, not voiceover. Each example is tagged [REEL] or [CAROUSEL]. Format is classified by content density, NOT metadata (metadata is often wrong).

For EVERY concept, structure examples in THREE layers:
1. UNIVERSAL: The principle that holds across BOTH formats.
2. REEL EXAMPLES: How this concept manifests in reels (1-2 sentences per slide, punchier, more compressed).
3. CAROUSEL EXAMPLES: How this concept manifests in carousels (3-5 sentences per slide, more detail, fuller explanations).

Key format differences to identify:
- Reel slides: 1-2 sentences, ~10-25 words. Carousel slides: 3-5 sentences, ~30-60 words.
- Reel transitions must work with less text — connectors are tighter, sometimes just one word.
- Carousel transitions can use fuller bridge phrases and forward pulls.
- Reel hooks are ultra-compressed (one punchy sentence). Carousel hooks can be 2-3 sentences.
- The underlying forces (State Change, Causality, Earned-ness) and RSV are UNIVERSAL across both.
- Identify which physics concepts are truly universal and which are format-specific.`;

  const userPrompt = `═══════════════════════════════════════════════════════════════
PRE-PROCESSED EXEMPLAR DATA (every post individually + aggregated voice/bridge data)
═══════════════════════════════════════════════════════════════

${preparedData}

═══════════════════════════════════════════════════════════════
COMPUTED STATISTICS
═══════════════════════════════════════════════════════════════

${computedStats}

═══════════════════════════════════════════════════════════════
YOUR TASK: CREATE THE EXEMPLAR CODEX
═══════════════════════════════════════════════════════════════

For EVERY physics concept you identify across ALL categories (speech acts, transitions, reader deltas, proof types, motivations, compressions, per-slide frames, experiential distances, techniques, dominant frames, arc shapes, physics events, long-range interactions, rhythm patterns, antimatter, resonance frequencies, and any NEW concepts the data reveals):

═══ {UNIFIED CONCEPT NAME} ({Category: e.g., Speech Act / Transition / Reader Delta}) ═══

DEFINITION: One precise paragraph defining what this IS mechanically — what happens in the actual text, what it produces in the reader, and WHY it works psychologically.

FREQUENCY: How many of the {N} posts use this concept, at what positions in the post.

REAL EXAMPLES (15-20 from the posts, chosen for VARIETY — different creators, different niches, different approaches to the same concept. Fall back to 10 if fewer exist):

1. "{exact slide text copied from the post data — do NOT rewrite}"
   — [{post title}] Slide {N}
   Why it works: {what specific sentence structure, word choices, and rhythm make this effective}
   Reader effect: {what changes in the reader's mind and why}
   How to apply: {how a writer would use this same structure with different content}

2. ...

PATTERNS (what the examples share — cite specific examples by number to prove each pattern):
- {pattern}: seen in examples #X, #Y, #Z. Specifically: {exact textual evidence}.

ANTI-PATTERNS (what would destroy this concept — with specific BAD wording so the writer knows what to avoid):
- {anti-pattern}: "{example of bad wording}" — fails because {reason}.

For TRANSITIONS: each example MUST include BOTH slides (from → to) with the actual connector text between them.
For LONG-RANGE INTERACTIONS: include both the setup and payoff slide text with the distance between them.
For ARC SHAPES: include a full post summary of the best example showing every slide's role.
For TECHNIQUES: show the actual text that demonstrates the technique, and explain what quark it produces.

AFTER all concept entries, add these sections:

═══ LAWS OF CONTENT PHYSICS ═══
Formal law statements derived from the data. For each law:
- Precise statement of the law
- Real evidence: quote 10-15 specific slides from specific posts that PROVE this law
- Violation evidence: if any post breaks this law, quote the specific slide and explain what happens
- Application: how a writer applies this law when creating new content

═══ INTERACTIONS ═══
Which concepts amplify each other, compensate, conflict, or are prerequisites.
For each interaction: cite 2-3 specific posts where you can SEE the interaction happening.
Quote the actual slide text that demonstrates the interaction.

═══ DEEP STRUCTURE ═══
The minimal set of principles from which everything derives. The E=mc² of content.
Back every principle with real examples from multiple posts.

═══ HYPOTHESIS TEST RESULTS ═══
Test these 17 hypotheses against ALL the data:
1. Proxy Character: viral content needs objection-processing mechanism
2. Trojan Horse: 2+ functional layers with different surface vs actual purpose
3. Format Is Narrative: powerful moments change the FORMAT itself
4. Compression Acceleration: meaning-per-word increases through the post
5. Specificity-Credibility Proportionality: trust proportional to verifiable detail
6. Omission Principle: imagined content > explicit content
7. CTA-Proof Inverse: CTA weight inversely proportional to proof weight
8. Double Helix Required: every transition needs narrative + psychological causality
9. Credibility Bank: trust deposits/withdrawals per slide
10. Sacrifice Concreteness: visualizable sacrifice >> abstract sacrifice
11. Descending Aspiration: closing aspiration matches reader's achievable identity
12. Participatory Validation: reader-verified claims > all other proof
13. Meaning Sandwich: FEELING → SUBSTANCE → FEELING
14. V=A/D: Virality = Agency / Detectability
15. Experiential Distance: viral content is predominantly zero or near distance
16. Technique Transfer: correct quarks with wrong techniques produce flat content
17. Dominant Frame Consistency: every slide conforms to the post's dominant frame

For each: CONFIRMED / MODIFIED / DENIED.
Back every verdict with 3+ real slide quotes from specific posts. Never just claim — always show the text that proves it.

═══ CONVERSATIONAL DNA ═══
Based on the voice DNA metrics and the actual posts:
- What sentence structures make viral content sound like SPEECH, not writing?
- What connector patterns chain sentences within slides? Quote real examples.
- What bridge patterns chain slides together? Quote real bridge text.
- What makes content sound conversational vs formal? Cite specific posts that do it best and explain exactly what they do differently at the sentence level.
- What rhythm patterns (sentence length variation, word count per slide) correlate with viral posts?

This section should give a writer everything they need to NEVER sound like AI — backed entirely by real examples.

This is the foundational text of Content Physics. Every claim backed by real text. Every pattern proven with examples. Discover what's real.`;

  const estimatedInput = Math.round((preparedData.length + computedStats.length + systemPrompt.length + userPrompt.length) / 4);
  console.log(`  🔬 Calling Opus for Exemplar synthesis (~${estimatedInput} input tokens, direct Anthropic streaming, 128K max output)...`);

  const synthesisApiKey = config.anthropicApiKey || apiKey;
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': synthesisApiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-opus-4-6',
      system: [{ type: 'text', text: systemPrompt }],
      messages: [{ role: 'user', content: userPrompt }],
      max_tokens: 128000,
      temperature: 0.3,
      stream: true,
    }),
    signal: AbortSignal.timeout(7200_000), // 2 hour timeout for safety
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Exemplar synthesis failed (${response.status}): ${errText.substring(0, 300)}`);
  }

  // Stream the response — keeps connection alive, shows progress
  const reader = response.body?.getReader();
  if (!reader) throw new Error('No response body reader for Opus synthesis');

  const decoder = new TextDecoder();
  let synthesisText = '';
  let inputTokens = 0;
  let outputTokens = 0;
  let lastLog = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunk = decoder.decode(value, { stream: true });
    for (const line of chunk.split('\n')) {
      if (!line.startsWith('data: ')) continue;
      const eventData = line.slice(6);
      if (eventData === '[DONE]') continue;
      try {
        const event = JSON.parse(eventData);
        if (event.type === 'content_block_delta' && event.delta?.text) {
          synthesisText += event.delta.text;
        }
        if (event.type === 'message_delta' && event.usage) {
          outputTokens = event.usage.output_tokens || 0;
        }
        if (event.type === 'message_start' && event.message?.usage) {
          inputTokens = event.message.usage.input_tokens || 0;
        }
      } catch {}
    }

    // Progress log every 30s
    if (Date.now() - lastLog > 30_000) {
      const tokens = Math.round(synthesisText.length / 4);
      console.log(`  🔬 Opus streaming: ${synthesisText.length} chars (~${tokens} tokens)...`);
      updateProgress({ phase: `Opus synthesis: ~${tokens} output tokens so far...` });
      lastLog = Date.now();
    }
  }

  console.log(`  🔬 Exemplar synthesis complete: ${inputTokens} input, ${outputTokens} output tokens`);
  console.log(`  🔬 Exemplar Codex output: ${synthesisText.length} chars (~${Math.round(synthesisText.length / 4)} tokens)`);
  updateProgress({ synthesisTokens: { input: inputTokens, output: outputTokens } });

  if (!synthesisText || synthesisText.length < 2000) {
    throw new Error(`Exemplar synthesis produced insufficient output (${synthesisText.length} chars)`);
  }

  // Save as the codex synthesis atom (overwrites previous synthesis)
  const allAtomsForSave = await fetchAllByType('research', { limit: 500 });
  const existingSynthesis = allAtomsForSave.find(a => a.metadata?.isCodexSynthesis);

  if (existingSynthesis) {
    await updateAtom(existingSynthesis.uuid, {
      body: synthesisText,
      metadata: {
        ...existingSynthesis.metadata,
        updatedAt: new Date().toISOString(),
        profileCount: N,
        isExemplarCodex: true,
      },
    });
    console.log(`  📊 Updated Exemplar Codex atom: ${existingSynthesis.uuid}`);
  } else {
    await createAtom({
      type: 'research',
      title: 'Content Physics Exemplar Codex',
      body: synthesisText,
      metadata: {
        isCodexSynthesis: true,
        isExemplarCodex: true,
        isSwipeFile: false,
        profileCount: N,
        createdAt: new Date().toISOString(),
      },
      structured: {},
    });
    console.log(`  📊 Created new Exemplar Codex atom`);
  }
}
