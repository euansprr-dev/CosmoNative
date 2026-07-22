// cosmo-cloud-agent/src/swipes/api.ts
// Swipe worker HTTP surface:
//   POST /api/swipes/process        {swipeUUID} — instant kick (skip the cron wait)
//   POST /api/swipes/refresh-stats  {swipeUUID} — re-fetch engagement only
//   GET  /api/swipes/health         — worker lag + counters
// Auth: service keys (same set as the writing API) OR a Supabase user JWT
// belonging to the configured user — the iPhone sends its session token.

import { Router, Request, Response } from 'express';
import { supabase, userId } from '../db/client';
import { config } from '../config';
import { pendingHealth, processSwipe, refreshEngagement, swipeWorkerStats } from './processor';
import { apifyRunsThisMonth } from './instagram';
import { getProgress } from './progress';
import { createAtom } from '../db/queries';

export const swipesRouter = Router();

/** Supported capture platforms → (contentSource, placeholder title). v1 = IG + YouTube. */
function captureTarget(url: string): { contentSource: string; title: string } | null {
  if (/instagram\.com/i.test(url)) return { contentSource: 'instagram', title: 'Instagram' };
  if (/youtube\.com|youtu\.be/i.test(url)) return { contentSource: 'youtube', title: 'YouTube video' };
  return null;
}

async function authenticate(req: Request, res: Response): Promise<boolean> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing Authorization header' });
    return false;
  }

  let token = authHeader.slice(7);
  // Swift Optional(...) interpolation quirk (see api/writing.ts).
  if (token.startsWith('Optional("') && token.endsWith('")')) {
    token = token.slice(10, -2);
  }

  const validKeys = [config.writingApiKey, process.env.SUPABASE_SERVICE_ROLE_KEY, 'cosmo-native-writing-2026'].filter(Boolean);
  if (validKeys.includes(token)) return true;

  // Fall back: a Supabase user JWT for THE configured user (iPhone path).
  try {
    const { data, error } = await supabase.auth.getUser(token);
    if (!error && data.user?.id === userId) return true;
  } catch {
    // fall through to 403
  }

  res.status(403).json({ error: 'Invalid API key' });
  return false;
}

swipesRouter.post('/process', async (req: Request, res: Response) => {
  if (!(await authenticate(req, res))) return;
  const { swipeUUID } = req.body ?? {};
  if (typeof swipeUUID !== 'string' || !swipeUUID) {
    res.status(400).json({ error: 'swipeUUID is required' });
    return;
  }
  console.log(`⚡ [API] swipe process kick: ${swipeUUID.slice(0, 8)}`);
  // Respond immediately; processing continues in the background.
  res.json({ status: 'queued' });
  void processSwipe(swipeUUID).catch(error => {
    console.error(`❌ kicked swipe ${swipeUUID.slice(0, 8)} failed:`, error);
  });
});

swipesRouter.post('/refresh-stats', async (req: Request, res: Response) => {
  if (!(await authenticate(req, res))) return;
  const { swipeUUID } = req.body ?? {};
  if (typeof swipeUUID !== 'string' || !swipeUUID) {
    res.status(400).json({ error: 'swipeUUID is required' });
    return;
  }
  console.log(`📊 [API] engagement refresh: ${swipeUUID.slice(0, 8)}`);
  try {
    const ok = await refreshEngagement(swipeUUID);
    res.json({ status: ok ? 'refreshed' : 'unsupported' });
  } catch (error) {
    res.status(502).json({ error: error instanceof Error ? error.message : 'refresh failed' });
  }
});

// Create a swipe from an external source (the Slack relay). Additive only: it
// inserts a NEW pending swipe atom exactly like an iPhone capture, then kicks
// processing. Never touches existing atoms. Dedups by URL.
swipesRouter.post('/capture', async (req: Request, res: Response) => {
  if (!(await authenticate(req, res))) return;
  const rawUrl = typeof req.body?.url === 'string' ? req.body.url.trim() : '';
  const savedBy = typeof req.body?.savedBy === 'string' ? req.body.savedBy.trim() : '';
  if (!rawUrl) {
    res.status(400).json({ error: 'url is required' });
    return;
  }
  const target = captureTarget(rawUrl);
  if (!target) {
    res.status(422).json({ error: 'unsupported platform (Instagram / YouTube only)' });
    return;
  }

  // Dedup: if this URL is already a swipe, return it instead of creating a twin.
  const { data: existing } = await supabase
    .from('atoms')
    .select('uuid')
    .eq('user_id', userId)
    .eq('type', 'research')
    .eq('is_deleted', false)
    .eq('metadata->>isSwipeFile', 'true')
    .eq('metadata->>url', rawUrl)
    .limit(1)
    .maybeSingle();
  if (existing?.uuid) {
    res.json({ status: 'exists', swipeUUID: existing.uuid });
    return;
  }

  const atom = await createAtom({
    type: 'research',
    title: target.title,
    structured: { sourceUrl: rawUrl },
    metadata: {
      isSwipeFile: true,
      url: rawUrl,
      contentSource: target.contentSource,
      processingStatus: 'pending',
      captureSource: 'slack',
      ...(savedBy ? { savedBy } : {}),
    },
  });
  if (!atom) {
    res.status(500).json({ error: 'failed to create swipe' });
    return;
  }

  console.log(`🔖 [API] slack capture ${atom.uuid.slice(0, 8)} (${target.contentSource}) by ${savedBy || 'unknown'}`);
  res.json({ status: 'queued', swipeUUID: atom.uuid });
  void processSwipe(atom.uuid).catch(error => {
    console.error(`❌ slack-captured swipe ${atom.uuid.slice(0, 8)} failed:`, error);
  });
});

// Live pipeline progress for the clients' progress bars. `known:false` when
// this worker instance isn't processing the swipe (restart / Mac fallback) —
// clients fall back to status-based estimates.
swipesRouter.get('/progress/:uuid', async (req: Request, res: Response) => {
  if (!(await authenticate(req, res))) return;
  const progress = getProgress(req.params.uuid);
  if (!progress) {
    res.json({ known: false });
    return;
  }
  res.json({ known: true, stage: progress.stage, progress: progress.progress });
});

swipesRouter.get('/health', async (_req: Request, res: Response) => {
  const health = await pendingHealth();
  res.json({
    ...health,
    ...swipeWorkerStats(),
    apifyRunsThisMonth: apifyRunsThisMonth(),
    workerEnabled: config.swipeWorkerEnabled,
    whisperConfigured: config.openaiApiKey.length > 0,
    videoUnderstandingTier: config.geminiApiKey ? 'gemini-direct' : 'openrouter',
  });
});
