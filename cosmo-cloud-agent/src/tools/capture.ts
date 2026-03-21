// cosmo-cloud-agent/src/tools/capture.ts
// Capture tools — 3 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 838-1400
// RISK: HIGH — capture_swipe involves URL fetching, SwipeAnalyzer, auto-linking

import { createAtom, fuzzyFindClient, updateAtom, fetchAllByType } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. capture_swipe
// PORTING CHECKLIST: AgentToolExecutor.swift line 838
// ✅ url required; hook, notes, clientName optional
// ✅ URL classification (YouTube, Instagram, X, Threads, Website)
// ✅ Create .research atom with swipe metadata
// ✅ Auto-link to client if clientName provided
// ⚠️ SIMPLIFIED: No transcript fetching, no SwipeAnalyzer, no auto-idea-linking
//    (These require external APIs that will be added in Phase 3)
// ✅ Return: {success, uuid, title, source, hook, processingStatus, message}
// ============================================================

export async function captureSwipe(args: Record<string, any>): Promise<string> {
  const url = args.url as string;
  if (!url) return jsonError('url is required');

  const hook = args.hook as string | undefined;
  const notes = args.notes as string | undefined;
  const clientName = args.clientName as string | undefined;

  // Classify URL source
  const source = classifyUrl(url);

  // Resolve client
  let clientUUID: string | undefined;
  let resolvedClientName: string | undefined;
  if (clientName) {
    const client = await fuzzyFindClient(clientName);
    if (client) {
      clientUUID = client.uuid;
      resolvedClientName = client.title ?? clientName;
    }
  }

  // Build title from URL
  const title = buildSwipeTitle(url, source);

  // Build links
  const links: Array<{ type: string; uuid: string; entityType?: string }> = [];
  if (clientUUID) {
    links.push({ type: 'swipeToClient', uuid: clientUUID, entityType: 'client_profile' });
  }

  // Create research atom
  const atom = await createAtom({
    type: 'research',
    title,
    body: notes ?? null,
    structured: {
      hookType: null,
      hookText: hook ?? null,
      frameworkType: null,
      contentSource: source,
      sourceUrl: url,
      processingStatus: 'pending_cloud',
    },
    metadata: {
      contentSource: source,
      sourceUrl: url,
      captureSource: 'telegram_cloud',
      ...(clientUUID ? { clientUUID } : {}),
    },
    links: links.length > 0 ? links : undefined,
  });

  if (!atom) return jsonError('Failed to capture swipe');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    source,
    hook: hook ?? null,
    processingStatus: 'pending_cloud',
    ...(resolvedClientName ? { clientName: resolvedClientName } : {}),
    message: `Captured ${source} swipe: "${title}"`,
  });
}

// ============================================================
// 2. capture_swipe_with_idea
// PORTING CHECKLIST: AgentToolExecutor.swift line 1135
// ✅ url required; ideaContext, clientName, hook, title optional
// ✅ Capture swipe first, then create linked idea
// ✅ Links: ideaToSwipe, swipeToIdea, ideaToClient
// ✅ Return: {success, swipeUUID, ideaUUID, ideaTitle, swipeTitle, message}
// ============================================================

