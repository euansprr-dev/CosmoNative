// cosmo-cloud-agent/src/tools/writing.ts
// Writing tools — 6 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 2037-2500
// NOTE: Phase 3 will add the full CloudWritingEngine.
//       For now, these tools operate on atom data directly.
//       generate_outline and generate_draft will call OpenRouter API.

import { fetchAtom, updateAtom, fuzzyFindClient } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. generate_outline
// PORTING CHECKLIST: AgentToolExecutor.swift line 2037
// ✅ contentUUID required; clientName, blueprintSwipeUUID, contentFormat, notes optional
// ⚠️ PHASE 2: Returns stub directing to Phase 3 writing engine
// ============================================================

export async function generateOutline(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const atom = await fetchAtom(contentUUID);
  if (!atom) return jsonError(`Content not found: ${contentUUID}`);

  // Phase 3 will add CloudWritingEngine with full 4-block context assembly
  return jsonEncode({
    success: false,
    contentUUID,
    message: 'Outline generation requires the Cloud Writing Engine (Phase 3). Use the Mac app for now.',
    currentTitle: atom.title,
    currentPhase: atom.metadata?.phase ?? 'ideation',
  });
}

// ============================================================
// 2. generate_draft
// PORTING CHECKLIST: AgentToolExecutor.swift line 2163
// ⚠️ PHASE 2: Returns stub directing to Phase 3 writing engine
// ============================================================

export async function generateDraft(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const atom = await fetchAtom(contentUUID);
  if (!atom) return jsonError(`Content not found: ${contentUUID}`);

  return jsonEncode({
    success: false,
    contentUUID,
    message: 'Draft generation requires the Cloud Writing Engine (Phase 3). Use the Mac app for now.',
    currentTitle: atom.title,
    currentPhase: atom.metadata?.phase ?? 'ideation',
  });
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
// ⚠️ PHASE 2: Returns stub directing to Phase 3 writing engine
// ============================================================

export async function reviseDraft(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const feedback = args.feedback as string;
  if (!feedback) return jsonError('feedback is required');

  return jsonEncode({
    success: false,
    contentUUID,
    message: 'Draft revision requires the Cloud Writing Engine (Phase 3). Use the Mac app for now.',
  });
}

// ============================================================
// 5. generate_hooks
// PORTING CHECKLIST: AgentToolExecutor.swift line 2452
// ⚠️ PHASE 2: Returns stub directing to Phase 3 writing engine
// ============================================================

export async function generateHooks(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  return jsonEncode({
    success: false,
    contentUUID,
    message: 'Hook generation requires the Cloud Writing Engine (Phase 3). Use the Mac app for now.',
  });
}

// ============================================================
// 6. score_draft
// PORTING CHECKLIST: AgentToolExecutor.swift line 3160
// ⚠️ PHASE 2: Returns stub directing to Phase 3 writing engine
// ============================================================

export async function scoreDraft(args: Record<string, any>): Promise<string> {
  const contentUUID = args.contentUUID as string;
  if (!contentUUID) return jsonError('contentUUID is required');

  const atom = await fetchAtom(contentUUID);
  if (!atom) return jsonError(`Content not found: ${contentUUID}`);

  const wordCount = (atom.body || '').split(/\s+/).filter(Boolean).length;

  return jsonEncode({
    success: false,
    contentUUID,
    wordCount,
    message: 'Draft scoring requires the Cloud Writing Engine (Phase 3). Use the Mac app for now.',
  });
}

// ============================================================
// Helpers
// ============================================================

/**
 * Render structured JSON draft to readable plaintext.
 * Source: renderDraftForDisplay() in AgentToolExecutor.swift
 */
function renderDraftForDisplay(body: string): string {
  if (!body) return '';

  try {
    const parsed = JSON.parse(body);

    // Carousel format: {slides: [{number, text, visualDirection?}]}
    if (parsed.slides && Array.isArray(parsed.slides)) {
      return parsed.slides.map((s: any, i: number) => {
        const num = s.number || i + 1;
        let text = `SLIDE ${num}\n${s.text || ''}`;
        if (s.visualDirection) text += `\n[Visual: ${s.visualDirection}]`;
        return text;
      }).join('\n\n');
    }

    // Thread format: {tweets: [...]}
    if (parsed.tweets && Array.isArray(parsed.tweets)) {
      return parsed.tweets.map((t: any, i: number) =>
        `TWEET ${i + 1}\n${typeof t === 'string' ? t : t.text || ''}`
      ).join('\n\n');
    }

    // Raw array format
    if (Array.isArray(parsed)) {
      return parsed.map((item: any, i: number) => {
        if (typeof item === 'string') return `SLIDE ${i + 1}\n${item}`;
        return `SLIDE ${i + 1}\n${item.text || JSON.stringify(item)}`;
      }).join('\n\n');
    }
  } catch {
    // Not JSON — return as-is (plaintext)
  }

  return body;
}
