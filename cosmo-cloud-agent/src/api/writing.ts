// cosmo-cloud-agent/src/api/writing.ts
// REST API endpoints for the cloud writing engine.
// Allows the Mac app (and any client) to use the same canonical engine as Telegram.
//
// Endpoints:
//   POST /api/writing/outline  — generate outline + hooks
//   POST /api/writing/draft    — generate full draft
//   POST /api/writing/revise   — revise draft with feedback
//   POST /api/writing/read     — read current draft
//
// Authentication: Bearer token (Supabase auth token) in Authorization header.
// The token is validated by checking it matches the configured COSMO_USER_ID.

import { Request, Response, Router } from 'express';
import { generateOutline, generateDraft, reviseDraft, readDraft } from '../tools/writing';
import { config } from '../config';

export const writingRouter = Router();

// ============================================================
// Auth Middleware
// ============================================================

function authenticate(req: Request, res: Response): boolean {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing Authorization header' });
    return false;
  }

  const token = authHeader.slice(7);
  // Accept either the Supabase service role key or a simple shared secret
  // For now, check against the configured API key
  if (token !== config.writingApiKey && token !== process.env.SUPABASE_SERVICE_ROLE_KEY) {
    res.status(403).json({ error: 'Invalid API key' });
    return false;
  }

  return true;
}

// ============================================================
// POST /api/writing/outline
// ============================================================

writingRouter.post('/outline', async (req: Request, res: Response) => {
  if (!authenticate(req, res)) return;

  const { contentUUID, blueprintTitles, notes, clientName, contentFormat, blueprintSwipeUUIDs, contextAtomUUIDs } = req.body;

  if (!contentUUID) {
    res.status(400).json({ error: 'contentUUID is required' });
    return;
  }

  console.log(`📝 [API] generate_outline: ${contentUUID}`);

  try {
    const result = await generateOutline({
      contentUUID,
      blueprintTitles,
      blueprintSwipeUUIDs,
      notes,
      clientName,
      contentFormat,
      contextAtomUUIDs,
    });

    const parsed = JSON.parse(result);
    res.json(parsed);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error(`❌ [API] generate_outline failed: ${msg}`);
    res.status(500).json({ error: msg });
  }
});

// ============================================================
// POST /api/writing/draft
// ============================================================

writingRouter.post('/draft', async (req: Request, res: Response) => {
  if (!authenticate(req, res)) return;

  const { contentUUID, userDirection, clientName, contentFormat } = req.body;

  if (!contentUUID) {
    res.status(400).json({ error: 'contentUUID is required' });
    return;
  }

  console.log(`📝 [API] generate_draft: ${contentUUID}`);

  try {
    const result = await generateDraft({
      contentUUID,
      userDirection,
      clientName,
      contentFormat,
    });

    const parsed = JSON.parse(result);
    res.json(parsed);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error(`❌ [API] generate_draft failed: ${msg}`);
    res.status(500).json({ error: msg });
  }
});

// ============================================================
// POST /api/writing/revise
// ============================================================

writingRouter.post('/revise', async (req: Request, res: Response) => {
  if (!authenticate(req, res)) return;

  const { contentUUID, feedback, currentDraft, clientName } = req.body;

  if (!contentUUID) {
    res.status(400).json({ error: 'contentUUID is required' });
    return;
  }
  if (!feedback) {
    res.status(400).json({ error: 'feedback is required' });
    return;
  }

  console.log(`📝 [API] revise_draft: ${contentUUID}`);

  try {
    const result = await reviseDraft({
      contentUUID,
      feedback,
      currentDraft,
      clientName,
    });

    const parsed = JSON.parse(result);
    res.json(parsed);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error(`❌ [API] revise_draft failed: ${msg}`);
    res.status(500).json({ error: msg });
  }
});

// ============================================================
// POST /api/writing/read
// ============================================================

writingRouter.post('/read', async (req: Request, res: Response) => {
  if (!authenticate(req, res)) return;

  const { contentUUID } = req.body;

  if (!contentUUID) {
    res.status(400).json({ error: 'contentUUID is required' });
    return;
  }

  try {
    const result = await readDraft({ contentUUID });
    const parsed = JSON.parse(result);
    res.json(parsed);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    res.status(500).json({ error: msg });
  }
});
