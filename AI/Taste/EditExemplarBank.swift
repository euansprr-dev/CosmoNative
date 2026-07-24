// CosmoOS/AI/Taste/EditExemplarBank.swift
// The exemplar bank: raw (AI version → user version) pairs from settled edit
// episodes, kept small and curated, retrieved few-shot into future edit runs.
// Beliefs compress WHAT to do; exemplars show HOW — models imitate concrete
// pairs far better than abstract rules, and retrieval keyed on the current
// ask means a hook edit pulls hook pairs.
//
// Bloat control is structural: dedup folds near-identical pairs into a
// supportCount, the bank caps at 60 active rows per scope, at most 3 pairs
// ever reach a prompt, and retrieval is threshold-gated (no match → nothing
// injected — silence over noise).
// July 2026

import Foundation
import GRDB

struct EditExemplar: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "edit_exemplars"

    enum Kind: String, Sendable {
        /// Accepted, then reshaped by hand — the 70%→100% pass.
        case tweak
        /// Rejected, then self-written — same pair, stronger negative.
        case rejectPair = "reject_pair"
    }

    enum Status: String, Sendable {
        case active
        /// User-struck tombstone: never shown, never re-learned.
        case struck
    }

    var id: String
    var clientUuid: String?
    var skillId: String
    var slideRole: String?
    var kind: String
    var aiText: String
    var humanText: String
    var embedding: Data?
    var supportCount: Int
    var timesShown: Int
    var status: String
    var createdAt: String
    var lastShownAt: String?

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case clientUuid = "client_uuid"
        case skillId = "skill_id"
        case slideRole = "slide_role"
        case kind
        case aiText = "ai_text"
        case humanText = "human_text"
        case embedding
        case supportCount = "support_count"
        case timesShown = "times_shown"
        case status
        case createdAt = "created_at"
        case lastShownAt = "last_shown_at"
    }
}

enum EditExemplarBank {
    /// Near-identical pairs fold into supportCount instead of duplicating —
    /// repetition becomes confidence, not bloat. Same contract as archival
    /// memory novelty.
    static let dedupThreshold: Float = 0.92
    /// Active rows per scope; history grows, the bank doesn't.
    static let maxActivePerScope = 60
    /// Embedding-scored retrieval floor (mirrors archival recall).
    static let retrievalThreshold: Float = 0.45
    /// Token-overlap floor for the no-embedding fallback path.
    static let fallbackRetrievalThreshold = 0.08
    static let maxRetrieved = 3

    // MARK: - Ingest

