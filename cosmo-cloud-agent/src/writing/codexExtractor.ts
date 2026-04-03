// cosmo-cloud-agent/src/writing/codexExtractor.ts
// Unified Codex-aware extraction: produces both a CodexProfile (JSON) and a
// Blueprint Walkthrough (text) in one call, using the Exemplar Codex's
// Periodic Table as the ONLY valid taxonomy.
//
// Replaces the old 10-pass quarkExtractor for new extractions.
// Uses GPT-5.4 via OpenRouter with streaming (1M context, handles full Codex).

import { config } from '../config';
import { Atom } from '../db/queries';
import { streamOpenRouterResponse } from './codexPipeline';
import { QuarkProfile } from './types';

// ============================================================
// Slide Text Resolution (same priority as old extractor)
// ============================================================

function resolveSlideText(atom: Atom): string {
  const analysis = atom.structured?.swipeAnalysis || {};

  // Priority 1: transcriptSlides (pre-parsed boundaries — most accurate)
  const transcriptSlides = analysis.transcriptSlides as Array<{ text: string; slideNumber: number }> | undefined;
  if (transcriptSlides && transcriptSlides.length > 1) {
    const text = transcriptSlides
      .sort((a, b) => (a.slideNumber || 0) - (b.slideNumber || 0))
      .map(s => `=== SLIDE ${s.slideNumber} ===\n${s.text}`)
      .join('\n\n');
    console.log(`  🔬 Codex extraction body: ${transcriptSlides.length} slides from transcriptSlides`);
    return text;
  }

  // Priority 2: raw atom.body (if it has meaningful content, not just a title)
  if (atom.body && atom.body.length > 200) {
    console.log(`  🔬 Codex extraction body: raw atom.body (${atom.body.length} chars)`);
    return atom.body;
  }

  // Priority 3: reconstruct from old contentPhysics slideQuarks[].text
  // These are truncated to ~100 chars per slide, but better than nothing
  const oldProfile = atom.structured?.contentPhysics as any;
  if (oldProfile?.slideQuarks?.length > 1) {
    const quarks = oldProfile.slideQuarks as Array<{ slideNumber: number; text: string }>;
    const text = quarks
      .sort((a, b) => (a.slideNumber || 0) - (b.slideNumber || 0))
      .map(q => `=== SLIDE ${q.slideNumber} ===\n${q.text || ''}`)
      .join('\n\n');
    const totalChars = quarks.reduce((sum, q) => sum + (q.text?.length || 0), 0);
    console.log(`  🔬 Codex extraction body: reconstructed from ${quarks.length} old slideQuarks (${totalChars} chars total — truncated per-slide)`);
    return text;
  }

  // Priority 4: body even if short (title-only posts like reels)
  if (atom.body && atom.body.length > 10) {
    console.log(`  🔬 Codex extraction body: short atom.body (${atom.body.length} chars — may be title only)`);
    return atom.body;
  }

  return '[no body text available]';
}

// ============================================================
// JSON Repair (state-machine approach from quarkExtractor.ts)
// ============================================================

function repairJsonString(input: string): string {
  const out: string[] = [];
  let inString = false;
  let i = 0;

  while (i < input.length) {
    const c = input[i];

    if (!inString) {
      if (c === '"') {
        inString = true;
        out.push(c);
      } else if (c === ',') {
        let j = i + 1;
        while (j < input.length && (input[j] === ' ' || input[j] === '\n' || input[j] === '\r' || input[j] === '\t')) j++;
        if (j < input.length && (input[j] === '}' || input[j] === ']')) {
          // Skip trailing comma
        } else {
          out.push(c);
        }
      } else {
        out.push(c);
      }
      i++;
    } else {
      if (c === '\\') {
        out.push(c);
        if (i + 1 < input.length) {
          out.push(input[i + 1]);
          i += 2;
        } else {
          i++;
        }
      } else if (c === '"') {
        let j = i + 1;
        while (j < input.length && (input[j] === ' ' || input[j] === '\t')) j++;
        const next = input[j];
        if (next === ':' || next === ',' || next === '}' || next === ']' || next === '\n' || next === '\r' || j >= input.length) {
          inString = false;
          out.push(c);
        } else {
          out.push('\\', '"');
        }
        i++;
      } else if (c === '\n') {
        out.push('\\', 'n');
        i++;
      } else if (c === '\r') {
        out.push('\\', 'r');
        i++;
      } else if (c === '\t') {
        out.push('\\', 't');
        i++;
      } else if (c.charCodeAt(0) < 0x20) {
        i++;
      } else {
        out.push(c);
        i++;
      }
    }
  }

  return out.join('');
}

