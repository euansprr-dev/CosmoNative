// cosmo-cloud-agent/src/writing/exemplarCodex.ts
// Deterministic pre-processing for the Exemplar Codex pipeline.
// Resolves full slide texts, groups instances by approximate type across all 63 physics
// concepts, and produces structured text that feeds into the Opus synthesis call.
//
// This is NOT the final Codex — Opus unifies inconsistent naming across independent
// extractions and curates the best examples into the definitive language.
//
// Pure computation, no LLM calls.

import { Atom, fetchAllByType } from '../db/queries';
import { QuarkProfile } from './types';

// ============================================================
// Configuration
// ============================================================

const MAX_EXAMPLES_PER_CONCEPT = 999; // Include ALL examples — let Opus see the full picture
const MIN_PROFILES_REQUIRED = 3;

// ============================================================
// Types
// ============================================================

interface ProfileEntry {
  profile: QuarkProfile;
  atom: Atom;
  title: string;
  format: string;
  detectedFormat: 'reel' | 'carousel' | 'other'; // Classified by content density
  slideTexts: string[]; // Full text per slide, indexed by slideNumber-1
}

interface Example {
  text: string;         // Full slide text (or slide pair for transitions)
  postTitle: string;
  slideNumber: number;
  format: 'reel' | 'carousel' | 'other';  // Format family for layered codex
  mechanism?: string;
  produces?: string[];  // Reader deltas produced
  techniques?: string[];
}

// ============================================================
// Main: Compute Exemplar Codex
// ============================================================

