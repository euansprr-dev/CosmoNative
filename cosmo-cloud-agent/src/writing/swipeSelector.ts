// cosmo-cloud-agent/src/writing/swipeSelector.ts
// Swipe selection algorithm — selects best swipes for writing context
// PORTING SOURCE: UnifiedWritingEngine.selectSwipes() lines 3060-3200
//
// 4-axis scoring:
//   Axis 1 (30%): Format match — same format family?
//   Axis 2 (25%): Structural — beat pattern in top-10 for this format?
//   Axis 3 (20%): Stylistic — sentence length match vs client voice
//   Axis 4 (25%): Performance — hookScore normalized
//
// Selection uses weighted random sampling (NOT top-K) for diversity.

import { Atom, fetchAllByType, fetchAtom, isSwipeFileAtom } from '../db/queries';
import { CompressedSwipe, ContentFormat, FormatFamily, getFormatFamily } from './types';
import { config } from '../config';

const TARGET_SWIPE_COUNT = 20; // Match Swift's count for full pattern diversity
const MAX_SWIPE_POOL = 200;

/**
 * Select the best swipes for a content piece's writing context.
 * Source: UnifiedWritingEngine.selectSwipes() in Swift
 */
export async function selectSwipes(
  contentAtom: Atom,
  targetFormat: ContentFormat,
  primarySwipeUUIDs: string[] = [],
): Promise<CompressedSwipe[]> {
  const targetFamily = getFormatFamily(targetFormat);

  // Phase 1: Load all swipe candidates
  const allResearch = await fetchAllByType('research', { limit: MAX_SWIPE_POOL * 2 });
  const allSwipes = allResearch.filter(isSwipeFileAtom);

  if (allSwipes.length === 0) return [];

  // Build top fingerprints index (top 10 patterns by frequency for structural scoring)
  const fingerprintCounts = new Map<string, number>();
  for (const swipe of allSwipes) {
    const analysis = getAnalysis(swipe);
    const fp = analysis?.beatFingerprint as string;
    if (fp) fingerprintCounts.set(fp, (fingerprintCounts.get(fp) || 0) + 1);
  }
  const topFingerprints = new Set(
    [...fingerprintCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([fp]) => fp)
  );

  // Phase 2: Score each swipe on 4 axes
  const scored: Array<{ atom: Atom; score: number; isPrimary: boolean }> = [];

  for (const swipe of allSwipes) {
    const analysis = getAnalysis(swipe);
    if (!analysis) continue;

    const isPrimary = primarySwipeUUIDs.includes(swipe.uuid);

    // Axis 1: Format match — soft penalty for wrong format (was hard exclude, but that killed pool diversity)
    const swipeFormat = detectSwipeFormat(swipe);
    const formatScore = swipeFormat === targetFamily ? 1.0 : 0.15;

    // Axis 2: Structural — beat pattern quality (check against top patterns)
    const fingerprint = analysis.beatFingerprint as string;
    let structuralScore = 0.3;
    if (fingerprint) {
      structuralScore = topFingerprints.has(fingerprint) ? 1.0 : 0.7;
    }

    // Axis 3: Stylistic — sentence + word length matching (ported from Swift computeStylisticScore)
    const body = swipe.body || '';
    const stylisticScore = computeStylisticScore(body);

    // Axis 4: Performance — hookScore normalized
    const hookScore = (analysis.hookScore as number) || 5;
    const perfScore = Math.min(hookScore / 10, 1.0);

    // Weighted fusion
    let finalScore = 0.3 * formatScore + 0.25 * structuralScore + 0.2 * stylisticScore + 0.25 * perfScore;

    // Primary boost: +0.5 for inherited swipes
    if (isPrimary) finalScore += 0.5;

    scored.push({ atom: swipe, score: finalScore, isPrimary });
  }

  // Phase 2b: Recency diversity — deprioritize swipes recently used in other content atoms
  const recentlyUsed = await getRecentlySelectedSwipeUUIDs(15);
  if (recentlyUsed.size > 0) {
    let penalized = 0;
    for (const entry of scored) {
      if (recentlyUsed.has(entry.atom.uuid) && !entry.isPrimary) {
        entry.score *= 0.5; // 50% penalty, not exclusion
        penalized++;
      }
    }
    if (penalized > 0) {
      console.log(`    ✍️ Swipe diversity: penalized ${penalized}/${scored.length} recently-used swipes`);
    }
  }

  // Phase 3: Weighted random sampling
  const selected = weightedRandomSample(scored, TARGET_SWIPE_COUNT);

  // Phase 4: Compress selected swipes
  return selected.map(({ atom, isPrimary }) => compressSwipe(atom, isPrimary));
}

