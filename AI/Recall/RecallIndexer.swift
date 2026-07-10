// CosmoOS/AI/Recall/RecallIndexer.swift
// Keeps the vector index consistent with the atoms table. Writes enqueue
// re-embeds into a durable outbox; a background worker drains it in batches
// with backoff. Failures never block saves; the backfill pass catches both
// MISSING atoms and STALE ones (doc-hash mismatch — the gap that let the old
// index rot after every edit).
// July 2026

import Foundation
import GRDB

// MARK: - Outbox Row

struct RecallOutboxRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recall_outbox"

    var id: Int64?
    var entityUuid: String
    var attempts: Int
    var lastError: String?
    var createdAt: String

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case entityUuid = "entity_uuid"
        case attempts
        case lastError = "last_error"
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Index Health (Settings panel)

struct RecallIndexStatus: Sendable, Equatable {
    var indexedAtoms: Int = 0
    var indexedVectors: Int = 0
    var pending: Int = 0
    var failing: Int = 0
    var model: String = ""
    var isConfigured: Bool = false
    var lastError: String?
}

// MARK: - Indexer

/// Owns the outbox and the drain loop. All entry points are cheap; the
/// expensive work happens on a background task with batching.
actor RecallIndexer {
    static let shared = RecallIndexer()

    private var client: any RecallEmbeddingClient = CloudEmbeddingClient()
    private var drainTask: Task<Void, Never>?
    private var lastError: String?

    /// Attempts beyond this park the row until the next backfill pass —
    /// it stops burning requests on a poisoned document.
    private let maxAttempts = 5
    private let drainBatch = 16

    /// Test seam.
    func setClient(_ newClient: any RecallEmbeddingClient) {
        client = newClient
    }

    // MARK: - Enqueue (write-path hook)

    /// Called after an atom save commits. Cheap: one INSERT if the atom is
    /// indexable and its content hash differs from the indexed one.
    func noteAtomChanged(_ atom: Atom) async {
        guard RecallDocumentBuilder.isIndexable(atom) else {
            // Type flips and emptied bodies fall out of the index.
            await RecallStore.shared.removeEntity(atom.uuid)
            return
        }
        await enqueue(uuid: atom.uuid)
        scheduleDrain()
    }

    /// UUID-only variant for callers that write outside AtomRepository —
    /// the drain fetches the fresh atom itself.
    func noteAtomChanged(uuid: String) async {
        await enqueue(uuid: uuid)
        scheduleDrain()
    }

    func noteAtomDeleted(_ uuid: String) async {
        await RecallStore.shared.removeEntity(uuid)
        try? await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(sql: "DELETE FROM recall_outbox WHERE entity_uuid = ?", arguments: [uuid])
        }
    }

    private func enqueue(uuid: String) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(RecallOutboxRow.databaseTableName)) ?? false else { return }
            let exists = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM recall_outbox WHERE entity_uuid = ?)",
                arguments: [uuid]
            ) ?? false
            if exists {
                // Content changed again — reset the attempt counter.
                try db.execute(
                    sql: "UPDATE recall_outbox SET attempts = 0, last_error = NULL WHERE entity_uuid = ?",
                    arguments: [uuid]
                )
            } else {
                var row = RecallOutboxRow(
                    id: nil, entityUuid: uuid, attempts: 0, lastError: nil,
                    createdAt: ISO8601.string(from: Date())
                )
                try row.insert(db)
            }
        }
    }

    // MARK: - Drain

    func scheduleDrain() {
        guard drainTask == nil else { return }
        drainTask = Task(priority: .utility) { [weak self] in
            await self?.drain()
            await self?.clearDrainTask()
        }
    }

    private func clearDrainTask() {
        drainTask = nil
    }

    private func drain() async {
        guard client.isConfigured else { return }

        while !Task.isCancelled {
            let batch: [RecallOutboxRow] = (try? await CosmoDatabase.shared.asyncRead { [maxAttempts, drainBatch] db in
                guard (try? db.tableExists(RecallOutboxRow.databaseTableName)) ?? false else { return [] }
                return try RecallOutboxRow
                    .filter(Column("attempts") < maxAttempts)
                    .order(Column("id"))
                    .limit(drainBatch)
                    .fetchAll(db)
            }) ?? []

            guard !batch.isEmpty else { return }

            var hadFailure = false
            for row in batch {
                do {
                    try await indexAtom(uuid: row.entityUuid)
                    try? await CosmoDatabase.shared.asyncWrite { db in
                        try db.execute(sql: "DELETE FROM recall_outbox WHERE entity_uuid = ?", arguments: [row.entityUuid])
                    }
                } catch {
                    hadFailure = true
                    lastError = error.localizedDescription
                    try? await CosmoDatabase.shared.asyncWrite { db in
                        try db.execute(
                            sql: "UPDATE recall_outbox SET attempts = attempts + 1, last_error = ? WHERE entity_uuid = ?",
                            arguments: [String(error.localizedDescription.prefix(300)), row.entityUuid]
                        )
                    }
                }
            }

            if hadFailure {
                // Backoff before the next batch; a dead network shouldn't spin.
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Embed one atom's chunks and replace its index rows.
    private func indexAtom(uuid: String) async throws {
        guard let atom = try await CosmoDatabase.shared.asyncRead({ db in
            try Atom.filter(Atom.CodingKeys.uuid == uuid).fetchOne(db)
        }) else {
            await RecallStore.shared.removeEntity(uuid)
            return
        }
        guard RecallDocumentBuilder.isIndexable(atom) else {
            await RecallStore.shared.removeEntity(uuid)
            return
        }

        let chunks = RecallDocumentBuilder.chunks(for: atom)
        guard !chunks.isEmpty else {
            await RecallStore.shared.removeEntity(uuid)
            return
        }

        let embeddings = try await client.embed(chunks.map(\.text))
        try await RecallStore.shared.replaceChunks(
            entityUuid: atom.uuid,
            entityType: atom.type.rawValue,
            docHash: RecallDocumentBuilder.documentHash(for: atom),
            model: client.modelID,
            chunks: chunks,
            embeddings: embeddings
        )
    }

    // MARK: - Backfill

    /// Full reconciliation: enqueue every indexable atom that is missing from
    /// the index OR stale (hash mismatch). Startup calls this deferred; the
    /// Settings panel can trigger it manually.
    @discardableResult
    func backfill() async -> Int {
        let indexed = await RecallStore.shared.indexedHashes()

        let candidates: [(uuid: String, hash: String)] = (try? await CosmoDatabase.shared.asyncRead { db in
            let typeList = RecallDocumentBuilder.indexedTypes.map { "'\($0.rawValue)'" }.joined(separator: ",")
            let atoms = try Atom
                .filter(sql: "is_deleted = 0 AND type IN (\(typeList))")
                .fetchAll(db)
            return atoms.compactMap { atom in
                guard RecallDocumentBuilder.isIndexable(atom) else { return nil }
                return (atom.uuid, RecallDocumentBuilder.documentHash(for: atom))
            }
        }) ?? []

        var enqueued = 0
        for candidate in candidates where indexed[candidate.uuid] != candidate.hash {
            await enqueue(uuid: candidate.uuid)
            enqueued += 1
        }

        // Index rows for atoms that no longer exist or stopped being indexable.
        let liveUuids = Set(candidates.map(\.uuid))
        for staleUuid in indexed.keys where !liveUuids.contains(staleUuid) {
            await RecallStore.shared.removeEntity(staleUuid)
        }

        if enqueued > 0 {
            print("RecallIndexer: backfill enqueued \(enqueued) atoms")
            scheduleDrain()
        }
        return enqueued
    }

    // MARK: - Status

    func status() async -> RecallIndexStatus {
        let stats = await RecallStore.shared.stats()
        let (pending, failing): (Int, Int) = (try? await CosmoDatabase.shared.asyncRead { [maxAttempts] db in
            guard (try? db.tableExists(RecallOutboxRow.databaseTableName)) ?? false else { return (0, 0) }
            let pending = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recall_outbox WHERE attempts < ?", arguments: [maxAttempts]) ?? 0
            let failing = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recall_outbox WHERE attempts >= ?", arguments: [maxAttempts]) ?? 0
            return (pending, failing)
        }) ?? (0, 0)

        return RecallIndexStatus(
            indexedAtoms: stats.atoms,
            indexedVectors: stats.vectors,
            pending: pending,
            failing: failing,
            model: client.modelID,
            isConfigured: client.isConfigured,
            lastError: lastError
        )
    }
}
