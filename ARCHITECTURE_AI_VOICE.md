# CosmoOS AI, LLM & Voice Architecture

> Technical reference for product architects. Covers every model (local and cloud), the voice command system, and how everything connects.

---

## System Overview

CosmoOS runs a **hybrid AI architecture**: a local XPC daemon hosts on-device models (ASR, embeddings, function-calling LLM), while cloud APIs handle research, deep analysis, and generative tasks. The voice pipeline is a 3-tier system where 60% of commands never leave the device.

```
┌─────────────────────────────────────────────────────────────┐
│                        Main App                             │
│                                                             │
│  VoiceEngine ─► VoiceCommandPipeline ─► AtomRepository      │
│       │              │                                      │
│       │         ┌────┴─────────────────┐                    │
│       │         │    Tier Routing       │                    │
│       │         │  T0: PatternMatcher   │                    │
│       │         │  T1: FunctionGemma    │                    │
│       │         │  T2: Claude API       │                    │
│       │         └──────────────────────┘                    │
│       │                                                     │
│  ┌────┴──────────────────────────┐                          │
│  │     DaemonXPCClient           │  ◄── XPC IPC ──┐        │
│  │  embed(), sendAudioChunk(),   │                 │        │
│  │  generateToolCall()           │                 │        │
│  └───────────────────────────────┘                 │        │
│                                                     │        │
│  Cloud APIs:                                        │        │
│  ├─ ResearchService (Claude via OpenRouter)          │        │
│  ├─ PerplexityService (Perplexity sonar)             │        │
│  ├─ GeminiSynthesisEngine (Gemini 3 Flash)           │        │
│  └─ PolishEngine (Gemini 3 Flash)                    │        │
└─────────────────────────────────────────────────────┼────────┘
                                                      │
┌─────────────────────────────────────────────────────┴────────┐
│                  CosmoVoiceDaemon (LaunchAgent)               │
│                  com.cosmo.voicedaemon                        │
│                                                               │
│  Models in RAM:                                               │
│  ├─ WhisperKit base (~140MB) ─── Streaming ASR                │
│  ├─ FunctionGemma 270M (~550MB) ─ Voice command dispatch      │
│  ├─ nomic-embed-text-v1.5 (~500MB) ─ 256d embeddings         │
│  └─ AXContextService ─── Accessibility screen capture         │
│                                                               │
│  Lazy-loaded:                                                 │
│  └─ WhisperKit large-v3 (~3GB) ── Batch transcription         │
└───────────────────────────────────────────────────────────────┘
```

---

## Local Models (On-Device via Daemon)

All local models run inside `CosmoVoiceDaemon`, a persistent LaunchAgent process. The main app communicates via XPC (`DaemonXPCClient.shared`). Models stay hot in RAM across app restarts.

### WhisperKit — Speech Recognition

| Property | Value |
|----------|-------|
| Model | WhisperKit `base` (OpenAI Whisper) |
| RAM | ~140MB |
| Latency | ~30ms per audio chunk |
| Format | 16kHz mono Float32 |
| Role | Streaming ASR (L1) |

**How it works:** Audio from the microphone is chunked and sent to the daemon via `DaemonXPCClient.sendAudioChunk()`. The daemon accumulates samples in a rolling buffer and runs WhisperKit inference. Partial transcripts are polled by the main app via `pollL1ASRChunks()`, which returns `L1TranscriptChunk` objects (text, isFinal, confidence, timestamp). When recording stops, a final pass over the full session audio produces the definitive transcript.

**L2 fallback:** WhisperKit `large-v3` (~3GB) is lazy-loaded only when high-accuracy batch transcription is needed (e.g., YouTube audio fallback). Loaded via `DaemonXPCClient.preloadL2()`, unloaded to reclaim RAM.

**Files:**
- `Daemon/CosmoVoiceDaemon.swift` — WhisperKitASREngine (lines 1500-1656)
- `Daemon/DaemonXPCClient.swift` — ASR methods (lines 312-549)
- `Voice/ASR/L1StreamingASR.swift` — Main app streaming interface

