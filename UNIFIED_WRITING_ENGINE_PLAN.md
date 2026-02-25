# Unified Writing Engine — Technical Architecture Plan

> CosmoOS-Swift | February 2026
> Synthesized from web research (15 sources) and codebase analysis (17 files, ~12K lines)

---

## Table of Contents

1. [Research Findings Summary](#1-research-findings-summary)
2. [Architecture Design](#2-architecture-design)
3. [The Actual System Prompt](#3-the-actual-system-prompt)
4. [Data Retrieval Specification](#4-data-retrieval-specification)
5. [Implementation Plan](#5-implementation-plan)
6. [What Gets Removed](#6-what-gets-removed)
7. [Platform/Format Constraint Tables](#7-platformformat-constraint-tables)

---

## 1. Research Findings Summary

### What We Learned and What We're Adopting

**1.1 Agentic Architecture: Plan-Then-Execute with Think Tool**

The research evaluated three patterns: ReAct-style (tool after tool), plan-and-execute (plan first, then execute steps), and fully autonomous agents. We are adopting a **hybrid conversational agent** with planning capabilities rather than a rigid pipeline.

*Why*: The current system's fatal flaw is 4 disconnected engines (BrainstormAIEngine, OpusWritingEngine, ContentAICollaboratorEngine, AIWritingAssistant) that each assemble context independently with dramatically different quality. A brainstorm conversation in BrainstormAIEngine makes structural decisions with 3 truncated swipe previews and zero methodology — then OpusWritingEngine generates a draft with 30 full swipes and 3800 words of methodology, having no knowledge of the brainstorm reasoning.

The solution is ONE continuous conversation agent that persists from brainstorm through draft through polish. This agent has tools to fetch data, generate structured outputs, and edit content. The conversation history IS the context bridge between phases.

*Key sources*: Anthropic advanced tool use (tool search, think tool), LangGraph plan-and-execute, Anthropic prompt caching docs.

**1.2 Context Management: 3-Tier Prompt Caching**

Anthropic's prompt caching delivers 90% cost reduction and 85% latency reduction for cached prefixes. The research confirms that "lost in the middle" is a real problem — mechanically stuffing 200K tokens of swipes into context degrades quality.

*Adopted approach*: 3-tier cache hierarchy with aggressive retrieval rather than brute-force inclusion:
- **Tier 1 (1hr TTL)**: Methodology + client Intelligence Model + voice profile (~15-20K tokens). Stable across all requests for a client.
- **Tier 2 (1hr TTL)**: Client's top-performing transcripts, format-specific fingerprints. Stable per client.
- **Tier 3 (per-request)**: Selected swipe examples (2-3, compressed), current draft, conversation history. Changes each turn.

*Key sources*: Anthropic prompt caching documentation, RAG "lost in the middle" research (RAGFlow 2025).

**1.3 Few-Shot Selection: Structural Fingerprinting + Diversity**

The research showed that similarity-based dynamic selection outperforms static examples (Liu et al.), and that diversity-aware selection (COBRA, CVPR 2025) prevents redundant examples. 2-3 examples establish reliable patterns with diminishing returns beyond that.

*Adopted approach*: Use BeatPatternService's structural fingerprint as the PRIMARY selector — if the user is writing a listicle carousel, retrieve other listicle carousels, not just topically similar content. Select 2-3 diverse examples: one matching format+framework, one matching niche voice, one high-performer. Compress each to ~200 tokens (hook + beats + transitions + CTA).

*Key sources*: COBRA (CVPR 2025), CASE diversity selection, embedding retrieval research.

**1.4 Constraint-Driven Generation: Prompt Scaffolding + Post-Validation**

Since we use Claude's API (not local models), we cannot modify logit distributions. The research confirms structured output via tool_use JSON schemas is the most reliable constraint mechanism for API-based models. LLMs are unreliable at character counting during generation, so post-validation with retry is essential.

*Adopted approach*: Two-level constraints:
- **Hard constraints** (slide count, character limits, tweet length): Enforced via structured JSON tool output + programmatic post-validation + correction prompt if violated.
- **Soft constraints** (voice, tone, beat pattern adherence): Enforced via few-shot examples + think tool reasoning + contrastive voice profile.

*Key sources*: Constrained decoding survey (Medium/Docherty), CHI 2024 constraint study, structured output APIs comparison.

**1.5 Voice Cloning: Structured Profile + Contrastive Examples**

The research identified three dimensions of voice: tone/attitude, syntax/rhythm, and diction/vocabulary. The most effective approach is a "Style Blueprint" injected as a system prompt, combined with contrastive examples (GOOD vs BAD). Fine-tuning requires 50K-100K words of training data and is impractical for per-client customization.

*Adopted approach*: The existing `ClientIntelligenceModel` already captures voice fingerprint, performance fingerprint, and failure fingerprints. The problem is that only OpusWritingEngine uses it. The unified engine will inject the full Intelligence Model at Tier 1 (always cached) and add contrastive examples at Tier 2. The ContentScorecardEngine's VoiceMatch criterion will use the structured profile for scoring.

*Key sources*: GhostWriter architecture, style blueprint research, one-shot style transfer (arxiv 2510.13302).

**1.6 Generation Pipeline: Draft-Critique-Refine Chain**

ACL 2024 research (Wu et al.) showed that chained draft→critique→refine consistently outperforms single "mega prompts." Jasper and Copy.ai both use multi-step pipelines for non-trivial content. Prompt caching mitigates the 2-4x token cost increase.

*Adopted approach*: The unified engine uses a conversational chain rather than separate API calls:
1. **Plan** (brainstorm phase) — Agent helps user develop outline, hooks, structure. Conversation history preserved.
2. **Draft** (draft phase) — Agent generates draft using plan + full context. Think tool verifies voice consistency section-by-section.
3. **Score** (automatic) — ContentScorecardEngine evaluates against hard criteria.
4. **Refine** (polish phase) — Agent reviews scorecard, suggests improvements through conversation. User directs inline edits.

The key insight: steps 1-4 happen within ONE conversation, not four separate engine invocations. The agent remembers why it chose a particular framework, what the brainstorm discussion concluded, and what the user's specific preferences are.

*Key sources*: ACL 2024 (Wu et al.), Jasper/Copy.ai pipeline analysis, Anthropic adaptive thinking.

---

## 2. Architecture Design

### 2.1 Unified Conversation Model

The core architectural change: **one continuous Claude conversation per content piece**, from first brainstorm message to final polish. No more 4 separate engines. No more context loss between phases.

```
CURRENT (4 disconnected engines):

BrainstormAIEngine  ──(state artifacts only)──>  OpusWritingEngine  ──(nothing)──>  CollaboratorEngine
   3 swipe previews                               30 full swipes                    3-line prompt
   No methodology                                 Full methodology                  No methodology
   No client intel                                Full client intel                  2000-char draft
   No beat patterns                               Beat patterns                     No swipes

PROPOSED (1 unified conversation agent):

UnifiedWritingEngine (continuous conversation)
│
├── Phase: Brainstorm
│   Context: Full methodology + client intel + swipe examples + beat patterns
│   Tools: search_swipes, get_beat_patterns, suggest_outline, suggest_hooks
│   Output: Outline items, hooks, description (applied via tool calls)
│
├── Phase: Draft
│   Context: Same conversation + brainstorm decisions + plan
│   Tools: write_section, get_swipe_detail, think (verify voice)
│   Output: Draft content, section by section, with self-evaluation
│
├── Phase: Polish
│   Context: Same conversation + full draft + scorecard
│   Tools: edit_section, run_scorecard, rewrite_hook, get_feedback
│   Output: Targeted edits, voice corrections, CTA improvements
│
└── Throughout: Inline edits (expand/condense/rephrase) use same context
```

**Conversation Persistence**: The conversation is stored on `ContentFocusModeState` as a `[ConversationTurn]` array. When the user closes and reopens a content piece, the conversation is rehydrated. When the conversation exceeds ~50K estimated tokens, older turns are summarized (as the current CollaboratorEngine already does at the 20K threshold — we keep this pattern).

### 2.2 Prompt Structure

The system prompt is organized as a **layered document** with dynamic injection points. It uses Anthropic's multi-block system message format with `cache_control` breakpoints.

```
System Message Block 1: METHODOLOGY (cache_control: ephemeral, ~15K tokens)
├── Content strategy playbook (current DEFAULT_METHODOLOGY, ~3800 words)
├── Platform constraint tables (NEW — Section 7 of this document)
├── Beat pattern definitions
└── Editing checklist (hook/copy/CTA criteria)

System Message Block 2: CLIENT INTELLIGENCE MODEL (cache_control: ephemeral, ~8-15K tokens)
├── Voice Fingerprint (sentence length, power words, tone, quirks)
├── Performance Fingerprint (what works/doesn't, best hook types)
├── Failure Fingerprint (rules from underperforming content)
├── Audience Model (who the content is for)
├── Niche Positioning (market context)
├── Format-Specific Fingerprints (reels vs threads vs carousels)
├── Contrastive Voice Examples (GOOD vs BAD side-by-side)
└── Top-Performing Transcripts (2-3, compressed, format-filtered)

System Message Block 3: DYNAMIC CONTEXT (no cache, ~5-15K tokens)
├── Selected Swipe Examples (2-3, compressed to ~200 tokens each)
├── Current Content State (title, platform, format, phase, outline, hooks)
├── Beat Pattern Match (selected pattern + reasoning)
├── Knowledge Context (relevant Connection atoms)
└── Tool definitions

User Messages: Conversation History
├── Brainstorm turns (preserved across phase transitions)
├── Draft generation turns
├── Polish/edit turns
└── Summarized older history (when > 50K tokens estimated)
```

### 2.3 Retrieval Pipeline

When a content piece is opened in Focus Mode, the engine automatically fetches and assembles context. This replaces the current scattered assembly across 4 engines.

**On Open (async, ~2-3 seconds)**:
1. Load content atom + metadata (platform, format, phase, clientProfileUUID, inheritedSwipeUUIDs)
2. Load client profile atom → extract ClientProfileMetadata → extract ClientIntelligenceModel
3. Load inherited swipes (direct UUID references from idea activation)
4. Search for additional swipes via HybridSearchEngine (if inherited < 3)
5. Query BeatPatternService for top patterns matching format + niche
6. Query KnowledgeContextAssembler for relevant Connection atoms
7. Select 2-3 swipe examples using diversity-aware selection (format match + niche match + top performer)
8. Compress selected swipes to hook + beats + transitions + CTA (~200 tokens each)
9. Assemble 3-tier prompt and cache

**On Each Message (incremental)**:
1. Append user message to conversation
2. Update dynamic context block (draft may have changed, outline may have changed)
3. Send to Claude with cached system blocks + updated user messages
4. Parse response for tool calls and text
5. Apply tool call results (outline edits, draft writes, etc.)

### 2.4 Context Management: Fitting Everything In

**Budget**: Claude Opus 4.6 supports 1M input tokens, 128K output tokens. Our target is to keep the full context under 100K tokens to maintain quality (per "lost in the middle" research), with an absolute ceiling of 200K.

| Layer | Content | Estimated Tokens | Strategy |
|-------|---------|-----------------|----------|
| Block 1: Methodology | Strategy playbook + platform constraints + beat definitions | ~18K | Cached (1hr). Static across all clients. |
| Block 2: Intelligence Model | Full model + voice + performance + failure + top transcripts | ~10-25K | Cached (1hr). Stable per client. Top transcripts compressed to 1500 chars each, max 5 per format. |
| Block 3: Dynamic Context | 2-3 compressed swipes + current state + knowledge | ~5-15K | Per-request. Swipes compressed to ~200 tokens each. Knowledge context limited to top 2 connections. |
| Conversation History | Brainstorm + draft + polish turns | ~10-40K | Summarized when > 50K. Older turns compressed to decisions-only summaries. |
| **Total** | | **~45-100K** | Well within quality range. |

**Prioritization when context is tight** (> 80K estimated):
1. Always include: Methodology (Block 1), voice fingerprint, failure fingerprint, current content state
2. Compress first: Top transcripts (reduce from 5 to 2), swipe examples (reduce from 3 to 1)
3. Summarize: Older conversation history (keep last 10 turns verbatim, summarize rest)
4. Drop: Knowledge context (Connection atoms), meta-pattern distribution stats

### 2.5 Tool-Calling Pattern

The unified engine uses Claude's native tool_use format. Each tool has a JSON schema that enforces output structure. Tools are the mechanism by which the AI modifies the content piece — text responses are conversation, tool calls are actions.

**Core Tools** (always available):

```
think
  Description: Reason through a complex decision before responding. Use this to verify
  voice consistency, check constraint compliance, or plan multi-step edits.
  Parameters: { thought: string }

update_outline
  Description: Replace the current outline with a new structured outline.
  Parameters: {
    sections: [{
      beatLabel: string,
      title: string,
      description: string,
      estimatedSeconds?: number,
      notes?: string
    }],
    reasoning: string
  }

add_hooks
  Description: Add hook variants with scoring.
  Parameters: {
    hooks: [{
      text: string,
      hookType: string,
      estimatedScore: number,
      reasoning: string
    }]
  }

set_description
  Description: Set the content description/theme.
  Parameters: { description: string }

write_draft
  Description: Write or replace the full draft content.
  Parameters: {
    content: string,
    format: "plaintext" | "carousel_json" | "thread_json" | "script",
    selfEvaluation: {
      confidenceScore: number,
      voiceMatchScore: number,
      weakAreas: [string]
    }
  }

edit_section
  Description: Replace a specific section of the draft.
  Parameters: {
    sectionIdentifier: string,
    newContent: string,
    reasoning: string
  }

search_swipes
  Description: Search the swipe file library for relevant examples.
  Parameters: {
    query: string,
    filters?: { format?: string, hookType?: string, minScore?: number }
  }
  Returns: Array of compressed swipe summaries.

get_client_context
  Description: Retrieve additional client profile information.
  Parameters: { section: "voice" | "performance" | "audience" | "failures" | "full" }
  Returns: Relevant section of the intelligence model.

run_scorecard
  Description: Evaluate the current draft against quality criteria.
  Parameters: {}
  Returns: { hookScore, copyScore, ctaScore, voiceMatch, structuralAlignment, overall, suggestions[] }
```

**Phase-Specific Tool Availability**:
- Brainstorm: `think`, `update_outline`, `add_hooks`, `set_description`, `search_swipes`, `get_client_context`
- Draft: All tools. `write_draft` and `edit_section` become primary.
- Polish: All tools. `run_scorecard` and `edit_section` become primary.

### 2.6 Conversation History Across Phases

The conversation is continuous. When the user advances from brainstorm to draft, the conversation is NOT cleared. Instead, the engine injects a phase transition marker:

```
[System] Phase transition: Brainstorm → Draft
The outline has been finalized with {N} sections using the {framework} pattern.
Selected hook: "{hook_text}"
Your task is now to write the full first draft following the outline.
```

This means:
- Draft generation has access to WHY each outline item was chosen (from brainstorm conversation)
- Polish has access to the original creative intent AND the draft generation reasoning
- The user never loses context from earlier decisions

### 2.7 Inline Editing Integration

Currently, AIWritingAssistant uses OpenRouter/Gemini with zero strategic context. In the unified system, inline edits (expand/condense/rephrase) are routed through the same conversation agent:

1. User selects text in the draft editor and clicks "Expand"
2. The system appends a message to the conversation: `[User action: Expand selection] "selected text here..."`
3. The agent responds using the `edit_section` tool, with full awareness of voice profile, methodology, and outline context
4. The diff preview is shown as before

This eliminates the context isolation problem where inline edits drift from the established voice because the inline AI has no strategic context.

---

## 3. The Actual System Prompt

This is the complete, production-ready system prompt text. It is injected as Block 1 of the system message. The `{PLACEHOLDERS}` are filled dynamically at runtime.

```
═══════════════════════════════════════════════════════════════
COSMO UNIFIED WRITING ENGINE — SYSTEM PROMPT
═══════════════════════════════════════════════════════════════

You are an expert content strategist and ghostwriter inside CosmoOS. You work
with creators to develop, draft, and polish content across every phase of the
pipeline — from first spark to final draft.

You are NOT a generic AI assistant. You are a specialized writing partner with
deep knowledge of content strategy, persuasion psychology, and platform-specific
best practices. Every response must reflect this expertise.

═══════════════════════════════════════════════════════════════
SECTION 1: YOUR ROLE AND BEHAVIOR
═══════════════════════════════════════════════════════════════

CONVERSATION STYLE:
- Be direct and opinionated. You have expertise — use it. Don't hedge with
  "you could try" or "one option might be." State what works and why.
- Be concise. Under 200 words for conversational replies. Use tools for
  structured output (outlines, drafts, edits).
- Reference specific evidence. When you recommend a hook type, cite which
  swipe examples score highest with that pattern. When you suggest a structure,
  reference which beat pattern has the best performance data.
- Challenge weak ideas constructively. If the user's hook is generic, say so.
  If the outline lacks tension, point it out. You are a collaborator, not a
  yes-machine.

PHASE AWARENESS:
- In BRAINSTORM: Focus on strategy — hook selection, framework choice, outline
  structure, audience targeting. Push for specificity and emotional charge.
  Use the think tool to evaluate the idea against the methodology before
  suggesting structure.
- In DRAFT: Focus on execution — voice matching, beat-by-beat writing,
  constraint compliance. Use the think tool between sections to verify voice
  consistency and structural adherence.
- In POLISH: Focus on refinement — scorecard evaluation, weak area targeting,
  CTA strengthening, voice drift correction. Be surgical, not wholesale.

TOOL USAGE:
- Use tools to make changes. Don't paste outline items or draft text into your
  conversational response — use the appropriate tool (update_outline, write_draft,
  edit_section, add_hooks, set_description).
- Use the think tool before any generation that requires strategic reasoning.
  Think through: What beat pattern fits? What hook type performs best for this
  niche+format? What voice characteristics must be matched?
- After writing a draft, always use the think tool to self-evaluate against the
  client's failure fingerprint rules before finalizing.

═══════════════════════════════════════════════════════════════
SECTION 2: CONTENT METHODOLOGY
═══════════════════════════════════════════════════════════════

{METHODOLOGY_TEXT}

═══════════════════════════════════════════════════════════════
SECTION 3: PLATFORM CONSTRAINTS (HARD RULES)
═══════════════════════════════════════════════════════════════

These are NON-NEGOTIABLE format constraints. Every draft MUST comply. Use the
think tool to verify compliance before finalizing any draft.

INSTAGRAM CAROUSEL:
- Slide count: 5-15 slides (optimal: 8-10)
- Slide 1: Hook ONLY. Maximum 80 characters. Must stop the scroll.
- Slides 2-N: Body content. Maximum 150 characters per slide. 1-2 sentences max.
- Final slide: CTA. Maximum 100 characters. Clear action + benefit.
- Design direction: Include [VISUAL: ...] markers for each slide.
- Total word count: 200-500 words across all slides.

INSTAGRAM REEL SCRIPT:
- Duration: 15-90 seconds (optimal: 30-60 for educational, 15-30 for hooks)
- Hook: First 3 seconds. Maximum 15 spoken words.
- Scenes: 3-8 scenes. Each scene 5-15 seconds.
- Words per scene: 20-50 spoken words.
- Format: Voiceover script with [VISUAL: ...] markers per scene.
- Total word count: 80-300 words.

INSTAGRAM STORY:
- Slides: 3-7 (optimal: 5)
- Text per slide: Maximum 100 characters (must be readable as overlay)
- CTA on final slide
- Format: Slide-by-slide with text overlay content + [VISUAL: ...] markers.

TWITTER/X THREAD:
- Thread length: 4-12 tweets (optimal: 6-8)
- Tweet 1 (hook): Maximum 200 characters. Must earn the "read more."
- Tweets 2-N: Maximum 280 characters each. Each tweet standalone-readable.
- Final tweet: CTA with clear next step.
- Total word count: 300-800 words.
- Formatting: No hashtags in thread body. Optional 1-2 hashtags in final tweet.

TWITTER/X SINGLE POST:
- Maximum 280 characters.
- One clear idea. One emotional trigger. Optional CTA.

LINKEDIN POST:
- First 3 lines: Hook (must earn "see more" click). Maximum 200 characters.
- Body: 1,200-1,500 characters optimal. Max 3,000.
- Line breaks between every 1-2 sentences.
- CTA: Last 2-3 lines.
- Tone: Professional but personal. First-person stories outperform advice 3x.
- Formatting: No emojis in hooks. Minimal emojis in body (max 3).

YOUTUBE SHORT SCRIPT:
- Duration: 15-60 seconds.
- Hook: First 2 seconds. Maximum 10 spoken words.
- Format: Same as Instagram Reel but optimized for YouTube audience (slightly
  more educational, less trend-dependent).

YOUTUBE LONG-FORM SCRIPT:
- Duration: 8-20 minutes optimal.
- Hook: First 30 seconds. Open loop that justifies watching.
- Sections: 4-8 chapters. Each 2-4 minutes.
- Format: Full script with [VISUAL: ...], [B-ROLL: ...], [GRAPHICS: ...] markers.
- Retention hooks: Re-hook every 2-3 minutes with open loops or transitions.

TIKTOK SCRIPT:
- Duration: 15-60 seconds (optimal: 20-40).
- Hook: First 1-2 seconds. Maximum 8 spoken words. Pattern interrupt required.
- Pacing: New beat every 2-3 seconds.
- Format: Same as Instagram Reel but pacing is faster, tone is more casual.

NEWSLETTER / LONG-FORM:
- Subject line: Maximum 50 characters. Follows hook criteria.
- Opening paragraph: Maximum 3 sentences. Must justify reading.
- Body: 500-2,000 words. Clear section headers. One CTA.
- Format: Markdown with headers, bold key phrases, and bullet lists for
  scanners.

STATIC IMAGE POST (Instagram/Facebook):
- Caption: Maximum 2,200 characters (optimal: 150-300 for engagement).
- First line: Hook. Must be compelling before "...more" truncation (~125 chars).
- Hashtags: 5-15, placed after main caption with line break separator.

═══════════════════════════════════════════════════════════════
SECTION 4: GENERATION RULES
═══════════════════════════════════════════════════════════════

BEFORE GENERATING ANY CONTENT, use the think tool to plan:
1. What format and platform constraints apply?
2. What beat pattern best fits this content? (Reference swipe data.)
3. What hook type performs best for this niche+format? (Reference swipe scores.)
4. What voice characteristics must I match? (Reference Intelligence Model.)
5. What failure rules must I avoid? (Reference Failure Fingerprint.)

DURING GENERATION:
- Follow the outline beat-by-beat. Each outline section = one structural beat.
- Match the client's sentence length, power words, and tone from the Voice
  Fingerprint. Use their signature phrases naturally.
- Comply with ALL hard constraints for the target format (character counts,
  slide counts, word counts). Verify after writing each section.
- Reference specific swipe examples when explaining structural choices.

AFTER GENERATION:
- Use the think tool to self-evaluate:
  a. Does each section comply with format character/word limits?
  b. Does the hook satisfy at least 5 of 7 hook criteria from the methodology?
  c. Does the voice match the client's fingerprint? Check: sentence length,
     power words, tone, no blacklisted phrases.
  d. Does the draft violate any failure fingerprint rules?
  e. Does the CTA follow the CTA criteria (calls out ICP, answers WIIFM,
     clear outcome+timeline)?
- If any check fails, fix it before outputting. Do NOT output a draft you
  know violates constraints.

STRUCTURED OUTPUT RULES:
- When writing carousel content, the write_draft tool's content field must be
  valid JSON: {"slides": [{"number": 1, "text": "...", "visualDirection": "..."}]}
- When writing thread content, use JSON: {"tweets": [{"number": 1, "text": "..."}]}
- When writing video scripts, use plaintext with [VISUAL: ...] markers.
- When writing long-form text, use Markdown.

═══════════════════════════════════════════════════════════════
SECTION 5: FEW-SHOT EXAMPLE INJECTION FORMAT
═══════════════════════════════════════════════════════════════

When swipe examples are provided in the dynamic context, they follow this format:

SWIPE EXAMPLE #{N}: "{title}"
Hook ({hookType}, score {score}/10): "{hook_text}"
Structure: {beat1} > {beat2} > {beat3} > ...
Key Transitions: {transition_notes}
CTA: "{cta_text}"
Why This Works: {performance_reasoning}

Use these examples as structural and tonal references. Do NOT copy text verbatim.
Extract the PATTERNS (hook technique, emotional arc, beat sequence, CTA style)
and apply them to the new content with the client's voice.

═══════════════════════════════════════════════════════════════
END OF SYSTEM PROMPT
═══════════════════════════════════════════════════════════════
```

**What gets injected dynamically**:
- `{METHODOLOGY_TEXT}` → `PromptTemplateStore.shared.methodology` (the existing ~3800-word playbook)
- Block 2 (Intelligence Model) is assembled from `ClientIntelligenceModel` fields — voice fingerprint, performance fingerprint, failure fingerprint, audience model, niche positioning, format-specific fingerprints, and 2-3 compressed top-performing transcripts
- Block 3 (Dynamic Context) includes selected swipe examples in the format shown in Section 5, current content state, and knowledge context

---

## 4. Data Retrieval Specification

### 4.1 Client Intelligence Model (Full)

**Source**: `ClientProfileMetadata.intelligenceModel` from the linked client profile atom.

**What Gets Included** (Block 2, cached):

| Field | Source Path | Token Estimate | Formatting |
|-------|-----------|---------------|-----------|
| Voice Fingerprint | `intelligenceModel.voiceFingerprint` | ~800 | Structured list: sentence length, power words, tone distribution, signature phrases, blacklisted phrases, quirks |
| Performance Fingerprint | `intelligenceModel.performanceFingerprint` | ~600 | Structured: best hook types + scores, best beat patterns, optimal length, engagement patterns |
| Failure Fingerprint | `intelligenceModel.failureFingerprint` or format-specific variant | ~400 | Numbered rules with severity (CRITICAL/WARNING). Prefixed with "RULES — Violating these correlates with underperformance:" |
| Audience Model | `intelligenceModel.audienceModel` | ~300 | Who they are, pain points, desires, language they use |
| Niche Positioning | `intelligenceModel.nicheAndPositioning` | ~300 | Specific niche, unique angle, competitive differentiation |
| Format Fingerprints | `intelligenceModel.reelVoiceFingerprint`, `threadVoiceFingerprint` (if matching format) | ~500 | Only the fingerprint matching the current content format |
| **Subtotal** | | **~2,900** | |

**When No Intelligence Model Exists** (legacy fallback): Assemble from individual `ClientProfileMetadata` fields: `brandStory`, `voiceNotes`, `uniqueAngle`, `coreBeliefs`, `signaturePhrases`, `extractedVoicePatterns`, `topPerformingPosts`. This is the current `assembleLegacyLayer2()` logic in OpusWritingEngine — it stays as-is.

### 4.2 Top-Performing Transcripts (Contrastive Voice Examples)

**Source**: `ClientIntelligenceEngine.shared.getTopTranscripts()` per format category.

**Selection Logic**:
1. Get current content format (reel, thread, carousel, etc.)
2. Fetch top 3 transcripts matching that format from the client's profile documents
3. If < 3 format-matched, backfill with best performers from any format
4. Compress each transcript: extract hook (first 2 sentences), structural beats (BeatPatternService.normalizeBeats), CTA (last sentence/paragraph). Target ~400 tokens per transcript.

**Contrastive Example** (NEW):
- If underperformer documents exist for the matching format, include 1 underperformer alongside the top performers
- Format as:
  ```
  GOOD (top performer, 50K views): "{compressed_transcript}"
  BAD (underperformer, 2K views): "{compressed_transcript}"
  DIFFERENCE: {auto-generated or human-provided explanation of what makes the good one work}
  ```

### 4.3 Swipe Examples (Format-Matched + Topic-Matched + High-Performer)

**Source**: Inherited swipe UUIDs from idea activation + HybridSearchEngine search.

**Selection Pipeline** (implements diversity-aware selection):

```
Step 1: Collect candidates
  - All inherited swipes from idea activation (metadata.inheritedSwipeUUIDs)
  - HybridSearchEngine search results for content title/idea (up to 20)
  - Filter: must have swipeAnalysis (non-nil hookType, frameworkType, sections)

Step 2: Score candidates on 3 axes
  - FORMAT_MATCH: Does the swipe match the target format? (carousel→carousel, reel→reel)
    Exact match: +10. Same platform: +5. Different platform: +0.
  - STRUCTURAL_MATCH: Does the beat fingerprint match the selected pattern?
    BeatPatternService.shared.fingerprintSimilarity(). Score 0-10.
  - PERFORMANCE: hookScore from swipeAnalysis. Score 0-10.

Step 3: Select 2-3 diverse examples
  - Example 1: Highest FORMAT_MATCH score (same format, same framework)
  - Example 2: Highest PERFORMANCE score (top performer in niche, any format)
  - Example 3: Highest STRUCTURAL_MATCH score if different from examples 1-2
  - Dedup: no two examples with the same beatFingerprint

Step 4: Compress each selected swipe
  - Hook: verbatim (first 2 sentences of transcript)
  - Structure: normalized beat sequence from BeatPatternService
  - Key transitions: first sentence of each non-hook section
  - CTA: last paragraph/sentence
  - Performance: hookType, hookScore, framework
  - Target: ~200 tokens per compressed swipe
```

### 4.4 Beat Patterns

**Source**: `BeatPatternService.shared.findTopPatterns(niche:limit:)`

**What Gets Included**: Top 3 patterns for the content's niche, formatted as:
```
PATTERN: {fingerprint}
Beats: {beat1} > {beat2} > {beat3} > ...
Frequency: {N}x in swipe library | Avg Hook Score: {X}/10
```

Included in Block 3 (dynamic context). Used by the agent to recommend structure during brainstorm.

### 4.5 Knowledge Context (Connection Atoms)

**Source**: `KnowledgeContextAssembler().assembleKnowledgeContext()`

**What Gets Included**: Top 1-2 Connection atoms semantically relevant to the content piece. Formatted as structured blocks with section titles and supporting research insights from graph neighbors.

Included in Block 3 (dynamic context). Lower priority — dropped first when context budget is tight.

### 4.6 Context Compression Strategy

When the total estimated context exceeds 80K tokens:

| Priority | Action | Saves |
|----------|--------|-------|
| 1 | Reduce top transcripts from 3 to 1 per format | ~2K tokens |
| 2 | Reduce swipe examples from 3 to 2 | ~200 tokens |
| 3 | Summarize conversation history > 15 turns old | ~5-15K tokens |
| 4 | Drop knowledge context (Connection atoms) | ~2-5K tokens |
| 5 | Reduce top transcripts to hooks-only (no full text) | ~1.5K tokens |
| 6 | Reduce swipe examples to 1 | ~200 tokens |

**Never drop**: Methodology, voice fingerprint, failure fingerprint, current content state, last 10 conversation turns.

### 4.7 Injection Format

Each data source is formatted with clear section headers for the AI to reference:

```
--- CLIENT INTELLIGENCE MODEL ---
[Voice Fingerprint]
...
[Performance Fingerprint]
...
[Failure Rules]
...

--- TOP-PERFORMING CONTENT ---
GOOD (Reel, 50K views): "..."
GOOD (Reel, 35K views): "..."
BAD (Reel, 2K views): "..."
DIFFERENCE: ...

--- SWIPE EXAMPLES ---
SWIPE #1: "Title" [carousel, curiosityGap, 8.5/10]
Hook: "..."
Structure: BoldClaim > Proof > Proof > Proof > CTA
...

--- BEAT PATTERNS ---
PATTERN 1: BoldClaim>StepByStep>SocialProof>UrgencyCTA
...

--- CURRENT CONTENT ---
Title: ...
Platform: Instagram
Format: Carousel
Phase: Brainstorm
Outline: ...
Hooks: ...
Description: ...
```

---

## 5. Implementation Plan

### 5.1 New Files to Create

**`AI/UnifiedWritingEngine.swift`** (~800-1000 lines)

The core engine. Replaces OpusWritingEngine, BrainstormAIEngine, ContentAICollaboratorEngine, and AIWritingAssistant for content pipeline use.

```swift
@MainActor
final class UnifiedWritingEngine: ObservableObject {
    // MARK: - Published State
    @Published var messages: [WritingMessage] = []
    @Published var isProcessing = false
    @Published var error: String?
    @Published var toolChainSteps: [ToolChainStep] = []

    // MARK: - Context Cache
    private var cachedSystemBlocks: [(content: String, cacheControl: Bool)] = []
    private var cachedContextVersion: UUID?  // invalidated when content/profile changes
    private var contentAtom: Atom?
    private var clientProfile: ClientProfileMetadata?
    private var intelligenceModel: ClientIntelligenceModel?

    // MARK: - Lifecycle
    func initialize(contentAtom: Atom) async { ... }
    func refreshContext() async { ... }

    // MARK: - Conversation
    func sendMessage(_ text: String, state: inout ContentFocusModeState) async { ... }
    func handlePhaseTransition(from: ContentStep, to: ContentStep, state: ContentFocusModeState) { ... }

    // MARK: - Quick Actions (convenience wrappers that send specific messages)
    func suggestOutline(state: inout ContentFocusModeState) async { ... }
    func generateDraft(state: inout ContentFocusModeState) async { ... }
    func runScorecard(state: inout ContentFocusModeState) async { ... }
    func inlineEdit(action: AIWritingAction, text: String, state: inout ContentFocusModeState) async { ... }

    // MARK: - Context Assembly
    private func assembleBlock1() -> String { ... }  // Methodology + platform constraints
    private func assembleBlock2() async -> String { ... }  // Intelligence model + transcripts
    private func assembleBlock3(state: ContentFocusModeState) async -> String { ... }  // Dynamic context
    private func assembleToolDefinitions(phase: ContentStep) -> [[String: Any]] { ... }

    // MARK: - Tool Execution
    private func executeToolCalls(_ toolCalls: [ToolCall], state: inout ContentFocusModeState) async { ... }
    private func handleUpdateOutline(_ params: UpdateOutlineParams, state: inout ContentFocusModeState) { ... }
    private func handleWriteDraft(_ params: WriteDraftParams, state: inout ContentFocusModeState) { ... }
    private func handleEditSection(_ params: EditSectionParams, state: inout ContentFocusModeState) { ... }
    private func handleAddHooks(_ params: AddHooksParams, state: inout ContentFocusModeState) { ... }
    private func handleSearchSwipes(_ params: SearchSwipesParams) async -> String { ... }

    // MARK: - Swipe Selection
    private func selectDiverseSwipes(for contentAtom: Atom, limit: Int) async -> [CompressedSwipe] { ... }
    private func compressSwipe(_ swipe: Atom) -> CompressedSwipe { ... }

    // MARK: - Conversation Memory
    private func summarizeHistoryIfNeeded() async { ... }
    private func estimateTokens() -> Int { ... }
}
```

**`AI/UnifiedWritingTypes.swift`** (~200 lines)

Shared types for the unified engine.

```swift
struct WritingMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: WritingMessageRole
    let content: String
    let timestamp: Date
    var toolCalls: [WritingToolCall]?
    var toolResults: [WritingToolResult]?

    enum WritingMessageRole: String, Codable { case user, assistant, system, toolResult }
}

struct WritingToolCall: Identifiable, Codable, Equatable {
    let id: UUID
    let toolName: String
    let parameters: String  // JSON string
    var status: ToolCallStatus
    enum ToolCallStatus: String, Codable { case pending, executing, completed, failed }
}

struct CompressedSwipe: Identifiable {
    let id: UUID
    let title: String
    let hookText: String
    let hookType: String
    let hookScore: Double
    let beatSequence: [String]
    let keyTransitions: [String]
    let ctaText: String
    let framework: String
    func formatted() -> String { ... }  // ~200 token formatted string
}

// Tool parameter types
struct UpdateOutlineParams: Codable { ... }
struct WriteDraftParams: Codable { ... }
struct EditSectionParams: Codable { ... }
struct AddHooksParams: Codable { ... }
struct SearchSwipesParams: Codable { ... }
```

### 5.2 Existing Files to Modify

**`UI/FocusMode/Content/ContentFocusModeView.swift`**

- Replace `@StateObject private var aiCollaboratorEngine = ContentAICollaboratorEngine()` with `@StateObject private var writingEngine = UnifiedWritingEngine()`
- Pass `writingEngine` to `ContentAICollaboratorView` (which becomes the unified chat UI)
- Initialize engine on appear: `writingEngine.initialize(contentAtom: atom)`
- Wire phase transitions: when `viewModel.state.currentStep` changes, call `writingEngine.handlePhaseTransition()`

**`UI/FocusMode/Content/ContentAICollaboratorView.swift`**

- Change from `ContentAICollaboratorEngine` to `UnifiedWritingEngine` as the engine type
- The view remains a 380px floating popover with chat UI
- Quick action pills become phase-aware tool invocations
- Tool call results are displayed inline with accept/reject UI (keeping existing pattern)
- Remove the separate `applyCollaboratorAction()` — tool execution is handled by the engine

**`UI/FocusMode/Content/ContentBrainstormView.swift`**

- Remove `BrainstormAIEngine` as a separate `@StateObject`
- The brainstorm sidebar chat now uses the shared `UnifiedWritingEngine` from the parent
- `BrainstormContextSidebar` takes `@ObservedObject var engine: UnifiedWritingEngine` instead of `BrainstormAIEngine`

**`UI/FocusMode/Content/ContentDraftView.swift`**

- Remove `@StateObject private var aiAssistant = AIWritingAssistant()`
- Inline edit actions (expand/condense/rephrase) are routed to `UnifiedWritingEngine.inlineEdit()`
- The floating action bar on text selection remains visually identical but calls the unified engine
- Draft generation button calls `writingEngine.generateDraft(state:)`

**`UI/FocusMode/Content/ContentFocusModeState.swift`**

- Add `var conversationHistory: [WritingMessage] = []` (persisted)
- Add `var conversationSummary: String = ""` (persisted — holds summarized older turns)
- Update `from(atom:)` and `toAtomFields()` to serialize/deserialize conversation
- Keep `generationHistory: [GenerationRecord]` for backward compatibility

**`Services/PromptTemplateStore.swift`**

- Replace the 4 separate prompts (methodology, outline, draft, collaborator) with ONE unified prompt
- `@Published var unifiedSystemPrompt: String` — the full text from Section 3 of this document
- Keep `methodology` as a sub-section that users can edit independently (it gets injected into the unified prompt at `{METHODOLOGY_TEXT}`)
- Remove: `outlinePrompt`, `draftPrompt`, `collaboratorPrompt` and their save/reset methods
- Add: `platformConstraints: String` — the platform constraint tables (users can customize)

**`Cosmo/ResearchService.swift`**

- Add `func generateWithTools(...)` method that supports Claude's native tool_use format
- Accepts: system blocks (with cache_control), messages, tool definitions, model
- Returns: structured response with text content + tool_use blocks
- This is the key API addition — the existing `generateWithCaching()` only supports text responses

**`Data/Models/LevelSystem/ContentPipelineMetadata.swift`**

- No structural changes needed. `ClientIntelligenceModel` and related types are already well-structured.
- The unified engine reads the same data — it just reads it once and injects it everywhere, rather than having 4 engines each reading different subsets.

### 5.3 Settings Changes

**`Settings/CosmoAgentSettingsTab.swift`** (or new `Settings/WritingEngineSettingsTab.swift`)

Add a writing engine settings section:

1. **System Prompt Editor**: Full text editor for the unified system prompt. Markdown preview. "Reset to default" button. This replaces the hidden 4-prompt PromptTemplateStore.
2. **Methodology Editor**: Editable sub-section of the system prompt (the ~3800-word playbook). This is what power users customize.
3. **Platform Constraints Editor**: Editable constraint tables. Users can adjust character limits, slide counts, etc.
4. **Intelligence Model Viewer**: Read-only display of the current client's intelligence model — voice fingerprint, performance fingerprint, failure rules. Users can see exactly what the AI "knows" about their client.
5. **Model Selection**: Dropdown for writing model tier (Opus/Sonnet/Gemini). Default: Opus for generation, Sonnet for scoring.

### 5.4 UI Transparency Panel

Add a collapsible "AI Context" indicator to the ContentFocusModeView that shows:
- Which client profile is loaded (name + confidence scores)
- How many swipe examples are in context (with names)
- Which beat pattern is recommended
- Whether failure rules are active (count + severity)
- Estimated token usage (current / budget)
- Link to open the full Intelligence Model viewer

This replaces the current opacity where users have no idea what context the AI is using.

### 5.5 Migration Path

The migration is additive — new engine alongside old engines, with a feature flag to switch:

1. **Phase 1**: Create `UnifiedWritingEngine` and `UnifiedWritingTypes`. Wire to `ContentFocusModeView` behind a flag.
2. **Phase 2**: Migrate brainstorm sidebar from `BrainstormAIEngine` to `UnifiedWritingEngine`.
3. **Phase 3**: Migrate inline edits from `AIWritingAssistant` to `UnifiedWritingEngine`.
4. **Phase 4**: Remove old engines once unified engine is validated.

---

## 6. What Gets Removed

### 6.1 Engines Removed

| File | Lines | Replaced By |
|------|-------|-------------|
| `AI/BrainstormAIEngine.swift` | ~357 | `UnifiedWritingEngine.sendMessage()` in brainstorm phase |
| `AI/ContentAICollaboratorEngine.swift` | ~958 | `UnifiedWritingEngine` (entire engine) |
| `Editor/AIWritingAssistant.swift` (content pipeline usage) | ~801 | `UnifiedWritingEngine.inlineEdit()`. NOTE: AIWritingAssistant may still be used outside the content pipeline (e.g., note editing). If so, keep it but make it call through the unified engine when a content context is available. |

### 6.2 Duplicate Code Removed

| Code | Location | Reason |
|------|----------|--------|
| `assembleMegaContext()` (legacy non-cached path) | `OpusWritingEngine.swift` line ~149 | Duplicate of `assembleCachedMegaContext()`. Unified engine only uses cached path. |
| `generateOutline(for:profile:)` (legacy overload) | `OpusWritingEngine.swift` line ~1212 | Duplicate of `generateOutline(contentAtom:)`. Unified engine uses one generation path. |
| `generateDraft(for:profile:outline:)` (legacy overload) | `OpusWritingEngine.swift` line ~1260 | Same. |
| `generateHookVariants(for:profile:count:)` (legacy overload) | `OpusWritingEngine.swift` line ~1343 | Same. |
| `[TOOL:xxx]...[/TOOL]` parsing | `ContentAICollaboratorEngine.swift` line ~924 | Replaced by Claude native tool_use parsing. |
| `[ACTION:xxx]` parsing | `BrainstormAIEngine.swift` | Same. |

### 6.3 Prompts Removed

| Prompt | Location | Replacement |
|--------|----------|-------------|
| `DEFAULT_COLLABORATOR_PROMPT` (3 lines) | `PromptTemplateStore.swift` line ~501 | Unified system prompt Section 1 |
| `DEFAULT_OUTLINE_PROMPT` | `PromptTemplateStore.swift` line ~445 | Tool schema for `update_outline` + unified system prompt Generation Rules |
| `DEFAULT_DRAFT_PROMPT` | `PromptTemplateStore.swift` line ~480 | Tool schema for `write_draft` + unified system prompt Generation Rules |

`DEFAULT_METHODOLOGY` is KEPT — it becomes the `{METHODOLOGY_TEXT}` injection into the unified prompt.

### 6.4 UI Flows Removed

| Flow | Current Location | Replacement |
|------|-----------------|-------------|
| "Generate Draft" button in ContentDraftView | Calls `OpusWritingEngine.generateDraft()` directly | User tells agent "Write the draft" or clicks quick action pill → agent uses `write_draft` tool |
| "Suggest Outline" button in ContentBrainstormView | Calls `OpusWritingEngine.generateOutline()` directly | User tells agent "Suggest an outline" → agent uses `update_outline` tool |
| Separate brainstorm chat sidebar | `BrainstormContextSidebar` with its own `BrainstormAIEngine` | Same sidebar, unified engine |

### 6.5 API Inconsistencies Removed

| Current | Replacement |
|---------|-------------|
| AIWritingAssistant calls OpenRouter/Gemini directly | All writing goes through ResearchService → Claude via unified engine |
| BrainstormAIEngine calls ResearchService without caching | Unified engine uses `generateWithTools()` with prompt caching |
| 3 different response parsing systems (JSON, [TOOL:], [ACTION:]) | One parsing system: Claude native tool_use responses |

### 6.6 OpusWritingEngine Refactoring

`OpusWritingEngine.swift` is NOT fully removed. It is **refactored** into a context assembly service:

- **Keep**: `assembleIntelligenceModelLayer2()`, `assembleLegacyLayer2()`, `assembleLayer3()`, `assembleLayer4()`, `findMatchingSwipes()`, all response parsing methods.
- **Remove**: `assembleMegaContext()` (legacy), all `generate*()` methods (generation moves to `UnifiedWritingEngine`), `assembleCachedMegaContext()` (replaced by `UnifiedWritingEngine.assembleBlock*()` methods).
- **Rename**: `OpusWritingEngine` → `WritingContextService` — it becomes a pure context assembly utility, no longer a generation engine.

Alternatively, the context assembly logic can be moved directly into `UnifiedWritingEngine` to avoid an extra layer. This is a code organization decision that can be made during implementation.

---

## 7. Platform/Format Constraint Tables

These are the hard constraints referenced in Section 3 of the system prompt. They are also used for post-generation validation.

### 7.1 Instagram Carousel

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Slide count | 5-15 (optimal: 8-10) | `slides.count` in [5, 15] |
| Slide 1 (hook) characters | Max 80 | `slides[0].text.count <= 80` |
| Body slide characters | Max 150 each | `slides[1...N-1].text.count <= 150` |
| Final slide (CTA) characters | Max 100 | `slides.last.text.count <= 100` |
| Sentences per body slide | 1-2 | Count `.` `!` `?` terminators |
| Total word count | 200-500 | Sum of all slide word counts |
| Visual directions | Required per slide | Each slide has non-empty `visualDirection` |

### 7.2 Instagram Reel Script

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Duration | 15-90 seconds | Sum of scene estimated seconds |
| Hook (first 3 seconds) | Max 15 spoken words | Word count of scene 1 |
| Scene count | 3-8 | `scenes.count` in [3, 8] |
| Words per scene | 20-50 | Per-scene word count check |
| Total word count | 80-300 | Sum of all scene word counts |
| Visual markers | Required per scene | Each scene has `[VISUAL: ...]` |

### 7.3 Instagram Story

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Slide count | 3-7 (optimal: 5) | `slides.count` in [3, 7] |
| Text per slide | Max 100 characters | `slides[i].text.count <= 100` |
| CTA | Final slide required | Last slide contains action verb |
| Visual directions | Required per slide | Each slide has `[VISUAL: ...]` |

### 7.4 Twitter/X Thread

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Tweet count | 4-12 (optimal: 6-8) | `tweets.count` in [4, 12] |
| Tweet 1 (hook) | Max 200 characters | `tweets[0].text.count <= 200` |
| Body tweets | Max 280 characters each | `tweets[i].text.count <= 280` |
| Final tweet (CTA) | Max 280 characters | Contains CTA language |
| Total word count | 300-800 | Sum of all tweet word counts |
| Hashtags | None in body, max 2 in final | Regex check for # in non-final tweets |

### 7.5 Twitter/X Single Post

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Characters | Max 280 | `text.count <= 280` |
| Ideas | Exactly 1 | Semantic check (soft) |

### 7.6 LinkedIn Post

| Constraint | Value | Validation |
|-----------|-------|-----------|
| First 3 lines (hook) | Max 200 characters | Character count of first 3 lines |
| Body length | 1,200-1,500 optimal, max 3,000 characters | `text.count` in [800, 3000] |
| Line breaks | Between every 1-2 sentences | Check for `\n` frequency |
| Emojis | Max 3 in body, none in hook | Emoji regex count |

### 7.7 YouTube Short Script

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Duration | 15-60 seconds | Sum of scene durations |
| Hook (first 2 seconds) | Max 10 spoken words | Word count of scene 1 |
| Visual markers | Required per scene | `[VISUAL: ...]` present |
| Total word count | 60-250 | Sum word count |

### 7.8 YouTube Long-Form Script

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Duration | 8-20 minutes optimal | Sum of section durations |
| Hook | First 30 seconds | Section 1 duration check |
| Chapter count | 4-8 | Section count |
| Chapter duration | 2-4 minutes each | Per-section duration check |
| Visual markers | `[VISUAL:]`, `[B-ROLL:]`, `[GRAPHICS:]` | Marker presence per section |
| Retention hooks | Every 2-3 minutes | Check for transition hooks between chapters |

### 7.9 TikTok Script

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Duration | 15-60 seconds (optimal: 20-40) | Sum of scene durations |
| Hook (first 1-2 seconds) | Max 8 spoken words | Word count of scene 1 |
| Pacing | New beat every 2-3 seconds | Scene duration check |
| Total word count | 60-250 | Sum word count |

### 7.10 Newsletter / Long-Form

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Subject line | Max 50 characters | `subjectLine.count <= 50` |
| Opening paragraph | Max 3 sentences | Sentence count |
| Body length | 500-2,000 words | Word count |
| CTA count | Exactly 1 clear CTA | Semantic check (soft) |
| Format | Markdown with headers | `##` header presence |

### 7.11 Static Image Post

| Constraint | Value | Validation |
|-----------|-------|-----------|
| Caption length | Max 2,200 characters (optimal: 150-300) | `text.count <= 2200` |
| First line | Max 125 characters (before truncation) | Character count of first line |
| Hashtags | 5-15, after line break | Hashtag count + placement check |

---

## Appendix A: Post-Generation Validation Pipeline

After the unified engine generates content via the `write_draft` tool, a validation pipeline runs:

```swift
func validateDraft(
    content: String,
    format: ContentFormat,
    platform: SocialPlatform
) -> ValidationResult {
    let constraints = PlatformConstraints.for(format: format, platform: platform)
    var violations: [ConstraintViolation] = []

    // 1. Parse structured output (JSON for carousels/threads, plaintext for scripts)
    let parsed = parseStructuredContent(content, format: format)

    // 2. Check hard constraints
    for constraint in constraints.hardConstraints {
        if !constraint.validate(parsed) {
            violations.append(ConstraintViolation(
                constraint: constraint,
                actual: constraint.measure(parsed),
                severity: .hard
            ))
        }
    }

    // 3. If hard violations found, send correction prompt
    if !violations.isEmpty {
        return .needsCorrection(violations)
    }

    // 4. Check soft constraints (warnings only)
    for constraint in constraints.softConstraints {
        if !constraint.validate(parsed) {
            violations.append(ConstraintViolation(
                constraint: constraint,
                actual: constraint.measure(parsed),
                severity: .soft
            ))
        }
    }

    return .passed(warnings: violations)
}
```

When validation finds hard violations, the engine automatically sends a correction message to Claude:

```
Your draft has the following constraint violations:
- Slide 3 has 185 characters (max: 150). Condense to fit.
- Thread has 14 tweets (max: 12). Combine or remove 2 tweets.

Rewrite ONLY the violating sections. Output using the edit_section tool.
```

This correction loop runs a maximum of 2 times. If constraints still fail after 2 corrections, the draft is returned with violation warnings displayed to the user.

---

## Appendix B: Cost Estimates

**Per Content Piece (brainstorm through draft)**:

| Step | Input Tokens | Output Tokens | Cached Tokens | Cost (Opus) |
|------|-------------|--------------|--------------|-------------|
| Initialize (context assembly) | ~40K | 0 | 0 | $0.00 (no API call) |
| Brainstorm (5 turns avg) | ~50K * 5 | ~500 * 5 | ~35K * 5 cached reads | ~$0.45 |
| Draft generation (1 call) | ~55K | ~4K | ~35K cached reads | ~$0.12 |
| Validation correction (0-2 calls) | ~45K * 1 | ~2K * 1 | ~35K cached reads | ~$0.06 |
| Polish (3 turns avg) | ~55K * 3 | ~500 * 3 | ~35K * 3 cached reads | ~$0.27 |
| **Total per content piece** | | | | **~$0.90** |

**Compared to current system**: The current 4-engine system makes approximately the same number of API calls but does NOT benefit from prompt caching across engines (each engine builds context from scratch). Estimated current cost per content piece: ~$1.50-2.00. The unified engine saves ~40-55% through prompt caching alone.

---

*Architecture plan authored 2026-02-17 by architect agent.*
*Inputs: 15 research sources + 17 codebase files (~12K lines).*
*Target: Production implementation in CosmoOS-Swift.*
