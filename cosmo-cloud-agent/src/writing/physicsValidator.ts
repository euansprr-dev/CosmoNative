// cosmo-cloud-agent/src/writing/physicsValidator.ts
// Content Physics execution layer — maps blueprint physics to targets,
// extracts physics from drafts, validates against targets.

import { config } from '../config';
import { QuarkProfile, PhysicsTarget, DraftPhysicsExtraction, PhysicsValidationResult } from './types';

// ============================================================
// 1. Map Blueprint Physics to Per-Slide Targets (deterministic)
// ============================================================

/**
 * Deterministically map a blueprint's quark profile to per-slide physics targets.
 * No LLM call. Directly reads the profile's extracted data.
 *
 * When targetSlideCount differs from the blueprint's slide count, targets are
 * scaled proportionally (nearest-neighbor mapping).
 */
export function mapBlueprintPhysicsToTargets(
  profile: QuarkProfile,
  targetSlideCount: number,
): PhysicsTarget[] {
  const bpSlideCount = profile.slideQuarks.length;
  if (bpSlideCount === 0) return [];

  const targets: PhysicsTarget[] = [];

  for (let targetIdx = 0; targetIdx < targetSlideCount; targetIdx++) {
    // Map target slide index to blueprint slide index (proportional scaling)
    const bpIdx = Math.min(
      Math.round((targetIdx / Math.max(targetSlideCount - 1, 1)) * (bpSlideCount - 1)),
      bpSlideCount - 1,
    );
    const sq = profile.slideQuarks[bpIdx];
    const transition = profile.transitions.find(t => t.from === sq.slideNumber);
    const rsvPoint = findNearestRSVPoint(profile, sq.slideNumber);

    targets.push({
      speechAct: sq.speechAct?.type || 'unknown',
      readerDeltas: (sq.readerDeltas || []).map(d => d.type).filter(Boolean),
      frame: sq.frame?.type || 'unknown',
      experientialDistance: normalizeDistance(sq.experientialDistance?.level || sq.experientialDistance?.mechanism),
      proofType: sq.proofType?.type,
      motivation: sq.motivation?.type,
      compression: sq.compression?.type,
      transitionToNext: transition?.type || 'unspecified',
      rsvAfter: {
        openLoops: rsvPoint?.openLoops?.count ?? 0,
        trust: normalizeTrust(rsvPoint?.trust),
        tension: normalizeTension(rsvPoint?.tension?.level),
        frame: rsvPoint?.frame || 'unknown',
        energyBalance: normalizeEnergy(rsvPoint?.energyBalance),
      },
    });
  }

  return targets;
}

function findNearestRSVPoint(profile: QuarkProfile, slideNumber: number): any {
  if (!profile.rsv?.trajectoryPoints?.length) return null;
  let nearest = profile.rsv.trajectoryPoints[0];
  for (const pt of profile.rsv.trajectoryPoints) {
    if (pt.afterSlide <= slideNumber) nearest = pt;
    else break;
  }
  return nearest;
}

function normalizeDistance(value: string | undefined): 'zero' | 'near' | 'far' {
  if (!value) return 'near';
  const lower = value.toLowerCase();
  if (lower.includes('zero') || lower.includes('inside') || lower.includes('sensory')) return 'zero';
  if (lower.includes('far') || lower.includes('report') || lower.includes('formal')) return 'far';
  return 'near';
}

function normalizeTrust(value: string | undefined): 'low' | 'building' | 'high' | 'maxed' {
  if (!value) return 'building';
  const lower = value.toLowerCase();
  if (lower.includes('max')) return 'maxed';
  if (lower.includes('high') || lower.includes('earned')) return 'high';
  if (lower.includes('low') || lower.includes('minimal')) return 'low';
  return 'building';
}

