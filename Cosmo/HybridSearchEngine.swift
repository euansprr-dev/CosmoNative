// CosmoOS/Cosmo/HybridSearchEngine.swift
// Hybrid BM25 + Vector Search for Telepathic Voice Assistant
// Combines fast keyword search with semantic understanding
// Query embeddings come from the Recall cloud client; stored vectors live in recall_vectors

import Foundation
import Accelerate
import GRDB

/// Hybrid search engine combining BM25 keyword search with vector similarity
/// Achieves both speed (BM25 pre-filter) and semantic understanding (vector re-ranking)
@MainActor
final class HybridSearchEngine: ObservableObject {
    static let shared = HybridSearchEngine()

    // MARK: - Dependencies

    private let database = CosmoDatabase.shared

    /// Vector dimension used for search (Matryoshka truncation)

    // MARK: - Configuration

    /// Default hybrid weight: 0.7 = 70% vector, 30% BM25
    let defaultHybridWeight: Double = 0.7

    /// Maximum candidates from BM25 pre-filter
    let maxBM25Candidates = 100

    /// Minimum similarity threshold for results
    let minSimilarity: Float = 0.3

    private init() {}

    // MARK: - UUID Resolution

    /// Resolve the atom UUID from entity type + id by querying the atoms table
    private func resolveUUID(entityType: String, entityId: Int64) async -> String? {
        guard entityId > 0 else { return nil }
        do {
            return try await database.asyncRead { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT uuid FROM atoms WHERE type = ? AND id = ? AND is_deleted = 0 LIMIT 1",
                    arguments: [entityType, entityId]
                )
            }
        } catch {
            return nil
        }
    }

    // MARK: - Search Results

    struct SearchResult: Identifiable, Sendable {
        let id = UUID()
        let entityType: EntityType
        let entityId: Int64
        let entityUUID: String?
        let title: String
        let preview: String
        let bm25Score: Double
        let vectorSimilarity: Double
        let combinedScore: Double
        let matchReason: MatchReason
        var updatedAt: String? = nil
        /// True when the strict all-terms BM25 pass produced this result.
        /// False for the broad any-term fallback and pure-vector results, so
        /// downstream ranking can tell real keyword evidence from partials.
        var matchedAllTerms: Bool = false

        enum MatchReason: String, Sendable {
            case keywordMatch = "Keyword match"
            case semanticSimilarity = "Semantically related"
            case contextRelevant = "Related to your context"
            case recentlyViewed = "Recently viewed"
            case sharedConcepts = "Shared concepts"
        }
    }

    // MARK: - BM25 Candidate

    private struct BM25Candidate {
        let uuid: String
        let entityType: String
        let entityId: Int64
        let title: String
        let content: String
        let bm25Score: Double
        let updatedAt: String?
    }

    // MARK: - Hybrid Search

    /// Perform hybrid search combining BM25 keyword matching with vector similarity
    /// - Parameters:
    ///   - query: Search query text
    ///   - context: Optional voice context for boosting
    ///   - limit: Maximum number of results
    ///   - hybridWeight: Weight for vector vs BM25 (0.0 = all BM25, 1.0 = all vector)
    ///   - entityTypes: Optional filter for specific entity types
    /// - Returns: Array of ranked search results
    func search(
        query: String,
        context: VoiceContextSnapshot? = nil,
        limit: Int = 10,
        hybridWeight: Double? = nil,
        entityTypes: [EntityType]? = nil,
        excludedEntityUUIDs: [String] = []
    ) async throws -> [SearchResult] {
        try Task.checkCancellation()
        let weight = hybridWeight ?? defaultHybridWeight
        let excludedUUIDs = Set(excludedEntityUUIDs)

        print("🔍 Hybrid search: \"\(query)\" (weight: \(Int(weight * 100))% vector)")

        // Stage 1: BM25 pre-filter for fast candidate retrieval
        let (bm25Candidates, matchedAllTerms) = try await bm25Search(
            query: query,
            limit: maxBM25Candidates,
            entityTypes: entityTypes,
            excludedEntityUUIDs: excludedUUIDs
        )
        try Task.checkCancellation()

        print("  📋 BM25 candidates: \(bm25Candidates.count)")

        guard !bm25Candidates.isEmpty else {
            // No keyword matches - fall back to pure vector search
            return try await pureVectorSearch(
                query: query,
                limit: limit,
                entityTypes: entityTypes,
                excludedEntityUUIDs: excludedUUIDs
            )
        }

        // Stage 2: Generate query embedding for vector similarity (Recall
        // cloud client — the daemon embedding path was a dormant stub).
        let queryVector: [Float]
        do {
            guard let vector = try await CloudEmbeddingClient().embed([query]).first else {
                throw RecallEmbeddingError.notConfigured
            }
            try Task.checkCancellation()
            queryVector = vector
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("  ⚠️ Embedding failed, using BM25 only: \(error.localizedDescription)")
            var fallbackResults: [SearchResult] = []
            for candidate in bm25Candidates.prefix(limit) {
                try Task.checkCancellation()
                if excludedUUIDs.contains(candidate.uuid) {
                    continue
                }
                guard let entityType = Self.mapAtomTypeToEntityType(candidate.entityType) else { continue }
                fallbackResults.append(SearchResult(
                    entityType: entityType,
                    entityId: candidate.entityId,
                    entityUUID: candidate.uuid,
                    title: candidate.title,
                    preview: String(candidate.content.prefix(200)),
                    bm25Score: candidate.bm25Score,
                    vectorSimilarity: 0,
                    combinedScore: candidate.bm25Score,
                    matchReason: .keywordMatch,
                    updatedAt: candidate.updatedAt,
                    matchedAllTerms: matchedAllTerms
                ))
            }
            return fallbackResults
        }

        // Stage 3: Compute vector similarity and combine scores.
        // One batched read for every candidate's chunks, with decode + cosine
        // running on the database queue — never the main actor.
        let candidateUUIDs = bm25Candidates.map(\.uuid).filter { !excludedUUIDs.contains($0) && !$0.isEmpty }
        let similarityByUUID = try await batchVectorSimilarity(
            entityUUIDs: candidateUUIDs,
            queryVector: queryVector
        )
        try Task.checkCancellation()

        var scoredResults: [SearchResult] = []

        for candidate in bm25Candidates {
            if excludedUUIDs.contains(candidate.uuid) {
                continue
            }
            let vectorSimilarity = similarityByUUID[candidate.uuid] ?? 0

            // Combine scores: weighted average of BM25 and vector similarity
            let normalizedBM25 = min(candidate.bm25Score / 25.0, 1.0)  // Normalize BM25 score
            let combinedScore = (weight * Double(vectorSimilarity)) + ((1 - weight) * normalizedBM25)

            // Determine match reason
            let matchReason: SearchResult.MatchReason
            if vectorSimilarity > 0.7 && normalizedBM25 > 0.5 {
                matchReason = .keywordMatch  // Strong keyword + semantic match
            } else if vectorSimilarity > 0.6 {
                matchReason = .semanticSimilarity
            } else {
                matchReason = .keywordMatch
            }

            guard let entityType = Self.mapAtomTypeToEntityType(candidate.entityType) else { continue }

            let result = SearchResult(
                entityType: entityType,
                entityId: candidate.entityId,
                entityUUID: candidate.uuid,
                title: candidate.title,
                preview: String(candidate.content.prefix(200)),
                bm25Score: candidate.bm25Score,
                vectorSimilarity: Double(vectorSimilarity),
                combinedScore: combinedScore,
                matchReason: matchReason,
                updatedAt: candidate.updatedAt,
                matchedAllTerms: matchedAllTerms
            )

            // Every candidate already matched the query by keyword — keep it
            // and let ranking decide its position. Dropping low-similarity
            // candidates here used to hide exact keyword matches whenever
            // embeddings were missing or weak.
            scoredResults.append(result)
        }

        // Stage 4: Apply context boosting if available
        if let ctx = context, ctx.contextVector != nil {
            scoredResults = await applyContextBoost(results: scoredResults, context: ctx)
            try Task.checkCancellation()
        }

        // Sort by combined score and return top results
        scoredResults.sort { $0.combinedScore > $1.combinedScore }

        print("  ✅ Returning \(min(limit, scoredResults.count)) results")

        return Array(scoredResults.prefix(limit)).filter { result in
            guard let entityUUID = result.entityUUID else { return true }
            return !excludedUUIDs.contains(entityUUID)
        }
    }

    // MARK: - Context-Aware Search

    /// Search for content related to what the user is currently editing
    /// Uses the editing context vector for pure semantic search
    func searchRelatedToContext(
        context: VoiceContextSnapshot,
        limit: Int = 5,
        entityTypes: [EntityType]? = nil
    ) async throws -> [SearchResult] {
        try Task.checkCancellation()
        guard let contextVector = context.contextVector else {
            // Fall back to concept-based search using extracted concepts
            if !context.extractedConcepts.isEmpty {
                let query = context.extractedConcepts.joined(separator: " ")
                return try await search(
                    query: query,
                    context: context,
                    limit: limit,
                    entityTypes: entityTypes
                )
            }

            // Last resort: use editing title
            if let title = context.editingTitle, !title.isEmpty {
                return try await search(
                    query: title,
                    context: context,
                    limit: limit,
                    entityTypes: entityTypes
                )
            }

            return []
        }

        print("🔍 Context-aware search using editing context vector")

        // Exclude the entity being edited
        let excludeType = context.editingEntityType
        let excludeId = context.editingEntityId

        // Pure vector search using context
        return try await pureVectorSearch(
            queryVector: contextVector,
            limit: limit,
            entityTypes: entityTypes,
            excludeEntity: (excludeType, excludeId),
            excludedEntityUUIDs: []
        )
    }

    // MARK: - BM25 Search (FTS5)

    /// Fast keyword search using SQLite FTS5 with BM25 ranking
    private func bm25Search(
        query: String,
        limit: Int,
        entityTypes: [EntityType]?,
        excludedEntityUUIDs: Set<String>
    ) async throws -> (candidates: [BM25Candidate], matchedAllTerms: Bool) {
        try Task.checkCancellation()
        // Spotlight semantics: require every term first, then broaden to
        // any-term matching only when the strict query finds nothing.
        let strictQuery = Self.prepareFTS5Query(query)
        let candidates = try await runBM25Query(
            ftsQuery: strictQuery,
            limit: limit,
            entityTypes: entityTypes,
            excludedEntityUUIDs: excludedEntityUUIDs
        )
        if !candidates.isEmpty {
            return (candidates, true)
        }

        let broadQuery = Self.prepareFTS5Query(query, matchAnyTerm: true)
        guard broadQuery != strictQuery else { return (candidates, false) }
        try Task.checkCancellation()
        let broadCandidates = try await runBM25Query(
            ftsQuery: broadQuery,
            limit: limit,
            entityTypes: entityTypes,
            excludedEntityUUIDs: excludedEntityUUIDs
        )
        return (broadCandidates, false)
    }

    private func runBM25Query(
        ftsQuery: String,
        limit: Int,
        entityTypes: [EntityType]?,
        excludedEntityUUIDs: Set<String>
    ) async throws -> [BM25Candidate] {
        guard !ftsQuery.isEmpty else { return [] }
        let candidates = try await database.asyncRead { db in
            // Query atoms_fts (unified atom index) instead of legacy semantic_fts
            // BM25 weights: uuid=0, type=0, title=10, body=5, metadata=1
            var sql = """
                SELECT atoms.uuid, atoms.type, atoms.title, atoms.body, atoms.updated_at,
                       bm25(atoms_fts, 0, 0, 10, 5, 1) AS score
                FROM atoms_fts
                JOIN atoms ON atoms.uuid = atoms_fts.uuid
                WHERE atoms_fts MATCH ?
                  AND atoms.is_deleted = 0
            """

            var arguments: [DatabaseValueConvertible] = [ftsQuery]

            // Internal bookkeeping atoms (agent conversation logs, sync/XP
            // events…) are trigger-indexed into atoms_fts but must never
            // surface as search results.
            let excludedTypes = AtomType.searchExcludedRawValues
            let excludedPlaceholders = excludedTypes.map { _ in "?" }.joined(separator: ", ")
            sql += " AND atoms.type NOT IN (\(excludedPlaceholders))"
            arguments.append(contentsOf: excludedTypes)

            // Filter by entity types if specified
            if let types = entityTypes, !types.isEmpty {
                let placeholders = types.map { _ in "?" }.joined(separator: ", ")
                sql += " AND atoms.type IN (\(placeholders))"
                // Map EntityType to AtomType raw values stored in atoms_fts
                for t in types {
                    switch t {
                    case .journal: arguments.append("journal_entry")
                    default: arguments.append(t.rawValue)
                    }
                }
            }

            if !excludedEntityUUIDs.isEmpty {
                let placeholders = excludedEntityUUIDs.map { _ in "?" }.joined(separator: ", ")
                sql += " AND atoms.uuid NOT IN (\(placeholders))"
                arguments.append(contentsOf: Array(excludedEntityUUIDs))
            }

            sql += " ORDER BY score LIMIT ?"
            arguments.append(limit)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

            return rows.map { row in
                BM25Candidate(
                    uuid: row["uuid"] as? String ?? "",
                    entityType: row["type"] as? String ?? "idea",
                    entityId: 0,  // Not used with atoms_fts — UUID is the identifier
                    title: row["title"] as? String ?? "",
                    content: row["body"] as? String ?? "",
                    bm25Score: -(row["score"] as? Double ?? 0),  // BM25 returns negative scores
                    updatedAt: row["updated_at"] as? String
                )
            }
        }
        try Task.checkCancellation()
        return candidates
    }

    /// Prepare query string for FTS5: each term quoted (so operators and
    /// punctuation can't break MATCH syntax) with a prefix wildcard.
    /// Terms are required (AND) by default; `matchAnyTerm` broadens to OR.
    nonisolated static func prepareFTS5Query(_ query: String, matchAnyTerm: Bool = false) -> String {
        let words = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { word in
                // Escape double quotes
                let escaped = word.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }

        return words.joined(separator: matchAnyTerm ? " OR " : " ")
    }

    // MARK: - Pure Vector Search

    /// Pure semantic search using vector similarity (when BM25 finds nothing)
    private func pureVectorSearch(
        query: String,
        limit: Int,
        entityTypes: [EntityType]?,
        excludedEntityUUIDs: Set<String>
    ) async throws -> [SearchResult] {
        try Task.checkCancellation()
        guard let queryVector = try? await CloudEmbeddingClient().embed([query]).first else {
            return []
        }
        try Task.checkCancellation()
        return try await pureVectorSearch(
            queryVector: queryVector,
            limit: limit,
            entityTypes: entityTypes,
            excludeEntity: (nil, nil),
            excludedEntityUUIDs: excludedEntityUUIDs
        )
    }

    /// Pure vector search with pre-computed query vector (Recall index sweep)
    private func pureVectorSearch(
        queryVector: [Float],
        limit: Int,
        entityTypes: [EntityType]?,
        excludeEntity: (EntityType?, Int64?),
        excludedEntityUUIDs: Set<String> = []
    ) async throws -> [SearchResult] {
        try Task.checkCancellation()
        var allowedTypeRawValues = entityTypes.map { Set($0.map(\.rawValue)) }
        if entityTypes?.contains(.journal) == true {
            allowedTypeRawValues?.insert(AtomType.journalEntry.rawValue)
        }

        // Over-fetch chunks so entity-level dedupe still fills the limit.
        let hits = await RecallStore.shared.search(
            embedding: queryVector,
            limit: max(limit * 4, 24),
            entityTypes: allowedTypeRawValues,
            minSimilarity: minSimilarity
        )
        try Task.checkCancellation()

        // Deduplicate by entity (hits arrive similarity-sorted).
        var seen: Set<String> = []
        var deduplicated: [RecallVectorHit] = []
        for hit in hits where !seen.contains(hit.entityUuid) {
            seen.insert(hit.entityUuid)
            deduplicated.append(hit)
        }

        // Hydrate atoms for id/title enrichment.
        let uuids = deduplicated.map(\.entityUuid)
        let atoms: [String: Atom] = (try? await database.asyncRead { db in
            let fetched = try Atom
                .filter(uuids.contains(Column("uuid")))
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
            return Dictionary(uniqueKeysWithValues: fetched.map { ($0.uuid, $0) })
        }) ?? [:]

        var enrichedResults: [SearchResult] = []
        for hit in deduplicated {
            guard enrichedResults.count < limit else { break }
            guard !excludedEntityUUIDs.contains(hit.entityUuid) else { continue }
            guard let atom = atoms[hit.entityUuid] else { continue }
            if let excludeTypeRaw = excludeEntity.0?.rawValue, let excludeId = excludeEntity.1,
               atom.type.rawValue == excludeTypeRaw, atom.id == excludeId {
                continue
            }
            guard let entityType = Self.mapAtomTypeToEntityType(hit.entityType) else { continue }
            enrichedResults.append(SearchResult(
                entityType: entityType,
                entityId: atom.id ?? 0,
                entityUUID: hit.entityUuid,
                title: atom.title?.isEmpty == false ? atom.title! : "Untitled",
                preview: String(hit.text.prefix(200)),
                bm25Score: 0,
                vectorSimilarity: Double(hit.similarity),
                combinedScore: Double(hit.similarity),
                matchReason: .semanticSimilarity
            ))
        }
        return enrichedResults
    }

    /// Max vector similarity per entity UUID for a batch of candidates,
    /// computed in one sweep over the Recall index's in-memory matrix.
    private func batchVectorSimilarity(
        entityUUIDs: [String],
        queryVector: [Float]
    ) async throws -> [String: Float] {
        guard !entityUUIDs.isEmpty else { return [:] }
        return await RecallStore.shared.bestSimilarities(
            entityUuids: Set(entityUUIDs),
            query: queryVector
        )
    }

    /// Map AtomType raw value string to EntityType (handles journal_entry → .journal).
    /// Returns nil for types with no search-result representation (e.g.
    /// system_event) so they are skipped instead of masquerading as ideas.
    private nonisolated static func mapAtomTypeToEntityType(_ atomTypeRaw: String) -> EntityType? {
        if atomTypeRaw == "journal_entry" {
            return .journal
        }
        return EntityType(rawValue: atomTypeRaw)
    }

    // MARK: - Context Boosting

    /// Apply context-based boosting to search results (one Recall sweep).
    private func applyContextBoost(
        results: [SearchResult],
        context: VoiceContextSnapshot
    ) async -> [SearchResult] {
        guard let contextVector = context.contextVector else {
            return results
        }

        let uuids = Set(results.compactMap(\.entityUUID))
        let similarities = await RecallStore.shared.bestSimilarities(
            entityUuids: uuids, query: contextVector
        )

        return results.map { result in
            guard let uuid = result.entityUUID,
                  let contextSimilarity = similarities[uuid],
                  contextSimilarity > 0.5 else { return result }
            let boost = Double(contextSimilarity) * 0.2  // Up to 20% boost
            return SearchResult(
                entityType: result.entityType,
                entityId: result.entityId,
                entityUUID: result.entityUUID,
                title: result.title,
                preview: result.preview,
                bm25Score: result.bm25Score,
                vectorSimilarity: result.vectorSimilarity,
                combinedScore: result.combinedScore + boost,
                matchReason: .contextRelevant,
                updatedAt: result.updatedAt,
                matchedAllTerms: result.matchedAllTerms
            )
        }
    }

}
