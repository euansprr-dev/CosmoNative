# CosmoOS Voice System - Micro-Brain Architecture v3

> **Last Updated**: December 2025
>
> **Design Principle**: 300ms or bust. Everything flows through Atoms. Maximum RAM efficiency.

---

## Executive Summary

The CosmoOS voice system uses a **Micro-Brain Architecture** - a single, purpose-built model for voice command dispatch with complex reasoning offloaded to cloud APIs.

```
┌─────────────────────────────────────────────────────────────────┐
│                    THE MICRO-BRAIN ARCHITECTURE                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Voice → Transcript → VoiceAtom → Function Call → Atom          │
│                                                                  │
│  95% of commands: < 300ms (FunctionGemma 270M)                  │
│  99% of commands: < 500ms                                        │
│  Generative: 1-5s (Claude API)                                  │
│                                                                  │
│  RAM Budget: ~533MB (vs 3.3GB old stack)                        │
│  Models: 1 local + 1 cloud API                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [The 3-Tier Model Stack](#the-3-tier-model-stack)
3. [FunctionGemma 270M - The Micro-Brain](#functiongemma-270m---the-micro-brain)
4. [Claude API - The Big Brain](#claude-api---the-big-brain)
5. [Function Call Protocol](#function-call-protocol)
6. [Unified Pipeline Design](#unified-pipeline-design)
7. [The VoiceAtom Flow](#the-voiceatom-flow)
8. [Memory Profile](#memory-profile)
9. [Complete File Structure](#complete-file-structure)
10. [Training Data Specification](#training-data-specification)

---

## Architecture Overview

### The Micro-Brain Philosophy

**FunctionGemma is a dispatcher, not a thinker.**

The Micro-Brain (FunctionGemma 270M) interprets user intent and outputs a single function call. It never reasons, explains, or generates content. All complex cognition is offloaded to Claude API (the "Big Brain").

```
┌─────────────────────────────────────────────────────────────────┐
│                     MICRO-BRAIN DISPATCH                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   FunctionGemma (Micro-Brain)          Claude (Big Brain)       │
│   ─────────────────────────            ─────────────────        │
│   • Interprets voice commands          • Correlation analysis   │
│   • Outputs function calls             • Content synthesis      │
│   • Routes to correct tool             • Pattern recognition    │
│   • NEVER reasons or explains          • Complex multi-step     │
│   • ~533MB RAM, <300ms                 • Cloud API, 1-5s        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### RAM Comparison

| Configuration | RAM Usage | Notes |
|--------------|-----------|-------|
| **Old Stack** (Qwen 0.5B + Hermes 3B) | ~3.3 GB | Crashed on 16GB M4 |
| **New Stack** (FunctionGemma 270M) | ~533 MB | Stable, 84% reduction |

---

## The 3-Tier Model Stack

### Tier 0: Pattern Matching (<50ms)
```
Coverage: 60% of commands
Latency: <50ms
No model involved

Examples:
- "Create idea called X" → regex → Atom
- "New task X" → regex → Atom
- "Delete that" → context → Atom.delete()
- "Open projects" → navigation
- "What's my level?" → query_level_system
```

### Tier 1: FunctionGemma 270M (<300ms)
```
Coverage: 39% of commands
Latency: <300ms
Model: FunctionGemma 270M, fine-tuned on CosmoOS commands
RAM: ~533MB peak

This model handles:
- Ambiguous entity extraction
- Time expression parsing
- Multi-entity commands
- Project-specific routing
- All function dispatch
```

### Tier 2: Claude Sonnet 4.5 (1-5s)
```
Coverage: 1% of commands
Latency: 1-5s
API: Claude via OpenRouter

ONLY for:
- "Give me 5 content ideas about X"
- "Find correlations between sleep and productivity"
- "Synthesize insights from my journals"
- Complex multi-step reasoning
```

### Model Selection Logic

