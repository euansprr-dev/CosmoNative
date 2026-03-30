// cosmo-cloud-agent/src/tools/swipes.ts
// Swipe tools — 7 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 451-750

import { fetchAtom, fetchAllByType, searchAtoms, fuzzyFindClient, atomToDict, isSwipeFileAtom, getSwipeAnalysis as getSwipeAnalysisFromAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';
import { config } from '../config';

// ============================================================
// 1. search_swipes
// PORTING CHECKLIST: AgentToolExecutor.swift line 529
// ✅ Keyword search via FTS with swipe filter
// ✅ Filter: isSwipeFileAtom only
// ✅ Return format: {results: [{uuid, title, preview, hookType, frameworkType, hookText, format}], count}
// ✅ Empty result: {results: [], count: 0}
// ============================================================

export async function searchSwipes(args: Record<string, any>): Promise<string> {
  const query = args.query as string;
  if (!query) return jsonError('query is required');

  const limit = (args.limit as number) || 10;

  const results = await searchAtoms(query, { types: ['research'], limit: limit * 2 });
  const swipes = results.filter(isSwipeFileAtom).slice(0, limit);

  return jsonEncode({
    results: swipes.map(a => {
      const analysis = getSwipeAnalysisHelper(a);
      return {
        uuid: a.uuid,
        title: a.title,
        preview: a.body ? a.body.substring(0, 200) : null,
        hookType: analysis?.hookType ?? null,
        frameworkType: analysis?.frameworkType ?? null,
        hookText: analysis?.hookText ?? null,
        format: a.metadata?.contentSource ?? null,
      };
    }),
    count: swipes.length,
  });
}

// ============================================================
// 2. list_all_swipes
// PORTING CHECKLIST: AgentToolExecutor.swift line 746
// ✅ limit (default 50), offset (default 0)
// ✅ Filter: isSwipeFileAtom
// ✅ Pagination: dropFirst(offset).prefix(limit)
// ✅ Return: {results, count, total, offset, hasMore}
// ============================================================

export async function listAllSwipes(args: Record<string, any>): Promise<string> {
  const limit = (args.limit as number) || 50;
  const offset = (args.offset as number) || 0;

  const allResearch = await fetchAllByType('research', { limit: 1000 });
  const allSwipes = allResearch.filter(isSwipeFileAtom);
  const total = allSwipes.length;

  const page = allSwipes.slice(offset, offset + limit);

  return jsonEncode({
    results: page.map(a => {
      const analysis = getSwipeAnalysisHelper(a);
      return {
        uuid: a.uuid,
        title: a.title,
        preview: a.body ? a.body.substring(0, 150) : null,
        hookType: analysis?.hookType ?? null,
        frameworkType: analysis?.frameworkType ?? null,
      };
    }),
    count: page.length,
    total,
    offset,
    hasMore: offset + limit < total,
  });
}

// ============================================================
// 3. filter_swipes_by_taxonomy
// PORTING CHECKLIST: AgentToolExecutor.swift line 783
// ✅ hookType, frameworkType, emotion, platform, format all optional
// ✅ AND all provided filters against swipeAnalysis
// ✅ Return: {results, count}
// RISK: MEDIUM — enum values must match exactly
// ============================================================

export async function filterSwipesByTaxonomy(args: Record<string, any>): Promise<string> {
  const hookType = args.hookType as string | undefined;
  const frameworkType = args.frameworkType as string | undefined;
  const emotion = args.emotion as string | undefined;
  const platform = args.platform as string | undefined;
  const format = args.format as string | undefined;

  const allResearch = await fetchAllByType('research', { limit: 1000 });
  const allSwipes = allResearch.filter(isSwipeFileAtom);

  const filtered = allSwipes.filter(a => {
    const analysis = getSwipeAnalysisHelper(a);
    if (!analysis) return false;

    if (hookType && analysis.hookType !== hookType) return false;
    if (frameworkType && analysis.frameworkType !== frameworkType) return false;
    if (emotion) {
      const emotions = analysis.emotions as string[] | undefined;
      if (!emotions?.includes(emotion)) return false;
    }
    if (platform) {
      const source = a.metadata?.contentSource as string | undefined;
      if (source && !source.toLowerCase().includes(platform.toLowerCase())) return false;
    }
    if (format) {
      const atomFormat = a.metadata?.contentFormat as string | undefined;
      if (atomFormat && atomFormat !== format) return false;
    }
    return true;
  });

  return jsonEncode({
    results: filtered.map(a => {
      const analysis = getSwipeAnalysisHelper(a);
      return {
        uuid: a.uuid,
        title: a.title,
        preview: a.body ? a.body.substring(0, 200) : null,
        hookType: analysis?.hookType ?? null,
        frameworkType: analysis?.frameworkType ?? null,
        hookText: analysis?.hookText ?? null,
      };
    }),
    count: filtered.length,
  });
}

// ============================================================
// 4. get_swipe_analysis
// PORTING CHECKLIST: AgentToolExecutor.swift line 595
// ✅ uuid required
// ✅ Return atomToDict + analysis JSON
// ============================================================

export async function getSwipeAnalysisTool(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Swipe not found: ${uuid}`);

  const analysis = atom.structured || {};

  return jsonEncode({
    ...atomToDict(atom),
    analysis,
  });
}

// ============================================================
// 5. find_similar_swipes
// PORTING CHECKLIST: AgentToolExecutor.swift line 615
// ✅ query required, limit (default 5)
// ✅ Uses FTS ranking (Phase 2). pgvector in Phase 5.
// ✅ Return: {results: [{uuid, title, preview}], count}
// ============================================================

export async function findSimilarSwipes(args: Record<string, any>): Promise<string> {
  const query = args.query as string;
  if (!query) return jsonError('query is required');

  const limit = (args.limit as number) || 5;

  const results = await searchAtoms(query, { types: ['research'], limit: limit * 3 });
  const swipes = results.filter(isSwipeFileAtom).slice(0, limit);

  return jsonEncode({
    results: swipes.map(a => ({
      uuid: a.uuid,
      title: a.title,
      preview: a.body ? a.body.substring(0, 200) : null,
    })),
    count: swipes.length,
  });
}

// ============================================================
// 6. get_swipe_stats
// PORTING CHECKLIST: AgentToolExecutor.swift line 641
// ✅ No params
// ✅ Aggregation: count hookType/frameworkType, top 5
// ✅ Return: {totalSwipes, topHooks, topFrameworks}
// ============================================================

export async function getSwipeStats(_args: Record<string, any>): Promise<string> {
  const allResearch = await fetchAllByType('research', { limit: 2000 });
  const swipes = allResearch.filter(isSwipeFileAtom);

  const hookCounts: Record<string, number> = {};
  const frameworkCounts: Record<string, number> = {};

  for (const s of swipes) {
    const analysis = getSwipeAnalysisHelper(s);
    if (analysis?.hookType) {
      hookCounts[analysis.hookType] = (hookCounts[analysis.hookType] || 0) + 1;
    }
    if (analysis?.frameworkType) {
      frameworkCounts[analysis.frameworkType] = (frameworkCounts[analysis.frameworkType] || 0) + 1;
    }
  }

  const topHooks = Object.entries(hookCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([hook, count]) => ({ hook, count }));

  const topFrameworks = Object.entries(frameworkCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([framework, count]) => ({ framework, count }));

  return jsonEncode({
    totalSwipes: swipes.length,
    topHooks,
    topFrameworks,
  });
}

// ============================================================
// 7. adapt_swipes_for_client
// PORTING CHECKLIST: AgentToolExecutor.swift line 681
// ✅ clientName required, timeFilter optional, maxResults (default 10, cap 25)
// NOTE: In Swift this uses SwipeAdaptationEngine with LLM calls.
//       Cloud version: assemble prompt + call OpenRouter directly.
// ✅ Return: {clientName, totalSwipesScanned, adaptedIdeas: [...], count}
// ============================================================

export async function adaptSwipesForClient(args: Record<string, any>): Promise<string> {
  const clientName = args.clientName as string;
  if (!clientName) return jsonError('clientName is required');

  const maxResults = Math.min((args.maxResults as number) || 5, 25);
  const timeFilter = args.timeFilter as string | undefined;

  // 1. Resolve client
  const clientAtom = await fuzzyFindClient(clientName);
  if (!clientAtom) return jsonError(`No client profile found matching '${clientName}'`);

  // 2. Load client metadata
  const meta = clientAtom.metadata || {};
  const structured = clientAtom.structured || {};
  const resolvedName = clientAtom.title || clientName;
  const clientMeta = {
    name: resolvedName,
    niche: meta.niche || meta.industry || null,
    targetAudience: meta.targetAudience || null,
    voiceNotes: meta.voiceNotes || null,
    signaturePhrases: meta.signaturePhrases as string[] || [],
    bestFormats: meta.bestFormats as string[] || [],
    intelligenceModel: structured.intelligenceModel || null,
    topPerformingPosts: (structured.topPerformingPosts || meta.topPerformingPosts || []) as any[],
    topPerformingTranscripts: (structured.topPerformingTranscripts || meta.topPerformingTranscripts || []) as string[],
    documents: ((structured.documents || meta.documents) || []) as any[],
  };

  // 3. Load all swipes
  const allResearch = await fetchAllByType('research', { limit: 2000 });
  let swipes = allResearch.filter(isSwipeFileAtom);

  // 4. Apply time filter
  if (timeFilter) {
    const now = Date.now();
    let cutoff = 0;
    if (timeFilter.includes('today')) cutoff = now - 24 * 3600 * 1000;
    else if (timeFilter.includes('week')) cutoff = now - 7 * 24 * 3600 * 1000;
    else if (timeFilter.match(/(\d+)\s*day/)) {
      const days = parseInt(timeFilter.match(/(\d+)\s*day/)![1]);
      cutoff = now - days * 24 * 3600 * 1000;
    }
    if (cutoff > 0) {
      swipes = swipes.filter(s => new Date(s.created_at).getTime() >= cutoff);
    }
  }

  // 5. Load existing ideas for dedup
  const allIdeas = await fetchAllByType('idea');
  const clientIdeas = allIdeas.filter(a => a.metadata?.clientUUID === clientAtom.uuid);
  const existingIdeaTitles = clientIdeas.map(a => (a.title || '').toLowerCase()).filter(Boolean);

  // 6. PROVENANCE DEDUP
  const allContent = await fetchAllByType('content');
  const clientContent = allContent.filter(a => a.metadata?.clientProfileUUID === clientAtom.uuid);

  // 6a. Published hooks
  const publishedHooks: string[] = clientContent.flatMap(a => {
    const m = a.metadata || {};
    const hooks = (m.inheritedHooks as string[]) || [];
    const title = (a.title || '').toLowerCase();
    return [...hooks.map((h: string) => h.toLowerCase()), title].filter(Boolean);
  });

  // 6b. Swipe UUIDs already used in content
  const usedSwipeUUIDs = new Set<string>(
    clientContent.flatMap(a => (a.metadata?.inheritedSwipeUUIDs as string[]) || [])
  );

  // 6c. Activated idea hooks
  const activatedIdeaHooks: string[] = clientIdeas
    .filter(a => ['activated', 'inProduction', 'published'].includes(a.metadata?.ideaStatus || ''))
    .map(a => (a.title || '').toLowerCase())
    .filter(Boolean);

  // 6d. Filter out already-used swipes
  swipes = swipes.filter(s => !usedSwipeUUIDs.has(s.uuid));

  if (swipes.length === 0) {
    return jsonEncode({
      clientName: resolvedName, clientUUID: clientAtom.uuid,
      totalSwipesScanned: 0, candidatesEvaluated: 0,
      adaptedIdeas: [], count: 0,
      warning: 'All swipes have already been used in content for this client, or no swipes exist.',
    });
  }

  // 7. STAGE 0: Mechanical pre-filter (free, instant)
  const compactSwipes = swipes.map((atom, idx) => {
    const analysis = getSwipeAnalysisHelper(atom);
    const slides = analysis?.transcriptSlides as any[] | undefined;
    const slide1 = slides?.[0]?.text;
    const hookDisplay = (slide1 || analysis?.hookText || atom.title || '').slice(0, 150).trim();
    if (!hookDisplay) return null;
    const hookScore = (analysis?.hookScore as number) ?? -1;
    // Keep unscored swipes (hookScore == -1) but filter out low scores
    if (hookScore >= 0 && hookScore < 3) return null;
    const hookType = analysis?.hookType || 'unknown';
    return { index: idx, atom, hookDisplay, hookType, hookScore, display: `#${idx + 1}. "${hookDisplay}" [${hookType}]` };
  }).filter(Boolean) as Array<{ index: number; atom: any; hookDisplay: string; hookType: string; hookScore: number; display: string }>;

  if (compactSwipes.length === 0) {
    return jsonEncode({
      clientName: resolvedName, clientUUID: clientAtom.uuid,
      totalSwipesScanned: swipes.length, candidatesEvaluated: 0,
      adaptedIdeas: [], count: 0,
      warning: 'No swipes have usable hook text for adaptation.',
    });
  }

  console.log(`  📊 Adaptation: ${swipes.length} swipes → ${compactSwipes.length} after mechanical filter`);

  // 8. STAGE 1: Sonnet structural mechanism screening
  const maxCandidates = Math.min(Math.max(maxResults * 3, 15), 30);
  let selectedCandidates: typeof compactSwipes;

  // Build rich client context for screening
  let screeningClientContext = `CLIENT: ${clientMeta.name}`;
  if (clientMeta.niche) screeningClientContext += ` — ${clientMeta.niche}`;
  if (clientMeta.targetAudience) screeningClientContext += `\nAudience: ${clientMeta.targetAudience}`;

  // Audience pain points + aspirations (from intelligence model)
  const audienceModel = clientMeta.intelligenceModel?.audienceModel;
  if (audienceModel?.topPainPoints?.length) {
    screeningClientContext += `\nAudience pain points: ${audienceModel.topPainPoints.join('; ')}`;
  }
  if (audienceModel?.aspirationalOutcomes?.length) {
    screeningClientContext += `\nAudience aspirations: ${audienceModel.aspirationalOutcomes.join('; ')}`;
  }

  // Best performing hook first-lines (few-shot for mechanism matching)
  const bestPerformingHooks: string[] = [];
  for (const post of clientMeta.topPerformingPosts.slice(0, 5)) {
    const transcript = typeof post === 'string' ? post : (post.transcript || post.content || '');
    const firstLine = transcript.split('\n')[0]?.trim();
    if (firstLine && !bestPerformingHooks.includes(firstLine)) bestPerformingHooks.push(firstLine);
  }
  for (const t of clientMeta.topPerformingTranscripts.slice(0, 5)) {
    const firstLine = t.split('\n')[0]?.trim();
    if (firstLine && !bestPerformingHooks.includes(firstLine)) bestPerformingHooks.push(firstLine);
  }
  if (bestPerformingHooks.length > 0) {
    screeningClientContext += `\n\nHooks that ALREADY work for this client (find MORE hooks with these same MECHANISMS):`;
    for (const h of bestPerformingHooks.slice(0, 5)) {
      screeningClientContext += `\n- "${h}"`;
    }
  }

  try {
    const screeningUserPrompt = `${screeningClientContext}

SWIPE LIBRARY (${compactSwipes.length} hooks):
${compactSwipes.map(s => s.display).join('\n')}

Select the top ${maxCandidates} hooks whose abstract MECHANISM transfers to this client's niche. \
Apply the noun-swap test for each. The best finds are the non-obvious ones — hooks from \
distant niches that share deep structural DNA with the client's audience.

Return ONLY valid JSON:
{ "selected": [{"index": 1, "mechanism": "identity validation + contrarian reframe", "reason": "noun-swap: audience defines identity against mainstream"}] }
Use the exact # numbers from the list above as index values.`;

    // Use Sonnet (not Haiku) — structural reasoning requires real intelligence
    // Use Sonnet for screening — structural reasoning requires real intelligence
    const screeningResponse = await callAnthropicDirectForAdaptation(
      SCREENING_EXPERTISE,
      screeningUserPrompt,
      4096,
      'claude-sonnet-4-6',
    );
    selectedCandidates = parseScreeningResponse(screeningResponse, compactSwipes);
    console.log(`  📊 Screening: ${compactSwipes.length} → ${selectedCandidates.length} candidates (Sonnet structural analysis)`);
  } catch (err) {
    console.log(`  ⚠️ Sonnet screening failed, falling back to top swipes by hookScore: ${err}`);
    selectedCandidates = [...compactSwipes]
      .sort((a, b) => b.hookScore - a.hookScore)
      .slice(0, maxCandidates);
  }

  if (selectedCandidates.length === 0) {
    selectedCandidates = compactSwipes.slice(0, maxCandidates);
  }

  // 9. PASS 2: Opus generation via direct Anthropic API
  const allExclusionHooks = [...existingIdeaTitles, ...publishedHooks, ...activatedIdeaHooks];
  const userPrompt = buildAdaptationUserPrompt(selectedCandidates, clientMeta, allExclusionHooks, maxResults);

  let adaptedIdeas: AdaptedIdea[] = [];
  try {
    const response = await callAnthropicDirectForAdaptation(HOOK_EXPERTISE_PROMPT, userPrompt, 8192);
    adaptedIdeas = parseAdaptationResponse(response, selectedCandidates);
  } catch (err) {
    console.log(`  ⚠️ Opus adaptation failed: ${err}`);
    return jsonEncode({
      clientName: resolvedName, clientUUID: clientAtom.uuid,
      totalSwipesScanned: swipes.length, candidatesEvaluated: selectedCandidates.length,
      adaptedIdeas: [], count: 0,
      warning: `Idea generation failed: ${err instanceof Error ? err.message : String(err)}`,
    });
  }

  // 10. Post-adaptation dedup
  const dedupedIdeas = adaptedIdeas.filter(idea => {
    const title = idea.ideaTitle.toLowerCase();
    const hook = idea.adaptedHook.toLowerCase();
    return !allExclusionHooks.some(existing =>
      levenshteinSimilarity(title, existing) > 0.7 ||
      levenshteinSimilarity(hook, existing) > 0.7
    );
  });

  const finalIdeas = dedupedIdeas.slice(0, maxResults);

  return jsonEncode({
    clientName: resolvedName,
    clientUUID: clientAtom.uuid,
    totalSwipesScanned: swipes.length,
    candidatesEvaluated: selectedCandidates.length,
    adaptedIdeas: finalIdeas.map(idea => ({
      sourceSwipeTitle: idea.sourceTitle,
      sourceSwipeUUID: idea.sourceUUID,
      ideaTitle: idea.ideaTitle,
      ideaBody: idea.ideaBody,
      adaptedHook: idea.adaptedHook,
      hookVariants: idea.hookVariants,
      hookType: idea.hookType,
      suggestedFramework: idea.suggestedFramework,
      suggestedFormat: idea.suggestedFormat,
      whyItWorks: idea.whyItWorks,
      confidence: idea.confidence,
    })),
    count: finalIdeas.length,
  });
}