export async function prepareExemplarData(): Promise<{ codexText: string; stats: ExemplarCodexStats }> {
  // Fetch all swipes with extracted quark profiles
  const allAtoms = await fetchAllByType('research', { limit: 500 });
  const profiledAtoms = allAtoms.filter(a =>
    a.metadata?.isSwipeFile &&
    a.structured?.contentPhysics?.version
  );

  console.log(`  📊 Computing Exemplar Codex from ${profiledAtoms.length} extracted profiles...`);

  if (profiledAtoms.length < MIN_PROFILES_REQUIRED) {
    return {
      codexText: `Content Physics Exemplar Codex — Insufficient data (${profiledAtoms.length} profiles, minimum ${MIN_PROFILES_REQUIRED})`,
      stats: { totalProfiles: profiledAtoms.length, conceptsCovered: 0 },
    };
  }

  // Build profile entries with full slide text resolution
  const entries: ProfileEntry[] = [];
  for (const atom of profiledAtoms) {
    const profile = atom.structured!.contentPhysics as QuarkProfile;
    const slideTexts = resolveSlideTexts(atom, profile);
    entries.push({
      profile,
      atom,
      title: atom.title || 'Untitled',
      format: atom.structured?.swipeAnalysis?.swipeContentFormat || 'unknown',
      detectedFormat: classifyFormat(slideTexts), // Always use density-based, metadata format is often wrong
      slideTexts,
    });
  }

  const N = entries.length;
  const lines: string[] = [];

  const reelCount = entries.filter(e => e.detectedFormat === 'reel').length;
  const carouselCount = entries.filter(e => e.detectedFormat === 'carousel').length;
  const otherCount = N - reelCount - carouselCount;

  lines.push(`PREPARED DATA FOR EXEMPLAR CODEX SYNTHESIS — ${N} analyzed viral posts`);
  lines.push(`Format split: ${reelCount} reels, ${carouselCount} carousels, ${otherCount} other`);
  lines.push(`All posts are curated high-quality viral content.\n`);
  lines.push(`NOTE: Different extractions may use different names for the same concept.`);
  lines.push(`Opus will unify naming and curate the definitive language.`);
  lines.push(`Each example is tagged [REEL] or [CAROUSEL] — Opus should identify UNIVERSAL`);
  lines.push(`principles that hold across both AND format-specific physics.\n`);
  lines.push(`STRUCTURE: Part 1 = Every post individually (full text + quark profile).`);
  lines.push(`           Part 2 = Grouped concept examples + voice DNA + bridges.\n`);

  // ═══════════════════════════════════════════════════
  // PART 1: EVERY POST — Full body + Full quark profile
  // ═══════════════════════════════════════════════════
  lines.push(`${'═'.repeat(70)}`);
  lines.push(`PART 1: ALL ${N} POSTS — Full text + Complete Content Physics Profile`);
  lines.push(`${'═'.repeat(70)}\n`);

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    const slideCount = entry.slideTexts.filter(s => s.length > 0).length;

    lines.push(`\n${'█'.repeat(70)}`);
    lines.push(`█  POST ${i + 1}/${N}: "${entry.title}"`);
    lines.push(`█  Format: ${entry.detectedFormat.toUpperCase()} | Slides: ${slideCount}`);
    lines.push(`${'█'.repeat(70)}\n`);

    // Section A: Full body — slide by slide, clearly numbered
    lines.push(`┌─ FULL TEXT ${'─'.repeat(55)}┐`);
    for (let s = 0; s < entry.slideTexts.length; s++) {
      const text = entry.slideTexts[s];
      if (!text || text.length < 3) continue;
      lines.push(`│ Slide ${s + 1}: "${text}"`);
    }
    lines.push(`└${'─'.repeat(66)}┘\n`);

    // Section B: Complete quark profile — per-slide quarks match slide numbers above
    lines.push(`┌─ CONTENT PHYSICS PROFILE ${'─'.repeat(42)}┐`);
    lines.push(formatProfileAsText(entry.profile));
    lines.push(`└${'─'.repeat(66)}┘`);
  }

  lines.push(`${'═'.repeat(70)}`);
  lines.push(`PART 2: GROUPED CONCEPT EXAMPLES + AGGREGATED DATA`);
  lines.push(`${'═'.repeat(70)}\n`);

  let conceptsCovered = 0;

  // ═══════════════════════════════════════════════════
  // MICRO-SCALE: SPEECH ACTS
  // ═══════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`SPEECH ACTS — What the speaker is psychologically doing per slide`);
  lines.push(`${'═'.repeat(60)}\n`);

  const speechActExamples = new Map<string, Example[]>();
  const speechActPosts = new Map<string, Set<string>>();

  for (const entry of entries) {
    for (const sq of entry.profile.slideQuarks) {
      const type = normalizeType(sq.speechAct?.type);
      if (!type) continue;
      if (!speechActExamples.has(type)) { speechActExamples.set(type, []); speechActPosts.set(type, new Set()); }
      speechActPosts.get(type)!.add(entry.title);
      const slideText = getSlideText(entry, sq.slideNumber);
      if (slideText.length < 10) continue;
      speechActExamples.get(type)!.push({
        text: slideText,
        postTitle: entry.title,
        format: entry.detectedFormat,
                slideNumber: sq.slideNumber,
        mechanism: sq.speechAct?.mechanism,
        produces: (sq.readerDeltas || []).map(d => d.type).filter(Boolean),
        techniques: (sq.techniques || []).map(t => t.technique).filter(Boolean),
      });
    }
  }

  for (const [type, examples] of sortedEntries(speechActExamples)) {
    const sorted = examples.sort(() => Math.random() - 0.5) /* shuffle for variety */.slice(0, MAX_EXAMPLES_PER_CONCEPT);
    const postCount = speechActPosts.get(type)?.size || 0;
    lines.push(`--- ${type.toUpperCase()} ---`);
    lines.push(`Found in ${postCount}/${N} posts (${pct(postCount, N)}).\n`);
    for (let i = 0; i < sorted.length; i++) {
      const ex = sorted[i];
      lines.push(`${i + 1}. "${truncate(ex.text, 300)}"`);
      lines.push(`   — [${ex.format?.toUpperCase() || 'OTHER'}] [${truncate(ex.postTitle, 50)}] Slide ${ex.slideNumber}`);
      if (ex.mechanism) lines.push(`   Mechanism: ${truncate(ex.mechanism, 150)}`);
      if (ex.produces?.length) lines.push(`   Produces: ${ex.produces.join(', ')}`);
      if (ex.techniques?.length) lines.push(`   Techniques: ${ex.techniques.join(', ')}`);
      lines.push('');
    }
    conceptsCovered++;
  }

  // ══��════════════════════════════════════════════════
  // MICRO-SCALE: READER DELTAS
  // ═══════���════════════════════════════��══════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`READER DELTAS — What changes in the reader's mind (and HOW)`);
  lines.push(`${'═'.repeat(60)}\n`);

  const deltaExamples = new Map<string, Example[]>();
  const deltaPosts = new Map<string, Set<string>>();

  for (const entry of entries) {
    for (const sq of entry.profile.slideQuarks) {
      for (const d of (sq.readerDeltas || [])) {
        const type = normalizeType(d.type);
        if (!type) continue;
        if (!deltaExamples.has(type)) { deltaExamples.set(type, []); deltaPosts.set(type, new Set()); }
        deltaPosts.get(type)!.add(entry.title);
        const slideText = getSlideText(entry, sq.slideNumber);
        if (slideText.length < 10) continue;
        deltaExamples.get(type)!.push({
          text: slideText,
          postTitle: entry.title,
        format: entry.detectedFormat,
                    slideNumber: sq.slideNumber,
          mechanism: d.mechanism,
          techniques: (sq.techniques || []).map(t => t.technique).filter(Boolean),
        });
      }
    }
  }

  for (const [type, examples] of sortedEntries(deltaExamples)) {
    const sorted = examples.sort(() => Math.random() - 0.5) /* shuffle for variety */.slice(0, MAX_EXAMPLES_PER_CONCEPT);
    const postCount = deltaPosts.get(type)?.size || 0;
    lines.push(`--- ${type.toUpperCase()} ---`);
    lines.push(`Found in ${postCount}/${N} posts (${pct(postCount, N)}).\n`);
    for (let i = 0; i < sorted.length; i++) {
      const ex = sorted[i];
      lines.push(`${i + 1}. "${truncate(ex.text, 300)}"`);
      lines.push(`   — [${ex.format?.toUpperCase() || 'OTHER'}] [${truncate(ex.postTitle, 50)}] Slide ${ex.slideNumber}`);
      if (ex.mechanism) lines.push(`   HOW this delta is created: ${truncate(ex.mechanism, 200)}`);
      if (ex.techniques?.length) lines.push(`   Techniques used: ${ex.techniques.join(', ')}`);
      lines.push('');
    }
    conceptsCovered++;
  }

  // ══════════���═════════════════���══════════════════════
  // MICRO-SCALE: PROOF TYPES
  // ══════���═══════════════════════════════════════���════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`PROOF TYPES — What type of evidence earns belief`);
  lines.push(`${'═'.repeat(60)}\n`);
  conceptsCovered += renderQuarkField(lines, entries, N, 'proofType');

  // ═════════════��══════════════════════���══════════════
  // MICRO-SCALE: MOTIVATIONS
  // ═══════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`MOTIVATIONS — Why the subject acts NOW (makes decisions inevitable)`);
  lines.push(`${'═'.repeat(60)}\n`);
  conceptsCovered += renderQuarkField(lines, entries, N, 'motivation');

  // ══════���══════════════��═════════════════════════════
  // MICRO-SCALE: COMPRESSIONS
  // ═��═════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`COMPRESSIONS — How skipped time/information is handled`);
  lines.push(`${'═'.repeat(60)}\n`);
  conceptsCovered += renderQuarkField(lines, entries, N, 'compression');

  // ═════════════��═════════════════════════════════════
  // MICRO-SCALE: PER-SLIDE FRAMES
  // ═══════���════════��════════════════════════════════���═
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`PER-SLIDE FRAMES — How each slide positions its content`);
  lines.push(`${'═'.repeat(60)}\n`);
  conceptsCovered += renderQuarkField(lines, entries, N, 'frame');

  // ══════��═════════════════��══════════════════════════
  // MICRO-SCALE: EXPERIENTIAL DISTANCE
  // ════════════════════════��══════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`EXPERIENTIAL DISTANCE — How close the writer is to the event`);
  lines.push(`${'═'.repeat(60)}\n`);
  conceptsCovered += renderQuarkField(lines, entries, N, 'experientialDistance');

  // ═══════════════════════════════════��═══════════════
  // MICRO-SCALE: TECHNIQUES
  // ══════��════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`TECHNIQUES — Craft moves that produce quarks (with real examples)`);
  lines.push(`${'═'.repeat(60)}\n`);

  const techExamples = new Map<string, Example[]>();
  for (const entry of entries) {
    for (const sq of entry.profile.slideQuarks) {
      for (const t of (sq.techniques || [])) {
        const type = normalizeType(t.technique);
        if (!type) continue;
        if (!techExamples.has(type)) techExamples.set(type, []);
        const slideText = getSlideText(entry, sq.slideNumber);
        if (slideText.length < 10) continue;
        techExamples.get(type)!.push({
          text: slideText,
          postTitle: entry.title,
        format: entry.detectedFormat,
                    slideNumber: sq.slideNumber,
          mechanism: t.usage,
          produces: (sq.readerDeltas || []).map(d => d.type).filter(Boolean),
        });
      }
    }
  }

  for (const [type, examples] of sortedEntries(techExamples)) {
    const sorted = examples.sort(() => Math.random() - 0.5) /* shuffle for variety */;
    lines.push(`--- ${type.toUpperCase()} ---`);
    lines.push(`Found in ${examples.length} slides across ${N} posts.\n`);
    for (let i = 0; i < sorted.length; i++) {
      const ex = sorted[i];
      lines.push(`${i + 1}. "${truncate(ex.text, 250)}"`);
      lines.push(`   — [${ex.format?.toUpperCase() || 'OTHER'}] [${truncate(ex.postTitle, 50)}] Slide ${ex.slideNumber}`);
      if (ex.mechanism) lines.push(`   Usage: ${truncate(ex.mechanism, 150)}`);
      if (ex.produces?.length) lines.push(`   Produces: ${ex.produces.join(', ')}`);
      lines.push('');
    }
    conceptsCovered++;
  }

  // ════════���═══════════════���══════════════════════════
  // MESO-SCALE: TRANSITIONS
  // ═��═════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`TRANSITIONS — Causal bridges between consecutive slides`);
  lines.push(`${'═'.repeat(60)}\n`);

  const transExamples = new Map<string, Array<{
    fromText: string; toText: string; postTitle: string; format: 'reel' | 'carousel' | 'other';
    from: number; to: number; mechanism?: string; doubleHelix?: boolean;
    swapTestPasses?: boolean;
  }>>();

  for (const entry of entries) {
    for (const t of entry.profile.transitions) {
      const type = normalizeType(t.type);
      if (!type) continue;
      if (!transExamples.has(type)) transExamples.set(type, []);
      const fromText = getSlideText(entry, t.from);
      const toText = getSlideText(entry, t.to);
      if (fromText.length < 10 || toText.length < 10) continue;
      transExamples.get(type)!.push({
        fromText, toText,
        postTitle: entry.title,
        format: entry.detectedFormat,
                from: t.from, to: t.to,
        mechanism: t.mechanism,
        doubleHelix: t.doubleHelix,
        swapTestPasses: t.swapTestPasses,
      });
    }
  }

  for (const [type, examples] of sortedEntries(transExamples)) {
    const sorted = examples.sort(() => Math.random() - 0.5) /* shuffle for variety */;
    const dhRate = examples.filter(e => e.doubleHelix).length / Math.max(examples.length, 1);
    const swapFailRate = examples.filter(e => e.swapTestPasses === false).length / Math.max(examples.length, 1);
    lines.push(`--- ${type.toUpperCase()} ---`);
    lines.push(`Found in ${examples.length} transitions. Double helix: ${pct(Math.round(dhRate * examples.length), examples.length)}. Strong (can't swap): ${pct(Math.round(swapFailRate * examples.length), examples.length)}.\n`);
    for (let i = 0; i < sorted.length; i++) {
      const ex = sorted[i];
      lines.push(`${i + 1}. Slide ${ex.from}: "${truncate(ex.fromText, 200)}"`);
      lines.push(`   → Slide ${ex.to}: "${truncate(ex.toText, 200)}"`);
      lines.push(`   — [${truncate(ex.postTitle, 50)}] `);
      if (ex.mechanism) lines.push(`   Bridge mechanism: ${truncate(ex.mechanism, 150)}`);
      if (ex.doubleHelix) lines.push(`   Double helix: YES (narrative + psychological causality)`);
      lines.push('');
    }
    conceptsCovered++;
  }

  // ══════════════════��════════════════════════════════
  // MACRO-SCALE: DOMINANT FRAMES
  // ═══════════════════════════════════════════════���═══
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`DOMINANT FRAMES — Post-level identity (what kind of content this IS)`);
  lines.push(`${'═'.repeat(60)}\n`);

  const frameExamples = new Map<string, Array<{ title: string; arcShape: string; mechanism?: string }>>();
  for (const entry of entries) {
    const df = entry.profile.arcQuarks?.dominantFrame;
    const type = normalizeType(df?.type);
    if (!type) continue;
    if (!frameExamples.has(type)) frameExamples.set(type, []);
    frameExamples.get(type)!.push({
      title: entry.title,
            arcShape: entry.profile.arcQuarks?.shape || 'unknown',
      mechanism: df?.mechanism,
    });
  }

  for (const [type, examples] of sortedEntries(frameExamples)) {
    const sorted = examples.sort(() => Math.random() - 0.5) /* shuffle for variety */;
    lines.push(`--- ${type.toUpperCase()} ---`);
    lines.push(`Found in ${examples.length}/${N} posts (${pct(examples.length, N)}).\n`);
    for (const ex of sorted) {
      lines.push(`  "${truncate(ex.title, 60)}" (arc: ${ex.arcShape})`);
      if (ex.mechanism) lines.push(`    Mechanism: ${truncate(ex.mechanism, 150)}`);
    }
    lines.push('');
    conceptsCovered++;
  }

  // ═══════��════════════════════════���══════════════════
  // PHYSICS EVENTS
  // ══════════════════════��════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`PHYSICS EVENTS — Emergent phenomena (symmetry breaks, phase transitions, gravity, energy)`);
  lines.push(`${'═'.repeat(60)}\n`);

  // Symmetry Breaks
  lines.push(`--- SYMMETRY BREAK ---`);
  const breakExamples: Array<{ title: string; slide: number; pattern: string; whatBreaks: string; whyDevastating: string; slideText: string }> = [];
  for (const entry of entries) {
    const brk = entry.profile.physicsEvents?.symmetryBreak;
    if (!brk?.slideNumber || brk.slideNumber <= 0) continue;
    breakExamples.push({
      title: entry.title,       slide: brk.slideNumber,
      pattern: brk.patternEstablished || '',
      whatBreaks: brk.whatBreaks || '',
      whyDevastating: (brk as any).whyDevastating || '',
      slideText: getSlideText(entry, brk.slideNumber),
    });
  }
  const sortedBreaks = breakExamples.sort(() => Math.random() - 0.5) /* shuffle for variety */.slice(0, MAX_EXAMPLES_PER_CONCEPT);
  lines.push(`Found in ${breakExamples.length}/${N} posts (${pct(breakExamples.length, N)}). Avg position: ${avg(breakExamples.map(e => e.slide)).toFixed(0)} (as slide #).\n`);
  for (let i = 0; i < sortedBreaks.length; i++) {
    const ex = sortedBreaks[i];
    lines.push(`${i + 1}. "${truncate(ex.slideText, 250)}"`);
    lines.push(`   — [${truncate(ex.title, 50)}] Slide ${ex.slide}`);
    lines.push(`   Pattern established: ${truncate(ex.pattern, 150)}`);
    lines.push(`   What breaks: ${truncate(ex.whatBreaks, 150)}`);
    if (ex.whyDevastating) lines.push(`   Why devastating: ${truncate(ex.whyDevastating, 150)}`);
    lines.push('');
  }
  conceptsCovered++;

  // Phase Transitions
  lines.push(`--- PHASE TRANSITION ---`);
  const ptExamples: Array<{ title: string; slide: number; frameBefore: string; frameAfter: string; recontextualization: string; slideText: string }> = [];
  for (const entry of entries) {
    const pt = entry.profile.physicsEvents?.phaseTransition;
    if (!pt?.slideNumber || pt.slideNumber <= 0) continue;
    ptExamples.push({
      title: entry.title,       slide: pt.slideNumber,
      frameBefore: pt.frameBefore || '',
      frameAfter: pt.frameAfter || '',
      recontextualization: pt.recontextualization || '',
      slideText: getSlideText(entry, pt.slideNumber),
    });
  }
  const sortedPT = ptExamples.sort(() => Math.random() - 0.5) /* shuffle for variety */.slice(0, MAX_EXAMPLES_PER_CONCEPT);
  lines.push(`Found in ${ptExamples.length}/${N} posts (${pct(ptExamples.length, N)}).\n`);
  for (let i = 0; i < sortedPT.length; i++) {
    const ex = sortedPT[i];
    lines.push(`${i + 1}. "${truncate(ex.slideText, 250)}"`);
    lines.push(`   — [${truncate(ex.title, 50)}] Slide ${ex.slide}`);
    lines.push(`   Frame shift: "${ex.frameBefore}" → "${ex.frameAfter}"`);
    if (ex.recontextualization) lines.push(`   Recontextualization: ${truncate(ex.recontextualization, 200)}`);
    lines.push('');
  }
  conceptsCovered++;

  // Peak Gravity
  lines.push(`--- PEAK GRAVITY ---`);
  const gravExamples: Array<{ title: string; slide: number; activeLoops: number; coincidesWithTransition: boolean; slideText: string }> = [];
  for (const entry of entries) {
    const pg = entry.profile.physicsEvents?.peakGravity;
    if (!pg?.slideNumber || pg.slideNumber <= 0) continue;
    gravExamples.push({
      title: entry.title,       slide: pg.slideNumber, activeLoops: pg.activeLoops,
      coincidesWithTransition: pg.coincidesWithTransition || false,
      slideText: getSlideText(entry, pg.slideNumber),
    });
  }
  const sortedGrav = gravExamples.sort((a, b) => b.activeLoops - a.activeLoops);
  lines.push(`Avg active loops at peak: ${avg(gravExamples.map(e => e.activeLoops)).toFixed(1)}. Coincides with transition: ${pct(gravExamples.filter(e => e.coincidesWithTransition).length, gravExamples.length)}.\n`);
  for (let i = 0; i < sortedGrav.length; i++) {
    const ex = sortedGrav[i];
    lines.push(`${i + 1}. "${truncate(ex.slideText, 200)}" — ${ex.activeLoops} open loops`);
    lines.push(`   — [${truncate(ex.title, 50)}] Slide ${ex.slide}`);
    lines.push('');
  }
  conceptsCovered++;

  // ═══════════════════════════════════════════════════
  // LONG-RANGE INTERACTIONS
  // ════���═════════════════���════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`LONG-RANGE INTERACTIONS — Bonds, echoes, interference across the full post`);
  lines.push(`${'═'.repeat(60)}\n`);

  // Setup-Payoff Bonds
  lines.push(`--- SETUP-PAYOFF BONDS ---`);
  const bondExamples: Array<{ title: string; setupSlide: number; payoffSlide: number; planted: string; harvested: string; setupText: string; payoffText: string; distance: number }> = [];
  for (const entry of entries) {
    for (const bond of (entry.profile.longRangeInteractions?.setupPayoffBonds || [])) {
      bondExamples.push({
        title: entry.title,         setupSlide: bond.setupSlide, payoffSlide: bond.payoffSlide,
        planted: bond.planted || '', harvested: bond.harvested || '',
        setupText: getSlideText(entry, bond.setupSlide),
        payoffText: getSlideText(entry, bond.payoffSlide),
        distance: bond.distance || (bond.payoffSlide - bond.setupSlide),
      });
    }
  }
  const sortedBonds = bondExamples.sort(() => Math.random() - 0.5) /* shuffle for variety */;
  lines.push(`Found ${bondExamples.length} bonds across ${N} posts. Avg distance: ${avg(bondExamples.map(e => e.distance)).toFixed(1)} slides.\n`);
  for (let i = 0; i < sortedBonds.length; i++) {
    const ex = sortedBonds[i];
    lines.push(`${i + 1}. Setup (Slide ${ex.setupSlide}): "${truncate(ex.setupText, 150)}"`);
    lines.push(`   Payoff (Slide ${ex.payoffSlide}): "${truncate(ex.payoffText, 150)}"`);
    lines.push(`   — [${truncate(ex.title, 50)}] Distance: ${ex.distance} slides`);
    if (ex.planted) lines.push(`   Planted: ${truncate(ex.planted, 100)}`);
    if (ex.harvested) lines.push(`   Harvested: ${truncate(ex.harvested, 100)}`);
    lines.push('');
  }
  conceptsCovered++;

  // Echo Patterns
  lines.push(`--- ECHO PATTERNS ---`);
  const echoExamples: Array<{ title: string; quarkType: string; positions: number[]; transformation: string }> = [];
  for (const entry of entries) {
    for (const echo of (entry.profile.longRangeInteractions?.echoPatterns || [])) {
      echoExamples.push({
        title: entry.title,         quarkType: echo.quarkType || '', positions: echo.positions || [],
        transformation: echo.transformation || '',
      });
    }
  }
  if (echoExamples.length > 0) {
    const sortedEchoes = echoExamples.sort(() => Math.random() - 0.5) /* shuffle for variety */;
    lines.push(`Found ${echoExamples.length} echo patterns.\n`);
    for (const ex of sortedEchoes) {
      lines.push(`  "${ex.quarkType}" echoes at slides [${ex.positions.join(', ')}]`);
      lines.push(`  — [${truncate(ex.title, 50)}] `);
      if (ex.transformation) lines.push(`  Transformation: ${truncate(ex.transformation, 150)}`);
      lines.push('');
    }
  }
  conceptsCovered++;

  // Deliberate Absences
  lines.push(`--- DELIBERATE ABSENCES ---`);
  const absenceExamples: Array<{ title: string; what: string; effect: string }> = [];
  for (const entry of entries) {
    for (const abs of (entry.profile.longRangeInteractions?.deliberateAbsences || [])) {
      absenceExamples.push({
        title: entry.title,         what: abs.what || '', effect: abs.effect || '',
      });
    }
  }
  if (absenceExamples.length > 0) {
    const sortedAbs = absenceExamples.sort(() => Math.random() - 0.5) /* shuffle for variety */;
    lines.push(`Found ${absenceExamples.length} deliberate absences.\n`);
    for (const ex of sortedAbs) {
      lines.push(`  What's missing: "${truncate(ex.what, 150)}"`);
      lines.push(`  Effect: ${truncate(ex.effect, 150)}`);
      lines.push(`  — [${truncate(ex.title, 50)}] `);
      lines.push('');
    }
  }
  conceptsCovered++;

  // Entanglement Pairs
  lines.push(`--- ENTANGLEMENT PAIRS ---`);
  const entangleExamples: Array<{ title: string; slideA: number; slideB: number; ifARemoved: string; ifBRemoved: string; textA: string; textB: string }> = [];
  for (const entry of entries) {
    for (const ep of (entry.profile.longRangeInteractions?.entanglementPairs || [])) {
      entangleExamples.push({
        title: entry.title,         slideA: ep.slideA, slideB: ep.slideB,
        ifARemoved: ep.ifARemoved || '', ifBRemoved: ep.ifBRemoved || '',
        textA: getSlideText(entry, ep.slideA), textB: getSlideText(entry, ep.slideB),
      });
    }
  }
  if (entangleExamples.length > 0) {
    const sortedEnt = entangleExamples.sort(() => Math.random() - 0.5) /* shuffle for variety */;
    lines.push(`Found ${entangleExamples.length} entanglement pairs.\n`);
    for (const ex of sortedEnt) {
      lines.push(`  Slide ${ex.slideA}: "${truncate(ex.textA, 120)}"`);
      lines.push(`  Slide ${ex.slideB}: "${truncate(ex.textB, 120)}"`);
      lines.push(`  — [${truncate(ex.title, 50)}] `);
      if (ex.ifARemoved) lines.push(`  If A removed: ${truncate(ex.ifARemoved, 100)}`);
      if (ex.ifBRemoved) lines.push(`  If B removed: ${truncate(ex.ifBRemoved, 100)}`);
      lines.push('');
    }
  }
  conceptsCovered++;

  // ═══════════════════════════════════════════���═══════
  // ANTIMATTER
  // ═══════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`ANTIMATTER — Phrases and moves that DESTROY accumulated physics`);
  lines.push(`${'═'.repeat(60)}\n`);

  const antimatterCounts = new Map<string, number>();
  for (const entry of entries) {
    for (const am of (entry.profile.antimatter || [])) {
      const key = am.toLowerCase().trim();
      antimatterCounts.set(key, (antimatterCounts.get(key) || 0) + 1);
    }
  }
  const topAntimatter = [...antimatterCounts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 50) /* show all meaningful entries */;
  if (topAntimatter.length > 0) {
    lines.push(`Most common destructive patterns (NEVER use these):\n`);
    for (const [phrase, count] of topAntimatter) {
      lines.push(`  • "${truncate(phrase, 120)}" (found in ${count} posts)`);
    }
    lines.push('');
  }
  conceptsCovered++;

  // ═══════��═══════════════════════════════════════════
  // ARC SHAPES (with full post summaries)
  // ═══════════���═══════════════════════════════��═══════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`ARC SHAPES — Full-post emotional trajectories`);
  lines.push(`${'═'.repeat(60)}\n`);

  const arcExamples = new Map<string, Array<{ title: string; reversals: number; slideCount: number }>>();
  for (const entry of entries) {
    const shape = entry.profile.arcQuarks?.shape;
    if (!shape) continue;
    if (!arcExamples.has(shape)) arcExamples.set(shape, []);
    arcExamples.get(shape)!.push({
      title: entry.title,       reversals: entry.profile.arcQuarks?.winLossReversals || 0,
      slideCount: entry.profile.slideQuarks?.length || 0,
    });
  }
  for (const [shape, examples] of sortedEntries(arcExamples)) {
    const sorted = examples.sort(() => Math.random() - 0.5) /* shuffle for variety */;
    lines.push(`--- "${shape}" ---`);
    lines.push(`Found in ${examples.length} posts. Avg reversals: ${avg(examples.map(e => e.reversals)).toFixed(1)}.\n`);
    for (const ex of sorted) {
      lines.push(`  "${truncate(ex.title, 60)}" (${ex.slideCount} slides, ${ex.reversals} reversals)`);
    }
    lines.push('');
    conceptsCovered++;
  }

  // ═════════════════════════��═════════════════════════
  // RESONANCE FREQUENCIES
  // ═════��════════════���════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`RESONANCE FREQUENCIES — Details that hit mass unspoken experiences`);
  lines.push(`${'═'.repeat(60)}\n`);

  const resExamples: Array<{ title: string; slideNumber: number; detail: string; unspoken: string; reach: string; slideText: string }> = [];
  for (const entry of entries) {
    for (const sq of entry.profile.slideQuarks) {
      const rf = sq.resonanceFrequency;
      if (!rf?.detail) continue;
      resExamples.push({
        title: entry.title,         slideNumber: sq.slideNumber,
        detail: rf.detail || '', unspoken: rf.unspokenExperience || '', reach: rf.estimatedReach || '',
        slideText: getSlideText(entry, sq.slideNumber),
      });
    }
  }
  const sortedRes = resExamples.sort(() => Math.random() - 0.5) /* shuffle for variety */.slice(0, MAX_EXAMPLES_PER_CONCEPT);
  if (sortedRes.length > 0) {
    for (let i = 0; i < sortedRes.length; i++) {
      const ex = sortedRes[i];
      lines.push(`${i + 1}. "${truncate(ex.slideText, 250)}"`);
      lines.push(`   — [${truncate(ex.title, 50)}] Slide ${ex.slideNumber}`);
      lines.push(`   Detail: ${truncate(ex.detail, 150)}`);
      if (ex.unspoken) lines.push(`   Unspoken experience: ${truncate(ex.unspoken, 150)}`);
      if (ex.reach) lines.push(`   Estimated reach: ${ex.reach}`);
      lines.push('');
    }
  }
  conceptsCovered++;

  // ═══════════════════════════════════════════════════
  // DEEP FABRIC (top syntheses)
  // ══��════════════���══════════════════════════���════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`DEEP FABRIC — Emergent synthesis from highest-scoring posts`);
  lines.push(`${'═'.repeat(60)}\n`);

  const fabricEntries = entries
    .filter(e => e.profile.deepFabric && e.profile.deepFabric.length > 50)
    .sort(() => Math.random() - 0.5) /* shuffle for variety */
    .slice(0, 5);

  for (const entry of fabricEntries) {
    lines.push(`"${truncate(entry.title, 60)}":`);
    lines.push(truncate(entry.profile.deepFabric!, 500));
    lines.push('');
  }
  conceptsCovered++;

  // ═══════════════════════════════════════════════════
  // VOICE DNA — Raw quantitative text analysis (no interpretation, let Opus discover)
  // ═══════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`VOICE DNA — Raw text metrics from ${N} viral posts (Opus: discover what matters)`);
  lines.push(`${'═'.repeat(60)}\n`);

  const voiceDNA = extractVoiceDNA(entries);
  lines.push(voiceDNA);

  // ═══════════════════════════════════════════════════
  // SLIDE BRIDGES — Raw connector data between consecutive slides
  // ═══════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`SLIDE BRIDGES — Actual text connecting consecutive slides (${N} posts)`);
  lines.push(`${'═'.repeat(60)}\n`);

  const bridgeData = extractSlideBridges(entries);
  lines.push(bridgeData);

  // ═══════════════════════════════════════════════════
  // STATS SUMMARY
  // ═══════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`CODEX STATISTICS`);
  lines.push(`${'═'.repeat(60)}\n`);
  lines.push(`Total profiles analyzed: ${N}`);
  lines.push(`Concepts covered with examples: ${conceptsCovered}`);
  lines.push(`All posts are curated high-quality viral content.`);

  const codexText = lines.join('\n');
  console.log(`  📊 Exemplar Codex computed: ${conceptsCovered} concepts, ${codexText.length} chars (~${Math.round(codexText.length / 4)} tokens)`);

  return {
    codexText,
    stats: { totalProfiles: N, conceptsCovered },
  };
}

