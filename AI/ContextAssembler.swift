// CosmoOS/AI/ContextAssembler.swift
// Gathers comprehensive context for Gemini's 1M token window
// Intelligent content selection based on query and intent
// macOS 26+ optimized

import Foundation
import GRDB

// NOTE: SourceReference, SuggestedAction, and SynthesisResult are defined in VoiceAction.swift

// MARK: - Context Entity Reference

/// Reference to a specific entity for must-include items (distinct from CosmoCore.EntityReference)
public struct ContextEntityRef: Sendable, Equatable {
    public let entityType: String
    public let entityId: Int64

    public init(entityType: String, entityId: Int64) {
        self.entityType = entityType
        self.entityId = entityId
    }
}

// MARK: - Depth Level

/// How deep to go when gathering context
public enum DepthLevel: String, Sendable {
    case shallow    // Just top-level summaries
    case medium     // Include some detail
    case deep       // Include full content
}

// MARK: - Assembled Context

/// Result of context assembly for Gemini
public struct AssembledContext: Sendable {
    public let systemPrompt: String
    public let userContext: String
    public let relevantContent: String
    public let totalTokens: Int
    public let sources: [SourceReference]

    /// Combined prompt for Gemini
    public var fullPrompt: String {
        """
        \(systemPrompt)

        ## USER CONTEXT
        \(userContext)

        ## RELEVANT CONTENT FROM KNOWLEDGE BASE
        \(relevantContent)
        """
    }
}

// MARK: - Assembly Configuration

/// Configuration for how to assemble context
public struct AssemblyConfig: Sendable {
    public let maxTokens: Int
    public let includeSwipeFile: Bool
    public let includeConnections: Bool
    public let includeResearch: Bool
    public let includeIdeas: Bool
    public let includeTasks: Bool
    public let prioritizeRecent: Bool
    public let specificEntityIds: [ContextEntityRef]?

    public init(
        maxTokens: Int = 50_000,
        includeSwipeFile: Bool = true,
        includeConnections: Bool = true,
        includeResearch: Bool = true,
        includeIdeas: Bool = true,
        includeTasks: Bool = false,
        prioritizeRecent: Bool = true,
        specificEntityIds: [ContextEntityRef]? = nil
    ) {
        self.maxTokens = maxTokens
        self.includeSwipeFile = includeSwipeFile
        self.includeConnections = includeConnections
        self.includeResearch = includeResearch
        self.includeIdeas = includeIdeas
        self.includeTasks = includeTasks
        self.prioritizeRecent = prioritizeRecent
        self.specificEntityIds = specificEntityIds
    }

    /// Create config from context size
    public static func from(contextSize: ContextSize) -> AssemblyConfig {
        switch contextSize {
        case .small:
            return AssemblyConfig(
                maxTokens: 10_000,
                includeSwipeFile: false,
                includeConnections: true,
                includeResearch: false,
                includeIdeas: true,
                includeTasks: false,
                prioritizeRecent: true
            )
        case .medium:
            return AssemblyConfig(
                maxTokens: 50_000,
                includeSwipeFile: true,
                includeConnections: true,
                includeResearch: true,
                includeIdeas: true,
                includeTasks: false,
                prioritizeRecent: true
            )
        case .large:
            return AssemblyConfig(
                maxTokens: 200_000,
                includeSwipeFile: true,
                includeConnections: true,
                includeResearch: true,
                includeIdeas: true,
                includeTasks: true,
                prioritizeRecent: true
            )
        case .massive:
            return AssemblyConfig(
                maxTokens: 500_000,
                includeSwipeFile: true,
                includeConnections: true,
                includeResearch: true,
                includeIdeas: true,
                includeTasks: true,
                prioritizeRecent: false  // Include everything
            )
        }
    }
}

// MARK: - Context Assembler Actor

