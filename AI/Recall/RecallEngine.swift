// CosmoOS/AI/Recall/RecallEngine.swift
// The retrieval API every recall consumer talks to: hybrid search that blends
// a BM25 keyword pass (atoms_fts) with a vector sweep (RecallStore), plus a
// gentle recency boost. Returns scored hits with the matched chunk text so
// every suggestion can show WHY it surfaced — receipts, not vibes.
// July 2026

import Foundation
import GRDB

// MARK: - Query & Hit

struct RecallQuery: Sendable {
    var text: String
    /// Restrict to specific atom types (raw values); nil = all indexed types.
    var types: Set<AtomType>? = nil
    var limit: Int = 8
    /// Half-life for the recency boost, in days. nil disables it.
    var recencyHalfLifeDays: Double? = 90
    /// Exclude these atoms (e.g. the document being written).
    var excludeUuids: Set<String> = []
    /// Hits below this blended score are dropped — silence over noise.
    var minScore: Double = 0.18
    /// Positive scope, applied before candidate limits. nil = global; [] = none.
    var includeUuids: Set<String>? = nil
}

struct RecallHit: Sendable, Identifiable {
    let atomUuid: String
    let atomType: AtomType
    let title: String
    /// The chunk that matched — the receipt shown to the user.
    let matchedText: String
    let page: Int?
    let score: Double
    let vectorSimilarity: Double
    let keywordScore: Double
    let updatedAt: Date?

    var id: String { "\(atomUuid):\(matchedText.hashValue)" }
}

// MARK: - Engine