// ============================================================
// Helpers
// ============================================================

interface ExemplarCodexStats {
  totalProfiles: number;
  conceptsCovered: number;
}

/**
 * Resolve full slide texts for an atom. Priority:
 * 1. transcriptSlides (pre-parsed per-slide text)
 * 2. atom.body parsed by "Slide N" markers or JSON
 * 3. slideQuarks[].text (only ~100 chars, last resort)
 */
function resolveSlideTexts(atom: Atom, profile: QuarkProfile): string[] {
  const slides: string[] = [];

  // Priority 1: transcriptSlides
  const ts = atom.structured?.swipeAnalysis?.transcriptSlides;
  if (ts && Array.isArray(ts) && ts.length > 0) {
    for (const s of ts) {
      const idx = (s.slideNumber || slides.length + 1) - 1;
      while (slides.length <= idx) slides.push('');
      slides[idx] = s.text || '';
    }
    if (slides.some(s => s.length > 0)) return slides;
  }

  // Priority 2: atom.body parsed
  const body = atom.body || '';
  if (body.length > 20) {
    // Try JSON
    try {
      const parsed = JSON.parse(body);
      if (parsed.slides && Array.isArray(parsed.slides)) {
        return parsed.slides.map((s: any) => String(typeof s === 'string' ? s : s.text || s.content || ''));
      }
    } catch {}

    // Try "Slide N" markers
    const markerMatches = [...body.matchAll(/^Slide \d+[^\n]*\n([\s\S]*?)(?=^Slide \d+[^\n]*\n|$)/gim)];
    if (markerMatches.length >= 3) {
      return markerMatches.map(m => (m[1] || '').trim());
    }

    // Try double-newline paragraphs
    const paragraphs = body.split(/\n{2,}/).filter(p => p.trim().length > 10);
    if (paragraphs.length >= 3) {
      return paragraphs.map(p => p.trim());
    }
  }

  // Priority 3: slideQuarks[].text (truncated, last resort)
  return profile.slideQuarks.map(sq => sq.text || '');
}

