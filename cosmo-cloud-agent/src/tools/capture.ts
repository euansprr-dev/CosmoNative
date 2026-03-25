// cosmo-cloud-agent/src/tools/capture.ts
// Capture tools — 3 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 838-1400

import { createAtom, fuzzyFindClient, updateAtom, fetchAllByType } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. capture_swipe
// PORTING CHECKLIST: AgentToolExecutor.swift line 838
// ✅ url required; hook, notes, clientName optional
// ✅ URL classification (YouTube, Instagram, X, Threads, Website)
// ✅ Create .research atom with swipe metadata
// ✅ Thumbnail fetching (YouTube video ID, Instagram oEmbed)
// ✅ richContent + swipeContentFormat for correct canvas block sizing
// ✅ processingStatus in metadata (triggers Mac app transcription on sync)
// ✅ Auto-link to client if clientName provided
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

  // Build title from URL (may be overridden by oEmbed)
  let title = buildSwipeTitle(url, source);
  let thumbnailUrl: string | null = null;
  let authorName: string | null = null;

  // Fetch platform-specific metadata (thumbnail, title, author)
  if (source === 'YouTube') {
    const videoId = extractYouTubeVideoId(url);
    if (videoId) {
      thumbnailUrl = `https://img.youtube.com/vi/${videoId}/maxresdefault.jpg`;
    }
    // Try oEmbed for better title
    try {
      const oembedUrl = `https://www.youtube.com/oembed?url=${encodeURIComponent(url)}&format=json`;
      const resp = await fetch(oembedUrl, { signal: AbortSignal.timeout(5000) });
      if (resp.ok) {
        const data = await resp.json() as any;
        if (data.title) title = data.title.substring(0, 200);
        if (data.author_name) authorName = data.author_name;
      }
    } catch {} // Best-effort
  }

  if (source === 'Instagram') {
    try {
      const oembedUrl = `https://www.instagram.com/api/v1/oembed/?url=${encodeURIComponent(url)}`;
      const resp = await fetch(oembedUrl, { signal: AbortSignal.timeout(5000) });
      if (resp.ok) {
        const data = await resp.json() as any;
        if (data.thumbnail_url) thumbnailUrl = data.thumbnail_url;
        if (data.title) title = data.title.substring(0, 200);
        if (data.author_name) authorName = `@${data.author_name}`;
      }
    } catch {} // Best-effort
  }

  // Determine content format for canvas block sizing
  const contentFormat = mapSourceToFormat(source, url);

  // Build links
  const links: Array<{ type: string; uuid: string; entityType?: string }> = [];
  if (clientUUID) {
    links.push({ type: 'swipeToClient', uuid: clientUUID, entityType: 'client_profile' });
  }

  // Create research atom with full metadata for Mac app compatibility
  const atom = await createAtom({
    type: 'research',
    title,
    body: notes ?? null,
    structured: {
      // swipeAnalysis format — used by swipeSelector.ts for format detection (line 492)
      swipeAnalysis: {
        hookText: hook ?? null,
        hookType: null,
        frameworkType: null,
        swipeContentFormat: contentFormat,
      },
      sourceUrl: url,
      contentSource: source,
      // richContent — used by CanvasBlock.detectMediaType() for block sizing
      richContent: {
        sourceType: source.toLowerCase(),
        thumbnailUrl,
        author: authorName,
      },
    },
    metadata: {
      isSwipeFile: true,
      contentSource: source.toLowerCase(),
      url,
      captureSource: 'telegram_cloud',
      // processingStatus MUST be in metadata — RealtimeSyncService reads meta["processingStatus"]
      processingStatus: 'pending',
      ...(thumbnailUrl ? { thumbnailUrl } : {}),
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
    format: contentFormat,
    thumbnailUrl,
    processingStatus: 'pending',
    ...(resolvedClientName ? { clientName: resolvedClientName } : {}),
    message: `Captured ${source} swipe: "${title}"${thumbnailUrl ? ' (with thumbnail)' : ''}`,
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
    if (source === 'Instagram') {
      const routeKeywords = new Set(['p', 'reel', 'reels', 'stories', 'tv', 'explore']);
      if (path.length >= 1 && !routeKeywords.has(path[0])) {
        return `Instagram: @${path[0]}`;
      }
      if (path[0] === 'reel' || path[0] === 'reels') return 'Instagram Reel';
      return 'Instagram Post';
    }
    if (source === 'TikTok' && path.length >= 1) return `TikTok: @${path[0].replace('@', '')}`;
    if (source === 'X' && path.length >= 1) return `X: @${path[0]}`;
    return `${source}: ${urlObj.hostname}`;
  } catch {
    return `${source} Swipe`;
  }
}

function extractYouTubeVideoId(url: string): string | null {
  // Handles youtube.com/watch?v=ID, youtu.be/ID, youtube.com/shorts/ID
  const patterns = [
    /[?&]v=([\w-]{11})/,
    /youtu\.be\/([\w-]{11})/,
    /\/shorts\/([\w-]{11})/,
    /\/embed\/([\w-]{11})/,
  ];
  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match) return match[1];
  }
  return null;
}

function mapSourceToFormat(source: string, url: string): string {
  if (source === 'YouTube') return 'youtube';
  if (source === 'Instagram') {
    if (url.includes('/reel/') || url.includes('/reels/')) return 'reel';
    return 'carousel'; // Default for Instagram posts
  }
  if (source === 'TikTok') return 'reel';
  if (source === 'X') return 'reel'; // X/Twitter short-form
  return 'reel'; // Default
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
