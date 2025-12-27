// CosmoOS/AI/MicroBrain/MicroBrainOrchestrator.swift
// Main orchestrator for the Micro-Brain voice command architecture
// Replaces the previous 4-tier pipeline with a streamlined 3-tier approach

import Foundation
import os.log

// MARK: - Micro-Brain Orchestrator

/// The main orchestrator for the Micro-Brain architecture.
///
/// This actor manages the 3-tier voice command pipeline:
/// - **Tier 0**: Pattern matching (<50ms) - 60% of commands
/// - **Tier 1**: FunctionGemma 270M (<300ms) - 39% of commands
/// - **Tier 2**: Claude API (1-5s) - 1% of commands (generative only)
///
/// The orchestrator:
/// 1. Routes commands through the appropriate tier
/// 2. Manages the FunctionGemma engine lifecycle
/// 3. Coordinates with the BigBrain (Claude API) for complex reasoning
/// 4. Executes function calls via ToolExecutor
public actor MicroBrainOrchestrator {

    // MARK: - Singleton

    public static let shared = MicroBrainOrchestrator()

    // MARK: - Dependencies

    private let logger = Logger(subsystem: "com.cosmo.microbrain", category: "Orchestrator")

    private let patternMatcher: PatternMatcherProtocol
    private let functionGemma: FunctionGemmaEngine
    private let toolExecutor: ToolExecutor
    private let intentClassifier: IntentClassifierProtocol
    private var claudeClient: ClaudeAPIClientProtocol?

    // MARK: - State

    private var isInitialized = false
    private var totalCommands: Int = 0
    private var tier0Hits: Int = 0
    private var tier1Hits: Int = 0
    private var tier2Hits: Int = 0

    // MARK: - Initialization

    private init(
        patternMatcher: PatternMatcherProtocol = PatternMatcherAdapter(),
        functionGemma: FunctionGemmaEngine = .shared,
        toolExecutor: ToolExecutor = .shared,
        intentClassifier: IntentClassifierProtocol = IntentClassifierAdapter()
    ) {
        self.patternMatcher = patternMatcher
        self.functionGemma = functionGemma
        self.toolExecutor = toolExecutor
        self.intentClassifier = intentClassifier
    }

    /// Configure the Claude API client for Big Brain operations
    public func configureClaude(_ client: ClaudeAPIClientProtocol) {
        self.claudeClient = client
    }

    /// Initialize the Micro-Brain (load models, etc.)
    public func initialize() async throws {
        guard !isInitialized else { return }

        logger.info("Initializing Micro-Brain...")

        // Load FunctionGemma model
        try await functionGemma.loadModel()

        isInitialized = true
        logger.info("Micro-Brain initialized successfully")
    }

    // MARK: - Command Processing

    /// Process a voice command through the Micro-Brain pipeline
    /// - Parameters:
    ///   - transcript: The voice command transcript
    ///   - context: Current voice context
    /// - Returns: MicroBrainResult with execution outcome
    public func process(_ transcript: String, context: VoiceContext) async -> MicroBrainResult {
        let startTime = Date()
        totalCommands += 1

        logger.info("Processing: \"\(transcript)\"")

        // Tier 0: Pattern Matching (<50ms, 60% of commands)
        if let patternResult = await patternMatcher.match(transcript, context: context) {
            tier0Hits += 1
            let latency = Date().timeIntervalSince(startTime) * 1000
            logger.info("Tier 0 match in \(String(format: "%.0f", latency))ms")
            return await executePatternResult(patternResult, context: context)
        }

        // Classify intent to determine routing
        let intent = await intentClassifier.classify(transcript)

        // Tier 2: Route generative intents to Claude API
        if intent.isGenerative {
            tier2Hits += 1
            return await routeToClaudeForSynthesis(transcript, context: context, intent: intent)
        }

        // Tier 1: FunctionGemma (<300ms, 39% of commands)
        tier1Hits += 1
        return await processWithFunctionGemma(transcript, context: context)
    }

    // MARK: - Tier 0: Pattern Matching

    private func executePatternResult(_ result: ParsedAction, context: VoiceContext) async -> MicroBrainResult {
        do {
            // Convert ParsedAction to FunctionCall for unified execution
            let functionCall = parsedActionToFunctionCall(result)

            if let call = functionCall {
                let executionResult = try await toolExecutor.execute(call, context: context)
                return MicroBrainResult(
                    success: true,
                    tier: .pattern,
                    executionResult: executionResult,
                    latencyMs: 0  // Filled by caller
                )
            } else {
                // Fall back to direct ParsedAction execution
                return MicroBrainResult(
                    success: true,
                    tier: .pattern,
                    parsedAction: result,
                    latencyMs: 0
                )
            }
        } catch {
            logger.error("Pattern execution failed: \(error.localizedDescription)")
            return MicroBrainResult(success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Tier 1: FunctionGemma

    private func processWithFunctionGemma(_ transcript: String, context: VoiceContext) async -> MicroBrainResult {
        let startTime = Date()

        do {
            // Generate function call
            let functionCall = try await functionGemma.generateFunctionCall(
                transcript: transcript,
                context: context
            )

            // Execute function call
            let executionResult = try await toolExecutor.execute(functionCall, context: context)

            let latency = Date().timeIntervalSince(startTime) * 1000
            logger.info("Tier 1 complete in \(String(format: "%.0f", latency))ms")

            return MicroBrainResult(
                success: true,
                tier: .functionGemma,
                executionResult: executionResult,
                functionCall: functionCall,
                latencyMs: latency
            )

        } catch {
            logger.error("FunctionGemma processing failed: \(error.localizedDescription)")
            return MicroBrainResult(success: false, tier: .functionGemma, error: error.localizedDescription)
        }
    }

    // MARK: - Tier 2: Claude API (Big Brain)

    private func routeToClaudeForSynthesis(
        _ transcript: String,
        context: VoiceContext,
        intent: ClassifiedIntent
    ) async -> MicroBrainResult {
        guard let claude = claudeClient else {
            logger.warning("Claude API not configured, falling back to FunctionGemma")
            return await processWithFunctionGemma(transcript, context: context)
        }

        let startTime = Date()

        do {
            let response = try await claude.generateSynthesis(
                transcript: transcript,
                context: context,
                intent: intent
            )

            let latency = Date().timeIntervalSince(startTime) * 1000
            logger.info("Tier 2 (Claude) complete in \(String(format: "%.0f", latency))ms")

            return MicroBrainResult(
                success: true,
                tier: .claudeAPI,
                synthesizedContent: response,
                latencyMs: latency
            )

        } catch {
            logger.error("Claude API failed: \(error.localizedDescription)")
            // Fall back to FunctionGemma for non-generative interpretation
            return await processWithFunctionGemma(transcript, context: context)
        }
    }

    // MARK: - Helpers

    /// Convert ParsedAction to FunctionCall for unified execution
    private func parsedActionToFunctionCall(_ action: ParsedAction) -> FunctionCall? {
        switch action.action {
        case .create:
            guard let atomType = action.atomType else { return nil }

            var params: [String: FunctionParameter] = [
                "atom_type": .string(atomType.rawValue)
            ]

            if let title = action.title {
                params["title"] = .string(title)
            }

            if let body = action.body {
                params["body"] = .string(body)
            }

            if let metadata = action.metadata {
                let metaParams = metadata.mapValues { FunctionParameter.from($0.value) }
                params["metadata"] = .object(metaParams)
            }

            return FunctionCall(name: "create_atom", parameters: params)

        case .update:
            var params: [String: FunctionParameter] = [
                "target": .string(action.target?.rawValue ?? "context")
            ]

            if let title = action.title {
                params["title"] = .string(title)
            }

            if let metadata = action.metadata {
                let metaParams = metadata.mapValues { FunctionParameter.from($0.value) }
                params["metadata"] = .object(metaParams)
            }

            return FunctionCall(name: "update_atom", parameters: params)

        case .delete:
            return FunctionCall(
                name: "delete_atom",
                parameters: ["target": .string(action.target?.rawValue ?? "context")]
            )

        case .search:
            var params: [String: FunctionParameter] = [:]

            if let query = action.query {
                params["query"] = .string(query)
            }

            if let types = action.types {
                params["types"] = .array(types.map { .string($0.rawValue) })
            }

            return FunctionCall(name: "search_atoms", parameters: params)

        case .batch:
            guard let items = action.items else { return nil }

            let itemParams: [FunctionParameter] = items.compactMap { item -> FunctionParameter? in
                guard let atomType = item.atomType else { return nil }

                var itemDict: [String: FunctionParameter] = [
                    "atom_type": .string(atomType.rawValue)
                ]

                if let title = item.title {
                    itemDict["title"] = .string(title)
                }

                return .object(itemDict)
            }

            return FunctionCall(name: "batch_create", parameters: ["items": .array(itemParams)])

        case .navigate:
            guard let destination = action.destination else { return nil }
            return FunctionCall(name: "navigate", parameters: ["destination": .string(destination)])

        case .query:
            var params: [String: FunctionParameter] = [
                "query_type": .string(action.queryType?.rawValue ?? "level_status")
            ]

            if let dimension = action.dimension {
                params["dimension"] = .string(dimension)
            }

            return FunctionCall(name: "query_level_system", parameters: params)
        }
    }

    // MARK: - Metrics

    /// Get orchestrator metrics
    public func getMetrics() async -> OrchestratorMetrics {
        let gemmaMetrics = await functionGemma.getMetrics()

        return OrchestratorMetrics(
            totalCommands: totalCommands,
            tier0Hits: tier0Hits,
            tier1Hits: tier1Hits,
            tier2Hits: tier2Hits,
            tier0Percentage: totalCommands > 0 ? Double(tier0Hits) / Double(totalCommands) * 100 : 0,
            tier1Percentage: totalCommands > 0 ? Double(tier1Hits) / Double(totalCommands) * 100 : 0,
            tier2Percentage: totalCommands > 0 ? Double(tier2Hits) / Double(totalCommands) * 100 : 0,
            functionGemmaMetrics: gemmaMetrics
        )
    }

    // MARK: - Lifecycle

    /// Shutdown the Micro-Brain
    public func shutdown() async {
        await functionGemma.shutdown()
        isInitialized = false
        logger.info("Micro-Brain shutdown complete")
    }
}

// MARK: - Micro-Brain Voice Result

/// Result of processing a voice command through the MicroBrain
/// Note: Different from VoiceAtom.VoiceResult which is used by VoiceCommandPipeline
public struct MicroBrainResult: Sendable {
    public let success: Bool
    public let tier: ProcessingTier?
    public let executionResult: ExecutionResult?
    public let parsedAction: ParsedAction?
    public let functionCall: FunctionCall?
    public let synthesizedContent: String?
    public let error: String?
    public let latencyMs: Double

    public init(
        success: Bool,
        tier: ProcessingTier? = nil,
        executionResult: ExecutionResult? = nil,
        parsedAction: ParsedAction? = nil,
        functionCall: FunctionCall? = nil,
        synthesizedContent: String? = nil,
        error: String? = nil,
        latencyMs: Double = 0
    ) {
        self.success = success
        self.tier = tier
        self.executionResult = executionResult
        self.parsedAction = parsedAction
        self.functionCall = functionCall
        self.synthesizedContent = synthesizedContent
        self.error = error
        self.latencyMs = latencyMs
    }

    /// Confirmation message for the user
    public var confirmationMessage: String {
        if let result = executionResult {
            return result.confirmationMessage
        }
        if let content = synthesizedContent {
            return content
        }
        if let err = error {
            return "Error: \(err)"
        }
        return "Command processed"
    }
}

/// Which tier processed the command
public enum ProcessingTier: String, Sendable {
    case pattern = "tier0_pattern"
    case functionGemma = "tier1_function_gemma"
    case claudeAPI = "tier2_claude_api"
}

// MARK: - Orchestrator Metrics

public struct OrchestratorMetrics: Codable, Sendable {
    public let totalCommands: Int
    public let tier0Hits: Int
    public let tier1Hits: Int
    public let tier2Hits: Int
    public let tier0Percentage: Double
    public let tier1Percentage: Double
    public let tier2Percentage: Double
    public let functionGemmaMetrics: FunctionGemmaMetrics
}

// MARK: - Classified Intent

/// Result of intent classification
public struct ClassifiedIntent: Sendable {
    public let primary: String
    public let confidence: Double
    public let isGenerative: Bool
    public let secondary: String?

    public init(primary: String, confidence: Double, isGenerative: Bool = false, secondary: String? = nil) {
        self.primary = primary
        self.confidence = confidence
        self.isGenerative = isGenerative
        self.secondary = secondary
    }
}

// MARK: - Protocols for Dependencies

/// Protocol for pattern matcher
public protocol PatternMatcherProtocol: Sendable {
    func match(_ transcript: String, context: VoiceContext) async -> ParsedAction?
}

/// Protocol for intent classifier
public protocol IntentClassifierProtocol: Sendable {
    func classify(_ transcript: String) async -> ClassifiedIntent
}

/// Extension of ClaudeAPIClientProtocol for synthesis
extension ClaudeAPIClientProtocol {
    func generateSynthesis(transcript: String, context: VoiceContext, intent: ClassifiedIntent) async throws -> String {
        // Default implementation - subclasses should override
        throw MicroBrainError.executionFailed("Synthesis not implemented")
    }
}

// MARK: - Adapters for Existing Components

/// Adapter for existing PatternMatcher
struct PatternMatcherAdapter: PatternMatcherProtocol {
    func match(_ transcript: String, context: VoiceContext) async -> ParsedAction? {
        // Use the real PatternMatcher.shared for Tier 0 matching
        return await PatternMatcher.shared.match(transcript)
    }
}

/// Adapter for existing IntentClassifier
struct IntentClassifierAdapter: IntentClassifierProtocol {
    func classify(_ transcript: String) async -> ClassifiedIntent {
        // Will integrate with existing IntentClassifier.swift
        // Check for generative keywords
        let generativeKeywords = ["generate", "give me ideas", "synthesize", "create content", "write me", "suggest"]
        let lowered = transcript.lowercased()

        let isGenerative = generativeKeywords.contains { lowered.contains($0) }

        return ClassifiedIntent(
            primary: isGenerative ? "generative" : "action",
            confidence: 0.9,
            isGenerative: isGenerative
        )
    }
}