### FunctionGemma 270M — Voice Command Dispatch

| Property | Value |
|----------|-------|
| Model | `functiongemma-270m-it-MLX-bf16` |
| RAM | ~550MB |
| Latency | <300ms |
| Temperature | 0.0 (deterministic) |
| Role | Tier 1 voice command interpretation |

**How it works:** Takes a voice transcript + context and outputs a structured function call. This is NOT a reasoning model — it's a pure dispatcher that maps natural language to CosmoOS actions.

**Output format:**
```
<start_function_call>call:create_atom{type:idea,title:hooks that convert}<end_function_call>
```

**Available functions:** `create_atom`, `update_atom`, `delete_atom`, `search_atoms`, `batch_create`, `navigate`, `query_level_system`, `start_deep_work`, `stop_deep_work`, `extend_deep_work`, `log_workout`, `trigger_correlation_analysis`

**Loading:** Downloads from HuggingFace cache on first run. Includes LoRA adapter fine-tuned for CosmoOS actions. System prompt is pre-cached (KV cache warmup) for faster first inference.

**Files:**
- `AI/MicroBrain/FunctionGemmaEngine.swift` — Model wrapper (lines 30-317)
- `AI/MicroBrain/MicroBrainOrchestrator.swift` — Tier routing (lines 85-211)

### nomic-embed-text-v1.5 — Text Embeddings

| Property | Value |
|----------|-------|
| Model | nomic-embed-text-v1.5 |
| Dimensions | 256 (Matryoshka truncation from native 768) |
| RAM | ~500MB |
| Latency | ~50ms per text |
| Role | Semantic search, similarity matching |

**How it works:** All text in CosmoOS (atoms, transcripts, ideas) is embedded and stored in a local SQLite vector database. Search uses HNSW indexing via `sqlite-vec` extension, with brute-force cosine similarity as fallback.

**API:** `DaemonXPCClient.shared.embed(text:)` returns `[Float]` (256 dimensions). Batch embedding via `embedBatch(texts:)`.

**Database schema:**
```sql
vectors (id, embedding BLOB)
vector_metadata (id, vector_id, entity_type, entity_id, entity_uuid, text_hash, chunk_index)
vector_texts (id, text_hash, text_content, vector_id)
```

**Deduplication:** SHA1 hash of text content prevents duplicate embeddings.

**Files:**
- `AI/VectorDatabase.swift` — Full vector DB implementation (lines 78-702)
- `Daemon/DaemonXPCClient.swift` — Embedding methods (lines 266-310)

### AXContextService — Screen Context Capture

Runs in the daemon with Accessibility API access (not available to the sandboxed main app). Captures URLs, selected text, and visible text from Chrome, Safari, VS Code, Terminal, and Finder. Used by TelepathyEngine for context-aware voice commands.

---

## Cloud Models (API Calls)

### Claude Sonnet 4.5 — Deep Analysis & Generation

| Property | Value |
|----------|-------|
| Provider | Anthropic via OpenRouter |
| Model ID | `anthropic/claude-sonnet-4.5` |
| Endpoint | `https://openrouter.ai/api/v1/chat/completions` |
| Auth | `APIKeys.openRouter` (Keychain) |
| Role | Research analysis, content blueprints, hook generation |

**Accessed via:** `ResearchService.shared.analyzeContent(prompt:)` — used throughout the codebase for any task requiring reasoning.

**Consumers:**
- `SwipeAnalyzer.deepAnalyze()` — Enhanced swipe analysis (frameworks, emotional arc)
- `IdeaInsightEngine.generateBlueprint()` — Content blueprint generation
- `IdeaInsightEngine.generateHooks()` — Hook variant generation
- `CosmoAIFocusModeViewModel` — Think mode and Research mode conversations

**Files:**
- `Cosmo/ResearchService.swift` — HTTP client (lines 181-224)
- `AI/BigBrain/ClaudeAPIClient.swift` — Alternative client used by voice pipeline

### Claude Sonnet 4 — Voice Pipeline (Tier 2)

