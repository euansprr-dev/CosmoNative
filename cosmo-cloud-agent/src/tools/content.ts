// cosmo-cloud-agent/src/tools/content.ts
// Content tools — 6 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 1412-1570

import { fetchAtom, fetchAllByType, createAtom, updateAtom, fuzzyFindClient, atomToDict, searchAtoms, searchAtomsByExactTitle, isSwipeFileAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. get_content_pipeline
// PORTING CHECKLIST: AgentToolExecutor.swift line 1412
// ✅ phase optional filter
// ✅ Group by ContentAtomMetadata.phase
// ✅ Return: {pipeline: {phase: [{uuid, title, phase, wordCount, platform}]}, totalCount}
// ============================================================

export async function getContentPipeline(args: Record<string, any>): Promise<string> {
  const phaseFilter = args.phase as string | undefined;

  const allContent = await fetchAllByType('content');

  const pipeline: Record<string, any[]> = {};
  let totalCount = 0;

  for (const atom of allContent) {
    const meta = atom.metadata || {};
    const phase = meta.phase as string || 'ideation';

    if (phaseFilter && phase !== phaseFilter) continue;

    if (!pipeline[phase]) pipeline[phase] = [];
    pipeline[phase].push({
      uuid: atom.uuid,
      title: atom.title,
      phase,
      wordCount: meta.wordCount ?? 0,
      platform: meta.platform ?? null,
      clientName: meta.clientProfileUUID ?? null,
    });
    totalCount++;
  }

  return jsonEncode({ pipeline, totalCount });
}

// ============================================================
// 2. advance_pipeline_phase
// PORTING CHECKLIST: AgentToolExecutor.swift line 1441
// ✅ uuid required, notes optional
// ✅ Phase progression: ideation → brainstorm → draft → polish → scheduled → published → analyzing → archived
// ✅ Return: {success, phaseTransition, message}
// ============================================================

const PHASE_ORDER = ['ideation', 'brainstorm', 'draft', 'polish', 'scheduled', 'published', 'analyzing', 'archived'];

export async function advancePipelinePhase(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Content not found: ${uuid}`);

  const currentPhase = (atom.metadata?.phase as string) || 'ideation';
  const currentIndex = PHASE_ORDER.indexOf(currentPhase);

  if (currentIndex === -1 || currentIndex >= PHASE_ORDER.length - 1) {
    return jsonError(`Cannot advance from phase: ${currentPhase}`);
  }

  const nextPhase = PHASE_ORDER[currentIndex + 1];

  await updateAtom(uuid, {
    metadata: {
      phase: nextPhase,
      [`${currentPhase}CompletedAt`]: new Date().toISOString(),
    },
  });

  return jsonEncode({
    success: true,
    phaseTransition: `${currentPhase} → ${nextPhase}`,
    message: `Content advanced to ${nextPhase} phase`,
  });
}

// ============================================================
// 3. create_content
// PORTING CHECKLIST: AgentToolExecutor.swift line 1462
// ✅ title required, body/description/platform/sourceIdeaUUID/framework/hooks/swipeUUIDs/clientName optional
// ✅ Fuzzy client resolution
// ✅ Links: ideaToContent, contentToClient
// ✅ Return: {success, uuid, title, clientName?, linkedSwipes?, message}
// ============================================================

export async function createContent(args: Record<string, any>): Promise<string> {
  const title = args.title as string;
  if (!title) return jsonError('title is required');

  let clientUUID: string | undefined;
  let clientName: string | undefined;
  if (args.clientName) {
    const client = await fuzzyFindClient(args.clientName as string);
    if (client) {
      clientUUID = client.uuid;
      clientName = client.title ?? args.clientName;
    }
  }

  const links: Array<{ type: string; uuid: string; entityType?: string }> = [];
  if (args.sourceIdeaUUID) {
    links.push({ type: 'ideaToContent', uuid: args.sourceIdeaUUID, entityType: 'idea' });
  }
  if (clientUUID) {
    links.push({ type: 'contentToClient', uuid: clientUUID, entityType: 'client_profile' });
  }

  let swipeUUIDs = args.swipeUUIDs as string[] | undefined;
  const hooks = args.hooks as string[] | undefined;

  // Resolve blueprint TITLES to UUIDs (so agent doesn't need search_swipes)
  const blueprintTitles = args.blueprintTitles as string[] | undefined;
  if (blueprintTitles && blueprintTitles.length > 0) {
    const resolved: string[] = [];
    for (const title of blueprintTitles) {
      // Try exact title match first, then fall back to fuzzy search
      let results = await searchAtomsByExactTitle(title, ['research']);
      if (results.length === 0) {
        results = await searchAtoms(title, { types: ['research'], limit: 5 });
      }
      const swipe = results.find(a => isSwipeFileAtom(a));
      if (swipe) {
        resolved.push(swipe.uuid);
        console.log(`    📎 Blueprint linked: "${title}" → ${swipe.uuid}`);
      } else {
        const found = results.length;
        const swipeCount = results.filter(isSwipeFileAtom).length;
        console.log(`    ⚠️ Blueprint not found: "${title}" (${found} results, ${swipeCount} swipes)`);
      }
    }
    if (resolved.length > 0) {
      swipeUUIDs = [...(swipeUUIDs || []), ...resolved];
    }
  }

  const atom = await createAtom({
    type: 'content',
    title,
    body: args.body ?? args.description ?? args.coreIdea ?? null,
    metadata: {
      phase: 'ideation',
      wordCount: 0,
      platform: args.platform ?? null,
      clientProfileUUID: clientUUID ?? null,
      sourceIdeaUUID: args.sourceIdeaUUID ?? null,
      inheritedSwipeUUIDs: swipeUUIDs ?? [],
      inheritedFramework: args.framework ?? null,
      inheritedHooks: hooks ?? [],
      activatedAt: new Date().toISOString(),
    },
    links: links.length > 0 ? links : undefined,
  });

  if (!atom) return jsonError('Failed to create content');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    ...(clientName ? { clientName } : {}),
    ...(swipeUUIDs ? { linkedSwipes: swipeUUIDs.length } : {}),
    message: `Content created: "${title}"`,
  });
}

// ============================================================
// 4. get_content
// PORTING CHECKLIST: AgentToolExecutor.swift line 1540
// ✅ uuid required
// ✅ Return atomToDict + phase, platform, wordCount
// ============================================================

export async function getContent(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Content not found: ${uuid}`);

  const meta = atom.metadata || {};

  return jsonEncode({
    ...atomToDict(atom),
    phase: meta.phase ?? 'ideation',
    platform: meta.platform ?? null,
    wordCount: meta.wordCount ?? 0,
    clientProfileUUID: meta.clientProfileUUID ?? null,
    outline: meta.outline ?? null,
    hooks: meta.hooks ?? meta.inheritedHooks ?? null,
  });
}

