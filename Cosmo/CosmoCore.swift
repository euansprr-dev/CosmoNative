// CosmoOS/Cosmo/CosmoCore.swift
// The heart of CosmoOS - Local-first AI with research capabilities
// Uses local LLM for most queries, OpenRouter/Perplexity for web research
// Deep Foundation Models integration for proactive intelligence

import Foundation
import SwiftUI
import GRDB

// MARK: - Cosmo Core
@MainActor
class CosmoCore: ObservableObject {
    static let shared = CosmoCore()

    // Published state
    @Published var isProcessing = false
    @Published var currentAction: CosmoAction?
    @Published var messages: [CosmoMessage] = []
    @Published var isResearching = false
    @Published var researchProgress: Double = 0

    // Proactive Intelligence state
    @Published var proactiveSuggestions: [ProactiveSuggestion] = []
    @Published var lastSuggestionTime: Date?
    @Published var userActivityPattern: UserActivityPattern?

    // Dependencies
    private let localLLM = LocalLLM.shared
    let database = CosmoDatabase.shared
    private let semanticSearch = SemanticSearchEngine.shared
    private let researchService = ResearchService.shared
    private let notificationService = ProactiveNotificationService.shared

    // Deep LLM Integration components
    private let confidenceCalibrator = ConfidenceCalibrator.shared
    private let entityTracker = EntityMentionTracker.shared

    // Proactive intelligence timer
    private var proactiveTimer: Timer?
    private let proactiveSuggestionInterval: TimeInterval = 300  // 5 minutes

    private init() {
        // Load conversation history
        loadRecentMessages()
        // Start proactive intelligence
        startProactiveIntelligence()
        // Setup response cache observer
        setupCacheObserver()
    }

    // MARK: - Proactive Intelligence

