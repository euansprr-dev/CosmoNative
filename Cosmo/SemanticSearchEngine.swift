// CosmoOS/Cosmo/SemanticSearchEngine.swift
// Local-first semantic search with vector embeddings via CosmoVoiceDaemon
// Uses nomic-embed-text-v1.5 (Matryoshka 256d) for instant local embeddings

import Foundation
import Accelerate
import GRDB

@MainActor
class SemanticSearchEngine: ObservableObject {
    static let shared = SemanticSearchEngine()

    @Published var isIndexing = false
    @Published var indexProgress: Double = 0
    @Published var totalChunks: Int = 0
    @Published var isDaemonReady = false

    private let database = CosmoDatabase.shared
    private let daemon = DaemonXPCClient.shared
    private var embeddingCache: [String: [Float]] = [:]

    // Embedding dimension for nomic-embed-text-v1.5 (Matryoshka 256d)
    // Falls back to 384-dim if using legacy n-gram embeddings
    private let daemonEmbeddingDimension = 256
    private var embeddingDimension: Int {
        isDaemonReady ? daemonEmbeddingDimension : 384
    }

    private init() {
        // Check daemon connectivity in background
        Task {
            await initializeDaemon()
        }
    }

    // MARK: - Daemon Initialization

    /// Initialize daemon connection for high-quality semantic search
    func initializeDaemon() async {
        let ready = await daemon.waitForReady(timeout: .seconds(5))
        isDaemonReady = ready

        if ready {
            print("✅ SemanticSearchEngine: Daemon embeddings ready (256-dim nomic)")
        } else {
            print("⚠️ SemanticSearchEngine: Daemon unavailable, using fallback embeddings")
            print("   Ensure CosmoVoiceDaemon is running")
        }
    }

    // MARK: - Semantic Search
    func search(
        query: String,
        limit: Int = 10,
        minSimilarity: Float = 0.5,
        entityTypes: [EntityType]? = nil
    ) async throws -> [SemanticSearchResult] {
        // Generate query embedding
        let queryVector = await generateEmbedding(for: query)

        guard !queryVector.isEmpty else {
            print("❌ Failed to generate query embedding")
            return []
        }

        // Fetch all chunks from database
        let chunks = try await database.asyncRead { db in
            try SemanticChunk
                .order(Column("created_at").desc)
                .fetchAll(db)
        }

        // Compute similarities
        var results: [SemanticSearchResult] = []
        var skippedDimensionMismatch = 0

        for chunk in chunks {
            guard let vectorData = chunk.vector,
                  let chunkVector = decodeVector(vectorData) else {
                continue
            }

            // Skip chunks with incompatible dimensions
            // This handles legacy 384-dim vectors when using 1024-dim Qwen3
            if !vectorsCompatible(queryVector, chunkVector) {
                skippedDimensionMismatch += 1
                continue
            }

            // Filter by entity type if specified
            if let types = entityTypes {
                let chunkType = EntityType(rawValue: chunk.entityType) ?? .idea
                if !types.contains(chunkType) {
                    continue
                }
            }

            let similarity = cosineSimilarity(queryVector, chunkVector)

            if similarity >= minSimilarity {
                let result = SemanticSearchResult(
                    entityType: EntityType(rawValue: chunk.entityType) ?? .idea,
                    entityId: chunk.entityId,
                    title: chunk.fieldName ?? "Untitled",
                    preview: String(chunk.text.prefix(200)),
                    similarity: similarity,
                    fieldName: chunk.fieldName,
                    chunkIndex: chunk.chunkIndex
                )
                results.append(result)
            }
        }

        // Log if many chunks were skipped due to dimension mismatch
        if skippedDimensionMismatch > 0 {
            print("⚠️ Skipped \(skippedDimensionMismatch) chunks due to dimension mismatch. Consider re-indexing.")
        }

        // Sort by similarity descending
        results.sort { $0.similarity > $1.similarity }

        // Deduplicate by entity (keep highest similarity per entity)
        var seen: Set<String> = []
        var deduplicated: [SemanticSearchResult] = []

        for result in results {
            let key = "\(result.entityType.rawValue)-\(result.entityId)"
            if !seen.contains(key) {
                seen.insert(key)
                deduplicated.append(result)
            }
        }

        // Enrich with entity titles
        let enriched = await enrichResults(deduplicated)

        return Array(enriched.prefix(limit))
    }

    // MARK: - Index All Entities
    func indexAllEntities() async {
        isIndexing = true
        indexProgress = 0

        defer {
            isIndexing = false
            indexProgress = 0
        }

        print("📊 Starting full semantic index...")

        do {
            // Index ideas
            let ideas = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
                    .map { IdeaWrapper(atom: $0) }
            }

            for (index, idea) in ideas.enumerated() {
                await indexIdea(idea)
                indexProgress = Double(index + 1) / Double(ideas.count) * 0.33
            }

            // Index content
            let content = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
                    .map { ContentWrapper(atom: $0) }
            }