    /// Called when an episode settles as a pair. Embedding is best-effort:
    /// an offline embedding service degrades dedup/retrieval to exact-text
    /// and token-overlap — learning never depends on the cloud.
    static func ingest(from episode: InlineEditEpisode, settledText: String) async {
        let aiText = String(episode.aiText.prefix(600))
        let humanText = String(settledText.prefix(600))
        guard !aiText.isEmpty, !humanText.isEmpty, aiText != humanText else { return }
        let kind: EditExemplar.Kind = episode.verdictKind == .accepted ? .tweak : .rejectPair
        let embedding = await embed(pairText(ai: aiText, human: humanText))

        // Dedup pass — actives fold in, struck tombstones swallow the ingest.
        let scoped = await exemplars(clientUuid: episode.clientUuid, includeStruck: true)
        for existing in scoped where existing.kind == kind.rawValue {
            let isNearDuplicate: Bool
            if let embedding, let existingEmbedding = existing.embedding {
                isNearDuplicate = cosine(embedding, vector(from: existingEmbedding)) >= dedupThreshold
            } else {
                isNearDuplicate = existing.aiText == aiText && existing.humanText == humanText
            }
            guard isNearDuplicate else { continue }
            if existing.status == EditExemplar.Status.struck.rawValue {
                return // The user struck this lesson — it stays dead.
            }
            await bumpSupport(id: existing.id)
            return
        }

        let exemplar = EditExemplar(
            id: UUID().uuidString,
            clientUuid: episode.clientUuid,
            skillId: episode.skillId,
            slideRole: episode.slideRole,
            kind: kind.rawValue,
            aiText: aiText,
            humanText: humanText,
            embedding: embedding.map(blob(from:)),
            supportCount: 1,
            timesShown: 0,
            status: EditExemplar.Status.active.rawValue,
            createdAt: ISO8601.string(from: Date()),
            lastShownAt: nil
        )
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(EditExemplar.databaseTableName)) ?? false else { return }
            var row = exemplar
            try row.save(db)
        }
        await enforceCap(clientUuid: episode.clientUuid)
    }

    // MARK: - Retrieval

    /// Top pairs for the current ask: client scope first, personal fallback,
    /// threshold-gated. Uses the same query-embedding the archival recall
    /// just computed (EmbeddingCache makes the second lookup free).
    static func retrieve(
        query: String,
        clientUuid: String?,
        limit: Int = EditExemplarBank.maxRetrieved
    ) async -> [EditExemplar] {
        var pool = await exemplars(clientUuid: clientUuid, includeStruck: false)
        if let clientUuid, !clientUuid.isEmpty {
            let personal = await exemplars(clientUuid: nil, includeStruck: false)
            pool.append(contentsOf: personal)
        }
        guard !pool.isEmpty else { return [] }

        if let queryEmbedding = await embed(query) {
            let scored = pool.compactMap { exemplar -> (EditExemplar, Float)? in
                guard let data = exemplar.embedding else { return nil }
                let score = cosine(queryEmbedding, vector(from: data))
                return score >= retrievalThreshold ? (exemplar, score) : nil
            }
            if !scored.isEmpty {
                return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
            }
        }
        // Fallback: token overlap between the ask and each pair's text.
        let scored = pool.compactMap { exemplar -> (EditExemplar, Double)? in
            let score = InlineEditHarvester.tokenSimilarity(
                query, pairText(ai: exemplar.aiText, human: exemplar.humanText)
            )
            return score >= fallbackRetrievalThreshold ? (exemplar, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// The volatile prompt block. The framing does the teaching: the delta is
    /// the lesson, the topics are noise.
    static func promptBlock(for exemplars: [EditExemplar]) -> String? {
        guard !exemplars.isEmpty else { return nil }
        var lines = [
            "## How the user upgrades drafts like this (real pairs from their own edits)",
            "Each pair shows text an AI staged and what the user turned it into. Study the DIFFERENCE — length, rhythm, person, punctuation, where the concrete detail sits — and write at the USER'S VERSION level the first time. The topics in these pairs are irrelevant; the transformation is the lesson."
        ]
        for exemplar in exemplars {
            let role = exemplar.slideRole.map { " (\($0))" } ?? ""
            let label = exemplar.kind == EditExemplar.Kind.rejectPair.rawValue
                ? "AI VERSION (rejected)" : "AI VERSION"
            lines.append("- \(label)\(role): \"\(exemplar.aiText)\"")
            lines.append("  USER'S VERSION: \"\(exemplar.humanText)\"")
        }
        return lines.joined(separator: "\n")
    }

    static func markShown(ids: [String]) async {
        guard !ids.isEmpty else { return }
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(EditExemplar.databaseTableName)) ?? false else { return }
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE edit_exemplars SET times_shown = times_shown + 1, last_shown_at = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments([ISO8601.string(from: Date())] + ids)
            )
        }
    }

    // MARK: - Curation (Profile Studio)

    /// Strike = tombstone: hidden from retrieval forever, and the dedup pass
    /// keeps swallowing re-learned near-duplicates.
    static func strike(id: String) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(EditExemplar.databaseTableName)) ?? false else { return }
            try db.execute(
                sql: "UPDATE edit_exemplars SET status = 'struck' WHERE id = ?",
                arguments: [id]
            )
        }
    }

    static func recent(clientUuid: String?, limit: Int = 20) async -> [EditExemplar] {
        let all = await exemplars(clientUuid: clientUuid, includeStruck: false)
        return Array(all.prefix(limit))
    }

    // MARK: - Internals

    private static func exemplars(clientUuid: String?, includeStruck: Bool) async -> [EditExemplar] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(EditExemplar.databaseTableName)) ?? false else { return [] }
            var request = clientUuid == nil
                ? EditExemplar.filter(sql: "client_uuid IS NULL")
                : EditExemplar.filter(EditExemplar.CodingKeys.clientUuid == clientUuid)
            if !includeStruck {
                request = request.filter(Column("status") == EditExemplar.Status.active.rawValue)
            }
            return try request.order(Column("created_at").desc).fetchAll(db)
        }) ?? []
    }

    private static func bumpSupport(id: String) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(EditExemplar.databaseTableName)) ?? false else { return }
            try db.execute(
                sql: "UPDATE edit_exemplars SET support_count = support_count + 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Evicts the least-supported, oldest actives once the scope overflows.
    private static func enforceCap(clientUuid: String?) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(EditExemplar.databaseTableName)) ?? false else { return }
            let scopeClause = clientUuid == nil ? "client_uuid IS NULL" : "client_uuid = ?"
            let scopeArguments: [DatabaseValueConvertible] = clientUuid.map { [$0] } ?? []
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM edit_exemplars WHERE \(scopeClause) AND status = 'active'",
                arguments: StatementArguments(scopeArguments)
            ) ?? 0
            let overflow = count - maxActivePerScope
            guard overflow > 0 else { return }
            try db.execute(
                sql: """
                DELETE FROM edit_exemplars WHERE id IN (
                    SELECT id FROM edit_exemplars
                    WHERE \(scopeClause) AND status = 'active'
                    ORDER BY support_count ASC, created_at ASC
                    LIMIT ?
                )
                """,
                arguments: StatementArguments(scopeArguments + [overflow])
            )
        }
    }

    private static func pairText(ai: String, human: String) -> String {
        "\(ai)\n\(human)"
    }

    private static func embed(_ text: String) async -> [Float]? {
        if let cached = await EmbeddingCache.shared.get(for: text) { return cached }
        guard let vector = try? await RecallEmbedding.embedText(text) else { return nil }
        await EmbeddingCache.shared.set(vector, for: text)
        return vector
    }

    private static func blob(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func vector(from data: Data) -> [Float] {
        data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }

    private static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            magnitudeA += a[index] * a[index]
            magnitudeB += b[index] * b[index]
        }
        let denominator = magnitudeA.squareRoot() * magnitudeB.squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }
}