/// Gathers comprehensive context for Gemini's 1M token window
public actor ContextAssembler {

    // MARK: - Singleton

    @MainActor public static let shared = ContextAssembler()

    // MARK: - Dependencies

    private let database: CosmoDatabase
    private let vectorDatabase: VectorDatabase

    // MARK: - Token Estimation

    /// Approximate tokens per character (GPT-style tokenization)
    private let tokensPerChar: Float = 0.25

    // MARK: - Initialization

    @MainActor
    private init() {
        self.database = CosmoDatabase.shared
        self.vectorDatabase = VectorDatabase.shared
    }

    // MARK: - Main Assembly API

    /// Assemble context for a generative query
    public func assemble(
        query: String,
        config: AssemblyConfig,
        hotContext: HotContext?
    ) async throws -> AssembledContext {
        let startTime = Date()

        var sources: [SourceReference] = []
        var contentSections: [String] = []
        var currentTokens = 0

        // 1. Add hot context (currently focused items)
        if let hotContext = hotContext {
            let (hotContent, hotSources) = await assembleHotContext(hotContext)
            contentSections.append(hotContent)
            sources.append(contentsOf: hotSources)
            currentTokens += estimateTokens(hotContent)
        }

        // 2. Add specifically referenced entities
        if let specificEntities = config.specificEntityIds, !specificEntities.isEmpty {
            let (specificContent, specificSources) = await assembleSpecificEntities(specificEntities)
            contentSections.append(specificContent)
            sources.append(contentsOf: specificSources)
            currentTokens += estimateTokens(specificContent)
        }

        // 3. Find semantically relevant content via vector search
        let remainingBudget = config.maxTokens - currentTokens
        let (semanticContent, semanticSources) = await assembleSemanticContent(
            query: query,
            config: config,
            tokenBudget: remainingBudget
        )
        contentSections.append(semanticContent)
        sources.append(contentsOf: semanticSources)
        currentTokens += estimateTokens(semanticContent)

        // 4. Build user context string
        let userContext = buildUserContext(query: query, hotContext: hotContext)

        // 5. Build system prompt (from GeminiPrompts - we'll keep a basic one here)
        let systemPrompt = buildSystemPrompt()

        let latencyMs = Date().timeIntervalSince(startTime) * 1000
        ConsoleLog.info(
            "ContextAssembler: Assembled \(currentTokens) tokens from \(sources.count) sources in \(String(format: "%.0f", latencyMs))ms",
            subsystem: .voice
        )

        return AssembledContext(
            systemPrompt: systemPrompt,
            userContext: userContext,
            relevantContent: contentSections.joined(separator: "\n\n---\n\n"),
            totalTokens: currentTokens,
            sources: sources
        )
    }

    // MARK: - Specialized Assemblers

    /// Assemble context for content ideas generation
    public func assembleForContentIdeas(
        topic: String,
        swipeFileCount: Int = 20,
        connectionCount: Int = 10
    ) async throws -> AssembledContext {
        var sources: [SourceReference] = []
        var contentSections: [String] = []

        // Get swipe file examples (prioritize recent/viral)
        let swipeFileContent = await assembleSwipeFile(limit: swipeFileCount)
        contentSections.append("## SWIPE FILE EXAMPLES\n\(swipeFileContent.content)")
        sources.append(contentsOf: swipeFileContent.sources)

        // Get relevant connections (mental models)
        let connectionsContent = await assembleConnections(
            query: topic,
            limit: connectionCount
        )
        contentSections.append("## MENTAL MODELS\n\(connectionsContent.content)")
        sources.append(contentsOf: connectionsContent.sources)

        // Get related ideas
        let ideasContent = await assembleIdeas(query: topic, limit: 10)
        contentSections.append("## RELATED IDEAS\n\(ideasContent.content)")
        sources.append(contentsOf: ideasContent.sources)

        let userContext = "User wants to generate content ideas about: \(topic)"
        let totalTokens = estimateTokens(contentSections.joined())

        return AssembledContext(
            systemPrompt: buildSystemPrompt(),
            userContext: userContext,
            relevantContent: contentSections.joined(separator: "\n\n"),
            totalTokens: totalTokens,
            sources: sources
        )
    }

    /// Assemble context for cross-domain analysis
    public func assembleForCrossDomainAnalysis(
        domains: [String],
        depthLevel: DepthLevel
    ) async throws -> AssembledContext {
        var sources: [SourceReference] = []
        var contentSections: [String] = []

        // For each domain, gather relevant content
        for domain in domains {
            let domainContent = await assembleDomain(domain: domain, depth: depthLevel)
            contentSections.append("## DOMAIN: \(domain.uppercased())\n\(domainContent.content)")
            sources.append(contentsOf: domainContent.sources)
        }

        let userContext = "User wants to find connections between domains: \(domains.joined(separator: ", "))"
        let totalTokens = estimateTokens(contentSections.joined())

        return AssembledContext(
            systemPrompt: buildSystemPrompt(),
            userContext: userContext,
            relevantContent: contentSections.joined(separator: "\n\n---\n\n"),
            totalTokens: totalTokens,
            sources: sources
        )
    }

    /// Assemble context for writing assistance
    public func assembleForWritingAssistance(
        currentDraft: String,
        referenceConnections: [Int64]
    ) async throws -> AssembledContext {
        var sources: [SourceReference] = []
        var contentSections: [String] = []

        // Include the current draft
        contentSections.append("## CURRENT DRAFT\n\(currentDraft)")

        // Get referenced connections
        for connectionId in referenceConnections {
            if let connection = await fetchConnection(id: connectionId) {
                let content = formatConnection(connection)
                let connectionTitle = connection.title ?? "Untitled"
                contentSections.append("## REFERENCE: \(connectionTitle)\n\(content)")
                sources.append(SourceReference(
                    entityType: "connection",
                    entityId: connectionId,
                    title: connectionTitle
                ))
            }
        }

        // Find semantically similar swipe file entries
        let swipeContent = await assembleSwipeFile(query: currentDraft, limit: 10)
        contentSections.append("## RELEVANT SWIPE FILE EXAMPLES\n\(swipeContent.content)")
        sources.append(contentsOf: swipeContent.sources)

        let userContext = "User is writing content and needs help improving it"
        let totalTokens = estimateTokens(contentSections.joined())

        return AssembledContext(
            systemPrompt: buildSystemPrompt(),
            userContext: userContext,
            relevantContent: contentSections.joined(separator: "\n\n"),
            totalTokens: totalTokens,
            sources: sources
        )
    }

    // MARK: - Content Assembly Helpers

    private func assembleHotContext(_ hotContext: HotContext) async -> (String, [SourceReference]) {
        var content = "## CURRENT FOCUS\n"
        var sources: [SourceReference] = []

        // Get top related connection from hot context
        if let topConnection = hotContext.relatedConnections.first {
            if let connection = await fetchConnection(id: topConnection.entityId) {
                let connectionTitle = connection.title ?? "Untitled"
                content += "### Related Connection: \(connectionTitle)\n"
                content += formatConnection(connection)
                sources.append(SourceReference(
                    entityType: "connection",
                    entityId: topConnection.entityId,
                    title: connectionTitle,
                    relevanceScore: topConnection.similarity
                ))
            }
        }

        // Get top related idea from hot context
        if let topIdea = hotContext.relatedIdeas.first {
            if let idea = await fetchIdea(id: topIdea.entityId) {
                content += "\n### Related Idea\n"
                content += "Title: \(idea.title ?? "Untitled")\n"
                content += idea.content
                sources.append(SourceReference(
                    entityType: "idea",
                    entityId: topIdea.entityId,
                    title: idea.title ?? "Untitled Idea",
                    relevanceScore: topIdea.similarity
                ))
            }
        }

        // Include last query context if available
        if !hotContext.lastQuery.isEmpty {
            content += "\n### Current Context Query\n"
            content += "User was working on: \"\(hotContext.lastQuery)\"\n"
        }

        return (content, sources)
    }

    private func assembleSpecificEntities(_ entities: [ContextEntityRef]) async -> (String, [SourceReference]) {
        var content = "## REFERENCED ITEMS\n"
        var sources: [SourceReference] = []

        for entity in entities {
            switch entity.entityType {
            case "connection":
                if let connection = await fetchConnection(id: entity.entityId) {
                    let connectionTitle = connection.title ?? "Untitled"
                    content += "\n### \(connectionTitle)\n"
                    content += formatConnection(connection)
                    sources.append(SourceReference(
                        entityType: "connection",
                        entityId: entity.entityId,
                        title: connectionTitle
                    ))
                }
            case "idea":
                if let idea = await fetchIdea(id: entity.entityId) {
                    content += "\n### \(idea.title ?? "Untitled Idea")\n"
                    content += idea.content
                    sources.append(SourceReference(
                        entityType: "idea",
                        entityId: entity.entityId,
                        title: idea.title ?? "Untitled Idea"
                    ))
                }
            case "research":
                if let research = await fetchResearch(id: entity.entityId) {
                    content += "\n### \(research.title ?? "Untitled Research")\n"
                    content += research.content
                    sources.append(SourceReference(
                        entityType: "research",
                        entityId: entity.entityId,
                        title: research.title ?? "Untitled Research"
                    ))
                }
            default:
                break
            }
        }

        return (content, sources)
    }

    private func assembleSemanticContent(
        query: String,
        config: AssemblyConfig,
        tokenBudget: Int
    ) async -> (String, [SourceReference]) {
        var content = "## SEMANTICALLY RELEVANT CONTENT\n"
        var sources: [SourceReference] = []
        var usedTokens = 0

        // Search vector database for relevant content
        do {
            let searchResults = try await vectorDatabase.search(
                query: query,
                limit: 50,
                minSimilarity: 0.4
            )

            for result in searchResults {
                guard usedTokens < tokenBudget else { break }

                // Filter by config
                let shouldInclude: Bool
                switch result.entityType {
                case "connection":
                    shouldInclude = config.includeConnections
                case "idea":
                    shouldInclude = config.includeIdeas
                case "research", "content":
                    shouldInclude = config.includeResearch
                case "task":
                    shouldInclude = config.includeTasks
                case "swipefile":
                    shouldInclude = config.includeSwipeFile
                default:
                    shouldInclude = true
                }

                guard shouldInclude else { continue }

                // Add content
                if let text = result.text {
                    let itemContent = "\n### [\(result.entityType)] (relevance: \(String(format: "%.2f", result.similarity)))\n\(text)\n"
                    let itemTokens = estimateTokens(itemContent)

                    if usedTokens + itemTokens <= tokenBudget {
                        content += itemContent
                        usedTokens += itemTokens
                        sources.append(SourceReference(
                            entityType: result.entityType,
                            entityId: result.entityId,
                            title: String(text.prefix(50)),
                            relevanceScore: result.similarity
                        ))
                    }
                }
            }
        } catch {
            ConsoleLog.warning("ContextAssembler: Vector search failed: \(error)", subsystem: .voice)
        }

        return (content, sources)
    }

    private func assembleSwipeFile(query: String? = nil, limit: Int = 20) async -> (content: String, sources: [SourceReference]) {
        var content = ""
        var sources: [SourceReference] = []

        do {
            // Use vector search if query provided, otherwise get recent
            let results: [VectorSearchResult]
            if let query = query {
                results = try await vectorDatabase.search(
                    query: query,
                    limit: limit,
                    entityTypeFilter: "swipefile"
                )
            } else {
                results = try await vectorDatabase.search(
                    query: "viral content hooks engagement",
                    limit: limit,
                    entityTypeFilter: "swipefile"
                )
            }

            for (index, result) in results.enumerated() {
                if let text = result.text {
                    content += "\n\(index + 1). \(text)\n"
                    sources.append(SourceReference(
                        entityType: "swipefile",
                        entityId: result.entityId,
                        title: String(text.prefix(40)),
                        relevanceScore: result.similarity
                    ))
                }
            }
        } catch {
            ConsoleLog.warning("ContextAssembler: Swipe file fetch failed: \(error)", subsystem: .voice)
        }

        return (content, sources)
    }

    private func assembleConnections(query: String, limit: Int = 10) async -> (content: String, sources: [SourceReference]) {
        var content = ""
        var sources: [SourceReference] = []

        do {
            let results = try await vectorDatabase.search(
                query: query,
                limit: limit,
                entityTypeFilter: "connection"
            )

            for result in results {
                if let connection = await fetchConnection(id: result.entityId) {
                    let connectionTitle = connection.title ?? "Untitled"
                    content += "\n### \(connectionTitle)\n"
                    content += formatConnection(connection)
                    sources.append(SourceReference(
                        entityType: "connection",
                        entityId: result.entityId,
                        title: connectionTitle,
                        relevanceScore: result.similarity
                    ))
                }
            }
        } catch {
            ConsoleLog.warning("ContextAssembler: Connections fetch failed: \(error)", subsystem: .voice)
        }

        return (content, sources)
    }

    private func assembleIdeas(query: String, limit: Int = 10) async -> (content: String, sources: [SourceReference]) {
        var content = ""
        var sources: [SourceReference] = []

        do {
            let results = try await vectorDatabase.search(
                query: query,
                limit: limit,
                entityTypeFilter: "idea"
            )

            for result in results {
                if let text = result.text {
                    content += "\n- \(text)\n"
                    sources.append(SourceReference(
                        entityType: "idea",
                        entityId: result.entityId,
                        title: String(text.prefix(40)),
                        relevanceScore: result.similarity
                    ))
                }
            }
        } catch {
            ConsoleLog.warning("ContextAssembler: Ideas fetch failed: \(error)", subsystem: .voice)
        }

        return (content, sources)
    }

    private func assembleDomain(domain: String, depth: DepthLevel) async -> (content: String, sources: [SourceReference]) {
        let limit: Int
        switch depth {
        case .shallow: limit = 5
        case .medium: limit = 15
        case .deep: limit = 30
        }

        var content = ""
        var sources: [SourceReference] = []

        do {
            let results = try await vectorDatabase.search(
                query: domain,
                limit: limit
            )

            for result in results {
                if let text = result.text {
                    content += "\n[\(result.entityType)] \(text)\n"
                    sources.append(SourceReference(
                        entityType: result.entityType,
                        entityId: result.entityId,
                        title: String(text.prefix(40)),
                        relevanceScore: result.similarity
                    ))
                }
            }
        } catch {
            ConsoleLog.warning("ContextAssembler: Domain fetch failed: \(error)", subsystem: .voice)
        }

        return (content, sources)
    }

    // MARK: - Database Fetch Helpers

    private func fetchConnection(id: Int64) async -> Connection? {
        await MainActor.run {
            ConnectionStore.shared.connection(for: id)
        }
    }

    private func fetchIdea(id: Int64) async -> Idea? {
        do {
            return try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("id") == id)
                    .fetchOne(db)
                    .map { IdeaWrapper(atom: $0) }
            }
        } catch {
            return nil
        }
    }

    private func fetchResearch(id: Int64) async -> Research? {
        do {
            return try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.research.rawValue)
                    .filter(Column("id") == id)
                    .fetchOne(db)
                    .map { ResearchWrapper(atom: $0) }
            }
        } catch {
            return nil
        }
    }

    // MARK: - Formatting Helpers

    private func formatConnection(_ connection: Connection) -> String {
        var content = ""
        let model = connection.mentalModelOrNew

        if let coreIdea = model.coreIdea, !coreIdea.isEmpty {
            content += "**Core Idea:** \(coreIdea)\n"
        }
        if let goal = model.goal, !goal.isEmpty {
            content += "**Goal:** \(goal)\n"
        }
        if let problem = model.problem, !problem.isEmpty {
            content += "**Problem:** \(problem)\n"
        }
        if let benefits = model.benefits, !benefits.isEmpty {
            content += "**Benefits:** \(benefits)\n"
        }
        if let beliefs = model.beliefsObjections, !beliefs.isEmpty {
            content += "**Beliefs/Objections:** \(beliefs)\n"
        }
        if let example = model.example, !example.isEmpty {
            content += "**Example:** \(example)\n"
        }
        if let process = model.process, !process.isEmpty {
            content += "**Process:** \(process)\n"
        }

        return content
    }

    private func buildUserContext(query: String, hotContext: HotContext?) -> String {
        var context = "User query: \"\(query)\"\n"

        if let hot = hotContext {
            if !hot.relatedConnections.isEmpty {
                context += "Has \(hot.relatedConnections.count) related Connection(s) in context.\n"
            }
            if !hot.relatedIdeas.isEmpty {
                context += "Has \(hot.relatedIdeas.count) related Idea(s) in context.\n"
            }
            if !hot.relatedTasks.isEmpty {
                context += "Has \(hot.relatedTasks.count) related Task(s) in context.\n"
            }
            if !hot.lastQuery.isEmpty {
                context += "Previous focus: \"\(hot.lastQuery)\"\n"
            }
        }

        return context
    }

    private func buildSystemPrompt() -> String {
        // Basic system prompt - full prompts will be in GeminiPrompts.swift
        """
        You are Cosmo's Generative Intelligence - an AI that helps synthesize, create, and discover novel connections across a personal knowledge base.

        You excel at:
        - Creative content ideation combining multiple sources
        - Finding unexpected parallels across domains
        - Building unified frameworks from diverse concepts
        - Generating original ideas in the user's voice and style

        Guidelines:
        - Be specific and actionable, not generic
        - Reference specific items from the provided context
        - Explain the "why" behind connections
        - Only use information from the provided context
        - If context is insufficient, say so rather than fabricating
        """
    }

    // MARK: - Token Estimation

    private func estimateTokens(_ text: String) -> Int {
        Int(Float(text.count) * tokensPerChar)
    }
}

// MARK: - Context Assembler Errors

public enum ContextAssemblerError: LocalizedError {
    case noContentFound
    case tokenBudgetExceeded
    case databaseError(String)

    public var errorDescription: String? {
        switch self {
        case .noContentFound:
            return "No relevant content found for the query"
        case .tokenBudgetExceeded:
            return "Token budget exceeded during assembly"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}