function getSlideText(entry: ProfileEntry, slideNumber: number): string {
  const idx = slideNumber - 1;
  if (idx >= 0 && idx < entry.slideTexts.length) {
    return entry.slideTexts[idx] || '';
  }
  // Fallback to quark text
  const sq = entry.profile.slideQuarks.find(s => s.slideNumber === slideNumber);
  return sq?.text || '';
}

/**
 * Generic renderer for optional quark fields (proofType, motivation, compression, frame, experientialDistance).
 * Returns the number of concept types rendered.
 */
function renderQuarkField(
  lines: string[],
  entries: ProfileEntry[],
  N: number,
  field: 'proofType' | 'motivation' | 'compression' | 'frame' | 'experientialDistance',
): number {
  const examples = new Map<string, Example[]>();
  const posts = new Map<string, Set<string>>();

  for (const entry of entries) {
    for (const sq of entry.profile.slideQuarks) {
      const quark = sq[field] as any;
      if (!quark) continue;
      const type = normalizeType(quark.type || quark.level || quark);
      if (!type) continue;
      if (!examples.has(type)) { examples.set(type, []); posts.set(type, new Set()); }
      posts.get(type)!.add(entry.title);
      const slideText = getSlideText(entry, sq.slideNumber);
      if (slideText.length < 10) continue;
      examples.get(type)!.push({
        text: slideText,
        postTitle: entry.title,
        format: entry.detectedFormat,
                slideNumber: sq.slideNumber,
        mechanism: quark.mechanism || quark.size,
        produces: (sq.readerDeltas || []).map((d: any) => d.type).filter(Boolean),
        techniques: (sq.techniques || []).map((t: any) => t.technique).filter(Boolean),
      });
    }
  }

  let count = 0;
  for (const [type, exs] of sortedEntries(examples)) {
    const sorted = exs.sort(() => Math.random() - 0.5) /* shuffle for variety */.slice(0, MAX_EXAMPLES_PER_CONCEPT);
    const postCount = posts.get(type)?.size || 0;
    lines.push(`--- ${type.toUpperCase()} ---`);
    lines.push(`Found in ${postCount}/${N} posts (${pct(postCount, N)}).\n`);
    for (let i = 0; i < sorted.length; i++) {
      const ex = sorted[i];
      lines.push(`${i + 1}. "${truncate(ex.text, 300)}"`);
      lines.push(`   — [${ex.format?.toUpperCase() || 'OTHER'}] [${truncate(ex.postTitle, 50)}] Slide ${ex.slideNumber}`);
      if (ex.mechanism) lines.push(`   Mechanism: ${truncate(ex.mechanism, 150)}`);
      if (ex.produces?.length) lines.push(`   Produces: ${ex.produces.join(', ')}`);
      lines.push('');
    }
    count++;
  }
  return count;
}

