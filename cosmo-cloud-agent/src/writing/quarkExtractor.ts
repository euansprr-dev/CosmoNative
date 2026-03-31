// cosmo-cloud-agent/src/writing/quarkExtractor.ts
// Content Physics: Quark extraction using Opus 4.6 for deep analysis
// Extracts the complete physics of WHY a viral post works — quarks, transitions, arc, RSV, physics events

import { config } from '../config';
import { Atom, fetchAllByType, fetchAtom, updateAtom } from '../db/queries';
import { QuarkProfile, QuarkSummary } from './types';

// ============================================================
// Extraction Prompt (6-pass deep analysis)
// ============================================================

function buildExtractionPrompt(atom: Atom): string {
  const analysis = atom.structured?.swipeAnalysis || {};
  const meta = atom.metadata || {};

  const sections = analysis.sections as Array<{ label: string; purpose: string; emotion: string; sizePercent: number }> | undefined;
  const persuasion = analysis.persuasionTechniques as Array<{ type: string; intensity: number; example: string }> | undefined;
  const emotionalArc = analysis.emotionalArc as Array<{ position: number; intensity: number; emotion: string }> | undefined;

  return `You are a Content Physics researcher analyzing a viral social media post at the deepest possible level. Your job is to extract the complete physics of WHY this post works — not what it does, but the invisible forces, state changes, and causal mechanisms that make it viral.

You have the post's full text and existing surface analysis. Go DEEPER than the surface. Find what no one has articulated before.

=== POST BODY (complete text — every slide, every word) ===
${atom.body || '[no body]'}

=== COMPLETE EXISTING ANALYSIS ===
Title: ${atom.title}
Format: ${analysis.swipeContentFormat || meta.contentSource || 'unknown'} | Platform: ${meta.contentSource || 'unknown'}
Hook Type: ${analysis.hookType || 'unknown'} | Hook Score: ${analysis.hookScore ?? 'N/A'}/10 | Hook Word Count: ${analysis.hookWordCount || 'N/A'}
Hook Text: "${analysis.hookText || ''}"
Hook Mechanism: ${analysis.hookMechanism || 'not analyzed'}
Hook Score Reason: ${analysis.hookScoreReason || 'not analyzed'}
Beat Fingerprint: ${analysis.beatFingerprint || 'not analyzed'}
${sections ? `Sections: ${sections.map(s => `${s.label} (${s.purpose}, ${s.emotion}, ${s.sizePercent}%)`).join(' | ')}` : ''}
Structural Recipe: ${analysis.structuralRecipe || 'not analyzed'}
Structure Complexity: ${analysis.structureComplexity ?? 'N/A'}
Framework Type: ${analysis.frameworkType || 'unknown'}
${emotionalArc ? `Emotional Arc: ${emotionalArc.map(p => `${p.emotion}@${(p.position * 100).toFixed(0)}%(${p.intensity.toFixed(1)})`).join(' → ')}` : ''}
Dominant Emotion: ${analysis.dominantEmotion || 'unknown'}
Sentiment Score: ${analysis.sentimentScore ?? 'N/A'}
${persuasion ? `Persuasion Techniques: ${persuasion.map(p => `${p.type}(${p.intensity.toFixed(1)}) — ${p.example}`).join('; ')}` : ''}
Voice Markers: ${(analysis.voiceMarkers as string[] || []).join(', ') || 'none'}
${analysis.likesCount ? `Engagement: ${analysis.likesCount} likes, ${analysis.viewsCount || 0} views, ${analysis.commentsCount || 0} comments, ${analysis.sharesCount || 0} shares` : ''}
${analysis.engagementRate ? `Engagement Rate: ${analysis.engagementRate}` : ''}

=== EXTRACT THE COMPLETE CONTENT PHYSICS ===

Analyze this post through 6 passes. Be specific about MECHANISMS — not just labels. For every quark you identify, explain WHAT in the text creates it and WHY that technique works.

PASS 1 — MICRO QUARKS (per slide):
For EVERY slide, extract:
1. SPEECH ACT — Name it AND describe the specific writing technique. How many words? What's included vs omitted? Why does THIS technique work for THIS act?
2. READER DELTA — Name 1-2 deltas AND identify the SPECIFIC TEXT MECHANISM that creates each (curiosity+: what question/what's withheld? tension+: what's at risk? trust+: what vulnerability/proof? identification+: what specific-yet-universal experience? surprise: what expectation broken? empathy+: what sensory detail simulated?)
   For slides with identification+: also identify the RESONANCE FREQUENCY — the specific detail that hits a mass unspoken experience. Specific enough to be vivid, universal enough that millions recognize it, unspoken enough that seeing it named feels like being seen. Name the frequency and estimate audience reach.
3. PROOF TYPE — If present: what type, WHY does that type fit here?
4. MOTIVATION — If decision/action: what PRESSURE makes it inevitable, not random?
5. COMPRESSION — If time skip: how large, what earns it, intrigue or confusion?

PASS 2 — MESO QUARKS (per slide pair):
For EVERY consecutive pair:
1. TRANSITION TYPE — Name the causal bridge + mechanism: what in slide N creates pressure that ONLY N+1 resolves?
2. INEVITABILITY TEST — Could you swap these slides unnoticed? Why/why not?
3. STATE CARRYOVER — What reader states carry from N to N+1?
4. DOUBLE HELIX — Does this have BOTH narrative causality (events chain) AND psychological causality (reader need chain) simultaneously?

PASS 3 — MACRO QUARKS:
1. ARC SHAPE — Map win/loss alternation. Where does fortune reverse? How many reversals?
2. TENSION CURVE — Where are peaks? Where does it breathe? Single peak, multiple, or sustained?
3. SPARSE/DENSE RHYTHM — Which slides sparse (raw emotion, few words), which dense (details/proof)?
4. INTERNAL/EXTERNAL TENSION — Does external success coexist with internal struggle? Where?

PASS 4 — RSV TRAJECTORY:
Trace the Reader State Vector at 5 boundaries (after slide 1, after ~slide 5, midpoint, most powerful moment, final slide):
For each: open loops (count + list), trust level, tension (level + type), pattern expectation, frame, energy balance.
Also for each boundary: SUPERPOSITION COUNT — how many simultaneous interpretations is the reader holding? (e.g., "success story AND cautionary tale AND love letter" = 3). The longer the superposition holds before collapsing at the phase transition, the more powerful the collapse. Note where the superposition collapses to a single interpretation.

PASS 5 — PHYSICS EVENTS:
1. SYMMETRY BREAK — What pattern do slides 1-5 establish? Which slide breaks it? What breaks? Why devastating?
2. PHASE TRANSITION — Where does the reader's FRAME shift? From what to what? How does it recontextualize?
3. ENERGY RESOLUTION — Is payoff proportional to buildup? Which loops close where? Any left open?
4. PEAK GRAVITY — Where are most loops active simultaneously? Coincides with transition?

PASS 6 — NOVEL DISCOVERIES:
What makes this post UNIQUELY effective beyond standard physics? Look for:
- Unusual transition types not in the standard list
- Unexpected quark combinations that create outsized impact
- Structural innovations (breaking "rules" that works)
- Audience psychology exploits specific to this niche/format
- Timing/rhythm patterns in revelation pacing
- Meta-narrative techniques
- Cultural resonance mechanisms (hitting unspoken societal frequencies)

ANTIMATTER: For every element that CREATES engagement, identify the anti-element that would DESTROY it with equal force. What specific phrase, structure, or move would annihilate the accumulated physics? A single "let that sink in" can destroy 10 slides of earned trust. An unearned flex cancels 15 slides of vulnerability. List the specific antimatter for THIS post — what must NEVER appear in a draft adapting this blueprint?

PASS 7 — LONG-RANGE QUARK INTERACTIONS:
Zoom out from individual slides and adjacent pairs. Look at how quarks ACROSS THE ENTIRE POST interact:
1. SETUP-PAYOFF BONDS: Map EVERY long-range bond — a detail planted on slide X that pays off on slide Y. An open loop from slide 1 that closes on slide 22. A character trait from slide 4 that makes slide 20's decision inevitable. [slide X → slide Y: planted what, harvested what, how many slides apart]
2. ECHO PATTERNS: Which quarks repeat at different positions with different emotional weight? Map every echo and how MEANING transforms with repetition.
3. INTERFERENCE EFFECTS: Where do multiple quark forces COMBINE to create something none creates alone? Find every point where compound forces produce emergent effects that no single quark explains.
4. ABSENCE AS FORCE: What is deliberately MISSING? Which omissions create curiosity (productive) vs confusion (destructive)? Map every deliberate omission and its effect.
5. CALLBACK CHAINS: Trace elements appearing 3+ times. How does each transform with each appearance?
6. ENTANGLEMENT PAIRS: For each long-range bond, test: if you REMOVED slide X, would slide Y collapse into meaninglessness? Truly entangled slides have NO independent meaning — they're a single quantum system separated by distance. List each entangled pair and what happens to each side if the other is removed.

PASS 8 — RHYTHM AND PACING:
Analyze the post as a WAVEFORM:
1. DENSITY WAVEFORM: Map word count per slide as a number sequence. Where does it accelerate vs decelerate? What rhythm?
2. ENERGY DYNAMICS: Rate energy 1-5 per slide. Map the curve. How does it interact with the tension curve?
3. INFORMATION RATE: New facts/details per slide. Where does the post starve the reader vs flood them?
4. SILENCE AND SPACE: Which slides are intentionally sparse? What function — decompression or held breath?
5. MOMENTUM MECHANICS: How does forward momentum work? Escalation, alternation, acceleration, mystery?

PASS 9 — COMPLETE READER SIMULATION:
For EVERY slide boundary (one entry per slide, not just 5), trace:
1. ACTIVE QUESTIONS: Every unresolved question in the reader's mind at this exact point.
2. BUILT ASSUMPTIONS: What the reader has assumed/inferred that was never stated.
3. PREDICTION: What the reader expects the next slide to be.
4. EMOTIONAL CHARGE: Dominant emotion right now. What caused any shift.
5. INVESTMENT LEVEL: How much the reader cares (low/medium/high/locked-in) and what built it.

PASS 10 — THE FABRIC:
You now have the complete physics from Passes 1-9. Synthesize EVERYTHING. Find what no single pass could reveal — emergent patterns visible only when you see ALL the physics together. How quarks interact across passes, how rhythm reinforces or fights quark physics, how long-range bonds create conditions for physics events, how the reader simulation reveals compound effects.
Write 500-1000 words of free-form synthesis. Cite specific slides, quarks, reader states from your findings. Every claim grounded in your data — but what you FIND is entirely up to you. Discover.

Output ONLY valid JSON matching this exact schema (no markdown, no explanation outside JSON):
{
  "version": 1,
  "slideQuarks": [{"slideNumber": 1, "text": "first 100 chars...", "speechAct": {"type": "...", "mechanism": "..."}, "readerDeltas": [{"type": "...", "mechanism": "..."}], "proofType": {"type": "...", "mechanism": "..."}, "motivation": {"type": "...", "mechanism": "..."}, "compression": {"type": "...", "size": "...", "mechanism": "..."}, "resonanceFrequency": {"detail": "...", "unspokenExperience": "...", "estimatedReach": "..."}}],
  "transitions": [{"from": 1, "to": 2, "type": "...", "mechanism": "...", "swapTestPasses": false, "doubleHelix": true, "doubleHelixDetail": "..."}],
  "arcQuarks": {"shape": "...", "winLossReversals": 0, "tensionPeaks": [], "sparseDensePattern": "...", "internalExternalTension": {"present": true, "peakSlide": 0, "description": "..."}},
  "rsv": {"trajectoryPoints": [{"afterSlide": 1, "openLoops": {"count": 1, "loops": ["..."]}, "trust": "low", "tension": {"level": "medium", "type": "external"}, "patternExpectation": "...", "frame": "...", "energyBalance": "charging", "superpositionCount": 2, "superpositions": ["success story", "love letter"]}]},
  "physicsEvents": {"symmetryBreak": {"slideNumber": 0, "patternEstablished": "...", "whatBreaks": "...", "whyDevastating": "..."}, "phaseTransition": {"slideNumber": 0, "frameBefore": "...", "frameAfter": "...", "recontextualization": "..."}, "energyResolution": {"proportional": true, "loopsClosed": [{"loop": "...", "closedAtSlide": 0}], "loopsUnclosed": [], "assessment": "..."}, "peakGravity": {"slideNumber": 0, "activeLoops": 0, "coincidesWithTransition": true}},
  "novelDiscoveries": ["..."],
  "longRangeInteractions": {
    "setupPayoffBonds": [{"setupSlide": 1, "payoffSlide": 22, "distance": 21, "planted": "...", "harvested": "..."}],
    "echoPatterns": [{"quarkType": "...", "positions": [1, 12, 24], "transformation": "..."}],
    "interferences": [{"slides": [3, 7, 11], "forces": ["trust+", "identification+", "tension+"], "emergentEffect": "..."}],
    "deliberateAbsences": [{"what": "...", "slides": [1, 2], "effect": "..."}],
    "callbackChains": [{"element": "...", "appearances": [{"slide": 1, "meaning": "..."}, {"slide": 24, "meaning": "..."}], "transformationArc": "..."}],
    "entanglementPairs": [{"slideA": 1, "slideB": 22, "ifARemoved": "...", "ifBRemoved": "..."}]
  },
  "rhythm": {
    "densityWaveform": [8, 12, 10, 6, 9],
    "energyCurve": [3, 2, 4, 5, 3],
    "informationRate": [1, 2, 1, 0, 3],
    "silenceSlides": [5, 16],
    "momentumMechanism": "...",
    "pacingPattern": "..."
  },
  "readerSimulation": [{"afterSlide": 1, "activeQuestions": ["..."], "builtAssumptions": ["..."], "prediction": "...", "dominantEmotion": "...", "investmentLevel": "low"}],
  "antimatter": ["specific phrase/structure/move that would destroy this post's physics..."],
  "deepFabric": "500-1000 words of emergent synthesis citing specific slides, quarks, and reader states from all passes..."
}`;
}