// ============================================================
// Internal helper (avoids name collision with exported getSwipeAnalysis)
// ============================================================

function getSwipeAnalysisHelper(atom: { structured: Record<string, any> | null }): Record<string, any> | null {
  if (!atom.structured) return null;
  if (atom.structured.swipeAnalysis) return atom.structured.swipeAnalysis;
  if (atom.structured.hookType) return atom.structured;
  return null;
}

// ============================================================
// Adaptation Engine — Types & Helpers
// ============================================================

interface AdaptedIdea {
  sourceIndex: number;
  sourceTitle: string;
  sourceUUID: string;
  adaptedHook: string;
  hookVariants: string[];
  ideaTitle: string;
  ideaBody: string;
  hookType: string;
  suggestedFramework: string;
  suggestedFormat: string | null;
  whyItWorks: string;
  confidence: string;
}

// ============================================================
// HOOK EXPERTISE PROMPT (cached via Anthropic prompt caching)
// Exact same 6-section prompt as SwipeAdaptationEngine.sharedHookExpertise in Swift
// ============================================================

// ============================================================
// SCREENING EXPERTISE — Deep structural mechanism analysis
// Teaches the screener HOW to find cross-niche hook transfers
// Cached via Anthropic prompt caching (~1800 tokens)
// ============================================================