/**
 * Format a single post's quark profile as readable text (not raw JSON).
 */
function formatProfileAsText(profile: QuarkProfile): string {
  const lines: string[] = [];

  for (const sq of profile.slideQuarks) {
    lines.push(`  Slide ${sq.slideNumber}:`);
    lines.push(`    Speech Act: ${sq.speechAct?.type || '?'} — ${sq.speechAct?.mechanism || ''}`);
    if (sq.readerDeltas?.length) {
      lines.push(`    Reader Deltas: ${sq.readerDeltas.map(d => `${d.type} (${d.mechanism || ''})`).join(', ')}`);
    }
    if (sq.frame) lines.push(`    Frame: ${sq.frame.type || '?'} — ${sq.frame.mechanism || ''}`);
    if (sq.experientialDistance) lines.push(`    Distance: ${(sq.experientialDistance as any).level || (sq.experientialDistance as any).type || '?'} — ${sq.experientialDistance.mechanism || ''}`);
    if (sq.proofType) lines.push(`    Proof: ${sq.proofType.type || '?'} — ${sq.proofType.mechanism || ''}`);
    if (sq.motivation) lines.push(`    Motivation: ${sq.motivation.type || '?'} — ${sq.motivation.mechanism || ''}`);
    if (sq.compression) lines.push(`    Compression: ${sq.compression.type} (${sq.compression.size || ''}) — ${sq.compression.mechanism || ''}`);
    if (sq.techniques?.length) lines.push(`    Techniques: ${sq.techniques.map(t => `${t.technique}${t.usage ? ': ' + t.usage : ''}`).join(', ')}`);
    if (sq.resonanceFrequency?.detail) lines.push(`    Resonance: ${sq.resonanceFrequency.detail} (unspoken: ${sq.resonanceFrequency.unspokenExperience || '?'}, reach: ${sq.resonanceFrequency.estimatedReach || '?'})`);
  }

  if (profile.transitions?.length) {
    lines.push(`  Transitions:`);
    for (const t of profile.transitions) {
      lines.push(`    ${t.from}→${t.to}: ${t.type} — ${t.mechanism || ''} ${t.doubleHelix ? `[DOUBLE HELIX: ${t.doubleHelixDetail || 'narrative+psychological'}]` : ''} ${t.swapTestPasses === false ? '[STRONG: can\'t swap]' : ''}`);
    }
  }

  if (profile.arcQuarks) {
    const a = profile.arcQuarks;
    lines.push(`  Arc: ${a.shape || '?'}, ${a.winLossReversals || 0} reversals`);
    if (a.tensionPeaks?.length) lines.push(`    Tension peaks at slides: [${a.tensionPeaks.join(', ')}]`);
    if (a.dominantFrame) lines.push(`    Dominant Frame: ${a.dominantFrame.type} — ${a.dominantFrame.mechanism || ''}`);
    if (a.internalExternalTension?.present) lines.push(`    Int/Ext Tension (peak @ slide ${a.internalExternalTension.peakSlide || '?'}): ${a.internalExternalTension.description || ''}`);
    if (a.sparseDensePattern) lines.push(`    Sparse/Dense: ${a.sparseDensePattern}`);
  }

  if (profile.physicsEvents) {
    const pe = profile.physicsEvents;
    if (pe.symmetryBreak?.slideNumber) lines.push(`  Symmetry Break @ slide ${pe.symmetryBreak.slideNumber}: pattern="${pe.symmetryBreak.patternEstablished || ''}" breaks="${pe.symmetryBreak.whatBreaks || ''}" why devastating="${pe.symmetryBreak.whyDevastating || ''}"`);
    if (pe.phaseTransition?.slideNumber) lines.push(`  Phase Transition @ slide ${pe.phaseTransition.slideNumber}: "${pe.phaseTransition.frameBefore}" → "${pe.phaseTransition.frameAfter}" recontextualization="${pe.phaseTransition.recontextualization || ''}"`);
    if (pe.peakGravity?.slideNumber) lines.push(`  Peak Gravity @ slide ${pe.peakGravity.slideNumber}: ${pe.peakGravity.activeLoops} loops${pe.peakGravity.coincidesWithTransition ? ' [WITH TRANSITION]' : ''}`);
    if (pe.energyResolution) {
      lines.push(`  Energy: ${pe.energyResolution.proportional ? 'proportional' : 'DISPROPORTIONAL'} — ${pe.energyResolution.assessment || ''}`);
      if (pe.energyResolution.loopsClosed?.length) lines.push(`    Loops closed: ${pe.energyResolution.loopsClosed.map(l => `"${l.loop}" @ slide ${l.closedAtSlide}`).join(', ')}`);
      if (pe.energyResolution.loopsUnclosed?.length) lines.push(`    Loops UNCLOSED: ${pe.energyResolution.loopsUnclosed.join(', ')}`);
    }
  }

  if (profile.rsv?.trajectoryPoints?.length) {
    lines.push(`  RSV Trajectory:`);
    for (const pt of profile.rsv.trajectoryPoints) {
      let rsvLine = `    After slide ${pt.afterSlide}: loops=${pt.openLoops?.count || 0}`;
      if (pt.openLoops?.loops?.length) rsvLine += ` [${pt.openLoops.loops.join('; ')}]`;
      rsvLine += ` trust=${pt.trust || '?'} tension=${pt.tension?.level || '?'}(${pt.tension?.type || '?'})`;
      if (pt.patternExpectation) rsvLine += ` expects="${pt.patternExpectation}"`;
      rsvLine += ` frame="${pt.frame || '?'}" energy=${pt.energyBalance || '?'}`;
      if (pt.superpositionCount) rsvLine += ` superpositions=${pt.superpositionCount}[${(pt.superpositions || []).join('; ')}]`;
      lines.push(rsvLine);
    }
  }

  if (profile.longRangeInteractions) {
    const lr = profile.longRangeInteractions;
    if (lr.setupPayoffBonds?.length) {
      lines.push(`  Setup-Payoff Bonds:`);
      for (const b of lr.setupPayoffBonds) lines.push(`    Slide ${b.setupSlide}→${b.payoffSlide} (${b.distance} apart): planted="${b.planted}" harvested="${b.harvested}"`);
    }
    if (lr.echoPatterns?.length) {
      lines.push(`  Echo Patterns:`);
      for (const e of lr.echoPatterns) lines.push(`    "${e.quarkType}" @ [${e.positions?.join(', ')}]: ${e.transformation}`);
    }
    if (lr.deliberateAbsences?.length) {
      lines.push(`  Deliberate Absences:`);
      for (const a of lr.deliberateAbsences) lines.push(`    "${a.what}" — effect: ${a.effect}`);
    }
    if (lr.entanglementPairs?.length) {
      lines.push(`  Entanglement:`);
      for (const ep of lr.entanglementPairs) lines.push(`    ${ep.slideA}↔${ep.slideB}: if A removed="${ep.ifARemoved}", if B removed="${ep.ifBRemoved}"`);
    }
    if (lr.callbackChains?.length) {
      lines.push(`  Callbacks:`);
      for (const cc of lr.callbackChains) lines.push(`    "${cc.element}" × ${cc.appearances?.length || 0} times, arc: ${cc.transformationArc}`);
    }
    if (lr.interferences?.length) {
      lines.push(`  Interference:`);
      for (const ie of lr.interferences) lines.push(`    [${ie.slides?.join(', ')}] forces=[${ie.forces?.join(', ')}] → ${ie.emergentEffect}`);
    }
  }

  if (profile.rhythm) {
    lines.push(`  Rhythm: momentum=${profile.rhythm.momentumMechanism || '?'}, pacing=${profile.rhythm.pacingPattern || '?'}`);
    if (profile.rhythm.energyCurve?.length) lines.push(`    Energy: [${profile.rhythm.energyCurve.join(', ')}]`);
    if (profile.rhythm.densityWaveform?.length) lines.push(`    Density: [${profile.rhythm.densityWaveform.join(', ')}]`);
    if (profile.rhythm.informationRate?.length) lines.push(`    Info rate: [${profile.rhythm.informationRate.join(', ')}]`);
    if (profile.rhythm.silenceSlides?.length) lines.push(`    Silence: [${profile.rhythm.silenceSlides.join(', ')}]`);
  }

  if (profile.readerSimulation?.length) {
    lines.push(`  Reader Simulation:`);
    for (const rs of profile.readerSimulation) {
      let line = `    After slide ${rs.afterSlide}: ${rs.dominantEmotion || '?'} invest=${rs.investmentLevel || '?'}`;
      if (rs.activeQuestions?.length) line += ` Qs=[${rs.activeQuestions.join('; ')}]`;
      if (rs.builtAssumptions?.length) line += ` assumptions=[${rs.builtAssumptions.join('; ')}]`;
      if (rs.prediction) line += ` predicts="${rs.prediction}"`;
      lines.push(line);
    }
  }

  if (profile.antimatter?.length) lines.push(`  Antimatter: ${profile.antimatter.join(' | ')}`);
  if (profile.novelDiscoveries?.length) lines.push(`  Novel: ${(profile.novelDiscoveries as any[]).map((d: any) => typeof d === 'string' ? d : JSON.stringify(d)).join(' | ')}`);
  if (profile.deepFabric) lines.push(`  Fabric: ${profile.deepFabric}`);

  return lines.join('\n');
}

