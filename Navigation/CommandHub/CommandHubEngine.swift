// CosmoOS/Navigation/CommandHub/CommandHubEngine.swift
// Semantic Search Engine for Command Hub
// 3-tier search: Instant → Semantic → LLM

import Foundation
import SwiftUI
import GRDB
import Combine

@MainActor
class CommandHubEngine: ObservableObject {
    @Published var results: [PaletteResult] = []
    @Published var defaultItems: [PaletteResult] = []
    @Published var recents: [PaletteResult] = []
    @Published var isSearching = false
    @Published var searchTier: SearchTier = .instant
    @Published var isContextAwareMode = false

    private let database = CosmoDatabase.shared
    private let semanticSearch = SemanticSearchEngine.shared
    private let localLLM = LocalLLM.shared
    private let editingContext = EditingContextTracker.shared
    private var searchTask: Task<Void, Never>?
    private var debounceTimer: Timer?
    private var contextSimilarityCache: [String: Float] = [:]

    // Search tier tracking
    enum SearchTier: String {
        case instant    // < 5ms - prefix matching
        case semantic   // < 15ms - vector similarity
        case llm        // < 50ms - natural language understanding
    }

    // MARK: - Load Defaults
    func loadDefaults() {
        var items: [PaletteResult] = []

        // Quick actions - voice-first design
        items.append(contentsOf: [
            PaletteResult(
                icon: "calendar",
                iconColor: CosmoColors.coral,
                title: "Open Calendar",
                subtitle: "View and manage your schedule",
                shortcut: "⌘K C",
                type: .command("open_calendar_window")
            ),
            PaletteResult(
                icon: "plus.circle.fill",
                iconColor: CosmoColors.lavender,
                title: "New Idea",
                subtitle: "Capture a new thought",
                shortcut: "⌘N",
                type: .create(.idea)
            ),
            PaletteResult(
                icon: "doc.text.fill",
                iconColor: CosmoColors.skyBlue,
                title: "New Content",
                subtitle: "Start writing",
                type: .create(.content)
            ),
            PaletteResult(
                icon: "checkmark.circle.fill",
                iconColor: CosmoColors.coral,
                title: "New Task",
                subtitle: "Add something to do",
                shortcut: "⌘T",
                type: .create(.task)
            ),
            PaletteResult(
                icon: "brain.head.profile",
                iconColor: CosmoColors.cosmoAI,
                title: "Ask Cosmo",
                subtitle: "Chat with your AI assistant",
                type: .command("open_cosmo")
            )
        ])

        // Categories
        items.append(contentsOf: [
            PaletteResult(
                icon: "lightbulb.fill",
                iconColor: CosmoColors.lavender,
                title: "Browse Ideas",
                subtitle: "All your ideas",
                type: .category(.ideas)
            ),
            PaletteResult(
                icon: "doc.text.fill",
                iconColor: CosmoColors.skyBlue,
                title: "Browse Content",
                subtitle: "Documents and writing",
                type: .category(.content)
            ),
            PaletteResult(
                icon: "magnifyingglass",
                iconColor: CosmoColors.emerald,
                title: "Browse Research",
                subtitle: "Saved research",
                type: .category(.research)
            ),
            PaletteResult(
                icon: "rectangle.3.group",
                iconColor: CosmoColors.thinkspacePurple,
                title: "Browse Thinkspaces",
                subtitle: "Saved canvas workspaces",
                type: .category(.thinkspaces)
            )
        ])

        defaultItems = items

        // Load recents in background
        Task {
            await loadRecents()
        }
    }

    // MARK: - Load Recents
    private func loadRecents() async {
        do {
            // Fetch recently updated entities across all types
            let ideas: [Idea] = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("is_deleted") == false)
                    .order(Column("updated_at").desc)
                    .limit(5)
                    .fetchAll(db)
                    .map { IdeaWrapper(atom: $0) }
            }