const SCREENING_EXPERTISE = `You are a structural hook analyst. Your job is to find hooks whose ABSTRACT MECHANISM transfers to a different niche — even when the surface words have zero topical overlap.

You do NOT look for topic similarity. You look for PSYCHOLOGICAL MACHINERY.

THE NOUN-SWAP TEST:
Take any hook. Replace every topic-specific word with the client's equivalent. If the hook still creates the same emotional pull, it's a structural match.

Example: "The one foreclosure trick banks don't want you to know"
Mechanism: [curiosity gap] + [authority gatekeeper challenge] + [insider secret]
Noun-swap for fitness: "The one recovery technique physical therapists don't want you to know"
→ PASSES. Same curiosity gap, same authority challenge, completely different niche.

MECHANISM TAXONOMY — how to decode any hook:

Every hook works by pulling one or more psychological levers:

OPEN LOOP: Creates an information gap that demands closure.
  → "I stopped doing [common practice] and this happened..."
  → The brain cannot leave the loop unclosed.

IDENTITY VALIDATION: Tells the audience "you're not broken, society is."
  → "How to disappoint society as a woman in her 30s"
  → Works for ANY audience that defines themselves against mainstream expectations.
  → Noun-swap: "How to ruin your 20s according to society" — same mechanism, different demo.

AUTHORITY CHALLENGE: Creates insider knowledge by naming a gatekeeper.
  → "[Industry experts] don't want you to know..."
  → Works in ANY niche with perceived gatekeepers (doctors, coaches, agents, banks).

STATUS THREAT: Makes the audience question their current approach.
  → "If you're still [common practice], you're leaving [result] on the table"
  → Triggers loss aversion. Works in any niche with a "wrong way" vs "right way."

SPECIFICITY SURPRISE: A precise number where you'd expect vague claims.
  → "$47K in 11 days" / "3 calls from one DM template" / "lost 23 pounds in 6 weeks"
  → The specific number creates instant credibility. Niche-agnostic.

TEMPORAL URGENCY: Frames knowledge as time-sensitive or age-sensitive.
  → "What I wish I knew at 20" / "Before you turn 30, do this"
  → Works for any age-bracket audience with "I wish I knew earlier" energy.

SOCIAL PROOF INVERSION: Flips what "most people" do against what winners do.
  → "95% of people do X. The top 1% do Y instead."
  → Works in ANY performance-oriented niche.

VULNERABILITY CONFESSION: Earns trust through honest admission.
  → "I've never told anyone this, but..." / "My biggest failure was..."
  → Works for any creator willing to be authentic. Niche-irrelevant.

CONTRARIAN REFRAME: Takes a commonly accepted belief and inverts it.
  → "Stop [widely recommended practice]" / "[Popular advice] is actually hurting you"
  → Works in ANY niche with established conventional wisdom.

CROSS-NICHE TRANSFER EXAMPLES — study these:

Example 1 — IDENTITY VALIDATION across demographics:
  Source: "How to disappoint society as a woman in her 30s" [women's empowerment]
  Transfer: "How to ruin your 20s according to society" [men's philosophy]
  Mechanism: contrarian societal expectation subversion
  Why: Both audiences define identity AGAINST mainstream expectations.

Example 2 — AUTHORITY CHALLENGE across industries:
  Source: "The one foreclosure trick banks don't want you to know" [real estate]
  Transfer: "The one recovery technique PTs don't want you to know" [fitness]
  Mechanism: curiosity gap + gatekeeper challenge
  Why: Both niches have trusted authorities the audience suspects of withholding.

Example 3 — VULNERABILITY CONFESSION across contexts:
  Source: "I lost $200K in 6 months. Here's what nobody warned me about." [finance]
  Transfer: "I wasted 3 years in the wrong relationship. Here's what nobody warned me." [dating]
  Mechanism: specific loss quantification + information gap
  Why: The specific loss creates empathy. "Nobody warned me" creates curiosity.

Example 4 — SPECIFICITY SURPRISE across niches:
  Source: "How I went from $0 to $10K/month in 90 days selling digital products" [e-commerce]
  Transfer: "How I went from 0 to 10K followers in 90 days without posting reels" [social media]
  Mechanism: zero-to-hero transformation with specific metrics and timeframe
  Why: Specific numbers + impossible-seeming timeframe. Topic doesn't matter.

Example 5 — CONTRARIAN REFRAME across fields:
  Source: "Stop stretching before workouts. Here's what to do instead." [fitness]
  Transfer: "Stop posting every day. Here's what to do instead." [content creation]
  Mechanism: contrarian attack on common practice + replacement offer
  Why: "Stop doing what everyone tells you" triggers curiosity in any field.

TRANSFERABILITY SCORING:

HIGH (select these): Universal emotions, structural patterns that work with ANY nouns swapped in, hooks where the mechanism is the star not the topic, story structures (niche-agnostic).

MEDIUM (select if mechanism is strong): Industry jargon that can be swapped but requires creative bridging, hooks tied to a demographic that parallels the client's audience, data-driven hooks where numbers can be replaced.

LOW (skip these): Hooks dependent on a specific news event or cultural moment with no parallel, hooks that only work because of the original creator's personal story, hooks where the topic IS the mechanism.

SCREENING PROCESS:
For each hook: (1) identify the abstract mechanism, (2) apply the noun-swap test, (3) check if the psychological pull survives, (4) evaluate fit with client's audience pain points and aspirations, (5) consider format compatibility.

Select hooks where the MECHANISM transfers, even if every surface word is different. The best finds are the non-obvious ones — hooks from distant niches that share deep structural DNA with the client's audience.`;

