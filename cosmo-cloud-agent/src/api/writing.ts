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
import { batchExtractAll, extractQuarkProfile, buildQuarkSummary } from '../writing/quarkExtractor';
import { computeCodex, saveCodexAtom, invalidateCodexCache } from '../writing/codex';
import { startCodexPipeline, getCodexProgress } from '../writing/codexPipeline';
import { fetchAtom, updateAtom } from '../db/queries';
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

  let token = authHeader.slice(7);
  // Handle Swift Optional(...) string wrapping quirk — Swift String? interpolation
  // produces "Optional("eyJ...")" instead of the raw value
  if (token.startsWith('Optional("') && token.endsWith('")')) {
    token = token.slice(10, -2);
  }
  // Accept either the Supabase service role key or a simple shared secret
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

// ============================================================
// Content Physics Codex
// ============================================================

// No auth required — endpoint is behind Railway deployment

// Start codex pipeline (background — returns immediately)
writingRouter.post('/codex/generate', async (req: Request, res: Response) => {
  const { reExtractAll, skipExtraction, pass2Only } = req.body || {};

  const progress = getCodexProgress();
  if (progress.status === 'extracting' || progress.status === 'computing_stats' || progress.status === 'synthesizing' || progress.status === 'saving') {
    res.json({ success: false, error: 'Pipeline already running', progress });
    return;
  }

  // Start in background — don't await
  startCodexPipeline({ reExtractAll: !!reExtractAll, skipExtraction: !!skipExtraction, pass2Only: !!pass2Only }).catch(err => {
    console.log(`  ❌ Background pipeline error: ${err.message}`);
  });

  res.json({ success: true, message: 'Pipeline started. Poll /codex/progress for updates.' });
});

// Poll progress
writingRouter.get('/codex/progress', async (req: Request, res: Response) => {
  res.json(getCodexProgress());
});

// Single swipe extraction — used by "Generate Atomic Profile" button in SwipeStudy
// No auth required — endpoint is behind Railway deployment, and the Mac app's
// APIKeys.supabaseServiceRoleKey keychain access is unreliable
writingRouter.post('/codex/extract-single', async (req: Request, res: Response) => {
  const { swipeUUID } = req.body || {};

  if (!swipeUUID) {
    res.status(400).json({ error: 'swipeUUID is required' });
    return;
  }

  try {
    console.log(`\n  🔬 Single extraction requested: ${swipeUUID}`);
    const atom = await fetchAtom(swipeUUID);
    if (!atom) {
      res.status(404).json({ error: 'Swipe not found' });
      return;
    }

    const profile = await extractQuarkProfile(atom);
    if (!profile) {
      res.status(500).json({ error: 'Extraction failed — check server logs' });
      return;
    }

    // Save profile to atom
    const existing = atom.structured || {};
    await updateAtom(swipeUUID, {
      structured: { ...existing, contentPhysics: profile },
    });

    console.log(`  ✅ Single extraction complete: ${profile.slideQuarks?.length || 0} slides, ${profile.transitions?.length || 0} transitions`);

    res.json({
      success: true,
      slides: profile.slideQuarks?.length || 0,
      transitions: profile.transitions?.length || 0,
      hasFabric: !!profile.deepFabric,
      hasRhythm: !!profile.rhythm,
      hasBonds: !!profile.longRangeInteractions,
      hasSimulation: (profile.readerSimulation || []).length > 0,
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Single extraction failed: ${msg}`);
    res.status(500).json({ error: msg });
  }
});
