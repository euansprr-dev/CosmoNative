// CosmoOS/AI/TelepathyEngine.swift
// Core coordinator for the Telepathy Engine - zero-latency predictive context system
// Runs Shadow Search during voice/typing input, builds HotContext for routing
// macOS 26+ optimized

import Foundation
import Combine

// MARK: - Notification Names
// Note: l1PartialTranscript and l1FinalTranscript are defined in L1StreamingASR.swift

extension Notification.Name {
    /// Posted when HotContext is updated (for UI reactivity)
    static let hotContextUpdated = Notification.Name("com.cosmo.hotContextUpdated")
}

// MARK: - Hot Context
// Note: L1TranscriptChunk is defined in Voice/TieredASR/L1StreamingASR.swift

/// Observable state containing related entities from Shadow Search
/// Updated in real-time as user speaks or types
public struct HotContext: Sendable {
    public var relatedConnections: [VectorSearchResult] = []
    public var relatedProjects: [VectorSearchResult] = []
    public var relatedIdeas: [VectorSearchResult] = []
    public var relatedTasks: [VectorSearchResult] = []
    public var lastQuery: String = ""
    public var lastUpdateTime: Date = Date()
    public var searchLatencyMs: Double = 0

    /// Get beliefs from top related connections for autocomplete context
    public var topBeliefs: [String] {
        relatedConnections
            .prefix(3)
            .compactMap { $0.metadata?["beliefs"] }
    }

    /// Get goals from top related connections
    public var topGoals: [String] {
        relatedConnections
            .prefix(3)
            .compactMap { $0.metadata?["goal"] }
    }

    /// Get problems from top related connections
    public var topProblems: [String] {
        relatedConnections
            .prefix(3)
            .compactMap { $0.metadata?["problem"] }
    }

    /// Get most relevant project for context-aware routing
    public var mostRelevantProject: VectorSearchResult? {
        relatedProjects.first
    }

    /// Get most relevant connection for brain dump routing
    public var mostRelevantConnection: VectorSearchResult? {
        relatedConnections.first
    }

    /// Check if context has any related entities
    public var hasRelatedEntities: Bool {
        !relatedConnections.isEmpty ||
        !relatedProjects.isEmpty ||
        !relatedIdeas.isEmpty ||
        !relatedTasks.isEmpty
    }

    /// Get all related entity IDs for a given type
    public func entityIds(for type: String) -> [Int64] {
        switch type.lowercased() {
        case "connection": return relatedConnections.map { $0.entityId }
        case "project": return relatedProjects.map { $0.entityId }
        case "idea": return relatedIdeas.map { $0.entityId }
        case "task": return relatedTasks.map { $0.entityId }
        default: return []
        }
    }
}

// MARK: - Telepathy Engine

@MainActor
public final class TelepathyEngine: ObservableObject {
    // MARK: - Singleton

    public static let shared = TelepathyEngine()

    // MARK: - Observable State

    @Published public private(set) var hotContext: HotContext = HotContext()
    @Published public private(set) var isProcessing = false
    @Published public private(set) var lastTranscript: String = ""
    @Published public private(set) var isListening = false

    // MARK: - Dependencies

    private let gardener: StreamingGardener
    private let autocomplete: AutocompleteService

    // MARK: - Shadow Search State

    private var lastShadowSearchTokenCount = 0
    private let shadowSearchThreshold = 50  // Trigger shadow search every ~50 tokens
    private let minWordCountForSearch = 3   // Minimum words before triggering search
    private var shadowSearchTask: Task<Void, Never>?
    private var shadowSearchDebounceMs: UInt64 = 100  // Debounce rapid updates

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    // MARK: - Initialization

    private init() {
        self.gardener = StreamingGardener()
        self.autocomplete = AutocompleteService()

        setupObservers()
        ConsoleLog.info("TelepathyEngine initialized", subsystem: .telepathy)
    }

    // Note: Observers are automatically cleaned up when NotificationCenter
    // sees that the observer objects are deallocated

    // MARK: - Setup Observers

