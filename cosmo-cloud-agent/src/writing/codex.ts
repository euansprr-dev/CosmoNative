// cosmo-cloud-agent/src/writing/codex.ts
// Content Physics Codex — Aggregates quark profiles from all swipes into statistical laws
// Pure computation, no LLM calls. Recomputed after each new extraction.

import { Atom, fetchAllByType, updateAtom, fetchAtom } from '../db/queries';
import { QuarkProfile } from './types';

// ============================================================
// Codex Atom ID (dedicated atom for storing the codex)
// ============================================================

const CODEX_ATOM_TYPE = 'research'; // Reuse research type with a codex flag in metadata

// ============================================================
// Compute Content Physics Codex from All Extracted Profiles
// ============================================================

export async function computeCodex(): Promise<{ codexText: string; stats: CodexStats }> {
  // Fetch all swipes with extracted quark profiles
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const profiledSwipes = allAtoms.filter(a =>
    a.metadata?.isSwipeFile &&
    a.structured?.contentPhysics?.version
  );

  console.log(`  📊 Computing codex from ${profiledSwipes.length} extracted profiles...`);

  if (profiledSwipes.length < 3) {
    return {
      codexText: `Content Physics Codex — Insufficient data (${profiledSwipes.length} profiles extracted, minimum 3 required)`,
      stats: { totalProfiles: profiledSwipes.length } as CodexStats,
    };
  }

  const profiles = profiledSwipes.map(a => ({
    profile: a.structured!.contentPhysics as QuarkProfile,
    title: a.title,
    hookScore: a.structured?.swipeAnalysis?.hookScore ?? 0,
    format: a.structured?.swipeAnalysis?.swipeContentFormat || a.metadata?.contentSource || 'unknown',
    detectedFormat: classifyFormatFromBody(a.body || ''),
  }));

  // === TRANSITION PHYSICS ===
  const transitionsByPosition = new Map<string, Map<string, number>>(); // position → type → count
  const transitionsByScore = { high: new Map<string, number>(), low: new Map<string, number>() };

  for (const { profile, hookScore } of profiles) {
    for (const t of profile.transitions) {
      const posKey = positionBucket(t.from, profile.slideQuarks.length);
      if (!transitionsByPosition.has(posKey)) transitionsByPosition.set(posKey, new Map());
      const posMap = transitionsByPosition.get(posKey)!;
      posMap.set(t.type, (posMap.get(t.type) || 0) + 1);

      const scoreMap = hookScore >= 8 ? transitionsByScore.high : hookScore <= 6 ? transitionsByScore.low : null;
      if (scoreMap) scoreMap.set(t.type, (scoreMap.get(t.type) || 0) + 1);
    }
  }

  // === SPEECH ACT PHYSICS ===
  const speechActsByPosition = new Map<string, Map<string, number>>();
  const speechActsByScore = { high: new Map<string, number>(), low: new Map<string, number>() };

  for (const { profile, hookScore } of profiles) {
    for (const sq of profile.slideQuarks) {
      const posKey = positionBucket(sq.slideNumber, profile.slideQuarks.length);
      if (!speechActsByPosition.has(posKey)) speechActsByPosition.set(posKey, new Map());
      const posMap = speechActsByPosition.get(posKey)!;
      posMap.set(sq.speechAct.type, (posMap.get(sq.speechAct.type) || 0) + 1);

      const scoreMap = hookScore >= 8 ? speechActsByScore.high : hookScore <= 6 ? speechActsByScore.low : null;
      if (scoreMap) scoreMap.set(sq.speechAct.type, (scoreMap.get(sq.speechAct.type) || 0) + 1);
    }
  }

  // === READER DELTA PHYSICS ===
  const deltasByPosition = new Map<string, Map<string, number>>();
  let totalMidpointLoops = 0;
  let totalTransitionLoops = 0;
  let transitionLoopCount = 0;
  const loopsByScore = { high4plus: { count: 0, totalScore: 0 }, low4: { count: 0, totalScore: 0 } };

  for (const { profile, hookScore } of profiles) {
    for (const sq of profile.slideQuarks) {
      const posKey = positionBucket(sq.slideNumber, profile.slideQuarks.length);
      if (!deltasByPosition.has(posKey)) deltasByPosition.set(posKey, new Map());
      const posMap = deltasByPosition.get(posKey)!;
      for (const d of sq.readerDeltas) {
        posMap.set(d.type, (posMap.get(d.type) || 0) + 1);
      }
    }

    // RSV trajectory analysis
    for (const pt of profile.rsv.trajectoryPoints) {
      const pct = pt.afterSlide / profile.slideQuarks.length;
      if (pct >= 0.4 && pct <= 0.6) totalMidpointLoops += pt.openLoops.count;
    }

    // Peak gravity loops
    const peakLoops = profile.physicsEvents.peakGravity.activeLoops;
    if (peakLoops >= 4) {
      loopsByScore.high4plus.count++;
      loopsByScore.high4plus.totalScore += hookScore;
    } else {
      loopsByScore.low4.count++;
      loopsByScore.low4.totalScore += hookScore;
    }

    totalTransitionLoops += profile.physicsEvents.peakGravity.activeLoops;
    transitionLoopCount++;
  }

  // === ARC PHYSICS ===
  const arcShapes = new Map<string, number>();
  let totalReversals = 0;
  let reversalsHigh = { count: 0, total: 0 };
  let reversalsLow = { count: 0, total: 0 };
  let withIntExtTension = { count: 0, totalScore: 0 };
  let withoutIntExtTension = { count: 0, totalScore: 0 };

  for (const { profile, hookScore } of profiles) {
    const shape = profile.arcQuarks.shape;
    arcShapes.set(shape, (arcShapes.get(shape) || 0) + 1);
    totalReversals += profile.arcQuarks.winLossReversals;

    if (profile.arcQuarks.winLossReversals >= 3) {
      reversalsHigh.count++;
      reversalsHigh.total += hookScore;
    } else {
      reversalsLow.count++;
      reversalsLow.total += hookScore;
    }

    if (profile.arcQuarks.internalExternalTension?.present) {
      withIntExtTension.count++;
      withIntExtTension.totalScore += hookScore;
    } else {
      withoutIntExtTension.count++;
      withoutIntExtTension.totalScore += hookScore;
    }
  }

  // === SYMMETRY BREAKING ===
  let totalBreakPosition = 0;
  let breakCount = 0;
  let breakHighScore = { count: 0, total: 0 };
  let breakLowScore = { count: 0, total: 0 };
  const breakExamples: Array<{ title: string; slide: number; pattern: string; whatBreaks: string }> = [];

  for (const { profile, title, hookScore } of profiles) {
    const brk = profile.physicsEvents.symmetryBreak;
    if (brk.slideNumber > 0) {
      const pct = brk.slideNumber / profile.slideQuarks.length;
      totalBreakPosition += pct;
      breakCount++;
      if (hookScore >= 8) { breakHighScore.count++; breakHighScore.total += hookScore; }
      else if (hookScore <= 6) { breakLowScore.count++; breakLowScore.total += hookScore; }

      breakExamples.push({ title: title || '', slide: brk.slideNumber, pattern: brk.patternEstablished || '', whatBreaks: brk.whatBreaks || '' });
    }
  }

  // === PHASE TRANSITIONS ===
  let withTransition = { count: 0, totalScore: 0 };
  let withoutTransition = { count: 0, totalScore: 0 };
  const frameShifts = new Map<string, number>();
  let totalTransitionPosition = 0;
  let transitionCount = 0;
  const transitionExamples: Array<{ title: string; slide: number; from: string; to: string; recontext: string }> = [];

  for (const { profile, title, hookScore } of profiles) {
    const pt = profile.physicsEvents.phaseTransition;
    if (pt.slideNumber > 0 && pt.frameBefore && pt.frameAfter) {
      withTransition.count++;
      withTransition.totalScore += hookScore;
      const shiftKey = `${pt.frameBefore} → ${pt.frameAfter}`;
      frameShifts.set(shiftKey, (frameShifts.get(shiftKey) || 0) + 1);
      totalTransitionPosition += pt.slideNumber / profile.slideQuarks.length;
      transitionCount++;
      transitionExamples.push({ title: title || '', slide: pt.slideNumber, from: pt.frameBefore || '', to: pt.frameAfter || '', recontext: pt.recontextualization || '' });
    } else {
      withoutTransition.count++;
      withoutTransition.totalScore += hookScore;
    }
  }

  // === ENERGY CONSERVATION ===
  let proportionalCount = 0;
  let disproportionalCount = 0;

  for (const { profile } of profiles) {
    if (profile.physicsEvents.energyResolution.proportional) proportionalCount++;
    else disproportionalCount++;
  }

  // === NOVEL DISCOVERIES ===
  const novelCounts = new Map<string, number>();
  for (const { profile } of profiles) {
    for (const d of profile.novelDiscoveries || []) {
      const key = d.substring(0, 100); // Truncate for grouping
      novelCounts.set(key, (novelCounts.get(key) || 0) + 1);
    }
  }
  const topNovel = [...novelCounts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);

  // === FORMAT-SPECIFIC (classified by actual content density, not metadata) ===
  const reelProfiles = profiles.filter(p => p.detectedFormat === 'reel');
  const carouselProfiles = profiles.filter(p => p.detectedFormat === 'carousel');
  console.log(`  📊 Format split: ${reelProfiles.length} reels, ${carouselProfiles.length} carousels, ${profiles.length - reelProfiles.length - carouselProfiles.length} other`);

  // === BUILD CODEX TEXT ===
  const N = profiles.length;
  const lines: string[] = [];

  lines.push(`CONTENT PHYSICS CODEX — Derived from ${N} analyzed viral posts\n`);

  // Transition Physics
  lines.push(`TRANSITION PHYSICS:`);
  for (const [pos, types] of transitionsByPosition) {
    const top = topN(types, 3);
    lines.push(`  At ${pos}: ${top.map(([t, c]) => `${t} (${pct(c, N)})`).join(', ')}`);
  }
  const highTrans = topN(transitionsByScore.high, 3);
  if (highTrans.length > 0) lines.push(`  Correlate with hookScore 8+: ${highTrans.map(([t]) => t).join(', ')}`);
  lines.push('');

  // Speech Act Physics
  lines.push(`SPEECH ACT PHYSICS:`);
  for (const [pos, types] of speechActsByPosition) {
    const top = topN(types, 3);
    lines.push(`  At ${pos}: ${top.map(([t, c]) => `${t} (${pct(c, N)})`).join(', ')}`);
  }
  lines.push('');

  // Reader Delta Physics
  lines.push(`READER DELTA PHYSICS:`);
  lines.push(`  Average open loops at transition point: ${(totalTransitionLoops / Math.max(transitionLoopCount, 1)).toFixed(1)}`);
  if (loopsByScore.high4plus.count > 0 && loopsByScore.low4.count > 0) {
    lines.push(`  Posts with 4+ loops at transition: avg hookScore ${(loopsByScore.high4plus.totalScore / loopsByScore.high4plus.count).toFixed(1)} vs ${(loopsByScore.low4.totalScore / loopsByScore.low4.count).toFixed(1)} for <4 loops`);
  }
  for (const [pos, types] of deltasByPosition) {
    const top = topN(types, 3);
    lines.push(`  Most common delta at ${pos}: ${top.map(([t, c]) => `${t} (${pct(c, N)})`).join(', ')}`);
  }
  lines.push('');

  // Arc Physics
  lines.push(`ARC PHYSICS:`);
  const topArcs = topN(arcShapes, 3);
  lines.push(`  Most common arc shapes: ${topArcs.map(([s, c]) => `"${s}" (${pct(c, N)})`).join(', ')}`);
  lines.push(`  Average win/loss reversals: ${(totalReversals / N).toFixed(1)}`);
  if (reversalsHigh.count > 0 && reversalsLow.count > 0) {
    lines.push(`  Posts with 3+ reversals: avg hookScore ${(reversalsHigh.total / reversalsHigh.count).toFixed(1)} vs ${(reversalsLow.total / reversalsLow.count).toFixed(1)} for <3`);
  }
  lines.push(`  ${pct(withIntExtTension.count, N)} of posts have internal/external tension`);
  if (withIntExtTension.count > 0 && withoutIntExtTension.count > 0) {
    lines.push(`  WITH tension: avg hookScore ${(withIntExtTension.totalScore / withIntExtTension.count).toFixed(1)} vs ${(withoutIntExtTension.totalScore / withoutIntExtTension.count).toFixed(1)} without`);
  }
  lines.push('');

  // Symmetry Breaking with examples
  lines.push(`SYMMETRY BREAKING:`);
  if (breakCount > 0) {
    lines.push(`  Average break position: ${(totalBreakPosition / breakCount * 100).toFixed(0)}% through the post`);
    lines.push(`  ${pct(breakHighScore.count, N)} of 8+ scored posts have clear symmetry break`);
  }
  const bestBreakExamples = breakExamples.sort((a, b) => b.slide - a.slide).slice(0, 3);
  for (const ex of bestBreakExamples) {
    lines.push(`  Example: In "${ex.title.substring(0, 50)}" — pattern '${ex.pattern.substring(0, 60)}' breaks at slide ${ex.slide}: ${ex.whatBreaks.substring(0, 100)}`);
  }
  lines.push('');

  // Phase Transitions with examples
  lines.push(`PHASE TRANSITIONS:`);
  lines.push(`  ${pct(withTransition.count, N)} of posts have a clear phase transition`);
  if (withTransition.count > 0 && withoutTransition.count > 0) {
    lines.push(`  WITH transition: avg hookScore ${(withTransition.totalScore / withTransition.count).toFixed(1)} vs ${(withoutTransition.totalScore / withoutTransition.count).toFixed(1)} without`);
  }
  const topShifts = topN(frameShifts, 3);
  if (topShifts.length > 0) lines.push(`  Most common frame shifts: ${topShifts.map(([s, c]) => `${s} (${pct(c, N)})`).join(', ')}`);
  if (transitionCount > 0) lines.push(`  Average transition position: ${(totalTransitionPosition / transitionCount * 100).toFixed(0)}% through`);
  const bestTransExamples = transitionExamples.slice(0, 3);
  for (const ex of bestTransExamples) {
    lines.push(`  Example: In "${ex.title.substring(0, 50)}" — frame shifts at slide ${ex.slide}: "${ex.from}" → "${ex.to}". ${ex.recontext.substring(0, 100)}`);
  }
  lines.push('');

  // Energy Conservation
  lines.push(`ENERGY CONSERVATION:`);
  lines.push(`  ${pct(proportionalCount, N)} of posts have proportional energy resolution`);
  lines.push(`  ${pct(disproportionalCount, N)} have disproportional resolution (weak payoffs or unresolved loops)`);
  lines.push('');

  // Novel Patterns
  if (topNovel.length > 0) {
    lines.push(`NOVEL PATTERNS (most frequently discovered across posts):`);
    for (const [pattern, count] of topNovel) {
      lines.push(`  • ${pattern} (found in ${count} posts)`);
    }
    lines.push('');
  }

  // Format-Specific Sections (classified by content density: <=2 sentences/slide = reel, >=3 = carousel)
  for (const [label, fmtProfiles] of [['REEL', reelProfiles], ['CAROUSEL', carouselProfiles]] as const) {
    if (fmtProfiles.length < 2) continue;
    const fN = fmtProfiles.length;
    lines.push(`\n═══ ${label} PHYSICS (${fN} posts, classified by ≤2 or ≥3 sentences/slide) ═══`);

    // Transitions for this format
    const fmtTransitions = new Map<string, Map<string, number>>();
    for (const { profile } of fmtProfiles) {
      for (const t of profile.transitions) {
        const posKey = positionBucket(t.from, profile.slideQuarks.length);
        if (!fmtTransitions.has(posKey)) fmtTransitions.set(posKey, new Map());
        const posMap = fmtTransitions.get(posKey)!;
        posMap.set(t.type, (posMap.get(t.type) || 0) + 1);
      }
    }
    lines.push(`  Transitions:`);
    for (const [pos, types] of fmtTransitions) {
      const top = topN(types, 3);
      lines.push(`    At ${pos}: ${top.map(([t, c]) => `${t} (${pct(c, fN)})`).join(', ')}`);
    }

    // Arc shape for this format
    const fmtArcs = new Map<string, number>();
    let fmtReversals = 0;
    for (const { profile } of fmtProfiles) {
      fmtArcs.set(profile.arcQuarks.shape, (fmtArcs.get(profile.arcQuarks.shape) || 0) + 1);
      fmtReversals += profile.arcQuarks.winLossReversals;
    }
    lines.push(`  Arc: avg ${(fmtReversals / fN).toFixed(1)} reversals, top shapes: ${topN(fmtArcs, 2).map(([s, c]) => `"${s}" (${pct(c, fN)})`).join(', ')}`);

    // Symmetry break position for this format
    let fmtBreakPct = 0, fmtBreakCount = 0;
    for (const { profile } of fmtProfiles) {
      if (profile.physicsEvents.symmetryBreak.slideNumber > 0) {
        fmtBreakPct += profile.physicsEvents.symmetryBreak.slideNumber / profile.slideQuarks.length;
        fmtBreakCount++;
      }
    }
    if (fmtBreakCount > 0) lines.push(`  Symmetry break: avg at ${(fmtBreakPct / fmtBreakCount * 100).toFixed(0)}% through`);

    // Peak gravity for this format
    const fmtGravity = fmtProfiles.reduce((s, p) => s + p.profile.physicsEvents.peakGravity.activeLoops, 0) / fN;
    lines.push(`  Peak gravity: avg ${fmtGravity.toFixed(1)} open loops`);

    // Phase transition rate
    const fmtWithTransition = fmtProfiles.filter(p => p.profile.physicsEvents.phaseTransition.slideNumber > 0).length;
    lines.push(`  Phase transition: ${pct(fmtWithTransition, fN)} of ${label.toLowerCase()}s have one`);

    // Examples
    const bestExample = fmtProfiles.sort((a, b) => b.hookScore - a.hookScore)[0];
    if (bestExample) {
      lines.push(`  Top example: "${(bestExample.title || '').substring(0, 50)}" (${bestExample.hookScore}/10)`);
    }
  }

  // Universal section (cross-format emergent patterns)
  lines.push(`\n═══ UNIVERSAL PHYSICS (patterns that hold across ALL ${N} posts) ═══`);
  lines.push(`  This section shows what's true regardless of format — the deepest laws.`);
  // The stats computed above (transition, speech act, reader delta, etc.) ARE the universal stats
  // They already cover all profiles. Just flag the key universals:
  if (breakCount > 0) lines.push(`  Symmetry breaking: ${pct(breakCount, N)} of ALL posts have a clear break (avg at ${(totalBreakPosition / breakCount * 100).toFixed(0)}% through)`);
  lines.push(`  Phase transitions: ${pct(withTransition.count, N)} of ALL posts shift the reader's frame`);
  lines.push(`  Energy conservation: ${pct(proportionalCount, N)} resolve energy proportionally`);
  if (loopsByScore.high4plus.count > 0 && loopsByScore.low4.count > 0) {
    lines.push(`  Gravity law: 4+ loops at transition → avg hookScore ${(loopsByScore.high4plus.totalScore / loopsByScore.high4plus.count).toFixed(1)} vs ${(loopsByScore.low4.totalScore / loopsByScore.low4.count).toFixed(1)} for <4`);
  }

  const codexText = lines.join('\n');
  const stats: CodexStats = {
    totalProfiles: N,
    avgReversals: totalReversals / N,
    avgPeakGravity: totalTransitionLoops / Math.max(transitionLoopCount, 1),
    pctWithPhaseTransition: withTransition.count / N * 100,
    pctWithSymmetryBreak: breakCount / N * 100,
    pctProportionalEnergy: proportionalCount / N * 100,
  };

  return { codexText, stats };
}