// ============================================================
// HOOK EXPERTISE — Full adaptation prompt for Opus (Pass 2)
// ============================================================

const HOOK_EXPERTISE_PROMPT = `You are a content strategy engine inside CosmoOS. You extract proven hook STRUCTURES \
from a swipe file library and adapt them to a specific client's niche, voice, and audience. \
You deliver complete, ready-to-use hooks — not templates or placeholders.

═══════════════════════════════════════════════
SECTION 1: HOOK CRAFT
═══════════════════════════════════════════════

Process: Generate 5 variants per idea. Never use first instinct. Read each aloud — if it \
doesn't flow naturally in under 3 seconds (for short-form) or feel compelling as a thread \
opener (for long-form), cut and rewrite.

Tests (EVERY hook must pass ALL of these):

COVER TEST: Hide the hook and read what follows. If what follows makes sense on its own, \
the hook isn't creating an open loop. FAIL → the hook needs to create an information gap \
that the content closes.

SCROLL TEST: Would this stop someone between a cooking video and a dog video? If not, \
add tension, specificity, or surprise. A hook that blends in is invisible.

DINNER TABLE TEST: Read the hook aloud as if saying it to a friend at dinner. If it sounds \
like a caption, thesis, marketing line, or "content" — it fails. Common failures:
- Thesis statements: "A high income didn't mean a good life" → FAILS. \
Say: "Sure we made more money, but we were still working 80 hour weeks"
- Caption voice: "We chose freedom." → FAILS. Too polished, not speech.
- Corporate phrasing: "leveraged our experience" → FAILS.
- Triple-comma lists: stacking 3 rhetorical items = copywriting, not speech. Say ONE with feeling.

Rules:
- Hook = open loop. Reader must continue to close it.
- Specific > vague. "$47K in 11 days" beats "How I grew my business."
- Hook = promise. "3 mistakes" → deliver exactly 3. Bait-and-switch kills trust.
- Hook IS the first line. Must make you want the next line.
- Compare structure (not words) to client's highest-performing hooks. Match their mechanism.

═══════════════════════════════════════════════
SECTION 2: HOOK TYPE REFERENCE (14 types)
═══════════════════════════════════════════════

- curiosityGap: Information gap the viewer needs to close. "The one thing most [X] get wrong about [Y]"
- boldClaim: Provocative statement to arrest attention. "[Unexpected number] in [short time] doing [surprising method]"
- question: Direct question demanding an answer. "Why does every [audience] struggle with [specific thing]?"
- story: Personal narrative building relatability. "I was [relatable low point] until [discovery moment]"
- statistic: Concrete numbers or data. "[Specific number]% of [audience] don't know [valuable insight]"
- controversy: Inflammatory or contrarian statement. "[Common practice] is actually destroying your [outcome]"
- contrast: Side-by-side comparison. "[Method A] vs [Method B] — the results shocked me"
- howTo: Process-driven educational. "How to [desirable outcome] in [specific timeframe] (step by step)"
- list: Numbered items. "[N] [things] that [outcome] — #[last] changed everything"
- challenge: Test or experiment format. "I tried [method] for [time period] and here's what happened"
- hiddenGem: Underrated discovery. "The [tool/method/place] nobody talks about that [impressive result]"
- contrarian: "Stop doing X / Don't do Y" format. "Stop [common advice]. Do [counterintuitive thing] instead."
- personal: Vulnerability or honest confession. "I've never told anyone this, but [honest truth about topic]"
- transformation: Before/after or journey arc. "From [low point] to [high point] in [time] — here's the playbook"

═══════════════════════════════════════════════
SECTION 3: ADAPTATION METHODOLOGY
═══════════════════════════════════════════════

BEAT PATTERNS (choose the right one for the format):
Every piece follows a structural beat pattern. The hook is the first beat.
Beat types: HOOK → CONTEXT → TENSION → INSIGHT → PROOF → EXPANSION → TRANSITION → CTA
- Short reel (15-30s): HOOK → INSIGHT → CTA
- Long reel (30-90s): HOOK → CONTEXT → TENSION → INSIGHT → CTA
- Carousel (5-15 slides): HOOK → CONTEXT → TENSION → INSIGHT → PROOF → CTA
- Thread (4-12 tweets): HOOK → CONTEXT → TENSION → INSIGHT → PROOF → EXPANSION → CTA
- LinkedIn: HOOK → CONTEXT → INSIGHT → PROOF → EXPANSION → CTA

When suggesting a framework for each idea, map the swipe's beat structure to the best \
format for this client. The hook must fit the format's natural rhythm.

ADAPTATION RULES:
1. Extract the PATTERN, never copy the text. "The one foreclosure trick banks don't want \
you to know" → for fitness: "The one recovery technique physical therapists don't want \
you to know". The curiosity gap + authority challenge STRUCTURE transfers.
2. Every adapted hook must pass Cover + Scroll + Dinner Table tests.
3. Maintain the original hook's MECHANISM while transplanting to client's world.
4. Reference the client's specific data, methods, stories, and audience language — \
never generic placeholders like "[your niche]" or "[your product]".
5. Match voice to client's actual voice — study their best performing content for \
sentence length, formality, signature phrases, and absences (what they DON'T use \
matters as much as what they do).

FORMAT-AWARE HOOK CONSTRAINTS:
- Reel/Short hooks: Must be speakable in <3 seconds. Max ~15 words.
- Carousel hooks: Max ~80 characters. Must work as text on an image.
- Thread hooks: Can be longer — up to 280 characters. Must earn the click to read \
the full thread. Threads allow more setup and context in the hook.
- LinkedIn hooks: First 3 lines visible before "see more". ~200 chars to earn the click.
- Newsletter subject lines: Max 50 characters. Curiosity-first.

VOICE MATCHING (The Absorption Method):
Before adapting: Study the client's best performing content. Notice:
- Sentence length: 5-8 word fragments or 15-20 word flowing sentences?
- Formality: "I" or "we"? Contractions? Casual asides?
- Signature patterns: "Look..." / "Here's the thing..." / emojis / "..." between thoughts?
- Absences: No rhetorical questions? No exclamation marks? Absences define voice too.

Same-person test: Read the client's actual post, then your hook variant. Must sound like \
the same person, same day. If yours sounds smarter or more polished — it's wrong.

═══════════════════════════════════════════════
SECTION 4: IDEA EVALUATION (Score each 1-10)
═══════════════════════════════════════════════

Before including ANY idea, evaluate against these 6 criteria. \
Minimum 40/60 total. No single criterion below 3/10. If it fails, skip the candidate.

1. TAM: Does this reach a large enough audience segment for this client?
2. Hook-ability: Can the core insight be compressed into a compelling hook that passes all 3 tests?
3. Authority Match: Does the client have real credibility and experience to say this?
4. Emotional Charge: Does it trigger a visceral reaction? Neutral = dead.
5. Angle Uniqueness: Is this a fresh take this client hasn't covered?
6. Trend Timing: Does this tap a current cultural moment, industry shift, or seasonal relevance?

═══════════════════════════════════════════════
SECTION 5: VOICE DNA (MANDATORY)
═══════════════════════════════════════════════

WRITING RULES:
- Write like a sharp human, not a language model.
- Use contractions naturally (don't, can't, won't).
- Get to the point. No throat-clearing, no preamble.
- If making a claim, be specific. Use numbers, names, concrete details.
- Vary sentence length. Mix short punchy lines with longer ones.
- Use physical verbs: "sanded down" not "improved," "bolted on" not "added."

BANNED PHRASES (if even ONE appears, the output fails):
Dead AI: "In today's [anything]", "It's important to note", "Delve", "Dive into", \
"Unpack", "Harness", "Leverage", "Utilize", "Landscape", "Realm", "Robust", \
"Game-changer", "Cutting-edge", "Straightforward", "In order to".
Dead transitions: "Furthermore", "Additionally", "Moreover", "Moving forward", \
"At the end of the day", "To put this in perspective", "In other words".
Engagement bait: "Let that sink in", "Read that again", "Full stop", \
"This changes everything", "Are you paying attention?", "You're not ready for this".
AI cringe: "Supercharge", "Unlock", "Future-proof", "10x your productivity".
Generic insider claims: "Here's the part nobody's talking about", \
"What nobody tells you", anything with "nobody" or "most people don't realize".
FATAL: "This isn't X. This is Y." and ALL variations — delete the negation, state the positive claim.

═══════════════════════════════════════════════
SECTION 6: 5-VARIANT STRATEGY
═══════════════════════════════════════════════

For each idea, generate exactly 5 hook variants spanning different emotional registers:
- Variant 1: Most punchy, scroll-stopping version (also used as adaptedHook).
- Variant 2: Curiosity-driven — create the strongest possible open loop.
- Variant 3: Story/personal angle — lead with a relatable moment or confession.
- Variant 4: Data/proof-driven — lead with a specific number, stat, or result.
- Variant 5: Contrarian/unexpected — challenge conventional wisdom or flip expectations.

Each variant must:
- Use the same underlying content idea but different entry point
- Pass all 3 tests (Cover, Scroll, Dinner Table)
- Match the client's voice (sentence length, formality, signature patterns)
- Contain zero banned phrases
- Be format-appropriate (respect hook length constraints for the suggested format)`;

