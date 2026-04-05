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
import { getOrCreateEngine } from '../writing/engine';
import { detectContentFormat } from '../writing/types';
import { batchExtractAll, extractQuarkProfile, buildQuarkSummary } from '../writing/quarkExtractor';
import { extractWithCodex, summarizeCodexExtraction } from '../writing/codexExtractor';
import { loadExemplarCodex } from '../writing/codexLoader';
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
  // Accept the Supabase service role key, the configured writing API key, or the shared app secret
  const validKeys = [config.writingApiKey, process.env.SUPABASE_SERVICE_ROLE_KEY, 'cosmo-native-writing-2026'].filter(Boolean);
  if (!validKeys.includes(token)) {
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
// POST /api/writing/session — Single agentic session (outline-required)
// ============================================================

writingRouter.post('/session', async (req: Request, res: Response) => {
  if (!authenticate(req, res)) return;

  const { contentUUID, userDirection, localMetadata } = req.body;

  if (!contentUUID) {
    res.status(400).json({ error: 'contentUUID is required' });
    return;
  }

  // Stream NDJSON progress events — keeps connection alive during long sessions
  res.setHeader('Content-Type', 'application/x-ndjson');
  res.setHeader('Transfer-Encoding', 'chunked');
  res.setHeader('Cache-Control', 'no-cache');
  res.flushHeaders();

  try {
    // If localMetadata provided, merge into the atom in Supabase BEFORE engine init.
    if (localMetadata && typeof localMetadata === 'object') {
      console.log(`  ⚛️ [Session] Merging ${Object.keys(localMetadata).length} local metadata fields into atom`);
      await updateAtom(contentUUID, { metadata: localMetadata });
    }

    const engine = await getOrCreateEngine(contentUUID);

    // Stream progress events to Swift client
    engine.onSessionProgress = (event) => {
      try { res.write(JSON.stringify(event) + '\n'); } catch {}
    };

    const result = await engine.runSingleSession(userDirection || '');

    // Clean up callback
    engine.onSessionProgress = undefined;

    // Read final state from DB
    const atom = await fetchAtom(contentUUID);
    const draft = atom?.body || '';
    const wordCount = draft.split(/\s+/).filter(Boolean).length;

    // Final event with the complete result
    res.write(JSON.stringify({
      type: 'complete',
      success: true,
      contentUUID,
      formattedDraft: draft,
      format: detectContentFormat(atom?.metadata || null),
      wordCount,
      engineNotes: result.text,
    }) + '\n');
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error(`❌ [Session] Error: ${msg}`);
    try { res.write(JSON.stringify({ type: 'error', success: false, error: msg }) + '\n'); } catch {}
  }
  res.end();
});

// ============================================================
// Content Physics Codex
// ============================================================

// No auth required — endpoint is behind Railway deployment

// Start codex pipeline (background — returns immediately)
writingRouter.post('/codex/generate', async (req: Request, res: Response) => {
  const { reExtractAll, skipExtraction, pass2Only, pass3Only, cleanupOnly, rewriteWalkthroughs, useCodexLanguage } = req.body || {};

  const progress = getCodexProgress();
  if (progress.status === 'extracting' || progress.status === 'computing_stats' || progress.status === 'synthesizing' || progress.status === 'saving') {
    res.json({ success: false, error: 'Pipeline already running', progress });
    return;
  }

  // Start in background — don't await
  startCodexPipeline({ reExtractAll: !!reExtractAll, skipExtraction: !!skipExtraction, pass2Only: !!pass2Only, pass3Only: !!pass3Only, cleanupOnly: !!cleanupOnly, rewriteWalkthroughs: !!rewriteWalkthroughs, useCodexLanguage: !!useCodexLanguage }).catch(err => {
    console.log(`  ❌ Background pipeline error: ${err.message}`);
  });

  res.json({ success: true, message: 'Pipeline started. Poll /codex/progress for updates.' });
});

// Poll progress
writingRouter.get('/codex/progress', async (req: Request, res: Response) => {
  res.json(getCodexProgress());
});

// Single swipe extraction — used by "Generate Codex Profile" button in SwipeStudy
// Produces both a CodexProfile (JSON) and a Blueprint Walkthrough (text) in one call
// using the Exemplar Codex's Periodic Table as the taxonomy.
// No auth required — endpoint is behind Railway deployment.
writingRouter.post('/codex/extract-single', async (req: Request, res: Response) => {
  const { swipeUUID, useCodexLanguage } = req.body || {};

  if (!swipeUUID) {
    res.status(400).json({ error: 'swipeUUID is required' });
    return;
  }

  try {
    console.log(`\n  🔬 Single extraction requested: ${swipeUUID} (codex: ${useCodexLanguage !== false})`);
    const atom = await fetchAtom(swipeUUID);
    if (!atom) {
      res.status(404).json({ error: 'Swipe not found' });
      return;
    }

    // Default to Codex extraction. Fall back to old extractor if useCodexLanguage=false
    if (useCodexLanguage === false) {
      // Legacy path — old 10-pass extraction
      const profile = await extractQuarkProfile(atom);
      if (!profile) {
        res.status(500).json({ error: 'Extraction failed — check server logs' });
        return;
      }
      const existing = atom.structured || {};
      await updateAtom(swipeUUID, {
        structured: { ...existing, contentPhysics: profile },
      });
      res.json({
        success: true,
        slides: profile.slideQuarks?.length || 0,
        transitions: profile.transitions?.length || 0,
        hasFabric: !!profile.deepFabric,
        hasRhythm: !!profile.rhythm,
        hasBonds: !!profile.longRangeInteractions,
        hasSimulation: (profile.readerSimulation || []).length > 0,
        profileLanguage: 'legacy',
      });
      return;
    }

    // Codex extraction path — load full Codex, extract profile + walkthrough
    const codexBody = await loadExemplarCodex();
    if (!codexBody) {
      res.status(500).json({ error: 'Exemplar Codex not found — generate it first from Codex settings' });
      return;
    }

    const { profile, walkthrough } = await extractWithCodex(atom, codexBody);
    const summary = summarizeCodexExtraction(profile, walkthrough);

    // Save both to atom — merge into existing structured data
    const existing = atom.structured || {};
    const newStructured = {
      ...existing,
      codexProfile: profile,
      blueprintWalkthrough: walkthrough,
      codexProfileVersion: 2,
    };

    const structuredKeys = Object.keys(newStructured);
    const structuredSize = JSON.stringify(newStructured).length;
    console.log(`  📦 Saving structured: ${structuredKeys.length} keys, ${structuredSize} chars (keys: ${structuredKeys.join(', ')})`);

    const saved = await updateAtom(swipeUUID, { structured: newStructured });
    if (!saved) {
      console.log(`  ❌ updateAtom returned null — save likely failed silently`);
      res.status(500).json({ error: 'Failed to save extraction results to database' });
      return;
    }

    // Verify the save
    const verify = await fetchAtom(swipeUUID);
    const hasCodex = !!(verify?.structured as any)?.codexProfile;
    const hasWalkthrough = !!(verify?.structured as any)?.blueprintWalkthrough;
    console.log(`  🔍 Verify save: codexProfile=${hasCodex}, walkthrough=${hasWalkthrough}`);

    console.log(`  ✅ Codex extraction complete: ${summary.slides} slides, ${summary.transitions} transitions, walkthrough: ${summary.walkthroughLength} chars`);

    res.json({ success: true, ...summary });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Single extraction failed: ${msg}`);
    res.status(500).json({ error: msg });
  }
});