/**
 * Get UUIDs of swipes recently selected for other content atoms.
 * Used to penalize (not exclude) repetition across different content pieces.
 */
async function getRecentlySelectedSwipeUUIDs(limit: number): Promise<Set<string>> {
  try {
    const contentAtoms = await fetchAllByType('content', { limit });
    const uuids = new Set<string>();
    for (const atom of contentAtoms) {
      const selected = atom.metadata?.selectedSwipeUUIDs as string[] | undefined;
      if (selected) {
        for (const uuid of selected) uuids.add(uuid);
      }
    }
    return uuids;
  } catch {
    return new Set();
  }
}

/**
 * Weighted random sampling — NOT top-K.
 * Squares scores to widen gap, then cumulative weight sampling.
 * Source: UnifiedWritingEngine Phase 3 in selectSwipes()
 */
function weightedRandomSample(
  items: Array<{ atom: Atom; score: number; isPrimary: boolean }>,
  count: number,
): Array<{ atom: Atom; isPrimary: boolean }> {
  if (items.length <= count) {
    return items.map(i => ({ atom: i.atom, isPrimary: i.isPrimary }));
  }

  // Always pick primaries first
  const primaries = items.filter(i => i.isPrimary);
  const nonPrimaries = items.filter(i => !i.isPrimary);
  const selected: Array<{ atom: Atom; isPrimary: boolean }> = primaries.map(i => ({
    atom: i.atom,
    isPrimary: true,
  }));

  const remaining = count - selected.length;
  if (remaining <= 0) return selected.slice(0, count);

  // Square scores to widen gap
  const weighted = nonPrimaries.map(i => ({
    ...i,
    weight: i.score * i.score,
  }));

  const usedFingerprints = new Set<string>();
  const totalWeight = weighted.reduce((sum, w) => sum + w.weight, 0);

  for (let i = 0; i < remaining && weighted.length > 0; i++) {
    let target = Math.random() * totalWeight;
    let picked = false;

    for (let j = 0; j < weighted.length; j++) {
      target -= weighted[j].weight;
      if (target <= 0) {
        const item = weighted[j];
        const fingerprint = getAnalysis(item.atom)?.beatFingerprint as string;

        // Skip duplicate fingerprints for diversity (unless pool exhausted)
        if (fingerprint && usedFingerprints.has(fingerprint) && weighted.length > remaining - i) {
          continue;
        }

        if (fingerprint) usedFingerprints.add(fingerprint);
        selected.push({ atom: item.atom, isPrimary: false });
        weighted.splice(j, 1);
        picked = true;
        break;
      }
    }

    // Fallback: pick first remaining if no weighted selection happened
    if (!picked && weighted.length > 0) {
      selected.push({ atom: weighted[0].atom, isPrimary: false });
      weighted.splice(0, 1);
    }
  }

  return selected;
}

// ============================================================
// Compression
// ============================================================

/**
 * Compress a swipe atom into the CompressedSwipe format for Block 3A.
 * Source: compressSwipe() in UnifiedWritingEngine.swift lines 3312-3384
 */
