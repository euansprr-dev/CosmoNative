// CosmoOS/Cosmo/KnowledgeLinker.swift
// Auto-generates linked knowledge for connections
// Uses semantic search + LLM to find related content

import Foundation
import GRDB

@MainActor
class KnowledgeLinker {
    static let shared = KnowledgeLinker()

    private let database = CosmoDatabase.shared
    private var pendingUpdates: Set<Int64> = []
    private var updateTask: Task<Void, Never>?

    private init() {}

    // MARK: - Schedule Update
    /// Schedule a knowledge link update (debounced)
    func scheduleUpdate(for connectionId: Int64) async {
        pendingUpdates.insert(connectionId)

        // Cancel existing task
        updateTask?.cancel()

        // Schedule new task with debounce
        updateTask = Task {
            try? await Task.sleep(for: .seconds(3))

            guard !Task.isCancelled else { return }

            // Process all pending updates
            let updates = pendingUpdates
            pendingUpdates.removeAll()

            for id in updates {
                await updateLinkedKnowledge(for: id)
            }
        }
    }

    // MARK: - Update Linked Knowledge
    /// Generate linked knowledge for a connection
    func updateLinkedKnowledge(for connectionId: Int64) async {
        print("🔗 Updating linked knowledge for connection: \(connectionId)")

        do {
            // 1. Load connection
            guard let connection = try await loadConnection(connectionId) else {
                print("❌ Connection not found")
                return
            }

            // 2. Get combined text for search
            let searchText = connection.combinedText
            guard !searchText.isEmpty else {
                print("⚠️ Connection has no content to search")
                return
            }

            // 3. Find related entities using semantic search
            let related = try await findRelatedEntities(text: searchText, excludeConnectionId: connectionId)

            // 4. Use LLM to rank and explain connections
            let linkedItems = try await rankAndExplain(connection: connection, candidates: related)

            // 5. Store back to connection
            try await saveLinkedKnowledge(connectionId: connectionId, items: linkedItems)

            print("✅ Found \(linkedItems.count) linked items")

        } catch {
            print("❌ Failed to update linked knowledge: \(error)")
        }
    }

