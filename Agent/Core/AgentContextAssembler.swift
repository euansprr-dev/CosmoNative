// CosmoOS/Agent/Core/AgentContextAssembler.swift
// Assembles system prompts with live user data for the Cosmo Agent

import Foundation

@MainActor
class AgentContextAssembler {
    static let shared = AgentContextAssembler()

    private let atomRepo = AtomRepository.shared

    private init() {}

    // MARK: - System Prompt Assembly

    /// Assemble the full system prompt from identity, user context, preferences, and conversation history
    func assembleSystemPrompt(
        conversation: AgentConversation?,
        preferences: [AgentPreference],
        tools: [LLMToolDefinition]
    ) async -> String {
        var sections: [String] = []

        // Layer 1: Identity and personality
        sections.append(identityPrompt())

        // Layer 2: Live user context from GRDB
        let userContext = await buildUserContext()
        if !userContext.isEmpty {
            sections.append(userContext)
        }

        // Layer 3: Learned preferences
        if !preferences.isEmpty {
            sections.append(preferencesPrompt(preferences))
        }

        // Layer 4: Conversation history summary
        if let conv = conversation, !conv.messages.isEmpty {
            sections.append(conversationContext(conv))
        }

        // Layer 5: Tool usage guidelines
        if !tools.isEmpty {
            sections.append(toolGuidelines(tools))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Identity

    private func identityPrompt() -> String {
        """
        You are Cosmo, an AI partner for creative strategists. You have full access to the user's \
        CosmoOS knowledge graph -- ideas, swipe files, content pipeline, calendar, quests, and more.

        Your personality: Warm, direct, and creative. You're a trusted partner, not a generic \
        assistant. You know the user's work deeply and can cross-reference their ideas, swipes, \
        and content in ways they couldn't manually.

        Key behaviors:
        - Be proactive: suggest connections between ideas and swipes when relevant
        - Be concise: keep responses digestible (under 200 words unless asked for detail)
        - Use tools to ground responses in real data -- never make up information about the user's work
        - For destructive actions (deleting blocks, etc.), always explain what you're about to do
        - Reference specific items by name when discussing the user's work
        - When the user asks to capture something, use create_idea or create_task immediately
        - When asked about schedule or plans, always query get_calendar_blocks first
        - When discussing content strategy, cross-reference swipe files for relevant examples
        """
    }

    // MARK: - User Context

    /// Build a concise snapshot of the user's current state (~500 tokens)
    private func buildUserContext() async -> String {
        var contextParts: [String] = []
        contextParts.append("[USER CONTEXT - Live Data]")

        // 1. Today's schedule blocks
        let todayBlocks = await fetchTodayBlocks()
        if !todayBlocks.isEmpty {
            let blockSummaries = todayBlocks.prefix(5).map { block -> String in
                let title = block.title ?? "Untitled"
                let meta = block.metadataValue(as: ScheduleBlockMetadata.self)
                let status = (meta?.isCompleted ?? false) ? "done" : "pending"
                let time = formatTimeRange(start: meta?.startTime, end: meta?.endTime)
                return "  - \(time) \(title) [\(status)]"
            }
            contextParts.append("Today's schedule (\(todayBlocks.count) blocks):")
            contextParts.append(contentsOf: blockSummaries)
        } else {
            contextParts.append("Today's schedule: No blocks scheduled")
        }

        // 2. Active tasks count
        let activeTasks = await fetchActiveTasks()
        let unscheduledCount = activeTasks.filter { atom in
            let meta = atom.metadataValue(as: TaskMetadata.self)
            return meta?.isUnscheduled == true || meta?.startTime == nil
        }.count
        contextParts.append("Active tasks: \(activeTasks.count) total, \(unscheduledCount) unscheduled")

        // 3. Recent ideas (last 5)
        let recentIdeas = await fetchRecentIdeas()
        if !recentIdeas.isEmpty {
            let ideaSummaries = recentIdeas.prefix(5).map { atom in
                "  - \(atom.title ?? "Untitled")"
            }
            contextParts.append("Recent ideas:")
            contextParts.append(contentsOf: ideaSummaries)
        }

        // 4. Pipeline status (count per phase)
        let pipelineCounts = await fetchPipelinePhaseCounts()
        if !pipelineCounts.isEmpty {
            let pipelineStr = pipelineCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            contextParts.append("Content pipeline: \(pipelineStr)")
        }

        // 5. Quest status summary
        let questSummary = await fetchQuestSummary()
        if !questSummary.isEmpty {
            contextParts.append("Quests: \(questSummary)")
        }

        return contextParts.joined(separator: "\n")
    }

    // MARK: - Data Fetching Helpers

    private func fetchTodayBlocks() async -> [Atom] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        do {
            let blocks = try await atomRepo.fetchAll(type: .scheduleBlock)
            return blocks.filter { atom in
                let meta = atom.metadataValue(as: ScheduleBlockMetadata.self)
                if let startStr = meta?.startTime,
                   let startDate = ISO8601DateFormatter().date(from: startStr) {
                    return calendar.isDate(startDate, inSameDayAs: todayStart)
                }
                if let date = ISO8601DateFormatter().date(from: atom.createdAt) {
                    return calendar.isDate(date, inSameDayAs: todayStart)
                }
                return false
            }.sorted { a, b in
                let aMeta = a.metadataValue(as: ScheduleBlockMetadata.self)
                let bMeta = b.metadataValue(as: ScheduleBlockMetadata.self)
                return (aMeta?.startTime ?? "") < (bMeta?.startTime ?? "")
            }
        } catch {
            return []
        }
    }

    private func fetchActiveTasks() async -> [Atom] {
        do {
            let tasks = try await atomRepo.fetchAll(type: .task)
            return tasks.filter { atom in
                let meta = atom.metadataValue(as: TaskMetadata.self)
                return meta?.isCompleted != true
            }
        } catch {
            return []
        }
    }

    private func fetchRecentIdeas() async -> [Atom] {
        do {
            let ideas = try await atomRepo.fetchAll(type: .idea)
            return Array(ideas.prefix(5))
        } catch {
            return []
        }
    }

    private func fetchPipelinePhaseCounts() async -> [String: Int] {
        do {
            let content = try await atomRepo.fetchAll(type: .content)
            var counts: [String: Int] = [:]
            for atom in content {
                let meta = atom.metadataValue(as: ContentAtomMetadata.self)
                let phase = meta?.phase.displayName ?? "Ideation"
                counts[phase, default: 0] += 1
            }
            return counts
        } catch {
            return [:]
        }
    }

    private func fetchQuestSummary() async -> String {
        let engine = QuestEngine()
        await engine.evaluate()

        let completed = engine.quests.filter { $0.isComplete }.count
        let total = engine.quests.count

        if total == 0 { return "" }

        let inProgress = engine.quests
            .filter { !$0.isComplete && $0.progress > 0 }
            .map { "\($0.title) (\(Int($0.progress * 100))%)" }

        var result = "\(completed)/\(total) complete"
        if !inProgress.isEmpty {
            result += ", in progress: " + inProgress.joined(separator: ", ")
        }
        return result
    }

    // MARK: - Formatting Helpers

    private func formatTimeRange(start: String?, end: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let startStr: String
        if let s = start, let d = ISO8601DateFormatter().date(from: s) {
            startStr = formatter.string(from: d)
        } else {
            startStr = "??"
        }

        let endStr: String
        if let e = end, let d = ISO8601DateFormatter().date(from: e) {
            endStr = formatter.string(from: d)
        } else {
            endStr = "??"
        }

        return "[\(startStr)-\(endStr)]"
    }

    // MARK: - Preferences Prompt

    private func preferencesPrompt(_ prefs: [AgentPreference]) -> String {
        var lines = ["[USER PREFERENCES]"]
        lines.append("The user has the following preferences (respect these in all interactions):")

        for pref in prefs.sorted(by: { $0.confidence > $1.confidence }) {
            let scopeLabel: String
            switch pref.scope {
            case .global: scopeLabel = ""
            case .client:
                scopeLabel = pref.scopeQualifier != nil ? " [client: \(pref.scopeQualifier!)]" : " [client-specific]"
            case .taskType:
                scopeLabel = pref.scopeQualifier != nil ? " [task: \(pref.scopeQualifier!)]" : " [task-specific]"
            }

            let confidence = pref.isExplicit ? "stated" : "inferred (\(Int(pref.confidence * 100))%)"
            lines.append("  - \(pref.key): \(pref.value)\(scopeLabel) (\(confidence))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Conversation Context

    private func conversationContext(_ conv: AgentConversation) -> String {
        var lines = ["[CONVERSATION CONTEXT]"]

        if let summary = conv.summary {
            lines.append("Previous conversation summary: \(summary)")
        }

        lines.append("Source: \(conv.source.rawValue)")
        lines.append("Messages in conversation: \(conv.messages.count)")

        if !conv.linkedAtomUUIDs.isEmpty {
            lines.append("Referenced atoms: \(conv.linkedAtomUUIDs.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Tool Guidelines

    private func toolGuidelines(_ tools: [LLMToolDefinition]) -> String {
        var lines = ["[TOOL GUIDELINES]"]
        lines.append("You have \(tools.count) tools available. Key rules:")
        lines.append("- Always use search tools before answering questions about the user's data")
        lines.append("- For destructive actions (delete_block), a confirmation will be requested automatically")
        lines.append("- When creating items, always return the UUID in your response for reference")
        lines.append("- If a tool returns an error, explain the issue to the user and suggest alternatives")
        lines.append("- Prefer specific tools over general queries (e.g. search_ideas over get_idea when exploring)")
        return lines.joined(separator: "\n")
    }
}