function compressSwipe(atom: Atom, isPrimary: boolean): CompressedSwipe {
  const analysis = getAnalysis(atom) || {};

  // Beat sequence from fingerprint or sections
  const fingerprint = (analysis.beatFingerprint as string) || '';
  const beatSequence = fingerprint
    ? fingerprint.split('>').map((b: string) => b.trim()).filter(Boolean)
    : ((analysis.sections as any[]) || []).map((s: any) => s.beatLabel || s.title || 'Unknown').slice(0, 8);

  // Hook text: full hookText or first 500 chars of body
  const hookText = (analysis.hookText as string)
    || (atom.body ? atom.body.substring(0, 500) : '');

  // Key transitions: first sentence of each non-hook section
  const sections = (analysis.sections as any[]) || [];
  const keyTransitions = sections.slice(1).map((s: any) => {
    const text = s.text || s.content || '';
    const firstSentence = text.split(/[.!?]/)[0];
    return firstSentence ? firstSentence.substring(0, 100) : '';
  }).filter(Boolean).slice(0, 5);

  // CTA: last paragraph
  const body = atom.body || '';
  const paragraphs = body.split('\n\n').filter(Boolean);
  const ctaText = paragraphs.length > 0 ? paragraphs[paragraphs.length - 1].substring(0, 150) : '';

  // Persuasion techniques
  const persuasion = (analysis.persuasionTypes as any[]) || [];
  const persuasionTechniques = persuasion
    .slice(0, 5)
    .map((p: any) => typeof p === 'string' ? p : `${p.type || p.name} (${p.intensity || p.score || '?'})`);

  // Emotional arc
  const emotions = (analysis.emotions as any[]) || [];
  const emotionalArc = emotions.slice(0, 6).map((e: any) => typeof e === 'string' ? e : e.name || String(e));

  // Structural breakdown for primary swipes
  let structuralBreakdown = '';
  if (isPrimary && sections.length > 0) {
    structuralBreakdown = sections.map((s: any, i: number) => {
      const beat = s.beatLabel || s.title || `Section ${i + 1}`;
      const role = s.function || s.role || 'Content';
      return `${i + 1}. [${beat}] ${role}`;
    }).join('\n');
  }

  return {
    uuid: atom.uuid,
    title: atom.title || 'Untitled Swipe',
    hookText,
    hookType: (analysis.hookType as string) || 'Unknown',
    hookScore: (analysis.hookScore as number) || 5,
    beatSequence,
    beatFingerprint: fingerprint,
    keyTransitions,
    ctaText,
    framework: (analysis.frameworkType as string) || 'Original',
    format: (atom.metadata?.contentSource as string) || 'Unknown',
    isPrimary,
    isClientExample: false,
    engagementSummary: '',
    fullBody: body,
    structuralBreakdown,
    persuasionTechniques,
    emotionalArc,
    hookScoreReason: (analysis.hookScoreReason as string) || '',
    hookMechanism: (analysis.hookMechanism as string) || '',
    structuralRecipe: (analysis.structuralRecipe as string) || '',
    voiceMarkers: (analysis.voiceMarkers as string[]) || [],
  };
}

// ============================================================
// Swipe Intelligence Brief (aggregated patterns)
// ============================================================

