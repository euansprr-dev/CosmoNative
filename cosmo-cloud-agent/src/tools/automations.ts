// cosmo-cloud-agent/src/tools/automations.ts
// Automation rule CRUD tools — create/list/toggle/delete rules via Telegram
// Rules are stored as atoms (type: 'automation') for sync, with structured JSON for rule config

import { createAtom, fetchAllByType, fetchAtom, updateAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. create_automation
// Creates an automation rule as an atom in Supabase.
// The local Swift app will pick it up on sync and create
// the automation_rules index entry.
// ============================================================

export async function createAutomation(args: Record<string, any>): Promise<string> {
  const name = args.name as string;
  if (!name) return jsonError('name is required');

  const trigger = args.trigger as string || 'atom_created';
  const condition = args.condition as string | undefined;
  const action = args.action as string || 'show_notification';
  const scope = args.scope as string || 'global';

  // Parse natural language trigger into structured config
  const triggerConfig = parseTrigger(trigger);
  const conditionConfig = condition ? parseCondition(condition) : null;
  const actionConfig = parseAction(action);

  // Build the rule as structured JSON (matches AutomationRule schema)
  const ruleStructured = {
    name,
    isEnabled: true,
    scope: scope.includes(':') ? scope.split(':')[0] : scope,
    scopeId: scope.includes(':') ? scope.split(':')[1] : null,
    triggerType: triggerConfig.type,
    triggerConfig: triggerConfig.config,
    conditions: conditionConfig ? [conditionConfig] : [],
    conditionLogic: 'all',
    actions: [actionConfig],
    priority: 50,
    cooldownSeconds: 1,
    isBuiltIn: false,
  };

  // Create as an automation atom — will sync to local app
  const atom = await createAtom({
    type: 'automation',
    title: name,
    body: `Automation rule: ${trigger} → ${action}`,
    structured: ruleStructured,
    metadata: {
      triggerType: triggerConfig.type,
      scope: ruleStructured.scope,
      isEnabled: true,
    },
    links: ruleStructured.scopeId
      ? [{ type: 'automation_scope', uuid: ruleStructured.scopeId }]
      : [],
  });

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    name,
    trigger: triggerConfig.type,
    action: actionConfig.type,
    scope: ruleStructured.scope,
    message: `Automation rule "${name}" created. It will activate when your Mac app syncs.`,
  });
}

// ============================================================
// 2. list_automations
// ============================================================

export async function listAutomations(_args: Record<string, any>): Promise<string> {
  const atoms = await fetchAllByType('automation');

  const rules = atoms.map(a => ({
    uuid: a.uuid,
    name: a.title,
    trigger: a.structured?.triggerType || a.metadata?.triggerType || 'unknown',
    scope: a.structured?.scope || a.metadata?.scope || 'global',
    isEnabled: a.structured?.isEnabled ?? a.metadata?.isEnabled ?? true,
    createdAt: a.created_at,
  }));

  return jsonEncode({
    rules,
    count: rules.length,
  });
}

// ============================================================
// 3. toggle_automation
// ============================================================

export async function toggleAutomation(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Automation not found: ${uuid}`);
  if (atom.type !== 'automation') return jsonError(`Atom is not an automation rule`);

  const currentEnabled = atom.structured?.isEnabled ?? atom.metadata?.isEnabled ?? true;
  const newEnabled = !currentEnabled;

  await updateAtom(uuid, {
    structured: { ...atom.structured, isEnabled: newEnabled },
    metadata: { ...atom.metadata, isEnabled: newEnabled },
  });

  return jsonEncode({
    success: true,
    uuid,
    isEnabled: newEnabled,
    message: `Automation "${atom.title}" ${newEnabled ? 'enabled' : 'disabled'}.`,
  });
}

// ============================================================
// 4. delete_automation
// ============================================================

export async function deleteAutomation(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Automation not found: ${uuid}`);

  await updateAtom(uuid, { is_deleted: true } as any);

  return jsonEncode({
    success: true,
    uuid,
    message: `Automation "${atom.title}" deleted.`,
  });
}

// ============================================================
// Natural Language Parsers
// ============================================================

interface TriggerParsed {
  type: string;
  config: Record<string, string>;
}

function parseTrigger(input: string): TriggerParsed {
  const lower = input.toLowerCase();

  if (lower.includes('idea') && (lower.includes('create') || lower.includes('new'))) {
    return { type: 'atom_type_created', config: { atomType: 'idea' } };
  }
  if (lower.includes('content') && (lower.includes('create') || lower.includes('new'))) {
    return { type: 'atom_type_created', config: { atomType: 'content' } };
  }
  if (lower.includes('swipe') || lower.includes('research') || lower.includes('capture')) {
    return { type: 'atom_type_created', config: { atomType: 'research' } };
  }
  if (lower.includes('status') && lower.includes('change')) {
    return { type: 'status_changed', config: {} };
  }
  if (lower.includes('link')) {
    return { type: 'link_created', config: {} };
  }
  if (lower.includes('task')) {
    return { type: 'atom_type_created', config: { atomType: 'task' } };
  }

  // Default: any atom created
  return { type: 'atom_created', config: {} };
}

function parseCondition(input: string): Record<string, any> | null {
  const lower = input.toLowerCase();

  if (lower.includes('telegram')) {
    return {
      field: 'capture_source',
      op: 'equals',
      value: { type: 'string', value: 'telegram' },
      negate: false,
    };
  }

  if (lower.includes('client')) {
    // Try to extract client name
    const match = input.match(/client\s+["\']?(\w+)["\']?/i);
    if (match) {
      return {
        field: 'atom_client_uuid',
        op: 'is_set',
        value: { type: 'bool', value: true },
        negate: false,
      };
    }
  }

  if (lower.includes('type')) {
    const match = input.match(/type\s+(?:is\s+)?["\']?(\w+)["\']?/i);
    if (match) {
      return {
        field: 'atom_type',
        op: 'equals',
        value: { type: 'string', value: match[1].toLowerCase() },
        negate: false,
      };
    }
  }

  return null;
}

interface ActionParsed {
  type: string;
  config: Record<string, any>;
  label: string;
}

function parseAction(input: string): ActionParsed {
  const lower = input.toLowerCase();

  if (lower.includes('notify') || lower.includes('notification') || lower.includes('alert')) {
    if (lower.includes('telegram')) {
      return {
        type: 'send_telegram',
        config: { message: { type: 'string', value: '⚡ {{atom.title}} — automation fired' } },
        label: 'Send Telegram notification',
      };
    }
    return {
      type: 'show_notification',
      config: { message: { type: 'string', value: 'Rule fired for {{atom.title}}' } },
      label: 'Show notification',
    };
  }

  if (lower.includes('status')) {
    const match = input.match(/status\s+(?:to\s+)?["\']?(\w+)["\']?/i);
    return {
      type: 'set_status',
      config: { status: { type: 'string', value: match?.[1] || 'developing' } },
      label: `Set status to ${match?.[1] || 'developing'}`,
    };
  }

  if (lower.includes('analyz') || lower.includes('enrich')) {
    return {
      type: 'run_analysis',
      config: { analysisType: { type: 'string', value: 'quickEnrich' } },
      label: 'Run analysis',
    };
  }

  if (lower.includes('telegram')) {
    return {
      type: 'send_telegram',
      config: { message: { type: 'string', value: '⚡ {{atom.title}} — automation fired' } },
      label: 'Send Telegram notification',
    };
  }

  // Default: show notification
  return {
    type: 'show_notification',
    config: { message: { type: 'string', value: 'Rule fired for {{atom.title}}' } },
    label: 'Show notification',
  };
}