// ============================================================
// Build user prompt for Pass 2
// ============================================================

function buildAdaptationUserPrompt(
  candidates: Array<{ index: number; atom: any; hookDisplay: string; hookType: string }>,
  clientMeta: {
    name: string; niche: string | null; targetAudience: string | null;
    voiceNotes: string | null; signaturePhrases: string[];
    bestFormats: string[]; intelligenceModel: any;
    topPerformingPosts: any[]; topPerformingTranscripts: string[];
    documents: any[];
  },
  exclusionHooks: string[],
  maxResults: number,
): string {
  const sections: string[] = [];

  // Client profile
  let clientSection = `CLIENT PROFILE: ${clientMeta.name}`;
  if (clientMeta.niche) clientSection += `\nNiche: ${clientMeta.niche}`;
  if (clientMeta.targetAudience) clientSection += `\nTarget Audience: ${clientMeta.targetAudience}`;
  if (clientMeta.voiceNotes) clientSection += `\nVoice: ${clientMeta.voiceNotes}`;
  if (clientMeta.signaturePhrases.length > 0) {
    clientSection += `\nSignature Phrases: ${clientMeta.signaturePhrases.join(', ')}`;
  }

  // Voice fingerprint from intelligence model
  const vf = clientMeta.intelligenceModel?.voiceFingerprint;
  if (vf) {
    if (vf.avgSentenceLength > 0) {
      clientSection += `\nVoice Target — Sentence length: ${Math.round(vf.avgSentenceLength * 0.7)}-${Math.round(vf.avgSentenceLength * 1.3)} words`;
    }
    if (vf.ctaPattern) clientSection += `\nCTA Style: ${vf.ctaPattern}`;
    if (vf.formattingQuirks?.length) clientSection += `\nStyle Markers: ${vf.formattingQuirks.join(', ')}`;
    if (vf.powerWords?.length) clientSection += `\nPower Words: ${vf.powerWords.slice(0, 10).join(', ')}`;
  }

  if (clientMeta.bestFormats.length > 0) {
    clientSection += `\nBest Formats: ${clientMeta.bestFormats.join(', ')}`;
  }

  // Full best performing post transcripts
  if (clientMeta.topPerformingPosts.length > 0) {
    clientSection += '\n\nBEST PERFORMING CONTENT (study these — they define what works):';
    for (let i = 0; i < Math.min(clientMeta.topPerformingPosts.length, 5); i++) {
      const post = clientMeta.topPerformingPosts[i];
      const transcript = typeof post === 'string' ? post : (post.transcript || post.content || '');
      if (transcript) clientSection += `\n\n[${i + 1}] ${transcript}`;
    }
  } else if (clientMeta.topPerformingTranscripts.length > 0) {
    clientSection += '\n\nBEST PERFORMING CONTENT:';
    for (let i = 0; i < Math.min(clientMeta.topPerformingTranscripts.length, 5); i++) {
      clientSection += `\n\n[${i + 1}] ${clientMeta.topPerformingTranscripts[i]}`;
    }
  }

  // Brand story from documents
  const storyDocs = clientMeta.documents.filter((d: any) => d.category === 'story');
  if (storyDocs.length > 0) {
    clientSection += `\n\nBRAND STORY:\n${storyDocs[0].content}`;
  }

  sections.push(clientSection);

  // Candidates
  let candidateSection = `SELECTED SWIPE CANDIDATES (${candidates.length} pre-screened):`;
  for (const [candidatePosition, c] of candidates.entries()) {
    const analysis = getSwipeAnalysisHelper(c.atom);
    candidateSection += `\n\n#${candidatePosition + 1}. "${c.atom.title || 'Untitled'}"`;
    const slides = analysis?.transcriptSlides as any[] | undefined;
    const slide1 = slides?.[0]?.text;
    if (slide1 && slide1 !== c.atom.title) {
      candidateSection += `\n   Slide 1: "${slide1}"`;
    }
    if (analysis?.hookText && analysis.hookText !== c.atom.title && analysis.hookText !== slide1) {
      candidateSection += `\n   Hook: "${analysis.hookText}"`;
    }
    candidateSection += `\n   Type: ${c.hookType}`;
    if (analysis?.frameworkType) candidateSection += ` | Framework: ${analysis.frameworkType}`;
    if (c.atom.body) candidateSection += `\n   Body: "${(c.atom.body as string).substring(0, 300)}"`;
  }
  sections.push(candidateSection);

  // Exclusion hooks
  if (exclusionHooks.length > 0) {
    const hookList = exclusionHooks.slice(0, 15).map(h => `- "${h}"`).join('\n');
    sections.push(`HOOKS ALREADY PUBLISHED OR IN PRODUCTION (do NOT regenerate these patterns):\n${hookList}\nThese hooks have already been written and published. Generate FRESH structural adaptations only.`);
  }

  // Output format
  sections.push(`For each candidate above, generate an adapted idea for ${clientMeta.name}. Return ONLY valid JSON:
{
  "adaptedIdeas": [
    {
      "sourceIndex": 1,
      "adaptedHook": "The most scroll-stopping variant (primary pick)",
      "hookVariants": [
        "Variant 1: punchy/scroll-stopping",
        "Variant 2: curiosity-driven",
        "Variant 3: story/personal angle",
        "Variant 4: data/proof-driven",
        "Variant 5: contrarian/unexpected"
      ],
      "ideaTitle": "Short title (3-8 words)",
      "ideaBody": "2-3 sentence expansion describing the content angle and key beats.",
      "hookType": "curiosityGap",
      "suggestedFramework": "pas",
      "suggestedFormat": "carousel",
      "adaptationReasoning": "What structural pattern was borrowed and how it transfers",
      "whyItWorks": "Why this resonates with ${clientMeta.name}'s audience",
      "confidence": "high"
    }
  ]
}

MANDATORY CHECKS:
- Every hook must pass Cover + Scroll + Dinner Table tests
- Every hook must use the client's actual voice from BEST PERFORMING CONTENT
- Zero banned phrases in any hook
- Hook length matches suggestedFormat constraints (see FORMAT-AWARE HOOK CONSTRAINTS)
- Each idea scores 40+ across the 6 evaluation criteria

IMPORTANT: sourceIndex must be the candidate number from the SELECTED SWIPE CANDIDATES list above \
(1-${candidates.length}), not the original swipe library index.

Generate exactly ${maxResults} ideas, ranked by LEVERAGE (highest viral potential first). \
Skip candidates only if their hook mechanism genuinely cannot transfer (explain why).

Valid hookTypes: curiosityGap, boldClaim, question, story, statistic, controversy, contrast, howTo, list, challenge, hiddenGem, contrarian, personal, transformation
Valid frameworks: aida, pas, bab, escalationArc, storyLoop, listicle, tutorial, caseStudy, interview, beforeAfter, mythBusting, dayInLife
Valid formats: carousel, reel, thread, linkedinPost, newsletter, youtubeShort
Confidence: "high" = hook structure maps directly, "medium" = creative bridging, "low" = stretch adaptation`);

  return sections.join('\n\n');
}