export function computeSwipeIntelligenceBrief(swipes: CompressedSwipe[]): string {
  if (swipes.length === 0) return '';

  const lines: string[] = ['=== SWIPE INTELLIGENCE BRIEF ===', `Aggregated from ${swipes.length} selected swipes:`, ''];

  // HOOK PATTERNS
  lines.push('HOOK PATTERNS:');
  const hookTypeCounts: Record<string, number> = {};
  let totalHookWords = 0;
  for (const s of swipes) {
    hookTypeCounts[s.hookType] = (hookTypeCounts[s.hookType] || 0) + 1;
    totalHookWords += s.hookText.split(/\s+/).length;
  }
  const topHooks = Object.entries(hookTypeCounts).sort((a, b) => b[1] - a[1]).slice(0, 3);
  lines.push(`‣ Top hook types: ${topHooks.map(([h, c]) => `${h} (${c}x)`).join(', ')}`);
  lines.push(`‣ Average hook length: ${Math.round(totalHookWords / swipes.length)} words`);

  // Mechanisms
  const mechanisms = swipes.filter(s => s.hookMechanism).map(s => s.hookMechanism);
  if (mechanisms.length > 0) {
    lines.push(`‣ Hook mechanisms: ${mechanisms.slice(0, 3).join('; ')}`);
  }

  // STRUCTURAL PATTERNS
  lines.push('');
  lines.push('STRUCTURAL PATTERNS:');
  const avgSections = swipes.reduce((sum, s) => sum + s.beatSequence.length, 0) / swipes.length;
  lines.push(`‣ Average section count: ${Math.round(avgSections)}`);

  // Most common beat pattern
  const fingerprints: Record<string, number> = {};
  for (const s of swipes) {
    const fp = s.beatSequence.join(' > ');
    fingerprints[fp] = (fingerprints[fp] || 0) + 1;
  }
  const topFP = Object.entries(fingerprints).sort((a, b) => b[1] - a[1])[0];
  if (topFP) {
    lines.push(`‣ Most common pattern: ${topFP[0]}`);
  }

  // Best swipe's recipe
  const bestSwipe = swipes.reduce((best, s) => s.hookScore > best.hookScore ? s : best, swipes[0]);
  if (bestSwipe.structuralRecipe) {
    lines.push(`‣ Recipe from best swipe (${bestSwipe.hookScore}/10):`);
    for (const line of bestSwipe.structuralRecipe.split('\n')) {
      lines.push(`    ${line.trim()}`);
    }
  }

  // VOICE PATTERNS
  const allVoiceMarkers: Record<string, number> = {};
  for (const s of swipes) {
    for (const v of s.voiceMarkers) {
      allVoiceMarkers[v] = (allVoiceMarkers[v] || 0) + 1;
    }
  }
  const topVoice = Object.entries(allVoiceMarkers).sort((a, b) => b[1] - a[1]).slice(0, 4);
  if (topVoice.length > 0) {
    lines.push('');
    lines.push('VOICE PATTERNS:');
    lines.push(`‣ Dominant voice traits: ${topVoice.map(([v, c]) => `${v} (${c}/${swipes.length})`).join(', ')}`);
  }

  // WHAT MAKES THESE WORK
  lines.push('');
  lines.push('WHAT MAKES THESE WORK:');
  const avgScore = swipes.reduce((sum, s) => sum + s.hookScore, 0) / swipes.length;
  lines.push(`‣ Average hook score: ${avgScore.toFixed(1)}/10`);
  const highScorers = swipes.filter(s => s.hookScore >= 8);
  if (highScorers.length > 0) {
    lines.push(`‣ ${highScorers.length}/${swipes.length} swipes score 8+ — study these patterns`);
  }

  // FORMATTING DNA (measured from loaded swipes)
  const stats = computeStyleDNA(swipes);
  if (stats.totalSlidesAnalyzed > 0) {
    lines.push('');
    lines.push('FORMATTING DNA (measured from your loaded swipes):');
    lines.push(`‣ Em-dashes: ${stats.swipesWithEmDash}/${swipes.length} swipes use em-dashes${stats.swipesWithEmDash === 0 ? ' → NONE of your reference swipes use them' : ''}`);
    lines.push(`‣ Density: avg ${stats.avgSentencesPerSlide.toFixed(1)} sentences per slide`);
    lines.push(`‣ Words per slide: avg ${stats.avgWordsPerSlide}`);
    lines.push(`‣ Sentence length: avg ${stats.avgWordsPerSentence} words`);
    lines.push(`‣ Slide count: range ${stats.slideCountRange[0]}-${stats.slideCountRange[1]}, avg ${stats.avgSlideCount}`);
    for (const line of stats.evidenceLines) {
      lines.push(`‣ ${line}`);
    }
  }

  return lines.join('\n');
}

// ============================================================
// Style DNA — Structural Statistics from Loaded Swipes
// ============================================================

export interface StyleDNA {
  avgSentencesPerSlide: number;
  avgWordsPerSlide: number;
  avgWordsPerSentence: number;
  slideCountRange: [number, number];
  avgSlideCount: number;
  emDashCount: number;
  swipesWithEmDash: number;
  totalSwipes: number;
  totalSlidesAnalyzed: number;
  evidenceLines: string[];
}

/**
 * Extract individual slide/paragraph texts from a swipe body.
 * Tries JSON → Slide N headers → double-newline paragraphs.
 */