```swift
func selectTier(_ voiceAtom: VoiceAtom) -> ModelTier {
    // Tier 0: Pattern matched successfully
    if voiceAtom.patternMatchResult != nil {
        return .pattern
    }

    // Tier 2: Generative intent → Claude API
    if voiceAtom.intent?.isGenerative == true {
        return .claude
    }

    // Tier 1: Everything else → FunctionGemma
    return .functionGemma
}
```

---

## FunctionGemma 270M - The Micro-Brain

### Model Configuration

```
Base Model: lmstudio-community/functiongemma-270m-it-MLX-bf16
Fine-tuned: LoRA adapter (CosmoOS-specific)
Parameters: 268M (0.315% trainable via LoRA = 844K params)
Quantization: BF16 (MLX native)
RAM Usage: 515MB model + 18MB KV cache = 533MB peak
Inference: ~145 tokens/sec on M4
```

### Output Format

FunctionGemma outputs a single function call in this format:

```
<start_function_call>call:FUNCTION_NAME{param:<escape>value<escape>,param2:<escape>value2<escape>}<end_function_call>
```

### Available Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `create_atom` | Create new Atom | atom_type, title, body, metadata, links |
| `update_atom` | Update existing Atom | target, title, body, metadata, links |
| `delete_atom` | Soft-delete Atom | target |
| `search_atoms` | Query Atoms | query, types, filters |
| `batch_create` | Create multiple Atoms | items[] |
| `navigate` | UI navigation | destination |
| `query_level_system` | Level system queries | query_type, dimension |
| `start_deep_work` | Start focus session | duration_minutes, pomodoro_mode |
| `stop_deep_work` | End focus session | - |
| `extend_deep_work` | Extend focus session | additional_minutes |
| `log_workout` | Log workout | workout_type, duration_minutes |
| `trigger_correlation_analysis` | Trigger Claude analysis | dimensions, trigger_reason |

### Example Outputs

```
Input: "Create idea about marketing automation"
Output: <start_function_call>call:create_atom{atom_type:<escape>idea<escape>,title:<escape>marketing automation<escape>}<end_function_call>

Input: "What's my level?"
Output: <start_function_call>call:query_level_system{query_type:<escape>levelStatus<escape>}<end_function_call>

Input: "Start deep work for 2 hours"
Output: <start_function_call>call:start_deep_work{duration_minutes:<escape>120<escape>}<end_function_call>

Input: "Task for Michael about the proposal at 3pm"
Output: <start_function_call>call:create_atom{atom_type:<escape>task<escape>,title:<escape>the proposal<escape>,metadata:<escape>{"startTime":"15:00"}<escape>,links:<escape>[{"type":"project","query":"Michael"}]<escape>}<end_function_call>
```

### Fine-Tuning Details

```
Training Examples: 14,082
Validation Examples: 1,565
Iterations: 300
Final Validation Loss: 0.167
LoRA Rank: 8
LoRA Alpha: 16
LoRA Layers: 8
Learning Rate: 2e-5

Adapter Location: Models/FunctionGemma/adapters/cosmo-v1/
```

---

## Claude API - The Big Brain

### Configuration

```swift
// ClaudeAPIClient.swift
private let baseURL = "https://openrouter.ai/api/v1/chat/completions"
private let modelId = "anthropic/claude-sonnet-4"
```

### Use Cases

| Trigger | Description | Frequency |
|---------|-------------|-----------|
| Generative Commands | "Give me 5 content ideas about X" | On-demand |
| Correlation Analysis | Cross-dimensional pattern detection | Nightly |
| Journal Insights | Deep reflection analysis | After 3+ entries |
| Content Synthesis | Framework creation, pattern analysis | On-demand |
| HRV Shift | Significant physiological change | Event-triggered |
| Streak Milestones | Achievement analysis | Event-triggered |

### Correlation Pipeline

