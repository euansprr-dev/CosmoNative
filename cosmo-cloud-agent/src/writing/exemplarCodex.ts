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

export async function prepareExemplarData(options?: { skipProfiles?: boolean }): Promise<{ codexText: string; stats: ExemplarCodexStats }> {
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
      stats: { totalProfiles: profiledAtoms.length },
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

  lines.push(`RAW SLIDE DATA — ${N} curated viral posts`);
  lines.push(`Format split: ${reelCount} reels, ${carouselCount} carousels, ${otherCount} other`);
  lines.push(`Each post is tagged [REEL] or [CAROUSEL].\n`);

  if (!options?.skipProfiles) {
    lines.push(`NOTE: Different extractions may use different names for the same concept.`);
    lines.push(`Opus will unify naming and curate the definitive language.\n`);
    lines.push(`STRUCTURE: Part 1 = Every post individually (full text + quark profile).`);
    lines.push(`           Part 2 = Aggregated voice DNA.\n`);
    lines.push(`PROFILE NOTATION LEGEND (compact format — every field from the 10-pass extraction):`);
    lines.push(`  SA = Speech Act (type + mechanism). What the speaker is psychologically doing.`);
    lines.push(`  RD = Reader Deltas (what changes in reader's mind + how). Multiple per slide.`);
    lines.push(`  F = Frame (how slide positions its content: loss/decision/consequence/success/setup/etc).`);
    lines.push(`  D = Experiential Distance (zero=inside moment | near=telling friend | far=reporting).`);
    lines.push(`  P = Proof Type (metric/sacrifice/timeline/sensory/named-entity/contradiction).`);
    lines.push(`  M = Motivation (escape/identity/money/love/defiance — why subject acts NOW).`);
    lines.push(`  C = Compression (how skipped time/info is handled: earned/intriguing/confusing).`);
    lines.push(`  T = Techniques (craft moves: ALL-CAPS, ellipsis, subject-drop, present-tense-shift, etc).`);
    lines.push(`  RF = Resonance Frequency (detail that hits mass unspoken experience + reach).`);
    lines.push(`  Transitions: from→to type(mechanism) [DH]=double helix [S]=strong(can't swap)`);
    lines.push(`  RSV: OL=open loops TR=trust TN=tension PE=pattern expectation FR=frame EB=energy balance SP=superpositions`);
    lines.push(`  Reader Sim: EM=emotion INV=investment Qs=active questions AS=assumptions PR=prediction\n`);
  }

  // ═══════════════════════════════════════════════════
  // PART 1: EVERY POST — Full body text
  // ═══════════════════════════════════════════════════
  lines.push(`${'═'.repeat(70)}`);
  lines.push(`PART 1: ALL ${N} POSTS — Full text${options?.skipProfiles ? '' : ' + Complete Content Physics Profile'}`);
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
    if (!options?.skipProfiles) {
      lines.push(`┌─ CONTENT PHYSICS PROFILE ${'─'.repeat(42)}┐`);
      lines.push(formatProfileAsText(entry.profile));
      lines.push(`└${'─'.repeat(66)}┘`);
    }
  }

  // ═══════════════════════════════════════════════════
  // PART 2: AGGREGATED DATA (voice DNA + bridges only — Opus does its own concept grouping from Part 1)
  // ═══════════════════════════════════════════════════
  lines.push(`${'═'.repeat(70)}`);
  lines.push(`PART 2: AGGREGATED VOICE + BRIDGE DATA`);
  lines.push(`${'═'.repeat(70)}\n`);

  // SKIP concept groupings — Opus already has all posts individually in Part 1
  // and will do its own unified taxonomy. Jump straight to voice DNA + bridges.

  // ═══════════════════════════════════════════════════
  // [Concept groupings removed — Opus analyzes posts directly from Part 1]
  // VOICE DNA — Raw quantitative text analysis (no interpretation, let Opus discover)
  // ═══════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`VOICE DNA — Raw text metrics from ${N} viral posts (Opus: discover what matters)`);
  lines.push(`${'═'.repeat(60)}\n`);

  const voiceDNA = extractVoiceDNA(entries);
  lines.push(voiceDNA);

  // Bridges removed — Opus already has all slide text per post in Part 1.
  // Voice DNA above captures the aggregate opening-word patterns.

  // ═══════════════════════════════════════════════════
  // STATS SUMMARY
  // ═══════════════════════════════════════════════════
  lines.push(`\n${'═'.repeat(60)}`);
  lines.push(`CODEX STATISTICS`);
  lines.push(`${'═'.repeat(60)}\n`);
  lines.push(`Total profiles analyzed: ${N}`);
  lines.push(`Opus will analyze all posts and create unified concept taxonomy with real examples.`);
  lines.push(`All posts are curated high-quality viral content.`);

  const codexText = lines.join('\n');
  console.log(`  📊 Exemplar data prepared: ${N} posts, ${codexText.length} chars (~${Math.round(codexText.length / 4)} tokens)`);

  return {
    codexText,
    stats: { totalProfiles: N },
  };
}

