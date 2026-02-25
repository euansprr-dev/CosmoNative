// CosmoOS/AI/CrossReferenceEngine.swift
// Background engine that proactively finds relationships between atoms
// using semantic similarity via HybridSearchEngine + embeddings.
// February 2026

import Foundation
import GRDB

// MARK: - Cross-Reference Result

struct CrossReference: Identifiable, Codable {
    let id: UUID
    let sourceAtomUUID: String
    let targetAtomUUID: String
    let targetTitle: String
    let targetType: AtomType
    let relevanceScore: Double  // 0-1
    let reason: String  // Brief explanation of why they're related
    let discoveredAt: Date

    init(
        id: UUID = UUID(),
        sourceAtomUUID: String,
        targetAtomUUID: String,
        targetTitle: String,
        targetType: AtomType,
        relevanceScore: Double,
        reason: String,
        discoveredAt: Date = Date()
    ) {
        self.id = id
        self.sourceAtomUUID = sourceAtomUUID
        self.targetAtomUUID = targetAtomUUID
        self.targetTitle = targetTitle
        self.targetType = targetType
        self.relevanceScore = relevanceScore
        self.reason = reason
        self.discoveredAt = discoveredAt
    }
}

// MARK: - Connection Suggestion (for content creation)

struct ConnectionSuggestion: Identifiable {
    let id: UUID
    let connection: Atom
    let maturityLevel: String  // "Seed", "Developing", "Mature", "Proven"
    let relevanceScore: Double
    let matchReason: String

    init(
        id: UUID = UUID(),
        connection: Atom,
        maturityLevel: String,
        relevanceScore: Double,
        matchReason: String
    ) {
        self.id = id
        self.connection = connection
        self.maturityLevel = maturityLevel
        self.relevanceScore = relevanceScore
        self.matchReason = matchReason
    }
}

// MARK: - Cross-Reference Engine

@MainActor
final class CrossReferenceEngine: ObservableObject {
    static let shared = CrossReferenceEngine()

    // MARK: - Dependencies

    private let database = CosmoDatabase.shared
    private let searchEngine = HybridSearchEngine.shared

    // MARK: - Configuration

    /// Minimum relevance score to surface a cross-reference
    private let minRelevanceScore: Double = 0.4

    /// Maximum cross-references to return per query
    private let maxResults = 10

    /// Debounce interval — don't re-process same atom within 30 seconds
    private let debounceInterval: TimeInterval = 30

    /// Tracks last processing time per atom UUID
    private var lastProcessed: [String: Date] = [:]

    private init() {}

    // MARK: - Trigger Methods

    /// Called when new research is saved. Finds related connections, other research, and content.
    func onResearchSave(atom: Atom) async {
        guard shouldProcess(atom: atom) else { return }
        print("🔗 CrossRef: Processing research save — \(atom.title ?? "Untitled")")

        let crossRefs = await findCrossReferences(for: atom)
        if !crossRefs.isEmpty {
            postCrossReferencesNotification(atomUUID: atom.uuid, crossReferences: crossRefs)
        }
    }

    /// Called when a connection is updated. Re-evaluates whether existing research/content now relates more strongly.
    func onConnectionUpdate(atom: Atom) async {
        guard shouldProcess(atom: atom) else { return }
        print("🔗 CrossRef: Processing connection update — \(atom.title ?? "Untitled")")

        await updateCrossReferences(for: atom)
    }

    /// Called when content creation starts. Finds relevant connections and research as proactive suggestions.
    func onContentCreation(atom: Atom) async {
        guard shouldProcess(atom: atom) else { return }
        print("🔗 CrossRef: Processing content creation — \(atom.title ?? "Untitled")")

        let suggestions = await findRelevantConnectionsForContent(contentAtom: atom)
        if !suggestions.isEmpty {
            postConnectionSuggestionsNotification(atomUUID: atom.uuid, suggestions: suggestions)
        }

        // Also find general cross-references (research, other content)
        let crossRefs = await findCrossReferences(for: atom)
        if !crossRefs.isEmpty {
            postCrossReferencesNotification(atomUUID: atom.uuid, crossReferences: crossRefs)
        }
    }

    // MARK: - Core Methods