    private func setupObservers() {
        // Voice transcript observer (partial)
        let partialObserver = NotificationCenter.default.addObserver(
            forName: .l1PartialTranscript,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let chunk = notification.object as? L1TranscriptChunk else { return }
            Task { @MainActor [weak self] in
                await self?.handleVoiceChunk(chunk)
            }
        }
        observers.append(partialObserver)

        // Voice transcript observer (final)
        let finalObserver = NotificationCenter.default.addObserver(
            forName: .l1FinalTranscript,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let chunk = notification.object as? L1TranscriptChunk else { return }
            Task { @MainActor [weak self] in
                await self?.handleFinalTranscript(chunk)
            }
        }
        observers.append(finalObserver)

        ConsoleLog.debug("Observers set up for voice transcripts", subsystem: .telepathy)
    }

    // MARK: - Voice Input Handling

    /// Handle partial voice transcript chunk (streaming)
    func handleVoiceChunk(_ chunk: L1TranscriptChunk) async {
        ConsoleLog.debug(
            "Voice chunk: \"\(chunk.text.prefix(50))...\" (words: \(chunk.wordCount), final: \(chunk.isFinal))",
            subsystem: .telepathy
        )

        isListening = true
        lastTranscript = chunk.text

        // Feed to gardener for hypothesis building
        await gardener.processChunk(chunk, hotContext: hotContext)

        // Shadow search on token threshold or word count
        let shouldSearch = chunk.wordCount >= minWordCountForSearch &&
            (chunk.wordCount - lastShadowSearchTokenCount >= shadowSearchThreshold ||
             lastShadowSearchTokenCount == 0)

        if shouldSearch {
            await runShadowSearch(query: chunk.text)
            lastShadowSearchTokenCount = chunk.wordCount
        }
    }

    /// Handle final transcript (voice activity ended)
    func handleFinalTranscript(_ chunk: L1TranscriptChunk) async {
        ConsoleLog.info("Final transcript: \"\(chunk.text.prefix(80))...\"", subsystem: .telepathy)

        isListening = false
        lastTranscript = chunk.text

        // Run final shadow search for complete context
        await runShadowSearch(query: chunk.text)

        // Execute accumulated hypotheses
        await gardener.executeHypotheses(hotContext: hotContext)

        // Reset for next session
        lastShadowSearchTokenCount = 0
    }

    // MARK: - Typing Input Handling

    /// Handle typing input from text editor
    public func handleTypingInput(_ text: String, cursorPosition: Int) async {
        ConsoleLog.debug("Typing input: \"\(text.suffix(50))...\"", subsystem: .telepathy)

        lastTranscript = text

        // Shadow search for autocomplete context
        if text.split(separator: " ").count >= minWordCountForSearch {
            await runShadowSearch(query: text)
        }

        // Trigger autocomplete after 600ms pause (handled by AutocompleteService)
        await autocomplete.onTypingInput(text, cursorPosition: cursorPosition, hotContext: hotContext)
    }

    // MARK: - Shadow Search

