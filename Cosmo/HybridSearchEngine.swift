// CosmoOS/Cosmo/HybridSearchEngine.swift
// Hybrid BM25 + Vector Search for Telepathic Voice Assistant
// Combines fast keyword search with semantic understanding
// Uses DaemonXPCClient for real 768d embeddings, truncated to 256d Matryoshka

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
    private let semanticEngine = SemanticSearchEngine.shared

    /// Vector dimension used for search (Matryoshka truncation)
    private let vectorDimension = VectorConfig.matryoshkaDimension  // 256

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
        let bm25Candidates = try await bm25Search(
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

        // Stage 2: Generate query embedding for vector similarity via DaemonXPCClient
        let queryVector: [Float]
        do {
            let fullVector = try await DaemonXPCClient.shared.embed(text: query)
            try Task.checkCancellation()
            // Truncate 768d → 256d Matryoshka to match stored vectors
            queryVector = Array(fullVector.prefix(vectorDimension))
            if fullVector.count != vectorDimension {
                print("  📐 Truncated query vector \(fullVector.count)d → \(queryVector.count)d")
            }
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
                let entityType = mapAtomTypeToEntityType(candidate.entityType)
                fallbackResults.append(SearchResult(
                    entityType: entityType,
                    entityId: candidate.entityId,
                    entityUUID: candidate.uuid,
                    title: candidate.title,
                    preview: String(candidate.content.prefix(200)),
                    bm25Score: candidate.bm25Score,
                    vectorSimilarity: 0,
                    combinedScore: candidate.bm25Score,
                    matchReason: .keywordMatch
                ))
            }
            return fallbackResults
        }

        // Stage 3: Compute vector similarity and combine scores
        var scoredResults: [SearchResult] = []

        for candidate in bm25Candidates {
            try Task.checkCancellation()
            if excludedUUIDs.contains(candidate.uuid) {
                continue
            }
            // Get vector similarity using atom UUID (from atoms_fts)
            let vectorSimilarity = await getVectorSimilarity(
                entityUUID: candidate.uuid,
                queryVector: queryVector
            )

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

            let entityType = mapAtomTypeToEntityType(candidate.entityType)

            let result = SearchResult(
                entityType: entityType,
                entityId: candidate.entityId,
                entityUUID: candidate.uuid,
                title: candidate.title,
                preview: String(candidate.content.prefix(200)),
                bm25Score: candidate.bm25Score,
                vectorSimilarity: Double(vectorSimilarity),
                combinedScore: combinedScore,
                matchReason: matchReason
            )

            if vectorSimilarity >= minSimilarity || normalizedBM25 > 0.3 {
                scoredResults.append(result)
            }
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
    ) async throws -> [BM25Candidate] {
        try Task.checkCancellation()
        // Escape special FTS5 characters and prepare query
        let escapedQuery = prepareFTS5Query(query)

        let candidates = try await database.asyncRead { db in
            // Query atoms_fts (unified atom index) instead of legacy semantic_fts
            // BM25 weights: uuid=0, type=0, title=10, body=5, metadata=1
            var sql = """
                SELECT atoms.uuid, atoms.type, atoms.title, atoms.body,
                       bm25(atoms_fts, 0, 0, 10, 5, 1) AS score
                FROM atoms_fts
                JOIN atoms ON atoms.uuid = atoms_fts.uuid
                WHERE atoms_fts MATCH ?
                  AND atoms.is_deleted = 0
            """

            var arguments: [DatabaseValueConvertible] = [escapedQuery]

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
                    bm25Score: -(row["score"] as? Double ?? 0)  // BM25 returns negative scores
                )
            }
        }
        try Task.checkCancellation()
        return candidates
    }

    /// Prepare query string for FTS5 (handle special characters)
    private func prepareFTS5Query(_ query: String) -> String {
        // Split into words and wrap each in quotes for literal matching
        // Also add wildcard suffix for prefix matching
        let words = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { word in
                // Escape double quotes
                let escaped = word.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }

        // Join with OR for broader matching
        return words.joined(separator: " OR ")
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
        let fullVector = try await DaemonXPCClient.shared.embed(text: query)
        try Task.checkCancellation()
        // Truncate 768d → 256d Matryoshka to match stored vectors
        let queryVector = Array(fullVector.prefix(vectorDimension))
        return try await pureVectorSearch(
            queryVector: queryVector,
            limit: limit,
            entityTypes: entityTypes,
            excludeEntity: (nil, nil),
            excludedEntityUUIDs: excludedEntityUUIDs
        )
    }

    /// Pure vector search with pre-computed query vector
    private func pureVectorSearch(
        queryVector: [Float],
        limit: Int,
        entityTypes: [EntityType]?,
        excludeEntity: (EntityType?, Int64?),
        excludedEntityUUIDs: Set<String> = []
    ) async throws -> [SearchResult] {
        try Task.checkCancellation()
        // Fetch all semantic chunks
        let chunks = try await database.asyncRead { db in
            try SemanticChunk
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
        try Task.checkCancellation()

        var results: [(entityType: String, entityId: Int64, title: String, text: String, similarity: Float)] = []

        for chunk in chunks {
            try Task.checkCancellation()
            // Skip excluded entity
            if let excludeType = excludeEntity.0,
               let excludeId = excludeEntity.1,
               chunk.entityType == excludeType.rawValue,
               chunk.entityId == excludeId {
                continue
            }

            // Filter by entity types
            if let types = entityTypes {
                let chunkType = EntityType(rawValue: chunk.entityType) ?? .idea
                if !types.contains(chunkType) {
                    continue
                }
            }

            guard let vectorData = chunk.vector,
                  let chunkVec = decodeVector(vectorData) else { continue }

            // Handle dimension mismatch by truncating the larger vector
            let (a, b): ([Float], [Float])
            if chunkVec.count == queryVector.count {
                (a, b) = (queryVector, chunkVec)
            } else if chunkVec.count > queryVector.count {
                (a, b) = (queryVector, Array(chunkVec.prefix(queryVector.count)))
            } else {
                (a, b) = (Array(queryVector.prefix(chunkVec.count)), chunkVec)
            }

            let similarity = cosineSimilarity(a, b)

            if similarity >= minSimilarity {
                results.append((
                    entityType: chunk.entityType,
                    entityId: chunk.entityId,
                    title: chunk.fieldName ?? "Untitled",
                    text: chunk.text,
                    similarity: similarity
                ))
            }
        }

        // Deduplicate by entity (keep highest similarity)
        var seen: Set<String> = []
        var deduplicated: [(entityType: String, entityId: Int64, title: String, text: String, similarity: Float)] = []

        results.sort { $0.similarity > $1.similarity }

        for result in results {
            let key = "\(result.entityType)-\(result.entityId)"
            if !seen.contains(key) {
                seen.insert(key)
                deduplicated.append(result)
            }
        }

        // Enrich with entity details and return
        var enrichedResults: [SearchResult] = []
        for result in deduplicated.prefix(limit) {
            try Task.checkCancellation()
            let uuid = await resolveUUID(entityType: result.entityType, entityId: result.entityId)
            if let uuid, excludedEntityUUIDs.contains(uuid) {
                continue
            }
            enrichedResults.append(SearchResult(
                entityType: EntityType(rawValue: result.entityType) ?? .idea,
                entityId: result.entityId,
                entityUUID: uuid,
                title: result.title,
                preview: String(result.text.prefix(200)),
                bm25Score: 0,
                vectorSimilarity: Double(result.similarity),
                combinedScore: Double(result.similarity),
                matchReason: .semanticSimilarity
            ))
        }
        return enrichedResults
    }

    // MARK: - Vector Similarity Lookup

    /// Get vector similarity for a specific entity
    private func getVectorSimilarity(
        entityType: String,
        entityId: Int64,
        queryVector: [Float]
    ) async -> Float {
        do {
            let chunks = try await database.asyncRead { db in
                try SemanticChunk
                    .filter(Column("entity_type") == entityType)
                    .filter(Column("entity_id") == entityId)
                    .fetchAll(db)
            }

            // Find max similarity across all chunks for this entity
            var maxSimilarity: Float = 0

            for chunk in chunks {
                if Task.isCancelled { return 0 }
                guard let vectorData = chunk.vector,
                      let chunkVector = decodeVector(vectorData) else {
                    continue
                }

                // Handle dimension mismatch by truncating the larger vector
                let (a, b): ([Float], [Float])
                if chunkVector.count == queryVector.count {
                    (a, b) = (queryVector, chunkVector)
                } else if chunkVector.count > queryVector.count {
                    (a, b) = (queryVector, Array(chunkVector.prefix(queryVector.count)))
                    print("  ⚠️ Truncated stored vector \(chunkVector.count)d → \(queryVector.count)d for \(entityType):\(entityId)")
                } else {
                    (a, b) = (Array(queryVector.prefix(chunkVector.count)), chunkVector)
                    print("  ⚠️ Truncated query vector \(queryVector.count)d → \(chunkVector.count)d for \(entityType):\(entityId)")
                }

                let similarity = cosineSimilarity(a, b)
                maxSimilarity = max(maxSimilarity, similarity)
            }

            return maxSimilarity

        } catch {
            return 0
        }
    }

    /// Get vector similarity for an entity by UUID (using semantic_chunks.entity_uuid)
    private func getVectorSimilarity(
        entityUUID: String,
        queryVector: [Float]
    ) async -> Float {
        guard !entityUUID.isEmpty else { return 0 }
        do {
            let rows = try await database.asyncRead { db in
                try Row.fetchAll(db,
                    sql: "SELECT vector FROM semantic_chunks WHERE entity_uuid = ?",
                    arguments: [entityUUID])
            }

            var maxSimilarity: Float = 0
            for row in rows {
                if Task.isCancelled { return 0 }
                guard let vectorData = row["vector"] as? Data,
                      let chunkVector = decodeVector(vectorData) else { continue }

                let (a, b): ([Float], [Float])
                if chunkVector.count == queryVector.count {
                    (a, b) = (queryVector, chunkVector)
                } else if chunkVector.count > queryVector.count {
                    (a, b) = (queryVector, Array(chunkVector.prefix(queryVector.count)))
                } else {
                    (a, b) = (Array(queryVector.prefix(chunkVector.count)), chunkVector)
                }

                let similarity = cosineSimilarity(a, b)
                maxSimilarity = max(maxSimilarity, similarity)
            }
            return maxSimilarity
        } catch {
            return 0
        }
    }

    /// Map AtomType raw value string to EntityType (handles journal_entry → .journal)
    private func mapAtomTypeToEntityType(_ atomTypeRaw: String) -> EntityType {
        if atomTypeRaw == "journal_entry" {
            return .journal
        }
        return EntityType(rawValue: atomTypeRaw) ?? .idea
    }

    // MARK: - Context Boosting

    /// Apply context-based boosting to search results
    private func applyContextBoost(
        results: [SearchResult],
        context: VoiceContextSnapshot
    ) async -> [SearchResult] {
        guard let contextVector = context.contextVector else {
            return results
        }

        var boostedResults: [SearchResult] = []

        for result in results {
            if Task.isCancelled { return results }
            let contextSimilarity = await getVectorSimilarity(
                entityType: result.entityType.rawValue,
                entityId: result.entityId,
                queryVector: contextVector
            )

            // Boost score if similar to editing context
            if contextSimilarity > 0.5 {
                let boost = Double(contextSimilarity) * 0.2  // Up to 20% boost
                boostedResults.append(SearchResult(
                    entityType: result.entityType,
                    entityId: result.entityId,
                    entityUUID: result.entityUUID,
                    title: result.title,
                    preview: result.preview,
                    bm25Score: result.bm25Score,
                    vectorSimilarity: result.vectorSimilarity,
                    combinedScore: result.combinedScore + boost,
                    matchReason: .contextRelevant
                ))
            } else {
                boostedResults.append(result)
            }
        }

        return boostedResults
    }

    // MARK: - Vector Utilities

    private func decodeVector(_ data: Data) -> [Float]? {
        let floatSize = MemoryLayout<Float>.size
        let elementCount = data.count / floatSize

        guard [256, 384, 768, 1024].contains(elementCount) else {
            print("  ⚠️ Vector dimension mismatch: got \(elementCount)d, expected 256/384/768/1024")
            return nil
        }

        return data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}

// MARK: - SemanticChunk Extension (for type access)

private extension HybridSearchEngine {
    // Uses SemanticChunk from SemanticSearchEngine.swift
}