// ============================================================
// Extract Quark Profile for a Single Swipe
// ============================================================

export async function extractQuarkProfile(atom: Atom): Promise<QuarkProfile | null> {
  // Always use OpenRouter for extraction — direct Anthropic fetch fails on Railway
  const useDirectAnthropic = false;
  const apiKey = config.openRouterApiKey || config.anthropicApiKey;
  if (!apiKey) {
    console.log(`  ❌ Quark extraction: no API key configured (neither ANTHROPIC_API_KEY nor OPENROUTER_API_KEY)`);
    return null;
  }

  const prompt = buildExtractionPrompt(atom);
  console.log(`  🔬 Extracting quarks for "${atom.title?.substring(0, 60)}" (${(atom.body || '').length} chars body) [${useDirectAnthropic ? 'direct Anthropic' : 'OpenRouter'}]...`);

  const model = useDirectAnthropic ? 'claude-sonnet-4-6' : 'anthropic/claude-sonnet-4-6';
  const apiUrl = useDirectAnthropic ? 'https://api.anthropic.com/v1/messages' : 'https://openrouter.ai/api/v1/chat/completions';

  // Build request based on provider
  const requestBody = useDirectAnthropic ? {
    model,
    system: [{ type: 'text', text: 'You are a Content Physics researcher. Output ONLY valid JSON. No markdown, no explanation outside the JSON object.' }],
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 32768,
    temperature: 0.2,
  } : {
    model,
    messages: [
      { role: 'system', content: 'You are a Content Physics researcher. Output ONLY valid JSON. No markdown, no explanation outside the JSON object.' },
      { role: 'user', content: prompt },
    ],
    max_tokens: 32768,
    temperature: 0.2,
  };

  const headers: Record<string, string> = useDirectAnthropic ? {
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
  } : {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${apiKey}`,
  };

  const MAX_RETRIES = 3;
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const response = await fetch(apiUrl, {
        method: 'POST',
        headers,
        body: JSON.stringify(requestBody),
        signal: AbortSignal.timeout(600_000), // 10 min timeout (Opus can be slow)
      });

      if (response.status === 429) {
        const retryAfter = response.headers.get('retry-after');
        const waitMs = retryAfter ? Math.ceil(parseFloat(retryAfter) * 1000) : 60_000;
        console.log(`  ⚠️ Rate limited — waiting ${(waitMs / 1000).toFixed(0)}s (attempt ${attempt + 1}/${MAX_RETRIES})`);
        await new Promise(r => setTimeout(r, waitMs));
        continue;
      }

      if (!response.ok) {
        const errText = await response.text();
        console.log(`  ❌ API error ${response.status}: ${errText.substring(0, 200)}`);
        if (attempt < MAX_RETRIES - 1) {
          await new Promise(r => setTimeout(r, (attempt + 1) * 5000));
          continue;
        }
        return null;
      }

      const data = await response.json() as any;

      // Extract text from response (Anthropic vs OpenRouter format)
      let rawText: string | undefined;
      if (useDirectAnthropic) {
        const textBlock = data.content?.find((c: any) => c.type === 'text');
        rawText = textBlock?.text;
      } else {
        rawText = data.choices?.[0]?.message?.content;
      }

      if (!rawText) {
        console.log(`  ❌ No text in response`);
        return null;
      }

      // Parse JSON from response (strip any markdown fences if model wraps them)
      let jsonText = rawText.trim();
      if (jsonText.startsWith('```')) {
        jsonText = jsonText.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
      }

      // Attempt JSON parse with repair for common LLM output issues
      let profile: QuarkProfile;
      try {
        profile = JSON.parse(jsonText);
      } catch (parseErr: any) {
        console.log(`  ⚠️ JSON parse failed at position ${parseErr.message.match(/position (\d+)/)?.[1] || '?'}, attempting repair...`);
        // Try to salvage: truncate at the last valid closing brace
        const lastBrace = jsonText.lastIndexOf('}');
        if (lastBrace > 0) {
          // Count open vs close braces to find a balanced cut point
          let depth = 0;
          let cutPoint = -1;
          for (let i = 0; i < jsonText.length; i++) {
            if (jsonText[i] === '{') depth++;
            if (jsonText[i] === '}') { depth--; if (depth === 0) { cutPoint = i; } }
          }
          if (cutPoint > 0) {
            const repaired = jsonText.substring(0, cutPoint + 1);
            try {
              profile = JSON.parse(repaired);
              console.log(`  ✅ JSON repaired by truncating at balanced brace (${repaired.length} chars of ${jsonText.length})`);
            } catch {
              console.log(`  ❌ JSON repair failed. Raw length: ${jsonText.length}, last 100 chars: ${jsonText.slice(-100)}`);
              return null;
            }
          } else {
            console.log(`  ❌ No balanced brace found. Raw length: ${jsonText.length}`);
            return null;
          }
        } else {
          console.log(`  ❌ No closing brace in response. Raw length: ${jsonText.length}`);
          return null;
        }
      }

      profile.extractedAt = new Date().toISOString();
      profile.extractedBy = 'claude-opus-4-6';
      profile.version = 1;

      const usage = data.usage || data.choices?.[0]?.usage;
      if (usage) {
        const inputTokens = usage.input_tokens || usage.prompt_tokens || 0;
        const outputTokens = usage.output_tokens || usage.completion_tokens || 0;
        console.log(`  🔬 Extraction complete: ${inputTokens} input, ${outputTokens} output tokens [${useDirectAnthropic ? 'Anthropic' : 'OpenRouter'}]`);
      }

      return profile;
    } catch (err: any) {
      console.log(`  ❌ Extraction error (attempt ${attempt + 1}): ${err.message}`);
      if (attempt < MAX_RETRIES - 1) {
        await new Promise(r => setTimeout(r, (attempt + 1) * 5000));
        continue;
      }
      return null;
    }
  }

  return null;
}