// ============================================================
// Main Extraction Function
// ============================================================

export interface CodexExtractionResult {
  profile: QuarkProfile;      // JSON physics profile using Codex language
  walkthrough: string;         // Full walkthrough text (like the 10 in the Codex)
}

/**
 * Extract a post's physics profile + walkthrough using the full Exemplar Codex
 * as the taxonomy reference. Uses GPT-5.4 via OpenRouter with streaming.
 *
 * @param atom — the swipe atom to analyze
 * @param codexBody — the full Exemplar Codex body (~486K chars)
 * @returns profile (JSON) + walkthrough (text), or throws on failure
 */
export async function extractWithCodex(
  atom: Atom,
  codexBody: string,
): Promise<CodexExtractionResult> {
  const apiKey = config.openRouterApiKey;
  if (!apiKey) {
    throw new Error('No OpenRouter API key configured for Codex extraction');
  }

  const slideText = resolveSlideText(atom);
  const title = atom.title || 'Untitled';
  const analysis = atom.structured?.swipeAnalysis || {};
  const format = analysis.swipeContentFormat || atom.metadata?.contentSource || 'unknown';
  const hookType = analysis.hookType || 'unknown';
  const hookScore = analysis.hookScore ?? 'N/A';

  console.log(`  🔬 Codex extraction: "${title.substring(0, 60)}" (format: ${format}, hook: ${hookScore}/10)`);

  const systemPrompt = `You are analyzing a viral social media post using the Exemplar Codex of Content Physics — the complete formal language of how human attention works in sequential media. The Codex is provided in <codex> tags below.

CRITICAL RULES:
- Use ONLY the concept names from the Codex's Periodic Table. Do not invent new names or use synonyms.
- Every slide must be analyzed individually — no skipping, no grouping.
- Quote the FULL TEXT of every slide in the walkthrough — not a summary, not a reference.

You will produce TWO outputs in sequence:

PART 1: STRUCTURED PROFILE
A JSON object with the post's complete physics. The JSON must follow this exact structure:
{
  "version": 2,
  "extractedAt": "<ISO timestamp>",
  "extractedBy": "gpt-5.4-codex",
  "slideQuarks": [
    {
      "slideNumber": 1,
      "text": "<first 100 chars of slide text>",
      "speechAct": { "type": "<Periodic Table speech act name>", "mechanism": "<≤15 words>" },
      "readerDeltas": [{ "type": "<Periodic Table delta name>", "mechanism": "<≤15 words>" }],
      "proofType": { "type": "<name>", "mechanism": "<≤15 words>" },
      "motivation": { "type": "<name>", "mechanism": "<≤15 words>" },
      "compression": { "type": "<name>", "mechanism": "<≤15 words>" },
      "frame": { "type": "<Periodic Table frame name>", "mechanism": "<≤15 words>" },
      "experientialDistance": { "level": "zero|near|far", "mechanism": "<≤15 words>" },
      "techniques": [{ "technique": "<Periodic Table technique name>", "usage": "<≤15 words>" }]
    }
  ],
  "transitions": [
    {
      "from": 1, "to": 2,
      "type": "<Periodic Table transition name>",
      "mechanism": "<≤20 words>",
      "swapTestPasses": false,
      "doubleHelix": true
    }
  ],
  "arcQuarks": {
    "shape": "<Periodic Table arc shape name>",
    "winLossReversals": 3,
    "tensionPeaks": [5, 12, 18],
    "dominantFrame": { "type": "<Periodic Table dominant frame name>", "mechanism": "<≤15 words>" }
  },
  "rsv": {
    "trajectoryPoints": [
      {
        "afterSlide": 5,
        "openLoops": { "count": 4, "loops": ["what happened?", "will it work?"] },
        "trust": "medium — specifics building",
        "tension": { "level": "high", "type": "relational" },
        "frame": "DIALOGUE / EAVESDROPPING",
        "energyBalance": "charging"
      }
    ]
  },
  "physicsEvents": {
    "symmetryBreak": { "slideNumber": 14, "patternEstablished": "<what pattern>", "whatBreaks": "<what breaks it>" },
    "phaseTransition": { "slideNumber": 16, "frameBefore": "<frame>", "frameAfter": "<frame>", "recontextualization": "<what changes>" },
    "energyResolution": { "proportional": true, "assessment": "<≤20 words>" },
    "peakGravity": { "slideNumber": 12, "activeLoops": 5 }
  },
  "longRangeInteractions": {
    "setupPayoffBonds": [{ "setupSlide": 3, "payoffSlide": 24, "planted": "<what>", "harvested": "<what>" }],
    "echoPatterns": [{ "quarkType": "<concept>", "positions": [1, 14, 24], "transformation": "<how it changes>" }],
    "deliberateAbsences": [{ "what": "<what's omitted>", "effect": "<why>" }],
    "callbackChains": [{ "element": "<recurring element>", "appearances": [{ "slide": 1, "meaning": "<meaning here>" }] }]
  },
  "antimatter": ["<specific phrases/moves that would destroy this post's physics>"],
  "rhythm": {
    "densityWaveform": [12, 8, 15, 22, 10],
    "energyCurve": [2, 3, 4, 5, 3, 4, 5, 4, 3, 2],
    "momentumMechanism": "<≤20 words>"
  },
  "readerSimulation": [
    {
      "afterSlide": 1,
      "activeQuestions": ["what's wrong?"],
      "prediction": "relationship crisis",
      "dominantEmotion": "concern",
      "investmentLevel": "medium"
    }
  ],
  "deepFabric": "<100-200 word synthesis of what makes this post's physics unique>"
}

Keep ALL mechanism descriptions to ≤15 words. Be precise, not verbose.
Provide RSV trajectory points at 5 evenly-spaced boundaries through the post.
Provide reader simulation for EVERY slide.

PART 2: WALKTHROUGH
After the JSON, write a full walkthrough exactly like the 10 examples at the end of the Codex.
Format:

═══ WALKTHROUGH: "{post title}" ═══

Why selected: <one sentence>
Dominant frame: <from Periodic Table>
Arc shape: <from Periodic Table>

SLIDE-BY-SLIDE ANALYSIS:

Slide 1: "{THE COMPLETE TEXT OF THIS SLIDE — every word}"
  Speech act: <name>
  Reader deltas: <list>
  Frame: <name>
  Distance: <zero/near/far>
  Techniques active: <list>
  Why this slide works: <1-2 sentences>

Slide 1 → Slide 2 TRANSITION: <name>
  Why this order: <why slide 2 MUST follow slide 1>

(continue for EVERY slide — no skipping, no grouping)

RSV TRAJECTORY:
  - <describe at key points>

PHYSICS EVENTS:
  - SYMMETRY BREAK at slide N: "<quoted text>" — why
  - PHASE TRANSITION at slide N: "<quoted text>" — what changes
  - PEAK GRAVITY at slide N: what's active
  - ENERGY RESOLUTION at slide N: "<quoted text>" — what discharges

COMPOSITION LESSON: <2-3 sentences>`;

  const userPrompt = `<codex>
${codexBody}
</codex>

<post>
Title: "${title}"
Format: ${format} | Hook Type: ${hookType} | Hook Score: ${hookScore}/10

${slideText}
</post>

Analyze this post. Output PART 1 (JSON profile) first, then PART 2 (walkthrough). Do not skip any slides.`;

  const estimatedInput = Math.round((systemPrompt.length + userPrompt.length) / 4);
  console.log(`  🔬 Sending to GPT-5.4 (~${estimatedInput} est. input tokens, streaming)...`);

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
      max_tokens: 32000,  // Profile (~8K) + walkthrough (~15K) + buffer
      temperature: 0.2,   // Low for analysis accuracy
      stream: true,
    }),
    signal: AbortSignal.timeout(900_000), // 15 min timeout
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Codex extraction failed (${response.status}): ${errText.substring(0, 300)}`);
  }

  const { text: fullOutput, inputTokens, outputTokens } = await streamOpenRouterResponse(
    response,
    `Codex extraction: ${title.substring(0, 40)}`,
  );

  console.log(`  🔬 Codex extraction complete: ${fullOutput.length} chars (~${Math.round(fullOutput.length / 4)} tokens), ${inputTokens} in / ${outputTokens} out`);

  if (!fullOutput || fullOutput.length < 500) {
    throw new Error(`Codex extraction produced insufficient output (${fullOutput.length} chars)`);
  }

  // ============================================================
  // Parse output: split into JSON profile + walkthrough text
  // ============================================================

  let jsonPart = '';
  let walkthroughPart = '';

  // Find the JSON block — it's between the first { and the matching }
  const jsonStart = fullOutput.indexOf('{');
  if (jsonStart === -1) {
    throw new Error('No JSON object found in extraction output');
  }

  // Find the end of the JSON by counting braces
  let depth = 0;
  let jsonEnd = -1;
  for (let i = jsonStart; i < fullOutput.length; i++) {
    if (fullOutput[i] === '{') depth++;
    else if (fullOutput[i] === '}') {
      depth--;
      if (depth === 0) {
        jsonEnd = i + 1;
        break;
      }
    }
  }

  if (jsonEnd === -1) {
    // JSON wasn't properly closed — try to repair by adding closing braces
    jsonPart = fullOutput.substring(jsonStart) + '}'.repeat(depth);
    walkthroughPart = '';
    console.log(`  ⚠️ JSON not properly closed — added ${depth} closing braces`);
  } else {
    jsonPart = fullOutput.substring(jsonStart, jsonEnd);
    // Everything after the JSON is the walkthrough
    walkthroughPart = fullOutput.substring(jsonEnd).trim();
  }

  // Also check for a PART 2 / WALKTHROUGH marker
  if (!walkthroughPart) {
    const walkthroughMarker = fullOutput.indexOf('═══ WALKTHROUGH');
    if (walkthroughMarker > -1) {
      walkthroughPart = fullOutput.substring(walkthroughMarker).trim();
    }
  }

  // Strip any "PART 2" prefix text before the actual walkthrough
  const walkthroughHeaderIdx = walkthroughPart.indexOf('═══');
  if (walkthroughHeaderIdx > 0) {
    walkthroughPart = walkthroughPart.substring(walkthroughHeaderIdx);
  }

  // ============================================================
  // Parse JSON into profile
  // ============================================================

  let profile: QuarkProfile;
  try {
    profile = JSON.parse(jsonPart);
  } catch {
    console.log(`  ⚠️ JSON parse failed — attempting repair...`);
    try {
      const repaired = repairJsonString(jsonPart);
      profile = JSON.parse(repaired);
      console.log(`  ✅ JSON repair succeeded`);
    } catch (repairErr) {
      throw new Error(`JSON parse failed even after repair: ${(repairErr as Error).message}`);
    }
  }

  // Ensure version and metadata
  profile.version = 2;
  profile.extractedAt = new Date().toISOString();
  profile.extractedBy = 'gpt-5.4-codex';

  console.log(`  ✅ Codex extraction: ${profile.slideQuarks?.length || 0} slides, ${profile.transitions?.length || 0} transitions, walkthrough: ${walkthroughPart.length} chars`);

  return { profile, walkthrough: walkthroughPart };
}

// ============================================================
// Summary Builder (for quick display in API response)
// ============================================================

export function summarizeCodexExtraction(profile: QuarkProfile, walkthrough: string) {
  return {
    slides: profile.slideQuarks?.length || 0,
    transitions: profile.transitions?.length || 0,
    hasFabric: !!profile.deepFabric,
    hasRhythm: !!profile.rhythm,
    hasBonds: !!(profile.longRangeInteractions?.setupPayoffBonds?.length),
    hasSimulation: (profile.readerSimulation || []).length > 0,
    hasWalkthrough: walkthrough.length > 500,
    walkthroughLength: walkthrough.length,
    profileLanguage: 'codex-v2',
    arcShape: profile.arcQuarks?.shape || 'unknown',
    dominantFrame: profile.arcQuarks?.dominantFrame?.type || 'unknown',
  };
}