| Property | Value |
|----------|-------|
| Provider | Anthropic via OpenRouter |
| Model ID | `anthropic/claude-sonnet-4` |
| Role | Generative voice commands (1% of traffic) |
| Timeout | 30 seconds |

**Accessed via:** `ClaudeAPIClient` in `AI/BigBrain/`. Used exclusively by the voice pipeline's Tier 2 for generative tasks (idea generation, content synthesis, pattern analysis).

**Key methods:**
- `generate(prompt:maxTokens:temperature:)`
- `analyzeCorrelations(dimensions:dataContext:)`
- `generateContentIdeas(topic:context:count:)`
- `synthesizeJournalInsights(entries:timeframe:)`

### Perplexity Sonar — Web Research

| Property | Value |
|----------|-------|
| Model | `sonar-medium-online` |
| Endpoints | OpenRouter proxy AND direct Perplexity API |
| Role | Web search with citations |

**Two access paths:**
1. `ResearchService.shared.performResearch(query:searchType:)` — Via OpenRouter (supports web, reddit, academic, news search types)
2. `PerplexityService.shared.research(query:)` — Direct Perplexity API with citation extraction

**Returns:** Summary text, findings array, citations with URLs, related questions.

**Files:**
- `Cosmo/ResearchService.swift` — OpenRouter path (lines 23-178)
- `AI/PerplexityService.swift` — Direct path (lines 43-103)

### Gemini 3 Flash — Synthesis & Polish

| Property | Value |
|----------|-------|
| Provider | Google via OpenRouter |
| Model ID | `google/gemini-3-flash-preview` |
| Fallback | `google/gemini-2.5-pro-preview` |
| Role | Creative synthesis, writing polish |

**Consumers:**
1. **GeminiSynthesisEngine** — Cross-domain creative synthesis with streaming support. Extracts suggested actions (create idea, add to swipe file, create connection) from responses.
2. **PolishEngine** — Takes `WritingAnalysis` results (readability scores, passive voice instances) and generates specific rewrite suggestions via Gemini.

**Files:**
- `AI/GeminiSynthesisEngine.swift` — Streaming synthesis (lines 74-329)
- `AI/PolishEngine.swift` — Writing suggestions

---

## On-Device NLP (No Model, No API)

These use Apple's `NaturalLanguage` framework directly — no daemon, no cloud, instant results.

### NLTagger Usage

| Engine | NLTagger Scheme | Purpose |
|--------|----------------|---------|
| SwipeAnalyzer | `.sentimentScore` | Emotional arc per sentence |
| IdeaInsightEngine | `.lexicalClass` | Topic keyword extraction (nouns, proper nouns) |
| IdeaInsightEngine | `.sentimentScore` | Quick sentiment for ideas |
| JournalRouter | `.sentimentScore` | Journal mood classification |
| JournalRouter | `.nameType` | Named entity extraction |
| JournalRouter | `.lemma` | Topic extraction via lemmatization |
| WritingAnalyzer | `.lexicalClass` | Adverb detection, passive voice detection |
| IntentClassifier | Centroid embeddings | Intent classification via cosine similarity |

### WritingAnalyzer — Pure Algorithmic

Hemingway-style readability analysis. Computes Flesch-Kincaid score, Gunning Fog grade level, sentence complexity, passive voice %, adverb density. Zero API calls.

**File:** `AI/WritingAnalyzer.swift`

### TaskRecommendationEngine — Heuristic Scoring

Ranks tasks by deadline pressure (35%), energy match (25%), priority (20%), recency (10%), time fit, and project alignment. No AI involved.

**File:** `AI/TaskRecommendationEngine.swift`

### GhostSuggestionEngine — Content Suggestions

Generates suggestions for Connection (document) sections by scoring snippets from related atoms. Uses keyword matching + title matching + structural indicators. Confidence threshold: 60%. Deduplicates by 70% word overlap.

**File:** `AI/GhostSuggestionEngine.swift`

---

## Voice Command System

### Architecture: 3-Tier Micro-Brain

