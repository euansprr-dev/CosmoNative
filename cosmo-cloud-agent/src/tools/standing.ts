// cosmo-cloud-agent/src/tools/standing.ts
// Standing instruction tools — 5 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 2840-2895

import { fetchAllByType, createAtom, updateAtom, deleteAtom, fetchAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. add_standing_instruction
// ✅ body required; schedule, hour, minute, days, intervalMinutes, dayOfMonth optional
// ✅ Creates agent_learning atom with subtype=standing_instruction
// ============================================================

export async function addStandingInstruction(args: Record<string, any>): Promise<string> {
  const body = args.body as string;
  if (!body) return jsonError('body is required');

  const schedule = (args.schedule as string) || 'daily';
  const hour = args.hour as number | undefined;
  const minute = args.minute as number | undefined;

  const atom = await createAtom({
    type: 'agent_learning',
    title: body.substring(0, 80),
    body,
    metadata: {
      subtype: 'standing_instruction',
      schedule,
      hour: hour ?? 9,
      minute: minute ?? 0,
      days: args.days ?? null,
      intervalMinutes: args.intervalMinutes ?? null,
      dayOfMonth: args.dayOfMonth ?? null,
      enabled: true,
      lastExecutedAt: null,
      createdAt: new Date().toISOString(),
    },
  });

  if (!atom) return jsonError('Failed to create standing instruction');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    body,
    schedule,
    message: `Standing instruction created (${schedule})`,
  });
}

// ============================================================
// 2. list_standing_instructions
// ============================================================

export async function listStandingInstructions(_args: Record<string, any>): Promise<string> {
  const all = await fetchAllByType('agent_learning');
  const instructions = all.filter(a => a.metadata?.subtype === 'standing_instruction');

  return jsonEncode({
    instructions: instructions.map(a => ({
      uuid: a.uuid,
      body: a.body,
      schedule: a.metadata?.schedule ?? 'daily',
      hour: a.metadata?.hour ?? 9,
      minute: a.metadata?.minute ?? 0,
      enabled: a.metadata?.enabled ?? true,
      lastExecutedAt: a.metadata?.lastExecutedAt ?? null,
    })),
    count: instructions.length,
  });
}

// ============================================================
// 3. remove_standing_instruction
// ============================================================

export async function removeStandingInstruction(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const success = await deleteAtom(uuid);
  if (!success) return jsonError(`Failed to remove instruction: ${uuid}`);

  return jsonEncode({ success: true, message: 'Standing instruction removed' });
}

// ============================================================
// 4. update_standing_instruction
// ============================================================

export async function updateStandingInstruction(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const metaUpdates: Record<string, any> = {};
  if (args.body !== undefined) metaUpdates.body = args.body;
  if (args.schedule !== undefined) metaUpdates.schedule = args.schedule;
  if (args.hour !== undefined) metaUpdates.hour = args.hour;
  if (args.minute !== undefined) metaUpdates.minute = args.minute;
  if (args.enabled !== undefined) metaUpdates.enabled = args.enabled;
  if (args.days !== undefined) metaUpdates.days = args.days;
  if (args.intervalMinutes !== undefined) metaUpdates.intervalMinutes = args.intervalMinutes;
  if (args.dayOfMonth !== undefined) metaUpdates.dayOfMonth = args.dayOfMonth;

  const updates: Record<string, any> = { metadata: metaUpdates };
  if (args.body) updates.body = args.body;

  const updated = await updateAtom(uuid, updates);
  if (!updated) return jsonError(`Instruction not found: ${uuid}`);

  return jsonEncode({ success: true, uuid, message: 'Standing instruction updated' });
}

// ============================================================
// 5. get_instruction_history
// ============================================================

export async function getInstructionHistory(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Instruction not found: ${uuid}`);

  const history = atom.structured?.executionHistory as any[] || [];

  return jsonEncode({
    uuid,
    body: atom.body,
    history: history.slice(-10),
    count: history.length,
  });
}
