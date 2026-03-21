// cosmo-cloud-agent/src/tools/analytics.ts
// Analytics tools — 2 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 1822-1860

import { fetchAllByType } from '../db/queries';
import { jsonEncode } from '../agent/toolExecutor';

// ============================================================
// 1. get_dimension_xp
// PORTING CHECKLIST: AgentToolExecutor.swift line 1822
// ✅ No params
// ✅ Legacy system removed in Swift — returns stub
// ✅ Return: {dimensions: [], overallLevel: 1, overallTrend: "stable"}
// ============================================================

export async function getDimensionXp(_args: Record<string, any>): Promise<string> {
  return jsonEncode({
    dimensions: [],
    overallLevel: 1,
    overallTrend: 'stable',
  });
}

// ============================================================
// 2. get_streak_data
// PORTING CHECKLIST: AgentToolExecutor.swift line 1831
// ✅ No params
// ✅ Query dimensionSnapshot atoms, extract dates, count consecutive
// ✅ Return: {streaks: {overall: N}}
// ============================================================

export async function getStreakData(_args: Record<string, any>): Promise<string> {
  const snapshots = await fetchAllByType('dimension_snapshot', { limit: 365 });

  // Extract unique dates, sorted descending
  const dates = [...new Set(
    snapshots.map(a => a.created_at.split('T')[0])
  )].sort().reverse();

  // Count consecutive days from today
  let streak = 0;
  const today = new Date();
  for (let i = 0; i < dates.length; i++) {
    const expected = new Date(today);
    expected.setDate(expected.getDate() - i);
    const expectedStr = expected.toISOString().split('T')[0];
    if (dates[i] === expectedStr) {
      streak++;
    } else {
      break;
    }
  }

  return jsonEncode({
    streaks: { overall: streak },
  });
}
