// CosmoOS/Agent/Memory/ConversationMemoryService.swift
// Persistent conversation memory with semantic search, topic threading, and summarization

import Foundation
import NaturalLanguage

@MainActor
class ConversationMemoryService {
    static let shared = ConversationMemoryService()

    private let atomRepo = AtomRepository.shared
    private let maxWindowSize = 20
    private let summarizationThreshold = 15
    private let archiveAgeDays = 30

    private init() {}

    // MARK: - Save Conversation

    func saveConversation(_ conversation: AgentConversation) async {
        var conv = conversation
        guard !conv.messages.isEmpty else {
            await deleteConversation(id: conv.id)
            return
        }

        // Auto-extract topics if not already set
        if conv.topics.isEmpty {
            conv.topics = extractTopics(from: conv)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let messagesData = try? encoder.encode(conv.messages),
              let messagesJSON = String(data: messagesData, encoding: .utf8) else { return }

        var metaDict: [String: Any] = [
            "subtype": "agent_conversation",
            "conversationId": conv.id,
            "source": conv.source.rawValue,
            "messageCount": conv.messages.count,
            "linkedAtomUUIDs": conv.linkedAtomUUIDs,
            "topics": conv.topics
        ]
        if let modelLock = conv.modelLock {
            metaDict["modelLock"] = modelLock.rawValue
        }
        let metadataJSON = (try? JSONSerialization.data(withJSONObject: metaDict)).flatMap { String(data: $0, encoding: .utf8) }

        var structuredDict: [String: Any] = [
            "createdAt": ISO8601.string(from: conv.createdAt)
        ]
        if let summary = conv.summary {
            structuredDict["summary"] = summary
        }
        structuredDict["topics"] = conv.topics
        let structuredJSON = (try? JSONSerialization.data(withJSONObject: structuredDict)).flatMap { String(data: $0, encoding: .utf8) }

        let existingAtoms = (try? await atomRepo.fetchAll(type: .systemEvent)) ?? []
        let existingConv = existingAtoms.first { atom in
            guard let meta = atom.metadata,
                  let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
                  let subtype = dict["subtype"] as? String,
                  let convId = dict["conversationId"] as? String else { return false }
            return subtype == "agent_conversation" && convId == conv.id
        }

        if var existing = existingConv {
            existing.body = messagesJSON
            existing.metadata = metadataJSON
            existing.structured = structuredJSON
            try? await atomRepo.update(existing)
        } else {
            let atom = Atom.new(
                type: .systemEvent,
                title: "Agent Conversation: \(conv.source.rawValue)",
                body: messagesJSON,
                structured: structuredJSON,
                metadata: metadataJSON
            )
            _ = try? await atomRepo.create(atom)
        }
    }

    // MARK: - Load Conversation

    func loadConversation(id: String) async -> AgentConversation? {
        let atoms = (try? await atomRepo.fetchAll(type: .systemEvent)) ?? []

        guard let atom = atoms.first(where: { atom in
            guard let meta = atom.metadata,
                  let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
                  let subtype = dict["subtype"] as? String,
                  let convId = dict["conversationId"] as? String else { return false }
            return subtype == "agent_conversation" && convId == id
        }) else { return nil }

        return decodeConversation(from: atom)
    }

    // MARK: - Get Recent Conversations

    func getRecentConversations(limit: Int = 10) async -> [AgentConversation] {
        let atoms = (try? await atomRepo.fetchAll(type: .systemEvent)) ?? []
        let convAtoms = atoms.filter { atom in
            guard let meta = atom.metadata,
                  let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
                  let subtype = dict["subtype"] as? String else { return false }
            return subtype == "agent_conversation"
        }

        return convAtoms
            .compactMap { decodeConversation(from: $0) }
            .filter { !$0.messages.isEmpty }
            .sorted { lhs, rhs in
                let lhsActivity = lhs.messages.last?.timestamp ?? lhs.createdAt
                let rhsActivity = rhs.messages.last?.timestamp ?? rhs.createdAt
                return lhsActivity > rhsActivity
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Semantic Search

    /// Vector-based semantic search over conversation summaries and content
    func semanticSearch(query: String, limit: Int = 5) async -> [AgentConversation] {
        // Try vector search first via DaemonXPCClient embeddings
        do {
            let queryVector = try await DaemonXPCClient.shared.embed(text: query)
            let truncatedQuery = Array(queryVector.prefix(256))

            let allConversations = await getRecentConversations(limit: 50)

            // Score each conversation by embedding similarity to its summary/content
            var scored: [(conv: AgentConversation, score: Float)] = []

            for conv in allConversations {
                let searchText = conv.summary ?? conv.messages.suffix(5).map(\.content).joined(separator: " ")
                guard !searchText.isEmpty else { continue }

                do {
                    let convVector = try await DaemonXPCClient.shared.embed(text: String(searchText.prefix(500)))
                    let truncatedConv = Array(convVector.prefix(256))
                    let similarity = cosineSimilarity(truncatedQuery, truncatedConv)
                    scored.append((conv: conv, score: similarity))
                } catch {
                    continue
                }
            }

            let results = scored
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map(\.conv)

            if !results.isEmpty { return results }
        } catch {
            // Fall through to keyword search
        }

        // Fallback: keyword search
        return await searchPastConversations(query: query)
    }

    // MARK: - Topic-Based Search

    /// Find conversations about a specific topic
    func findConversations(aboutTopic topic: String) async -> [AgentConversation] {
        let all = await getRecentConversations(limit: 50)
        let topicLower = topic.lowercased()

        return all.filter { conv in
            // Check extracted topics
            if conv.topics.contains(where: { $0.lowercased().contains(topicLower) }) {
                return true
            }
            // Check summary
            if let summary = conv.summary, summary.localizedCaseInsensitiveContains(topic) {
                return true
            }
            return false
        }
    }

    /// "Continue our conversation about X" — finds the most recent relevant conversation
    func findConversationAbout(_ topic: String) async -> AgentConversation? {
        let topicResults = await findConversations(aboutTopic: topic)
        if let recent = topicResults.first { return recent }

        // Fall back to semantic search
        let semanticResults = await semanticSearch(query: topic, limit: 1)
        return semanticResults.first
    }

    // MARK: - Keyword Search (Legacy)

    func searchPastConversations(query: String) async -> [AgentConversation] {
        let atoms = (try? await atomRepo.fetchAll(type: .systemEvent)) ?? []
        let matching = atoms.filter { atom in
            guard let meta = atom.metadata,
                  let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
                  let subtype = dict["subtype"] as? String,
                  subtype == "agent_conversation" else { return false }
            return (atom.body ?? "").localizedCaseInsensitiveContains(query) ||
                   (atom.title ?? "").localizedCaseInsensitiveContains(query)
        }

        return matching.prefix(5).compactMap { decodeConversation(from: $0) }
    }

    // MARK: - Build Context Window

    /// Assembles recent conversation context for the LLM system prompt.
    /// Collapses older tool call/result pairs into summaries to preserve more
    /// conversational context within the 20-message window.
    func buildContextWindow(for source: MessageSource, maxMessages: Int? = nil) async -> [AgentMessage] {
        let recent = await getRecentConversations(limit: 3)
        let sourceConversations = recent.filter { $0.source == source }

        let limit = maxMessages ?? maxWindowSize
        var contextMessages: [AgentMessage] = []

        for conv in sourceConversations {
            // For summarized conversations, inject the summary as a system message
            if let summary = conv.summary, conv.messages.count > summarizationThreshold {
                let summaryMsg = AgentMessage(
                    role: .system,
                    content: "[Previous conversation summary: \(summary)]"
                )
                contextMessages.append(summaryMsg)
                // Then add only the last few messages for recency
                // Sanitize to avoid orphaned tool_result messages after truncation
                let recentMessages = Self.sanitizeToolPairs(Array(conv.messages.suffix(5)))
                for msg in recentMessages {
                    contextMessages.append(msg)
                    if contextMessages.count >= limit { break }
                }
            } else {
                // Collapse older tool pairs to preserve conversational context
                let collapsed = Self.collapseToolPairs(conv.messages, keepLastPairs: 3)
                for msg in collapsed.suffix(limit - contextMessages.count) {
                    contextMessages.append(msg)
                    if contextMessages.count >= limit { break }
                }
            }
            if contextMessages.count >= limit { break }
        }

        return contextMessages
    }

    /// Collapse consecutive assistant(tool_use) + tool_result message pairs into
    /// compact summaries, preserving the last `keepLastPairs` tool pairs un-collapsed
    /// so the model can see recent tool results in full.
    private static func collapseToolPairs(_ messages: [AgentMessage], keepLastPairs: Int) -> [AgentMessage] {
        // First, identify indices of tool pair groups (assistant with toolCalls + following tool results)
        struct ToolPairGroup {
            let assistantIndex: Int
            var toolResultIndices: [Int] = []
            var toolNames: [String] = []
        }

        var groups: [ToolPairGroup] = []
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            if msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty {
                var group = ToolPairGroup(assistantIndex: i)
                group.toolNames = calls.map(\.name)
                // Collect following tool result messages
                var j = i + 1
                while j < messages.count && messages[j].role == .tool {
                    group.toolResultIndices.append(j)
                    j += 1
                }
                groups.append(group)
                i = j
            } else {
                i += 1
            }
        }

        // Keep last N tool pair groups un-collapsed
        let groupsToCollapse = groups.count > keepLastPairs
            ? Array(groups.prefix(groups.count - keepLastPairs))
            : []

        // Build set of indices to collapse
        var collapseIndices = Set<Int>()
        var collapseSummaries: [Int: String] = [:] // assistantIndex -> summary text
        for group in groupsToCollapse {
            collapseIndices.insert(group.assistantIndex)
            for idx in group.toolResultIndices {
                collapseIndices.insert(idx)
            }
            let toolStr = group.toolNames.joined(separator: ", ")
            collapseSummaries[group.assistantIndex] = "[Used tools: \(toolStr) -- results summarized]"
        }

        // Rebuild message array
        var result: [AgentMessage] = []
        for (idx, msg) in messages.enumerated() {
            if collapseIndices.contains(idx) {
                // If this is the assistant message that starts a collapsed group, insert summary
                if let summary = collapseSummaries[idx] {
                    result.append(AgentMessage(role: .assistant, content: summary))
                }
                // Skip tool result messages in collapsed groups (they're summarized)
            } else {
                result.append(msg)
            }
        }

        return result
    }

    // MARK: - Conversation Lifecycle

    /// Archive old conversations (keep summaries, drop message bodies)
    func archiveOldConversations() async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -archiveAgeDays, to: Date()) ?? Date()
        let all = await getRecentConversations(limit: 100)

        for conv in all {
            guard conv.createdAt < cutoffDate else { continue }

            // Generate summary if not already present
            var archived = conv
            if archived.summary == nil {
                archived.summary = await generateSummary(for: archived)
            }

            // Keep only the summary and topics, trim messages to last 3
            // Sanitize to avoid orphaned tool_result messages after truncation
            if archived.messages.count > 3 {
                let lastMessages = Array(archived.messages.suffix(3))
                archived.messages = Self.sanitizeToolPairs(lastMessages)
            }

            await saveConversation(archived)
        }
    }