    /// Find cross-references for any atom using semantic similarity.
    func findCrossReferences(for atom: Atom) async -> [CrossReference] {
        let queryText = buildQueryText(for: atom)
        guard !queryText.isEmpty else { return [] }

        // Determine which entity types to search (exclude the source type to find cross-domain refs)
        let targetTypes = crossReferenceTargetTypes(for: atom.type)

        do {
            let results = try await searchEngine.search(
                query: queryText,
                limit: maxResults + 5,  // Fetch extra to filter self-matches
                entityTypes: targetTypes
            )

            // Convert search results to CrossReference structs
            var crossRefs: [CrossReference] = []

            for result in results {
                // Skip self-references
                if let resultUUID = result.entityUUID, resultUUID == atom.uuid {
                    continue
                }
                // Skip results below threshold
                guard result.combinedScore >= minRelevanceScore else { continue }

                // Look up the target atom to get its UUID
                let targetAtom = try await lookupAtom(entityType: result.entityType, entityId: result.entityId)
                guard let target = targetAtom, target.uuid != atom.uuid else { continue }

                let reason = buildReason(
                    sourceType: atom.type,
                    targetType: target.type,
                    targetTitle: target.title ?? "Untitled",
                    matchReason: result.matchReason
                )

                crossRefs.append(CrossReference(
                    sourceAtomUUID: atom.uuid,
                    targetAtomUUID: target.uuid,
                    targetTitle: target.title ?? "Untitled",
                    targetType: target.type,
                    relevanceScore: result.combinedScore,
                    reason: reason
                ))
            }

            // Sort by relevance and cap
            crossRefs.sort { $0.relevanceScore > $1.relevanceScore }
            return Array(crossRefs.prefix(maxResults))

        } catch {
            print("🔗 CrossRef: Search failed — \(error.localizedDescription)")
            return []
        }
    }

    /// Re-evaluate cross-references when an atom is updated. Posts notification with new results.
    func updateCrossReferences(for atom: Atom) async {
        let crossRefs = await findCrossReferences(for: atom)
        if !crossRefs.isEmpty {
            postCrossReferencesNotification(atomUUID: atom.uuid, crossReferences: crossRefs)
        }
    }