// ============================================================
// Anthropic Direct API Call (with prompt caching + retry)
// ============================================================

async function callAnthropicDirectForAdaptation(
  systemPrompt: string,
  userPrompt: string,
  maxTokens: number = 8192,
  model: string = 'claude-opus-4-6',
): Promise<string> {
  const apiKey = config.anthropicApiKey || config.agentLLMApiKey;
  if (!apiKey) {
    // Fallback to OpenRouter if no Anthropic key
    const orModel = model.includes('sonnet') ? config.models.strategist : config.models.writer;
    console.log(`  ⚠️ No ANTHROPIC_API_KEY — falling back to OpenRouter (${orModel})`);
    return callOpenRouterSimple(
      `${systemPrompt}\n\n${userPrompt}`,
      orModel,
      maxTokens,
    );
  }

  const body = {
    model,
    max_tokens: maxTokens,
    temperature: 0.4,
    system: [
      { type: 'text', text: systemPrompt, cache_control: { type: 'ephemeral' } },
    ],
    messages: [
      { role: 'user', content: userPrompt },
    ],
  };

  const MAX_RETRIES = 5;
  let lastError: Error | null = null;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'anthropic-beta': 'prompt-caching-2024-07-31',
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(120_000),
      });

      if (response.status === 429) {
        const retryAfter = response.headers.get('retry-after');
        const waitMs = retryAfter ? Math.ceil(parseFloat(retryAfter) * 1000) : 30_000;
        console.log(`  ⚠️ Anthropic rate limited — waiting ${(waitMs / 1000).toFixed(0)}s (attempt ${attempt + 1}/${MAX_RETRIES})`);
        lastError = new Error('Anthropic rate limit');
        await new Promise(r => setTimeout(r, waitMs));
        continue;
      }

      if (response.status >= 500 && response.status < 600) {
        const backoff = (attempt + 1) * 2000;
        console.log(`  ⚠️ Anthropic server error ${response.status} — retrying in ${backoff}ms`);
        lastError = new Error(`Anthropic error ${response.status}`);
        await new Promise(r => setTimeout(r, backoff));
        continue;
      }

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Anthropic error ${response.status}: ${errorText.substring(0, 200)}`);
      }

      const data = await response.json() as any;

      // Log cache stats
      if (data.usage) {
        const cacheRead = data.usage.cache_read_input_tokens || 0;
        const totalInput = (data.usage.input_tokens || 0) + cacheRead + (data.usage.cache_creation_input_tokens || 0);
        const cacheRate = totalInput > 0 ? ((cacheRead / totalInput) * 100).toFixed(1) : '0.0';
        console.log(`  🧠 Adaptation: input=${totalInput}, output=${data.usage.output_tokens || 0}, cache=${cacheRate}%`);
      }

      // Extract text
      for (const block of (data.content || [])) {
        if (block.type === 'text') return block.text;
      }
      throw new Error('No text content in Anthropic response');
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (error instanceof DOMException && error.name === 'TimeoutError') {
        console.log(`  ⚠️ Anthropic timeout (attempt ${attempt + 1}/${MAX_RETRIES})`);
        continue;
      }
      if (attempt === MAX_RETRIES - 1) throw error;
    }
  }

  throw lastError || new Error(`Anthropic API failed after ${MAX_RETRIES} attempts`);
}

// ============================================================
// OpenRouter Simple Call (for Haiku screening)
// ============================================================

async function callOpenRouterSimple(
  prompt: string,
  model: string,
  maxTokens: number = 2048,
): Promise<string> {
  const apiKey = config.openRouterApiKey || config.agentLLMApiKey;
  if (!apiKey) throw new Error('No OpenRouter API key configured');

  const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: maxTokens,
      temperature: 0.2,
    }),
    signal: AbortSignal.timeout(30_000),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenRouter error ${response.status}: ${errorText.substring(0, 200)}`);
  }

  const data = await response.json() as any;
  return data.choices?.[0]?.message?.content || '';
}