    /// Run vector search to find related entities
    private func runShadowSearch(query: String) async {
        // Cancel previous search
        shadowSearchTask?.cancel()

        shadowSearchTask = Task(priority: .utility) { [weak self] in
            // Debounce rapid updates
            try? await Task.sleep(nanoseconds: (self?.shadowSearchDebounceMs ?? 100) * 1_000_000)
            guard !Task.isCancelled else { return }

            let startTime = Date()
            ConsoleLog.debug("Shadow search: \"\(query.prefix(30))...\"", subsystem: .telepathy)

            self?.setProcessing(true)

            do {
                // Run vector searches in parallel for each entity type
                async let connections = VectorDatabase.shared.search(
                    query: query,
                    limit: 5,
                    entityTypeFilter: "connection",
                    minSimilarity: 0.4
                )

                async let projects = VectorDatabase.shared.search(
                    query: query,
                    limit: 5,
                    entityTypeFilter: "project",
                    minSimilarity: 0.4
                )

                async let ideas = VectorDatabase.shared.search(
                    query: query,
                    limit: 5,
                    entityTypeFilter: "idea",
                    minSimilarity: 0.4
                )

                async let tasks = VectorDatabase.shared.search(
                    query: query,
                    limit: 5,
                    entityTypeFilter: "task",
                    minSimilarity: 0.4
                )

                // Await all results
                let (connResults, projResults, ideaResults, taskResults) = try await (
                    connections, projects, ideas, tasks
                )

                let latencyMs = Date().timeIntervalSince(startTime) * 1000

                // Update HotContext on main actor
                if let self = self {
                    self.updateHotContext(
                        connections: connResults,
                        projects: projResults,
                        ideas: ideaResults,
                        tasks: taskResults,
                        query: query,
                        latencyMs: latencyMs
                    )
                }

                ConsoleLog.info(
                    "Shadow search complete: \(connResults.count + projResults.count + ideaResults.count + taskResults.count) results in \(String(format: "%.1f", latencyMs))ms",
                    subsystem: .telepathy
                )

            } catch {
                ConsoleLog.error("Shadow search failed", subsystem: .telepathy, error: error)
            }

            self?.setProcessing(false)
        }
    }

    // MARK: - State Updates

    @MainActor
    private func setProcessing(_ value: Bool) {
        isProcessing = value
    }

    @MainActor
    private func updateHotContext(
        connections: [VectorSearchResult],
        projects: [VectorSearchResult],
        ideas: [VectorSearchResult],
        tasks: [VectorSearchResult],
        query: String,
        latencyMs: Double
    ) {
        hotContext = HotContext(
            relatedConnections: connections,
            relatedProjects: projects,
            relatedIdeas: ideas,
            relatedTasks: tasks,
            lastQuery: query,
            lastUpdateTime: Date(),
            searchLatencyMs: latencyMs
        )

        // Post notification for UI reactivity
        NotificationCenter.default.post(
            name: .hotContextUpdated,
            object: nil,
            userInfo: [
                "connectionCount": connections.count,
                "projectCount": projects.count,
                "ideaCount": ideas.count,
                "taskCount": tasks.count,
                "latencyMs": latencyMs
            ]
        )
    }

    // MARK: - Public API

    /// Manually trigger a shadow search (useful for testing or explicit refresh)
    public func triggerSearch(for query: String) async {
        await runShadowSearch(query: query)
    }

    /// Clear the current hot context
    public func clearContext() {
        hotContext = HotContext()
        lastTranscript = ""
        lastShadowSearchTokenCount = 0
        ConsoleLog.debug("Context cleared", subsystem: .telepathy)
    }

    /// Get the streaming gardener for direct access (e.g., testing)
    public var streamingGardener: StreamingGardener {
        gardener
    }

    /// Get the autocomplete service for direct access
    public var autocompleteService: AutocompleteService {
        autocomplete
    }
}

// MARK: - Debug Helpers

extension TelepathyEngine {
    /// Log current state for debugging
    public func logState() {
        ConsoleLog.debug("""
        TelepathyEngine State:
        - Listening: \(isListening)
        - Processing: \(isProcessing)
        - Last transcript: \"\(lastTranscript.prefix(50))...\"
        - Related connections: \(hotContext.relatedConnections.count)
        - Related projects: \(hotContext.relatedProjects.count)
        - Related ideas: \(hotContext.relatedIdeas.count)
        - Related tasks: \(hotContext.relatedTasks.count)
        - Last search latency: \(String(format: "%.1f", hotContext.searchLatencyMs))ms
        """, subsystem: .telepathy)
    }

    /// Simulate a voice chunk (for testing)
    public func simulateVoiceChunk(_ text: String, isFinal: Bool = false) async {
        let chunk = L1TranscriptChunk(
            text: text,
            isFinal: isFinal,
            confidence: 0.85,
            timestamp: Date().timeIntervalSince1970
        )
        if isFinal {
            await handleFinalTranscript(chunk)
        } else {
            await handleVoiceChunk(chunk)
        }
    }
}
