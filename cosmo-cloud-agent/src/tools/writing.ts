// cosmo-cloud-agent/src/tools/writing.ts
// Writing tools — 6 tools using the Cloud Writing Engine
// PORTING SOURCE: AgentToolExecutor.swift lines 2037-2500
// Phase 3: Real engine implementation (replaces stubs)

import { fetchAtom, updateAtom, fuzzyFindClient } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';
import { getOrCreateEngine, evictEngine } from '../writing/engine';
import { renderDraftForDisplay, detectContentFormat } from '../writing/types';

// ============================================================
// 1. generate_outline
// PORTING CHECKLIST: AgentToolExecutor.swift line 2037
// ✅ contentUUID required; clientName, blueprintSwipeUUID, contentFormat, notes optional
// ✅ Pre-engine: inject blueprintSwipeUUID + contentFormat into metadata, evict cache
// ✅ Engine: sendMessage(instruction, phase: brainstorm)
// ✅ Return: {success, contentUUID, outlineSections, hookVariants, sectionCount, hookCount, swipesUsed, swipeCount}
// ============================================================

export async function generateOutline(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const atom = await fetchAtom(contentUUID);
  if (!atom) return jsonError(`Content not found: ${contentUUID}`);

  // Pre-engine metadata injection
  const metaUpdates: Record<string, any> = {};
  let shouldEvict = false;

  if (args.blueprintSwipeUUID) {
    const existing = (atom.metadata?.inheritedSwipeUUIDs as string[]) || [];
    if (!existing.includes(args.blueprintSwipeUUID)) {
      metaUpdates.inheritedSwipeUUIDs = [args.blueprintSwipeUUID, ...existing];
      shouldEvict = true;
    }
  }

  if (args.contentFormat) {
    metaUpdates.explicitFormat = args.contentFormat;
    metaUpdates.contentFormat = args.contentFormat;
    shouldEvict = true;
  }

  if (Object.keys(metaUpdates).length > 0) {
    await updateAtom(contentUUID, { metadata: metaUpdates });
  }

  if (shouldEvict) evictEngine(contentUUID);

  // Get or create engine
  const engine = getOrCreateEngine(contentUUID);

  // Build instruction
  let instruction = args.notes || 'Generate an outline for this content piece.';
  if (args.blueprintSwipeUUID) {
    instruction += ' Use BLUEPRINT-FIRST methodology — study the primary blueprint swipe structure and mirror it.';
  }
  instruction += ' Call update_outline with the sections, then add_hooks with hook variants.';

  try {
    const response = await engine.sendMessage(instruction, 'brainstorm');

    const outline = engine.getOutline();
    const hooks = engine.getHooks();

    return jsonEncode({
      success: true,
      contentUUID,
      message: response || 'Outline generated via cloud writing engine.',
      outlineSections: outline.map((o, i) => `${i + 1}. ${o.title}${o.beatLabel ? ` [${o.beatLabel}]` : ''}`),
      hookVariants: hooks,
      sectionCount: outline.length,
      hookCount: hooks.length,
      swipesUsed: engine.getSwipeTitles(),
      swipeCount: engine.getSwipeCount(),
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return jsonError(`Outline generation failed: ${msg}`);
  }
}

// ============================================================
// 2. generate_draft
// PORTING CHECKLIST: AgentToolExecutor.swift line 2163
// ✅ contentUUID required; clientName, contentFormat, userDirection optional
// ✅ Engine: sendMessage(instruction, phase: draft)
// ✅ Return: {success, contentUUID, formattedDraft, format, swipesUsed, swipeCount}
// ============================================================

export async function generateDraft(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  // Format injection
  if (args.contentFormat) {
    await updateAtom(contentUUID, { metadata: { explicitFormat: args.contentFormat, contentFormat: args.contentFormat } });
    evictEngine(contentUUID);
  }

  const engine = getOrCreateEngine(contentUUID);

  const direction = args.userDirection || 'Write the full first draft following the outline. Mirror the PRIMARY blueprint structure. Call write_draft with the complete draft.';

  try {
    const response = await engine.sendMessage(direction, 'draft');

    // Fetch updated atom to get the draft
    const updated = await fetchAtom(contentUUID);
    const draftBody = updated?.body || '';
    const formattedDraft = renderDraftForDisplay(draftBody);
    const wordCount = draftBody.split(/\s+/).filter(Boolean).length;

    // Detect format
    let format = 'plaintext';
    try {
      const parsed = JSON.parse(draftBody);
      if (parsed.slides) format = 'carousel';
      else if (parsed.tweets) format = 'thread';
      else if (Array.isArray(parsed)) format = 'json';
    } catch {}

    return jsonEncode({
      success: true,
      contentUUID,
      message: 'Here is the draft. Display the text below to the user exactly as-is:',
      formattedDraft,
      format,
      wordCount,
      engineNotes: response,
      swipesUsed: engine.getSwipeTitles(),
      swipeCount: engine.getSwipeCount(),
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return jsonError(`Draft generation failed: ${msg}`);
  }
}

// ============================================================
// 3. read_draft
// PORTING CHECKLIST: AgentToolExecutor.swift line 2266
// ✅ contentUUID required
// ✅ Return: {success, contentUUID, title, formattedDraft, wordCount}
// ============================================================

export async function readDraft(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const atom = await fetchAtom(contentUUID);
  if (!atom) return jsonError(`Content not found: ${contentUUID}`);

  const body = atom.body || '';
  const formattedDraft = renderDraftForDisplay(body);
  const wordCount = body.split(/\s+/).filter(Boolean).length;

  return jsonEncode({
    success: true,
    contentUUID,
    title: atom.title,
    formattedDraft,
    wordCount,
  });
}

// ============================================================
// 4. revise_draft
// PORTING CHECKLIST: AgentToolExecutor.swift line 2363
// ✅ contentUUID, feedback required; currentDraft, clientName optional
// ✅ Engine: sendMessage(revision instruction, phase: draft)
// ✅ Return: {success, contentUUID, formattedDraft, format, swipesUsed}
// ============================================================

export async function reviseDraft(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const feedback = args.feedback as string;
  if (!feedback) return jsonError('feedback is required');

  // If currentDraft provided and atom body is empty, seed it
  if (args.currentDraft) {
    const atom = await fetchAtom(contentUUID);
    if (atom && (!atom.body || atom.body.length === 0)) {
      await updateAtom(contentUUID, { body: args.currentDraft });
    }
  }

  const engine = getOrCreateEngine(contentUUID);

  const instruction = `REVISION REQUEST:\n${feedback}\n\nREVISION RULES — MANDATORY:\n- Use read_draft first to see the full current draft\n- Apply ONLY the requested changes\n- Do NOT compress slides/sections\n- Do NOT introduce new frameworks\n- Do NOT add generic language unless asked\n- Preserve EVERY unchanged slide\n- Output the COMPLETE revised draft via write_draft`;

  try {
    const response = await engine.sendMessage(instruction, 'draft');

    const updated = await fetchAtom(contentUUID);
    const draftBody = updated?.body || '';
    const formattedDraft = renderDraftForDisplay(draftBody);

    let format = 'plaintext';
    try {
      const parsed = JSON.parse(draftBody);
      if (parsed.slides) format = 'carousel';
      else if (parsed.tweets) format = 'thread';
    } catch {}

    return jsonEncode({
      success: true,
      contentUUID,
      message: 'Here is the revised draft:',
      formattedDraft,
      format,
      engineNotes: response,
      swipesUsed: engine.getSwipeTitles(),
      swipeCount: engine.getSwipeCount(),
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return jsonError(`Revision failed: ${msg}`);
  }
}

// ============================================================
// 5. generate_hooks
// PORTING CHECKLIST: AgentToolExecutor.swift line 2452
// ✅ contentUUID required; clientName, count optional
// ✅ Engine: sendMessage(instruction, phase: brainstorm)
// ✅ Return: {success, contentUUID, hookVariants, engineNotes}
// ============================================================

export async function generateHooks(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const count = Math.min((args.count as number) || 5, 8);

  const engine = getOrCreateEngine(contentUUID);

  const instruction = `Generate ${count} hook variants for this content. The hook type and sentence structure must match the blueprint swipe's pattern. Call add_hooks with the variants.`;

  try {
    const response = await engine.sendMessage(instruction, 'brainstorm');
    const hooks = engine.getHooks();

    return jsonEncode({
      success: true,
      contentUUID,
      message: 'Hooks generated via cloud writing engine.',
      hookVariants: hooks,
      engineNotes: response,
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return jsonError(`Hook generation failed: ${msg}`);
  }
}

// ============================================================
// 6. score_draft
// PORTING CHECKLIST: AgentToolExecutor.swift line 3160
// ✅ contentUUID required
// ✅ Uses Sonnet model for evaluation
// ✅ Return: scorecard with 6 dimensions
// ============================================================

export async function scoreDraft(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const atom = await fetchAtom(contentUUID);
  if (!atom) return jsonError(`Content not found: ${contentUUID}`);

  const draft = atom.body || '';
  if (!draft) return jsonError('No draft to score');

  const wordCount = draft.split(/\s+/).filter(Boolean).length;

  // Use the scorecard engine (simplified for cloud)
  const { scoreDraftWithLLM } = await import('./scorecard');
  const scorecard = await scoreDraftWithLLM(atom, draft);

  return jsonEncode({
    success: true,
    contentUUID,
    ...scorecard,
    wordCount,
  });
}