            recents = ideas.map { idea in
                PaletteResult(
                    icon: "lightbulb.fill",
                    iconColor: CosmoColors.lavender,
                    title: idea.title ?? "Untitled Idea",
                    subtitle: String(idea.content.prefix(50)),
                    type: .entity(.idea, idea.id ?? -1)
                )
            }
        } catch {
            print("❌ Failed to load recents: \(error)")
        }
    }

    // MARK: - 3-Tier Search
    func search(_ query: String) {
        // Cancel previous search
        searchTask?.cancel()
        debounceTimer?.invalidate()

        guard !query.isEmpty else {
            results = []
            searchTier = .instant
            return
        }

        isSearching = true
        searchTier = .instant

        // Tier 1: Instant search (no debounce) - < 5ms
        performInstantSearch(query)

        // Tier 2: Semantic search with slight debounce - < 15ms
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performSemanticSearch(query)
            }
        }
    }

    // MARK: - Tier 1: Instant Search (Prefix Matching)
    private func performInstantSearch(_ query: String) {
        let lowered = query.lowercased()
        var instantResults: [PaletteResult] = []

        // Check for URL - offer to save as research
        if let urlResult = detectURL(query) {
            instantResults.append(urlResult)
            results = instantResults
            isSearching = false
            return
        }

        // Check for command patterns
        let commands = parseCommands(query)
        if !commands.isEmpty {
            instantResults.append(contentsOf: commands)
        }

        // Quick filter of default items by prefix
        let matchingDefaults = defaultItems.filter { item in
            item.title.lowercased().hasPrefix(lowered) ||
            item.title.lowercased().contains(lowered)
        }
        instantResults.append(contentsOf: matchingDefaults)

        // Quick filter of recents
        let matchingRecents = recents.filter { item in
            item.title.lowercased().contains(lowered)
        }
        instantResults.append(contentsOf: matchingRecents)

        results = Array(instantResults.prefix(10))
    }

    // MARK: - Tier 2: Semantic Search (Vector Similarity)
    private func performSemanticSearch(_ query: String) async {
        searchTier = .semantic

        var semanticResults: [PaletteResult] = []

        // Search all entity types
        async let ideasTask = searchIdeas(query: query)
        async let contentTask = searchContent(query: query)
        async let tasksTask = searchTasks(query: query)
        async let researchTask = searchResearch(query: query)
        async let connectionsTask = searchConnections(query: query)
        async let thinkspacesTask = searchThinkspaces(query: query)

        let (ideas, content, tasks, research, connections, thinkspaces) = await (
            ideasTask, contentTask, tasksTask, researchTask, connectionsTask, thinkspacesTask
        )

        semanticResults.append(contentsOf: ideas)
        semanticResults.append(contentsOf: content)
        semanticResults.append(contentsOf: tasks)
        semanticResults.append(contentsOf: research)
        semanticResults.append(contentsOf: connections)
        semanticResults.append(contentsOf: thinkspaces)

        // Check if we have editing context for context-aware ranking
        let contextSnapshot = editingContext.snapshot()

        if let contextVector = contextSnapshot.contextVector, !contextVector.isEmpty {
            // Focus Mode: Apply context-aware ranking
            isContextAwareMode = true
            contextSimilarityCache.removeAll() // Invalidate cache for new search
            semanticResults = await applyContextAwareRanking(to: semanticResults, contextVector: contextVector)
        } else {
            // Home Page: Sort by text-based relevance score
            isContextAwareMode = false
            semanticResults.sort { a, b in
                scoreMatch(query: query, title: a.title, subtitle: a.subtitle) >
                scoreMatch(query: query, title: b.title, subtitle: b.subtitle)
            }
        }

        // Merge with instant results (keeping instant at top for commands)
        var mergedResults = results.filter { result in
            if case .command = result.type { return true }
            if case .create = result.type { return true }
            if case .saveURL = result.type { return true }
            return false
        }
        mergedResults.append(contentsOf: semanticResults)

        results = Array(mergedResults.prefix(25))
        isSearching = false

        // Tier 3: LLM for complex queries (if needed)
        if semanticResults.isEmpty && query.split(separator: " ").count >= 3 {
            await performLLMSearch(query)
        }
    }

    // MARK: - Tier 3: LLM Search (Natural Language Understanding)
    private func performLLMSearch(_ query: String) async {
        searchTier = .llm

        // Use LocalLLM to understand intent
        let prompt = """
        The user is searching for: "\(query)"

        Interpret this as a search query and extract:
        1. Entity type (idea, content, task, research, connection, project)
        2. Key search terms
        3. Any temporal context (today, this week, recent)

        Respond in JSON format: {"type": "...", "terms": [...], "temporal": "..."}
        """

        let response = await localLLM.generate(prompt: prompt, maxTokens: 100)

        // Parse LLM response and refine search
        // This is a simplified implementation - in production, parse the JSON
        print("🧠 LLM search interpretation: \(response)")

        // Re-run semantic search with extracted terms if parsing succeeds
        // For now, we'll just log the LLM's interpretation
    }

    // MARK: - URL Detection
    private func detectURL(_ query: String) -> PaletteResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.looksLikeURL,
              let urlType = URLClassifier.classify(trimmed) else {
            return nil
        }

        let (icon, color, subtitle) = urlTypeInfo(urlType)

        return PaletteResult(
            icon: icon,
            iconColor: color,
            title: "Save to Research",
            subtitle: subtitle,
            type: .saveURL(trimmed, urlType)
        )
    }

    private func urlTypeInfo(_ type: URLType) -> (icon: String, color: Color, subtitle: String) {
        switch type {
        case .youtube(let videoId):
            return ("play.rectangle.fill", CosmoColors.softRed, "YouTube video • \(videoId)")
        case .twitter:
            return ("bubble.left.fill", CosmoColors.skyBlue, "Tweet • Will embed")
        case .loom(let videoId):
            return ("video.bubble.fill", Color(hex: "#625DF5"), "Loom video • \(videoId)")
        case .pdf:
            return ("doc.fill", CosmoColors.coral, "PDF document")
        case .website:
            return ("globe", CosmoColors.emerald, "Website • Will capture screenshot")
        }
    }

    // MARK: - Command Parsing
    private func parseCommands(_ query: String) -> [PaletteResult] {
        let lowered = query.lowercased()
        var commands: [PaletteResult] = []

        // "new idea", "create idea"
        if lowered.hasPrefix("new ") || lowered.hasPrefix("create ") {
            if lowered.contains("idea") {
                commands.append(PaletteResult(
                    icon: "plus.circle.fill",
                    iconColor: CosmoColors.lavender,
                    title: "Create New Idea",
                    subtitle: "Create and start editing",
                    type: .create(.idea)
                ))
            }
            if lowered.contains("task") {
                commands.append(PaletteResult(
                    icon: "plus.circle.fill",
                    iconColor: CosmoColors.coral,
                    title: "Create New Task",
                    subtitle: "Add a new task",
                    type: .create(.task)
                ))
            }
            if lowered.contains("content") || lowered.contains("doc") {
                commands.append(PaletteResult(
                    icon: "plus.circle.fill",
                    iconColor: CosmoColors.skyBlue,
                    title: "Create New Content",
                    subtitle: "Start writing",
                    type: .create(.content)
                ))
            }
            if lowered.contains("project") {
                commands.append(PaletteResult(
                    icon: "plus.circle.fill",
                    iconColor: CosmoColors.emerald,
                    title: "Create New Project",
                    subtitle: "Start a new project",
                    type: .create(.project)
                ))
            }
        }

        // "go to", "open"
        if lowered.hasPrefix("go to ") || lowered.hasPrefix("open ") {
            if lowered.contains("calendar") {
                commands.append(PaletteResult(
                    icon: "calendar",
                    iconColor: CosmoColors.coral,
                    title: "Open Calendar",
                    subtitle: "View your schedule",
                    type: .command("open_calendar_window")
                ))
            }
            if lowered.contains("idea") {
                commands.append(PaletteResult(
                    icon: "lightbulb.fill",
                    iconColor: CosmoColors.lavender,
                    title: "Open Ideas",
                    subtitle: "Browse all ideas",
                    type: .category(.ideas)
                ))
            }
            if lowered.contains("cosmo") || lowered.contains("ai") || lowered.contains("assistant") {
                commands.append(PaletteResult(
                    icon: "brain.head.profile",
                    iconColor: CosmoColors.cosmoAI,
                    title: "Open Cosmo AI",
                    subtitle: "Chat with your AI assistant",
                    type: .command("open_cosmo")
                ))
            }
        }

        // Natural language queries
        if lowered.contains("show me") || lowered.contains("find") || lowered.contains("search") {
            // Let semantic search handle these
            return []
        }

        return commands
    }

    // MARK: - Entity Search Methods
    private func searchIdeas(query: String) async -> [PaletteResult] {
        do {
            let ideas: [Idea] = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(
                        Column("title").like("%\(query)%") ||
                        Column("body").like("%\(query)%")
                    )
                    .order(Column("updated_at").desc)
                    .limit(10)
                    .fetchAll(db)
                    .map { IdeaWrapper(atom: $0) }
            }

            return ideas.map { idea in
                PaletteResult(
                    icon: "lightbulb.fill",
                    iconColor: CosmoColors.lavender,
                    title: idea.title ?? "Untitled Idea",
                    subtitle: String(idea.content.prefix(60)),
                    type: .entity(.idea, idea.id ?? -1)
                )
            }
        } catch {
            return []
        }
    }

    private func searchContent(query: String) async -> [PaletteResult] {
        do {
            let content: [CosmoContent] = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(
                        Column("title").like("%\(query)%") ||
                        Column("body").like("%\(query)%")
                    )
                    .order(Column("updated_at").desc)
                    .limit(10)
                    .fetchAll(db)
                    .map { ContentWrapper(atom: $0) }
            }

            return content.map { item in
                PaletteResult(
                    icon: "doc.text.fill",
                    iconColor: CosmoColors.skyBlue,
                    title: item.title ?? "Untitled",
                    subtitle: item.body?.prefix(60).description ?? "Document",
                    type: .entity(.content, item.id ?? -1)
                )
            }
        } catch {
            return []
        }
    }

    private func searchTasks(query: String) async -> [PaletteResult] {
        do {
            let tasks: [CosmoTask] = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.task.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("title").like("%\(query)%"))
                    .order(Column("updated_at").desc)
                    .limit(10)
                    .fetchAll(db)
                    .map { TaskWrapper(atom: $0) }
            }

            return tasks.map { task in
                PaletteResult(
                    icon: task.status == "completed" ? "checkmark.circle.fill" : "circle",
                    iconColor: CosmoColors.coral,
                    title: task.title ?? "Untitled",
                    subtitle: task.status.capitalized,
                    type: .entity(.task, task.id ?? -1)
                )
            }
        } catch {
            return []
        }
    }

    private func searchResearch(query: String) async -> [PaletteResult] {
        do {
            let research: [Research] = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.research.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(
                        Column("title").like("%\(query)%") ||
                        Column("body").like("%\(query)%")
                    )
                    .order(Column("updated_at").desc)
                    .limit(10)
                    .fetchAll(db)
                    .map { ResearchWrapper(atom: $0) }
            }

            return research.map { item in
                let (icon, color) = researchIconInfo(for: item)
                return PaletteResult(
                    icon: icon,
                    iconColor: color,
                    title: item.title ?? "Untitled",
                    subtitle: item.domain ?? item.summary?.prefix(60).description ?? "Research",
                    type: .entity(.research, item.id ?? -1)
                )
            }
        } catch {
            return []
        }
    }

    private func researchIconInfo(for research: Research) -> (String, Color) {
        guard let sourceType = research.sourceType else {
            return ("magnifyingglass", CosmoColors.emerald)
        }
        switch sourceType {
        case .youtube, .youtubeShort: return ("play.rectangle.fill", CosmoColors.softRed)
        case .twitter, .xPost: return ("bubble.left.fill", CosmoColors.skyBlue)
        case .loom: return ("video.bubble.fill", Color(hex: "#625DF5"))
        case .threads: return ("at", Color(hex: "#000000"))
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel: return ("camera.fill", Color(hex: "#DD2A7B"))
        case .rawNote: return ("note.text", CosmoColors.lavender)
        case .pdf: return ("doc.fill", CosmoColors.coral)
        case .website: return ("globe", CosmoColors.emerald)
        case .podcast: return ("waveform", CosmoColors.lavender)
        case .article: return ("doc.text", CosmoColors.skyBlue)
        case .book: return ("book.fill", CosmoColors.emerald)
        case .tiktok: return ("music.note", CosmoColors.softRed)
        case .other, .unknown: return ("magnifyingglass", CosmoColors.emerald)
        }
    }

    private func searchConnections(query: String) async -> [PaletteResult] {
        do {
            let connections: [Connection] = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.connection.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("title").like("%\(query)%"))
                    .order(Column("updated_at").desc)
                    .limit(10)
                    .fetchAll(db)
                    .map { ConnectionWrapper(atom: $0) }
            }

            return connections.map { item in
                PaletteResult(
                    icon: "link.circle.fill",
                    iconColor: CosmoMentionColors.connection,
                    title: item.title ?? "Untitled",
                    subtitle: item.mentalModelOrNew.coreIdea?.prefix(60).description ?? "Mental model",
                    type: .entity(.connection, item.id ?? -1)
                )
            }
        } catch {
            return []
        }
    }

    private func searchThinkspaces(query: String) async -> [PaletteResult] {
        do {
            let thinkspaces: [Atom] = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.thinkspace.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("title").like("%\(query)%"))
                    .order(Column("updated_at").desc)
                    .limit(10)
                    .fetchAll(db)
            }

            return thinkspaces.map { atom in
                // Parse metadata to get block count
                var blockCount = 0
                if let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
                    blockCount = metadata.blockIds.count
                }

                return PaletteResult(
                    icon: "rectangle.3.group",
                    iconColor: CosmoColors.thinkspacePurple,
                    title: atom.title ?? "Untitled Thinkspace",
                    subtitle: "\(blockCount) blocks",
                    type: .entity(.thinkspace, atom.id ?? -1)
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Scoring
    private func scoreMatch(query: String, title: String, subtitle: String?) -> Int {
        let lowQuery = query.lowercased()
        let lowTitle = title.lowercased()

        var score = 0

        // Exact title match
        if lowTitle == lowQuery {
            score += 100
        }
        // Title starts with query
        else if lowTitle.hasPrefix(lowQuery) {
            score += 75
        }
        // Title contains query
        else if lowTitle.contains(lowQuery) {
            score += 50
        }

        // Word boundary bonus
        let queryWords = lowQuery.split(separator: " ")
        for word in queryWords {
            if lowTitle.contains(word) {
                score += 10
            }
        }

        // Subtitle contains query
        if let sub = subtitle?.lowercased(), sub.contains(lowQuery) {
            score += 25
        }

        return score
    }

    // MARK: - Context-Aware Ranking (Telepathy Integration)

    /// Re-rank results based on semantic similarity to current editing context
    /// Only called when in Focus Mode (editing context has a vector)
    private func applyContextAwareRanking(
        to results: [PaletteResult],
        contextVector: [Float]
    ) async -> [PaletteResult] {
        // Only rank top 50 for performance
        let candidateCount = min(results.count, 50)
        let candidates = Array(results.prefix(candidateCount))
        let remainder = Array(results.dropFirst(candidateCount))

        var scoredResults: [(result: PaletteResult, contextScore: Float)] = []

        for result in candidates {
            guard case .entity(let entityType, let entityId) = result.type else {
                // Commands, categories, etc. don't get context scoring - keep them but with 0 score
                scoredResults.append((result, 0))
                continue
            }

            let similarity = await getContextSimilarity(
                entityType: entityType,
                entityId: entityId,
                contextVector: contextVector
            )
            scoredResults.append((result, similarity))
        }

        // Sort by context similarity (higher = more relevant to what you're writing)
        scoredResults.sort { $0.contextScore > $1.contextScore }

        return scoredResults.map { $0.result } + remainder
    }

    /// Get similarity between an entity's stored vector and the current editing context vector
    private func getContextSimilarity(
        entityType: EntityType,
        entityId: Int64,
        contextVector: [Float]
    ) async -> Float {
        let cacheKey = "\(entityType.rawValue):\(entityId)"

        // Check cache first
        if let cached = contextSimilarityCache[cacheKey] {
            return cached
        }

        do {
            // Query VectorDatabase for vectors matching this entity
            let results = try await VectorDatabase.shared.searchByVector(
                embedding: contextVector,
                limit: 100,
                entityTypeFilter: entityType.rawValue,
                minSimilarity: 0.0 // Get all matches, we'll use the score
            )

            // Find this specific entity's similarity
            let similarity = results.first { $0.entityId == entityId }?.similarity ?? 0

            // Cache the result
            contextSimilarityCache[cacheKey] = similarity
            return similarity
        } catch {
            print("⚠️ Context similarity lookup failed: \(error)")
            return 0
        }
    }
}

// MARK: - Palette Result Model

struct PaletteResult: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var shortcut: String? = nil
    let type: PaletteResultType
}

enum PaletteResultType: Equatable {
    case entity(EntityType, Int64)
    case command(String)
    case category(LibrarySection)
    case create(EntityType)
    case saveURL(String, URLType)
    
    static func == (lhs: PaletteResultType, rhs: PaletteResultType) -> Bool {
        switch (lhs, rhs) {
        case (.entity(let t1, let id1), .entity(let t2, let id2)):
            return t1 == t2 && id1 == id2
        case (.command(let c1), .command(let c2)):
            return c1 == c2
        case (.category(let s1), .category(let s2)):
            return s1 == s2
        case (.create(let e1), .create(let e2)):
            return e1 == e2
        case (.saveURL(let u1, let t1), .saveURL(let u2, let t2)):
            return u1 == u2 && t1 == t2
        default:
            return false
        }
    }
}

// MARK: - Library Section

enum LibrarySection: String, CaseIterable {
    case ideas
    case content
    case research
    case connections
    case projects
    case tasks
    case thinkspaces
}