function normalizeTension(value: string | undefined): 'low' | 'medium' | 'high' | 'peak' {
  if (!value) return 'medium';
  const lower = value.toLowerCase();
  if (lower.includes('peak') || lower.includes('maximum')) return 'peak';
  if (lower.includes('high') || lower.includes('strong')) return 'high';
  if (lower.includes('low') || lower.includes('minimal') || lower.includes('none')) return 'low';
  return 'medium';
}

function normalizeEnergy(value: string | undefined): 'charging' | 'peak' | 'discharging' | 'resolved' {
  if (!value) return 'charging';
  const lower = value.toLowerCase();
  if (lower.includes('resolv') || lower.includes('released') || lower.includes('complete')) return 'resolved';
  if (lower.includes('discharg') || lower.includes('releasing') || lower.includes('falling')) return 'discharging';
  if (lower.includes('peak') || lower.includes('maximum') || lower.includes('full')) return 'peak';
  return 'charging';
}

// ============================================================
// 2. Extract Draft Physics (single Sonnet API call)
// ============================================================

/**
 * Run a lightweight physics extraction on a draft.
 * Single Sonnet call — extracts per-slide physics, transitions, open loops,
 * symmetry break, phase transition, arc shape.
 *
 * Targets are provided as reference so the model can do gap analysis.
 */
export async function extractDraftPhysics(
  draftText: string,
  targets: PhysicsTarget[],
): Promise<DraftPhysicsExtraction> {
  // Parse slides from draft
  const slides = parseDraftSlides(draftText);
  if (slides.length === 0) {
    return emptyExtraction();
  }

  const targetsSummary = targets.map((t, i) => (
    `Slide ${i + 1}: speechAct=${t.speechAct}, frame=${t.frame}, dist=${t.experientialDistance}, deltas=[${t.readerDeltas.join(',')}], transition→next=${t.transitionToNext}`
  )).join('\n');

  const slidesText = slides.map((s, i) => `--- Slide ${i + 1} ---\n${s}`).join('\n\n');

  const prompt = `Analyze this content draft's ACTUAL physics — what the text produces in the reader's mind, not what was intended.

DRAFT:
${slidesText}

TARGET PHYSICS (from blueprint — compare against these):
${targetsSummary}

Extract the ACTUAL physics. Output ONLY valid JSON matching this exact schema:
{
  "slides": [{"slideNumber": 1, "speechAct": "string", "frame": "string", "experientialDistance": "zero|near|far", "readerDeltas": ["string"]}],
  "transitions": [{"from": 1, "to": 2, "type": "string", "swapTestPasses": true/false}],
  "openLoops": {
    "opened": ["question string"],
    "closed": [{"loop": "string", "closedAtSlide": 1}],
    "unclosed": ["string"]
  },
  "symmetryBreak": {"detected": true/false, "slideNumber": null or number, "description": "string"},
  "phaseTransition": {"detected": true/false, "slideNumber": null or number, "frameBefore": "string", "frameAfter": "string"},
  "peakGravitySlide": null or number,
  "arcShape": "3-5 word description"
}

Rules:
- speechAct: what each slide IS DOING (confession, proof, evidence, reframe, tutorial, declaration, etc)
- frame: how it POSITIONS content (loss, success, decision, consequence, observation, setup, transformation)
- experientialDistance: zero=inside moment/sensory, near=telling friend/vivid, far=reporting/formal
- readerDeltas: what CHANGES in reader (curiosity+, trust+, tension+, empathy+, identification+, surprise, fear+, desire+)
- transitions: causal bridge type (escalation, deflation, doubt→reaffirmation, reason→action, etc)
- swapTestPasses: true means slides COULD swap unnoticed (weak transition)
- openLoops: questions raised in reader's mind. Track where opened and where closed.`;

  try {
    const response = await callPhysicsExtraction(prompt);
    const parsed = JSON.parse(response);
    return {
      slides: parsed.slides || [],
      transitions: parsed.transitions || [],
      openLoops: parsed.openLoops || { opened: [], closed: [], unclosed: [] },
      symmetryBreak: parsed.symmetryBreak || { detected: false, slideNumber: null, description: '' },
      phaseTransition: parsed.phaseTransition || { detected: false, slideNumber: null, frameBefore: '', frameAfter: '' },
      peakGravitySlide: parsed.peakGravitySlide ?? null,
      arcShape: parsed.arcShape || 'unknown',
    };
  } catch (err) {
    console.error('  ⚠️ Physics extraction failed:', err);
    return emptyExtraction();
  }
}

