// CosmoOS/Cosmo/HybridSearchEngine.swift
// Hybrid BM25 + Vector Search for Telepathic Voice Assistant
// Combines fast keyword search with semantic understanding

import Foundation
import Accelerate
import GRDB

/// Hybrid search engine combining BM25 keyword search with MLX vector similarity
/// Achieves both speed (BM25 pre-filter) and semantic understanding (vector re-ranking)
@MainActor
final class HybridSearchEngine: ObservableObject {
    static let shared = HybridSearchEngine()

    // MARK: - Dependencies

    private let database = CosmoDatabase.shared
    private let mlxService = MLXEmbeddingService.shared
    private let semanticEngine = SemanticSearchEngine.shared

    // MARK: - Configuration

    /// Default hybrid weight: 0.7 = 70% vector, 30% BM25
    let defaultHybridWeight: Double = 0.7

    /// Maximum candidates from BM25 pre-filter
    let maxBM25Candidates = 100

    /// Minimum similarity threshold for results
    let minSimilarity: Float = 0.3

    private init() {}

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
        entityTypes: [EntityType]? = nil
    ) async throws -> [SearchResult] {
        let weight = hybridWeight ?? defaultHybridWeight

        print("🔍 Hybrid search: \"\(query)\" (weight: \(Int(weight * 100))% vector)")

        // Stage 1: BM25 pre-filter for fast candidate retrieval
        let bm25Candidates = try await bm25Search(
            query: query,
            limit: maxBM25Candidates,
            entityTypes: entityTypes
        )

        print("  📋 BM25 candidates: \(bm25Candidates.count)")

        guard !bm25Candidates.isEmpty else {
            // No keyword matches - fall back to pure vector search
            return try await pureVectorSearch(
                query: query,
                limit: limit,
                entityTypes: entityTypes
            )
        }

        // Stage 2: Generate query embedding for vector similarity
        let queryVector: [Float]
        do {
            queryVector = try await mlxService.embed(query)
        } catch {
            print("  ⚠️ MLX embedding failed, using BM25 only: \(error.localizedDescription)")
            return bm25Candidates.prefix(limit).map { candidate in
                SearchResult(
                    entityType: EntityType(rawValue: candidate.entityType) ?? .idea,
                    entityId: candidate.entityId,
                    entityUUID: nil,
                    title: candidate.title,
                    preview: String(candidate.content.prefix(200)),
                    bm25Score: candidate.bm25Score,
                    vectorSimilarity: 0,
                    combinedScore: candidate.bm25Score,
                    matchReason: .keywordMatch
                )
            }
        }

        // Stage 3: Compute vector similarity and combine scores
        var scoredResults: [SearchResult] = []

        for candidate in bm25Candidates {
            // Get vector for this candidate
            let vectorSimilarity = await getVectorSimilarity(
                entityType: candidate.entityType,
                entityId: candidate.entityId,
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

            let result = SearchResult(
                entityType: EntityType(rawValue: candidate.entityType) ?? .idea,
                entityId: candidate.entityId,
                entityUUID: nil,
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
        }

        // Sort by combined score and return top results
        scoredResults.sort { $0.combinedScore > $1.combinedScore }

        print("  ✅ Returning \(min(limit, scoredResults.count)) results")

        return Array(scoredResults.prefix(limit))
    }

    // MARK: - Context-Aware Search

    /// Search for content related to what the user is currently editing
    /// Uses the editing context vector for pure semantic search
    func searchRelatedToContext(
        context: VoiceContextSnapshot,
        limit: Int = 5,
        entityTypes: [EntityType]? = nil
    ) async throws -> [SearchResult] {
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
            excludeEntity: (excludeType, excludeId)
        )
    }

    // MARK: - BM25 Search (FTS5)

    /// Fast keyword search using SQLite FTS5 with BM25 ranking
    private func bm25Search(
        query: String,
        limit: Int,
        entityTypes: [EntityType]?
    ) async throws -> [BM25Candidate] {
        // Escape special FTS5 characters and prepare query
        let escapedQuery = prepareFTS5Query(query)

        return try await database.asyncRead { db in
            var sql = """
                SELECT entity_type, entity_id, title, content,
                       bm25(semantic_fts, 1, 2, 3) AS score
                FROM semantic_fts
                WHERE semantic_fts MATCH ?
            """

            var arguments: [DatabaseValueConvertible] = [escapedQuery]

            // Filter by entity types if specified
            if let types = entityTypes, !types.isEmpty {
                let placeholders = types.map { _ in "?" }.joined(separator: ", ")
                sql += " AND entity_type IN (\(placeholders))"
                arguments += types.map { $0.rawValue }
            }

            sql += " ORDER BY score LIMIT ?"
            arguments.append(limit)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

            return rows.map { row in
                BM25Candidate(
                    entityType: row["entity_type"] as? String ?? "idea",
                    entityId: row["entity_id"] as? Int64 ?? 0,
                    title: row["title"] as? String ?? "",
                    content: row["content"] as? String ?? "",
                    bm25Score: -(row["score"] as? Double ?? 0)  // BM25 returns negative scores
                )
            }
        }
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
        entityTypes: [EntityType]?
    ) async throws -> [SearchResult] {
        let queryVector = try await mlxService.embed(query)
        return try await pureVectorSearch(
            queryVector: queryVector,
            limit: limit,
            entityTypes: entityTypes,
            excludeEntity: (nil, nil)
        )
    }

    /// Pure vector search with pre-computed query vector
    private func pureVectorSearch(
        queryVector: [Float],
        limit: Int,
        entityTypes: [EntityType]?,
        excludeEntity: (EntityType?, Int64?)
    ) async throws -> [SearchResult] {
        // Fetch all semantic chunks
        let chunks = try await database.asyncRead { db in
            try SemanticChunk
                .order(Column("created_at").desc)
                .fetchAll(db)
        }

        var results: [(entityType: String, entityId: Int64, title: String, text: String, similarity: Float)] = []

        for chunk in chunks {
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

            guard let vectorData = chunk.vector else { continue }
            let chunkVector = decodeVector(vectorData)

            // Skip incompatible dimensions
            guard let chunkVec = chunkVector, chunkVec.count == queryVector.count else {
                continue
            }

            let similarity = cosineSimilarity(queryVector, chunkVec)

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
        return Array(deduplicated.prefix(limit)).map { result in
            SearchResult(
                entityType: EntityType(rawValue: result.entityType) ?? .idea,
                entityId: result.entityId,
                entityUUID: nil,
                title: result.title,
                preview: String(result.text.prefix(200)),
                bm25Score: 0,
                vectorSimilarity: Double(result.similarity),
                combinedScore: Double(result.similarity),
                matchReason: .semanticSimilarity
            )
        }
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
                guard let vectorData = chunk.vector,
                      let chunkVector = decodeVector(vectorData),
                      chunkVector.count == queryVector.count else {
                    continue
                }

                let similarity = cosineSimilarity(queryVector, chunkVector)
                maxSimilarity = max(maxSimilarity, similarity)
            }

            return maxSimilarity

        } catch {
            return 0
        }
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

        return results.map { result in
            var boostedResult = result

            // Check similarity to context vector
            Task {
                let contextSimilarity = await getVectorSimilarity(
                    entityType: result.entityType.rawValue,
                    entityId: result.entityId,
                    queryVector: contextVector
                )

                // Boost score if similar to editing context
                if contextSimilarity > 0.5 {
                    let boost = Double(contextSimilarity) * 0.2  // Up to 20% boost
                    boostedResult = SearchResult(
                        entityType: result.entityType,
                        entityId: result.entityId,
                        entityUUID: result.entityUUID,
                        title: result.title,
                        preview: result.preview,
                        bm25Score: result.bm25Score,
                        vectorSimilarity: result.vectorSimilarity,
                        combinedScore: result.combinedScore + boost,
                        matchReason: .contextRelevant
                    )
                }
            }

            return boostedResult
        }
    }

    // MARK: - Vector Utilities

    private func decodeVector(_ data: Data) -> [Float]? {
        let floatSize = MemoryLayout<Float>.size
        let elementCount = data.count / floatSize

        guard [384, 768, 1024].contains(elementCount) else {
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
