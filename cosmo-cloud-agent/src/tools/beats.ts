// cosmo-cloud-agent/src/tools/beats.ts
// Beat pattern tools — 1 tool ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift line 3133

import { fetchAllByType, isSwipeFileAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// get_beat_patterns
// PORTING CHECKLIST: AgentToolExecutor.swift line 3133
// ✅ format, niche, limit (default 5, cap 20) all optional
// ✅ Aggregates beat fingerprints from swipe structured data
// ✅ Return: {patterns: [{fingerprint, beatSequence, frequency, avgHookScore}], count}
// ============================================================

export async function getBeatPatterns(args: Record<string, any>): Promise<string> {
  const format = args.format as string | undefined;
  const niche = args.niche as string | undefined;
  const limit = Math.min((args.limit as number) || 5, 20);

  const allResearch = await fetchAllByType('research', { limit: 2000 });
  const swipes = allResearch.filter(isSwipeFileAtom);

  // Aggregate beat fingerprints
  const patternMap: Record<string, { count: number; totalHookScore: number; beats: string[] }> = {};

  for (const s of swipes) {
    const analysis = s.structured?.swipeAnalysis || s.structured;
    if (!analysis) continue;

    const fingerprint = analysis.beatFingerprint as string;
    if (!fingerprint) continue;

    // Apply format/niche filters
    if (format && analysis.contentFormat !== format) continue;
    if (niche && analysis.niche !== niche) continue;

    if (!patternMap[fingerprint]) {
      patternMap[fingerprint] = {
        count: 0,
        totalHookScore: 0,
        beats: (analysis.beatSequence as string[]) || fingerprint.split('-'),
      };
    }

    patternMap[fingerprint].count++;
    patternMap[fingerprint].totalHookScore += (analysis.hookScore as number) || 0;
  }

  const patterns = Object.entries(patternMap)
    .map(([fingerprint, data]) => ({
      fingerprint,
      beatSequence: data.beats,
      frequency: data.count,
      avgHookScore: data.count > 0 ? Math.round((data.totalHookScore / data.count) * 10) / 10 : 0,
      swipeCount: data.count,
    }))
    .sort((a, b) => b.frequency - a.frequency)
    .slice(0, limit);

  return jsonEncode({
    patterns,
    count: patterns.length,
  });
}