actor RecallEngine {
    static let shared = RecallEngine()

    private var client: any RecallEmbeddingClient = CloudEmbeddingClient()

    /// Blend weights: semantic similarity carries the ranking, keywords keep
    /// exact-term matches honest, recency nudges fresh work upward.
    private let vectorWeight = 0.65
    private let keywordWeight = 0.25
    private let recencyWeight = 0.10

    /// Small LRU for query embeddings — repeated Margin refreshes on the same
    /// paragraph shouldn't re-bill the API.
    private var embeddingCache: [String: [Float]] = [:]
    private var embeddingCacheOrder: [String] = []
    private let embeddingCacheLimit = 64

    func setClient(_ newClient: any RecallEmbeddingClient) {
        client = newClient
        embeddingCache.removeAll()
        embeddingCacheOrder.removeAll()
    }

    // MARK: - Query

    func query(_ query: RecallQuery) async -> [RecallHit] {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        if query.includeUuids?.isEmpty == true { return [] }

        let typeFilter = query.types.map { Set($0.map(\.rawValue)) }

        // Two candidate pools, fetched concurrently.
        async let vectorHitsTask = vectorCandidates(text: text, typeFilter: typeFilter, limit: max(24, query.limit * 3), includeUuids: query.includeUuids)
        async let keywordHitsTask = keywordCandidates(text: text, typeFilter: typeFilter, limit: 24, includeUuids: query.includeUuids)
        let (vectorHits, keywordHits) = await (vectorHitsTask, keywordHitsTask)

        guard !vectorHits.isEmpty || !keywordHits.isEmpty else { return [] }

        // Blend per atom: best chunk similarity + normalized bm25 + recency.
        struct Candidate {
            var vectorSimilarity: Double = 0
            var keywordScore: Double = 0
            var matchedText: String = ""
            var page: Int?
        }
        var candidates: [String: Candidate] = [:]

        for hit in vectorHits {
            var candidate = candidates[hit.entityUuid] ?? Candidate()
            if Double(hit.similarity) > candidate.vectorSimilarity {
                candidate.vectorSimilarity = Double(hit.similarity)
                candidate.matchedText = hit.text
                candidate.page = hit.page
            }
            candidates[hit.entityUuid] = candidate
        }

        let maxBM25 = keywordHits.map(\.score).max() ?? 1
        for hit in keywordHits {
            var candidate = candidates[hit.uuid] ?? Candidate()
            candidate.keywordScore = maxBM25 > 0 ? hit.score / maxBM25 : 0
            if candidate.matchedText.isEmpty { candidate.matchedText = hit.snippet }
            candidates[hit.uuid] = candidate
        }

        // Hydrate atoms for titles/recency + apply filters.
        let uuids = Array(candidates.keys.filter { !query.excludeUuids.contains($0) })
        guard !uuids.isEmpty else { return [] }

        let atoms: [String: Atom] = (try? await CosmoDatabase.shared.asyncRead { db in
            var out: [String: Atom] = [:]
            for slice in stride(from: 0, to: uuids.count, by: 200).map({ Array(uuids[$0..<min($0 + 200, uuids.count)]) }) {
                let fetched = try Atom
                    .filter(slice.contains(Column("uuid")))
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
                for atom in fetched { out[atom.uuid] = atom }
            }
            return out
        }) ?? [:]

        let now = Date()
        var hits: [RecallHit] = []
        for (uuid, candidate) in candidates {
            if let allowed = query.includeUuids, !allowed.contains(uuid) { continue }
            guard let atom = atoms[uuid] else { continue }
            if let types = query.types, !types.contains(atom.type) { continue }

            let updatedAt = ISO8601.date(from: atom.updatedAt)
            let recency: Double
            if let halfLife = query.recencyHalfLifeDays, let updatedAt {
                let ageDays = now.timeIntervalSince(updatedAt) / 86_400
                recency = pow(0.5, ageDays / halfLife)
            } else {
                recency = 0
            }

            let score = vectorWeight * candidate.vectorSimilarity
                + keywordWeight * candidate.keywordScore
                + recencyWeight * recency
            guard score >= query.minScore else { continue }

            hits.append(RecallHit(
                atomUuid: uuid,
                atomType: atom.type,
                title: atom.title?.isEmpty == false ? atom.title! : "Untitled",
                matchedText: String(candidate.matchedText.prefix(400)),
                page: candidate.page,
                score: score,
                vectorSimilarity: candidate.vectorSimilarity,
                keywordScore: candidate.keywordScore,
                updatedAt: updatedAt
            ))
        }

        return hits
            .sorted { $0.score > $1.score }
            .prefix(query.limit)
            .map { $0 }
    }

    // MARK: - Candidate pools

    private func vectorCandidates(
        text: String,
        typeFilter: Set<String>?,
        limit: Int,
        includeUuids: Set<String>?
    ) async -> [RecallVectorHit] {
        guard client.isConfigured else { return [] }
        guard let embedding = await queryEmbedding(for: text) else { return [] }
        return await RecallStore.shared.search(
            embedding: embedding,
            limit: limit,
            entityTypes: typeFilter,
            minSimilarity: 0.05,
            entityUuids: includeUuids
        )
    }

    private struct KeywordHit {
        let uuid: String
        let score: Double
        let snippet: String
    }

    private func keywordCandidates(
        text: String,
        typeFilter: Set<String>?,
        limit: Int,
        includeUuids: Set<String>?
    ) async -> [KeywordHit] {
        // Build a forgiving OR query from the meaningful terms.
        let terms = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .prefix(12)
        guard !terms.isEmpty else { return [] }
        let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")

        return (try? await CosmoDatabase.shared.asyncRead { db in
            var sql = """
                SELECT atoms_fts.uuid AS uuid,
                       -bm25(atoms_fts, 0, 0, 10, 5, 1) AS score,
                       snippet(atoms_fts, 3, '', '', '…', 24) AS snip
                FROM atoms_fts
                WHERE atoms_fts MATCH ?
                """
            var arguments: [DatabaseValueConvertible] = [match]
            if let typeFilter, !typeFilter.isEmpty {
                let placeholders = Array(repeating: "?", count: typeFilter.count).joined(separator: ",")
                sql += " AND atoms_fts.type IN (\(placeholders))"
                arguments.append(contentsOf: Array(typeFilter))
            }
            if let includeUuids {
                // One bound JSON parameter supports large boards without
                // exceeding SQLite's variable limit. Scope precedes top-k.
                sql += " AND atoms_fts.uuid IN (SELECT value FROM json_each(?))"
                arguments.append(String(data: try JSONEncoder().encode(includeUuids.sorted()), encoding: .utf8) ?? "[]")
            }
            sql += " ORDER BY score DESC LIMIT ?"
            arguments.append(limit)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return rows.compactMap { row -> KeywordHit? in
                guard let uuid: String = row["uuid"] else { return nil }
                let score: Double = row["score"] ?? 0
                let snippet: String = row["snip"] ?? ""
                return KeywordHit(uuid: uuid, score: max(score, 0), snippet: snippet)
            }
        }) ?? []
    }

    // MARK: - Query embedding cache

    private func queryEmbedding(for text: String) async -> [Float]? {
        let key = "\(client.modelID)|\(text)"
        if let cached = embeddingCache[key] { return cached }
        guard let vector = try? await client.embed([text]).first else { return nil }
        embeddingCache[key] = vector
        embeddingCacheOrder.append(key)
        if embeddingCacheOrder.count > embeddingCacheLimit {
            let evicted = embeddingCacheOrder.removeFirst()
            embeddingCache.removeValue(forKey: evicted)
        }
        return vector
    }
}
