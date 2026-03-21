// cosmo-cloud-agent/src/tools/calendar.ts
// Calendar & Task tools — 7 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 1574-1820

import { fetchAtom, fetchAllByType, createAtom, updateAtom, deleteAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. get_calendar_blocks
// PORTING CHECKLIST: AgentToolExecutor.swift line 1574
// ✅ date optional (default today), ISO8601 or yyyy-MM-dd
// ✅ Filter by metadata.startTime or createdAt matching date
// ✅ Return: {date, blocks: [{uuid, title, startTime, endTime, isCompleted, intent}], count}
// ============================================================

export async function getCalendarBlocks(args: Record<string, any>): Promise<string> {
  const dateStr = (args.date as string) || new Date().toISOString().split('T')[0];
  const targetDate = dateStr.split('T')[0]; // normalize to yyyy-MM-dd

  const allBlocks = await fetchAllByType('schedule_block');

  const filtered = allBlocks.filter(a => {
    const meta = a.metadata || {};
    const startTime = meta.startTime as string;
    if (startTime) return startTime.startsWith(targetDate);
    return a.created_at.startsWith(targetDate);
  });

  return jsonEncode({
    date: targetDate,
    blocks: filtered.map(a => {
      const meta = a.metadata || {};
      return {
        uuid: a.uuid,
        title: a.title,
        startTime: meta.startTime ?? null,
        endTime: meta.endTime ?? null,
        isCompleted: meta.isCompleted ?? false,
        blockType: meta.originType ?? null,
        intent: meta.intent ?? null,
      };
    }),
    count: filtered.length,
  });
}

// ============================================================
// 2. create_block
// PORTING CHECKLIST: AgentToolExecutor.swift line 1626
// ✅ title, startTime, endTime required; intent optional
// ✅ Return: {success, uuid, title, startTime, endTime, message}
// ============================================================

export async function createBlock(args: Record<string, any>): Promise<string> {
  const title = args.title as string;
  const startTime = args.startTime as string;
  const endTime = args.endTime as string;
  if (!title || !startTime || !endTime) return jsonError('title, startTime, endTime are required');

  const atom = await createAtom({
    type: 'schedule_block',
    title,
    metadata: {
      startTime,
      endTime,
      status: 'scheduled',
      originType: 'manual',
      intent: args.intent ?? null,
    },
  });

  if (!atom) return jsonError('Failed to create block');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    startTime,
    endTime,
    message: `Block created: "${title}"`,
  });
}

// ============================================================
// 3. update_block
// PORTING CHECKLIST: AgentToolExecutor.swift line 1671
// ✅ uuid required; title, startTime, endTime optional
// ✅ Return: {success, uuid, message}
// ============================================================

export async function updateBlock(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const updates: Record<string, any> = {};
  const metaUpdates: Record<string, any> = {};

  if (args.title) updates.title = args.title;
  if (args.startTime) metaUpdates.startTime = args.startTime;
  if (args.endTime) metaUpdates.endTime = args.endTime;

  if (Object.keys(metaUpdates).length > 0) updates.metadata = metaUpdates;

  const updated = await updateAtom(uuid, updates);
  if (!updated) return jsonError(`Failed to update block: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    message: `Block updated: "${updated.title}"`,
  });
}

// ============================================================
// 4. delete_block
// PORTING CHECKLIST: AgentToolExecutor.swift line 1696
// ✅ uuid required
// ✅ Soft delete
// ✅ Return: {success, message}
// NOTE: Swift version has confirmation flow. Cloud version skips it.
// ============================================================

export async function deleteBlock(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Block not found: ${uuid}`);

  const success = await deleteAtom(uuid);
  if (!success) return jsonError(`Failed to delete block: ${uuid}`);

  return jsonEncode({
    success: true,
    message: `Block deleted: "${atom.title}"`,
  });
}

// ============================================================
// 5. complete_block
// PORTING CHECKLIST: AgentToolExecutor.swift line 1732
// ✅ uuid required
// ✅ Metadata: isCompleted, completedAt, status
// ✅ Return: {success, uuid, title, message}
// ============================================================

export async function completeBlock(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const updated = await updateAtom(uuid, {
    metadata: {
      isCompleted: true,
      completedAt: new Date().toISOString(),
      status: 'completed',
    },
  });

  if (!updated) return jsonError(`Failed to complete block: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    title: updated.title,
    message: `Block completed. XP awarded.`,
  });
}

// ============================================================
// 6. get_unscheduled_tasks
// PORTING CHECKLIST: AgentToolExecutor.swift line 1758
// ✅ limit optional (default 20)
// ✅ Filter: isUnscheduled or no startTime
// ✅ Return: {tasks: [{uuid, title, priority, intent, dueDate}], count}
// ============================================================

export async function getUnscheduledTasks(args: Record<string, any>): Promise<string> {
  const limit = (args.limit as number) || 20;

  const allTasks = await fetchAllByType('task');

  const unscheduled = allTasks.filter(a => {
    const meta = a.metadata || {};
    return meta.isUnscheduled === true || !meta.startTime;
  }).filter(a => {
    const meta = a.metadata || {};
    return !meta.isCompleted;
  }).slice(0, limit);

  return jsonEncode({
    tasks: unscheduled.map(a => {
      const meta = a.metadata || {};
      return {
        uuid: a.uuid,
        title: a.title,
        priority: meta.priority ?? 'medium',
        intent: meta.intent ?? null,
        dueDate: meta.dueDate ?? null,
      };
    }),
    count: unscheduled.length,
  });
}

// ============================================================
// 7. create_task
// PORTING CHECKLIST: AgentToolExecutor.swift line 1781
// ✅ title required; body, priority, intent, dueDate optional
// ✅ Return: {success, uuid, title, message}
// ============================================================

export async function createTask(args: Record<string, any>): Promise<string> {
  const title = args.title as string;
  if (!title) return jsonError('title is required');

  const atom = await createAtom({
    type: 'task',
    title,
    body: args.body ?? null,
    metadata: {
      priority: args.priority ?? 'medium',
      isUnscheduled: true,
      intent: args.intent ?? null,
      dueDate: args.dueDate ?? null,
      isCompleted: false,
    },
  });

  if (!atom) return jsonError('Failed to create task');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    message: `Task created: "${title}"`,
  });
}
