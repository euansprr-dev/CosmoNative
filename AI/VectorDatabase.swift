// CosmoOS/AI/VectorDatabase.swift
// HNSW vector database using sqlite-vec extension
// Optimized for Matryoshka 256d embeddings (3x storage efficiency)
// macOS 26+ optimized

import Foundation
import GRDB

// MARK: - Vector Configuration

public struct VectorConfig {
    public static let modelName = "nomic-embed-text-v1.5"
    public static let fullDimension = 768  // Native nomic dimension
    public static let matryoshkaDimension = 256  // Truncated for efficiency
    public static let maxBatchSize = 32
    public static let defaultSearchLimit = 20
    public static let similarityThreshold: Float = 0.5

    // HNSW parameters
    public static let hnswM = 16  // Max connections per layer
    public static let hnswEfConstruction = 200  // Construction quality
    public static let hnswEfSearch = 100  // Search quality
}

// MARK: - Vector Search Result

public struct VectorSearchResult: Identifiable, Sendable {
    public let id: Int64
    public let entityType: String
    public let entityId: Int64
    public let entityUUID: String?
    public let similarity: Float
    public let text: String?
    public let metadata: [String: String]?

    public var identifier: String {
        "\(entityType):\(entityId)"
    }
}

// MARK: - Vector Metadata

public struct VectorMetadata: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "vector_metadata"

    public let id: Int64?
    public let vectorId: Int64
    public let entityType: String
    public let entityId: Int64
    public let entityUUID: String?
    public let textHash: String?
    public let chunkIndex: Int
    public let createdAt: Date

    public init(
        id: Int64? = nil,
        vectorId: Int64,
        entityType: String,
        entityId: Int64,
        entityUUID: String?,
        textHash: String?,
        chunkIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.vectorId = vectorId
        self.entityType = entityType
        self.entityId = entityId
        self.entityUUID = entityUUID
        self.textHash = textHash
        self.chunkIndex = chunkIndex
        self.createdAt = createdAt
    }
}

// MARK: - Vector Database Actor