```
Voice Input (microphone or text)
    │
    ▼
┌──────────────────────────────────────────┐
│  VoiceEngine                             │
│  ├─ Audio capture (AVAudioEngine)        │
│  ├─ ASR via daemon (WhisperKit base)     │
│  └─ Context snapshot (section, editing   │
│     atom, selected atoms, project)       │
└────────────────┬─────────────────────────┘
                 │ transcript + VoiceContext
                 ▼
┌──────────────────────────────────────────┐
│  VoiceCommandPipeline                    │
│                                          │
│  Step 1: PatternMatcher.match()          │
│    ├─ Match? → Execute immediately       │
│    └─ No match? → Continue               │
│                                          │
│  Step 2: IntentClassifier.classify()     │
│    └─ Returns VoiceIntent + isGenerative │
│                                          │
│  Step 3: Tier Selection                  │
│    ├─ Generative? → Tier 2 (Claude)      │
│    └─ Action?     → Tier 1 (FunctionGemma│
│                                          │
│  Step 4: Execute ParsedAction            │
│    ├─ .create  → AtomRepository.create() │
│    ├─ .update  → AtomRepository.update() │
│    ├─ .delete  → AtomRepository.delete() │
│    ├─ .search  → AtomSearchEngine        │
│    ├─ .navigate → NotificationCenter     │
│    ├─ .query   → LevelSystemQueryHandler │
│    └─ .batch   → Recursive execution     │
└──────────────────────────────────────────┘
```

### Tier 0: Pattern Matching (<50ms, ~60% of commands)

Regex-based instant matching. 50+ static patterns across categories:

| Category | Examples | Patterns |
|----------|---------|----------|
| Navigation | "canvas", "plannerum", "home" | ~15 |
| Idea creation | "idea about X", "thread idea: X" | ~8 |
| Task creation | "task to X", "remind me to X" | ~6 |
| Status updates | "mark it done", "high priority" | ~8 |
| Search | "find X", "search for X" | ~4 |
| Thinkspace | "create thinkspace called X" | ~4 |
| Deep work | "start deep work for 2 hours" | ~3 |
| Level queries | "what's my level", "XP today" | ~6 |

**Smart filtering:** Patterns that detect time expressions or project references bail out to Tier 1 for more nuanced parsing.

**Metadata injection:** Patterns can inject metadata directly. For example, "thread idea: hooks that convert" injects `{"contentFormat": "thread", "captureSource": "voice"}` which routes through `AtomRepository.createEnrichedIdea()`.

**File:** `Voice/Pipeline/PatternMatcher.swift`

### Tier 1: FunctionGemma 270M (<300ms, ~39% of commands)

Handles standard commands that patterns can't cover. The 270M model outputs structured function calls parsed by `FunctionCallParser`.

**Example flow:**
```
User: "Add a task to review the analytics dashboard by Friday"
  → FunctionGemma output: call:create_atom{type:task,title:Review analytics dashboard,deadline:friday}
  → Parsed to: ParsedAction(action: .create, atomType: .task, title: "Review analytics dashboard", metadata: {...})
  → Executed: AtomRepository.create(type: .task, ...)
```

**Files:**
- `AI/MicroBrain/FunctionGemmaEngine.swift` — Model wrapper
- `AI/MicroBrain/MicroBrainOrchestrator.swift` — Routing logic
- `Voice/Models/FunctionCallParser.swift` — Output parsing

### Tier 2: Claude API (1-5s, ~1% of commands)

Reserved for generative tasks: idea generation, content synthesis, correlation analysis. Routes via `ClaudeAPIClient` in `AI/BigBrain/`.

**Triggers:** VoiceIntent with `isGenerative = true` — includes `generateIdeas`, `generateContent`, `synthesizeConnections`, `analyzePattern`.

### TelepathyEngine — Real-Time Context

Runs background vector searches during voice input. Every ~50 tokens of partial transcript triggers a "shadow search" across all entity types, building a `HotContext` with related connections, projects, ideas, and tasks. 100ms debounce.