```
Data Sources → FunctionGemma Trigger → Claude Analysis → Atom Storage
     │                 │                     │              │
     ├── Journal       ├── trigger_correlation_analysis    │
     ├── Sleep         │                     │              │
     ├── HRV           │                     ├── Generate   │
     ├── Content       │                     │   insights   │
     ├── Behavior      │                     │              │
     └── Streaks       └─────────────────────┴──────────────┘
                                                    │
                                                    ▼
                                        AtomRepository.create(
                                            type: .correlationInsight
                                        )
```

---

## Function Call Protocol

### FunctionCall Structure

```swift
struct FunctionCall: Codable, Sendable {
    let name: String
    let parameters: [String: AnyCodable]

    // Convenience accessors
    var atomType: AtomType?
    var title: String?
    var body: String?
    var metadata: [String: Any]?
    var links: [AtomLink]?
    var target: String?
    var queryType: String?
}
```

### ToolExecutor

```swift
actor ToolExecutor {
    func execute(_ call: FunctionCall) async throws -> ExecutionResult {
        switch call.name {
        case "create_atom":
            return try await executeCreate(call.parameters)
        case "update_atom":
            return try await executeUpdate(call.parameters)
        case "delete_atom":
            return try await executeDelete(call.parameters)
        case "search_atoms":
            return try await executeSearch(call.parameters)
        case "batch_create":
            return try await executeBatch(call.parameters)
        case "navigate":
            return try await executeNavigate(call.parameters)
        case "query_level_system":
            return try await executeQuery(call.parameters)
        case "start_deep_work":
            return try await executeStartDeepWork(call.parameters)
        case "stop_deep_work":
            return try await executeStopDeepWork()
        case "extend_deep_work":
            return try await executeExtendDeepWork(call.parameters)
        case "log_workout":
            return try await executeLogWorkout(call.parameters)
        case "trigger_correlation_analysis":
            return try await triggerClaudeAnalysis(call.parameters)
        default:
            throw ToolExecutorError.unknownFunction(call.name)
        }
    }
}
```

---

## Unified Pipeline Design

### VoiceCommandPipeline

```swift
actor VoiceCommandPipeline {
    // Dependencies
    private let patternMatcher = PatternMatcher()
    private let microBrain = MicroBrainOrchestrator.shared
    private let bigBrain = ClaudeAPIClient.shared
    private let atomRepo = AtomRepository.shared

    func process(_ transcript: String, context: VoiceContext) async -> VoiceResult {
        // Step 1: Create VoiceAtom
        var voiceAtom = VoiceAtom(
            transcript: transcript,
            context: context,
            timestamp: Date()
        )

        // Step 2: Try pattern matching (< 50ms)
        if let result = patternMatcher.match(transcript) {
            voiceAtom.tier = .pattern
            voiceAtom.patternMatchResult = result
            return await execute(voiceAtom)
        }

        // Step 3: Classify intent (< 20ms)
        voiceAtom.intent = await IntentClassifier.shared.classify(transcript)

        // Step 4: Select tier
        voiceAtom.tier = selectTier(voiceAtom)

        // Step 5: Route to appropriate model
        switch voiceAtom.tier {
        case .pattern:
            fatalError("Already handled above")

        case .functionGemma:
            let functionCall = try await microBrain.process(transcript, context: context)
            voiceAtom.parsedAction = functionCall.toParsedAction()

        case .claude:
            return await routeToClaudeForSynthesis(voiceAtom)

        default:
            break
        }

        // Step 6: Execute
        return await execute(voiceAtom)
    }
}
```

### Latency Breakdown

```
Voice Command: "Create task call mom at 2pm"

├─ ASR (WhisperKit streaming): ~100ms (parallel with speaking)
├─ Pattern Match attempt: ~5ms (miss - has time expression)
├─ Intent Classification: ~15ms
├─ Tier Selection: ~1ms (→ functionGemma)
├─ FunctionGemma Generation: ~200ms
├─ Function Call Parsing: ~2ms
├─ ToolExecutor.execute(): ~20ms
├─ UI Notification: ~10ms
└─ TOTAL: ~353ms
```