// ============================================================
// 5. update_content
// PORTING CHECKLIST: AgentToolExecutor.swift line 2493
// ✅ uuid required, title/body/description/platform/framework/hooks/outline/clientName optional
// ✅ Metadata write: contentDescription (NOT body), platform, inheritedFramework, hooks, outline
// ✅ Links: adds contentToClient if new client
// ✅ Return: {success, uuid, title, clientName?, message}
// ============================================================

export async function updateContent(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const updates: Partial<{ title: string; body: string; metadata: Record<string, any>; links: any[] }> = {};
  const metaUpdates: Record<string, any> = {};

  if (args.title) updates.title = args.title;
  if (args.body) updates.body = args.body;
  if (args.description || args.coreIdea) metaUpdates.contentDescription = args.description || args.coreIdea;
  if (args.platform) metaUpdates.platform = args.platform;
  if (args.framework) {
    metaUpdates.inheritedFramework = args.framework;
  }
  if (args.hooks) {
    metaUpdates.hooks = args.hooks;
    metaUpdates.inheritedHooks = args.hooks;
  }
  if (args.outline) {
    metaUpdates.outline = Array.isArray(args.outline)
      ? args.outline.map((item: any, i: number) => ({
          id: typeof item === 'string' ? `section_${i}` : item.id || `section_${i}`,
          title: typeof item === 'string' ? item : item.title || item,
          sortOrder: i,
        }))
      : args.outline;
  }

  if (args.clientName) {
    const client = await fuzzyFindClient(args.clientName);
    if (client) {
      metaUpdates.clientProfileUUID = client.uuid;
      updates.links = [{ type: 'contentToClient', uuid: client.uuid, entityType: 'client_profile' }];
    }
  }

  if (Object.keys(metaUpdates).length > 0) {
    updates.metadata = metaUpdates;
  }

  const updated = await updateAtom(uuid, updates);
  if (!updated) return jsonError(`Failed to update content: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    title: updated.title,
    message: `Content updated: "${updated.title}"`,
  });
}

// ============================================================
// 6. create_thinkspace
// PORTING CHECKLIST: AgentToolExecutor.swift line 1556
// ✅ title required
// ✅ Creates .thinkspace atom
// ✅ Return: {success, uuid, title, message}
// ============================================================

export async function createThinkspace(args: Record<string, any>): Promise<string> {
  const title = args.title as string;
  if (!title) return jsonError('title is required');

  const atom = await createAtom({ type: 'thinkspace', title });
  if (!atom) return jsonError('Failed to create thinkspace');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    message: `Thinkspace created: "${title}"`,
  });
}