function parseDraftSlides(draft: string): string[] {
  try {
    const parsed = JSON.parse(draft);
    if (parsed.slides && Array.isArray(parsed.slides)) {
      return parsed.slides.map((s: any) => String(typeof s === 'string' ? s : s.text || ''));
    }
    if (parsed.tweets && Array.isArray(parsed.tweets)) {
      return parsed.tweets.map((t: any) => String(typeof t === 'string' ? t : t.text || t.content || ''));
    }
  } catch {}

  if (/^Slide \d+/im.test(draft)) {
    const matches = [...draft.matchAll(/^Slide \d+[^\n]*\n([\s\S]*?)(?=^Slide \d+[^\n]*\n|$)/gim)];
    if (matches.length > 0) return matches.map(m => (m[1] || '').trim());
  }

  return draft.split(/\n{2,}/).filter(p => p.trim().length > 10).map(p => p.trim());
}

function emptyExtraction(): DraftPhysicsExtraction {
  return {
    slides: [],
    transitions: [],
    openLoops: { opened: [], closed: [], unclosed: [] },
    symmetryBreak: { detected: false, slideNumber: null, description: '' },
    phaseTransition: { detected: false, slideNumber: null, frameBefore: '', frameAfter: '' },
    peakGravitySlide: null,
    arcShape: 'unknown',
  };
}

async function callPhysicsExtraction(prompt: string): Promise<string> {
  const apiKey = config.anthropicApiKey || process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('No Anthropic API key configured');

  const model = config.models?.strategist || 'claude-sonnet-4-20250514';

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model,
      max_tokens: 2500,
      messages: [{ role: 'user', content: prompt }],
    }),
  });

  if (!response.ok) {
    throw new Error(`Physics extraction API error: ${response.status} ${response.statusText}`);
  }

  const data = await response.json() as any;
  const text = data.content?.[0]?.text || '';

  // Extract JSON from response (may be wrapped in markdown code block)
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error('No JSON found in physics extraction response');
  return jsonMatch[0];
}

// ============================================================
// 3. Validate Draft Physics Against Targets (deterministic)
// ============================================================

/**
 * Compare extracted draft physics against target physics.
 * Pure deterministic — no LLM call.
 *
 * Returns blocking violations (force rewrite) and advisory violations (feedback).
 */