export async function captureSwipeWithIdea(args: Record<string, any>): Promise<string> {
  // Step 1: Capture the swipe
  const swipeResult = await captureSwipe({
    url: args.url,
    hook: args.hook,
    clientName: args.clientName,
  });

  const swipeData = JSON.parse(swipeResult);
  if (!swipeData.success) return swipeResult;

  const swipeUUID = swipeData.uuid;
  const swipeTitle = swipeData.title;

  // Step 2: Resolve client
  let clientUUID: string | undefined;
  let resolvedClientName: string | undefined;
  if (args.clientName) {
    const client = await fuzzyFindClient(args.clientName);
    if (client) {
      clientUUID = client.uuid;
      resolvedClientName = client.title ?? args.clientName;
    }
  }

  // Step 3: Create idea
  const ideaTitle = (args.title as string) || (args.ideaContext as string) || `Idea from: ${swipeTitle}`;

  const ideaLinks: Array<{ type: string; uuid: string; entityType?: string }> = [
    { type: 'ideaToSwipe', uuid: swipeUUID, entityType: 'research' },
  ];
  if (clientUUID) {
    ideaLinks.push({ type: 'ideaToClient', uuid: clientUUID, entityType: 'client_profile' });
  }

  const source = classifyUrl(args.url);

  const ideaAtom = await createAtom({
    type: 'idea',
    title: ideaTitle,
    body: args.ideaContext ?? null,
    metadata: {
      ideaStatus: 'spark',
      captureSource: 'telegram_cloud',
      originSwipeUUID: swipeUUID,
      linkedSwipeIds: [swipeUUID],
      ...(clientUUID ? { clientUUID } : {}),
      ...(source ? { platform: mapSourceToPlatform(source) } : {}),
    },
    links: ideaLinks,
  });

  if (!ideaAtom) return jsonError('Swipe captured but failed to create idea');

  // Step 4: Add reverse link on swipe (swipeToIdea)
  await updateAtom(swipeUUID, {
    links: [{ type: 'swipeToIdea', uuid: ideaAtom.uuid, entityType: 'idea' }],
  });

  return jsonEncode({
    success: true,
    swipeUUID,
    ideaUUID: ideaAtom.uuid,
    ideaTitle: ideaAtom.title,
    swipeTitle,
    ...(resolvedClientName ? { clientName: resolvedClientName } : {}),
    message: `Captured swipe + created idea: "${ideaTitle}"`,
  });
}

// ============================================================
// 3. capture_research
// PORTING CHECKLIST: AgentToolExecutor.swift line 1330
// ✅ title required; url, body optional
// ✅ Creates .research atom (NOT a swipe)
// ✅ Return: {success, uuid, title, message}
// ============================================================

export async function captureResearch(args: Record<string, any>): Promise<string> {
  const title = args.title as string;
  if (!title) return jsonError('title is required');

  const atom = await createAtom({
    type: 'research',
    title,
    body: args.body ?? null,
    metadata: {
      sourceUrl: args.url ?? null,
      captureSource: 'telegram_cloud',
    },
  });

  if (!atom) return jsonError('Failed to capture research');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    message: `Research captured: "${title}"`,
  });
}

// ============================================================
// Helpers
// ============================================================

function classifyUrl(url: string): string {
  const lower = url.toLowerCase();
  if (lower.includes('youtube.com') || lower.includes('youtu.be')) return 'YouTube';
  if (lower.includes('instagram.com')) return 'Instagram';
  if (lower.includes('tiktok.com')) return 'TikTok';
  if (lower.includes('twitter.com') || lower.includes('x.com')) return 'X';
  if (lower.includes('threads.net')) return 'Threads';
  return 'Website';
}

function buildSwipeTitle(url: string, source: string): string {
  try {
    const urlObj = new URL(url);
    const path = urlObj.pathname.split('/').filter(Boolean);
    if (source === 'YouTube' && path.length > 0) return `YouTube: ${path[path.length - 1]}`;
    if (source === 'Instagram' && path.length >= 2) return `Instagram: @${path[0]}`;
    if (source === 'TikTok' && path.length >= 1) return `TikTok: @${path[0].replace('@', '')}`;
    if (source === 'X' && path.length >= 1) return `X: @${path[0]}`;
    return `${source}: ${urlObj.hostname}`;
  } catch {
    return `${source} Swipe`;
  }
}

function mapSourceToPlatform(source: string): string | null {
  switch (source) {
    case 'YouTube': return 'youtube';
    case 'Instagram': return 'instagram';
    case 'TikTok': return 'tiktok';
    case 'X': return 'x';
    case 'Threads': return 'threads';
    default: return null;
  }
}