export function extractSlideTexts(body: string): string[] {
  if (!body || body.trim().length === 0) return [];

  // Try JSON parse (carousel or thread format)
  try {
    const parsed = JSON.parse(body);
    if (parsed.slides && Array.isArray(parsed.slides)) {
      return parsed.slides.map((s: any) => (typeof s === 'string' ? s : s.text || '').trim()).filter(Boolean);
    }
    if (parsed.tweets && Array.isArray(parsed.tweets)) {
      return parsed.tweets.map((t: any) => (typeof t === 'string' ? t : t.text || '').trim()).filter(Boolean);
    }
  } catch {
    // Not JSON — try text-based parsing
  }

  // Try Slide N headers (plaintext carousel format)
  const slideHeaderPattern = /^Slide \d+/im;
  if (slideHeaderPattern.test(body)) {
    const parts = body.split(/^Slide \d+[^\n]*/im).filter(s => s.trim().length > 0);
    if (parts.length >= 3) return parts.map(s => s.trim());
  }

  // Fallback: double-newline paragraphs
  const paragraphs = body.split(/\n\n+/).map(p => p.trim()).filter(p => p.length > 0);
  if (paragraphs.length >= 3) return paragraphs;

  // Single block — return as one "slide"
  return [body.trim()];
}

/**
 * Compute measurable structural statistics from loaded swipes.
 * These are evidence-based observations, not hardcoded rules.
 */
export function computeStyleDNA(swipes: CompressedSwipe[]): StyleDNA {
  let totalEmDashes = 0;
  let swipesWithEmDash = 0;
  let totalSlides = 0;
  let totalSentences = 0;
  let totalWords = 0;
  let totalSentenceWords = 0;
  let totalSentenceCount = 0;
  let swipesAnalyzed = 0;
  let minSlides = Infinity;
  let maxSlides = 0;
  const evidenceLines: string[] = [];

  for (const swipe of swipes) {
    const body = swipe.fullBody;
    if (!body || body.trim().length === 0) continue;

    // Em-dash usage
    const emDashes = (body.match(/[\u2014\u2013]/g) || []).length;
    totalEmDashes += emDashes;
    if (emDashes > 0) swipesWithEmDash++;

    // Extract slides
    const slides = extractSlideTexts(body);
    if (slides.length >= 2) {
      swipesAnalyzed++;
      const slideCount = slides.length;
      totalSlides += slideCount;
      if (slideCount < minSlides) minSlides = slideCount;
      if (slideCount > maxSlides) maxSlides = slideCount;

      for (const slide of slides) {
        // Words per slide
        const words = slide.split(/\s+/).filter(Boolean);
        totalWords += words.length;

        // Sentences per slide
        const sentences = slide.match(/[^.!?]*[.!?]+(?:\s|$)/g) || [];
        const sentCount = Math.max(sentences.length, 1);
        totalSentences += sentCount;

        // Words per sentence
        for (const sent of sentences) {
          const sentWords = sent.trim().split(/\s+/).filter(Boolean).length;
          if (sentWords > 0) {
            totalSentenceWords += sentWords;
            totalSentenceCount++;
          }
        }
      }
    }
  }

  const avgSentencesPerSlide = totalSlides > 0 ? totalSentences / totalSlides : 0;
  const avgWordsPerSlide = totalSlides > 0 ? Math.round(totalWords / totalSlides) : 0;
  const avgWordsPerSentence = totalSentenceCount > 0 ? Math.round(totalSentenceWords / totalSentenceCount) : 0;
  const avgSlideCount = swipesAnalyzed > 0 ? Math.round(totalSlides / swipesAnalyzed) : 0;

  if (minSlides === Infinity) minSlides = 0;

  // Build evidence lines
  if (swipesWithEmDash === 0 && swipes.length > 0) {
    evidenceLines.push('Zero em-dashes across all loaded swipes — this punctuation is not part of high-performing content');
  }
  if (avgSentencesPerSlide > 0 && avgSentencesPerSlide <= 1.5) {
    evidenceLines.push('Swipes use ~1 sentence per slide — short, punchy, one-breath rhythm');
  } else if (avgSentencesPerSlide > 3) {
    evidenceLines.push(`Swipes use ~${avgSentencesPerSlide.toFixed(0)} sentences per slide — denser, storytelling rhythm`);
  }

  return {
    avgSentencesPerSlide,
    avgWordsPerSlide,
    avgWordsPerSentence,
    slideCountRange: [minSlides, maxSlides],
    avgSlideCount,
    emDashCount: totalEmDashes,
    swipesWithEmDash,
    totalSwipes: swipes.length,
    totalSlidesAnalyzed: swipesAnalyzed,
    evidenceLines,
  };
}