export function validatePhysics(
  extraction: DraftPhysicsExtraction,
  targets: PhysicsTarget[],
  blueprintProfile: QuarkProfile | null,
): PhysicsValidationResult {
  const perSlideViolations: PhysicsValidationResult['perSlideViolations'] = [];
  const transitionViolations: PhysicsValidationResult['transitionViolations'] = [];
  const conservationViolations: PhysicsValidationResult['conservationViolations'] = [];
  const eventViolations: PhysicsValidationResult['eventViolations'] = [];

  // --- Per-slide physics comparison ---
  const maxSlides = Math.min(extraction.slides.length, targets.length);
  for (let i = 0; i < maxSlides; i++) {
    const actual = extraction.slides[i];
    const target = targets[i];
    if (!actual || !target) continue;

    // Experiential distance: target=zero but actual=far is BLOCKING (empathy killer)
    if (target.experientialDistance === 'zero' && actual.experientialDistance === 'far') {
      perSlideViolations.push({
        slideNumber: actual.slideNumber,
        field: 'experientialDistance',
        target: 'zero (inside the moment, sensory)',
        actual: 'far (reporting/formal voice)',
        severity: 'blocking',
        message: `Slide ${actual.slideNumber}: Target distance is ZERO (reader should feel inside the moment) but draft reads as FAR (reporting voice). Rewrite to place reader IN the scene — use sensory details, present tense, no explanation.`,
      });
    } else if (target.experientialDistance !== actual.experientialDistance && target.experientialDistance !== 'near') {
      perSlideViolations.push({
        slideNumber: actual.slideNumber,
        field: 'experientialDistance',
        target: target.experientialDistance,
        actual: actual.experientialDistance,
        severity: 'advisory',
        message: `Slide ${actual.slideNumber}: Distance mismatch — target "${target.experientialDistance}" but reads as "${actual.experientialDistance}". Study the blueprint's equivalent slide for the right distance.`,
      });
    }

    // Speech act mismatch
    if (target.speechAct !== 'unknown' && actual.speechAct &&
        !actual.speechAct.toLowerCase().includes(target.speechAct.toLowerCase()) &&
        !target.speechAct.toLowerCase().includes(actual.speechAct.toLowerCase())) {
      perSlideViolations.push({
        slideNumber: actual.slideNumber,
        field: 'speechAct',
        target: target.speechAct,
        actual: actual.speechAct,
        severity: 'advisory',
        message: `Slide ${actual.slideNumber}: Speech act — target "${target.speechAct}" but reads as "${actual.speechAct}".`,
      });
    }

    // Frame mismatch
    if (target.frame !== 'unknown' && actual.frame &&
        !actual.frame.toLowerCase().includes(target.frame.toLowerCase()) &&
        !target.frame.toLowerCase().includes(actual.frame.toLowerCase())) {
      perSlideViolations.push({
        slideNumber: actual.slideNumber,
        field: 'frame',
        target: target.frame,
        actual: actual.frame,
        severity: 'advisory',
        message: `Slide ${actual.slideNumber}: Frame — target "${target.frame}" but reads as "${actual.frame}".`,
      });
    }
  }

  // --- Transition comparison ---
  const maxTransitions = Math.min(extraction.transitions.length, targets.length - 1);
  for (let i = 0; i < maxTransitions; i++) {
    const actual = extraction.transitions[i];
    const target = targets[i];
    if (!actual || !target?.transitionToNext || target.transitionToNext === 'unspecified') continue;

    if (!actual.type.toLowerCase().includes(target.transitionToNext.toLowerCase()) &&
        !target.transitionToNext.toLowerCase().includes(actual.type.toLowerCase())) {
      transitionViolations.push({
        from: actual.from,
        to: actual.to,
        target: target.transitionToNext,
        actual: actual.type,
        message: `Slides ${actual.from}→${actual.to}: Transition — target "${target.transitionToNext}" but reads as "${actual.type}".`,
      });
    }

    if (actual.swapTestPasses) {
      transitionViolations.push({
        from: actual.from,
        to: actual.to,
        target: 'causal (can\'t swap)',
        actual: 'swappable',
        message: `Slides ${actual.from}→${actual.to}: Weak transition — these slides could swap unnoticed. Add a causal bridge.`,
      });
    }
  }

  // --- Conservation law checks ---
  const unclosedCount = extraction.openLoops.unclosed?.length ?? 0;
  if (unclosedCount >= 3) {
    conservationViolations.push({
      type: 'unclosed_loops',
      severity: 'blocking',
      message: `${unclosedCount} open loops never closed — the reader finishes with unresolved questions.`,
      details: extraction.openLoops.unclosed.slice(0, 5),
    });
  } else if (unclosedCount >= 1) {
    conservationViolations.push({
      type: 'unclosed_loops',
      severity: 'advisory',
      message: `${unclosedCount} open loop(s) unclosed — consider if intentional (driving CTA action) or oversight.`,
      details: extraction.openLoops.unclosed,
    });
  }

  // --- Physics event checks ---
  const bpHasSymmetryBreak = blueprintProfile?.physicsEvents?.symmetryBreak?.slideNumber &&
    blueprintProfile.physicsEvents.symmetryBreak.slideNumber > 0;
  const bpHasPhaseTransition = blueprintProfile?.physicsEvents?.phaseTransition?.slideNumber &&
    blueprintProfile.physicsEvents.phaseTransition.slideNumber > 0;

  if (bpHasSymmetryBreak && !extraction.symmetryBreak.detected) {
    eventViolations.push({
      type: 'symmetry_break',
      severity: 'blocking',
      message: `Blueprint has a symmetry break but none detected in draft. The established pattern must break at a pivotal moment.`,
    });
  } else if (bpHasSymmetryBreak && extraction.symmetryBreak.detected) {
    // Check position alignment
    const bpBreakPct = blueprintProfile!.physicsEvents.symmetryBreak.slideNumber / blueprintProfile!.slideQuarks.length;
    const draftBreakPct = extraction.symmetryBreak.slideNumber! / extraction.slides.length;
    if (Math.abs(bpBreakPct - draftBreakPct) > 0.2) {
      eventViolations.push({
        type: 'symmetry_break',
        severity: 'advisory',
        message: `Symmetry break position: blueprint at ${Math.round(bpBreakPct * 100)}%, draft at ${Math.round(draftBreakPct * 100)}%. Consider aligning closer to blueprint.`,
      });
    }
  }

  if (bpHasPhaseTransition && !extraction.phaseTransition.detected) {
    eventViolations.push({
      type: 'phase_transition',
      severity: 'blocking',
      message: `Blueprint has a phase transition (reader's frame shifts) but none detected in draft. The reader must experience a qualitative shift in what they think they're reading.`,
    });
  }

  // --- Score calculation ---
  const totalViolations = perSlideViolations.length + transitionViolations.length +
    conservationViolations.length + eventViolations.length;
  const blockingCount = [...perSlideViolations, ...conservationViolations, ...eventViolations]
    .filter((v: any) => v.severity === 'blocking').length;
  const score = Math.max(0, 100 - (blockingCount * 20) - (totalViolations * 5));

  // --- Format violations ---
  const formattedViolations = formatPhysicsViolations({
    overallScore: score,
    perSlideViolations,
    transitionViolations,
    conservationViolations,
    eventViolations,
  });

  return {
    overallScore: score,
    perSlideViolations,
    transitionViolations,
    conservationViolations,
    eventViolations,
    formattedViolations,
  };
}