// ============================================================
// Save Codex to Dedicated Atom
// ============================================================

export async function saveCodexAtom(codexText: string): Promise<string> {
  // Look for existing codex atom
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const existing = allAtoms.find(a => a.metadata?.isCodex);

  if (existing) {
    await updateAtom(existing.uuid, {
      body: codexText,
      metadata: { ...existing.metadata, updatedAt: new Date().toISOString() },
    });
    console.log(`  📊 Updated existing codex atom: ${existing.uuid}`);
    return existing.uuid;
  }

  // Create new codex atom — import createAtom if available, otherwise use updateAtom pattern
  // For now, use a well-known UUID approach
  const { createAtom } = await import('../db/queries');
  const uuid = await createAtom({
    type: 'research',
    title: 'Content Physics Codex',
    body: codexText,
    metadata: {
      isCodex: true,
      isSwipeFile: false,
      createdAt: new Date().toISOString(),
    },
    structured: {},
  });

  const codexUUID = typeof uuid === 'string' ? uuid : (uuid as any)?.uuid || 'unknown';
  console.log(`  📊 Created new codex atom: ${codexUUID}`);
  return codexUUID;
}

// ============================================================
// Load Cached Codex Text
// ============================================================

let cachedCodex: { text: string; computedAt: number } | null = null;
const CODEX_CACHE_TTL = 3600_000; // 1 hour