            for (index, item) in content.enumerated() {
                await indexContent(item)
                indexProgress = 0.33 + Double(index + 1) / Double(content.count) * 0.33
            }

            // Index research
            let research = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.research.rawValue)
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
                    .map { ResearchWrapper(atom: $0) }
            }

            for (index, item) in research.enumerated() {
                await indexResearch(item)
                indexProgress = 0.66 + Double(index + 1) / Double(research.count) * 0.34
            }

            // Update total count
            totalChunks = try await database.asyncRead { db in
                try SemanticChunk.fetchCount(db)
            }

            print("✅ Indexed \(totalChunks) semantic chunks")

        } catch {
            print("❌ Indexing failed: \(error)")
        }
    }

    // MARK: - Index Individual Entities
    func indexIdea(_ idea: Idea) async {
        guard let id = idea.id else { return }

        let text = [idea.title, idea.content]
            .compactMap { $0 }
            .joined(separator: "\n")

        guard !text.isEmpty else { return }

        let vector = await generateEmbedding(for: text)
        await saveChunk(
            entityType: "idea",
            entityId: id,
            fieldName: idea.title,
            text: text,
            vector: vector
        )
    }

    func indexContent(_ content: ContentWrapper) async {
        guard let id = content.id else { return }

        let text = [content.title, content.body]
            .compactMap { $0 }
            .joined(separator: "\n")

        guard !text.isEmpty else { return }

        let vector = await generateEmbedding(for: text)
        await saveChunk(
            entityType: "content",
            entityId: id,
            fieldName: content.title,
            text: text,
            vector: vector
        )
    }

    func indexResearch(_ research: Research) async {
        guard let id = research.id else { return }

        // For YouTube, `research.content` is JSON transcript. Index readable text instead.
        let contentText: String? = {
            if research.sourceType == .youtube, let segments = research.transcriptSegments {
                return segments.fullText
            }
            return research.content
        }()

        let text = [research.title, research.summary, contentText, research.personalNotes]
            .compactMap { $0 }
            .joined(separator: "\n")

        guard !text.isEmpty else { return }

        let vector = await generateEmbedding(for: text)
        await saveChunk(
            entityType: "research",
            entityId: id,
            fieldName: research.title,
            text: text,
            vector: vector
        )
    }

    // MARK: - Embedding Generation

    /// Generate embedding using CosmoVoiceDaemon (nomic) or fallback to n-gram hashing
    private func generateEmbedding(for text: String) async -> [Float] {
        // Check cache first
        let cacheKey = String(text.prefix(200))
        if let cached = embeddingCache[cacheKey] {
            return cached
        }

        // Try daemon embedding service (high-quality semantic embeddings via nomic)
        if isDaemonReady {
            do {
                let embedding = try await daemon.embed(text: text)
                embeddingCache[cacheKey] = embedding
                return embedding
            } catch {
                print("⚠️ Daemon embedding failed, using fallback: \(error.localizedDescription)")
            }
        }

        // Fallback to simple n-gram hashing (degraded quality)
        let embedding = generateFallbackEmbedding(text: text)
        embeddingCache[cacheKey] = embedding
        return embedding
    }

    /// Batch embedding generation for indexing (much faster)
    private func generateEmbeddings(for texts: [String]) async -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        if isDaemonReady {
            do {
                return try await daemon.embedBatch(texts: texts)
            } catch {
                print("⚠️ Daemon batch embedding failed, using fallback: \(error.localizedDescription)")
            }
        }

        // Fallback: generate individually
        return texts.map { generateFallbackEmbedding(text: $0) }
    }

    /// Fallback embedding using n-gram hashing (when daemon unavailable)
    /// Quality is significantly degraded - semantic understanding is minimal
    private func generateFallbackEmbedding(text: String) -> [Float] {
        let dimension = 384  // Fallback uses smaller dimension

        var embedding = [Float](repeating: 0, count: dimension)

        let normalized = text.lowercased()
        let words = normalized.components(separatedBy: .whitespacesAndNewlines)

        for word in words {
            // Hash word to embedding dimension
            let hash = word.hashValue
            let index = abs(hash) % dimension
            embedding[index] += 1.0

            // Add bigram features
            if word.count >= 2 {
                for i in 0..<(word.count - 1) {
                    let start = word.index(word.startIndex, offsetBy: i)
                    let end = word.index(start, offsetBy: 2)
                    let bigram = String(word[start..<end])
                    let bigramIndex = abs(bigram.hashValue) % dimension
                    embedding[bigramIndex] += 0.5
                }
            }
        }

        // L2 normalize
        var norm: Float = 0
        vDSP_dotpr(embedding, 1, embedding, 1, &norm, vDSP_Length(dimension))
        norm = sqrt(norm)

        if norm > 0 {
            var scale = 1.0 / norm
            vDSP_vsmul(embedding, 1, &scale, &embedding, 1, vDSP_Length(dimension))
        }

        return embedding
    }

    // MARK: - Cosine Similarity
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

    // MARK: - Vector Encoding/Decoding

    private func encodeVector(_ vector: [Float]) -> Data {
        return vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Decode vector from database, handling 256-dim (daemon/nomic), 384-dim (legacy), etc.
    private func decodeVector(_ data: Data) -> [Float]? {
        let floatSize = MemoryLayout<Float>.size
        let elementCount = data.count / floatSize

        // Accept 256-dim (daemon nomic), 384-dim (legacy fallback), 768-dim, or 1024-dim (legacy Qwen3)
        guard [256, 384, 768, 1024].contains(elementCount) else {
            print("⚠️ Unknown vector dimension: \(elementCount)")
            return nil
        }

        return data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }

    /// Check if vectors are compatible for comparison
    private func vectorsCompatible(_ a: [Float], _ b: [Float]) -> Bool {
        return a.count == b.count
    }

    // MARK: - Database Operations
    private func saveChunk(
        entityType: String,
        entityId: Int64,
        fieldName: String?,
        text: String,
        vector: [Float],
        chunkIndex: Int = 0
    ) async {
        let textHash = text.hashValue
        let vectorData = encodeVector(vector)

        do {
            try await database.asyncWrite { db in
                // Check if chunk already exists
                let existing = try SemanticChunk
                    .filter(Column("entity_type") == entityType)
                    .filter(Column("entity_id") == entityId)
                    .filter(Column("chunk_index") == chunkIndex)
                    .fetchOne(db)

                if var chunk = existing {
                    // Update
                    chunk.text = text
                    chunk.textHash = String(textHash)
                    chunk.vector = vectorData
                    chunk.updatedAt = ISO8601DateFormatter().string(from: Date())
                    try chunk.update(db)
                } else {
                    // Insert
                    let chunk = SemanticChunk(
                        id: nil,
                        entityType: entityType,
                        entityId: entityId,
                        fieldName: fieldName,
                        chunkIndex: chunkIndex,
                        startTime: nil,
                        endTime: nil,
                        text: text,
                        textHash: String(textHash),
                        vector: vectorData,
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        updatedAt: ISO8601DateFormatter().string(from: Date())
                    )
                    try chunk.insert(db)
                }
            }
        } catch {
            print("❌ Failed to save chunk: \(error)")
        }
    }

    // MARK: - Enrich Results
    private func enrichResults(_ results: [SemanticSearchResult]) async -> [SemanticSearchResult] {
        var enriched: [SemanticSearchResult] = []

        for result in results {
            var enrichedResult = result
            switch result.entityType {
            case .idea:
                if let idea = try? await database.asyncRead({ db in
                    try Atom
                        .filter(Column("type") == AtomType.idea.rawValue)
                        .filter(Column("id") == result.entityId)
                        .fetchOne(db)
                        .map { IdeaWrapper(atom: $0) }
                }) {
                    enrichedResult.title = idea.title ?? "Untitled Idea"
                    enrichedResult.preview = String(idea.content.prefix(200))
                }

            case .content:
                if let content = try? await database.asyncRead({ db in
                    try Atom
                        .filter(Column("type") == AtomType.content.rawValue)
                        .filter(Column("id") == result.entityId)
                        .fetchOne(db)
                        .map { ContentWrapper(atom: $0) }
                }) {
                    enrichedResult.title = content.title ?? "Untitled"
                    enrichedResult.preview = String((content.body ?? "").prefix(200))
                }

            case .research:
                if let research = try? await database.asyncRead({ db in
                    try Atom
                        .filter(Column("type") == AtomType.research.rawValue)
                        .filter(Column("id") == result.entityId)
                        .fetchOne(db)
                        .map { ResearchWrapper(atom: $0) }
                }) {
                    enrichedResult.title = research.title ?? "Untitled"
                    enrichedResult.preview = research.summary ?? String(research.content.prefix(200))
                }

            default:
                break
            }

            enriched.append(enrichedResult)
        }

        return enriched
    }
}

// MARK: - Semantic Search Result
struct SemanticSearchResult: Identifiable {
    let id = UUID()
    var entityType: EntityType
    var entityId: Int64
    var title: String
    var preview: String?
    var similarity: Float
    var fieldName: String?
    var chunkIndex: Int
}

// MARK: - SemanticChunk Model
struct SemanticChunk: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "semantic_chunks"

    var id: Int64?
    var entityType: String
    var entityId: Int64
    var fieldName: String?
    var chunkIndex: Int
    var startTime: Double?
    var endTime: Double?
    var text: String
    var textHash: String
    var vector: Data?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case entityId = "entity_id"
        case fieldName = "field_name"
        case chunkIndex = "chunk_index"
        case startTime = "start_time"
        case endTime = "end_time"
        case text
        case textHash = "text_hash"
        case vector
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