    // MARK: - Delete Conversation

    func deleteConversation(id: String) async {
        let atoms = (try? await atomRepo.fetchAll(type: .systemEvent)) ?? []
        if let atom = atoms.first(where: { atom in
            guard let meta = atom.metadata,
                  let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
                  let subtype = dict["subtype"] as? String,
                  let convId = dict["conversationId"] as? String else { return false }
            return subtype == "agent_conversation" && convId == id
        }) {
            try? await atomRepo.delete(atom)
        }
    }

    // MARK: - Topic Extraction

    /// Extract topics from conversation using NaturalLanguage framework
    private func extractTopics(from conversation: AgentConversation) -> [String] {
        let userMessages = conversation.messages
            .filter { $0.role == .user }
            .map(\.content)
            .joined(separator: " ")

        guard !userMessages.isEmpty else { return [] }

        // Use NLTagger for noun phrase extraction
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = String(userMessages.prefix(2000))

        var nouns: [String: Int] = [:]

        tagger.enumerateTags(in: userMessages.startIndex..<userMessages.prefix(2000).endIndex,
                             unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            if tag == .noun || tag == .verb {
                let word = String(userMessages[range]).lowercased()
                if word.count > 3 && !Self.stopWords.contains(word) {
                    nouns[word, default: 0] += 1
                }
            }
            return true
        }

        // Return top 5 most frequent meaningful words as topics
        return nouns
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)
    }

    private static let stopWords: Set<String> = [
        "this", "that", "have", "been", "would", "could", "should", "will",
        "about", "from", "with", "they", "them", "their", "what", "when",
        "where", "which", "there", "these", "those", "also", "just", "more",
        "some", "very", "than", "then", "into", "only", "over", "does", "done",
        "want", "need", "make", "like", "know", "help", "tell", "show"
    ]

    // MARK: - Conversation Summarization

    /// Generate a concise summary of a conversation using the LLM
    private func generateSummary(for conversation: AgentConversation) async -> String? {
        let messageText = conversation.messages.prefix(30).map { msg in
            "\(msg.role == .user ? "User" : "Agent"): \(msg.content.prefix(200))"
        }.joined(separator: "\n")

        guard !messageText.isEmpty else { return nil }

        let prompt = "Summarize this conversation in 2-3 sentences. Focus on the main topics discussed and any decisions made:\n\n\(messageText)"

        // Use the agent's LLM provider for summarization
        let agentService = CosmoAgentService.shared
        do {
            let messages = [
                AgentMessage(role: .system, content: "You are a concise summarizer. Respond with only the summary, no preamble."),
                AgentMessage.user(prompt)
            ]
            // Access LLM through agent service's internal provider
            let response = try await agentService.summarize(messages: messages)
            if let text = response, !text.isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // Fall through to extractive summary
        }

        // Fallback: simple extractive summary from first and last user messages
        let userMsgs = conversation.messages.filter { $0.role == .user }
        guard let first = userMsgs.first else { return nil }
        let last = userMsgs.last

        var summary = "Started with: \"\(first.content.prefix(100))\""
        if let lastMsg = last, lastMsg.content != first.content {
            summary += ". Ended with: \"\(lastMsg.content.prefix(100))\""
        }
        return summary
    }

    // MARK: - Tool Pair Sanitization

    /// Remove orphaned tool_result messages whose corresponding tool_use assistant
    /// message was truncated by a history window slice. The Anthropic API requires every
    /// tool_result to have a matching tool_use in the preceding assistant message.
    private static func sanitizeToolPairs(_ messages: [AgentMessage]) -> [AgentMessage] {
        var availableToolCallIds = Set<String>()
        for msg in messages {
            if msg.role == .assistant, let calls = msg.toolCalls {
                for call in calls {
                    availableToolCallIds.insert(call.id)
                }
            }
        }
        return messages.filter { msg in
            if msg.role == .tool, let callId = msg.toolCallId {
                return availableToolCallIds.contains(callId)
            }
            return true
        }
    }

    // MARK: - Private Helpers

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }

    private func decodeConversation(from atom: Atom) -> AgentConversation? {
        guard let body = atom.body,
              let data = body.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let messages = try? decoder.decode([AgentMessage].self, from: data),
              let meta = atom.metadata,
              let metaDict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
              let convId = metaDict["conversationId"] as? String,
              let sourceStr = metaDict["source"] as? String,
              let source = MessageSource(rawValue: sourceStr) else { return nil }

        let linkedUUIDs = metaDict["linkedAtomUUIDs"] as? [String] ?? []
        let topics = metaDict["topics"] as? [String] ?? []
        let modelLock = (metaDict["modelLock"] as? String).flatMap(AgentModelTier.init(rawValue:))

        // Parse structured data
        var summary: String? = nil
        var createdAt = Date()
        if let structuredStr = atom.structured,
           let structuredData = structuredStr.data(using: .utf8),
           let structuredDict = try? JSONSerialization.jsonObject(with: structuredData) as? [String: Any] {
            summary = structuredDict["summary"] as? String
            if let dateStr = structuredDict["createdAt"] as? String {
                createdAt = ISO8601.date(from: dateStr) ?? Date()
            }
        }

        var conv = AgentConversation(id: convId, source: source, createdAt: createdAt)
        for msg in messages {
            conv.messages.append(msg)
        }
        conv.summary = summary
        conv.linkedAtomUUIDs = linkedUUIDs
        conv.topics = topics
        conv.modelLock = modelLock

        return conv
    }
}