    // MARK: - Load Connection
    private func loadConnection(_ id: Int64) async throws -> Connection? {
        try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.connection.rawValue)
                .filter(Column("id") == id)
                .fetchOne(db)
                .map { ConnectionWrapper(atom: $0) }
        }
    }

    // MARK: - Find Related Entities
    private func findRelatedEntities(text: String, excludeConnectionId: Int64, limit: Int = 20) async throws -> [RelatedCandidate] {
        var candidates: [RelatedCandidate] = []

        // Search ideas
        let ideas: [Idea] = try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.idea.rawValue)
                .filter(Column("is_deleted") == false)
                .limit(limit)
                .fetchAll(db)
                .map { IdeaWrapper(atom: $0) }
        }

        for idea in ideas {
            let score = calculateSimilarity(text, idea.content)
            if score > 0.1 {
                candidates.append(RelatedCandidate(
                    entityType: "idea",
                    entityId: idea.id ?? 0,
                    title: idea.title ?? "Untitled Idea",
                    content: idea.content,
                    score: score
                ))
            }
        }

        // Search research
        let research: [Research] = try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .limit(limit)
                .fetchAll(db)
                .map { ResearchWrapper(atom: $0) }
        }

        for item in research {
            let content = [item.title, item.summary, item.content].compactMap { $0 }.joined(separator: " ")
            let score = calculateSimilarity(text, content)
            if score > 0.1 {
                candidates.append(RelatedCandidate(
                    entityType: "research",
                    entityId: item.id ?? 0,
                    title: item.title ?? "Untitled",
                    content: content,
                    score: score
                ))
            }
        }

        // Search other connections
        let connections: [Connection] = try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.connection.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(Column("id") != excludeConnectionId)
                .limit(limit)
                .fetchAll(db)
                .map { ConnectionWrapper(atom: $0) }
        }

        for conn in connections {
            let score = calculateSimilarity(text, conn.combinedText)
            if score > 0.1 {
                candidates.append(RelatedCandidate(
                    entityType: "connection",
                    entityId: conn.id ?? 0,
                    title: conn.title ?? "Untitled",
                    content: conn.combinedText,
                    score: score
                ))
            }
        }

        // Sort by score and limit
        return candidates.sorted { $0.score > $1.score }.prefix(10).map { $0 }
    }

    // MARK: - Calculate Similarity
    /// Simple TF-IDF-like similarity for quick filtering
    private func calculateSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().split(separator: " ").map(String.init))
        let words2 = Set(text2.lowercased().split(separator: " ").map(String.init))

        guard !words1.isEmpty && !words2.isEmpty else { return 0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return Double(intersection) / Double(union) // Jaccard similarity
    }

    // MARK: - Rank and Explain
    private func rankAndExplain(connection: Connection, candidates: [RelatedCandidate]) async throws -> [LinkedKnowledgeItem] {
        guard !candidates.isEmpty else { return [] }

        // Use LLM for better ranking
        let prompt = buildRankingPrompt(connection: connection, candidates: candidates)
        let response = await LocalLLM.shared.generate(prompt: prompt, maxTokens: 1000)

        // Parse LLM response, fallback to simple scoring if parsing fails
        let parsedItems = parseLinkedItems(from: response, candidates: candidates)
        if !parsedItems.isEmpty {
            return parsedItems
        }

        // Fallback to simple scoring
        return candidates.prefix(5).map { candidate in
            LinkedKnowledgeItem(
                entityType: candidate.entityType,
                entityId: candidate.entityId,
                title: candidate.title,
                relevanceScore: candidate.score,
                explanation: nil
            )
        }
    }

    private func buildRankingPrompt(connection: Connection, candidates: [RelatedCandidate]) -> String {
        let model = connection.mentalModel
        var prompt = """
        Analyze how these items relate to the following mental model/connection:

        Connection: "\(connection.title ?? "Untitled")"
        Core Idea: \(model?.coreIdea ?? "Not specified")
        Goal: \(model?.goal ?? "Not specified")

        Candidates:
        """

        for (index, candidate) in candidates.enumerated() {
            prompt += "\n\(index + 1). [\(candidate.entityType)] \(candidate.title)"
            if let preview = candidate.content.prefix(200).description.nilIfEmpty {
                prompt += ": \(preview)..."
            }
        }

        prompt += """

        For each candidate, provide:
        1. Relevance score (0-100)
        2. One-sentence explanation of how it relates

        Format: INDEX|SCORE|EXPLANATION
        Only include items with relevance > 30.
        """

        return prompt
    }

    private func parseLinkedItems(from response: String, candidates: [RelatedCandidate]) -> [LinkedKnowledgeItem] {
        var items: [LinkedKnowledgeItem] = []

        let lines = response.split(separator: "\n")
        for line in lines {
            let parts = line.split(separator: "|")
            guard parts.count >= 2,
                  let index = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let score = Double(parts[1].trimmingCharacters(in: .whitespaces)),
                  index > 0 && index <= candidates.count else {
                continue
            }

            let candidate = candidates[index - 1]
            let explanation = parts.count > 2 ? String(parts[2]).trimmingCharacters(in: .whitespaces) : nil

            items.append(LinkedKnowledgeItem(
                entityType: candidate.entityType,
                entityId: candidate.entityId,
                title: candidate.title,
                relevanceScore: score / 100.0,
                explanation: explanation
            ))
        }

        return items.sorted { ($0.relevanceScore ?? 0) > ($1.relevanceScore ?? 0) }
    }

    // MARK: - Save Linked Knowledge
    private func saveLinkedKnowledge(connectionId: Int64, items: [LinkedKnowledgeItem]) async throws {
        guard var connection = try await loadConnection(connectionId) else { return }

        var model = connection.mentalModel ?? ConnectionMentalModel()

        // Encode items to JSON
        if let data = try? JSONEncoder().encode(items),
           let json = String(data: data, encoding: .utf8) {
            model.linkedKnowledge = json
            model.linkedKnowledgeUpdatedAt = ISO8601DateFormatter().string(from: Date())
        }

        connection.setMentalModel(model)
        connection.updatedAt = ISO8601DateFormatter().string(from: Date())

        // Capture as immutable for Sendable closure
        let connectionToSave = connection
        try await database.asyncWrite { db in
            try connectionToSave.save(db)
        }
    }
}

// MARK: - Related Candidate
private struct RelatedCandidate {
    let entityType: String
    let entityId: Int64
    let title: String
    let content: String
    let score: Double
}

// MARK: - String Extension
private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
