// cosmo-cloud-agent/src/tools/preferences.ts
// Preference tools — 3 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 1864-1930

import { fetchAllByType, createAtom, updateAtom, deleteAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. get_preferences
// PORTING CHECKLIST: AgentToolExecutor.swift line 1864
// ✅ scope optional (global/client/taskType)
// ✅ Query user_preference atoms
// ✅ Return: {preferences: [{key, value, scope, source}], count}
// ============================================================

export async function getPreferences(args: Record<string, any>): Promise<string> {
  const scope = args.scope as string | undefined;

  const allPrefs = await fetchAllByType('user_preference');

  const filtered = scope
    ? allPrefs.filter(a => (a.metadata?.scope as string) === scope)
    : allPrefs;

  return jsonEncode({
    preferences: filtered.map(a => ({
      key: a.metadata?.key ?? a.title,
      value: a.body ?? a.metadata?.value,
      scope: a.metadata?.scope ?? 'global',
      source: a.metadata?.source ?? 'explicit',
    })),
    count: filtered.length,
  });
}

// ============================================================
// 2. store_preference
// PORTING CHECKLIST: AgentToolExecutor.swift line 1882
// ✅ key required, value required, scope optional (default global)
// ✅ Return: {success, key, value, scope, message}
// ============================================================

export async function storePreference(args: Record<string, any>): Promise<string> {
  const key = args.key as string;
  const value = args.value as string;
  if (!key || !value) return jsonError('key and value are required');

  const scope = (args.scope as string) || 'global';
  const scopeQualifier = args.scopeQualifier as string | undefined;

  // Check for existing preference with same key+scope
  const existing = await fetchAllByType('user_preference');
  const match = existing.find(a =>
    (a.metadata?.key === key || a.title === key) &&
    (a.metadata?.scope ?? 'global') === scope
  );

  if (match) {
    await updateAtom(match.uuid, {
      body: value,
      metadata: { value, source: 'explicit', updatedAt: new Date().toISOString() },
    });
  } else {
    await createAtom({
      type: 'user_preference',
      title: key,
      body: value,
      metadata: {
        key,
        value,
        scope,
        scopeQualifier: scopeQualifier ?? null,
        source: 'explicit',
        confidence: 1.0,
      },
    });
  }

  return jsonEncode({
    success: true,
    key,
    value,
    scope,
    message: `Preference stored: ${key} = ${value}`,
  });
}

// ============================================================
// 3. delete_preference
// PORTING CHECKLIST: AgentToolExecutor.swift line 1911
// ✅ key required
// ✅ Return: {success, key, message}
// ============================================================

export async function deletePreference(args: Record<string, any>): Promise<string> {
  const key = args.key as string;
  if (!key) return jsonError('key is required');

  const scope = (args.scope as string) || 'global';

  const existing = await fetchAllByType('user_preference');
  const match = existing.find(a =>
    (a.metadata?.key === key || a.title === key) &&
    (a.metadata?.scope ?? 'global') === scope
  );

  if (!match) return jsonError(`Preference not found: ${key}`);

  await deleteAtom(match.uuid);

  return jsonEncode({
    success: true,
    key,
    message: `Preference deleted: ${key}`,
  });
}