**File:** `AI/TelepathyEngine.swift`

### Voice UI Surface

`VoicePillWindow` — Floating pill at top of screen.

| Mode | Size | Trigger |
|------|------|---------|
| Idle | 36x180px | Hover trigger zone (top-center) |
| Listening | 36x180px | Space (push-to-talk) |
| Typing | 44x320px | Cmd+Shift+C or Option+C |

Features: 24-bar waveform visualization (60fps), URL paste detection with glow effect, auto-hide after 4s idle. Glass morphism background.

**File:** `Voice/VoiceUI/VoicePillWindow.swift`

---

## Data Flow Through the System

### Key Data Types

| Type | Purpose | File |
|------|---------|------|
| `VoiceAtom` | Voice command state (transcript, intent, tier, timing) | `Voice/Models/VoiceAtom.swift` |
| `VoiceContext` | App state snapshot (section, editing atom, project) | `Voice/Models/VoiceAtom.swift` |
| `VoiceIntent` | Classified intent (38 types across capture/retrieval/generative/control) | `Voice/Models/VoiceAtom.swift` |
| `ParsedAction` | Bridge between LLM output and AtomRepository operations | `Voice/Models/ParsedAction.swift` |
| `VoiceAnyCodable` | Type-erased Codable for flexible JSON metadata | `Voice/Models/ParsedAction.swift` |
| `PatternMatchResult` | Tier 0 match output (action, type, title, metadata, confidence) | `Voice/Models/VoiceAtom.swift` |

### Example: "Reel idea about morning routines"

```
1. VoiceEngine.stopRecording()
   └─ WhisperKit transcribes: "reel idea about morning routines"

2. VoiceCommandPipeline.process(transcript, context)
   └─ Creates VoiceAtom

3. PatternMatcher.match()
   └─ Matches: ^(thread|reel|carousel|...)\\s+idea[\\s:]+(.+)$
   └─ Extracts: formatStr="reel", title="Morning Routines"
   └─ Returns PatternMatchResult(
        action: .create, atomType: .idea,
        title: "Morning Routines",
        metadata: {"contentFormat": "reel", "captureSource": "voice"}
      )

4. VoiceCommandPipeline.executeAction()
   └─ Detects .idea + contentFormat metadata
   └─ Routes to: AtomRepository.createEnrichedIdea(
        title: "Morning Routines",
        content: "Morning Routines",
        contentFormat: .reel,
        captureSource: "voice"
      )

5. createEnrichedIdea() internally:
   └─ Creates atom with IdeaMetadata(status: .spark, contentFormat: .reel)
   └─ Runs IdeaInsightEngine.quickEnrich() in background
       └─ NLTagger extracts topic keywords
       └─ VectorDatabase.search() finds matching swipes
       └─ Updates atom with suggestedFramework, matchingSwipeCount
   └─ Indexes in VectorDatabase

6. Returns Atom → VoiceResult.success
   └─ UI shows confirmation, voice pill auto-hides
```

### Example: "Give me viral content ideas for TikTok"

```
1. PatternMatcher → No match (generative request)

2. IntentClassifier.classify()
   └─ Detects "generate"/"ideas" keywords
   └─ Returns VoiceIntent.generateIdeas (isGenerative = true)

3. Tier selection → Tier 2 (Claude)

4. ClaudeAPIClient.generate(prompt)
   └─ POST to OpenRouter → Claude Sonnet 4
   └─ Prompt includes: current section, time of day, recent context
   └─ Returns synthesized content (3-5 idea suggestions)

5. VoiceResult.success with synthesizedContent
   └─ UI displays in conversation panel
```

---

## Intelligence Engines — How AI Is Consumed

### SwipeAnalyzer (SwipeFile/SwipeAnalyzer.swift)

Analyzes viral content patterns across 4 dimensions:

| Dimension | Method | Models | Output |
|-----------|--------|--------|--------|
| Hook analysis | Pattern matching + scoring | None (regex) | Hook text, type (14 types), score (0-10) |
| Emotional arc | `NLTagger.sentimentScore` per sentence | Apple NLP | `[EmotionDataPoint]` |
| Persuasion | Keyword pattern matching | None (regex) | 12 technique types detected |
| Framework | Structural pattern detection | None (heuristic) | 12 framework types |
| Deep analysis | `ResearchService.analyzeContent()` | Claude 4.5 | Enhanced framework + sections |

### IdeaInsightEngine (AI/IdeaInsightEngine.swift)

9-stage pipeline bridging swipe analysis to ideation:

| Stage | Method | Speed | Uses |
|-------|--------|-------|------|
| 1. quickInsight | NLTagger keywords + sentiment | <100ms | On-device NLP |
| 2. findMatchingSwipes | VectorDatabase.search() | ~200ms | Local embeddings |
| 3. recommendFrameworks | Tally + affinity scoring | <50ms | Local heuristics |
| 4. scoreFormats | Complexity + platform scoring | <50ms | Local heuristics |
| 5. generateBlueprint | ResearchService.analyzeContent() | 2-5s | Claude 4.5 |
| 6. generateHooks | ResearchService.analyzeContent() | 2-5s | Claude 4.5 |
| 7. findIdeasForSwipe | VectorDatabase.search() | ~200ms | Local embeddings |
| 8. quickEnrich | Stages 1-3 combined | <300ms | On-device |
| 9. fullAnalysis | All stages | 5-10s | Everything |

### CosmoAI Focus Mode (UI/FocusMode/CosmoAI/)

4-mode AI conversation interface:

| Mode | What it calls | Returns |
|------|-------------|---------|
| Think | `ResearchService.performResearch()` + connected atom context | Summary + findings |
| Research | `ResearchService.performResearch()` (web search) | Summary + citations |
| Recall | `VectorDatabase.search()` + `AtomRepository.search()` | Matching atoms + similarity scores |
| Act | Intent parsing → `AtomRepository.create()` or `TaskRecommendationEngine` | Action results |

### LivingIntelligenceEngine (AI/BigBrain/)

Background intelligence with 12-hour sync cycles. Detects new atoms since last sync, runs local `CausalityEngine`, then optionally calls Claude (via `SanctuaryOrchestrator.runAnalysis()`) if 5+ new atoms exist. Insights have a lifecycle: fresh → validated → established → stale → decaying → removed.

---

## URL Processing Pipeline

When a URL is captured (via voice pill paste or clipboard):

```
URL Input
    │
    ▼
SwipeURLClassifier.classify()
    │
    ├─ YouTube ─► YouTubeProcessor
    │              ├─ oEmbed metadata (title, author, duration)
    │              ├─ yt-dlp captions (fast, ~2s)
    │              └─ Audio transcription fallback (WhisperKit L2, ~30s)
    │
    ├─ X/Twitter ─► oEmbed embed fetcher (tweet text)
    │
    ├─ Instagram ─► Manual entry modal (no API access)
    │
    ├─ Threads ──► URL + metadata save (no public API)
    │
    ├─ Loom ────► oEmbed metadata + thumbnail
    │
    └─ Website ─► WebsiteCapture (screenshot + title)

    Then for all:
    ├─ VectorDatabase.index() (semantic embedding)
    ├─ IdeaInsightEngine.findIdeasForSwipe() (auto-link to existing ideas)
    └─ Save to GRDB + post notification
```

**Files:**
- `SwipeFile/SwipeURLClassifier.swift` — URL pattern detection (YouTube, X, Instagram, Threads, Loom)
- `SwipeFile/SwipeFileEngine.swift` — Orchestrator
- `SwipeFile/QuickCaptureProcessor.swift` — Command bar URL handler
- `Cosmo/YouTubeProcessor.swift` — Full YouTube processing
- `SwipeFile/YouTubeTranscriptFetcher.swift` — Page-scraping fallback (no dependencies)
- `Cosmo/ResearchProcessor.swift` — Multi-URL-type handler

**Dependency:** `yt-dlp` must be installed (`brew install yt-dlp`) for YouTube caption fetching. Falls back to WhisperKit audio transcription if unavailable.