// ============================================================
// 4. Format Violations for Prompt Injection
// ============================================================

function formatPhysicsViolations(result: Omit<PhysicsValidationResult, 'formattedViolations'>): string {
  const allBlocking = [
    ...result.perSlideViolations.filter(v => v.severity === 'blocking'),
    ...result.conservationViolations.filter(v => v.severity === 'blocking'),
    ...result.eventViolations.filter(v => v.severity === 'blocking'),
  ];
  const allAdvisory = [
    ...result.perSlideViolations.filter(v => v.severity === 'advisory'),
    ...result.transitionViolations,
    ...result.conservationViolations.filter(v => v.severity === 'advisory'),
    ...result.eventViolations.filter(v => v.severity === 'advisory'),
  ];

  if (allBlocking.length === 0 && allAdvisory.length === 0) return '';

  const lines: string[] = [];
  lines.push(`═══ CONTENT PHYSICS ANALYSIS (score: ${result.overallScore}/100) ═══`);

  if (allBlocking.length > 0) {
    lines.push('');
    lines.push('BLOCKING (must fix before presenting):');
    for (const v of allBlocking) {
      lines.push(`  [BLOCKING] ${v.message}`);
      if ('details' in v && (v as any).details?.length) {
        for (const d of (v as any).details) {
          lines.push(`    - "${d}"`);
        }
      }
    }
  }

  if (allAdvisory.length > 0) {
    lines.push('');
    lines.push('ADVISORY (address in self-edit where possible):');
    for (const v of allAdvisory) {
      lines.push(`  [advisory] ${v.message}`);
    }
  }

  return lines.join('\n');
}