    private func startProactiveIntelligence() {
        proactiveTimer = Timer.scheduledTimer(withTimeInterval: proactiveSuggestionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.generateProactiveSuggestions()
            }
        }
        print("🧠 Proactive intelligence started (interval: \(Int(proactiveSuggestionInterval))s)")
    }

    func generateProactiveSuggestions() async {
        guard !isProcessing else { return }

        do {
            // Analyze recent activity
            let recentIdeas = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("is_deleted") == false)
                    .order(Column("updated_at").desc)
                    .limit(10)
                    .fetchAll(db)
                    .map { IdeaWrapper(atom: $0) }
            }

            let incompleteTasks = try await database.asyncRead { db in
                // Note: status/priority are in metadata JSON, not table columns
                // Fetch tasks and filter in-memory using wrapper properties
                try Atom
                    .filter(Column("type") == AtomType.task.rawValue)
                    .filter(Column("is_deleted") == false)
                    .order(Column("updated_at").desc)
                    .limit(20)
                    .fetchAll(db)
                    .map { TaskWrapper(atom: $0) }
                    .filter { $0.status != "completed" }
                    .prefix(5)
                    .map { $0 }
            }

            var suggestions: [ProactiveSuggestion] = []

            // Suggest connecting lonely ideas
            let lonelyIdeas = recentIdeas.filter { $0.connectionId == nil }
            if lonelyIdeas.count >= 2 {
                suggestions.append(ProactiveSuggestion(
                    type: .connect,
                    title: "Connect related ideas",
                    description: "You have \(lonelyIdeas.count) unconnected ideas. Want me to suggest connections?",
                    action: .suggestConnections(ideaIds: lonelyIdeas.compactMap { $0.id }),
                    priority: .medium
                ))
            }

            // Suggest overdue task review
            if !incompleteTasks.isEmpty {
                suggestions.append(ProactiveSuggestion(
                    type: .taskReminder,
                    title: "Task check-in",
                    description: "You have \(incompleteTasks.count) open tasks. Focus on '\(incompleteTasks.first?.title ?? "top task")'?",
                    action: .focusOnTask(taskId: incompleteTasks.first?.id ?? 0),
                    priority: .high
                ))
            }

            // Suggest canvas organization if cluttered
            let canvasBlocks = try await database.asyncRead { db in
                try CanvasBlockRecord
                    .filter(sql: "is_deleted = 0")
                    .fetchCount(db)
            }

            if canvasBlocks > 15 {
                suggestions.append(ProactiveSuggestion(
                    type: .organize,
                    title: "Organize your canvas",
                    description: "Your canvas has \(canvasBlocks) blocks. Want me to arrange them semantically?",
                    action: .organizeCanvas,
                    priority: .low
                ))
            }

            // Update published suggestions
            proactiveSuggestions = suggestions.sorted { $0.priority.rawValue > $1.priority.rawValue }
            lastSuggestionTime = Date()

            if !suggestions.isEmpty {
                print("💡 Generated \(suggestions.count) proactive suggestions")
            }

        } catch {
            print("⚠️ Proactive suggestion generation failed: \(error)")
        }
    }

    func executeProactiveSuggestion(_ suggestion: ProactiveSuggestion) async {
        switch suggestion.action {
        case .suggestConnections(let ideaIds):
            // Use LLM to find best connections
            print("🔗 Analyzing \(ideaIds.count) ideas for potential connections...")
            // This would trigger the knowledge graph tools

        case .focusOnTask(let taskId):
            NotificationCenter.default.post(
                name: .navigateToSection,
                object: nil,
                userInfo: ["section": NavigationSection.today, "taskId": taskId]
            )

        case .organizeCanvas:
            _ = await process("organize my canvas semantically")

        case .startResearchOnTopic(let topic):
            _ = await process("research \(topic)")
        }

        // Remove executed suggestion
        proactiveSuggestions.removeAll { $0.id == suggestion.id }
    }

    private func setupCacheObserver() {
        Task {
            await ResponseCache.shared.setupDatabaseObserver(database: database)
        }
    }

    // MARK: - Process User Input
    func process(_ input: String, context: CosmoContext? = nil) async -> CosmoResponse {
        isProcessing = true
        defer { isProcessing = false }

        // Save user message
        let userMessage = CosmoMessage(
            role: .user,
            content: input,
            timestamp: Date()
        )
        messages.append(userMessage)
        await saveMessage(userMessage)

        // Determine intent
        let intent = await classifyIntent(input)
        print("🧠 Cosmo intent: \(intent)")

        // Route to appropriate handler
        let response: CosmoResponse

        switch intent {
        case .research(let query):
            // Web research - use OpenRouter/Perplexity
            response = await handleResearch(query: query, originalInput: input)

        case .createEntity(let type, let details):
            // Create idea/task/content - local only
            response = await handleCreateEntity(type: type, details: details)

        case .search(let query):
            // Semantic search - local embeddings
            response = await handleSearch(query: query)

        case .schedule(let details):
            // Calendar scheduling - local + AI
            response = await handleSchedule(details: details)

        case .navigation(let destination):
            // Navigate to section
            response = await handleNavigation(destination: destination)

        case .question(let query):
            // General question - local LLM
            response = await handleQuestion(query: query, context: context)

        case .canvas(let action):
            // Canvas operations
            response = await handleCanvasAction(action: action, input: input)

        case .unknown:
            // Default to local LLM
            response = await handleQuestion(query: input, context: context)
        }

        // Save assistant message
        let assistantMessage = CosmoMessage(
            role: .assistant,
            content: response.message,
            timestamp: Date(),
            entities: response.entities,
            actions: response.suggestedActions
        )
        messages.append(assistantMessage)
        await saveMessage(assistantMessage)

        return response
    }

    // MARK: - Intent Classification
    private func classifyIntent(_ input: String) async -> CosmoIntent {
        let lowered = input.lowercased()

        // Research patterns (→ OpenRouter/Perplexity)
        let researchPatterns = [
            "research", "look up", "find out", "search online",
            "what's the latest", "news about", "find me",
            "reddit", "pain points", "look into"
        ]

        for pattern in researchPatterns {
            if lowered.contains(pattern) {
                let query = extractQuery(from: input, trigger: pattern)
                return .research(query: query)
            }
        }

        // Create patterns
        if lowered.contains("create idea") || lowered.contains("new idea") {
            return .createEntity(type: .idea, details: input)
        }
        if lowered.contains("create task") || lowered.contains("new task") || lowered.contains("add task") {
            return .createEntity(type: .task, details: input)
        }
        if lowered.contains("create note") || lowered.contains("new note") {
            return .createEntity(type: .content, details: input)
        }

        // Search patterns
        if lowered.contains("find") || lowered.contains("search") || lowered.starts(with: "what") {
            if !researchPatterns.contains(where: { lowered.contains($0) }) {
                return .search(query: input)
            }
        }

        // Schedule patterns
        if lowered.contains("schedule") || lowered.contains("remind me") || lowered.contains("set up") {
            return .schedule(details: input)
        }

        // Navigation patterns
        if lowered.contains("go to") || lowered.contains("open") || lowered.contains("show me") {
            return .navigation(destination: input)
        }

        // Canvas patterns
        if lowered.contains("canvas") || lowered.contains("place") || lowered.contains("arrange") {
            return .canvas(action: input)
        }

        // Default to question
        return .question(query: input)
    }

    private func extractQuery(from input: String, trigger: String) -> String {
        if let range = input.lowercased().range(of: trigger) {
            let afterTrigger = input[range.upperBound...]
            return afterTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return input
    }

    // MARK: - Research Handler (OpenRouter/Perplexity)
    private func handleResearch(query: String, originalInput: String) async -> CosmoResponse {
        isResearching = true
        researchProgress = 0.1

        defer {
            isResearching = false
            researchProgress = 0
        }

        print("🔬 Cosmo: Initiating web research via Perplexity...")

        do {
            researchProgress = 0.3

            // Call research service (uses OpenRouter/Perplexity)
            let results = try await researchService.performResearch(
                query: query,
                searchType: .web,
                maxResults: 5
            )

            researchProgress = 0.7

            // Save research to database
            let initialResearch = Research.new(
                title: "Research: \(query)",
                query: query,
                url: nil,
                sourceType: .website
            )
            let research = try await database.asyncWrite { db -> Research in
                var mutableResearch = initialResearch
                if let findingsData = try? JSONEncoder().encode(results.findings) {
                    mutableResearch.findings = String(data: findingsData, encoding: .utf8)
                } else {
                    mutableResearch.findings = nil
                }
                mutableResearch.summary = results.summary
                mutableResearch.processingStatus = "completed"
                try mutableResearch.insert(db)
                return mutableResearch
            }

            researchProgress = 1.0

            // Format response
            let response = formatResearchResponse(results)

            return CosmoResponse(
                message: response,
                entities: [EntityReference(type: .research, id: research.id ?? -1, title: research.title ?? "Research")],
                suggestedActions: [
                    .openEntity(type: .research, id: research.id ?? -1),
                    .placeOnCanvas(entityType: .research, count: 1)
                ]
            )

        } catch {
            print("❌ Research failed: \(error)")
            return CosmoResponse(
                message: "I couldn't complete the research. Error: \(error.localizedDescription)",
                entities: [],
                suggestedActions: []
            )
        }
    }

    private func formatResearchResponse(_ results: ResearchResult) -> String {
        var response = "📚 **Research Complete**\n\n"
        response += results.summary + "\n\n"

        if !results.findings.isEmpty {
            response += "**Key Findings:**\n"
            for (index, finding) in results.findings.prefix(5).enumerated() {
                response += "\(index + 1). \(finding.title)\n"
                if let snippet = finding.snippet {
                    response += "   \(snippet.prefix(100))...\n"
                }
            }
        }

        return response
    }

    // MARK: - Create Entity Handler (Local Only)
    private func handleCreateEntity(type: EntityType, details: String) async -> CosmoResponse {
        print("📝 Cosmo: Creating \(type.rawValue) locally...")

        // Extract title and content from details
        let parsed = await localLLM.parseEntityDetails(details)

        do {
            var entityId: Int64 = -1
            var entityTitle = ""

            switch type {
            case .idea:
                let idea = try await database.asyncWrite { db -> Idea in
                    var newIdea = Idea.new(
                        title: parsed.title,
                        content: parsed.content ?? details
                    )
                    try newIdea.insert(db)
                    newIdea.id = db.lastInsertedRowID
                    return newIdea
                }
                entityId = idea.id ?? -1
                entityTitle = idea.title ?? "New Idea"

            case .task:
                let task = try await database.asyncWrite { db -> CosmoTask in
                    var newTask = CosmoTask.new(title: parsed.title, status: "todo")
                    try newTask.insert(db)
                    newTask.id = db.lastInsertedRowID
                    return newTask
                }
                entityId = task.id ?? -1
                entityTitle = task.title ?? "New Task"

            case .content:
                let content = try await database.asyncWrite { db -> CosmoContent in
                    var newContent = CosmoContent.new(
                        title: parsed.title,
                        body: parsed.content ?? details
                    )
                    try newContent.insert(db)
                    newContent.id = db.lastInsertedRowID
                    return newContent
                }
                entityId = content.id ?? -1
                entityTitle = content.title ?? "New Content"

            default:
                break
            }

            return CosmoResponse(
                message: "✅ Created \(type.rawValue): **\(entityTitle)**",
                entities: [EntityReference(type: type, id: entityId, title: entityTitle)],
                suggestedActions: [
                    .openEntity(type: type, id: entityId),
                    .addToCalendar
                ]
            )

        } catch {
            return CosmoResponse(
                message: "❌ Couldn't create \(type.rawValue): \(error.localizedDescription)",
                entities: [],
                suggestedActions: []
            )
        }
    }

    // MARK: - Search Handler (Local Embeddings)
    private func handleSearch(query: String) async -> CosmoResponse {
        print("🔍 Cosmo: Semantic search (local embeddings)...")

        do {
            let results = try await semanticSearch.search(
                query: query,
                limit: 10,
                minSimilarity: 0.5
            )

            if results.isEmpty {
                return CosmoResponse(
                    message: "I couldn't find anything matching \"\(query)\" in your knowledge base.",
                    entities: [],
                    suggestedActions: [.createIdea(withContent: query)]
                )
            }

            var response = "🔍 **Found \(results.count) matches:**\n\n"
            var entities: [EntityReference] = []

            for result in results.prefix(5) {
                response += "• **\(result.title)** (\(result.entityType.rawValue))\n"
                response += "  Relevance: \(Int(result.similarity * 100))%\n"
                if let preview = result.preview {
                    response += "  \(preview.prefix(80))...\n\n"
                }

                entities.append(EntityReference(
                    type: result.entityType,
                    id: result.entityId,
                    title: result.title
                ))
            }

            return CosmoResponse(
                message: response,
                entities: entities,
                suggestedActions: [
                    .placeOnCanvas(entityType: .idea, count: results.count)
                ]
            )

        } catch {
            return CosmoResponse(
                message: "Search failed: \(error.localizedDescription)",
                entities: [],
                suggestedActions: []
            )
        }
    }

    // MARK: - Schedule Handler
    private func handleSchedule(details: String) async -> CosmoResponse {
        print("📅 Cosmo: Scheduling (local AI)...")

        // Use InstantParser + LocalLLM for parsing
        let parser = InstantParser()
        let parsed = parser.parse(details)

        let formatter = ISO8601DateFormatter()
        let now = Date()
        let oneHourLater = now.addingTimeInterval(3600)

        let eventTitle: String
        let startTimeStr: String
        let endTimeStr: String
        let eventIsAllDay: Bool

        if let p = parsed {
            eventTitle = p.title
            startTimeStr = formatter.string(from: p.startTime)
            endTimeStr = formatter.string(from: p.endTime)
            eventIsAllDay = p.isAllDay
        } else {
            eventTitle = "New Event"
            startTimeStr = formatter.string(from: now)
            endTimeStr = formatter.string(from: oneHourLater)
            eventIsAllDay = false
        }

        do {
            let startDate = ISO8601DateFormatter().date(from: startTimeStr) ?? Date()
            let endDate = ISO8601DateFormatter().date(from: endTimeStr) ?? startDate.addingTimeInterval(3600)
            let durationMins = Int((endDate.timeIntervalSince(startDate)) / 60)

            var block = ScheduleBlock.task(
                title: eventTitle,
                startTime: startDate,
                durationMinutes: durationMins
            )
            block.endTime = endDate
            block.isAllDay = eventIsAllDay
            block.reminderMinutes = 15

            // Capture block by value for async context
            let blockToSave = block
            try await database.asyncWrite { db in
                let mutableBlock = blockToSave
                try mutableBlock.insert(db)
            }

            return CosmoResponse(
                message: "📅 Scheduled: **\(blockToSave.title)**\n\nTime: \(formatBlockTime(blockToSave))",
                entities: [EntityReference(type: .calendar, id: blockToSave.databaseId ?? -1, title: blockToSave.title)],
                suggestedActions: [.openCalendar]
            )

        } catch {
            return CosmoResponse(
                message: "❌ Couldn't schedule: \(error.localizedDescription)",
                entities: [],
                suggestedActions: []
            )
        }
    }

    private func formatBlockTime(_ block: ScheduleBlock) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if let date = block.startTime {
            return formatter.string(from: date)
        }
        return "Unscheduled"
    }

    // MARK: - Navigation Handler
    private func handleNavigation(destination: String) async -> CosmoResponse {
        let lowered = destination.lowercased()

        var section: NavigationSection = .home

        if lowered.contains("idea") { section = .ideas }
        else if lowered.contains("task") || lowered.contains("today") { section = .today }
        else if lowered.contains("content") || lowered.contains("note") { section = .content }
        else if lowered.contains("calendar") { section = .calendar }
        else if lowered.contains("canvas") { section = .canvas }
        else if lowered.contains("research") { section = .research }
        else if lowered.contains("project") { section = .projects }
        else if lowered.contains("connection") { section = .connections }

        NotificationCenter.default.post(
            name: .navigateToSection,
            object: nil,
            userInfo: ["section": section]
        )

        return CosmoResponse(
            message: "📍 Navigating to \(section.rawValue)",
            entities: [],
            suggestedActions: []
        )
    }

    // MARK: - Question Handler (Local LLM)
    private func handleQuestion(query: String, context: CosmoContext?) async -> CosmoResponse {
        print("💭 Cosmo: Answering question (local LLM)...")

        // Get relevant context from semantic search
        let relevantEntities = try? await semanticSearch.search(
            query: query,
            limit: 5,
            minSimilarity: 0.6
        )

        // Build context for LLM
        var contextText = ""
        if let entities = relevantEntities, !entities.isEmpty {
            contextText = "Relevant knowledge:\n"
            for entity in entities {
                contextText += "- \(entity.title): \(entity.preview ?? "")\n"
            }
        }

        // Use local LLM
        let response = await localLLM.generate(
            prompt: """
            You are Cosmo, an intelligent assistant for a knowledge OS.

            Context from user's knowledge base:
            \(contextText)

            User question: \(query)

            Provide a helpful, concise response based on the context and your knowledge.
            """,
            maxTokens: 500
        )

        return CosmoResponse(
            message: response,
            entities: relevantEntities?.map { EntityReference(type: $0.entityType, id: $0.entityId, title: $0.title) } ?? [],
            suggestedActions: []
        )
    }

    // MARK: - Canvas Handler (Deep LLM Integration)
    private func handleCanvasAction(action: String, input: String) async -> CosmoResponse {
        print("🎨 Cosmo: Canvas action with LLM intelligence...")

        // Preprocess for pronoun resolution
        let (processedInput, resolvedEntities) = localLLM.preprocessPronouns(in: input)

        if !resolvedEntities.isEmpty {
            print("🔀 Resolved \(resolvedEntities.count) entity references")
        }

        // Delegate to VoiceCommandRouter
        let router = VoiceCommandRouter()
        do {
            let result = try await router.route(processedInput)

            // Track any entities mentioned for future pronoun resolution
            if let llmResult = result.llmResult {
                if let entityType = llmResult.entityType,
                   let uuid = llmResult.targetBlockQuery ?? llmResult.entityUuid {
                    entityTracker.trackMention(
                        entityUuid: uuid,
                        entityType: entityType
                    )
                }

                return CosmoResponse(
                    message: "✅ \(describeCanvasAction(llmResult))",
                    entities: [],
                    suggestedActions: []
                )
            }

            return CosmoResponse(
                message: "✅ Action completed",
                entities: [],
                suggestedActions: []
            )
        } catch {
            return CosmoResponse(
                message: "❌ Canvas action failed: \(error.localizedDescription)",
                entities: [],
                suggestedActions: []
            )
        }
    }

    private func describeCanvasAction(_ result: LLMCommandResult) -> String {
        switch result.action {
        case "create_entity", "create_idea":
            return "Created '\(result.title ?? "new idea")'"
        case "move_block":
            return "Moved '\(result.targetBlockQuery ?? "block")' to \(result.position ?? "new position")"
        case "arrange_blocks":
            return "Arranged blocks in \(result.layout ?? "pattern")"
        case "delete", "delete_entity":
            return "Deleted '\(result.targetBlockQuery ?? result.title ?? "item")'"
        default:
            return "Canvas action completed"
        }
    }

    // MARK: - Cross-Entity Intelligence

    /// Analyze relationships between entities and suggest actions
    func analyzeKnowledgeGraph() async -> [KnowledgeInsight] {
        var insights: [KnowledgeInsight] = []

        do {
            // Find disconnected clusters
            let allConnections = try await database.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT source_entity_uuid, target_entity_uuid
                    FROM connections WHERE is_deleted = 0
                    """)
            }

            // Find ideas that could be connected
            let ideas = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
                    .map { IdeaWrapper(atom: $0) }
            }

            // Simple semantic similarity check (in production, use embeddings)
            for i in 0..<ideas.count {
                for j in (i+1)..<ideas.count {
                    let idea1 = ideas[i]
                    let idea2 = ideas[j]

                    // Check if already connected
                    let connected = allConnections.contains { row in
                        let source = row["source_entity_uuid"] as? String
                        let target = row["target_entity_uuid"] as? String
                        return (source == idea1.uuid && target == idea2.uuid) ||
                               (source == idea2.uuid && target == idea1.uuid)
                    }

                    if !connected {
                        // Check for word overlap (simple heuristic)
                        let words1 = Set((idea1.title ?? "").lowercased().split(separator: " "))
                        let words2 = Set((idea2.title ?? "").lowercased().split(separator: " "))
                        let overlap = words1.intersection(words2).count

                        if overlap > 0 {
                            insights.append(KnowledgeInsight(
                                type: .potentialConnection,
                                description: "'\(idea1.title ?? "")' and '\(idea2.title ?? "")' might be related",
                                action: .connect(uuid1: idea1.uuid, uuid2: idea2.uuid),
                                confidence: Double(overlap) * 0.2
                            ))
                        }
                    }
                }
            }

        } catch {
            print("⚠️ Knowledge graph analysis failed: \(error)")
        }

        return insights.sorted { $0.confidence > $1.confidence }.prefix(5).map { $0 }
    }

    // MARK: - Research-to-Action Pipeline

    /// Complete research workflow: research → ideas → connections
    func executeResearchPipeline(query: String) async -> CosmoResponse {
        print("🔬 Starting research pipeline for: \(query)")

        // Step 1: Start research
        let researchResponse = await handleResearch(query: query, originalInput: query)

        guard let researchEntity = researchResponse.entities.first else {
            return researchResponse
        }

        // Step 2: Convert to ideas (via tool calling)
        do {
            let researchUUID = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.research.rawValue)
                    .filter(Column("id") == researchEntity.id)
                    .fetchOne(db)
                    .map { ResearchWrapper(atom: $0) }?.uuid
            }

            if let uuid = researchUUID {
                _ = await process("convert research \(uuid) to ideas")
            }
        } catch {
            print("⚠️ Research pipeline step 2 failed: \(error)")
        }

        return CosmoResponse(
            message: researchResponse.message + "\n\n🔄 Research pipeline complete. Ideas created and ready for connection.",
            entities: researchResponse.entities,
            suggestedActions: [
                .placeOnCanvas(entityType: .research, count: 1),
                .startResearch(query: "related: \(query)")
            ]
        )
    }

    // MARK: - Message Persistence
    private func loadRecentMessages() {
        Task {
            let entries = try? await database.asyncRead { db in
                try JournalEntry
                    .filter(Column("is_deleted") == false)
                    .order(Column("created_at").desc)
                    .limit(50)
                    .fetchAll(db)
            }

            // Convert to messages
            await MainActor.run {
                messages = (entries ?? []).reversed().flatMap { entry -> [CosmoMessage] in
                    var msgs: [CosmoMessage] = []

                    msgs.append(CosmoMessage(
                        role: .user,
                        content: entry.content,
                        timestamp: ISO8601DateFormatter().date(from: entry.createdAt) ?? Date()
                    ))

                    if let response = entry.aiResponse {
                        msgs.append(CosmoMessage(
                            role: .assistant,
                            content: response,
                            timestamp: ISO8601DateFormatter().date(from: entry.createdAt) ?? Date()
                        ))
                    }

                    return msgs
                }
            }
        }
    }

    private func saveMessage(_ message: CosmoMessage) async {
        guard message.role == .user else { return }

        let entry = JournalEntry(
            id: nil,
            uuid: UUID().uuidString as String?,
            userId: nil,
            content: message.content,
            source: "cosmo-ai",
            status: "completed",
            aiResponse: nil,
            linkedTasks: nil,
            linkedIdeas: nil,
            linkedContent: nil,
            errorMessage: nil,
            createdAt: ISO8601DateFormatter().string(from: message.timestamp),
            updatedAt: ISO8601DateFormatter().string(from: message.timestamp),
            syncedAt: nil,
            isDeleted: false,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0
        )

        try? await database.asyncWrite { db in
            try entry.insert(db)
        }
    }

    // MARK: - Clear Conversation
    func clearConversation() {
        messages.removeAll()
    }
}

// MARK: - Cosmo Action (current action in progress)
enum CosmoAction: Equatable {
    case thinking
    case searching(query: String)
    case researching(query: String)
    case creating(type: EntityType)
    case navigating(to: NavigationSection)
    case idle
}

// MARK: - Supporting Types
enum CosmoIntent {
    case research(query: String)
    case createEntity(type: EntityType, details: String)
    case search(query: String)
    case schedule(details: String)
    case navigation(destination: String)
    case question(query: String)
    case canvas(action: String)
    case unknown
}

struct CosmoMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date
    var entities: [EntityReference] = []
    var actions: [CosmoSuggestedAction] = []

    enum MessageRole {
        case user, assistant, system
    }
}

struct CosmoResponse {
    let message: String
    let entities: [EntityReference]
    let suggestedActions: [CosmoSuggestedAction]
}

struct CosmoContext {
    var currentSection: NavigationSection?
    var selectedEntities: [EntityReference] = []
    var canvasState: CanvasState?
}

struct CanvasState {
    var blockCount: Int = 0
    var selectedBlockIds: [UUID] = []
}

struct EntityReference: Identifiable {
    let id: Int64
    let type: EntityType
    let title: String

    init(type: EntityType, id: Int64, title: String) {
        self.type = type
        self.id = id
        self.title = title
    }
}

enum CosmoSuggestedAction {
    case openEntity(type: EntityType, id: Int64)
    case placeOnCanvas(entityType: EntityType, count: Int)
    case createIdea(withContent: String)
    case addToCalendar
    case openCalendar
    case startResearch(query: String)
}

// MARK: - Notification Names
extension Notification.Name {
    static let navigateToSection = Notification.Name("navigateToSection")
    static let canvasBlocksChanged = Notification.Name("com.cosmo.canvasBlocksChanged")
}

// MARK: - Proactive Intelligence Types

struct ProactiveSuggestion: Identifiable {
    let id = UUID()
    let type: SuggestionType
    let title: String
    let description: String
    let action: ProactiveAction
    let priority: SuggestionPriority
    let timestamp = Date()

    enum SuggestionType {
        case connect
        case organize
        case taskReminder
        case research
        case schedule
    }
}

enum SuggestionPriority: Int {
    case low = 1
    case medium = 2
    case high = 3
    case urgent = 4
}

enum ProactiveAction {
    case suggestConnections(ideaIds: [Int64])
    case focusOnTask(taskId: Int64)
    case organizeCanvas
    case startResearchOnTopic(topic: String)
}

struct UserActivityPattern {
    var mostActiveHours: [Int] = []
    var preferredEntityTypes: [String: Int] = [:]
    var averageSessionDuration: TimeInterval = 0
    var commonWorkflows: [String] = []
}

// MARK: - Knowledge Graph Insights

struct KnowledgeInsight: Identifiable {
    let id = UUID()
    let type: InsightType
    let description: String
    let action: InsightAction
    let confidence: Double

    enum InsightType {
        case potentialConnection
        case orphanedEntity
        case duplicateContent
        case staleContent
        case topicCluster
    }
}

enum InsightAction {
    case connect(uuid1: String, uuid2: String)
    case archive(uuid: String)
    case merge(uuid1: String, uuid2: String)
    case refresh(uuid: String)
    case createProject(fromUUIDs: [String])
}

// MARK: - JournalEntry Model (Legacy - to be migrated to Atom)
struct JournalEntry: Codable, FetchableRecord, PersistableRecord, Syncable {
    static let databaseTableName = "journal_entries"

    var id: Int64?
    var uuid: String?
    var userId: String?
    var content: String
    var source: String
    var status: String
    var aiResponse: String?
    var linkedTasks: String?
    var linkedIdeas: String?
    var linkedContent: String?
    var errorMessage: String?
    var createdAt: String
    var updatedAt: String
    var syncedAt: String?
    var isDeleted: Bool
    var localVersion: Int
    var serverVersion: Int
    var syncVersion: Int

    // Column mappings to match database schema
    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id, uuid, content, source, status
        case userId = "user_id"
        case aiResponse = "ai_response"
        case linkedTasks = "linked_tasks"
        case linkedIdeas = "linked_ideas"
        case linkedContent = "linked_content"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
        case isDeleted = "is_deleted"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