---

## The VoiceAtom Flow

### VoiceAtom Definition

```swift
struct VoiceAtom: Sendable, Identifiable {
    let id: UUID
    let transcript: String
    let context: VoiceContext
    let timestamp: Date

    // Classification
    var intent: VoiceIntent?
    var confidence: Double = 0.0

    // Processing state
    var tier: ModelTier = .unknown
    var patternMatchResult: PatternMatchResult?
    var parsedAction: ParsedAction?

    // Result
    var resultAtoms: [Atom] = []
    var error: String?

    // Timing metrics
    var asrDurationMs: Int = 0
    var classificationDurationMs: Int = 0
    var modelDurationMs: Int = 0
    var executionDurationMs: Int = 0
}
```

### ModelTier Enum

```swift
enum ModelTier: String, Sendable, Codable {
    case unknown = "unknown"
    case pattern = "pattern"             // Tier 0: Regex matching (<50ms)
    case functionGemma = "functiongemma" // Tier 1: FunctionGemma 270M (<300ms)
    case claude = "claude"               // Tier 2: Claude Sonnet 4.5 (1-5s)

    var targetLatencyMs: Int {
        switch self {
        case .unknown: return 0
        case .pattern: return 50
        case .functionGemma: return 300
        case .claude: return 5000
        }
    }
}
```

### Flow Diagram

```
User speaks: "Idea for Michael about the new logo"
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ VoiceAtom created                                               │
│ {                                                                │
│   transcript: "Idea for Michael about the new logo",            │
│   context: { section: .ideas, currentProject: nil }             │
│ }                                                                │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ Pattern Match: MISS (project reference detected)                │
│ Intent Classification: .createIdea (0.92)                       │
│ Tier Selection: .functionGemma                                  │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ FunctionGemma Output:                                           │
│ <start_function_call>call:create_atom{                          │
│   atom_type:<escape>idea<escape>,                               │
│   title:<escape>the new logo<escape>,                           │
│   links:<escape>[{"type":"project","query":"Michael"}]<escape>  │
│ }<end_function_call>                                            │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ ToolExecutor.executeCreate()                                    │
│                                                                  │
│ 1. Parse function call parameters                               │
│ 2. Resolve project link: "Michael" → fuzzy match → uuid         │
│ 3. AtomRepository.create(type: .idea, title: "the new logo",   │
│                          links: [.project(uuid)])               │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
           Atom saved, UI notified
              TOTAL: ~320ms
```

---

## Memory Profile

### Target: 16GB M4 MacBook