// ============================================================
// Helpers
// ============================================================

function getAnalysis(atom: Atom): Record<string, any> | null {
  if (!atom.structured) return null;
  if (atom.structured.swipeAnalysis) return atom.structured.swipeAnalysis;
  if (atom.structured.hookType) return atom.structured;
  return null;
}

function detectSwipeFormat(atom: Atom): FormatFamily {
  const analysis = getAnalysis(atom);

  // Priority 1: AI taxonomy swipeContentFormat (most accurate — user confirmed)
  const format = analysis?.swipeContentFormat as string | undefined;
  if (format) {
    const f = format.toLowerCase();
    if (f.includes('reel') || f.includes('tiktok') || f.includes('voiceover')) return 'reel';
    if (f.includes('carousel')) return 'carousel_thread';
    if (f.includes('thread')) return 'carousel_thread';
    if (f.includes('static') || f === 'post') return 'post';
    if (f.includes('youtube') || f.includes('long form')) return 'youtube';
    if (f.includes('newsletter')) return 'newsletter';
  }

  // Priority 2: Rich content type signals (capture-time, reliable)
  const richContent = atom.structured?.richContent || atom.structured;
  const instagramType = (richContent?.instagramType as string || '').toLowerCase();
  const sourceType = (richContent?.sourceType as string || '').toLowerCase();
  const contentType = (richContent?.instagramData?.contentType as string || '').toLowerCase();

  if (instagramType.includes('reel') || sourceType.includes('reel') || contentType.includes('reel')) return 'reel';
  if (instagramType.includes('carousel') || contentType.includes('carousel')) return 'carousel_thread';

  // Priority 3: URL pattern
  const sourceUrl = (atom.metadata?.sourceUrl || richContent?.sourceURL) as string | undefined;
  if (sourceUrl) {
    if (sourceUrl.includes('/reel/') || sourceUrl.includes('/reels/')) return 'reel';
    if (sourceUrl.includes('/p/') && richContent?.instagramData?.carouselItems) return 'carousel_thread';
  }

  // Priority 4: Generic contentSource (LEAST reliable)
  const source = (atom.metadata?.contentSource as string || '').toLowerCase();
  if (source.includes('youtube')) return 'youtube';
  if (source.includes('tiktok')) return 'reel';
  if (source.includes('twitter') || source.includes('x.com')) return 'carousel_thread';
  if (source.includes('linkedin')) return 'post';

  // Default: carousel_thread (safe for Instagram where type is unknown)
  return 'carousel_thread';
}

/**
 * Compute stylistic score based on sentence and word length matching.
 * Ported from Swift: UnifiedWritingEngine.computeStylisticScore() lines 3292-3309
 * Swipes with natural sentence lengths (5-15 words) and moderate word lengths (3-7 chars)
 * score higher — they're more likely to match a conversational client voice.
 */
function computeStylisticScore(transcript: string): number {
  if (!transcript || transcript.length === 0) return 0.5;

  // Split on sentence boundaries
  const sentences = transcript.split(/[.!?]/).filter(s => s.trim().length > 0);

  // Average sentence length in words
  const avgSentenceLen = sentences.length > 0
    ? sentences.map(s => s.trim().split(/\s+/).length).reduce((a, b) => a + b, 0) / sentences.length
    : 0;

  // Average word length in characters
  const words = transcript.split(/\s+/).filter(w => w.length > 0);
  const avgWordLen = words.length > 0
    ? words.map(w => w.length).reduce((a, b) => a + b, 0) / words.length
    : 0;

  // Scoring tiers (matching Swift logic)
  let score = 0.5; // Base 50%
  if (avgSentenceLen >= 5 && avgSentenceLen <= 15) score += 0.25; // +25% for natural sentence length
  if (avgWordLen >= 3 && avgWordLen <= 7) score += 0.25;           // +25% for moderate word length

  return Math.min(score, 1.0);
}