export async function getCodexText(): Promise<string | null> {
  // Return cached if fresh
  if (cachedCodex && Date.now() - cachedCodex.computedAt < CODEX_CACHE_TTL) {
    return cachedCodex.text;
  }

  // Try to load from atom
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const codexAtom = allAtoms.find(a => a.metadata?.isCodex);

  if (codexAtom?.body) {
    cachedCodex = { text: codexAtom.body, computedAt: Date.now() };
    return codexAtom.body;
  }

  return null;
}

export function invalidateCodexCache(): void {
  cachedCodex = null;
}

// ============================================================
// Helpers
// ============================================================

interface CodexStats {
  totalProfiles: number;
  avgReversals?: number;
  avgPeakGravity?: number;
  pctWithPhaseTransition?: number;
  pctWithSymmetryBreak?: number;
  pctProportionalEnergy?: number;
}

function positionBucket(slideNum: number, totalSlides: number): string {
  const pct = slideNum / Math.max(totalSlides, 1);
  if (pct <= 0.1) return 'hook (1-2)';
  if (pct <= 0.3) return 'early (3-5)';
  if (pct <= 0.6) return 'middle';
  if (pct <= 0.85) return 'late';
  return 'ending';
}

function classifyFormatFromBody(body: string): 'reel' | 'carousel' | 'other' {
  if (!body || body.length < 20) return 'other';

  // Extract slides from body (JSON slides, "Slide N" markers, or double-newline paragraphs)
  let slideTexts: string[] = [];

  try {
    const parsed = JSON.parse(body);
    if (parsed.slides && Array.isArray(parsed.slides)) {
      slideTexts = parsed.slides.map((s: any) => s.text || s.content || '');
    }
  } catch {
    // Not JSON — try markers
    const markerSplit = body.split(/^Slide \d+[:\s—–-]*/gim).filter(s => s.trim().length > 5);
    if (markerSplit.length >= 3) {
      slideTexts = markerSplit;
    } else {
      // Fall back to double-newline paragraphs
      slideTexts = body.split(/\n\n+/).filter(s => s.trim().length > 5);
    }
  }

  if (slideTexts.length < 3) return 'other';

  // Count sentences per slide (periods + question marks + exclamation marks)
  let totalSentences = 0;
  for (const slide of slideTexts) {
    const sentences = (slide.match(/[.!?]+/g) || []).length;
    totalSentences += Math.max(sentences, 1); // At least 1 sentence per slide
  }

  const avgSentencesPerSlide = totalSentences / slideTexts.length;

  // Reel: <=2 sentences/slide (short punchy text)
  // Carousel: >=3 sentences/slide (denser text)
  if (avgSentencesPerSlide <= 2) return 'reel';
  if (avgSentencesPerSlide >= 3) return 'carousel';
  return 'other';
}

function topN(map: Map<string, number>, n: number): [string, number][] {
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, n);
}

function pct(count: number, total: number): string {
  return `${Math.round(count / Math.max(total, 1) * 100)}%`;
}