public actor VectorDatabase {
    // MARK: - Singleton

    public static let shared = VectorDatabase()

    // MARK: - Dependencies

    // Note: Access DaemonXPCClient.shared via MainActor.run when needed

    // MARK: - State

    private var dbPool: DatabasePool?
    private var isInitialized = false
    private var extensionLoaded = false

    // MARK: - Statistics

    private var totalVectors: Int64 = 0
    private var searchCount: Int = 0
    private var totalSearchTime: TimeInterval = 0

    // MARK: - Initialization

    private init() {}

    /// Initialize the vector database
    public func initialize(databasePath: String) async throws {
        guard !isInitialized else { return }

        // Create database pool
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        dbPool = try DatabasePool(path: databasePath, configuration: config)

        // Load sqlite-vec extension
        try await loadSqliteVecExtension()

        // Create tables
        try await createTables()

        // Get initial count
        totalVectors = await getVectorCount()

        isInitialized = true
        print("VectorDatabase: Initialized with \(totalVectors) vectors")
    }

    // MARK: - Extension Loading

    private func loadSqliteVecExtension() async throws {
        guard let pool = dbPool else {
            throw VectorDatabaseError.notInitialized
        }

        // CRITICAL: Use absolute bundle path for sqlite-vec.dylib
        // This avoids code signing issues with relative paths
        guard let dylibPath = Bundle.main.path(forResource: "sqlite-vec", ofType: "dylib") else {
            print("VectorDatabase: sqlite-vec.dylib not found in bundle, using brute-force fallback")
            extensionLoaded = false
            return
        }

        // Try to load extension using SQL PRAGMA (supported in some SQLite builds)
        // Note: This requires SQLite to be compiled with SQLITE_ENABLE_LOAD_EXTENSION
        // and the app to have appropriate entitlements
        do {
            try await pool.write { db in
                // Enable extension loading via PRAGMA (if supported)
                try db.execute(sql: "PRAGMA enable_load_extension = 1")

                // Load the extension
                try db.execute(sql: "SELECT load_extension(?)", arguments: [dylibPath])

                // Disable extension loading for security
                try db.execute(sql: "PRAGMA enable_load_extension = 0")
            }

            extensionLoaded = true
            print("VectorDatabase: sqlite-vec extension loaded from \(dylibPath)")
        } catch {
            // Extension loading failed - this is expected on most macOS builds
            // SQLite on macOS typically doesn't allow extension loading without special flags
            print("VectorDatabase: sqlite-vec extension loading failed (expected on macOS): \(error.localizedDescription)")
            print("VectorDatabase: Using brute-force vector search fallback")
            extensionLoaded = false
        }
    }

    // MARK: - Table Creation

    private func createTables() async throws {
        guard let pool = dbPool else {
            throw VectorDatabaseError.notInitialized
        }

        // Capture actor state before closure
        let hasExtension = extensionLoaded

        try await pool.write { db in
            if hasExtension {
                // Create HNSW-backed virtual table with sqlite-vec
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE IF NOT EXISTS vectors USING vec0(
                        id INTEGER PRIMARY KEY,
                        embedding float[\(VectorConfig.matryoshkaDimension)]
                    )
                """)
            } else {
                // Fallback: Regular table for vectors (slower but works without extension)
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS vectors (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        embedding BLOB NOT NULL
                    )
                """)

                // Create index for faster lookups
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_vectors_id ON vectors(id)
                """)
            }

            // Create metadata table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS vector_metadata (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    vector_id INTEGER NOT NULL,
                    entity_type TEXT NOT NULL,
                    entity_id INTEGER NOT NULL,
                    entity_uuid TEXT,
                    text_hash TEXT,
                    chunk_index INTEGER DEFAULT 0,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(entity_type, entity_id, chunk_index)
                )
            """)

            // Create indexes for fast lookups
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_vector_metadata_entity
                ON vector_metadata(entity_type, entity_id)
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_vector_metadata_vector
                ON vector_metadata(vector_id)
            """)

            // Create text content table for deduplication
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS vector_texts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    text_hash TEXT UNIQUE NOT NULL,
                    text_content TEXT NOT NULL,
                    vector_id INTEGER,
                    FOREIGN KEY (vector_id) REFERENCES vectors(id) ON DELETE SET NULL
                )
            """)
        }

        print("VectorDatabase: Tables created")
    }

    // MARK: - Embedding Operations

    /// Index a single text with its entity reference
    public func index(
        text: String,
        entityType: String,
        entityId: Int64,
        entityUUID: String? = nil,
        chunkIndex: Int = 0
    ) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // Check for duplicate
        let textHash = Self.hashText(text)
        if await isDuplicate(textHash: textHash, entityType: entityType, entityId: entityId, chunkIndex: chunkIndex) {
            return
        }

        // Get embedding from daemon
        let client = await MainActor.run { DaemonXPCClient.shared }
        let embedding = try await client.embed(text: text)

        // Truncate to Matryoshka dimension
        let truncatedEmbedding = Self.truncateToMatryoshka(embedding)

        // Store in database
        try await storeVector(
            embedding: truncatedEmbedding,
            entityType: entityType,
            entityId: entityId,
            entityUUID: entityUUID,
            textHash: textHash,
            chunkIndex: chunkIndex,
            text: text
        )

        totalVectors += 1
    }

    /// Batch index multiple texts
    public func indexBatch(
        items: [(text: String, entityType: String, entityId: Int64, entityUUID: String?)]
    ) async throws {
        // Filter out empty texts
        let validItems = items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !validItems.isEmpty else { return }

        // Get embeddings in batch
        let texts = validItems.map(\.text)
        let client = await MainActor.run { DaemonXPCClient.shared }
        let embeddings = try await client.embedBatch(texts: texts)

        guard embeddings.count == validItems.count else {
            throw VectorDatabaseError.embeddingCountMismatch
        }

        // Store all vectors
        for (index, item) in validItems.enumerated() {
            let truncatedEmbedding = Self.truncateToMatryoshka(embeddings[index])
            let textHash = Self.hashText(item.text)

            try await storeVector(
                embedding: truncatedEmbedding,
                entityType: item.entityType,
                entityId: item.entityId,
                entityUUID: item.entityUUID,
                textHash: textHash,
                chunkIndex: 0,
                text: item.text
            )
        }

        totalVectors += Int64(validItems.count)
        print("VectorDatabase: Indexed \(validItems.count) vectors")
    }

    // MARK: - Search Operations

    /// Search for similar vectors by text query
    public func search(
        query: String,
        limit: Int = VectorConfig.defaultSearchLimit,
        entityTypeFilter: String? = nil,
        minSimilarity: Float = VectorConfig.similarityThreshold
    ) async throws -> [VectorSearchResult] {
        let startTime = Date()

        // Get query embedding
        let client = await MainActor.run { DaemonXPCClient.shared }
        let queryEmbedding = try await client.embed(text: query)
        let truncatedQuery = Self.truncateToMatryoshka(queryEmbedding)

        // Perform vector search
        let results = try await searchByVector(
            embedding: truncatedQuery,
            limit: limit,
            entityTypeFilter: entityTypeFilter,
            minSimilarity: minSimilarity
        )

        // Update statistics
        searchCount += 1
        totalSearchTime += Date().timeIntervalSince(startTime)

        return results
    }

    /// Search by pre-computed embedding
    public func searchByVector(
        embedding: [Float],
        limit: Int = VectorConfig.defaultSearchLimit,
        entityTypeFilter: String? = nil,
        minSimilarity: Float = VectorConfig.similarityThreshold
    ) async throws -> [VectorSearchResult] {
        guard let pool = dbPool else {
            throw VectorDatabaseError.notInitialized
        }

        let startTime = Date()

        // Capture actor state before closure
        let hasExtension = extensionLoaded

        let results: [VectorSearchResult]

        if hasExtension {
            // Use sqlite-vec HNSW search
            results = try await pool.read { db in
                try Self.hnswSearch(
                    db: db,
                    embedding: embedding,
                    limit: limit,
                    entityTypeFilter: entityTypeFilter,
                    minSimilarity: minSimilarity
                )
            }
        } else {
            // Fallback to brute-force cosine similarity
            results = try await pool.read { db in
                try Self.bruteForceSearch(
                    db: db,
                    embedding: embedding,
                    limit: limit,
                    entityTypeFilter: entityTypeFilter,
                    minSimilarity: minSimilarity
                )
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        print("VectorDatabase: Search completed in \(String(format: "%.1f", duration * 1000))ms (\(results.count) results)")

        return results
    }

    private nonisolated static func hnswSearch(
        db: Database,
        embedding: [Float],
        limit: Int,
        entityTypeFilter: String?,
        minSimilarity: Float
    ) throws -> [VectorSearchResult] {
        // Convert embedding to blob for query
        let embeddingBlob = embeddingToBlob(embedding)

        // Build query with optional filter
        var sql = """
            SELECT v.rowid, v.distance, m.entity_type, m.entity_id, m.entity_uuid, t.text_content
            FROM vectors v
            JOIN vector_metadata m ON m.vector_id = v.rowid
            LEFT JOIN vector_texts t ON t.vector_id = v.rowid
            WHERE v.embedding MATCH ?
        """

        var arguments: [DatabaseValueConvertible] = [embeddingBlob]

        if let filter = entityTypeFilter {
            sql += " AND m.entity_type = ?"
            arguments.append(filter)
        }

        sql += """
            ORDER BY v.distance
            LIMIT ?
        """
        arguments.append(limit)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

        return rows.compactMap { row -> VectorSearchResult? in
            guard let vectorId = row["rowid"] as? Int64,
                  let distance = row["distance"] as? Double,
                  let entityType = row["entity_type"] as? String,
                  let entityId = row["entity_id"] as? Int64 else {
                return nil
            }

            // Convert distance to similarity (sqlite-vec uses L2 distance)
            let similarity = Float(1.0 / (1.0 + distance))

            guard similarity >= minSimilarity else { return nil }

            return VectorSearchResult(
                id: vectorId,
                entityType: entityType,
                entityId: entityId,
                entityUUID: row["entity_uuid"] as? String,
                similarity: similarity,
                text: row["text_content"] as? String,
                metadata: nil
            )
        }
    }

    private nonisolated static func bruteForceSearch(
        db: Database,
        embedding: [Float],
        limit: Int,
        entityTypeFilter: String?,
        minSimilarity: Float
    ) throws -> [VectorSearchResult] {
        // Fallback: Load all vectors and compute similarity in-memory
        var sql = """
            SELECT v.id, v.embedding, m.entity_type, m.entity_id, m.entity_uuid, t.text_content
            FROM vectors v
            JOIN vector_metadata m ON m.vector_id = v.id
            LEFT JOIN vector_texts t ON t.vector_id = v.id
        """

        if let filter = entityTypeFilter {
            sql += " WHERE m.entity_type = '\(filter)'"
        }

        let rows = try Row.fetchAll(db, sql: sql)

        var results: [(VectorSearchResult, Float)] = []

        for row in rows {
            guard let vectorId = row["id"] as? Int64,
                  let embeddingBlob = row["embedding"] as? Data,
                  let entityType = row["entity_type"] as? String,
                  let entityId = row["entity_id"] as? Int64 else {
                continue
            }

            let storedEmbedding = blobToEmbedding(embeddingBlob)
            let similarity = cosineSimilarity(embedding, storedEmbedding)

            guard similarity >= minSimilarity else { continue }

            let result = VectorSearchResult(
                id: vectorId,
                entityType: entityType,
                entityId: entityId,
                entityUUID: row["entity_uuid"] as? String,
                similarity: similarity,
                text: row["text_content"] as? String,
                metadata: nil
            )

            results.append((result, similarity))
        }

        // Sort by similarity and limit
        return results
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Delete Operations

    /// Delete vectors for an entity
    public func deleteEntity(entityType: String, entityId: Int64) async throws {
        guard let pool = dbPool else {
            throw VectorDatabaseError.notInitialized
        }

        try await pool.write { db in
            // Get vector IDs first
            let vectorIds = try Int64.fetchAll(db, sql: """
                SELECT vector_id FROM vector_metadata
                WHERE entity_type = ? AND entity_id = ?
            """, arguments: [entityType, entityId])

            // Delete from vectors table
            for vectorId in vectorIds {
                try db.execute(sql: "DELETE FROM vectors WHERE id = ?", arguments: [vectorId])
            }

            // Delete metadata
            try db.execute(sql: """
                DELETE FROM vector_metadata
                WHERE entity_type = ? AND entity_id = ?
            """, arguments: [entityType, entityId])

            // Delete text content
            for vectorId in vectorIds {
                try db.execute(sql: "DELETE FROM vector_texts WHERE vector_id = ?", arguments: [vectorId])
            }
        }

        let count = await getVectorCount()
        totalVectors = count

        print("VectorDatabase: Deleted vectors for \(entityType):\(entityId)")
    }

    /// Clear all vectors
    public func clearAll() async throws {
        guard let pool = dbPool else {
            throw VectorDatabaseError.notInitialized
        }

        try await pool.write { db in
            try db.execute(sql: "DELETE FROM vector_texts")
            try db.execute(sql: "DELETE FROM vector_metadata")
            try db.execute(sql: "DELETE FROM vectors")
        }

        totalVectors = 0
        print("VectorDatabase: All vectors cleared")
    }

    // MARK: - Statistics

    public func getVectorCount() async -> Int64 {
        guard let pool = dbPool else { return 0 }

        return (try? await pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM vectors") ?? 0
        }) ?? 0
    }

    public func getStatistics() async -> VectorDatabaseStatistics {
        let count = await getVectorCount()
        let avgSearchTime = searchCount > 0 ? totalSearchTime / Double(searchCount) : 0

        return VectorDatabaseStatistics(
            totalVectors: count,
            searchCount: searchCount,
            averageSearchTimeMs: avgSearchTime * 1000,
            extensionLoaded: extensionLoaded,
            dimension: VectorConfig.matryoshkaDimension
        )
    }

    // MARK: - Private Helpers

    private func storeVector(
        embedding: [Float],
        entityType: String,
        entityId: Int64,
        entityUUID: String?,
        textHash: String,
        chunkIndex: Int,
        text: String
    ) async throws {
        guard let pool = dbPool else {
            throw VectorDatabaseError.notInitialized
        }

        // Capture actor state before closure
        let hasExtension = extensionLoaded

        try await pool.write { db in
            // Insert vector
            let embeddingBlob = Self.embeddingToBlob(embedding)

            if hasExtension {
                try db.execute(sql: """
                    INSERT INTO vectors (embedding) VALUES (?)
                """, arguments: [embeddingBlob])
            } else {
                try db.execute(sql: """
                    INSERT INTO vectors (embedding) VALUES (?)
                """, arguments: [embeddingBlob])
            }

            let vectorId = db.lastInsertedRowID

            // Insert metadata
            try db.execute(sql: """
                INSERT OR REPLACE INTO vector_metadata
                (vector_id, entity_type, entity_id, entity_uuid, text_hash, chunk_index, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                vectorId, entityType, entityId, entityUUID, textHash, chunkIndex, Date()
            ])

            // Insert text content
            try db.execute(sql: """
                INSERT OR REPLACE INTO vector_texts (text_hash, text_content, vector_id)
                VALUES (?, ?, ?)
            """, arguments: [textHash, text, vectorId])
        }
    }

    private func isDuplicate(textHash: String, entityType: String, entityId: Int64, chunkIndex: Int) async -> Bool {
        guard let pool = dbPool else { return false }

        return (try? await pool.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM vector_metadata
                WHERE entity_type = ? AND entity_id = ? AND chunk_index = ? AND text_hash = ?
            """, arguments: [entityType, entityId, chunkIndex, textHash]) ?? 0
            return count > 0
        }) ?? false
    }

    private nonisolated static func truncateToMatryoshka(_ embedding: [Float]) -> [Float] {
        // Matryoshka: Simply take first N dimensions
        Array(embedding.prefix(VectorConfig.matryoshkaDimension))
    }

    private nonisolated static func embeddingToBlob(_ embedding: [Float]) -> Data {
        var mutableEmbedding = embedding
        return Data(bytes: &mutableEmbedding, count: embedding.count * MemoryLayout<Float>.size)
    }

    private nonisolated static func blobToEmbedding(_ blob: Data) -> [Float] {
        blob.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    private nonisolated static func hashText(_ text: String) -> String {
        // Simple hash for deduplication
        let data = text.data(using: .utf8) ?? Data()
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
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
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}

// MARK: - Statistics

public struct VectorDatabaseStatistics: Sendable {
    public let totalVectors: Int64
    public let searchCount: Int
    public let averageSearchTimeMs: Double
    public let extensionLoaded: Bool
    public let dimension: Int
}

// MARK: - Errors

public enum VectorDatabaseError: LocalizedError {
    case notInitialized
    case extensionLoadFailed(String)
    case embeddingCountMismatch
    case searchFailed(String)
    case indexFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Vector database not initialized"
        case .extensionLoadFailed(let message):
            return "Failed to load sqlite-vec: \(message)"
        case .embeddingCountMismatch:
            return "Embedding count doesn't match input count"
        case .searchFailed(let message):
            return "Vector search failed: \(message)"
        case .indexFailed(let message):
            return "Vector indexing failed: \(message)"
        }
    }
}
