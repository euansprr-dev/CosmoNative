// cosmo-cloud-agent/src/tools/lessons.ts
// Lesson tools — 4 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 2576-2720

import { fetchAllByType, createAtom, updateAtom, deleteAtom, fuzzyFindClient } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

const VALID_CATEGORIES = [
  'hook_style', 'voice', 'structure', 'format', 'cta',
  'scheduling', 'productivity', 'time_management',
  'strategy_pattern', 'audience_insight', 'analysis_method',
  'reflection_prompt', 'general',
];

// ============================================================
// 1. save_lessons
// PORTING CHECKLIST: AgentToolExecutor.swift line 2576
// ✅ lessons array required (each: {rule, category, evidence?, intent?, targetModule?})
// ✅ clientName optional → resolves to clientUUID
// ✅ Validates category against whitelist
// ✅ Creates agent_learning atoms
// ✅ Return: {success, savedCount, message}
// ============================================================

export async function saveLessons(args: Record<string, any>): Promise<string> {
  const lessons = args.lessons as any[];
  if (!lessons || !Array.isArray(lessons) || lessons.length === 0) {
    return jsonError('lessons array is required');
  }

  let clientUUID: string | undefined;
  if (args.clientName) {
    const client = await fuzzyFindClient(args.clientName);
    if (client) clientUUID = client.uuid;
  }

  let savedCount = 0;

  for (const lesson of lessons) {
    const rule = lesson.rule as string;
    if (!rule) continue;

    const category = VALID_CATEGORIES.includes(lesson.category) ? lesson.category : 'general';

    const lessonId = crypto.randomUUID().toUpperCase();
    const now = new Date().toISOString();

    await createAtom({
      type: 'agent_learning',
      title: rule.substring(0, 100),
      body: rule,
      // structured must match Swift's InferredLesson Codable struct for Mac app display
      structured: {
        id: lessonId,
        clientUUID: clientUUID ?? null,
        rule,
        evidence: lesson.evidence ?? '',
        category,
        confidence: 0.9,
        createdAt: now,
        lastConfirmedAt: now,
        source: 'explicit_user',
        enforcement: 'hard',
        targetModuleId: lesson.targetModule ?? null,
        intent: lesson.intent ?? null,
      },
      metadata: {
        subtype: 'lesson',
        lessonType: 'inferred_lesson',
        lessonID: lessonId, // Must match what Mac's deleteLearnedSkill() looks for
        category,
        evidence: lesson.evidence ?? null,
        intent: lesson.intent ?? null,
        targetModuleId: lesson.targetModule ?? null,
        clientUUID: clientUUID ?? null,
        confidence: 0.9,
        source: 'explicit_user',
        enforcement: 'hard',
      },
    });

    savedCount++;
  }

  return jsonEncode({
    success: true,
    savedCount,
    message: `Saved ${savedCount} lesson(s)`,
  });
}

// ============================================================
// 2. get_lessons
// PORTING CHECKLIST: AgentToolExecutor.swift line 2629
// ✅ clientName, category, intent all optional
// ✅ Filter agent_learning atoms by subtype=lesson
// ✅ Return: {results: [{id, rule, category, evidence, confidence, intent, scope}], count}
// ============================================================

export async function getLessons(args: Record<string, any>): Promise<string> {
  let clientUUID: string | undefined;
  if (args.clientName) {
    const client = await fuzzyFindClient(args.clientName);
    if (client) clientUUID = client.uuid;
  }

  const category = args.category as string | undefined;
  const intent = args.intent as string | undefined;

  const allLearning = await fetchAllByType('agent_learning');
  const lessons = allLearning.filter(a => {
    const meta = a.metadata || {};
    if (meta.subtype !== 'lesson') return false;
    if (clientUUID && meta.clientUUID && meta.clientUUID !== clientUUID) return false;
    if (category && meta.category !== category) return false;
    if (intent && meta.intent && meta.intent !== intent) return false;
    return true;
  });

  return jsonEncode({
    results: lessons.map(a => ({
      id: a.uuid,
      rule: a.body || a.title,
      category: a.metadata?.category ?? 'general',
      evidence: a.metadata?.evidence ?? null,
      confidence: a.metadata?.confidence ?? 0.9,
      intent: a.metadata?.intent ?? null,
      scope: a.metadata?.clientUUID ? 'client-specific' : 'universal',
    })),
    count: lessons.length,
    message: `Found ${lessons.length} lesson(s)`,
  });
}

// ============================================================
// 3. update_skill
// PORTING CHECKLIST: AgentToolExecutor.swift line 2675
// ✅ lessonId required; rule, category, intent optional
// ============================================================

export async function updateSkill(args: Record<string, any>): Promise<string> {
  const lessonId = args.lessonId as string;
  if (!lessonId) return jsonError('lessonId is required');

  const updates: Record<string, any> = {};
  const metaUpdates: Record<string, any> = {};

  if (args.rule) {
    updates.body = args.rule;
    updates.title = (args.rule as string).substring(0, 100);
  }
  if (args.category) metaUpdates.category = args.category;
  if (args.intent) metaUpdates.intent = args.intent;

  if (Object.keys(metaUpdates).length > 0) updates.metadata = metaUpdates;

  const updated = await updateAtom(lessonId, updates);
  if (!updated) return jsonError(`Lesson not found: ${lessonId}`);

  return jsonEncode({
    success: true,
    lessonId,
    message: 'Lesson updated',
  });
}

// ============================================================
// 4. delete_skill
// PORTING CHECKLIST: AgentToolExecutor.swift (lesson deletion)
// ✅ lessonId required
// ============================================================

export async function deleteSkill(args: Record<string, any>): Promise<string> {
  const lessonId = args.lessonId as string;
  if (!lessonId) return jsonError('lessonId is required');

  const success = await deleteAtom(lessonId);
  if (!success) return jsonError(`Failed to delete lesson: ${lessonId}`);

  return jsonEncode({
    success: true,
    lessonId,
    message: 'Lesson deleted',
  });
}