```
┌─────────────────────────────────────────────────────────────────┐
│                      RAM BUDGET                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FunctionGemma 270M (fine-tuned):     ~533 MB                   │
│  Nomic Embeddings:                    ~500 MB                   │
│  WhisperKit Base (ASR):               ~500 MB                   │
│  ──────────────────────────────────────────────────             │
│  TOTAL MODEL RAM:                     ~1.5 GB                   │
│  Headroom for OS + Apps:              ~14.5 GB                  │
│                                                                  │
│  Result: Stable operation, zero crashes                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Memory Profiling Results

| Metric | Value |
|--------|-------|
| Model size in Metal | 515 MB |
| Peak during inference | 533 MB |
| Target budget | 550 MB |
| **Status** | ✓ Within Budget |

---

## Complete File Structure

```
CosmoOS/
├── AI/
│   ├── MicroBrain/
│   │   ├── FunctionGemmaEngine.swift        # Model wrapper (~440 lines)
│   │   ├── FunctionCallParser.swift         # Parse FunctionGemma output (~150 lines)
│   │   ├── FunctionCall.swift               # Function call model (~100 lines)
│   │   ├── ToolExecutor.swift               # Execute function calls (~400 lines)
│   │   └── MicroBrainOrchestrator.swift     # Main orchestrator (~250 lines)
│   │
│   ├── BigBrain/
│   │   ├── ClaudeAPIClient.swift            # Claude via OpenRouter (~480 lines)
│   │   ├── CorrelationRequestBuilder.swift  # Build Claude prompts (~200 lines)
│   │   └── InsightProcessor.swift           # Process Claude responses (~150 lines)
│   │
│   ├── Classification/
│   │   └── IntentClassifier.swift           # Embedding-based (~400 lines)
│   │
│   └── Search/
│       ├── VectorDatabase.swift             # Vector storage (~500 lines)
│       └── SemanticSearch.swift             # Similarity search (~200 lines)
│
├── Voice/
│   ├── Pipeline/
│   │   ├── VoiceCommandPipeline.swift       # THE pipeline (~400 lines)
│   │   ├── PatternMatcher.swift             # Tier 0 matching (~300 lines)
│   │   └── VoiceContext.swift               # Context snapshot (~100 lines)
│   │
│   ├── Models/
│   │   ├── VoiceAtom.swift                  # Voice command model (~415 lines)
│   │   ├── ParsedAction.swift               # LLM output model (~180 lines)
│   │   └── VoiceIntent.swift                # Intent enum (~100 lines)
│   │
│   ├── ASR/
│   │   ├── ASRCoordinator.swift             # ASR coordination (~300 lines)
│   │   └── WhisperKitASR.swift              # WhisperKit wrapper (~250 lines)
│   │
│   ├── Engine/
│   │   ├── VoiceEngine.swift                # Recording control (~400 lines)
│   │   ├── AudioCapture.swift               # Mic input (~300 lines)
│   │   └── HotkeyManager.swift              # SPACE key (~200 lines)
│   │
│   └── LevelSystem/
│       ├── LevelSystemQueryHandler.swift    # Query execution (~300 lines)
│       └── LevelSystemVoicePatterns.swift   # Level query patterns (~200 lines)
│
├── Models/
│   └── FunctionGemma/
│       ├── adapters/
│       │   └── cosmo-v1/
│       │       ├── adapters.safetensors     # LoRA weights (~3.4 MB)
│       │       └── adapter_config.json      # LoRA config
│       └── CosmoFunctionGemmaConfig.swift   # Swift config (~30 lines)
│
├── Daemon/
│   ├── CosmoVoiceDaemon.swift               # XPC service (~600 lines)
│   └── DaemonXPCClient.swift                # App client (~400 lines)
│
├── Data/
│   └── Repositories/
│       └── AtomRepository.swift             # THE repository (~400 lines)
│
├── config/
│   └── APIKeys.swift                        # Keychain + env keys (~100 lines)
│
└── scripts/
    ├── finetune_functiongemma.py            # Fine-tuning script (~315 lines)
    ├── generate_training_data.py            # Data generation (~500 lines)
    ├── lora_config.yaml                     # LoRA configuration
    └── training_data/
        ├── train.jsonl                      # 14,082 examples
        └── valid.jsonl                      # 1,565 examples

