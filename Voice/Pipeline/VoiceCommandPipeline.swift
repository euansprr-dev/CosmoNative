// CosmoOS/Voice/Pipeline/VoiceCommandPipeline.swift
// THE unified voice command pipeline. There is no other.
// Updated for Micro-Brain architecture: FunctionGemma 270M + Claude Sonnet 4.5

import Foundation
import os.log

// MARK: - Voice Command Pipeline

/// THE voice command pipeline.
/// Processes all voice commands through the Micro-Brain architecture.
///
/// Architecture (Micro-Brain):
/// - Tier 0: Pattern Matching (<50ms) - Handles 60% of commands
/// - Tier 1: FunctionGemma 270M (<300ms) - Handles 39% of commands (replaces Qwen + Hermes)
/// - Tier 2: Claude Sonnet 4.5 (1-5s) - Handles 1% (generative/correlation only)
///
/// Benefits over old architecture:
/// - 6x RAM reduction: ~550MB vs ~3.3GB
/// - Consistent latency: <300ms for 99% of commands
/// - Better accuracy: Fine-tuned for CosmoOS actions
actor VoiceCommandPipeline {
    /// Shared singleton
    static let shared = VoiceCommandPipeline()

    private let logger = Logger(subsystem: "com.cosmo.voice", category: "Pipeline")

    // Dependencies - Micro-Brain Architecture
    private let patternMatcher = PatternMatcher.shared
    private let intentClassifier: IntentClassifier
    private let microBrain: MicroBrainOrchestrator  // Replaces Qwen 0.5B + Hermes 1.5B
    private let bigBrain: ClaudeAPIClient           // Replaces GeminiAPI
    private var atomRepo: AtomRepository?
    private var queryHandler: LevelSystemQueryHandler?  // Lazy-loaded from MainActor

    // Metrics
    private var totalCommands: Int = 0
    private var tierCounts: [ModelTier: Int] = [:]
    private var totalLatencyMs: Int = 0

    // MARK: - Initialization

    init(
        intentClassifier: IntentClassifier = .shared,
        microBrain: MicroBrainOrchestrator = .shared,
        bigBrain: ClaudeAPIClient = .shared
    ) {
        self.intentClassifier = intentClassifier
        self.microBrain = microBrain
        self.bigBrain = bigBrain
        self.atomRepo = nil  // Lazy-loaded from MainActor when needed
    }

    /// Get or lazily initialize the AtomRepository from the MainActor
    private func getAtomRepo() async -> AtomRepository {
        if let repo = atomRepo {
            return repo
        }
        let repo = await MainActor.run { AtomRepository.shared }
        atomRepo = repo
        return repo
    }

    /// Get or lazily initialize the LevelSystemQueryHandler from the MainActor
    private func getQueryHandler() async -> LevelSystemQueryHandler {
        if let handler = queryHandler {
            return handler
        }
        let handler = await MainActor.run { LevelSystemQueryHandler.shared }
        queryHandler = handler
        return handler
    }

    // MARK: - Main Processing

    /// Process ANY voice command.
    /// This is the single entry point for all voice processing.
    /// Uses the Micro-Brain architecture for efficient command dispatch.
    func process(_ transcript: String, context: VoiceContext) async -> VoiceResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        totalCommands += 1

        logger.info("Processing voice command: \(transcript)")

        // Step 1: Create VoiceAtom
        var voiceAtom = VoiceAtom(
            transcript: transcript,
            context: context,
            timestamp: Date()
        )

        // Step 2: Try pattern matching (Tier 0) - fastest path
        let patternStart = CFAbsoluteTimeGetCurrent()
        if let parsedAction = await patternMatcher.match(transcript) {
            let patternMs = Int((CFAbsoluteTimeGetCurrent() - patternStart) * 1000)
            voiceAtom.tier = .pattern
            voiceAtom.parsedAction = parsedAction
            voiceAtom.modelDurationMs = patternMs

            logger.info("Pattern matched in \(patternMs)ms")
            tierCounts[.pattern, default: 0] += 1

            return await execute(voiceAtom, startTime: startTime)
        }

        // Step 3: Classify intent for routing decision
        let classifyStart = CFAbsoluteTimeGetCurrent()
        let (intent, confidence) = await intentClassifier.classify(transcript)
        voiceAtom.intent = intent
        voiceAtom.confidence = confidence
        voiceAtom.classificationDurationMs = Int((CFAbsoluteTimeGetCurrent() - classifyStart) * 1000)

        // Step 4: Select model tier (Micro-Brain simplified tiers)
        voiceAtom.tier = selectTier(voiceAtom)
        logger.info("Selected tier: \(voiceAtom.tier.rawValue) for intent: \(intent.rawValue)")

        // Step 5: Generate action based on tier
        let modelStart = CFAbsoluteTimeGetCurrent()

        do {
            switch voiceAtom.tier {
            case .pattern:
                // Already handled above
                fatalError("Pattern tier should have been handled above")

            case .functionGemma:
                // Micro-Brain: FunctionGemma 270M handles all standard commands
                let result = await microBrain.process(transcript, context: context)
                if result.success, let action = result.parsedAction {
                    voiceAtom.parsedAction = action
                } else {
                    throw VoicePipelineError.modelError(result.error ?? "FunctionGemma failed")
                }

            case .claude:
                // Big Brain: Claude handles generative/correlation tasks
                let result = await routeToClaudeForSynthesis(voiceAtom)
                voiceAtom.modelDurationMs = Int((CFAbsoluteTimeGetCurrent() - modelStart) * 1000)
                tierCounts[.claude, default: 0] += 1
                return result

            case .unknown:
                return VoiceResult.failure("Could not determine processing tier")

            // Legacy tiers - route to FunctionGemma
            case .qwen0_5B, .hermes1_5B, .gemini:
                logger.warning("Legacy tier \(voiceAtom.tier.rawValue) - routing to FunctionGemma")
                let result = await microBrain.process(transcript, context: context)
                if result.success, let action = result.parsedAction {
                    voiceAtom.parsedAction = action
                    voiceAtom.tier = .functionGemma
                } else {
                    throw VoicePipelineError.modelError(result.error ?? "FunctionGemma failed")
                }
            }

            voiceAtom.modelDurationMs = Int((CFAbsoluteTimeGetCurrent() - modelStart) * 1000)
            tierCounts[voiceAtom.tier, default: 0] += 1

        } catch {
            logger.error("Model error: \(error.localizedDescription)")
            return VoiceResult.failure("Model error: \(error.localizedDescription)", tier: voiceAtom.tier)
        }

        // Step 6: Execute the parsed action
        return await execute(voiceAtom, startTime: startTime)
    }

    // MARK: - Tier Selection

    /// Select the appropriate model tier for a VoiceAtom.
    /// Micro-Brain architecture: Pattern → FunctionGemma → Claude
    private func selectTier(_ voiceAtom: VoiceAtom) -> ModelTier {
        // Tier 2: Generative/correlation intents go to Claude (Big Brain)
        if let intent = voiceAtom.intent, intent.isGenerative {
            return .claude
        }

        // Tier 1: Everything else goes to FunctionGemma (Micro-Brain)
        // FunctionGemma handles all command types: create, update, delete, query, etc.
        return .functionGemma
    }

    // MARK: - Claude Synthesis

    /// Route generative requests to Claude API (Big Brain).
    /// Handles tasks like idea generation, content synthesis, correlation analysis.
    private func routeToClaudeForSynthesis(_ voiceAtom: VoiceAtom) async -> VoiceResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let synthesisContext = SynthesisContext(
                currentSection: voiceAtom.context.section.rawValue,
                currentProject: voiceAtom.context.currentProjectName,
                timeOfDay: getTimeOfDay(),
                recentActivitySummary: "Processing voice command"
            )

            let prompt = CorrelationRequestBuilder.buildSynthesisPrompt(
                transcript: voiceAtom.transcript,
                context: synthesisContext
            )

            let response = try await bigBrain.generate(prompt: prompt)

            let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            logger.info("Claude synthesis in \(durationMs)ms")

            return VoiceResult(
                success: true,
                synthesizedContent: response,
                tier: .claude,
                durationMs: durationMs
            )
        } catch {
            logger.error("Claude synthesis error: \(error.localizedDescription)")
            return VoiceResult.failure("Claude synthesis failed: \(error.localizedDescription)", tier: .claude)
        }
    }

    /// Get time of day for context
    private func getTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }

    // MARK: - Execution

    /// Execute a parsed VoiceAtom against AtomRepository.
    private func execute(_ voiceAtom: VoiceAtom, startTime: CFAbsoluteTime) async -> VoiceResult {
        guard let action = voiceAtom.parsedAction else {
            return VoiceResult.failure("No action parsed", tier: voiceAtom.tier)
        }

        _ = CFAbsoluteTimeGetCurrent()  // Execute start time (used for debugging if needed)

        do {
            // Handle query actions specially - they return a response, not atoms
            if action.action == .query {
                let queryResponse = try await getQueryHandler().executeQuery(action)
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                totalLatencyMs += durationMs

                logger.info("Query executed in \(durationMs)ms (tier: \(voiceAtom.tier.rawValue))")

                return VoiceResult.query(queryResponse, tier: voiceAtom.tier, durationMs: durationMs)
            }

            // Standard atom operations
            let atoms = try await executeAction(action, context: voiceAtom.context)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            totalLatencyMs += durationMs

            logger.info("Command executed in \(durationMs)ms (tier: \(voiceAtom.tier.rawValue))")

            return VoiceResult(
                success: true,
                atoms: atoms,
                tier: voiceAtom.tier,
                durationMs: durationMs
            )

        } catch {
            logger.error("Execution error: \(error.localizedDescription)")
            return VoiceResult.failure("Execution error: \(error.localizedDescription)", tier: voiceAtom.tier)
        }
    }

    /// Execute a ParsedAction against AtomRepository.
    private func executeAction(_ action: ParsedAction, context: VoiceContext) async throws -> [Atom] {
        let repo = await getAtomRepo()

        switch action.action {
        case .create:
            guard let atomType = action.atomType else {
                throw VoicePipelineError.missingAtomType
            }

            let links = action.resolveLinks(using: context)

            let atom = try await repo.create(
                type: atomType,
                title: action.title,
                body: action.body,
                structured: nil,
                metadata: action.metadataJson,
                links: links
            )
            return [atom]

        case .update:
            let targetUuid = resolveTargetUuid(action, context: context)
            guard let uuid = targetUuid else {
                throw VoicePipelineError.noTargetResolved
            }

            if let atom = try await repo.update(uuid: uuid, updates: { atom in
                if let title = action.title { atom.title = title }
                if let body = action.body { atom.body = body }
                if let meta = action.metadataJson { atom.metadata = meta }
            }) {
                return [atom]
            }
            return []

        case .delete:
            let targetUuid = resolveTargetUuid(action, context: context)
            guard let uuid = targetUuid else {
                throw VoicePipelineError.noTargetResolved
            }

            try await repo.delete(uuid: uuid)
            return []

        case .search:
            var options = AtomSearchOptions.default
            if let types = action.types {
                options.types = types
            }

            if let query = action.query {
                let engine = AtomSearchEngine()
                let results = try await engine.search(query: query, options: options)
                return results.map { $0.atom }
            }
            return []

        case .batch:
            guard let items = action.items else {
                throw VoicePipelineError.noBatchItems
            }

            var atoms: [Atom] = []
            for item in items {
                let itemAtoms = try await executeAction(item, context: context)
                atoms.append(contentsOf: itemAtoms)
            }
            return atoms

        case .navigate:
            // Navigation is handled by the UI layer
            // We just notify that navigation was requested
            if let destination = action.destination {
                await NavigationController.shared.navigate(to: destination)
            }
            return []

        case .query:
            // Query actions are handled separately and return a response instead of atoms
            // This case shouldn't reach here - queries are handled in execute()
            return []
        }
    }

    /// Resolve target UUID from ParsedAction and context.
    private func resolveTargetUuid(_ action: ParsedAction, context: VoiceContext) -> String? {
        // Direct UUID provided
        if let uuid = action.targetUuid {
            return uuid
        }

        // Resolve from target reference
        switch action.target {
        case .context:
            return context.contextualAtomUuid
        case .lastCreated:
            return context.recentAtomUuids.first
        case .firstResult:
            // Would need to be set from previous search
            return nil
        case .none:
            // Default to context
            return context.contextualAtomUuid
        }
    }

    // MARK: - Metrics

    /// Get pipeline metrics.
    func getMetrics() -> PipelineMetrics {
        let avgLatency = totalCommands > 0 ? Double(totalLatencyMs) / Double(totalCommands) : 0

        return PipelineMetrics(
            totalCommands: totalCommands,
            tierDistribution: tierCounts,
            averageLatencyMs: avgLatency,
            patternMatchRate: Double(tierCounts[.pattern] ?? 0) / max(1, Double(totalCommands))
        )
    }

    /// Reset metrics.
    func resetMetrics() {
        totalCommands = 0
        tierCounts = [:]
        totalLatencyMs = 0
    }
}