// ============================================================
// Response Parsers
// ============================================================

function parseScreeningResponse(
  response: string,
  compactSwipes: Array<{ index: number; atom: any; hookDisplay: string; hookType: string; hookScore: number; display: string }>,
): typeof compactSwipes {
  try {
    // Try direct JSON parse
    let json: any;
    try {
      json = JSON.parse(response);
    } catch {
      // Try extracting JSON from markdown code block
      const match = response.match(/\{[\s\S]*"selected"[\s\S]*\}/);
      if (match) json = JSON.parse(match[0]);
    }

    if (!json?.selected) return compactSwipes.slice(0, 20);

    const selectedIndices = new Set(
      (json.selected as any[]).map((s: any) => {
        const idx = typeof s === 'number' ? s : (s.index || s.idx || 0);
        return idx;
      })
    );

    return compactSwipes.filter(s => selectedIndices.has(s.index + 1)); // 1-indexed in prompt
  } catch {
    return compactSwipes.slice(0, 20);
  }
}

function parseAdaptationResponse(
  response: string,
  candidates: Array<{ index: number; atom: any; hookDisplay: string; hookType: string }>,
): AdaptedIdea[] {
  let json: any;
  try {
    json = JSON.parse(response);
  } catch {
    // Extract JSON from response (may be wrapped in markdown)
    const match = response.match(/\{[\s\S]*"adaptedIdeas"[\s\S]*\}/);
    if (match) {
      try { json = JSON.parse(match[0]); } catch { return []; }
    }
  }

  if (!json?.adaptedIdeas) return [];

  return (json.adaptedIdeas as any[]).map((idea: any, ideaPosition: number) => {
    const rawSourceIndex = typeof idea.sourceIndex === 'number'
      ? idea.sourceIndex
      : parseInt(String(idea.sourceIndex || ''), 10);

    // Preferred mapping: the prompt numbers candidates 1..N.
    const sourceByPromptPosition = Number.isFinite(rawSourceIndex) && rawSourceIndex >= 1 && rawSourceIndex <= candidates.length
      ? candidates[rawSourceIndex - 1]
      : undefined;

    // Backward-compatible fallback for responses generated against the earlier prompt,
    // which exposed the original swipe-library numbering instead of dense candidate numbers.
    const sourceByOriginalIndex = Number.isFinite(rawSourceIndex)
      ? candidates.find(candidate => candidate.index + 1 === rawSourceIndex)
      : undefined;

    const source = sourceByPromptPosition || sourceByOriginalIndex || candidates[ideaPosition] || candidates[0];
    return {
      sourceIndex: Number.isFinite(rawSourceIndex) ? rawSourceIndex : (ideaPosition + 1),
      sourceTitle: source?.atom?.title || 'Unknown',
      sourceUUID: source?.atom?.uuid || '',
      adaptedHook: idea.adaptedHook || idea.hookVariants?.[0] || '',
      hookVariants: idea.hookVariants || [idea.adaptedHook || ''],
      ideaTitle: idea.ideaTitle || 'Untitled Idea',
      ideaBody: idea.ideaBody || '',
      hookType: idea.hookType || source?.hookType || 'unknown',
      suggestedFramework: idea.suggestedFramework || 'pas',
      suggestedFormat: idea.suggestedFormat || null,
      whyItWorks: idea.whyItWorks || idea.adaptationReasoning || '',
      confidence: idea.confidence || 'medium',
    };
  });
}

// ============================================================
// Levenshtein Similarity (for dedup)
// ============================================================

function levenshteinSimilarity(a: string, b: string): number {
  if (a === b) return 1.0;
  if (!a || !b) return 0.0;

  const aLen = a.length;
  const bLen = b.length;
  const matrix: number[][] = Array.from({ length: aLen + 1 }, (_, i) =>
    Array.from({ length: bLen + 1 }, (_, j) => (i === 0 ? j : j === 0 ? i : 0))
  );

  for (let i = 1; i <= aLen; i++) {
    for (let j = 1; j <= bLen; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      matrix[i][j] = Math.min(
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      );
    }
  }

  const distance = matrix[aLen][bLen];
  const maxLen = Math.max(aLen, bLen);
  return 1.0 - distance / maxLen;
}