// ============================================================
// Helpers
// ============================================================

interface ExemplarCodexStats {
  totalProfiles: number;
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
 * Format a single post's quark profile in COMPACT notation.
 * Same data, ~60% smaller. Legend is in the prep data header.
 */
function formatProfileAsText(profile: QuarkProfile): string {
  const lines: string[] = [];
  const m = (v: string | undefined) => v ? v.substring(0, 80) : ''; // cap mechanism length

  // Per-slide quarks — one line per slide
  for (const sq of profile.slideQuarks) {
    let line = `  S${sq.slideNumber}: SA=${sq.speechAct?.type || '?'}(${m(sq.speechAct?.mechanism)})`;
    if (sq.readerDeltas?.length) line += ` RD=[${sq.readerDeltas.map(d => `${d.type}(${m(d.mechanism)})`).join(',')}]`;
    if (sq.frame) line += ` F=${sq.frame.type || '?'}`;
    if (sq.experientialDistance) line += ` D=${(sq.experientialDistance as any).level || (sq.experientialDistance as any).type || '?'}`;
    if (sq.proofType) line += ` P=${sq.proofType.type || '?'}(${m(sq.proofType.mechanism)})`;
    if (sq.motivation) line += ` M=${sq.motivation.type || '?'}`;
    if (sq.compression) line += ` C=${sq.compression.type}`;
    if (sq.techniques?.length) line += ` T=[${sq.techniques.map(t => t.technique).join(',')}]`;
    if (sq.resonanceFrequency?.detail) line += ` RF="${sq.resonanceFrequency.detail}"(reach:${sq.resonanceFrequency.estimatedReach || '?'})`;
    lines.push(line);
  }

  // Transitions — one line each
  if (profile.transitions?.length) {
    for (const t of profile.transitions) {
      lines.push(`  ${t.from}→${t.to}: ${t.type}(${m(t.mechanism)})${t.doubleHelix ? ' [DH]' : ''}${t.swapTestPasses === false ? ' [S]' : ''}`);
    }
  }

  // Arc — one line
  if (profile.arcQuarks) {
    const a = profile.arcQuarks;
    let line = `  Arc: ${a.shape || '?'} rev=${a.winLossReversals || 0}`;
    if (a.tensionPeaks?.length) line += ` peaks=[${a.tensionPeaks.join(',')}]`;
    if (a.dominantFrame) line += ` frame=${a.dominantFrame.type}`;
    if (a.internalExternalTension?.present) line += ` int/ext@${a.internalExternalTension.peakSlide || '?'}`;
    if (a.sparseDensePattern) line += ` density=${a.sparseDensePattern}`;
    lines.push(line);
  }

  // Physics events — one line each
  if (profile.physicsEvents) {
    const pe = profile.physicsEvents;
    if (pe.symmetryBreak?.slideNumber) lines.push(`  SymBreak@${pe.symmetryBreak.slideNumber}: pattern="${m(pe.symmetryBreak.patternEstablished)}" breaks="${m(pe.symmetryBreak.whatBreaks)}"`);
    if (pe.phaseTransition?.slideNumber) lines.push(`  PhaseT@${pe.phaseTransition.slideNumber}: "${pe.phaseTransition.frameBefore}"→"${pe.phaseTransition.frameAfter}" recon="${m(pe.phaseTransition.recontextualization)}"`);
    if (pe.peakGravity?.slideNumber) lines.push(`  Gravity@${pe.peakGravity.slideNumber}: ${pe.peakGravity.activeLoops}loops${pe.peakGravity.coincidesWithTransition ? ' [WITH-TRANSITION]' : ''}`);
    if (pe.energyResolution) {
      let eLine = `  Energy: ${pe.energyResolution.proportional ? 'proportional' : 'DISPROPORTIONAL'}`;
      if (pe.energyResolution.loopsClosed?.length) eLine += ` closed=[${pe.energyResolution.loopsClosed.map(l => `"${l.loop}"@${l.closedAtSlide}`).join(',')}]`;
      if (pe.energyResolution.loopsUnclosed?.length) eLine += ` UNCLOSED=[${pe.energyResolution.loopsUnclosed.join(',')}]`;
      lines.push(eLine);
    }
  }

  // RSV — one line per trajectory point
  if (profile.rsv?.trajectoryPoints?.length) {
    for (const pt of profile.rsv.trajectoryPoints) {
      let line = `  RSV@${pt.afterSlide}: OL=${pt.openLoops?.count || 0}`;
      if (pt.openLoops?.loops?.length) line += `[${pt.openLoops.loops.join(';')}]`;
      line += ` TR=${pt.trust || '?'} TN=${pt.tension?.level || '?'}(${pt.tension?.type || '?'}) FR="${pt.frame || '?'}" EB=${pt.energyBalance || '?'}`;
      if (pt.patternExpectation) line += ` PE="${m(pt.patternExpectation)}"`;
      if (pt.superpositionCount) line += ` SP=${pt.superpositionCount}`;
      lines.push(line);
    }
  }

  // Long-range — compact
  if (profile.longRangeInteractions) {
    const lr = profile.longRangeInteractions;
    if (lr.setupPayoffBonds?.length) for (const b of lr.setupPayoffBonds) lines.push(`  Bond: S${b.setupSlide}→S${b.payoffSlide}(${b.distance}) planted="${m(b.planted)}" harvested="${m(b.harvested)}"`);
    if (lr.echoPatterns?.length) for (const e of lr.echoPatterns) lines.push(`  Echo: "${e.quarkType}"@[${e.positions?.join(',')}] ${m(e.transformation)}`);
    if (lr.deliberateAbsences?.length) for (const a of lr.deliberateAbsences) lines.push(`  Absence: "${m(a.what)}"→${m(a.effect)}`);
    if (lr.entanglementPairs?.length) for (const ep of lr.entanglementPairs) lines.push(`  Entangle: S${ep.slideA}↔S${ep.slideB}`);
    if (lr.callbackChains?.length) for (const cc of lr.callbackChains) lines.push(`  Callback: "${cc.element}"×${cc.appearances?.length || 0} arc=${m(cc.transformationArc)}`);
    if (lr.interferences?.length) for (const ie of lr.interferences) lines.push(`  Interfere: [${ie.slides?.join(',')}]→${m(ie.emergentEffect)}`);
  }

  // Rhythm — one line
  if (profile.rhythm) {
    let line = `  Rhythm: ${profile.rhythm.momentumMechanism || '?'}`;
    if (profile.rhythm.energyCurve?.length) line += ` E=[${profile.rhythm.energyCurve.join(',')}]`;
    if (profile.rhythm.densityWaveform?.length) line += ` D=[${profile.rhythm.densityWaveform.join(',')}]`;
    if (profile.rhythm.silenceSlides?.length) line += ` silence=[${profile.rhythm.silenceSlides.join(',')}]`;
    lines.push(line);
  }

  // Reader simulation — one line per slide
  if (profile.readerSimulation?.length) {
    for (const rs of profile.readerSimulation) {
      let line = `  Sim@${rs.afterSlide}: EM=${rs.dominantEmotion || '?'} INV=${rs.investmentLevel || '?'}`;
      if (rs.activeQuestions?.length) line += ` Qs=[${rs.activeQuestions.map(q => m(q)).join(';')}]`;
      if (rs.builtAssumptions?.length) line += ` AS=[${rs.builtAssumptions.map(a => m(a)).join(';')}]`;
      if (rs.prediction) line += ` PR="${m(rs.prediction)}"`;
      lines.push(line);
    }
  }

  if (profile.antimatter?.length) lines.push(`  Antimatter: ${profile.antimatter.join(' | ')}`);
  if (profile.novelDiscoveries?.length) lines.push(`  Novel: ${(profile.novelDiscoveries as any[]).map((d: any) => typeof d === 'string' ? d : JSON.stringify(d)).join(' | ')}`);
  if (profile.deepFabric) lines.push(`  Fabric: ${truncate(profile.deepFabric, 300)}`);

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
