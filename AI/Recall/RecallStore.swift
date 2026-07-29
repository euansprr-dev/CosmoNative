// CosmoOS/AI/Recall/RecallStore.swift
// Vector storage + search for the Recall foundation. Vectors live in a plain
// GRDB table (normalized float blobs) with an in-memory matrix cache; search
// is an Accelerate dot-product sweep. At personal scale (tens of thousands of
// chunks) this is a few milliseconds — no native extension, no HNSW, no dylib
// that never loads (the old sqlite-vec path failed on every launch).
// July 2026

import Foundation
import GRDB
import Accelerate

// MARK: - Stored Row

struct RecallVectorRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recall_vectors"

    var id: Int64?
    var entityUuid: String
    var entityType: String
    var chunkIndex: Int
    var docHash: String
    var model: String
    var page: Int?
    var text: String
    var embedding: Data
    var updatedAt: String
    /// `SwipeUnitRole.rawValue` for chunks that ARE a swipe's artifact unit.
    /// Nullable: every vector written before the reference layer stays valid.
    var role: String?

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case entityUuid = "entity_uuid"
        case entityType = "entity_type"
        case chunkIndex = "chunk_index"
        case docHash = "doc_hash"
        case model
        case page
        case text
        case embedding
        case updatedAt = "updated_at"
        case role
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Search Hit

struct RecallVectorHit: Sendable {
    let entityUuid: String
    let entityType: String
    let chunkIndex: Int
    let page: Int?
    let text: String
    let similarity: Float
    let role: String?
}

// MARK: - Store

actor RecallStore {
    static let shared = RecallStore()

    private struct CachedVector {
        let entityUuid: String
        let entityType: String
        let chunkIndex: Int
        let page: Int?
        let text: String
        let embedding: [Float]
        let role: String?
    }

    private var cache: [CachedVector]?

    // MARK: - Writes

    /// Replace all chunks for an atom in one transaction (delete + insert).
    func replaceChunks(
        entityUuid: String,
        entityType: String,
        docHash: String,
        model: String,
        chunks: [RecallChunk],
        embeddings: [[Float]]
    ) async throws {
        guard chunks.count == embeddings.count else { return }
        let now = ISO8601.string(from: Date())
        let rows = zip(chunks, embeddings).map { chunk, vector in
            RecallVectorRow(
                id: nil,
                entityUuid: entityUuid,
                entityType: entityType,
                chunkIndex: chunk.index,
                docHash: docHash,
                model: model,
                page: chunk.page,
                text: chunk.text,
                embedding: Self.blob(from: vector),
                updatedAt: now,
                role: chunk.role
            )
        }
        try await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(
                sql: "DELETE FROM recall_vectors WHERE entity_uuid = ?",
                arguments: [entityUuid]
            )
            for var row in rows {
                try row.insert(db)
            }
        }
        cache = nil
    }

    /// Tombstone cascade: an atom's vectors die with it.
    func removeEntity(_ entityUuid: String) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(
                sql: "DELETE FROM recall_vectors WHERE entity_uuid = ?",
                arguments: [entityUuid]
            )
        }
        cache = nil
    }

    func invalidateCache() {
        cache = nil
    }

    // MARK: - Reads

    /// entity_uuid → doc_hash for freshness checks (backfill, save hook).
    func indexedHashes() async -> [String: String] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT DISTINCT entity_uuid, doc_hash FROM recall_vectors"
            )
            var out: [String: String] = [:]
            for row in rows {
                if let uuid: String = row["entity_uuid"], let hash: String = row["doc_hash"] {
                    out[uuid] = hash
                }
            }
            return out
        }) ?? [:]
    }

    func stats() async -> (vectors: Int, atoms: Int) {
        (try? await CosmoDatabase.shared.asyncRead { db in
            let vectors = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recall_vectors") ?? 0
            let atoms = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT entity_uuid) FROM recall_vectors") ?? 0
            return (vectors, atoms)
        }) ?? (0, 0)
    }

    // MARK: - Search

    /// Cosine sweep over the cached matrix (vectors stored normalized, so
    /// similarity = dot product). Optional type filter narrows the sweep.
    ///
    /// `roles` narrows to chunks that ARE artifact units of those roles —
    /// "show me guarantee sections" is a role filter plus a semantic sweep,
    /// not a text search for the word "guarantee".
    func search(
        embedding query: [Float],
        limit: Int,
        entityTypes: Set<String>? = nil,
        minSimilarity: Float = 0,
        roles: Set<String>? = nil
    ) async -> [RecallVectorHit] {
        let vectors = await loadedCache()
        guard !vectors.isEmpty, !query.isEmpty else { return [] }

        var scored: [(Int, Float)] = []
        scored.reserveCapacity(min(vectors.count, 512))

        for (index, item) in vectors.enumerated() {
            if let entityTypes, !entityTypes.contains(item.entityType) { continue }
            if let roles {
                guard let role = item.role, roles.contains(role) else { continue }
            }
            guard item.embedding.count == query.count else { continue }
            var similarity: Float = 0
            vDSP_dotpr(item.embedding, 1, query, 1, &similarity, vDSP_Length(query.count))
            if similarity >= minSimilarity {
                scored.append((index, similarity))
            }
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { index, similarity in
                let item = vectors[index]
                return RecallVectorHit(
                    entityUuid: item.entityUuid,
                    entityType: item.entityType,
                    chunkIndex: item.chunkIndex,
                    page: item.page,
                    text: item.text,
                    similarity: similarity,
                    role: item.role
                )
            }
    }

    /// First-chunk vector per entity — centroid math (inbox routing fallback).
    func embeddings(forEntityUuids uuids: [String]) async -> [String: [Float]] {
        guard !uuids.isEmpty else { return [:] }
        let wanted = Set(uuids)
        let vectors = await loadedCache()
        var out: [String: [Float]] = [:]
        for item in vectors where item.chunkIndex == 0 && wanted.contains(item.entityUuid) {
            out[item.entityUuid] = item.embedding
        }
        return out
    }

    /// Max chunk similarity per entity for a candidate set — the re-rank stage
    /// of hybrid search (one cache sweep, no per-candidate roundtrips).
    func bestSimilarities(
        entityUuids: Set<String>,
        query: [Float]
    ) async -> [String: Float] {
        guard !entityUuids.isEmpty, !query.isEmpty else { return [:] }
        let vectors = await loadedCache()
        var best: [String: Float] = [:]
        for item in vectors where entityUuids.contains(item.entityUuid) {
            guard item.embedding.count == query.count else { continue }
            var similarity: Float = 0
            vDSP_dotpr(item.embedding, 1, query, 1, &similarity, vDSP_Length(query.count))
            if similarity > (best[item.entityUuid] ?? -1) {
                best[item.entityUuid] = similarity
            }
        }
        return best
    }

    // MARK: - Cache

    private func loadedCache() async -> [CachedVector] {
        if let cache { return cache }
        let loaded: [CachedVector] = (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(RecallVectorRow.databaseTableName)) ?? false else { return [] }
            let rows = try RecallVectorRow.fetchAll(db)
            return rows.map { row in
                CachedVector(
                    entityUuid: row.entityUuid,
                    entityType: row.entityType,
                    chunkIndex: row.chunkIndex,
                    page: row.page,
                    text: row.text,
                    embedding: Self.vector(from: row.embedding),
                    role: row.role
                )
            }
        }) ?? []
        cache = loaded
        return loaded
    }

    // MARK: - Blob Codec

    nonisolated static func blob(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    nonisolated static func vector(from blob: Data) -> [Float] {
        blob.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