---

## API Key Management

All keys stored in macOS Keychain under service `com.cosmo.apikeys` with environment variable fallback.

| Key | Service | Required For |
|-----|---------|-------------|
| `openRouter` | OpenRouter.ai | Claude, Gemini, Perplexity (via proxy) — **most features need this** |
| `perplexity` | Perplexity.ai | Direct Perplexity research (alternative to OpenRouter path) |
| `youtube` | YouTube Data API | Extended video metadata (optional, oEmbed works without) |
| `instagram` | Instagram API | Post performance tracking (optional) |

Supabase credentials (sync) are hardcoded in `config/APIKeys.swift`.

**File:** `config/APIKeys.swift`

---

## Daemon Lifecycle

| Event | Behavior |
|-------|----------|
| App launch | `DaemonInstaller.onAppLaunch()` → installs LaunchAgent plist, bootstraps daemon |
| Daemon start | Loads FunctionGemma, nomic-embed, WhisperKit base in parallel (~5s) |
| App quit | Daemon continues running (stays warm for next launch) |
| Option+Quit | Force stops daemon (reclaims ~1.2GB RAM) |
| First run | Downloads models to `~/Library/Caches/com.cosmo.voicedaemon/mlx` (~5GB) |
| Memory pressure | `flushKVCache()`, `unloadEmbeddingModel()`, `unloadLLM()` available |
| Health check | `DaemonXPCClient.healthCheck()` → (alive: Bool, ramUsageMB: Int64) |

**Files:**
- `Daemon/DaemonInstaller.swift` — Install, start, stop, bootstrap
- `Daemon/CosmoVoiceDaemon.swift` — Model loading and inference
- `Daemon/DaemonXPCClient.swift` — Main app XPC client

---

## What Works, What Doesn't

### Fully Functional

| System | Notes |
|--------|-------|
| Voice Tier 0 (Pattern Matching) | 50+ patterns, <50ms |
| Voice Tier 1 (FunctionGemma) | Atom CRUD, navigation, search |
| Voice Tier 2 (Claude) | Generative via OpenRouter |
| Streaming ASR | WhisperKit base via daemon |
| Text Embeddings | nomic-embed 256d + HNSW search |
| Swipe Analysis (on-device) | Hook, emotion, framework, persuasion |
| Swipe Analysis (deep) | Claude-powered enhanced analysis |
| Idea Insight Pipeline | All 9 stages operational |
| Writing Analysis | Flesch-Kincaid, passive voice, adverbs |
| Polish Engine | Gemini-powered rewrite suggestions |
| Task Recommendations | Heuristic scoring (no AI) |
| Perplexity Research | Web search with citations |
| Gemini Synthesis | Streaming creative synthesis |
| CosmoAI Focus Mode | 4-mode conversation (Think/Research/Recall/Act) |
| TelepathyEngine | Real-time shadow search during voice input |
| YouTube Transcripts | yt-dlp caption fetching |
| URL Classification | 10 platform types detected |

### Stubbed / Non-Functional

| System | Issue | Location |
|--------|-------|----------|
| `LocalLLM.shared.generate()` | Returns empty string | `AI/LegacyStubs.swift:87` |
| YouTube summary generation | Calls LocalLLM (stub) | `Cosmo/YouTubeProcessor.swift` |
| YouTube formatted transcript | Calls LocalLLM (stub) | `Cosmo/YouTubeProcessor.swift` |
| YouTube section breakdown | Calls LocalLLM (stub) | `Cosmo/YouTubeProcessor.swift` |
| `AIWritingAssistant` | Returns original text | UI stub only |
| `MLXEmbeddingService` | Returns empty array | `AI/LegacyStubs.swift:256` |
| `ResponseCache` | No-op | `AI/LegacyStubs.swift:147` |

> **Note:** YouTube transcript *fetching* works. Only summarization and formatting are stubbed because they relied on a now-removed local LLM. These should be re-routed through `ResearchService` (Claude) or `GeminiSynthesisEngine`.