    /// Specifically for content creation — finds relevant connections with maturity levels.
    func findRelevantConnectionsForContent(contentAtom: Atom) async -> [ConnectionSuggestion] {
        let queryText = buildQueryText(for: contentAtom)
        guard !queryText.isEmpty else { return [] }

        do {
            // Search specifically for connections
            let results = try await searchEngine.search(
                query: queryText,
                limit: 10,
                entityTypes: [.connection]
            )

            var suggestions: [ConnectionSuggestion] = []
            let coDevEngine = ConnectionCoDevEngine()

            for result in results {
                guard result.combinedScore >= minRelevanceScore else { continue }

                // Look up the connection atom
                let connectionAtom = try await lookupAtom(entityType: .connection, entityId: result.entityId)
                guard let conn = connectionAtom else { continue }

                // Compute maturity level
                let sourceCount = countLinkedSources(for: conn)
                let contentUsageCount = countContentUsage(for: conn)
                let maturity = coDevEngine.computeMaturity(
                    connection: conn,
                    sourceCount: sourceCount,
                    contentUsageCount: contentUsageCount,
                    profileCount: 0
                )

                let matchReason = buildConnectionMatchReason(
                    connectionTitle: conn.title ?? "Untitled",
                    contentTitle: contentAtom.title ?? "Untitled",
                    score: result.combinedScore
                )

                suggestions.append(ConnectionSuggestion(
                    connection: conn,
                    maturityLevel: maturity.displayName,
                    relevanceScore: result.combinedScore,
                    matchReason: matchReason
                ))
            }

            suggestions.sort { $0.relevanceScore > $1.relevanceScore }
            return suggestions

        } catch {
            print("🔗 CrossRef: Connection search failed — \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Debounce

    private func shouldProcess(atom: Atom) -> Bool {
        let now = Date()
        if let lastTime = lastProcessed[atom.uuid],
           now.timeIntervalSince(lastTime) < debounceInterval {
            print("🔗 CrossRef: Skipping \(atom.uuid) — debounced")
            return false
        }
        lastProcessed[atom.uuid] = now
        return true
    }

    // MARK: - Query Text Construction

    /// Build a rich query string from the atom's content for semantic search.
    private func buildQueryText(for atom: Atom) -> String {
        var parts: [String] = []

        if let title = atom.title, !title.isEmpty {
            parts.append(title)
        }

        let body = (atom.body ?? "")
        if !body.isEmpty {
            // Use first 500 chars of body for query
            parts.append(String(body.prefix(500)))
        }

        // For connections, extract structured section content
        if atom.type == .connection, let structured = atom.structured,
           let data = ConnectionStructuredData.fromJSON(structured) {
            for section in data.sections where !section.items.isEmpty {
                // Take first item from each filled section
                if let firstItem = section.items.first {
                    parts.append(firstItem.content)
                }
            }
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Target Type Resolution

    /// Determine which atom types to search for cross-references based on source type.
    private func crossReferenceTargetTypes(for sourceType: AtomType) -> [EntityType] {
        switch sourceType {
        case .research:
            return [.connection, .content, .idea, .research]
        case .connection:
            return [.research, .content, .idea, .connection]
        case .content:
            return [.connection, .research, .idea]
        case .idea:
            return [.research, .connection, .content]
        default:
            return [.research, .connection, .content, .idea]
        }
    }

    // MARK: - Atom Lookup

    /// Look up an atom by entity type and ID.
    private func lookupAtom(entityType: EntityType, entityId: Int64) async throws -> Atom? {
        try await database.asyncRead { db in
            try Atom
                .filter(Column("id") == entityId)
                .filter(Column("is_deleted") == false)
                .fetchOne(db)
        }
    }

    // MARK: - Connection Metadata Helpers

    /// Count linked source atoms for a connection (for maturity computation).
    private func countLinkedSources(for connection: Atom) -> Int {
        guard let structured = connection.structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return 0
        }
        // Count items that have a sourceAtomUUID
        return data.sections.flatMap(\.items).filter { $0.sourceAtomUUID != nil }.count
    }

    /// Count content atoms that reference this connection (for maturity computation).
    private func countContentUsage(for connection: Atom) -> Int {
        // Simple heuristic: check metadata for content usage count
        if let metadata = connection.metadata,
           let metaData = metadata.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
           let count = json["contentUsageCount"] as? Int {
            return count
        }
        return 0
    }

    // MARK: - Reason Building

    /// Build a human-readable reason for a cross-reference.
    private func buildReason(
        sourceType: AtomType,
        targetType: AtomType,
        targetTitle: String,
        matchReason: HybridSearchEngine.SearchResult.MatchReason
    ) -> String {
        let targetLabel = targetType.displayName
        switch matchReason {
        case .semanticSimilarity:
            return "Semantically related \(targetLabel.lowercased())"
        case .keywordMatch:
            return "Shares key concepts with this \(sourceType.displayName.lowercased())"
        case .contextRelevant:
            return "Contextually relevant \(targetLabel.lowercased())"
        case .recentlyViewed:
            return "Recently viewed related \(targetLabel.lowercased())"
        case .sharedConcepts:
            return "Overlapping concepts found"
        }
    }

    /// Build a specific match reason for connection suggestions.
    private func buildConnectionMatchReason(
        connectionTitle: String,
        contentTitle: String,
        score: Double
    ) -> String {
        if score > 0.7 {
            return "Strong thematic alignment with your content topic"
        } else if score > 0.5 {
            return "Related concepts that could strengthen your argument"
        } else {
            return "Potentially relevant mental model for this content"
        }
    }

    // MARK: - Notifications

    private func postCrossReferencesNotification(atomUUID: String, crossReferences: [CrossReference]) {
        print("🔗 CrossRef: Found \(crossReferences.count) cross-references for \(atomUUID)")
        NotificationCenter.default.post(
            name: CosmoNotification.Intelligence.crossReferencesUpdated,
            object: nil,
            userInfo: [
                "atomUUID": atomUUID,
                "crossReferences": crossReferences
            ]
        )
    }

    private func postConnectionSuggestionsNotification(atomUUID: String, suggestions: [ConnectionSuggestion]) {
        let summaryParts = suggestions.prefix(3).map { "\($0.connection.title ?? "Untitled") (\($0.maturityLevel))" }
        let summary = summaryParts.joined(separator: ", ")
        print("🔗 CrossRef: Found \(suggestions.count) connection suggestions for content — \(summary)")

        NotificationCenter.default.post(
            name: CosmoNotification.Intelligence.connectionSuggestionsAvailable,
            object: nil,
            userInfo: [
                "atomUUID": atomUUID,
                "connectionSuggestions": suggestions
            ]
        )
    }
}