// MARK: - Pipeline Errors

enum VoicePipelineError: Error, LocalizedError {
    case missingAtomType
    case noTargetResolved
    case noBatchItems
    case modelError(String)

    var errorDescription: String? {
        switch self {
        case .missingAtomType:
            return "Create action requires an atom type"
        case .noTargetResolved:
            return "Could not resolve target for update/delete"
        case .noBatchItems:
            return "Batch action has no items"
        case .modelError(let message):
            return "Model error: \(message)"
        }
    }
}

// MARK: - Pipeline Metrics

struct PipelineMetrics: Sendable {
    let totalCommands: Int
    let tierDistribution: [ModelTier: Int]
    let averageLatencyMs: Double
    let patternMatchRate: Double

    var description: String {
        """
        Pipeline Metrics:
        - Total commands: \(totalCommands)
        - Pattern match rate: \(String(format: "%.1f%%", patternMatchRate * 100))
        - Average latency: \(String(format: "%.0fms", averageLatencyMs))
        - Tier distribution: \(tierDistribution)
        """
    }
}

// MARK: - Intent Classifier (Placeholder)

/// Intent classifier using embeddings.
/// This is a placeholder - actual implementation would use the embedding model.
actor IntentClassifier {
    static let shared = IntentClassifier()

    func classify(_ transcript: String) async -> (VoiceIntent, Double) {
        let lowered = transcript.lowercased()

        // Level System query detection (high priority)
        if let queryIntent = classifyQueryIntent(lowered) {
            return queryIntent
        }

        // Simple keyword-based classification (placeholder for embedding-based)
        if lowered.contains("generate") || lowered.contains("give me ideas") ||
           lowered.contains("find unexpected") || lowered.contains("create a framework") {
            return (.generateIdeas, 0.8)
        }

        if lowered.contains("idea") || lowered.contains("thought") || lowered.contains("note") {
            return (.createIdea, 0.85)
        }

        if lowered.contains("task") || lowered.contains("remind") || lowered.contains("need to") {
            if lowered.contains("at ") || lowered.contains("tomorrow") || lowered.contains("pm") || lowered.contains("am") {
                return (.createTaskTimed, 0.85)
            }
            return (.createTask, 0.85)
        }

        if lowered.contains("complete") || lowered.contains("done") || lowered.contains("finish") {
            return (.updateStatus, 0.9)
        }

        if lowered.contains("find") || lowered.contains("search") || lowered.contains("show me") {
            return (.search, 0.8)
        }

        if lowered.contains("delete") || lowered.contains("remove") {
            return (.delete, 0.85)
        }

        if lowered.contains("go to") || lowered.contains("open") {
            return (.navigate, 0.9)
        }

        // Check for brain dump (multiple items)
        let commaCount = lowered.components(separatedBy: ",").count
        let andCount = lowered.components(separatedBy: " and ").count
        if commaCount > 2 || andCount > 2 {
            return (.brainDump, 0.75)
        }

        return (.unknown, 0.3)
    }

    /// Classify Level System query intents
    private func classifyQueryIntent(_ text: String) -> (VoiceIntent, Double)? {
        // Level queries
        let levelPatterns = ["my level", "cosmo index", "what level", "how am i doing", "my progress"]
        if levelPatterns.contains(where: { text.contains($0) }) {
            return (.queryLevel, 0.9)
        }

        // XP queries
        let xpPatterns = ["my xp", "xp today", "experience points", "how much xp", "xp breakdown", "earned today"]
        if xpPatterns.contains(where: { text.contains($0) }) {
            return (.queryXP, 0.9)
        }

        // Streak queries
        let streakPatterns = ["my streak", "streak", "how long is my", "all streaks", "at risk"]
        if streakPatterns.contains(where: { text.contains($0) }) {
            return (.queryStreak, 0.9)
        }

        // Badge queries
        let badgePatterns = ["my badges", "badges", "badge", "earned", "close to"]
        if badgePatterns.contains(where: { text.contains($0) }) &&
           (text.contains("what") || text.contains("which") || text.contains("show") || text.contains("list")) {
            return (.queryBadge, 0.9)
        }

        // Health queries
        let healthPatterns = ["readiness", "hrv", "heart rate variability", "sleep", "health summary"]
        if healthPatterns.contains(where: { text.contains($0) }) {
            return (.queryHealth, 0.9)
        }

        // Readiness specific
        if text.contains("ready") || text.contains("rested") || text.contains("prepared") {
            return (.queryReadiness, 0.85)
        }

        // Summary queries
        let summaryPatterns = ["daily summary", "weekly summary", "today's summary", "this week", "recap", "how did i do"]
        if summaryPatterns.contains(where: { text.contains($0) }) {
            return (.querySummary, 0.9)
        }

        return nil
    }
}

// MARK: - Navigation Controller (Placeholder)

/// Navigation controller for handling navigation commands.
actor NavigationController {
    static let shared = NavigationController()

    func navigate(to destination: String) async {
        // This would typically post a notification or call SwiftUI navigation
        NotificationCenter.default.post(
            name: .voiceNavigationRequested,
            object: nil,
            userInfo: ["destination": destination]
        )
    }
}

// Notification.Name.voiceNavigationRequested is defined in ToolExecutor.swift

// Note: MicroBrainOrchestrator is defined in AI/MicroBrain/MicroBrainOrchestrator.swift

