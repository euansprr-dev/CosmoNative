// CosmoOS/Agent/Memory/ConversationMemoryService.swift
// Persistent conversation memory for Cosmo Agent

import Foundation

@MainActor
class ConversationMemoryService {
    static let shared = ConversationMemoryService()

    private let atomRepo = AtomRepository.shared
    private let maxWindowSize = 20

    private init() {}

    // MARK: - Save Conversation

    func saveConversation(_ conversation: AgentConversation) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let messagesData = try? encoder.encode(conversation.messages),
              let messagesJSON = String(data: messagesData, encoding: .utf8) else { return }

        // Build metadata
        var metaDict: [String: Any] = [
            "subtype": "agent_conversation",
            "conversationId": conversation.id,
            "source": conversation.source.rawValue,
            "messageCount": conversation.messages.count,
            "linkedAtomUUIDs": conversation.linkedAtomUUIDs
        ]
        let metadataJSON = (try? JSONSerialization.data(withJSONObject: metaDict)).flatMap { String(data: $0, encoding: .utf8) }

        // Build structured data for reconstruction
        var structuredDict: [String: Any] = [
            "createdAt": ISO8601DateFormatter().string(from: conversation.createdAt)
        ]
        if let summary = conversation.summary {
            structuredDict["summary"] = summary
        }
        let structuredJSON = (try? JSONSerialization.data(withJSONObject: structuredDict)).flatMap { String(data: $0, encoding: .utf8) }

        // Check if conversation atom already exists
        let existingAtoms = (try? await atomRepo.fetchAll(type: .systemEvent)) ?? []
        let existingConv = existingAtoms.first { atom in
            guard let meta = atom.metadata,
                  let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
                  let subtype = dict["subtype"] as? String,
                  let convId = dict["conversationId"] as? String else { return false }
            return subtype == "agent_conversation" && convId == conversation.id
        }

        if var existing = existingConv {
            existing.body = messagesJSON
            existing.metadata = metadataJSON
            existing.structured = structuredJSON
            try? await atomRepo.update(existing)
        } else {
            let atom = Atom.new(
                type: .systemEvent,
                title: "Agent Conversation: \(conversation.source.rawValue)",
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

        return convAtoms.prefix(limit).compactMap { decodeConversation(from: $0) }
    }

    // MARK: - Search Past Conversations

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

    /// Assembles recent conversation context for the LLM system prompt
    func buildContextWindow(for source: MessageSource, maxMessages: Int? = nil) async -> [AgentMessage] {
        let recent = await getRecentConversations(limit: 3)
        let sourceConversations = recent.filter { $0.source == source }

        let limit = maxMessages ?? maxWindowSize
        var contextMessages: [AgentMessage] = []

        for conv in sourceConversations {
            for msg in conv.messages.suffix(limit - contextMessages.count) {
                contextMessages.append(msg)
                if contextMessages.count >= limit { break }
            }
            if contextMessages.count >= limit { break }
        }

        return contextMessages
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

    // MARK: - Private Helpers

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

        // Parse structured data
        var summary: String? = nil
        var createdAt = Date()
        if let structuredStr = atom.structured,
           let structuredData = structuredStr.data(using: .utf8),
           let structuredDict = try? JSONSerialization.jsonObject(with: structuredData) as? [String: Any] {
            summary = structuredDict["summary"] as? String
            if let dateStr = structuredDict["createdAt"] as? String {
                createdAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
            }
        }

        // Reconstruct conversation with the original ID so lookups work
        var conv = AgentConversation(id: convId, source: source)
        for msg in messages {
            conv.messages.append(msg)
        }
        conv.summary = summary
        conv.linkedAtomUUIDs = linkedUUIDs

        return conv
    }
}
