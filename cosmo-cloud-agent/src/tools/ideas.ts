// cosmo-cloud-agent/src/tools/ideas.ts
// Idea tools — 5 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 239-400

import { fetchAtom, fetchAllByType, createAtom, updateAtom, searchAtoms, fuzzyFindClient, atomToDict } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. search_ideas
// PORTING CHECKLIST: AgentToolExecutor.swift line 239
// ✅ Keyword search via FTS with ILIKE fallback
// ✅ Limit parameter (default 10)
// ✅ Return format: {results: [{uuid, title, preview}], count}
// ✅ Empty result: {results: [], count: 0}
// ============================================================

export async function searchIdeas(args: Record<string, any>): Promise<string> {
  const query = args.query as string;
  if (!query) return jsonError('query is required');

  const limit = (args.limit as number) || 10;

  const results = await searchAtoms(query, { types: ['idea'], limit });

  return jsonEncode({
    results: results.map(a => ({
      uuid: a.uuid,
      title: a.title,
      preview: a.body ? a.body.substring(0, 200) : null,
      ...(a.metadata?.ideaStatus ? { status: a.metadata.ideaStatus } : {}),
      ...(a.metadata?.clientUUID ? { clientUUID: a.metadata.clientUUID } : {}),
    })),
    count: results.length,
  });
}

// ============================================================
// 2. get_idea
// PORTING CHECKLIST: AgentToolExecutor.swift line 286
// ✅ Fetch by UUID
// ✅ Return full atom dict
// ✅ Error if not found
// ============================================================

export async function getIdea(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Idea not found: ${uuid}`);

  return jsonEncode(atomToDict(atom));
}

// ============================================================
// 3. create_idea
// PORTING CHECKLIST: AgentToolExecutor.swift line 296
// ✅ title required
// ✅ body optional
// ✅ Creates .idea atom
// ✅ Return: {success, uuid, title, message}
// ============================================================

export async function createIdea(args: Record<string, any>): Promise<string> {
  const title = args.title as string;
  if (!title) return jsonError('title is required');

  const body = args.body as string | undefined;
  const clientName = args.clientName as string | undefined;

  // Resolve client if provided
  let clientUUID: string | undefined;
  let resolvedClientName: string | undefined;
  if (clientName) {
    const client = await fuzzyFindClient(clientName);
    if (client) {
      clientUUID = client.uuid;
      resolvedClientName = client.title ?? clientName;
    }
  }

  const links: Array<{ type: string; uuid: string; entityType?: string }> = [];
  if (clientUUID) {
    links.push({ type: 'ideaToClient', uuid: clientUUID, entityType: 'client_profile' });
  }

  const atom = await createAtom({
    type: 'idea',
    title,
    body,
    metadata: {
      ideaStatus: 'spark',
      captureSource: 'telegram_cloud',
      ...(clientUUID ? { clientUUID } : {}),
    },
    links: links.length > 0 ? links : null,
  });

  if (!atom) return jsonError('Failed to create idea');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    ...(resolvedClientName ? { clientName: resolvedClientName } : {}),
    message: `Idea created: "${title}"${resolvedClientName ? ` for ${resolvedClientName}` : ''}`,
  });
}

// ============================================================
// 4. update_idea
// PORTING CHECKLIST: AgentToolExecutor.swift line 315
// ✅ uuid required
// ✅ title, body, status optional
// ✅ Metadata write: ideaStatus
// ✅ Return: {success, uuid, title, message}
// ============================================================

export async function updateIdea(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const updates: Record<string, any> = {};
  if (args.title) updates.title = args.title;
  if (args.body) updates.body = args.body;

  const metadataUpdates: Record<string, any> = {};
  if (args.status) metadataUpdates.ideaStatus = args.status;

  if (Object.keys(metadataUpdates).length > 0) {
    updates.metadata = metadataUpdates;
  }

  const updated = await updateAtom(uuid, updates);
  if (!updated) return jsonError(`Failed to update idea: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    title: updated.title,
    message: `Idea updated: "${updated.title}"`,
  });
}

// ============================================================
// 5. activate_idea
// PORTING CHECKLIST: AgentToolExecutor.swift line 342
// ✅ uuid required
// ✅ Fetch idea → read clientUUID, platform, linkedSwipeIds
// ✅ Create content atom with inherited context
// ✅ Set idea status to "activated"
// ✅ Create ideaToContent link on content
// ✅ Create contentToClient link if clientUUID
// ✅ Return: {success, ideaUUID, contentUUID, message}
// RISK: HIGH — multi-step (analysis + create + link + update)
// NOTE: IdeaInsightEngine.fullAnalysis() not available server-side.
//       We skip the analysis and just promote with existing metadata.
// ============================================================

export async function activateIdea(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const idea = await fetchAtom(uuid);
  if (!idea) return jsonError(`Idea not found: ${uuid}`);
  if (idea.type !== 'idea') return jsonError(`Atom ${uuid} is not an idea`);

  const ideaMetadata = idea.metadata || {};
  const clientUUID = ideaMetadata.clientUUID as string | undefined;
  const platform = ideaMetadata.platform as string | undefined;
  const linkedSwipeIds = ideaMetadata.linkedSwipeIds as string[] | undefined;
  const suggestedFramework = ideaMetadata.suggestedFramework as string | undefined;
  const hooks = ideaMetadata.hooks as string[] | undefined;

  // Build content atom links
  const contentLinks: Array<{ type: string; uuid: string; entityType?: string }> = [
    { type: 'ideaToContent', uuid: idea.uuid, entityType: 'idea' },
  ];
  if (clientUUID) {
    contentLinks.push({ type: 'contentToClient', uuid: clientUUID, entityType: 'client_profile' });
  }

  // Create content atom with inherited context from idea
  const contentAtom = await createAtom({
    type: 'content',
    title: idea.title,
    body: idea.body,
    metadata: {
      phase: 'ideation',
      wordCount: 0,
      sourceIdeaUUID: idea.uuid,
      activatedAt: new Date().toISOString(),
      clientProfileUUID: clientUUID ?? null,
      platform: platform ?? null,
      inheritedSwipeUUIDs: linkedSwipeIds ?? [],
      inheritedFramework: suggestedFramework ?? null,
      inheritedHooks: hooks ?? [],
    },
    links: contentLinks,
  });

  if (!contentAtom) return jsonError('Failed to create content atom');

  // Update idea status to activated
  await updateAtom(uuid, {
    metadata: {
      ideaStatus: 'activated',
      statusChangedAt: new Date().toISOString(),
      contentUUIDs: [...(ideaMetadata.contentUUIDs || []), contentAtom.uuid],
    },
  });

  return jsonEncode({
    success: true,
    ideaUUID: uuid,
    contentUUID: contentAtom.uuid,
    matchedSwipes: (linkedSwipeIds || []).length,
    framework: suggestedFramework || null,
    hookCount: (hooks || []).length,
    message: `Idea activated and promoted to content pipeline: "${idea.title}"`,
  });
}