TOTAL: ~25 core files, ~7,500 lines
```

---

## Training Data Specification

### Dataset Summary

| Category | Count | Description |
|----------|-------|-------------|
| Simple Creation | 4,000 | Basic idea/task/project creation |
| Project-Specific | 2,500 | Routing to project inboxes |
| Timed Creation | 2,000 | Time expressions and scheduling |
| Modification | 1,500 | Updates, status changes, priority |
| Queries (Level System) | 2,000 | XP, streaks, badges, health |
| Deep Work | 1,000 | Start/stop/extend focus |
| Journal | 1,000 | Gratitude, mood, learning |
| Content | 500 | Pipeline, performance |
| Batch/Brain Dump | 500 | Multiple items |
| **TOTAL** | **15,647** | |

### Training Data Format

```json
{
  "messages": [
    {
      "role": "developer",
      "content": "You are FunctionGemma, the CosmoOS Micro-Brain. You interpret user voice commands and output exactly ONE function call.\nYou NEVER reason, explain, or generate text. You ONLY output function calls in the format:\n<start_function_call>call:FUNCTION_NAME{params}<end_function_call>\n\nAvailable functions: create_atom, update_atom, delete_atom, search_atoms, batch_create, navigate, query_level_system, start_deep_work, stop_deep_work, extend_deep_work, log_workout, trigger_correlation_analysis"
    },
    {
      "role": "user",
      "content": "Create task call mom at 2pm"
    },
    {
      "role": "model",
      "content": "<start_function_call>call:create_atom{atom_type:<escape>task<escape>,title:<escape>Call mom<escape>,metadata:<escape>{\"startTime\":\"14:00\"}<escape>}<end_function_call>"
    }
  ]
}
```

### Sample Training Examples

```jsonl
{"messages":[...,"user":"Idea for Michael about marketing","model":"<start_function_call>call:create_atom{atom_type:<escape>idea<escape>,title:<escape>marketing<escape>,links:<escape>[{\"type\":\"project\",\"query\":\"Michael\"}]<escape>}<end_function_call>"]}
{"messages":[...,"user":"What's my level?","model":"<start_function_call>call:query_level_system{query_type:<escape>levelStatus<escape>}<end_function_call>"]}
{"messages":[...,"user":"Start deep work for 2 hours","model":"<start_function_call>call:start_deep_work{duration_minutes:<escape>120<escape>}<end_function_call>"]}
{"messages":[...,"user":"Mark as complete","model":"<start_function_call>call:update_atom{target:<escape>context<escape>,metadata:<escape>{\"status\":\"completed\"}<escape>}<end_function_call>"]}
{"messages":[...,"user":"Delete that","model":"<start_function_call>call:delete_atom{target:<escape>context<escape>}<end_function_call>"]}
```

---

## Success Metrics

| Metric | Old Stack | Micro-Brain | Improvement |
|--------|-----------|-------------|-------------|
| RAM Usage | ~3.3 GB | ~533 MB | **84% reduction** |
| P50 Latency | ~1000ms | ~200ms | **5x faster** |
| P95 Latency | ~2000ms | ~350ms | **6x faster** |
| P99 Latency | ~6000ms | ~500ms | **12x faster** |
| Model Count | 2 local + 1 API | 1 local + 1 API | Simplified |
| Cold Start | ~5s | ~2s | 2.5x faster |
| Crash Rate | Occasional | None | **Zero crashes** |
| Accuracy | ~90% | ~95% | +5% |

---

## API Reference

### OpenRouter (Claude)

```
Endpoint: https://openrouter.ai/api/v1/chat/completions
Model: anthropic/claude-sonnet-4
Auth: Bearer token (OPENROUTER_API_KEY)
Headers:
  - Content-Type: application/json
  - HTTP-Referer: CosmoOS/1.0
  - X-Title: CosmoOS BigBrain
```

### HuggingFace (FunctionGemma)

```
Model: lmstudio-community/functiongemma-270m-it-MLX-bf16
Format: MLX BF16 (Apple Silicon native)
Cache: ~/.cache/huggingface/hub/models--lmstudio-community--functiongemma-270m-it-MLX-bf16/
```

---

## Summary

The Micro-Brain Architecture achieves:

1. **84% RAM reduction** - From 3.3GB to 533MB
2. **6x faster P95 latency** - From 2000ms to 350ms
3. **Single local model** - FunctionGemma 270M replaces Qwen + Hermes
4. **Pure dispatch pattern** - Model outputs function calls, never reasons
5. **Claude for cognition** - Complex reasoning offloaded to cloud API
6. **Zero crashes** - Stable on 16GB M4 MacBook

**The result**: Voice commands feel instant, the codebase is maintainable, and everything flows through the Atom data layer.
