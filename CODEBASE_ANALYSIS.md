# CosmoOS AI Writing System — Codebase Analysis

## Table of Contents
1. [File-by-File Documentation](#1-file-by-file-documentation)
2. [Data Flow Map](#2-data-flow-map)
3. [Failure Analysis](#3-failure-analysis)
4. [Prompt Inventory](#4-prompt-inventory)
5. [Recommendations Summary](#5-recommendations-summary)

---

## 1. File-by-File Documentation

### 1.1 AI/ContentAICollaboratorEngine.swift (~958 lines)

**Purpose**: Main AI chat engine for the Content Focus Mode floating collaborator panel (Cmd+J). Handles conversational AI interactions during drafting and polishing.

**Key Functions**:
- `sendMessage()` (line ~283) — Routes user messages to AI, delegates structured generation to OpusWritingEngine
- `classifyEditIntent()` (line ~122) — Classifies user intent for inline editing
- `buildSystemPrompt()` (line ~722) — Assembles system prompt from template + content state
- `assembleConversationPrompt()` (line ~810) — Builds full conversation with history
- `handleStreamingEdit()` (line ~343) — Handles streaming section-level rewrites
- `parseToolBlocks()` (line ~924) — Parses `[TOOL:xxx]...[/TOOL]` action blocks from AI responses

**Prompt Construction** (`buildSystemPrompt`, line ~722):
- Starts with `PromptTemplateStore.shared.collaboratorPrompt` (only 3 lines)
- Appends content metadata: format, platform, phase
- Appends hooks (all), outline (full), content description
- Appends draft excerpt: **truncated to first 2000 chars** (line ~769): `let excerpt = String(state.draftContent.prefix(2000))`
- Appends client profile `toAIContextString()` if available
- Does NOT include: methodology, swipe intelligence, beat patterns, knowledge context

**Conversation History** (line ~823-833):
- Last 10 messages appended as plain `User: ... / Assistant: ...` text
- Summarization triggered when estimated tokens > 20K (line ~848)

**Data Flow**:
- IN: ContentFocusModeState (outline, hooks, draft, description), conversation history, client profile atom
- OUT: Text responses, tool blocks (editOutline, editDraft, addHook, setDescription)
- DELEGATES TO: OpusWritingEngine.shared for `generateDraft()`, `generateOutline()`, `generateHookVariants()`

**What's Broken**:
- Draft truncated to 2000 chars means AI loses context on longer drafts during conversation
- Collaborator prompt is only 3 generic lines — no methodology, no style guidance
- No swipe intelligence or beat patterns injected — collaborator is "flying blind" compared to OpusWritingEngine
- Tool block format `[TOOL:xxx]` differs from BrainstormAIEngine's `[ACTION:xxx]` — two parsing systems

---

### 1.2 UI/FocusMode/Content/ContentAICollaboratorView.swift (~1349 lines)

**Purpose**: 380px floating popover UI for AI chat during content creation. Anchored bottom-right, toggled via Cmd+J.

**Key Functions**:
- `sendMessage()` (line ~1000) — Copies state, calls engine, assigns back
- `applyCollaboratorAction()` (line ~1010) — Handles tool block results (outline edits, draft replacement, hook addition)
- Quick action pills: phase-dependent (brainstorm vs draft vs polish)

**Phase-Specific Quick Actions**:
- Default: "Write draft", "Suggest outline", "Improve hook", "Research topic"
- Polish: "Improve Hook", "Fix Voice Drift", "Strengthen CTA", "Run Scorecard", "Run Red Team"

**State Management Issue** (line ~1000):
```swift
var stateCopy = state
await engine.sendMessage(..., state: &stateCopy)
state = stateCopy
```
State is copied before the async call and assigned back after — if the user modifies state during the AI call, their changes are overwritten.

**Data Flow**:
- IN: `@Binding var state: ContentFocusModeState`, `ContentAICollaboratorEngine` as `@StateObject`
- OUT: Mutated state (outline, hooks, draft, description), UI actions (apply/ignore)

---

### 1.3 AI/OpusWritingEngine.swift (~1573 lines)

**Purpose**: Singleton engine for high-quality content generation. Assembles the richest context ("mega-context") of any engine in the system. Uses 4-layer cached prompt architecture.

**Key Functions**:
- `assembleCachedMegaContext()` (line ~187) — 4-layer cached context assembly (primary path)
- `assembleMegaContext()` (line ~149) — Legacy non-cached path (duplicates logic)
- `generateOutline()` (line ~572) — Outline generation with cached context
- `generateDraft()` (line ~601) — Format-aware draft generation with self-correction
- `generateHookVariants()` (line ~735) — Hook generation with JSON output
- `findMatchingSwipes()` (line ~1162) — Hybrid search for relevant swipes
- `classifyEditIntent()` — Intent classification for inline edits

**4-Layer Cached Context Assembly** (`assembleCachedMegaContext`, line ~187):

| Layer | Source | Content | Size |
|-------|--------|---------|------|
| 1 | `PromptTemplateStore.shared.methodology` | ~3800 words of content strategy methodology | ~15K tokens |
| 2 | `ClientProfileMetadata.intelligenceModel` or legacy fields | Voice fingerprint, performance data, failure rules | Variable |
| 3 | `BeatPatternService` + `findMatchingSwipes()` | Top beat patterns + up to 30 swipe transcripts (3000 chars each) | Up to ~90K chars |
| 4 | `KnowledgeContextAssembler` | Connection atoms ranked by semantic relevance | Variable |

**Layer 2 Detail** (line ~262):
- Intelligence Model path: includes voiceFingerprint, performanceFingerprint, audienceModel, nichePositioning, format-specific fingerprints
- Legacy path (line ~357): falls back to individual ClientProfileMetadata fields (brandStory, voiceNotes, etc.)

**Layer 3 Detail** (line ~447):
- Beat patterns from `BeatPatternService.shared.getTopPatterns(for:limit:)`
- Swipe transcripts truncated at 3000 chars each (line ~512): `body.count > 3000 ? String(body.prefix(3000)) + "..." : body`
- Up to 30 matching swipes loaded

**Self-Correction Phase** (line ~641-666):
- Checks `intelligenceModel?.failureFingerprints`
- Converts to directives via `FailureFingerprint.asDirectives()`
- Appended to draft prompt as "CRITICAL SELF-CORRECTION RULES"

**Format-Aware Generation** (line ~613-638):
- Video: "Write a video script with clear visual and audio directions..."
- Twitter/Thread: "Write in a thread format, punchy and scannable..."
- Text/Default: "Write in a natural, engaging long-form style..."
- **Missing**: No carousel-specific, no reel-vs-story distinction, no platform-specific length constraints

**Duplication Issue**:
- `assembleMegaContext()` (line ~149) and `assembleCachedMegaContext()` (line ~187) are parallel paths
- Legacy path lacks some Layer 2 intelligence model features
- Both paths exist and are callable — risk of inconsistency

**Data Flow**:
- IN: ContentFocusModeState, client profile atom, content format/platform, cached layers
- OUT: Generated outlines (JSON), drafts (text), hook variants (JSON), edit suggestions
- CALLS: ResearchService.shared.analyzeContent(), BeatPatternService.shared, KnowledgeContextAssembler, HybridSearchEngine

---

### 1.4 AI/BrainstormAIEngine.swift (~357 lines)

**Purpose**: AI chat engine specifically for the brainstorm step (Step 1). Separate from ContentAICollaboratorEngine.

**Key Functions**:
- `sendMessage()` — Sends user message with context to AI
- `updateContext()` (line ~336) — Manually sets context (hooks, outline, description, swipe previews)
- System prompt construction (line ~76)

**System Prompt** (line ~76):
- Basic role description ("You are an expert content strategist...")
- Current context fields: coreIdea, hooks, outline, description
- Action format instructions: `[ACTION:ADD]`, `[ACTION:EDIT:N]`, `[ACTION:REORDER]`, `[ACTION:REPLACE]`, `[ACTION:REFINE_CORE_IDEA]`, `[ACTION:ADD_HOOK]`, `[ACTION:SET_DESCRIPTION]`

**Critical Context Gaps**:
- Only receives `matchedSwipePreviews: [String]` — truncated previews, NOT full transcripts
- Only includes first 3 swipe previews (line ~118): `matchedSwipePreviews.prefix(3)`
- **No methodology** from PromptTemplateStore
- **No client profile** or intelligence model
- **No beat patterns** from BeatPatternService
- **No knowledge context** from connections
- **No format-specific structural guidance**

**Action Format** (different from CollaboratorEngine):
- Uses `[ACTION:xxx]` blocks (not `[TOOL:xxx]`)
- Two completely separate parsing systems in the codebase

**Data Flow**:
- IN: Core idea, hooks, outline items, description, 3 truncated swipe previews
- OUT: Text responses with action blocks
- DOES NOT CALL: OpusWritingEngine, BeatPatternService, KnowledgeContextAssembler

---

### 1.5 Services/PromptTemplateStore.swift (~506 lines)

**Purpose**: Singleton store for 4 editable AI prompts. Persisted in UserDefaults.

**4 Prompts**:

| Prompt | Key | Default Size | Used By |
|--------|-----|-------------|---------|
| `methodology` | `cosmo_methodology_prompt` | ~3800 words | OpusWritingEngine Layer 1 |
| `outlinePrompt` | `cosmo_outline_prompt` | ~30 lines | OpusWritingEngine.generateOutline() |
| `draftPrompt` | `cosmo_draft_prompt` | ~15 lines | OpusWritingEngine.generateDraft() |
| `collaboratorPrompt` | `cosmo_collaborator_prompt` | **3 lines** | ContentAICollaboratorEngine |

**DEFAULT_METHODOLOGY** (line ~109-441, ~3800 words):
Comprehensive content strategy covering 8 sections:
1. Virality drivers (pattern interrupts, open loops, emotional triggers)
2. Emotional triggering techniques
3. Editing checklist (hook criteria, copy criteria, CTA criteria)
4. Funnel types (TOF/MOF/BOF) with examples
5. Copywriting rules (power words, specificity, conversational tone)
6. Idea evaluation framework
7. Beat pattern definitions
8. Platform intelligence (Instagram, YouTube, Twitter, TikTok, LinkedIn)

**DEFAULT_OUTLINE_PROMPT** (line ~445-476):
- Requests structured JSON with `selectedPatternFingerprint`, sections with `beatLabel`, `hookVariants`
- References beat pattern data that should be in context

**DEFAULT_DRAFT_PROMPT** (line ~480-497):
- Voice matching instructions
- Self-evaluation JSON block (voiceMatchScore, hookEffectivenessScore, ctaStrength, improvementNotes)
- Brief — only ~15 lines

**DEFAULT_COLLABORATOR_PROMPT** (line ~501-505):
```
You are an expert content strategist and AI collaborator inside CosmoOS.
Help the user refine their content through conversation.
Be concise, specific, and actionable.
```
**This is the entire collaborator prompt — critically minimal.**

**UI Access**: No visible UI in the content pipeline for editing these prompts. The PromptTemplateStore has `reset()` and `update()` methods but they're only accessible programmatically or potentially through a hidden settings path.

---

### 1.6 Editor/AIWritingAssistant.swift (~801 lines)

**Purpose**: Inline text editing for expand/condense/rephrase/continueWriting operations. Used in ContentDraftView for selection-based AI actions.

**Key Functions**:
- `expand()`, `condense()`, `rephrase()` — Selection-based text transforms
- `continueWriting()` (line ~161) — Appends content after current text
- `computeWordDiff()` (line ~205) — Word-level LCS diff for preview
- `callOpenRouter()` — Direct OpenRouter API call

**API Routing Inconsistency**:
- `expand()`, `condense()`, `rephrase()` use `callOpenRouter()` directly with `google/gemini-3-flash-preview` (line ~73)
- `continueWriting()` (line ~161) falls back to `ResearchService.shared.analyzeContent()` — different API path
- Neither uses OpusWritingEngine's mega-context

**Client Profile Injection**:
- Optional `clientProfileAtom` property
- When present, appends `meta.toAIContextString()` to prompts
- **No methodology, no swipe intelligence, no beat patterns**

**Prompt Quality**:
- Simple task-specific prompts ("Expand the following text while maintaining voice and style...")
- No content-aware context (doesn't know about hooks, outline, format, platform)
- No self-correction rules from failure fingerprints

**Data Flow**:
- IN: Selected text, surrounding context (preceding/following text), optional client profile
- OUT: Modified text with word-level diff preview
- DOES NOT CALL: OpusWritingEngine, BeatPatternService, PromptTemplateStore

---

### 1.7 Data/Models/LevelSystem/ContentPipelineMetadata.swift (~1410 lines)

**Purpose**: Data models for the entire content pipeline — phases, metadata, client profiles, intelligence models.

**Key Types**:

**ContentPhase** (line ~1):
- 7 phases: ideation, draft, polish, scheduled, published, analyzing, archived
- Only 4 visible in V1 pipeline bar

**ContentDraftMetadata**: Version tracking, word count, diff summary

**ClientProfileMetadata** (line ~1035):
- 40+ fields organized in sections:
  - Identity: clientName, platforms, handles
  - Brand context: brandStory, brandVision, coreBeliefs, voiceNotes, uniqueAngle
  - Performance: topPerformingPosts, extractedVoicePatterns, preferredBeatPatterns
  - Intelligence: `intelligenceModel: ClientIntelligenceModel?`
  - Documents: `documents: [ProfileDocument]?`

**ClientIntelligenceModel** (line ~732):
- `voiceFingerprint`: AI-generated voice analysis
- `performanceFingerprint`: What works/doesn't work for this creator
- `audienceModel`: Target audience profile
- `nichePositioning`: Market positioning analysis
- `formatFingerprints`: Per-format (reel, thread, carousel) specific guidance
- `failureFingerprints: [FailureFingerprint]?`: Rules from underperforming content

**FailureFingerprint** (line ~696):
- `dimension`: What was measured (hookRetention, ctaClickRate, etc.)
- `bestMetric` / `worstMetric` / `delta`: Performance spread
- `severity`: How critical the rule is
- `asDirectives()`: Converts to plain-English self-correction rules

**ProfileDocument** (line ~481):
- Categories: story, reel, thread, voiceGuide, underperformingReel, underperformingThread
- Contains: content text, optional metrics (views, likes, shares, saves, comments)
- Used for voice extraction and failure fingerprint generation

---

### 1.8 UI/FocusMode/Content/ContentFocusModeState.swift (~709 lines)

**Purpose**: Central state model for the content focus mode. Persisted to atom metadata JSON.

**Key Types**:

**ContentStep** enum: brainstorm, draft, polish

**OutlineItem**: title, reasoning, estimatedSeconds, sortOrder, isCompleted
- Backward-compatible decoding from legacy "text" key

**ContentFocusModeState** (persisted fields):
- atomUUID, currentStep, coreIdea, hooks, contentDescription
- outline: [OutlineItem], draftContent, polishAnalysis
- generationHistory: [GenerationRecord]

**Transient Fields** (not persisted):
- aiUndoStack, pinnedDecisions, contentScorecard, redTeamResult
- Streaming edit state fields

**GenerationRecord**: Tracks mode, inputContext, outputSummary, userAction, editDistance, beatPatternUsed
- Intended for preference learning but not yet consumed by any learning engine

**Persistence**:
- `from(atom:)` reads from atom's metadata JSON
- `toAtomFields()` writes to atom body + metadata
- `save()` fires notification for ViewModel to write to DB

**Data Flow**:
- IN: Atom metadata JSON on load
- OUT: Atom metadata JSON on save, notifications to ViewModel
- SHARED BY: ContentFocusModeView, ContentAICollaboratorView, ContentBrainstormView, ContentDraftView, ContentPolishView

---

### 1.9 UI/FocusMode/Content/ContentProfileEditor.swift (~1714 lines)

**Purpose**: Full form UI for creating and editing ClientProfileMetadata. Includes AI-powered auto-fill from uploaded documents.

**Key Features**:
- Context file upload (PDF/TXT/DOCX) with drag-and-drop
- AI auto-fill: sends uploaded content to OpenRouter/Gemini to extract profile fields
- Document library with top-performer / underperformer categorization (reels, threads)
- Voice pattern extraction from top-performing posts via Claude Sonnet (ResearchService)
- Intelligence model generation from accumulated profile data

**API Usage**:
- Auto-fill: OpenRouter/Gemini directly
- Voice extraction: ResearchService (Claude Sonnet)
- Intelligence model: ResearchService (Claude)

**Data Flow**:
- IN: Existing ClientProfileMetadata or legacy ClientMetadata from atom
- OUT: Updated ClientProfileMetadata saved to atom structured JSON
- CALLS: OpenRouter (auto-fill), ResearchService (voice extraction, intelligence model)

---

### 1.10 Search & Knowledge Layer

#### Cosmo/HybridSearchEngine.swift (~536 lines)
- Singleton, BM25 (FTS5) + vector similarity hybrid search
- Default weight: 70% vector, 30% BM25
- Query embedding via `DaemonXPCClient.shared.embed()`, truncated 768d to 256d Matryoshka
- Falls back to BM25-only if embedding fails
- Context-aware boosting from `VoiceContextSnapshot`

#### AI/SearchReRanker.swift (~193 lines)
- AI conceptual re-ranking via `ResearchService.shared.analyzeContent()`
- Skips re-ranking for: short queries, exact matches (>90% top score), well-differentiated results
- Blended score: 60% AI + 40% original
- 5-minute TTL cache, max 20 cached queries

#### AI/KnowledgeContextAssembler.swift (~281 lines)
- Assembles Layer 4 of OpusWritingEngine's mega-context
- Loads Connection atoms scoped to profile or universal
- Ranks by semantic relevance via HybridSearchEngine
- Filters to Developing+ maturity level
- Selects top 1-3 connections, loads supporting research insights from graph neighbors
- Formats as structured "LAYER 4: KNOWLEDGE CONTEXT" block

---

### 1.11 Supporting View Files

#### UI/FocusMode/Content/ContentBrainstormView.swift
- Step 1 of content focus mode
- Left column: hooks section, description section, outline section (all editable)
- Right column: `BrainstormContextSidebar` (separate file) — hosts BrainstormAIEngine chat
- No direct AI engine integration in this view file

#### UI/FocusMode/Content/ContentDraftView.swift
- Step 2 of content focus mode
- Left sidebar: outline checklist with completion tracking
- Main area: rich text editor with `TextKitCoordinator`
- Inline AI: floating action bar on text selection (Expand/Condense/Rephrase via Cmd+Shift+E/C/R)
- Uses `AIWritingAssistant` as `@StateObject`
- Draft generation state: isGeneratingDraft, confidenceScore, selfCorrectionRuleCount

#### UI/FocusMode/Content/ContentFocusModeView.swift
- Main container routing between brainstorm/draft/polish steps
- Hosts `ContentAICollaboratorView` as 380px floating popover (Cmd+J toggle)
- `ContentAICollaboratorEngine` as `@StateObject`
- Routes to `PostCreationPhaseView` for phases beyond polish

#### Settings/CosmoAgentSettingsTab.swift
- Settings for the Cosmo Agent chat system — **NOT the writing system**
- AI provider picker (Anthropic/OpenRouter/Ollama/Custom)
- Telegram bot configuration
- Custom system prompt editor
- **No writing-specific prompt or methodology configuration here**

---

## 2. Data Flow Map

### 2.1 Pipeline Stage Context Flow

```
BRAINSTORM STEP                    DRAFT STEP                     POLISH STEP
┌──────────────────┐              ┌──────────────────┐           ┌──────────────────┐
│ BrainstormAI     │              │ OpusWritingEngine │           │ CollaboratorEngine│
│ Engine           │              │ (mega-context)    │           │ (minimal context) │
│                  │              │                   │           │                   │
│ Context:         │              │ Context:          │           │ Context:          │
│ - Core idea      │──(state)──> │ - 4-layer cached  │──(state)──>│ - 3-line prompt  │
│ - 3 swipe        │              │ - Methodology     │           │ - 2000 char draft │
│   previews       │              │ - Client intel    │           │ - Hooks, outline  │
│ - Outline/hooks  │              │ - 30 swipes full  │           │ - No methodology  │
│                  │              │ - Knowledge ctx   │           │ - No swipes       │
│ NO methodology   │              │                   │           │ - No beat patterns│
│ NO client intel  │              │ FULL CONTEXT      │           │                   │
│ NO beat patterns │              │                   │           │ MINIMAL CONTEXT   │
│ NO knowledge ctx │              │                   │           │                   │
└──────────────────┘              └──────────────────┘           └──────────────────┘
                                         │
                                         │ (inline edits)
                                         v
                                  ┌──────────────────┐
                                  │ AIWritingAssistant│
                                  │                   │
                                  │ Context:          │
                                  │ - Selected text   │
                                  │ - Surrounding ctx │
                                  │ - Optional profile│
                                  │                   │
                                  │ NO methodology    │
                                  │ NO swipes         │
                                  │ NO outline aware  │
                                  │ NO format aware   │
                                  └──────────────────┘
```

### 2.2 Context Assembly Comparison

| Feature | OpusWritingEngine | CollaboratorEngine | BrainstormAIEngine | AIWritingAssistant |
|---------|:-:|:-:|:-:|:-:|
| Methodology (3800 words) | YES | NO | NO | NO |
| Client Intelligence Model | YES | Partial (profile only) | NO | Partial (profile only) |
| Swipe Transcripts | 30 full (3000 chars each) | NO | 3 truncated previews | NO |
| Beat Patterns | YES | NO | NO | NO |
| Knowledge Context (Connections) | YES | NO | NO | NO |
| Full Draft | YES | 2000 chars | N/A | Selected text only |
| Outline | YES | YES | YES | NO |
| Hooks | YES | YES | YES | NO |
| Format-Specific Instructions | YES (3 types) | NO | NO | NO |
| Self-Correction Rules | YES | NO | NO | NO |
| Failure Fingerprints | YES | NO | NO | NO |

### 2.3 API Routing

| Engine | Primary API | Fallback |
|--------|-------------|----------|
| OpusWritingEngine | ResearchService (Claude) | None |
| ContentAICollaboratorEngine | ResearchService (Claude) | Delegates to OpusWritingEngine |
| BrainstormAIEngine | ResearchService (Claude) | None |
| AIWritingAssistant | OpenRouter/Gemini directly | `continueWriting()` uses ResearchService |
| ContentProfileEditor | OpenRouter/Gemini (auto-fill), ResearchService (voice/intel) | None |

---

## 3. Failure Analysis

### 3.1 FAILURE: Fragmented Context Between Pipeline Stages

**Severity: Critical**

The system has 4 separate AI engines that each assemble their own context independently, with dramatically different quality levels:

**A. Brainstorm Stage Context Starvation**
- `BrainstormAIEngine.swift` line ~118: Only receives 3 truncated swipe previews via `matchedSwipePreviews.prefix(3)`
- Meanwhile, `OpusWritingEngine.swift` line ~447: Loads up to 30 full swipe transcripts (3000 chars each)
- The brainstorm engine has NO access to: methodology, client intelligence model, beat patterns, knowledge context
- **Impact**: The brainstorm step — where structural decisions are made — has the LEAST intelligence. The user makes outline and hook decisions without the AI having access to what actually works for their audience.

**B. Collaborator Context Truncation**
- `ContentAICollaboratorEngine.swift` line ~769: `let excerpt = String(state.draftContent.prefix(2000))`
- A typical reel script is 300-500 words (~2000 chars), but threads/carousels can be 2000-5000 words
- For longer content, the collaborator AI literally cannot see the second half of the draft
- The collaborator also lacks: methodology, swipe intelligence, beat patterns, knowledge context
- **Impact**: During polish, the AI advisor that should help improve the draft can't see the full draft and doesn't know the creator's methodology.

**C. Inline AI Context Isolation**
- `AIWritingAssistant.swift` operates on selected text with minimal surrounding context
- No awareness of: outline structure, hooks, content format, platform constraints, methodology
- Uses different API (OpenRouter/Gemini) than the rest of the system (Claude via ResearchService)
- **Impact**: Inline edits may drift from the established voice and strategy because the inline AI has no strategic context.

**D. No Context Bridge Between Steps**
- BrainstormAIEngine decisions (outline reasoning, hook selection rationale) are NOT passed to OpusWritingEngine
- The `ContentFocusModeState` carries the data artifacts (outline items, hooks) but not the AI's reasoning
- `GenerationRecord` logs exist but are never consumed by downstream engines
- **Impact**: Each step starts from scratch strategically, even though the data artifacts flow through state.

**E. Duplicate Context Assembly**
- `OpusWritingEngine.swift` has both `assembleMegaContext()` (line ~149) and `assembleCachedMegaContext()` (line ~187)
- These are parallel implementations with different feature sets
- Risk of calling the wrong one and getting inconsistent context

---

### 3.2 FAILURE: Permission UI / Data Access Configuration

**Severity: Medium**

**A. No Prompt Editing UI in Content Pipeline**
- `PromptTemplateStore.swift` has 4 editable prompts with `update()` and `reset()` methods
- There is NO visible UI anywhere in the content pipeline to access these
- `CosmoAgentSettingsTab.swift` has prompt editing — but for the Agent system, not the writing system
- **Impact**: Users cannot customize or even view the AI methodology that drives their content generation.

**B. Hidden Intelligence Model**
- `ClientIntelligenceModel` (ContentPipelineMetadata.swift line ~732) contains voiceFingerprint, performanceFingerprint, failureFingerprints
- Generated in `ContentProfileEditor.swift` but stored deep in the profile atom's structured JSON
- No read-only view of what the intelligence model contains or how it influences generation
- **Impact**: Users can't understand or correct the AI's learned model of their style.

**C. Profile Context Inconsistency**
- `ContentAICollaboratorEngine` checks for a client profile atom and includes `toAIContextString()`
- `AIWritingAssistant` has an optional `clientProfileAtom` that may or may not be set
- `BrainstormAIEngine` has NO client profile access at all
- **Impact**: Profile context application is inconsistent — some engines use it, others don't, with no user visibility into which is active.

**D. No API Key Management for Writing**
- `AIWritingAssistant.swift` uses OpenRouter API key hardcoded or from UserDefaults
- `ResearchService` uses Anthropic API key
- No unified settings UI for configuring which model/provider the writing system uses
- **Impact**: Users can't choose their preferred AI model for content generation.

---

### 3.3 FAILURE: Prompt Quality Issues

**Severity: High**

**A. Collaborator Prompt — Critically Minimal**
`PromptTemplateStore.swift` line ~501-505:
```
You are an expert content strategist and AI collaborator inside CosmoOS.
Help the user refine their content through conversation.
Be concise, specific, and actionable.
```
This is the ENTIRE system prompt for the AI collaborator that users interact with during drafting and polishing. It contains:
- No content strategy methodology
- No voice matching instructions
- No format awareness
- No tool/action format instructions (those are added separately in assembleConversationPrompt)

**B. Brainstorm Engine — Lightweight System Prompt**
- `BrainstormAIEngine.swift` line ~76: Basic role description + action format
- No methodology reference, no strategic framework
- The AI helps structure content without knowing content strategy principles
- **Impact**: Outline suggestions and hook improvements lack strategic grounding.

**C. Draft Prompt — Brief**
- `PromptTemplateStore.DEFAULT_DRAFT_PROMPT` (line ~480-497): ~15 lines
- Voice matching instructions exist but are generic
- Self-evaluation JSON block is requested but results aren't surfaced to the user
- **Impact**: Draft generation quality depends heavily on Layer 1-4 context; the actual generation instructions are thin.

**D. Methodology Not Propagated**
- The `DEFAULT_METHODOLOGY` is comprehensive (~3800 words, 8 sections)
- But it's ONLY injected into OpusWritingEngine Layer 1
- CollaboratorEngine, BrainstormAIEngine, and AIWritingAssistant all lack this methodology
- **Impact**: The carefully crafted methodology only influences one of four AI touchpoints.

**E. Format Instructions Are Coarse**
- `OpusWritingEngine.swift` line ~613-638: Only 3 format categories (video, twitter, text)
- No distinction between: Instagram reel vs YouTube short vs TikTok video
- No carousel-specific instructions (slide count, per-slide hooks, visual directions)
- No story-specific instructions
- **Impact**: Platform-specific best practices are missing from generation.

---

### 3.4 FAILURE: Wrong Output Format Generation

**Severity: Medium-High**

**A. Coarse Format Detection**
- `OpusWritingEngine.swift` line ~613-638 checks `contentFormat` and `platform`:
  - `.reel`, `.story` → "video script" instructions
  - `.thread` on Twitter → "thread format" instructions
  - Everything else → "long-form" instructions
- Missing format-specific handling for:
  - Instagram carousels (need per-slide structure, visual directions, hook-on-slide-1)
  - LinkedIn posts (professional tone, hashtag strategy)
  - YouTube long-form vs Shorts
  - Newsletter format
  - Blog posts

**B. No Structural Templates**
- Beat patterns from `BeatPatternService` provide structural fingerprints
- But there's no enforcement that the generated draft follows the selected pattern
- The AI receives pattern names but not structural constraints
- **Impact**: Generated drafts may use a different structure than the selected beat pattern.

**C. Outline-to-Draft Format Mismatch**
- Outline generation (OpusWritingEngine.generateOutline) requests JSON with sections and beat labels
- Draft generation receives the outline as text context
- No validation that the draft covers all outline sections
- No format-specific section templates (e.g., carousel should have exactly N slides)
- **Impact**: Drafts may not follow the outline structure, especially for structured formats like carousels.

**D. Self-Evaluation Not Enforced**
- Draft prompt requests a `[SELF_EVALUATION]` JSON block with scores
- But the parsing code for this block is fragile or missing in some paths
- Evaluation results stored in state but not displayed or acted upon
- **Impact**: The AI may generate a draft it internally rates poorly, with no feedback loop.

---

## 4. Prompt Inventory

### 4.1 All System Prompts

| Location | Purpose | Size | Quality |
|----------|---------|------|---------|
| `PromptTemplateStore.DEFAULT_METHODOLOGY` (line ~109) | Content strategy methodology | ~3800 words | Comprehensive |
| `PromptTemplateStore.DEFAULT_OUTLINE_PROMPT` (line ~445) | Outline generation instructions | ~30 lines | Adequate |
| `PromptTemplateStore.DEFAULT_DRAFT_PROMPT` (line ~480) | Draft generation instructions | ~15 lines | Thin |
| `PromptTemplateStore.DEFAULT_COLLABORATOR_PROMPT` (line ~501) | Collaborator system prompt | **3 lines** | **Critical gap** |
| `BrainstormAIEngine` system prompt (line ~76) | Brainstorm AI instructions | ~40 lines | Lightweight |
| `ContentAICollaboratorEngine.buildSystemPrompt()` (line ~722) | Assembled collaborator prompt | Variable | Missing methodology |
| `AIWritingAssistant` inline prompts | Expand/condense/rephrase | ~5 lines each | Task-specific only |
| `KnowledgeContextAssembler` formatting | Layer 4 knowledge block | ~20 lines template | Good structure |
| `OpusWritingEngine` self-correction | Failure fingerprint rules | Variable | Good when present |

### 4.2 Action/Tool Formats

| Engine | Format | Example |
|--------|--------|---------|
| ContentAICollaboratorEngine | `[TOOL:xxx]...[/TOOL]` | `[TOOL:editOutline]{"sections":[...]}[/TOOL]` |
| BrainstormAIEngine | `[ACTION:xxx]` | `[ACTION:ADD]New section title[/ACTION]` |
| OpusWritingEngine | JSON output | `{"selectedPatternFingerprint":"...","sections":[...]}` |
| AIWritingAssistant | Plain text | Modified text returned directly |

---

## 5. Recommendations Summary

### Critical (Must Fix)
1. **Unify context assembly**: All 4 engines should share a common context layer. At minimum, inject methodology + client intelligence into CollaboratorEngine and BrainstormAIEngine.
2. **Expand collaborator prompt**: Replace the 3-line prompt with a rich system prompt that includes methodology and format awareness.
3. **Remove draft truncation**: CollaboratorEngine's 2000-char draft excerpt loses critical context for longer content.
4. **Bridge brainstorm-to-draft context**: Pass brainstorm AI reasoning and decisions into draft generation context.

### High Priority
5. **Add format-specific generation**: Carousel, reel, thread, story, newsletter each need distinct structural templates and constraints.
6. **Propagate methodology everywhere**: The 3800-word methodology should influence all AI touchpoints, not just OpusWritingEngine.
7. **Surface intelligence model**: Users need to see and correct the AI's learned voice/performance model.
8. **Add prompt editing UI**: Expose PromptTemplateStore prompts in Settings or Content Pipeline settings.

### Medium Priority
9. **Consolidate API routing**: Choose Claude or Gemini for inline edits; don't mix providers within the same user session.
10. **Remove duplicate assembleMegaContext()**: Keep only the cached version to prevent inconsistency.
11. **Standardize action format**: Choose one format ([TOOL:] or [ACTION:]) for all engines.
12. **Enforce outline-to-draft alignment**: Validate draft sections against outline structure.

---

*Analysis completed 2026-02-17 by codebase-analyst agent.*
*Files analyzed: 17 files across 10 categories.*
*Total lines read: ~12,000+*
