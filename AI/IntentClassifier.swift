// CosmoOS/AI/IntentClassifier.swift
// Embedding-based intent classification - replaces brittle pattern matching
// Uses pre-computed centroids for sub-20ms classification
// macOS 26+ optimized

import Foundation

// MARK: - Intent Types

/// Primary intent classification for voice input (AI classifier version)
/// Note: This is separate from Voice/Models/VoiceAtom.VoiceIntent to avoid collision
public enum ClassifiedVoiceIntent: String, Codable, Sendable, CaseIterable {
    // Capture intents
    case createTask           // "I need to...", "Remind me to..."
    case createTaskTimed      // "Call Sarah at 2pm"
    case createIdea           // "I had a thought about..."
    case createScheduleBlock  // "Deep work from 2-4pm"
    case createFocusSession   // "25 minute focus session"
    case modifySchedule       // "Expand to 5pm", "Move to 3pm"
    case createConnection     // EXPLICIT: "Create a connection about..."
    case brainDump            // Long multi-item voice input

    // Retrieval intents
    case findRelevant         // "What's relevant to this?"
    case findSimilar          // "Similar posts/hooks"
    case helpWriting          // "What can help me write this?"
    case discoverPatterns     // "What connections am I missing?"
    case directSearch         // "Have I written about X?"
    case currentFocus         // "What am I working on?", "What is this about?"

    // Generative intents (trigger Gemini 3 Pro via OpenRouter)
    case synthesizeContent    // "Give me 5 content ideas combining..."
    case generateIdeas        // "Propose 10 original ideas..."
    case crossDomainAnalysis  // "Find unexpected parallels between..."
    case deepSynthesis        // "How does this research link to..."
    case createFramework      // "Create a unified framework from..."
    case fullDatabaseQuery    // "Using my entire database/all my notes..."

    // Control intents
    case navigate             // "Go to projects", "Open inbox"
    case cancel               // "Cancel", "Never mind"
    case confirm              // "Yes", "Do it"
    case unclear              // Needs LLM for disambiguation

    /// Whether this intent triggers the capture path
    public var isCapture: Bool {
        switch self {
        case .createTask, .createTaskTimed, .createIdea,
             .createScheduleBlock, .createFocusSession,
             .modifySchedule, .createConnection, .brainDump:
            return true
        default:
            return false
        }
    }

    /// Whether this intent triggers the retrieval path
    public var isRetrieval: Bool {
        switch self {
        case .findRelevant, .findSimilar, .helpWriting,
             .discoverPatterns, .directSearch, .currentFocus:
            return true
        default:
            return false
        }
    }

    /// Whether this is a context-awareness query (uses editing context, not search)
    public var isContextQuery: Bool {
        switch self {
        case .currentFocus:
            return true
        default:
            return false
        }
    }

    /// Whether this requires the deep model (Qwen 8B)
    public var requiresDeepModel: Bool {
        switch self {
        case .helpWriting, .discoverPatterns:
            return true
        default:
            return false
        }
    }

    /// Whether this intent triggers the generative path (Gemini 3 Pro)
    public var isGenerative: Bool {
        switch self {
        case .synthesizeContent, .generateIdeas, .crossDomainAnalysis,
             .deepSynthesis, .createFramework, .fullDatabaseQuery:
            return true
        default:
            return false
        }
    }

    /// Estimated context size for generative intents (determines token budget)
    public var estimatedContextSize: ContextSize {
        switch self {
        case .synthesizeContent, .generateIdeas:
            return .medium      // 10-50k tokens - few entities
        case .crossDomainAnalysis, .deepSynthesis:
            return .large       // 50-200k tokens - topic cluster
        case .createFramework, .fullDatabaseQuery:
            return .massive     // 200k+ tokens - full database scan
        default:
            return .small       // < 10k tokens - single entity focus
        }
    }
}

// MARK: - Context Size

/// Token budget categories for generative intents
public enum ContextSize: String, Codable, Sendable {
    case small      // < 10k tokens - single entity focus
    case medium     // 10-50k tokens - few entities
    case large      // 50-200k tokens - topic cluster
    case massive    // 200k+ tokens - full database scan

    /// Maximum token budget for this context size
    public var maxTokens: Int {
        switch self {
        case .small: return 10_000
        case .medium: return 50_000
        case .large: return 200_000
        case .massive: return 500_000
        }
    }
}


// EmbeddingIntentClassifier (daemon-embedding centroid classifier) removed —
// it was never initialized anywhere and the daemon embed endpoint is gone.
// The two enums above (ClassifiedVoiceIntent, ContextSize) remain in live use
// by GeminiSynthesisEngine / ContextAssembler / LegacyStubs.
