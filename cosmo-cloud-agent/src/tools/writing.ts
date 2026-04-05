// cosmo-cloud-agent/src/tools/writing.ts
// Writing tools — 6 tools using the Cloud Writing Engine
// PORTING SOURCE: AgentToolExecutor.swift lines 2037-2500
// Phase 3: Real engine implementation (replaces stubs)

import { Atom, fetchAtom, updateAtom, createAtom, fuzzyFindClient, searchAtoms, searchAtomsByExactTitle, isSwipeFileAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';
import { getOrCreateEngine, evictEngine } from '../writing/engine';
import { renderDraftForDisplay, detectContentFormat } from '../writing/types';
import { config } from '../config';

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

  // Collect ALL blueprint UUIDs (single + array)
  const blueprintUUIDs: string[] = [];
  if (args.blueprintSwipeUUID) blueprintUUIDs.push(args.blueprintSwipeUUID);
  if (args.blueprintSwipeUUIDs && Array.isArray(args.blueprintSwipeUUIDs)) {
    for (const uuid of args.blueprintSwipeUUIDs) {
      if (uuid && !blueprintUUIDs.includes(uuid)) blueprintUUIDs.push(uuid);
    }
  }

  // Resolve blueprint TITLES to UUIDs (so agent doesn't need search_swipes)
  const resolvedBlueprints: string[] = [];
  const failedBlueprints: string[] = [];
  if (args.blueprintTitles && Array.isArray(args.blueprintTitles)) {
    for (const title of args.blueprintTitles) {
      // Try exact title match first, then fall back to fuzzy search
      let results = await searchAtomsByExactTitle(title, ['research']);
      if (results.length === 0) {
        results = await searchAtoms(title, { types: ['research'], limit: 5 });
      }
      const swipe = results.find(a => isSwipeFileAtom(a));
      if (swipe && !blueprintUUIDs.includes(swipe.uuid)) {
        blueprintUUIDs.push(swipe.uuid);
        resolvedBlueprints.push(title);
        console.log(`    ✍️ Resolved blueprint: "${title}" → ${swipe.uuid}`);
      } else {
        const found = results.length;
        const swipeCount = results.filter(isSwipeFileAtom).length;
        failedBlueprints.push(title);
        console.log(`    ⚠️ Blueprint not found: "${title}" (${found} search results, ${swipeCount} were swipe files)`);
      }
    }
  }

  // Pre-engine metadata injection
  const metaUpdates: Record<string, any> = {};
  let shouldEvict = false;

  if (blueprintUUIDs.length > 0) {
    const existing = (atom.metadata?.inheritedSwipeUUIDs as string[]) || [];
    const merged = [...new Set([...blueprintUUIDs, ...existing])];
    if (JSON.stringify(merged) !== JSON.stringify(existing)) {
      metaUpdates.inheritedSwipeUUIDs = merged;
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
  const engine = await getOrCreateEngine(contentUUID);

  // Load @ mentioned context atoms (connections, research, ideas, etc.)
  let contextBlock = '';
  const contextAtomUUIDs = args.contextAtomUUIDs as string[] | undefined;
  if (contextAtomUUIDs && contextAtomUUIDs.length > 0) {
    const blocks: string[] = [];
    for (const uuid of contextAtomUUIDs) {
      const ctxAtom = await fetchAtom(uuid);
      if (ctxAtom) blocks.push(formatAtomAsContext(ctxAtom));
    }
    if (blocks.length > 0) {
      contextBlock = `REFERENCED CONTEXT (from @ mentions — use this as raw material for the content):\n${blocks.join('\n\n')}\n\n`;
      console.log(`    ✍️ Loaded ${blocks.length} context atoms from @ mentions`);
    }
  }

  // Build instruction — include user's structural notes + blueprint context + @ context
  let instruction = contextBlock + (args.notes || 'Generate an outline for this content piece.');
  if (blueprintUUIDs.length > 0) {
    instruction += `\n\n${blueprintUUIDs.length} blueprint swipes loaded as PRIMARY references. Study their structure and mirror it.`;
    instruction += ' Use BLUEPRINT-FIRST methodology.';
  }
  instruction += '\nCreate the writing plan with outline, hooks, and per-slide physics targets via create_writing_plan.';

  try {
    // Use 'draft' phase to trigger Phase 1 of the physics pipeline (not brainstorm loop)
    // Phase 1 creates plan + outline + hooks with full Content Physics — then stops for user confirmation
    const response = await engine.sendMessage(instruction, 'draft');

    const outline = engine.getOutline();
    const hooks = engine.getHooks();

    return jsonEncode({
      success: true,
      contentUUID,
      message: 'STOP HERE. Show this outline and hook variants to the user. Ask which hook they want. Do NOT call generate_draft until user confirms.',
      blueprintStatus: failedBlueprints.length > 0
        ? { resolved: resolvedBlueprints, failed: failedBlueprints, warning: `Could not find: ${failedBlueprints.join(', ')}. Tell the user.` }
        : undefined,
      outlineSections: outline.map((o, i) => `${i + 1}. ${o.title}${o.beatLabel ? ` [${o.beatLabel}]` : ''}`),
      hookVariants: hooks,
      sectionCount: outline.length,
      hookCount: hooks.length,
      swipesLoaded: engine.getSwipesSummary(),
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

  // Format injection — only update metadata, NEVER evict engine during draft
  // (engine was already initialized with the correct format during outline)
  if (args.contentFormat) {
    await updateAtom(contentUUID, { metadata: { explicitFormat: args.contentFormat, contentFormat: args.contentFormat } });
    // DO NOT evictEngine here — preserves conversation context from outline phase
  }

  // Save research briefing to content atom metadata (persists across all phases + revisions)
  if (args.researchBriefing) {
    await updateAtom(contentUUID, { metadata: { researchBriefing: args.researchBriefing } });
    console.log(`  📋 Research briefing saved: ${(args.researchBriefing as string).length} chars`);
  }

  const engine = await getOrCreateEngine(contentUUID);

  const direction = args.userDirection || 'Write the full first draft following the outline. Mirror the PRIMARY blueprint structure. Call write_draft with the complete draft.';

  // Single session: if feature flag on AND codex outline exists, run all phases in one Opus call
  const atom = await fetchAtom(contentUUID);
  const hasCodexOutline = atom?.metadata?.codexOutline || atom?.metadata?.inheritedCodexOutline;
  if (config.useSingleSession && hasCodexOutline) {
    console.log(`  ⚛️ [generateDraft] Single session mode — codex outline detected`);
    try {
      const sessionResult = await engine.runSingleSession(direction);
      const updated = await fetchAtom(contentUUID);
      const draftBody = updated?.body || '';
      const formattedDraft = renderDraftForDisplay(draftBody);
      const wordCount = draftBody.split(/\s+/).filter(Boolean).length;
      let format = 'plaintext';
      try {
        const parsed = JSON.parse(draftBody);
        if (parsed.slides) format = 'carousel';
        else if (parsed.tweets) format = 'thread';
      } catch {}
      return jsonEncode({
        success: true,
        contentUUID,
        message: 'STOP HERE. Show this draft to the user exactly as-is. Ask for feedback. Do NOT call any more tools.',
        formattedDraft,
        format,
        wordCount,
        engineNotes: sessionResult.text,
        swipesLoaded: engine.getSwipesSummary(),
        swipeCount: engine.getSwipeCount(),
      });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`  ❌ [generateDraft] Single session failed, falling back to multi-phase: ${msg}`);
      // Fall through to existing multi-phase pipeline
    }
  }

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
      message: 'STOP HERE. Show this draft to the user exactly as-is. Ask for feedback. Do NOT call any more tools.',
      formattedDraft,
      format,
      wordCount,
      engineNotes: response,
      swipesLoaded: engine.getSwipesSummary(),
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

  // Capture before-state for experience creation
  const beforeAtom = await fetchAtom(contentUUID);
  const beforeBody = beforeAtom?.body || '';

  // If currentDraft provided and atom body is empty, seed it
  if (args.currentDraft && (!beforeBody || beforeBody.length === 0)) {
    await updateAtom(contentUUID, { body: args.currentDraft });
  }

  const engine = await getOrCreateEngine(contentUUID);

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

    // Capture experience: if draft changed significantly, save before/after for few-shot learning
    if (beforeBody && draftBody && beforeBody !== draftBody) {
      const beforeWords = beforeBody.split(/\s+/).length;
      const afterWords = draftBody.split(/\s+/).length;
      const wordDiff = Math.abs(afterWords - beforeWords);
      const editRatio = wordDiff / Math.max(beforeWords, 1);
      if (editRatio > 0.1 || wordDiff > 20) { // >10% changed or 20+ words different
        try {
          const clientUUID = beforeAtom?.metadata?.clientProfileUUID as string | undefined;
          await createExperienceAtom(beforeBody, draftBody, feedback, editRatio, clientUUID);
          console.log(`    ✍️ Experience captured (${(editRatio * 100).toFixed(0)}% edit distance)`);
        } catch (e) {
          console.log(`    ⚠️ Failed to capture experience: ${e}`);
        }
      }
    }

    return jsonEncode({
      success: true,
      contentUUID,
      message: 'STOP HERE. Show this revised draft to the user. Ask if they want more changes.',
      formattedDraft,
      format,
      engineNotes: response,
      swipesLoaded: engine.getSwipesSummary(),
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

  const engine = await getOrCreateEngine(contentUUID);

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

// ============================================================
// Context Atom Formatting (for @ mentions)
// ============================================================

/**
 * Format an atom for injection into writing engine context.
 * Special handling for connections (8-section structured content).
 */
function formatAtomAsContext(atom: Atom): string {
  if (atom.type === 'connection') {
    return formatConnectionForWriting(atom);
  }

  // Research/swipe: include full body
  if (atom.type === 'research') {
    const analysis = atom.structured?.swipeAnalysis || atom.structured;
    const hookText = (analysis?.hookText as string) || '';
    return `[${atom.type.toUpperCase()}: ${atom.title}]\nHook: ${hookText}\n${atom.body || ''}`;
  }

  // Default: title + body
  return `[${atom.type.toUpperCase()}: ${atom.title}]\n${atom.body || ''}`;
}

/**
 * Format a connection atom with all 8 structured sections as flexible building blocks.
 * Any part can serve any beat — a belief can be a hook, a problem can be a CTA.
 */
function formatConnectionForWriting(atom: Atom): string {
  const model = atom.structured || {};
  const sections: string[] = [];
  sections.push(`=== CONNECTION: ${atom.title} ===`);
  if (model.idea) sections.push(`Core Idea: ${model.idea}`);
  if (model.personalBelief) sections.push(`Personal Belief: ${model.personalBelief}`);

  sections.push('\n--- CONTENT BUILDING BLOCKS ---');
  sections.push('These are raw material. Any piece can serve ANY beat — a belief can be a hook,');
  sections.push('a problem can be a CTA, an example can open the piece. Use them creatively.');

  if (model.goal) sections.push(`\nGOAL:\n${model.goal}`);
  if (model.problems) sections.push(`\nPROBLEMS:\n${model.problems}`);
  if (model.benefit) sections.push(`\nBENEFITS:\n${model.benefit}`);
  if (model.example) sections.push(`\nEXAMPLES:\n${model.example}`);
  if (model.beliefsObjections) sections.push(`\nBELIEFS & OBJECTIONS:\n${model.beliefsObjections}`);
  if (model.process) sections.push(`\nPROCESS:\n${model.process}`);
  if (model.conceptName) sections.push(`\nCONCEPT NAME: "${model.conceptName}"`);

  // References as evidence/authority sources
  if (model.referencesData) {
    try {
      const raw = typeof model.referencesData === 'string' ? model.referencesData : JSON.stringify(model.referencesData);
      const refs = JSON.parse(raw);
      if (Array.isArray(refs) && refs.length > 0) {
        sections.push(`\nREFERENCES:`);
        for (const ref of refs as any[]) {
          sections.push(`  • ${ref.title || ref.url || 'Source'}${ref.notes ? ': ' + ref.notes : ''}`);
        }
      }
    } catch {}
  }

  return sections.join('\n');
}

/**
 * Create an experience atom from a draft revision — captures before/after for few-shot learning.
 * These are loaded by engine.loadExperiences() and injected into Block 3A as editing examples.
 */
async function createExperienceAtom(
  beforeDraft: string,
  afterDraft: string,
  feedback: string,
  editDistance: number,
  clientUUID?: string,
): Promise<void> {
  // Truncate to reasonable size for few-shot examples
  const maxChars = 2000;
  const generated = beforeDraft.substring(0, maxChars);
  const edited = afterDraft.substring(0, maxChars);

  await createAtom({
    type: 'agent_learning',
    title: `Edit experience: ${feedback.substring(0, 80)}`,
    body: `BEFORE:\n${generated}\n\nAFTER:\n${edited}\n\nFEEDBACK: ${feedback}`,
    structured: {
      generatedExcerpt: generated,
      editedExcerpt: edited,
      diffSummary: feedback.substring(0, 500),
    },
    metadata: {
      subtype: 'experience',
      lessonType: 'experience',
      enforcement: 'advisory',
      confidence: 0.8,
      editDistance,
      ...(clientUUID ? { clientUUID } : {}),
    },
  });
}
