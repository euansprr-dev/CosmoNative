// cosmo-cloud-agent/src/tools/clients.ts
// Client profile tools — 5 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 451, 1931-2035, 2962-3080

import { fetchAtom, fetchAllByType, createAtom, updateAtom, fuzzyFindClient, searchAtoms, atomToDict, isSwipeFileAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. list_client_profiles
// PORTING CHECKLIST: AgentToolExecutor.swift line 2962
// ✅ No params
// ✅ Return: {profiles: [{uuid, name, niche, platforms, hasIntelligenceModel}], count}
// ============================================================

export async function listClientProfiles(_args: Record<string, any>): Promise<string> {
  const clients = await fetchAllByType('client_profile');

  return jsonEncode({
    profiles: clients.map(a => {
      const meta = a.metadata || {};
      return {
        uuid: a.uuid,
        name: a.title,
        niche: meta.niche ?? null,
        platforms: meta.preferredPlatforms ?? [],
        hasIntelligenceModel: !!(a.structured?.intelligenceModel || a.structured?.voiceFingerprint),
        topPerformingPostCount: (a.structured?.topPerformingPosts as any[])?.length ?? 0,
      };
    }),
    count: clients.length,
  });
}

// ============================================================
// 2. get_client_profile
// PORTING CHECKLIST: AgentToolExecutor.swift line 2981
// ✅ client_name required (fuzzy matched)
// ✅ Return: full profile with intelligence model, voice fingerprint, etc.
// ============================================================

export async function getClientProfile(args: Record<string, any>): Promise<string> {
  const clientName = (args.client_name || args.clientName) as string;
  if (!clientName) return jsonError('client_name is required');

  const client = await fuzzyFindClient(clientName);
  if (!client) return jsonError(`Client not found: ${clientName}`);

  const meta = client.metadata || {};
  const structured = client.structured || {};

  // Load profile documents (brand story, voice guides, top posts)
  // Stored in structured.documents array, NOT flat fields like structured.brandStory
  const documents = (structured.documents || meta.documents) as any[] || [];
  const storyDocs = documents.filter((d: any) => d.category === 'story');
  const voiceGuides = documents.filter((d: any) => d.category === 'voiceGuide');
  const topContent = documents.filter((d: any) => ['reel', 'thread'].includes(d.category));

  return jsonEncode({
    uuid: client.uuid,
    name: client.title,
    niche: meta.niche ?? null,
    platforms: meta.preferredPlatforms ?? [],
    handle: meta.handles ?? null,
    brandVoice: meta.brandVoice ?? null,
    // Use documents array first (where Mac app stores it), fall back to flat field
    brandStory: storyDocs[0]?.content ?? structured.brandStory ?? null,
    brandVision: structured.brandVision ?? null,
    uniqueAngle: structured.uniqueAngle ?? null,
    voiceNotes: voiceGuides[0]?.content ?? structured.voiceNotes ?? null,
    coreBeliefs: structured.coreBeliefs ?? [],
    signaturePhrases: structured.signaturePhrases ?? [],
    targetAudience: structured.targetAudience ?? null,
    bestFormats: structured.bestFormats ?? [],
    preferredBeatPatterns: structured.preferredBeatPatterns ?? [],
    postingFrequency: structured.postingFrequency ?? null,
    topPerformingPosts: structured.topPerformingPosts ?? [],
    topPerformingTranscripts: structured.topPerformingTranscripts ?? [],
    intelligenceModel: structured.intelligenceModel ?? null,
    // Document availability
    profileDocuments: {
      stories: storyDocs.length,
      voiceGuides: voiceGuides.length,
      topContent: topContent.length,
      total: documents.length,
    },
  });
}

// ============================================================
// 3. search_by_client
// PORTING CHECKLIST: AgentToolExecutor.swift line 451
// ✅ clientName required, entityType optional (idea/swipe/content)
// ✅ Fuzzy find client → filter atoms by clientUUID in metadata/links
// ✅ Return: {clientName, clientUUID, results, count}
// ============================================================

export async function searchByClient(args: Record<string, any>): Promise<string> {
  const clientName = args.clientName as string;
  if (!clientName) return jsonError('clientName is required');

  const entityType = args.entityType as string | undefined;

  const client = await fuzzyFindClient(clientName);
  if (!client) return jsonError(`Client not found: ${clientName}`);

  const types = entityType ? [entityType === 'swipe' ? 'research' : entityType] : ['idea', 'research', 'content'];
  const results: any[] = [];

  for (const type of types) {
    const atoms = await fetchAllByType(type, { limit: 100 });
    for (const atom of atoms) {
      // Check metadata.clientUUID
      if (atom.metadata?.clientUUID === client.uuid || atom.metadata?.clientProfileUUID === client.uuid) {
        results.push({ uuid: atom.uuid, type: atom.type, title: atom.title, preview: atom.body?.substring(0, 150) ?? null });
        continue;
      }
      // Check links for *ToClient
      if (atom.links?.some(l => l.uuid === client.uuid && l.type.includes('Client'))) {
        results.push({ uuid: atom.uuid, type: atom.type, title: atom.title, preview: atom.body?.substring(0, 150) ?? null });
      }
    }
  }

  return jsonEncode({
    clientName: client.title,
    clientUUID: client.uuid,
    results,
    count: results.length,
  });
}

// ============================================================
// 4. update_client_memory
// PORTING CHECKLIST: AgentToolExecutor.swift line 1931
// ✅ client_name, field, value required
// ✅ Creates or updates user_preference atom scoped to client
// ✅ Return: {success, clientName, field, value, message}
// ============================================================

export async function updateClientMemory(args: Record<string, any>): Promise<string> {
  const clientName = (args.client_name || args.clientName) as string;
  const field = args.field as string;
  const value = args.value as string;
  if (!clientName || !field || !value) return jsonError('client_name, field, and value are required');

  const client = await fuzzyFindClient(clientName);
  if (!client) return jsonError(`Client not found: ${clientName}`);

  // Find existing memory for this client+field
  const allPrefs = await fetchAllByType('user_preference');
  const existing = allPrefs.find(a =>
    a.metadata?.scope === client.uuid &&
    a.metadata?.key === field &&
    a.metadata?.source === 'agent_memory'
  );

  if (existing) {
    await updateAtom(existing.uuid, {
      body: value,
      metadata: { value, updatedAt: new Date().toISOString() },
    });
  } else {
    await createAtom({
      type: 'user_preference',
      title: field,
      body: value,
      metadata: {
        key: field,
        value,
        scope: client.uuid,
        source: 'agent_memory',
        updatedAt: new Date().toISOString(),
      },
    });
  }

  return jsonEncode({
    success: true,
    clientName: client.title,
    field,
    value,
    message: `Client memory updated: ${field} = ${value}`,
  });
}

// ============================================================
// 5. list_client_memory
// PORTING CHECKLIST: AgentToolExecutor.swift line 1992
// ✅ client_name required
// ✅ Filter user_preference atoms by scope=clientUUID, source=agent_memory
// ✅ Return: {clientName, memories, count}
// ============================================================

export async function listClientMemory(args: Record<string, any>): Promise<string> {
  const clientName = (args.client_name || args.clientName) as string;
  if (!clientName) return jsonError('client_name is required');

  const client = await fuzzyFindClient(clientName);
  if (!client) return jsonError(`Client not found: ${clientName}`);

  const allPrefs = await fetchAllByType('user_preference');
  const memories = allPrefs.filter(a =>
    a.metadata?.scope === client.uuid &&
    a.metadata?.source === 'agent_memory'
  );

  return jsonEncode({
    clientName: client.title,
    memories: memories.map(a => ({
      field: a.metadata?.key ?? a.title,
      value: a.body ?? a.metadata?.value,
      updatedAt: a.metadata?.updatedAt ?? a.updated_at,
    })),
    count: memories.length,
  });
}