// ============================================================
// Build QuarkSummary from Full Profile (compact for Block 3A)
// ============================================================

export function buildQuarkSummary(profile: QuarkProfile): QuarkSummary {
  // Dominant speech acts — count frequency across all slides
  const actCounts: Record<string, number> = {};
  for (const sq of profile.slideQuarks) {
    const act = sq.speechAct.type;
    actCounts[act] = (actCounts[act] || 0) + 1;
  }
  const dominantSpeechActs = Object.entries(actCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([act]) => act);

  return {
    dominantSpeechActs,
    arcShape: profile.arcQuarks.shape,
    symmetryBreakSlide: profile.physicsEvents.symmetryBreak.slideNumber,
    phaseTransition: profile.physicsEvents.phaseTransition.frameBefore && profile.physicsEvents.phaseTransition.frameAfter
      ? `${profile.physicsEvents.phaseTransition.frameBefore} → ${profile.physicsEvents.phaseTransition.frameAfter}`
      : undefined,
    peakGravityLoops: profile.physicsEvents.peakGravity.activeLoops,
    novelDiscoveries: (profile.novelDiscoveries || []).slice(0, 2),
  };
}

// ============================================================
// Batch Extraction
// ============================================================

export async function batchExtractAll(options: { reExtractAll?: boolean } = {}): Promise<{
  total: number;
  extracted: number;
  skipped: number;
  failed: string[];
  cost: { inputTokens: number; outputTokens: number };
}> {
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const swipes = allAtoms.filter(a =>
    a.metadata?.isSwipeFile &&
    a.body &&
    a.body.length > 50 &&
    (a.structured?.swipeAnalysis?.hookType || a.structured?.swipeAnalysis?.beatFingerprint)
  );

  console.log(`\n  🔬 ═══ CONTENT PHYSICS BATCH EXTRACTION ═══`);
  console.log(`  🔬 Found ${swipes.length} analyzed swipes`);

  const results = { total: swipes.length, extracted: 0, skipped: 0, failed: [] as string[], cost: { inputTokens: 0, outputTokens: 0 } };

  for (let i = 0; i < swipes.length; i++) {
    const atom = swipes[i];
    const hasProfile = !!atom.structured?.contentPhysics?.version;

    if (hasProfile && !options.reExtractAll) {
      results.skipped++;
      continue;
    }

    console.log(`\n  🔬 [${i + 1}/${swipes.length}] Extracting: "${atom.title?.substring(0, 50)}"...`);

    const profile = await extractQuarkProfile(atom);
    if (profile) {
      // Store profile in atom
      const existing = atom.structured || {};
      await updateAtom(atom.uuid, {
        structured: { ...existing, contentPhysics: profile },
      });
      results.extracted++;
      console.log(`  ✅ Extracted: ${profile.slideQuarks.length} slides, ${profile.transitions.length} transitions, ${profile.novelDiscoveries.length} discoveries`);
    } else {
      results.failed.push(atom.uuid);
      console.log(`  ❌ Failed: ${atom.uuid}`);
    }

    // Rate limit courtesy — 2s between calls
    if (i < swipes.length - 1) {
      await new Promise(r => setTimeout(r, 2000));
    }
  }

  console.log(`\n  🔬 ═══ BATCH EXTRACTION COMPLETE ═══`);
  console.log(`  🔬 Extracted: ${results.extracted}, Skipped: ${results.skipped}, Failed: ${results.failed.length}`);

  return results;
}
