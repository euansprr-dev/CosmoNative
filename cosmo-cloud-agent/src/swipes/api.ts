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

export const swipesRouter = Router();

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