function normalizeType(type: string | undefined | null): string {
  if (!type) return '';
  return type.trim().toLowerCase().replace(/[_\s]+/g, '-');
}

function sortedEntries<T>(map: Map<string, T[]>): [string, T[]][] {
  return [...map.entries()]
    .filter(([, v]) => v.length > 0)
    .sort((a, b) => b[1].length - a[1].length);
}

function truncate(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  return text.substring(0, maxLen - 3) + '...';
}

function pct(count: number, total: number): string {
  return `${Math.round(count / Math.max(total, 1) * 100)}%`;
}

function avg(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((s, v) => s + v, 0) / values.length;
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

// ============================================================
// Voice DNA: Raw quantitative text analysis
// ============================================================

/**
 * Extract raw voice metrics from all posts — zero interpretation.
 * Opus discovers what patterns matter. We just measure everything.
 */
function extractVoiceDNA(entries: ProfileEntry[]): string {
  const lines: string[] = [];

  // Aggregate metrics across ALL slides of ALL posts
  const allSentenceLengths: number[] = [];
  const allSentencesPerSlide: number[] = [];
  const allWordsPerSlide: number[] = [];
  const startingWords = new Map<string, number>();
  let totalContractions = 0;
  let totalSentences = 0;
  let totalSlides = 0;
  let totalEllipsis = 0;
  let totalQuestionMarks = 0;
  let totalExclamations = 0;
  let totalCapsWords = 0;
  const avgWordLengths: number[] = [];

  // Per-post voice signatures (so Opus can see variation between posts)
  const postSignatures: Array<{ title: string; format: string; sentenceLengthSequence: number[]; wordsPerSlide: number[]; startingWordSequence: string[] }> = [];

  for (const entry of entries) {
    const postSentenceLengths: number[] = [];
    const postWordsPerSlide: number[] = [];
    const postStartingWords: string[] = [];

    for (const slideText of entry.slideTexts) {
      if (!slideText || slideText.length < 5) continue;
      totalSlides++;

      const words = slideText.split(/\s+/).filter(Boolean);
      const wordCount = words.length;
      allWordsPerSlide.push(wordCount);
      postWordsPerSlide.push(wordCount);

      // Sentence splitting (period/question/exclamation followed by space or end)
      const sentences = slideText.split(/[.!?]+\s*/).filter(s => s.trim().length > 0);
      allSentencesPerSlide.push(sentences.length);
      totalSentences += sentences.length;

      for (const sentence of sentences) {
        const sentenceWords = sentence.trim().split(/\s+/).filter(Boolean);
        const len = sentenceWords.length;
        if (len > 0) {
          allSentenceLengths.push(len);
          postSentenceLengths.push(len);

          // Starting word (lowercase, first word of each sentence)
          const firstWord = sentenceWords[0].toLowerCase().replace(/[^a-z']/g, '');
          if (firstWord) {
            startingWords.set(firstWord, (startingWords.get(firstWord) || 0) + 1);
            postStartingWords.push(firstWord);
          }
        }
      }

      // Contractions
      const contractions = slideText.match(/\b\w+[''][a-z]+\b/gi) || [];
      totalContractions += contractions.length;

      // Punctuation
      totalEllipsis += (slideText.match(/\.{3}|…/g) || []).length;
      totalQuestionMarks += (slideText.match(/\?/g) || []).length;
      totalExclamations += (slideText.match(/!/g) || []).length;

      // ALL CAPS words (2+ chars)
      totalCapsWords += (slideText.match(/\b[A-Z]{2,}\b/g) || []).length;

      // Average word length (vocabulary complexity)
      if (words.length > 0) {
        const avgLen = words.reduce((s, w) => s + w.replace(/[^a-zA-Z]/g, '').length, 0) / words.length;
        avgWordLengths.push(avgLen);
      }
    }

    // Store per-post signature (ALL posts for Opus to examine)
    postSignatures.push({
        title: entry.title,
        format: entry.detectedFormat,
        sentenceLengthSequence: postSentenceLengths,
        wordsPerSlide: postWordsPerSlide,
        startingWordSequence: postStartingWords,
      });
  }

  // === AGGREGATE STATS ===
  lines.push(`AGGREGATE VOICE METRICS (${totalSlides} slides, ${totalSentences} sentences):\n`);

  // Sentence length distribution
  const slBuckets = [0, 0, 0, 0, 0]; // 1-5, 6-10, 11-15, 16-20, 21+
  for (const len of allSentenceLengths) {
    if (len <= 5) slBuckets[0]++;
    else if (len <= 10) slBuckets[1]++;
    else if (len <= 15) slBuckets[2]++;
    else if (len <= 20) slBuckets[3]++;
    else slBuckets[4]++;
  }
  const slTotal = allSentenceLengths.length || 1;
  lines.push(`Sentence length distribution:`);
  lines.push(`  1-5 words: ${pct(slBuckets[0], slTotal)} (${slBuckets[0]} sentences)`);
  lines.push(`  6-10 words: ${pct(slBuckets[1], slTotal)} (${slBuckets[1]} sentences)`);
  lines.push(`  11-15 words: ${pct(slBuckets[2], slTotal)} (${slBuckets[2]} sentences)`);
  lines.push(`  16-20 words: ${pct(slBuckets[3], slTotal)} (${slBuckets[3]} sentences)`);
  lines.push(`  21+ words: ${pct(slBuckets[4], slTotal)} (${slBuckets[4]} sentences)`);
  lines.push(`  Average: ${avg(allSentenceLengths).toFixed(1)} words/sentence`);
  lines.push(`  Median: ${median(allSentenceLengths)} words/sentence`);
  lines.push('');

  // Words per slide
  lines.push(`Words per slide:`);
  lines.push(`  Average: ${avg(allWordsPerSlide).toFixed(1)}`);
  lines.push(`  Median: ${median(allWordsPerSlide)}`);
  lines.push(`  Range: ${Math.min(...allWordsPerSlide)} - ${Math.max(...allWordsPerSlide)}`);
  lines.push('');

  // Sentences per slide
  lines.push(`Sentences per slide:`);
  lines.push(`  Average: ${avg(allSentencesPerSlide).toFixed(1)}`);
  lines.push(`  Median: ${median(allSentencesPerSlide)}`);
  lines.push('');

  // Starting word distribution (top 20)
  const topStarting = [...startingWords.entries()].sort((a, b) => b[1] - a[1]).slice(0, 50) /* show all meaningful entries */;
  lines.push(`Starting word distribution (top 20):`);
  for (const [word, count] of topStarting) {
    lines.push(`  "${word}": ${pct(count, totalSentences)} (${count} sentences)`);
  }
  lines.push('');

  // Punctuation
  lines.push(`Punctuation per ${totalSlides} slides:`);
  lines.push(`  Ellipsis (...): ${totalEllipsis} total (${(totalEllipsis / totalSlides * 100).toFixed(1)}% of slides)`);
  lines.push(`  Question marks: ${totalQuestionMarks} total (${(totalQuestionMarks / totalSentences * 100).toFixed(1)}% of sentences)`);
  lines.push(`  Exclamation marks: ${totalExclamations} total (${(totalExclamations / totalSentences * 100).toFixed(1)}% of sentences)`);
  lines.push(`  ALL CAPS words: ${totalCapsWords} total (${(totalCapsWords / totalSlides).toFixed(1)} per slide avg)`);
  lines.push('');

  // Contractions
  lines.push(`Contractions: ${totalContractions} total (${(totalContractions / totalSentences).toFixed(2)} per sentence)`);
  lines.push('');

  // Vocabulary complexity
  lines.push(`Average word length: ${avg(avgWordLengths).toFixed(1)} chars (lower = simpler vocabulary)`);
  lines.push('');

  // === PER-POST VOICE SIGNATURES (for Opus to examine individual patterns) ===
  lines.push(`\nPER-POST VOICE SIGNATURES (${postSignatures.length} posts — Opus: examine how each post constructs sentences):\n`);
  for (const sig of postSignatures) {
    lines.push(`"${truncate(sig.title, 50)}" [${sig.format.toUpperCase()}]:`);
    lines.push(`  Sentence lengths: [${sig.sentenceLengthSequence.join(', ')}]`);
    lines.push(`  Words/slide: [${sig.wordsPerSlide.join(', ')}]`);
    lines.push(`  Starting words: [${sig.startingWordSequence.join(', ')}]`);
    lines.push('');
  }

  return lines.join('\n');
}

// ============================================================
// Slide Bridges: Raw connector data between consecutive slides
// ============================================================

/**
 * Extract the actual text that bridges consecutive slides — the last ~15 words
 * of slide N and the first ~15 words of slide N+1. Raw data, no interpretation.
 */
function extractSlideBridges(entries: ProfileEntry[]): string {
  const lines: string[] = [];
  const bridges: Array<{ title: string; format: string; slideN: number; endText: string; startText: string }> = [];

  for (const entry of entries) {
    for (let i = 0; i < entry.slideTexts.length - 1; i++) {
      const slideA = entry.slideTexts[i];
      const slideB = entry.slideTexts[i + 1];
      if (!slideA || !slideB || slideA.length < 5 || slideB.length < 5) continue;

      // Last ~15 words of slide A
      const wordsA = slideA.trim().split(/\s+/);
      const endText = wordsA.slice(-15).join(' ');

      // First ~15 words of slide B
      const wordsB = slideB.trim().split(/\s+/);
      const startText = wordsB.slice(0, 15).join(' ');

      bridges.push({
        title: entry.title,
        format: entry.detectedFormat,
        slideN: i + 1,
        endText,
        startText,
      });
    }
  }

  // First word of each slide (transition opener distribution)
  const slideOpeners = new Map<string, number>();
  for (const bridge of bridges) {
    const firstWord = bridge.startText.split(/\s+/)[0]?.toLowerCase().replace(/[^a-z']/g, '');
    if (firstWord) {
      slideOpeners.set(firstWord, (slideOpeners.get(firstWord) || 0) + 1);
    }
  }

  lines.push(`Total bridges analyzed: ${bridges.length}\n`);

  // Slide opener distribution
  const topOpeners = [...slideOpeners.entries()].sort((a, b) => b[1] - a[1]).slice(0, 50) /* show all meaningful entries */;
  lines.push(`Slide opening word distribution (first word of each non-hook slide):`);
  for (const [word, count] of topOpeners) {
    lines.push(`  "${word}": ${pct(count, bridges.length)} (${count} slides)`);
  }
  lines.push('');

  // ALL bridges for Opus to study
  const sampleBridges = bridges.sort(() => Math.random() - 0.5); // shuffle for variety in order
  lines.push(`ALL BRIDGES (${bridges.length} real slide-to-slide connections):\n`);
  for (const b of sampleBridges) {
    lines.push(`[${b.format.toUpperCase()}] "${truncate(b.title, 40)}" Slide ${b.slideN}→${b.slideN + 1}:`);
    lines.push(`  END: "...${b.endText}"`);
    lines.push(`  START: "${b.startText}..."`);
    lines.push('');
  }

  return lines.join('\n');
}

/**
 * Classify a post's format by content density.
 * Reel: ≤2 sentences per slide (shorter text per slide)
 * Carousel: ≥3 sentences per slide (denser text per slide)
 */
function classifyFormat(slideTexts: string[]): 'reel' | 'carousel' | 'other' {
  if (slideTexts.length < 3) return 'other';
  let totalSentences = 0;
  for (const slide of slideTexts) {
    const sentences = (slide.match(/[.!?]+/g) || []).length;
    totalSentences += Math.max(sentences, 1);
  }
  const avgPerSlide = totalSentences / slideTexts.length;
  if (avgPerSlide <= 2) return 'reel';
  if (avgPerSlide >= 3) return 'carousel';
  return 'other';
}
