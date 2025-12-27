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

// MARK: - Classification Result

/// Result of intent classification with confidence
public struct IntentClassification: Sendable {
    public let intent: ClassifiedVoiceIntent
    public let confidence: Float
    public let secondaryIntent: ClassifiedVoiceIntent?
    public let secondaryConfidence: Float?
    public let classificationTimeMs: Double

    /// Whether confidence is high enough for immediate action
    public var isHighConfidence: Bool {
        confidence > 0.7
    }

    /// Whether we should fall back to LLM for disambiguation
    public var needsLLMDisambiguation: Bool {
        confidence < 0.5 || intent == .unclear
    }
}

// MARK: - Embedding Intent Classifier

/// Embedding-based intent classifier with pre-computed centroids
/// Note: Renamed to avoid collision with Voice/Pipeline/VoiceCommandPipeline.IntentClassifier
/// Target: < 20ms classification time
public actor EmbeddingIntentClassifier {

    // MARK: - Singleton

    public static let shared = EmbeddingIntentClassifier()

    // MARK: - Centroids

    /// Pre-computed centroid embeddings for each intent
    private var centroids: [ClassifiedVoiceIntent: [Float]] = [:]

    /// Example phrases for each intent (used to compute centroids)
    private let intentExamples: [ClassifiedVoiceIntent: [String]] = [
        // Capture - Task
        .createTask: [
            "I need to",
            "remind me to",
            "I should",
            "don't forget to",
            "add a task",
            "I have to",
            "need to do",
            "task to"
        ],

        // Capture - Task with time
        .createTaskTimed: [
            "at 2pm",
            "tomorrow at",
            "call at 3",
            "meeting at",
            "schedule for",
            "on Friday at",
            "appointment at",
            "dentist at 4pm"
        ],

        // Capture - Idea (simple creation - NOT brainstorming)
        .createIdea: [
            "create an idea called",
            "create an idea named",
            "new idea called",
            "add an idea called",
            "save idea called",
            "I had an idea",
            "just thought of",
            "what if we",
            "idea about",
            "I've been thinking",
            "occurred to me",
            "insight about",
            "thought about",
            "I just had this idea",
            "idea for",
            "quick idea"
        ],

        // Capture - Schedule block
        .createScheduleBlock: [
            "deep work from",
            "block out time",
            "writing time",
            "work session from",
            "block the afternoon",
            "time for project work",
            "schedule time block",
            "block 2 to 4"
        ],

        // Capture - Focus session
        .createFocusSession: [
            "focus session",
            "25 minute focus",
            "pomodoro",
            "focused time",
            "concentration session",
            "distraction free",
            "focus for 30 minutes"
        ],

        // Capture - Modify schedule
        .modifySchedule: [
            "expand to",
            "extend to",
            "move to",
            "reschedule to",
            "cancel the",
            "push back",
            "change time to",
            "move meeting"
        ],

        // Capture - Connection (EXPLICIT)
        .createConnection: [
            "create a connection about",
            "new connection for",
            "add connection about",
            "make a connection on",
            "start connection about"
        ],

        // Capture - Brain dump
        .brainDump: [
            "so today I",
            "let me brain dump",
            "few things to capture",
            "bunch of stuff",
            "multiple things",
            "here's what happened",
            "had a lot going on"
        ],

        // Retrieval - Find relevant
        .findRelevant: [
            "what's relevant to",
            "most relevant things",
            "related to this",
            "what connects to",
            "find relevant",
            "3 most relevant"
        ],

        // Retrieval - Find similar
        .findSimilar: [
            "similar posts",
            "hooks for this",
            "similar format",
            "like this one",
            "same structure",
            "similar threads",
            "from swipe file"
        ],

        // Retrieval - Help writing
        .helpWriting: [
            "help me write",
            "what can help write",
            "for this post",
            "writing this",
            "content for",
            "help with writing"
        ],

        // Retrieval - Pattern discovery
        .discoverPatterns: [
            "what patterns",
            "connections am I missing",
            "what links",
            "patterns in my",
            "hidden connections",
            "what relates"
        ],

        // Retrieval - Direct search
        .directSearch: [
            "have I written about",
            "do I have anything on",
            "search for",
            "find my notes on",
            "what did I write about"
        ],

        // Retrieval - Current focus (uses editing context - INSTANT)
        .currentFocus: [
            "what am I working on",
            "what is this about",
            "what's this document about",
            "what's the focus here",
            "what's related to what I'm editing",
            "what connects to this",
            "related to what I'm writing",
            "relevant to this document",
            "show me related to this",
            "what ties into this"
        ],

        // Generative - Synthesize content
        .synthesizeContent: [
            "give me content ideas",
            "give me 5 ideas combining",
            "content ideas for",
            "ideas using my swipe file",
            "post ideas based on",
            "create content combining",
            "content ideas using my connections",
            "write content from my research"
        ],

        // Generative - Generate ideas (BRAINSTORMING - requires Gemini)
        // Only for creative synthesis, NOT simple "create an idea called X"
        .generateIdeas: [
            "propose 10 original ideas",
            "give me 10 ideas",
            "give me five ideas",
            "brainstorm ideas using my",
            "generate creative ideas based on my notes",
            "original ideas based on my research",
            "creative ideas from my swipe file",
            "come up with unique ideas using",
            "novel ideas combining my connections",
            "brainstorm content ideas",
            "what ideas can you generate from",
            "suggest ideas based on my content"
        ],

        // Generative - Cross-domain analysis
        .crossDomainAnalysis: [
            "find unexpected parallels",
            "connections between these topics",
            "how does this relate to",
            "link across domains",
            "surprising connections",
            "relate neuroscience to writing",
            "parallels between",
            "cross-pollinate ideas from"
        ],

        // Generative - Deep synthesis
        .deepSynthesis: [
            "how does this research link to",
            "how does this connect to what I'm writing",
            "deep connection between",
            "synthesize these ideas",
            "unify these concepts",
            "bring together my thoughts on",
            "integrate my research with",
            "how does this fit with"
        ],

        // Generative - Create framework
        .createFramework: [
            "create a unified framework",
            "build a mental model from",
            "framework combining",
            "unified model of",
            "structure these ideas into",
            "organize my thinking about",
            "comprehensive model for",
            "systematic approach to"
        ],

        // Generative - Full database query
        .fullDatabaseQuery: [
            "use my entire database",
            "all my notes on",
            "everything I have about",
            "across all my research",
            "all my connections about",
            "entire swipe file",
            "everything I've captured on",
            "my complete knowledge on"
        ],

        // Control - Navigate
        .navigate: [
            "go to",
            "open",
            "show me",
            "navigate to",
            "take me to",
            "switch to"
        ],

        // Control - Cancel
        .cancel: [
            "cancel",
            "never mind",
            "stop",
            "forget it",
            "don't do that",
            "undo"
        ],

        // Control - Confirm
        .confirm: [
            "yes",
            "do it",
            "confirm",
            "that's right",
            "correct",
            "go ahead"
        ]
    ]

    // MARK: - Dependencies

    private var embedder: DaemonXPCClient?
    private var isInitialized = false

    // MARK: - Initialization

    private init() {}

    /// Initialize with embedding service (call on app launch)
    public func initialize(embedder: DaemonXPCClient) async throws {
        self.embedder = embedder

        // Pre-compute centroids for each intent
        let startTime = Date()

        for intent in ClassifiedVoiceIntent.allCases {
            guard let examples = intentExamples[intent], !examples.isEmpty else {
                continue
            }

            // Embed all examples
            var embeddings: [[Float]] = []
            for example in examples {
                if let embedding = try? await embedder.embed(text: example) {
                    embeddings.append(embedding)
                }
            }

            guard !embeddings.isEmpty else { continue }

            // Compute centroid (mean of all embeddings)
            let centroid = computeCentroid(embeddings)
            centroids[intent] = centroid
        }

        let initTimeMs = Date().timeIntervalSince(startTime) * 1000
        isInitialized = true

        ConsoleLog.info(
            "IntentClassifier initialized: \(centroids.count) centroids in \(String(format: "%.1f", initTimeMs))ms",
            subsystem: .voice
        )
    }

    // MARK: - Classification

    /// Classify voice input intent (< 20ms target)
    public func classify(_ text: String) async throws -> IntentClassification {
        guard isInitialized, let embedder = embedder else {
            throw IntentClassifierError.notInitialized
        }

        let startTime = Date()

        // Embed the input text
        let inputEmbedding = try await embedder.embed(text: text)

        // Find closest centroid
        var bestIntent: ClassifiedVoiceIntent = .unclear
        var bestScore: Float = -1
        var secondIntent: ClassifiedVoiceIntent?
        var secondScore: Float?

        for (intent, centroid) in centroids {
            let similarity = cosineSimilarity(inputEmbedding, centroid)

            if similarity > bestScore {
                // Move current best to second
                secondIntent = bestIntent
                secondScore = bestScore

                // Update best
                bestIntent = intent
                bestScore = similarity
            } else if secondScore == nil || similarity > secondScore! {
                secondIntent = intent
                secondScore = similarity
            }
        }

        // Check for time indicators to upgrade task → timedTask
        if bestIntent == .createTask && containsTimeIndicator(text) {
            bestIntent = .createTaskTimed
        }

        // Check for long input to suggest brain dump
        let wordCount = text.split(separator: " ").count
        if wordCount > 50 && bestIntent.isCapture {
            // Long input might be brain dump
            if bestScore < 0.8 {
                secondIntent = bestIntent
                secondScore = bestScore
                bestIntent = .brainDump
                bestScore = 0.75  // Moderate confidence
            }
        }

        let classificationTimeMs = Date().timeIntervalSince(startTime) * 1000

        ConsoleLog.debug(
            "Intent classified: \(bestIntent.rawValue) (\(String(format: "%.2f", bestScore))) in \(String(format: "%.1f", classificationTimeMs))ms",
            subsystem: .voice
        )

        return IntentClassification(
            intent: bestIntent,
            confidence: bestScore,
            secondaryIntent: secondIntent,
            secondaryConfidence: secondScore,
            classificationTimeMs: classificationTimeMs
        )
    }

    /// Classify with additional context (improves accuracy)
    public func classify(
        _ text: String,
        currentView: String?,
        hotContext: HotContext?
    ) async throws -> IntentClassification {
        // Start with base classification
        var result = try await classify(text)

        // Boost confidence if context supports the intent
        if let currentView = currentView {
            // If in schedule view and talking about time, boost schedule intents
            if currentView == "schedule" && result.intent == .createTaskTimed {
                result = IntentClassification(
                    intent: result.intent,
                    confidence: min(result.confidence + 0.1, 1.0),
                    secondaryIntent: result.secondaryIntent,
                    secondaryConfidence: result.secondaryConfidence,
                    classificationTimeMs: result.classificationTimeMs
                )
            }
        }

        return result
    }

    // MARK: - Helpers

    /// Compute centroid (mean) of multiple embeddings
    private func computeCentroid(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }

        let dimension = embeddings[0].count
        var centroid = [Float](repeating: 0, count: dimension)

        for embedding in embeddings {
            for i in 0..<dimension {
                centroid[i] += embedding[i]
            }
        }

        let count = Float(embeddings.count)
        for i in 0..<dimension {
            centroid[i] /= count
        }

        // Normalize
        return normalize(centroid)
    }

    /// Normalize vector to unit length
    private func normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    /// Cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dot / denominator
    }

    /// Check if text contains time indicators
    private func containsTimeIndicator(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        let timePatterns = [
            // Specific times
            "\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)",  // 2pm, 2:30am
            "\\d{1,2}(?::\\d{2})?\\s*o'clock",     // 2 o'clock

            // Relative times
            "tomorrow",
            "today",
            "tonight",
            "this morning",
            "this afternoon",
            "this evening",

            // Days
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",

            // Prepositions with time
            "at \\d",
            "by \\d",
            "from \\d",
            "until \\d",

            // Recurring
            "every day",
            "daily",
            "weekly",
            "every morning",
            "every evening"
        ]

        for pattern in timePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                if regex.firstMatch(in: lowercased, options: [], range: range) != nil {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Debug

    /// Get all centroid scores for debugging
    public func debugScores(for text: String) async throws -> [(ClassifiedVoiceIntent, Float)] {
        guard isInitialized, let embedder = embedder else {
            throw IntentClassifierError.notInitialized
        }

        let inputEmbedding = try await embedder.embed(text: text)

        var scores: [(ClassifiedVoiceIntent, Float)] = []
        for (intent, centroid) in centroids {
            let similarity = cosineSimilarity(inputEmbedding, centroid)
            scores.append((intent, similarity))
        }

        return scores.sorted { $0.1 > $1.1 }
    }
}

// MARK: - Errors

public enum IntentClassifierError: LocalizedError {
    case notInitialized
    case embeddingFailed

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "IntentClassifier not initialized. Call initialize() first."
        case .embeddingFailed:
            return "Failed to generate embedding for input text."
        }
    }
}
