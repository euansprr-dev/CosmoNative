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

// ============================================================
// Codex Cleanup — strip model thinking, task headers, reorganize
// ============================================================

export function cleanupCodexText(raw: string): string {
  let text = raw;

  // 1. Strip opening meta paragraph (everything before the first section header)
  const firstSectionMatch = text.match(/^[\s\S]*?((?:#+\s*|═══\s*)(?:PERIODIC TABLE|FORCES|SPEECH ACTS|TRANSITIONS|READER DELTAS))/m);
  if (firstSectionMatch) {
    const idx = text.indexOf(firstSectionMatch[1]);
    if (idx > 0 && idx < 2000) {
      text = text.substring(idx);
    }
  }

  // 2. Strip TASK prefixes from headers
  text = text.replace(/# TASK \d+[A-Za-z]?\s*—\s*/g, '# ');
  text = text.replace(/TASK \d+[A-Za-z]?\s*—\s*/g, '');

  // 3. Remove "TASK 2A — COMPLETION CHECK" section entirely (model thinking)
  text = text.replace(/#{1,3}\s*COMPLETION CHECK AGAINST EXISTING CODEX[\s\S]*?(?=(?:#{1,3}\s+|═══\s+)(?!COMPLETION))/gi, '');

  // 4. Remove "COMPLETION NOTE" section
  text = text.replace(/═══\s*COMPLETION NOTE\s*═══[\s\S]*?(?=═══|$)/gi, '');

  // 5. Remove "MANDATORY COMPLETION CHECKLIST" section
  text = text.replace(/═══\s*MANDATORY COMPLETION CHECKLIST\s*═══[\s\S]*?(?=═══|$)/gi, '');

  // 6. Remove meta conclusion paragraph
  text = text.replace(/This prepend gives the writing model[\s\S]*?(?=═══)/gi, '');

  // 7. Remove "DETAILED REFERENCE" header (just the header line, keep content)
  text = text.replace(/═══\s*DETAILED REFERENCE \(Pass 1 \+ Pass 2 Entries\)\s*═══\s*\n*/gi, '');

  // 8. Remove duplicate/multiple "PASS 2: DEEPENED CONCEPT ENTRIES" headers
  //    Keep the first occurrence's content, strip duplicate header lines
  let pass2Count = 0;
  text = text.replace(/[\\n\n]*═══\s*PASS 2: DEEPENED CONCEPT ENTRIES\s*═══[\\n\n]*/gi, (match) => {
    pass2Count++;
    return pass2Count === 1 ? '\n\n' : '\n\n';
  });

  // 9. Remove raw inventory data (SPEECH ACTS FOUND: ..., TRANSITIONS FOUND: ..., etc.)
  //    These are massive blocks of post-number lists that are superseded by the Periodic Table
  const inventoryPatterns = [
    'SPEECH ACTS FOUND:',
    'TRANSITIONS FOUND:',
    'READER DELTAS FOUND:',
    'PROOF TYPES FOUND:',
    'MOTIVATIONS FOUND:',
    'COMPRESSIONS FOUND:',
    'FRAMES FOUND:',
    'DISTANCES FOUND:',
    'TECHNIQUES FOUND:',
    'DOMINANT FRAMES FOUND:',
    'ARC SHAPES FOUND:',
    'TRANSITIONS DOUBLE-HELIX:',
    'LONG-RANGE TYPES FOUND:',
    'ANTIMATTER CATALOG:',
    'NOVEL PATTERNS:',
  ];
  for (const pattern of inventoryPatterns) {
    // Each inventory item is one giant paragraph — remove from pattern start to the next double newline or section header
    const escPattern = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    text = text.replace(new RegExp(escPattern + '[\\s\\S]*?(?=\\n\\n═══|\\n\\n#{1,3}\\s|$)', 'gi'), '');
  }

  // 10. Remove escaped literal newlines that got into the DB from code bugs
  text = text.replace(/\\n/g, '\n');

  // 11. Clean up excessive whitespace
  text = text.replace(/\n{4,}/g, '\n\n\n');

  // 12. Now reorganize: extract sections and reorder
  //     The goal: Periodic Table → Variant Mapping → Deep Entries → Laws → Interactions → Deep Structure → Hypotheses → DNA → Walkthroughs
  //     For now, just ensure Variant Mapping follows the Periodic Table

  // Find where variant mapping starts and ends
  const variantStart = text.search(/#{1,3}\s*VARIANT MAPPING|═══.*VARIANT MAPPING/i);
  if (variantStart > -1) {
    // Find where it ends (next major non-mapping section)
    const afterVariant = text.substring(variantStart);
    const variantEndMatch = afterVariant.match(/\n(═══\s*(?!.*MAPPING)(?:FALSE FLOOR|DIALOGUE|SPECIFICITY|OMITTED|UNIVERSAL|STATE CHANGE|CONTRAST|VALIDATION|PARTICIPATORY|PHASE TRANSITION|ANTI-GLAMOUR|EAVESDROPPING|HOOK|CLAIM|OBSERVATION|INSTRUCTION|REVEAL|PROOF|PERMISSION|WARNING|INVITATION|GRATITUDE|THESIS|LAW|INTERACTION|DEEP STRUCTURE|HYPOTHESIS|CONVERSATIONAL|WALKTHROUGH|CURATION|FEAR|RELIEF|MOTIVATION|READER DELTA|PROOF TYPE|TECHNIQUE|COMPRESSION|FRAME|DISTANCE|ARC SHAPE|ANSWER|ACCUMULATION|PARTIAL|CAUSE))/i);

    if (variantEndMatch) {
      const variantEndIdx = variantStart + afterVariant.indexOf(variantEndMatch[0]);
      const variantBlock = text.substring(variantStart, variantEndIdx);

      // Remove it from current position
      text = text.substring(0, variantStart) + text.substring(variantEndIdx);

      // Find end of Periodic Table (the ANTIMATTER section is the last table category)
      const antimatterEnd = text.search(/\n\n(?=═══\s*(?:FALSE FLOOR|DIALOGUE|SPECIFICITY|OMITTED|UNIVERSAL|STATE CHANGE|CONTRAST|VALIDATION|PARTICIPATORY|PHASE TRANSITION|ANTI-GLAMOUR|EAVESDROPPING|HOOK|CLAIM|OBSERVATION|INSTRUCTION))/i);

      if (antimatterEnd > -1) {
        // Insert variant mapping right after the Periodic Table
        text = text.substring(0, antimatterEnd) + '\n\n\n# VARIANT MAPPING\n\n' + variantBlock.replace(/^#{1,3}\s*VARIANT MAPPING\s*\n*/i, '') + '\n\n' + text.substring(antimatterEnd);
      }
    }
  }

  // 13. Strip "Fill remaining gaps" meta-commentary paragraphs
  text = text.replace(/Below are \*\*new full entries\*\* only for concepts[\s\S]*?I'll fill the highest-frequency missing ones first\.\s*---/gi, '');
  text = text.replace(/The biggest remaining workhorse gaps from the current Codex are:[\s\S]*?---/gi, '');

  // 14. Cut everything after MANDATORY COMPLETION CHECKLIST
  //     All Pass 2 appends below this point used a bugged SSE parser and are garbled.
  //     They'll be regenerated cleanly by the new Pass 2 code.
  const checklistIdx = text.indexOf('MANDATORY COMPLETION CHECKLIST');
  if (checklistIdx > -1) {
    // Find the start of that section (the ═══ before it)
    const beforeChecklist = text.lastIndexOf('═══', checklistIdx);
    if (beforeChecklist > -1) {
      const removed = text.length - beforeChecklist;
      text = text.substring(0, beforeChecklist).trimEnd();
      console.log(`  🧹 Cut ${removed} chars of garbled Pass 2 content (after MANDATORY COMPLETION CHECKLIST)`);
    }
  }

  // Also cut any "PASS 2: DEEPENED CONCEPT ENTRIES" sections that survived
  const pass2Idx = text.indexOf('PASS 2: DEEPENED CONCEPT ENTRIES');
  if (pass2Idx > -1) {
    const beforePass2 = text.lastIndexOf('═══', pass2Idx);
    if (beforePass2 > -1) {
      const removed = text.length - beforePass2;
      text = text.substring(0, beforePass2).trimEnd();
      console.log(`  🧹 Cut ${removed} chars of remaining Pass 2 content`);
    }
  }

  // 15. Final whitespace cleanup
  text = text.replace(/\n{4,}/g, '\n\n\n');
  text = text.trim();

  return text;
}

export async function startCodexPipeline(options: { reExtractAll?: boolean; skipExtraction?: boolean; pass2Only?: boolean; pass3Only?: boolean; cleanupOnly?: boolean; rewriteWalkthroughs?: boolean } = {}): Promise<void> {
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
    // CLEANUP-ONLY mode: just clean the existing Codex and save
    if (options.cleanupOnly) {
      updateProgress({ status: 'computing_stats', phase: 'Cleaning up Codex structure...' });
      const allAtoms = await fetchAllByType('research', { limit: 500 });
      const existingCodex = allAtoms.find(a => a.metadata?.isCodexSynthesis);
      if (!existingCodex?.body || existingCodex.body.length < 1000) {
        throw new Error('No existing Codex found for cleanup.');
      }

      const before = existingCodex.body.length;
      const cleaned = cleanupCodexText(existingCodex.body);
      const after = cleaned.length;

      await updateAtom(existingCodex.uuid, {
        body: cleaned,
        metadata: { ...existingCodex.metadata, updatedAt: new Date().toISOString(), cleanedUp: true },
      });

      console.log(`  🧹 Codex cleaned: ${before} → ${after} chars (removed ${before - after} chars of thinking/meta)`);
      updateProgress({ status: 'complete', phase: `Cleanup done: ${before} → ${after} chars`, completedAt: new Date().toISOString() });
      return;
    }

    // REWRITE WALKTHROUGHS mode: replace thin walkthroughs with full slide-text + unified language
    if (options.rewriteWalkthroughs) {
      updateProgress({ status: 'computing_stats', phase: 'Preparing data for walkthrough rewrite...' });
      const { codexText: prepText } = await prepareExemplarData();
      const allAtomsForWT = await fetchAllByType('research', { limit: 500 });
      const existingCodex = allAtomsForWT.find(a => a.metadata?.isCodexSynthesis);
      if (!existingCodex?.body || existingCodex.body.length < 1000) {
        throw new Error('No existing Codex found for walkthrough rewrite.');
      }
      console.log(`  📊 Rewriting walkthroughs with ${existingCodex.body.length} char Codex + raw data`);
      updateProgress({ status: 'synthesizing', phase: 'Rewriting walkthroughs with unified language + full slide text...' });
      await runWalkthroughRewrite(prepText, existingCodex.body);
      updateProgress({ status: 'complete', phase: 'Walkthroughs rewritten', completedAt: new Date().toISOString() });
      return;
    }

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

    if (options.pass3Only) {
      // Skip Pass 1+2 — load existing Codex and run unification
      const allAtomsForPass3 = await fetchAllByType('research', { limit: 500 });
      const existingCodex = allAtomsForPass3.find(a => a.metadata?.isCodexSynthesis);
      if (!existingCodex?.body || existingCodex.body.length < 1000) {
        throw new Error('No existing Codex found for Pass 3. Run full pipeline first.');
      }
      console.log(`  ⏭️ Skipping Pass 1+2 — using existing Codex (${existingCodex.body.length} chars)`);
      updateProgress({ status: 'synthesizing', phase: 'Pass 3: Unifying language + filling gaps...' });
      await runCodexUnification(prepText, existingCodex.body);
    } else if (options.pass2Only) {
      // Skip Pass 1 — load existing Codex and go straight to deepening
      const allAtomsForPass2 = await fetchAllByType('research', { limit: 500 });
      const existingCodex = allAtomsForPass2.find(a => a.metadata?.isCodexSynthesis);
      if (!existingCodex?.body || existingCodex.body.length < 1000) {
        throw new Error('No existing Codex found for Pass 2. Run full pipeline first.');
      }
      // Clean up the Codex before sending to GPT — strip task headers, thinking, reorganize
      const cleanedCodex = cleanupCodexText(existingCodex.body);
      console.log(`  🧹 Cleaned Codex: ${existingCodex.body.length} → ${cleanedCodex.length} chars`);
      console.log(`  ⏭️ Skipping Pass 1 — using cleaned Codex (${cleanedCodex.length} chars)`);
      updateProgress({ status: 'synthesizing', phase: 'Pass 2: Deepening existing Codex with real examples...' });
      await runCodexDeepening(prepText, cleanedCodex);
    } else {
      // STEP 3: Pass 1 — Foundation (inventory + first batch of deep concept entries)
      updateProgress({ status: 'synthesizing', phase: 'Pass 1: Building Codex foundation...' });
      const pass1Text = await runExemplarSynthesis(prepText, statsText);

      // STEP 4: Pass 2 — Deepening (fill in every concept the first pass missed)
      updateProgress({ status: 'synthesizing', phase: 'Pass 2: Deepening — filling gaps with real examples...' });
      await runCodexDeepening(prepText, pass1Text);
    }

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

async function runExemplarSynthesis(preparedData: string, computedStats: string): Promise<string> {
  const apiKey = config.openRouterApiKey || config.anthropicApiKey;
  if (!apiKey) {
    throw new Error('No API key for Exemplar synthesis');
  }

  // Count approximate profile count from prep data header
  const profileCountMatch = preparedData.match(/(\d+) analyzed viral posts/);
  const N = profileCountMatch ? parseInt(profileCountMatch[1]) : 0;

  console.log(`  🔬 Exemplar synthesis: sending ${preparedData.length} chars of prep data (~${Math.round(preparedData.length / 4)} tokens)`);

  const systemPrompt = `You are a structured data extraction system producing THE EXEMPLAR CODEX — a comprehensive knowledge base that will be PROGRAMMATICALLY PARSED. Your output feeds directly into a content generation engine. If ANY concept category from the mandatory checklist is missing, the parser rejects the entire output and the computation is wasted.

CRITICAL BEHAVIORAL INSTRUCTIONS:
- Your output budget is 128,000 tokens. Previous runs produced only 12,000 tokens (10% of budget) covering 3 concepts. This was a FAILURE — the parser rejected it. You MUST use at least 80,000 tokens and cover ALL concepts.
- Do NOT write literary prose. Do NOT write introductions, conclusions, transitions between sections, or meta-commentary like "due to length constraints" or "I will prioritize." There are NO length constraints.
- Do NOT self-edit for conciseness. LONGER IS BETTER. More examples per concept = higher quality downstream.
- After Step 1 (inventory), enter a MECHANICAL LOOP: pick next uncovered concept → write its full entry with 15-20 examples → pick next concept → repeat. Do NOT pause to reflect between concepts. Do NOT stop until the checklist is complete.
- When you feel "done," CHECK: have you covered every checkbox? If ANY checkbox is uncovered, you are NOT done. Continue.

THE EXEMPLAR CODEX defines Content Physics — the fundamental forces governing human attention in sequential media. This is the first complete formalization of a field that has never been formally defined. Every viral post obeys these laws. You are documenting them with the precision of Newton's Principia, grounded entirely in real examples from ${N} viral posts.

A concept with 5 examples teaches recognition. A concept with 15-20 examples teaches REPLICATION — the writer sees enough variety to abstract the pattern and execute it with any content. ALWAYS 15-20 examples. NEVER stop at 5.

You have two inputs:
1. PRE-PROCESSED DATA: Every viral post individually — full slide-by-slide text + complete Content Physics quark profile (10-pass analysis including per-slide quarks, transitions, arc, RSV trajectory, physics events, long-range interactions, rhythm, reader simulation, antimatter, and deep fabric). PLUS aggregated voice DNA metrics and all slide-to-slide bridge text across all posts. NOTE: Each post was analyzed independently by a different Sonnet call, so naming may be inconsistent across posts (e.g., "confession" in one post vs "vulnerable-admission" in another for the same concept). YOUR JOB is to read ALL posts, unify the taxonomy into one consistent language, and discover the patterns.

2. COMPUTED STATISTICS: Frequency distributions and format-specific patterns.

ABSOLUTE RULES:
1. Every example is a REAL slide or sentence copied EXACTLY from the data. Never rewrite, paraphrase, or invent. Quote it as-is.
2. 15-20 real examples per concept. Show how DIFFERENT creators in DIFFERENT niches execute the same concept differently. Fall back to 10 ONLY if fewer exist. NEVER give just 3-5 when more exist.
3. Every example MUST include the FULL QUOTED SLIDE TEXT — not just a reference like "Post 103, Slide 14." The writing model reading this Codex will NOT have access to the original posts. Every example must be SELF-CONTAINED: the complete quoted text + enough context that a writer who has never seen the original post understands what's happening and why it works.
4. Every claim, pattern, and law backed by multiple quoted examples with post title + slide number.
4. Merge concepts that are the same thing with different names across extractions. Add new concepts the data reveals.
5. For each example, explain: (a) why THIS specific text creates this effect, (b) what sentence structure/word choices make it work, (c) how a writer would replicate this pattern with different content.
6. For COMPOUND PATTERNS — when two or more concepts appear together and produce an effect greater than either alone — document these as their own entries. Show the real examples where the compound occurs.
7. Do NOT conclude early. Check: have you covered every concept from the mandatory checklist? Have you given 15+ examples for each? If not, keep going. If you've written less than 80,000 tokens, you are not done.
8. After individual concepts, include 10 FULL POST WALKTHROUGHS — analyze each slide-by-slide showing how ALL concepts compose. This teaches COMBINATION. Remember: your Step 1 inventory was built by examining EVERY post's profile — the walkthroughs make that analysis visible for the 10 most instructive examples.

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

CRITICAL: Do NOT begin writing the codex until you have read ALL ${N} posts.

STEP 1 — RAW INVENTORY (output this FIRST, before any prose):
Read every single post. For each concept category below, build a raw frequency table listing every unique type found across ALL ${N} posts, with the post numbers that contain each type. This forces you to scan the complete dataset before writing.

Output format for Step 1:
SPEECH ACTS FOUND: confession(posts 1,3,7,14,22,...), update(posts 2,5,8,...), reveal(posts ...), [every type]
TRANSITIONS FOUND: escalation(posts ...), deflation(posts ...), [every type]
READER DELTAS FOUND: curiosity+(posts ...), trust+(posts ...), [every type]
PROOF TYPES FOUND: [every type with post numbers]
MOTIVATIONS FOUND: [every type with post numbers]
COMPRESSIONS FOUND: [every type with post numbers]
FRAMES FOUND: [every type with post numbers]
DISTANCES FOUND: zero(posts ...), near(posts ...), far(posts ...)
TECHNIQUES FOUND: [every type with post numbers]
DOMINANT FRAMES FOUND: [every type with post numbers]
ARC SHAPES FOUND: [every shape with post numbers]
TRANSITIONS DOUBLE-HELIX: [which transitions are DH, which aren't]
LONG-RANGE TYPES FOUND: [bonds, echoes, absences, entanglement — with post numbers]
ANTIMATTER CATALOG: [every destructive phrase found, with frequency]
NOVEL PATTERNS: [anything not in the standard framework]

STEP 2 — THE EXEMPLAR CODEX (write this AFTER the inventory):
Now that you have cataloged everything across all ${N} posts, write the full codex.
Go through your inventory SYSTEMATICALLY — do not skip any concept type.
For EVERY concept type from your inventory above (even if it only appears in 3-5 posts):

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

═══ MANDATORY COMPLETION CHECKLIST ═══

DO NOT STOP until you have covered EVERY category below. This is not optional.
Check off each one as you complete it. Your output should be 80,000-128,000 tokens.
If you find yourself concluding early, you are not done.

MICRO-SCALE QUARKS (cover EVERY type found in the data):
□ ALL Speech Act types (confession, update, vow, doubt, reveal, gratitude, boast, defiance, lament, AND any others found)
□ ALL Reader Delta types (curiosity+, curiosity-, tension+, tension-, trust+, identification+, surprise, empathy+, fear+, desire+, AND any others)
□ ALL Proof types (metric, sacrifice, timeline, sensory, named-entity, contradiction, emotional)
□ ALL Motivation types (escape, identity, money/freedom, love/legacy, defiance)
□ ALL Compression types (earned-skip, intriguing-skip, confusing-skip, time-jump, summary)
□ ALL Per-slide Frame types (loss, decision, consequence, success, observation, setup, absurd, compression-punch, transformation)
□ ALL Experiential Distance levels (zero, near, far) — with 15+ examples EACH
□ ALL Technique types (ALL CAPS, ellipsis, subject-drop, casual spelling, present-tense shift, POV framing, direct address, number formatting, maximum compression, parenthetical aside, repetition device, contrast structure, AND any others)
□ ALL Resonance Frequency patterns found

MESO-SCALE:
□ ALL Transition types (reason→action, action→result, result→discomfort, discomfort→decision, decision→risk, risk→loss, loss→adaptation, adaptation→payoff, doubt→reaffirmation, deflation, escalation, gratitude→closure, contrast, personal→universal, AND any others)
□ ALL Relational quark types (foregrounded, implied, payoff-only, relational-proof, listener-as-witness)

MACRO-SCALE:
□ ALL Arc Shape patterns found in the data (with full post summaries for each)
□ ALL Dominant Frame types (museum_of_failures, chronological_journey, dialogue, tutorial, letter_to_someone, testimony, listicle, AND any others)

PHYSICS EVENTS:
□ Symmetry Break — with 15+ real examples
□ Phase Transition — with 15+ real examples
□ Peak Gravity — with examples
□ Energy Resolution — proportional vs disproportional with examples

RSV DIMENSIONS:
□ Open Loops — patterns, optimal counts, examples
□ Trust Level — trajectory patterns, examples
□ Tension — types (external/internal), escalation patterns, examples
□ Pattern Expectation — how it's set and broken, examples
□ Frame — how reader's frame evolves, examples
□ Energy Balance — charging/discharging patterns, examples
□ Superposition — when readers hold multiple interpretations, examples

LONG-RANGE INTERACTIONS:
□ Setup-Payoff Bonds — with 15+ real examples showing both slides
□ Echo Patterns — with examples
□ Interference Effects — with examples
□ Deliberate Absences — with examples
□ Callback Chains — with examples
□ Entanglement Pairs — with examples

RHYTHM & PACING:
□ Density Waveform patterns
□ Energy Curve patterns
□ Information Rate patterns
□ Silence/Breathing patterns
□ Momentum types

ANTIMATTER:
□ Complete catalog of destructive phrases/patterns from the data

COMPOUND PATTERNS:
□ Document every compound (2+ concepts appearing together for outsized effect)
□ Show the real posts where each compound occurs with quoted slides

FULL POST WALKTHROUGHS (10 posts):
□ Select 10 posts that showcase different structural approaches (mix of reels + carousels, different arc shapes, different dominant frames)
□ For EACH of the 10: analyze EVERY SLIDE showing which concepts are active (speech act, deltas, frame, distance, techniques, proof)
□ For EACH transition between slides: explain the causal bridge and why these slides MUST be in this order
□ Show the RSV trajectory through the post — how loops, trust, tension, and energy evolve slide by slide
□ Identify the symmetry break, phase transition, and peak gravity — and explain WHY they're placed where they are
□ This teaches a writer how to COMPOSE a complete post from physics, not just use individual concepts

THEN:
□ Laws (with 10-15 quoted slides each)
□ Interactions (which concepts amplify/conflict/require each other — with real examples)
□ Deep Structure (the minimal principles from which everything derives)
□ Hypothesis Tests (all 17, each backed by 3+ quoted slides)
□ Conversational DNA (sentence structures, connectors, bridges, rhythm — backed by real text)

FINAL CHECK BEFORE STOPPING:
- Have you covered EVERY type from your Step 1 inventory? If any are missing, go back.
- Does each concept have 15+ examples? If any have fewer than 10, add more.
- Have you included 5 full post walkthroughs? If not, add them.
- Is your output at least 80,000 tokens? If not, you stopped too early — deepen your analysis.

This is the foundational text of Content Physics. It should read like a textbook written by someone who has spent years studying these ${N} posts. USE YOUR FULL OUTPUT BUDGET.`;

  const estimatedInput = Math.round((preparedData.length + computedStats.length + systemPrompt.length + userPrompt.length) / 4);
  const synthesisModel = 'openai/gpt-5.4';
  console.log(`  🔬 Calling ${synthesisModel} for Exemplar synthesis (~${estimatedInput} est. input tokens, OpenRouter streaming, 128K max output)...`);

  const synthesisApiKey = config.openRouterApiKey || apiKey;
  const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${synthesisApiKey}`,
    },
    body: JSON.stringify({
      model: synthesisModel,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: 128000,
      temperature: 0.3,
      stream: true,
    }),
    signal: AbortSignal.timeout(7200_000), // 2 hour timeout
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Exemplar synthesis failed (${response.status}): ${errText.substring(0, 300)}`);
  }

  // Stream the response (OpenRouter uses OpenAI SSE format)
  const reader = response.body?.getReader();
  if (!reader) throw new Error('No response body reader for synthesis');

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
        // OpenRouter SSE format (OpenAI-compatible)
        const delta = event.choices?.[0]?.delta?.content;
        if (delta) synthesisText += delta;
        if (event.usage) {
          inputTokens = event.usage.prompt_tokens || inputTokens;
          outputTokens = event.usage.completion_tokens || outputTokens;
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

  return synthesisText;
}

// ============================================================
// Pass 2: Codex Deepening — fill in concepts missed by Pass 1
// Uses continuation loop: if model stops early, auto-continues
// ============================================================

// Concept list for Pass 2 — each becomes a numbered entry the model must produce
const PASS2_CONCEPTS = [
  // Speech Acts (highest frequency first)
  'HOOK (Speech Act)',           // 105/105
  'REVEAL (Speech Act)',         // 83/105
  'CLAIM (Speech Act)',          // 82/105
  'PROOF (Speech Act)',          // 79/105
  'REFRAME (Speech Act)',        // 73/105
  'OBSERVATION (Speech Act)',    // 71/105
  'INSTRUCTION (Speech Act)',    // 54/105
  'DECISION (Speech Act)',       // 48/105
  'THESIS (Speech Act)',         // 47/105
  'PERMISSION (Speech Act)',     // 34/105
  'WARNING (Speech Act)',        // 31/105
  'INVITATION (Speech Act)',     // 58/105
  'GRATITUDE (Speech Act)',      // 12/105
  // Reader Deltas
  'IDENTIFICATION+ (Reader Delta)',  // 97/105
  'TENSION+ (Reader Delta)',         // 98/105
  'TRUST+ (Reader Delta)',           // 91/105
  'ASPIRATION+ (Reader Delta)',      // 95/105
  'SURPRISE (Reader Delta)',         // 88/105
  'EMPATHY+ (Reader Delta)',         // 54/105
  'RELIEF / TENSION- (Reader Delta)', // 52/105
  'FEAR+ (Reader Delta)',            // 41/105
  'AWE (Reader Delta)',              // 49/105
  'GUILT (Reader Delta)',            // 32/105
  'WARMTH (Reader Delta)',           // 29/105
  'CATHARSIS (Reader Delta)',        // 18/105
  // Transitions
  'ESCALATION (Transition)',         // 86/105
  'ANSWER (Transition)',             // 62/105
  'ACCUMULATION (Transition)',       // 58/105
  'OBJECTION-TO-RESOLUTION (Transition)', // 52/105
  'CAUSE-TO-CONSEQUENCE (Transition)', // 57/105
  'PIVOT (Transition)',              // 73/105
  'PARTIAL RESOLUTION (Transition)', // 49/105
  // Techniques
  'ELLIPSIS MOMENTUM (Technique)',   // 79/105
  'SUBJECT DROP (Technique)',        // 84/105
  'DIRECT ADDRESS (Technique)',      // 56/105
  'COLON-AS-PROMISE (Technique)',    // 51/105
  'DIRECT DIALOGUE (Technique)',     // 32/105
  'REPETITION DEVICE (Technique)',   // 36/105
];

/** Stream an OpenRouter SSE response and collect text content */
async function streamOpenRouterResponse(
  response: Response,
  label: string,
): Promise<{ text: string; inputTokens: number; outputTokens: number }> {
  const reader = response.body?.getReader();
  if (!reader) throw new Error(`No response body reader for ${label}`);

  const decoder = new TextDecoder();
  let text = '';
  let inputTokens = 0;
  let outputTokens = 0;
  let lastLog = 0;
  let lineBuffer = ''; // Buffer for partial lines that span chunk boundaries

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunk = decoder.decode(value, { stream: true });
    // Prepend any leftover partial line from previous chunk
    const combined = lineBuffer + chunk;
    const lines = combined.split('\n');
    // Last element might be incomplete — save it for next chunk
    lineBuffer = lines.pop() || '';

    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      const eventData = line.slice(6).trim();
      if (eventData === '[DONE]') continue;
      try {
        const event = JSON.parse(eventData);
        const delta = event.choices?.[0]?.delta?.content;
        if (delta) text += delta;
        if (event.usage) {
          inputTokens = event.usage.prompt_tokens || inputTokens;
          outputTokens = event.usage.completion_tokens || outputTokens;
        }
      } catch {}
    }

    if (Date.now() - lastLog > 30_000) {
      const tokens = Math.round(text.length / 4);
      console.log(`  🔬 ${label}: ${text.length} chars (~${tokens} tokens)...`);
      updateProgress({ phase: `${label}: ~${tokens} output tokens...` });
      lastLog = Date.now();
    }
  }

  // Process any remaining buffered line
  if (lineBuffer.startsWith('data: ')) {
    const eventData = lineBuffer.slice(6).trim();
    if (eventData !== '[DONE]') {
      try {
        const event = JSON.parse(eventData);
        const delta = event.choices?.[0]?.delta?.content;
        if (delta) text += delta;
        if (event.usage) {
          inputTokens = event.usage.prompt_tokens || inputTokens;
          outputTokens = event.usage.completion_tokens || outputTokens;
        }
      } catch {}
    }
  }

  return { text, inputTokens, outputTokens };
}

/** Detect which concepts were already covered in the output text */
function detectCoveredConcepts(outputText: string): Set<number> {
  const covered = new Set<number>();
  for (let i = 0; i < PASS2_CONCEPTS.length; i++) {
    // Extract the concept name (before the category in parentheses)
    const name = PASS2_CONCEPTS[i].split(' (')[0];
    // Check if the entry header appears in the output (flexible matching)
    const patterns = [
      `═══ ${name}`,                          // exact header
      `## ${name}`,                            // markdown header
      `**${name}**`,                           // bold
      `### ${name}`,                           // h3
      `ENTRY ${i + 1}:`,                       // numbered entry
      `${i + 1}. ${name}`,                     // numbered list
    ];
    if (patterns.some(p => outputText.includes(p))) {
      covered.add(i);
    }
  }
  return covered;
}

async function runCodexDeepening(preparedData: string, pass1Codex: string): Promise<void> {
  const apiKey = config.openRouterApiKey || config.anthropicApiKey;
  if (!apiKey) throw new Error('No API key for Codex deepening');

  console.log(`  🔬 Pass 2: Deepening ${PASS2_CONCEPTS.length} concepts...`);

  // Build the numbered concept list for the prompt
  const numberedList = PASS2_CONCEPTS.map((c, i) => `${i + 1}. ${c}`).join('\n');

  // System prompt — context + rigor + format. No behavioral nagging.
  const systemPrompt = `You are writing the Exemplar Codex of Content Physics — the first formal language that defines how human attention works in sequential media. This is a new field. No one has ever formalized this before. The Codex is grounded in 105+ real viral posts, each analyzed through 10-pass extraction (speech acts, transitions, reader state, physics events, rhythm, long-range interactions, antimatter, deep fabric). Every concept in this language exists because we observed it in real content that went viral.

This is empirical science with the rigor of physics — every claim must be backed by real evidence from real posts. Every example you cite MUST be a real slide copied EXACTLY from the post data provided. Never fabricate, paraphrase, or invent examples. If you can't find a real example for a concept in the data, say so — do not make one up. The writing model that reads this Codex will use these examples as ground truth for generating content. A hallucinated example teaches the wrong pattern and produces bad content.

The "Where active" line in each example is critical — it teaches the writing model to SEE the concept operating inside real text, not just recognize the label. Point to the specific words, phrase, or sentence structure that make the concept happen.

OUTPUT FORMAT — use this exact structure for every entry, then immediately start the next:

═══ {CONCEPT NAME} ({Category}) ═══

DEFINITION: What this concept IS — mechanically, what happens in the text and what it produces in the reader. Why it works psychologically.
FREQUENCY: Appears in X/105 posts.

EXAMPLES:

1. "{FULL SLIDE TEXT copied exactly from the post data}"
   — [{Post title}] Slide {N}
   Where active: {the SPECIFIC words/phrase/structure that make this concept happen — e.g., "The word 'cheated' without an object creates the curiosity gap" or "The shift from past to present tense at 'I find businesses...' is where distance drops to zero"}
   Why it works: {mechanism — sentence structure, word choice, rhythm, position}
   Reader effect: {what changes in the reader's mind}
   How to apply: {operational instruction — how a writer uses this same structure with different content}

2. ... (10-15 examples per entry, chosen for VARIETY — different creators, niches, approaches to the same concept)

PATTERNS: {what the examples share — cite specific example numbers as evidence}
ANTI-PATTERNS: {what would destroy this concept — with specific BAD wording so the writer knows what to avoid}

For TRANSITIONS: each example MUST include BOTH slides (from → to) with the connector text.
For TECHNIQUES: show the actual text demonstrating the technique and explain what quark/delta it produces.`;

  // User message: data first (biggest chunk), existing codex second, task LAST (recency bias)
  const userPrompt = `<raw_data>
${preparedData}
</raw_data>

<existing_codex>
${pass1Codex}
</existing_codex>

<task>
The existing Codex has a Periodic Table (definitions + frequencies for every concept) and detailed entries (with 10-15 real examples each) for these 13 concepts ONLY:
- CONFESSION, FALSE FLOOR, DIALOGUE-BASED OBJECTION VENTRILOQUISM, SPECIFICITY AS CREDIBILITY PROXY, OMITTED MECHANISM, STATE CHANGE THROUGH CONTRAST (from Pass 1)
- CONTRAST, VALIDATION, PARTICIPATORY VALIDATION, PHASE TRANSITION, ANTI-GLAMOUR POSITIONING, EAVESDROPPING PHYSICS (from Pass 3 gap-fill)
- Plus Laws 1-6, Interactions, Deep Structure, Hypothesis Tests, Conversational DNA, 10 Walkthroughs

The following ${PASS2_CONCEPTS.length} concepts appear in the Periodic Table but have NO detailed entry with real examples yet. Write all ${PASS2_CONCEPTS.length} entries sequentially:

${numberedList}

For EVERY entry above:
- DEFINITION: One precise paragraph — what mechanically happens in the text, what it produces in the reader, why it works psychologically.
- FREQUENCY: "Appears in X/105 posts" — count from the quark profiles in the raw data.
- 10-15 REAL EXAMPLES chosen for VARIETY (different creators, niches, approaches to the same concept). Each example must include:
  • The FULL SLIDE TEXT copied exactly from the raw data — not a reference like "Post 47, Slide 3" but the actual words. The writing model reading this Codex will NOT have access to the original posts.
  • Post title + slide number for attribution.
  • "Where active" — point to the SPECIFIC words, phrase, or sentence structure within that slide that make this concept happen. This is the most important line. Without it, the model knows the name but cannot locate the physics in actual sentences.
  • "Why it works" — the mechanism (sentence structure, word choice, rhythm, position in the post).
  • "Reader effect" — what changes in the reader's mind and why.
  • "How to apply" — operational instruction a writer follows to use this same structure with different content.
- PATTERNS: What the examples share — cite specific example numbers as evidence for each pattern.
- ANTI-PATTERNS: What would DESTROY this concept — with specific bad wording examples so the writer knows what to avoid.

For TRANSITION entries: every example MUST include BOTH slides (the "from" slide and the "to" slide) with the actual connector/bridge text between them.
For TECHNIQUE entries: show the actual text demonstrating the technique, and explain what quark or reader delta it produces.

Write entry 1 now, then 2, then 3, continuing through ${PASS2_CONCEPTS.length}. Output will be appended to the existing Codex — do not repeat entries already deeply covered.
</task>`;

  // Continuation loop — if model stops early, we continue from where it left off
  const MAX_CONTINUATIONS = 5;
  let allPass2Text = '';
  let totalInputTokens = 0;
  let totalOutputTokens = 0;

  for (let attempt = 0; attempt <= MAX_CONTINUATIONS; attempt++) {
    const isFirstCall = attempt === 0;
    const covered = isFirstCall ? new Set<number>() : detectCoveredConcepts(allPass2Text);
    const remaining = PASS2_CONCEPTS.length - covered.size;

    if (!isFirstCall) {
      if (remaining === 0) {
        console.log(`  ✅ All ${PASS2_CONCEPTS.length} concepts covered after ${attempt} calls`);
        break;
      }
      // Check if we got meaningful new output in the last round
      console.log(`  🔄 Continuation ${attempt}/${MAX_CONTINUATIONS}: ${covered.size}/${PASS2_CONCEPTS.length} concepts covered, ${remaining} remaining`);
    }

    // Build messages — first call vs continuation
    const messages: Array<{ role: string; content: string }> = [];

    if (isFirstCall) {
      messages.push({ role: 'system', content: systemPrompt });
      messages.push({ role: 'user', content: userPrompt });
    } else {
      // Continuation: include previous output as assistant, then ask to continue
      messages.push({ role: 'system', content: systemPrompt });
      messages.push({ role: 'user', content: userPrompt });
      messages.push({ role: 'assistant', content: allPass2Text });

      // Build list of remaining concepts
      const remainingConcepts = PASS2_CONCEPTS
        .filter((_, i) => !covered.has(i))
        .map((c, i) => `${i + 1}. ${c}`)
        .join('\n');

      messages.push({
        role: 'user',
        content: `You wrote ${covered.size} entries. Continue with the remaining ${remaining}:\n\n${remainingConcepts}\n\nPick up exactly where you stopped. Same format. Next entry now.`,
      });
    }

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: 'openai/gpt-5.4',
        messages,
        max_tokens: 128000,
        temperature: 0.5, // slightly higher to reduce premature convergence
        stream: true,
      }),
      signal: AbortSignal.timeout(7200_000),
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Codex deepening failed (${response.status}): ${errText.substring(0, 300)}`);
    }

    const label = isFirstCall ? 'Pass 2' : `Pass 2 continuation ${attempt}`;
    const { text, inputTokens, outputTokens } = await streamOpenRouterResponse(response, label);

    totalInputTokens += inputTokens;
    totalOutputTokens += outputTokens;
    console.log(`  🔬 ${label} complete: ${text.length} chars (~${Math.round(text.length / 4)} tokens), ${inputTokens} in / ${outputTokens} out`);

    if (!text || text.length < 500) {
      console.log(`  ⚠️ ${label} produced minimal output — stopping continuations`);
      break;
    }

    // Append this round's output
    if (isFirstCall) {
      allPass2Text = text;
    } else {
      allPass2Text += '\n\n' + text;
    }

    // Check coverage after this round
    const newCovered = detectCoveredConcepts(allPass2Text);
    const newRemaining = PASS2_CONCEPTS.length - newCovered.size;
    console.log(`  📊 After ${label}: ${newCovered.size}/${PASS2_CONCEPTS.length} concepts covered (${newRemaining} remaining)`);

    // If all covered or model produced a huge output, we're done
    if (newRemaining === 0 || allPass2Text.length > 400000) {
      console.log(`  ✅ Pass 2 complete: all concepts covered or output limit reached`);
      break;
    }
  }

  console.log(`  🔬 Pass 2 total: ${allPass2Text.length} chars (~${Math.round(allPass2Text.length / 4)} tokens), ${totalInputTokens} total input, ${totalOutputTokens} total output`);
  updateProgress({ synthesisTokens: { input: totalInputTokens, output: totalOutputTokens } });

  if (!allPass2Text || allPass2Text.length < 1000) {
    console.log('  ⚠️ Pass 2 produced minimal output — skipping append');
    return;
  }

  // Append Pass 2 to the existing Codex atom
  const combinedCodex = pass1Codex + '\n\n═══ PASS 2: DEEPENED CONCEPT ENTRIES ═══\n\n' + allPass2Text;

  const allAtomsForSave = await fetchAllByType('research', { limit: 500 });
  const existingCodex = allAtomsForSave.find(a => a.metadata?.isCodexSynthesis);

  if (existingCodex) {
    await updateAtom(existingCodex.uuid, {
      body: combinedCodex,
      metadata: {
        ...existingCodex.metadata,
        updatedAt: new Date().toISOString(),
        pass2Complete: true,
        pass2Concepts: PASS2_CONCEPTS.length,
        pass2Covered: detectCoveredConcepts(allPass2Text).size,
        pass2Continuations: totalOutputTokens > 0 ? Math.ceil(totalOutputTokens / 3000) : 0,
      },
    });
    console.log(`  📊 Updated Codex with Pass 2 content: ${combinedCodex.length} total chars`);
  }
}

// ============================================================
// Walkthrough Rewrite — replace thin summaries with full slide text + unified language
// ============================================================

const WALKTHROUGH_POSTS = [
  'POST 1 — "2020: \'Babe, I\'m worried about our future…\'"',
  'POST 7 — "$100k is officially lower middle class..."',
  'POST 10 — "In 2018 my wife told me it wasn\'t working anymore..."',
  'POST 12 — "Mommy, why is our family rich?"',
  'POST 13 — "I\'m 23 yrs old and here\'s all the L\'s I taken..."',
  'POST 14 — "As a millionaire, I don\'t invest in the S&P500 because..."',
  'POST 22 — "As millionaires, we\'ll never post our son on social media because..."',
  'POST 24 — "EX BANKER EXPLAINS: PLUMBERS & HVAC OWNERS..."',
  'POST 30 — "- The government shut down (again)..."',
  'POST 103 — "2011: Dad, I got kicked out of school..."',
];

async function runWalkthroughRewrite(preparedData: string, existingCodex: string): Promise<void> {
  const apiKey = config.openRouterApiKey || config.anthropicApiKey;
  if (!apiKey) throw new Error('No API key for walkthrough rewrite');

  console.log(`  🔬 Walkthrough rewrite: ${WALKTHROUGH_POSTS.length} posts...`);

  const numberedPosts = WALKTHROUGH_POSTS.map((p, i) => `${i + 1}. ${p}`).join('\n');

  const systemPrompt = `You are rewriting the 10 Full Post Walkthroughs for the Exemplar Codex of Content Physics — the first formal language of how human attention works in sequential media.

The existing walkthroughs are thin summaries: they mention concept names but don't quote actual slide text, don't use the unified language consistently, and group slides into ranges like "Slides 4-10" instead of analyzing each one.

Your job: rewrite all 10 walkthroughs so they are the definitive teaching tool for how Content Physics concepts compose into complete posts. A writer reading one walkthrough should understand exactly how every slide works, what physics are active, and why the slides must be in that order.

RULES:
- For EVERY slide, you MUST include the COMPLETE TEXT of what that slide says — the actual words a reader sees on screen, copied character-for-character from the raw post data. NOT a reference like "Slide 3" or a summary like "the speaker confesses." The FULL TEXT. A writer reading this walkthrough will NOT have access to the original posts — the walkthrough must be self-contained.
- Use the exact concept names from the Codex's Periodic Table and deep entries. Not vague descriptions — the formal language (HOOK, CONFESSION, ESCALATION, IDENTIFICATION+, etc.).
- Analyze EVERY slide individually. Do NOT group slides into ranges like "Slides 4-10: problem stack." Each slide gets its own entry with its own quoted text and its own physics labels.

OUTPUT FORMAT for each walkthrough:

═══ WALKTHROUGH {N}: {POST TITLE} ═══

Why selected: {one sentence — what makes this post structurally instructive}
Dominant frame: {from Periodic Table}
Arc shape: {from Periodic Table}

SLIDE-BY-SLIDE ANALYSIS:

Slide 1: "{THE COMPLETE TEXT OF THIS SLIDE — every word the reader sees, copied from the raw data}"
  Speech act: {name from Codex}
  Reader deltas: {list — e.g., curiosity+, identification+, tension+}
  Frame: {name from Codex}
  Distance: {zero / near / far}
  Techniques active: {list — e.g., ellipsis momentum, direct dialogue, subject drop}
  Why this slide works: {1-2 sentences — what makes THIS specific text effective}

Slide 1 → Slide 2 TRANSITION: {name from Codex — e.g., ANSWER, ESCALATION, PIVOT}
  Why this order: {why slide 2 MUST follow slide 1 — what would break if you swapped them}

Slide 2: "{THE COMPLETE TEXT OF THIS SLIDE}"
  Speech act: ...
  Reader deltas: ...
  (continue for EVERY slide in the post — no skipping, no grouping)

After all slides:

RSV TRAJECTORY:
  - Slides 1-{N}: {describe open loops count, trust level, tension level, energy balance using formal terms}
  - Slide {X}: {PEAK GRAVITY — name the moment and what's simultaneously active}
  - Slide {Y}: {ENERGY RESOLUTION — what discharges and how}
  - Slide {Z}: {final reader state}

PHYSICS EVENTS:
  - SYMMETRY BREAK at slide {N}: "{quoted text from that slide}" — {why the pattern breaks here}
  - PHASE TRANSITION at slide {N}: "{quoted text}" — {what the post becomes after this moment}
  - PEAK GRAVITY at slide {N}: {which open loops, trust deposits, and tension sources are simultaneously active}
  - ENERGY RESOLUTION at slide {N}: "{quoted text}" — {what stored energy discharges and into what}

COMPOSITION LESSON: {2-3 sentences — what a writer learns from this post's structure that they can replicate in any niche}`;

  const userPrompt = `<raw_data>
${preparedData}
</raw_data>

<existing_codex>
${existingCodex}
</existing_codex>

<task>
Rewrite all 10 walkthroughs. For each post:
1. Find the post in the raw data above.
2. For EVERY slide, copy the COMPLETE slide text into the walkthrough — every word the reader sees on screen.
3. Label each slide with the Codex language: speech act, reader deltas, frame, distance, techniques.
4. Label the transition between every pair of adjacent slides.
5. After all slides: RSV trajectory, physics events (with quoted text), composition lesson.

Do NOT summarize slides. Do NOT group slides. Do NOT skip slides. The full text of every slide must appear in the walkthrough.

${numberedPosts}

Write walkthrough 1 now, then 2, then 3, continuing through 10. These replace the existing thin walkthroughs.
</task>`;

  // Continuation loop — same as Pass 2
  const MAX_CONTINUATIONS = 5;
  let allText = '';
  let totalInputTokens = 0;
  let totalOutputTokens = 0;

  for (let attempt = 0; attempt <= MAX_CONTINUATIONS; attempt++) {
    const isFirstCall = attempt === 0;

    if (!isFirstCall) {
      // Count completed walkthroughs
      const completedCount = (allText.match(/═══ WALKTHROUGH/g) || []).length;
      const remaining = WALKTHROUGH_POSTS.length - completedCount;
      if (remaining <= 0) {
        console.log(`  ✅ All ${WALKTHROUGH_POSTS.length} walkthroughs complete after ${attempt} calls`);
        break;
      }
      console.log(`  🔄 Continuation ${attempt}/${MAX_CONTINUATIONS}: ${completedCount}/${WALKTHROUGH_POSTS.length} walkthroughs done, ${remaining} remaining`);
    }

    const messages: Array<{ role: string; content: string }> = [];

    if (isFirstCall) {
      messages.push({ role: 'system', content: systemPrompt });
      messages.push({ role: 'user', content: userPrompt });
    } else {
      messages.push({ role: 'system', content: systemPrompt });
      messages.push({ role: 'user', content: userPrompt });
      messages.push({ role: 'assistant', content: allText });

      const completedCount = (allText.match(/═══ WALKTHROUGH/g) || []).length;
      const remainingPosts = WALKTHROUGH_POSTS
        .slice(completedCount)
        .map((p, i) => `${i + 1}. ${p}`)
        .join('\n');

      messages.push({
        role: 'user',
        content: `You wrote ${completedCount} walkthroughs. Continue with the remaining:\n\n${remainingPosts}\n\nSame format. Next walkthrough now.`,
      });
    }

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: 'openai/gpt-5.4',
        messages,
        max_tokens: 128000,
        temperature: 0.5,
        stream: true,
      }),
      signal: AbortSignal.timeout(7200_000),
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Walkthrough rewrite failed (${response.status}): ${errText.substring(0, 300)}`);
    }

    const label = isFirstCall ? 'Walkthrough rewrite' : `Walkthrough continuation ${attempt}`;
    const { text, inputTokens, outputTokens } = await streamOpenRouterResponse(response, label);

    totalInputTokens += inputTokens;
    totalOutputTokens += outputTokens;
    console.log(`  🔬 ${label} complete: ${text.length} chars (~${Math.round(text.length / 4)} tokens)`);

    if (!text || text.length < 500) {
      console.log(`  ⚠️ ${label} produced minimal output — stopping`);
      break;
    }

    allText = isFirstCall ? text : allText + '\n\n' + text;

    const completedCount = (allText.match(/═══ WALKTHROUGH/g) || []).length;
    console.log(`  📊 After ${label}: ${completedCount}/${WALKTHROUGH_POSTS.length} walkthroughs done`);

    if (completedCount >= WALKTHROUGH_POSTS.length || allText.length > 500000) {
      console.log(`  ✅ Walkthrough rewrite complete`);
      break;
    }
  }

  console.log(`  🔬 Walkthrough rewrite total: ${allText.length} chars, ${totalInputTokens} in / ${totalOutputTokens} out`);
  updateProgress({ synthesisTokens: { input: totalInputTokens, output: totalOutputTokens } });

  if (!allText || allText.length < 2000) {
    console.log('  ⚠️ Walkthrough rewrite produced minimal output — skipping');
    return;
  }

  // Replace old walkthroughs in the Codex
  const codexAtoms = await fetchAllByType('research', { limit: 500 });
  const existingAtom = codexAtoms.find(a => a.metadata?.isCodexSynthesis);

  if (existingAtom) {
    let codex = existingAtom.body || '';

    // Find and remove old walkthroughs section
    const oldWalkthroughStart = codex.indexOf('═══ 10 FULL POST WALKTHROUGHS ═══');
    if (oldWalkthroughStart > -1) {
      // Old walkthroughs go to the end of the pre-Pass-2 content (before ═══ PASS 2)
      const pass2Start = codex.indexOf('═══ PASS 2:', oldWalkthroughStart);
      if (pass2Start > -1) {
        // Replace old walkthroughs but keep Pass 2 content
        codex = codex.substring(0, oldWalkthroughStart) + allText + '\n\n' + codex.substring(pass2Start);
      } else {
        // No Pass 2 marker — old walkthroughs are at the end of base content
        codex = codex.substring(0, oldWalkthroughStart) + allText;
        // Re-append Pass 2 if it exists after walkthroughs
        const pass2Marker = existingAtom.body?.indexOf('═══ PASS 2: DEEPENED CONCEPT ENTRIES ═══');
        if (pass2Marker && pass2Marker > oldWalkthroughStart) {
          codex += '\n\n' + existingAtom.body!.substring(pass2Marker);
        }
      }
    } else {
      // No old walkthroughs found — just append before Pass 2
      const pass2Start = codex.indexOf('═══ PASS 2: DEEPENED CONCEPT ENTRIES ═══');
      if (pass2Start > -1) {
        codex = codex.substring(0, pass2Start) + '\n\n' + allText + '\n\n' + codex.substring(pass2Start);
      } else {
        codex += '\n\n' + allText;
      }
    }

    await updateAtom(existingAtom.uuid, {
      body: codex,
      metadata: {
        ...existingAtom.metadata,
        updatedAt: new Date().toISOString(),
        walkthroughsRewritten: true,
      },
    });
    console.log(`  📊 Updated Codex with rewritten walkthroughs: ${codex.length} total chars`);
  }
}

// ============================================================
// Pass 3: Unification — collapse micro-variants, fill gaps, prepend language reference
// ============================================================

async function runCodexUnification(preparedData: string, existingCodex: string): Promise<void> {
  const apiKey = config.openRouterApiKey || config.anthropicApiKey;
  if (!apiKey) throw new Error('No API key for Codex unification');

  console.log(`  🔬 Pass 3: Unifying language from ${existingCodex.length} chars of existing Codex...`);

  const systemPrompt = `You are completing the EXEMPLAR CODEX — the first formal language of Content Physics.

Passes 1 and 2 produced brilliant analysis: deep concept entries with real examples, laws, walkthroughs, conversational DNA. But the language is NOT YET UNIFIED. The inventory at the top lists hundreds of micro-variant names that are actually the same concept ("confession-hook," "failure-confession," "confession-cliffhanger" are all CONFESSION in different positions). And some concepts from the inventory still lack detailed entries.

Newton didn't publish hundreds of unnamed observations. He published 3 laws and showed how everything derives from them. That's what you're doing now.

YOUR THREE TASKS:

TASK 1 — THE PERIODIC TABLE OF CONTENT PHYSICS
Produce a complete reference table listing EVERY distinct concept that exists in viral content. Collapse all micro-variants into their parent concepts. For each concept: one name, one precise 1-2 sentence definition, and which category it belongs to.

Categories:
- FORCES (the 3 fundamental forces)
- SPEECH ACTS (what the speaker is doing — collapsed to the minimal distinct set)
- TRANSITIONS (how slides connect — collapsed to the minimal distinct set)
- READER DELTAS (what changes in the reader — collapsed to the minimal distinct set)
- PROOF TYPES (what earns belief — collapsed to the minimal distinct set)
- MOTIVATIONS (why the subject acts — collapsed to the minimal distinct set)
- COMPRESSIONS (how time/info is skipped — collapsed to the minimal distinct set)
- FRAMES (how a slide positions content — collapsed to the minimal distinct set)
- DISTANCES (zero / near / far)
- TECHNIQUES (craft moves — collapsed to the minimal distinct set)
- DOMINANT FRAMES (post-level identity — collapsed to the minimal distinct set)
- ARC SHAPES (full-post emotional trajectory — collapsed to the minimal distinct set)
- PHYSICS EVENTS (symmetry break, phase transition, peak gravity, energy resolution)
- LONG-RANGE INTERACTIONS (bonds, echoes, absences, entanglement, callbacks, interference)
- RSV DIMENSIONS (open loops, trust, tension, pattern expectation, frame, energy balance, superposition)
- COMPOUND PATTERNS (concepts that combine for outsized effect)
- ANTIMATTER (phrases/moves that destroy physics)

For each concept in the table: NAME | CATEGORY | 1-2 sentence definition | frequency (X/105 posts)

This table IS the language. Every concept that exists in viral content must be named here. If it's not in this table, it doesn't exist in the language.

TASK 2 — FILL REMAINING GAPS
After producing the periodic table, check: does every concept in your table have a detailed entry with real examples somewhere in the existing Codex (Pass 1 or Pass 2)? If NOT, write that entry now with 10-15 real examples from the raw post data. Full quoted slide text, why it works, how to apply. Same format as Pass 1 and Pass 2 entries.

Focus on the concepts that appear in 20+ posts but still lack entries. These are the workhorses of viral content that the writing model MUST understand deeply.

TASK 3 — VARIANT MAPPING
For each concept in the periodic table, list the micro-variant names from the inventory that collapse into it. This mapping tells the writing model: "when you see 'confession-hook' or 'failure-confession' in a profile, that's CONFESSION."

Example:
CONFESSION → includes: confession-hook, failure-confession, confession-cliffhanger, vulnerability-open, sacrifice-confession, breaking-point-declaration, honest-limitation

RULES:
- You are ONLY ADDING new content. The existing Codex (Pass 1 + Pass 2) is ALREADY GREAT — do NOT summarize, rewrite, or replace any of it. Your output gets prepended to the top. The existing entries remain as the detailed reference below.
- Every example MUST be real slide text from the raw data. Never fabricate. Include the FULL QUOTED SLIDE TEXT — the writing model won't have access to the original posts, only this Codex.
- The periodic table must be EXHAUSTIVE — no concept left unnamed. Every concept that appears in the data must be in the table. If you're unsure whether something is a distinct concept or a variant, check: does it produce a different reader effect through a different mechanism? If yes, it's distinct. If no, it's a variant.
- Collapse aggressively but correctly. 10-15 unified speech acts is better than 50 micro-variants. If two concepts are genuinely distinct (different mechanism, different reader effect), keep them separate. If they're the same concept in a different position or context, collapse them.
- For TASK 2 gap-filling: write entries with 10-15 REAL examples each. Every entry must have the same depth as the Pass 1 entries (Confession, Curiosity+, Specificity-as-Credibility). Do NOT write shallow 2-3 example entries. If a concept appears in 30+ posts, it deserves 15 examples. If it appears in 5 posts, 5 examples is fine.
- This is empirical science. Every concept exists because we observed it in real viral content. No theory without evidence. No concept without examples.
- You have ALL the data and ALL the existing Codex. Do NOT ask for more. Do NOT negotiate scope. Do NOT say "this would require multiple passes." Produce the output NOW.
- You have 128,000 tokens. USE THEM. If you finish the periodic table + gap entries + variant mapping and have tokens left, go deeper on the most important remaining concepts. Do NOT stop early.`;

  const userPrompt = `═══ EXISTING CODEX (Pass 1 + Pass 2) ═══

${existingCodex}

═══ RAW POST DATA (all posts with full text + quark profiles) ═══

${preparedData}

═══ YOUR TASK ═══

1. Produce the PERIODIC TABLE OF CONTENT PHYSICS — every distinct concept, collapsed from micro-variants, with 1-2 sentence definitions.
2. Fill gaps — write detailed entries for any concept in your table that lacks one in the existing Codex.
3. Produce the VARIANT MAPPING — for each concept, list all the micro-variant names that collapse into it.

Start with the periodic table. Then the gap-filling entries. Then the variant mapping. GO.`;

  const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: 'openai/gpt-5.4',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: 128000,
      temperature: 0.3,
      stream: true,
    }),
    signal: AbortSignal.timeout(7200_000),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Codex unification failed (${response.status}): ${errText.substring(0, 300)}`);
  }

  const { text: pass3Text, inputTokens, outputTokens } = await streamOpenRouterResponse(response, 'Pass 3 unification');
  console.log(`  🔬 Pass 3 complete: ${pass3Text.length} chars (~${Math.round(pass3Text.length / 4)} tokens), ${inputTokens} in / ${outputTokens} out`);
  updateProgress({ synthesisTokens: { input: inputTokens, output: outputTokens } });

  if (!pass3Text || pass3Text.length < 1000) {
    console.log('  ⚠️ Pass 3 produced minimal output — skipping');
    return;
  }

  // Prepend the periodic table + gap entries to the existing Codex
  const unifiedCodex = pass3Text + '\n\n═══ DETAILED REFERENCE (Pass 1 + Pass 2 Entries) ═══\n\n' + existingCodex;

  const allAtomsForSave = await fetchAllByType('research', { limit: 500 });
  const existingAtom = allAtomsForSave.find(a => a.metadata?.isCodexSynthesis);

  if (existingAtom) {
    await updateAtom(existingAtom.uuid, {
      body: unifiedCodex,
      metadata: {
        ...existingAtom.metadata,
        updatedAt: new Date().toISOString(),
        pass3Complete: true,
        unified: true,
      },
    });
    console.log(`  📊 Updated Codex with unified language: ${unifiedCodex.length} total chars`);
  }
}
