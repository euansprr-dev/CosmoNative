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

Output ONLY valid JSON matching this exact schema (no markdown, no explanation outside JSON):
{
  "version": 1,
  "slideQuarks": [{"slideNumber": 1, "text": "first 100 chars...", "speechAct": {"type": "...", "mechanism": "..."}, "readerDeltas": [{"type": "...", "mechanism": "..."}], "proofType": {"type": "...", "mechanism": "..."}, "motivation": {"type": "...", "mechanism": "..."}, "compression": {"type": "...", "size": "...", "mechanism": "..."}}],
  "transitions": [{"from": 1, "to": 2, "type": "...", "mechanism": "...", "swapTestPasses": false, "doubleHelix": true, "doubleHelixDetail": "..."}],
  "arcQuarks": {"shape": "...", "winLossReversals": 0, "tensionPeaks": [], "sparseDensePattern": "...", "internalExternalTension": {"present": true, "peakSlide": 0, "description": "..."}},
  "rsv": {"trajectoryPoints": [{"afterSlide": 1, "openLoops": {"count": 1, "loops": ["..."]}, "trust": "low", "tension": {"level": "medium", "type": "external"}, "patternExpectation": "...", "frame": "...", "energyBalance": "charging"}]},
  "physicsEvents": {"symmetryBreak": {"slideNumber": 0, "patternEstablished": "...", "whatBreaks": "...", "whyDevastating": "..."}, "phaseTransition": {"slideNumber": 0, "frameBefore": "...", "frameAfter": "...", "recontextualization": "..."}, "energyResolution": {"proportional": true, "loopsClosed": [{"loop": "...", "closedAtSlide": 0}], "loopsUnclosed": [], "assessment": "..."}, "peakGravity": {"slideNumber": 0, "activeLoops": 0, "coincidesWithTransition": true}},
  "novelDiscoveries": ["..."]
}`;
}

// ============================================================
// Extract Quark Profile for a Single Swipe
// ============================================================

export async function extractQuarkProfile(atom: Atom): Promise<QuarkProfile | null> {
  const apiKey = config.anthropicApiKey;
  if (!apiKey) {
    console.log(`  ❌ Quark extraction: no Anthropic API key configured`);
    return null;
  }

  const prompt = buildExtractionPrompt(atom);
  console.log(`  🔬 Extracting quarks for "${atom.title?.substring(0, 60)}" (${(atom.body || '').length} chars body)...`);

  const body = {
    model: 'claude-opus-4-6',
    system: [{ type: 'text', text: 'You are a Content Physics researcher. Output ONLY valid JSON. No markdown, no explanation outside the JSON object.' }],
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 16384,
    temperature: 0.2,
  };

  const MAX_RETRIES = 3;
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify(body),
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
        console.log(`  ❌ Anthropic error ${response.status}: ${errText.substring(0, 200)}`);
        if (attempt < MAX_RETRIES - 1) {
          await new Promise(r => setTimeout(r, (attempt + 1) * 5000));
          continue;
        }
        return null;
      }

      const data = await response.json() as any;
      const textBlock = data.content?.find((c: any) => c.type === 'text');
      if (!textBlock?.text) {
        console.log(`  ❌ No text in response`);
        return null;
      }

      // Parse JSON from response (strip any markdown fences if model wraps them)
      let jsonText = textBlock.text.trim();
      if (jsonText.startsWith('```')) {
        jsonText = jsonText.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
      }

      const profile: QuarkProfile = JSON.parse(jsonText);
      profile.extractedAt = new Date().toISOString();
      profile.extractedBy = 'claude-opus-4-6';
      profile.version = 1;

      const usage = data.usage;
      if (usage) {
        console.log(`  🔬 Extraction complete: ${usage.input_tokens} input, ${usage.output_tokens} output tokens`);
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
  const allAtoms = await fetchAllByType('research', 500);
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
