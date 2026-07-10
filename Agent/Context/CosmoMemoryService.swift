// CosmoOS/Agent/Context/CosmoMemoryService.swift
// The agent's persistent memory: core facts (always injected), working memory
// (per conversation), and archival memory (embedding-recalled). Previously an
// in-RAM stub — every remembered fact vanished on restart, which is why the
// assistant never seemed to learn. Now GRDB-backed with the same actor API.

import Foundation
import GRDB

actor CosmoMemoryService {
    static let shared = CosmoMemoryService()

    /// Cosine similarity above which two archival memories are considered the
    /// same fact — the distiller uses this to avoid re-remembering.
    static let archivalDuplicateThreshold: Float = 0.92

    private let usesDatabase: Bool

    // In-memory fallback: tests, and graceful degradation when the DB is
    // unavailable (values still live for the session).
    private var coreByKey: [String: String] = [:]
    private var workingByConversationID: [String: [String]] = [:]
    private var archival: [(value: String, embedding: [Float]?)] = []
    private var didLoadFromDatabase = false

    init(usesDatabase: Bool = CosmoMemoryService.runtimeUsesDatabase()) {
        self.usesDatabase = usesDatabase
    }

    static func inMemoryForTests() -> CosmoMemoryService {
        CosmoMemoryService(usesDatabase: false)
    }

    private static func runtimeUsesDatabase() -> Bool {
        !(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil)
    }

    // MARK: - Core memory

    func upsertCoreMemory(_ value: String, key: String) async throws {
        await loadIfNeeded()
        coreByKey[key] = value
        guard usesDatabase, let dbQueue = Self.resolveDBQueue() else { return }
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO agent_core_memory (key, value, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                """,
                arguments: [key, value, ISO8601.string(from: Date())]
            )
        }
    }

    func coreMemory() async throws -> [String] {
        await loadIfNeeded()
        return coreByKey.keys.sorted().compactMap { coreByKey[$0] }
    }

    // MARK: - Working memory (per conversation)

    func upsertWorkingMemory(_ conversationID: String, value: String) async throws {
        await loadIfNeeded()
        var values = workingByConversationID[conversationID] ?? []
        guard !values.contains(value) else { return }
        values.append(value)
        workingByConversationID[conversationID] = values

        guard usesDatabase, let dbQueue = Self.resolveDBQueue() else { return }
        try? await dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO agent_working_memory (conversation_id, value, created_at) VALUES (?, ?, ?)",
                arguments: [conversationID, value, ISO8601.string(from: Date())]
            )
        }
    }

    func workingMemory(conversationID: String) async throws -> [String] {
        await loadIfNeeded()
        return workingByConversationID[conversationID] ?? []
    }

    func clearWorkingMemory(conversationID: String) async {
        workingByConversationID.removeValue(forKey: conversationID)
        guard usesDatabase, let dbQueue = Self.resolveDBQueue() else { return }
        try? await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM agent_working_memory WHERE conversation_id = ?",
                arguments: [conversationID]
            )
        }
    }

    // MARK: - Archival memory

    func addArchivalMemory(_ value: String) async throws {
        await loadIfNeeded()
        let embedding = await Self.embed(value)
        archival.append((value, embedding))

        guard usesDatabase, let dbQueue = Self.resolveDBQueue() else { return }
        let blob = embedding.map(Self.blob(from:))
        try? await dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO agent_archival_memory (uuid, value, embedding, created_at) VALUES (?, ?, ?, ?)",
                arguments: [UUID().uuidString, value, blob, ISO8601.string(from: Date())]
            )
        }
    }

    /// Adds the fact only when no stored memory already says the same thing
    /// (embedding similarity). Returns true when the fact was new.
    @discardableResult
    func addArchivalMemoryIfNovel(_ value: String) async -> Bool {
        await loadIfNeeded()
        if let embedding = await Self.embed(value) {
            let isDuplicate = archival.contains { stored in
                guard let storedEmbedding = stored.embedding else { return false }
                return Self.cosineSimilarity(embedding, storedEmbedding) >= Self.archivalDuplicateThreshold
            }
            if isDuplicate { return false }
        } else if archival.contains(where: { $0.value == value }) {
            return false
        }
        try? await addArchivalMemory(value)
        return true
    }

    /// Keyword search over archival memory (the agent's memory_search tool).
    func searchArchivalMemory(query: String, limit: Int = 5) async throws -> [String] {
        await loadIfNeeded()
        let terms = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        guard !terms.isEmpty else { return archival.prefix(limit).map(\.value) }

        return archival
            .filter { memory in
                let lower = memory.value.lowercased()
                return terms.contains { lower.contains($0) }
            }
            .prefix(limit)
            .map { $0.value }
    }

    /// Embedding recall for prompt assembly: the closest stored facts to the
    /// query, threshold-gated so unrelated memories never pollute a request.
    func recallArchivalMemory(
        query: String,
        limit: Int = 3,
        threshold: Float = 0.45
    ) async -> [String] {
        await loadIfNeeded()
        guard !archival.isEmpty, let queryEmbedding = await Self.embed(query) else { return [] }

        return archival
            .compactMap { memory -> (value: String, score: Float)? in
                guard let embedding = memory.embedding else { return nil }
                let score = Self.cosineSimilarity(queryEmbedding, embedding)
                return score >= threshold ? (memory.value, score) : nil
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.value)
    }

    func archivalMemoryCount() async -> Int {
        await loadIfNeeded()
        return archival.count
    }

    /// All archival facts, newest last — memory transparency for the UI.
    func allArchivalMemory() async -> [String] {
        await loadIfNeeded()
        return archival.map(\.value)
    }

    func deleteArchivalMemory(_ value: String) async {
        await loadIfNeeded()
        archival.removeAll { $0.value == value }
        guard usesDatabase, let dbQueue = Self.resolveDBQueue() else { return }
        try? await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM agent_archival_memory WHERE value = ?",
                arguments: [value]
            )
        }
    }

    // MARK: - Load

    private func loadIfNeeded() async {
        guard usesDatabase, !didLoadFromDatabase else { return }
        didLoadFromDatabase = true
        guard let dbQueue = Self.resolveDBQueue() else { return }

        let loaded = try? await dbQueue.read { db -> (core: [String: String], working: [String: [String]], archival: [(String, [Float]?)]) in
            var core: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key, value FROM agent_core_memory") {
                if let key = row["key"] as? String, let value = row["value"] as? String {
                    core[key] = value
                }
            }

            var working: [String: [String]] = [:]
            for row in try Row.fetchAll(
                db,
                sql: "SELECT conversation_id, value FROM agent_working_memory ORDER BY id ASC"
            ) {
                if let conversationID = row["conversation_id"] as? String,
                   let value = row["value"] as? String {
                    working[conversationID, default: []].append(value)
                }
            }

            var archivalRows: [(String, [Float]?)] = []
            for row in try Row.fetchAll(
                db,
                sql: "SELECT value, embedding FROM agent_archival_memory ORDER BY id ASC"
            ) {
                guard let value = row["value"] as? String else { continue }
                let embedding = (row["embedding"] as? Data).map(Self.vector(from:))
                archivalRows.append((value, embedding))
            }

            return (core, working, archivalRows)
        }

        if let loaded {
            coreByKey = loaded.core
            workingByConversationID = loaded.working
            archival = loaded.archival
        }
    }

    // MARK: - Helpers

    /// Same resolution pattern as CosmoInlineSkillStore: dbQueue is main-actor
    /// state; hop when called off-main (GRDB queues are thread-safe once held).
    private static func resolveDBQueue() -> DatabaseQueue? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { CosmoDatabase.shared.dbQueue }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { CosmoDatabase.shared.dbQueue }
        }
    }

    /// Recall cloud embeddings (L2-normalized). The old daemon path threw on
    /// every call, so no legacy 256-dim vectors were ever persisted — blobs
    /// written from here on all share the cloud model's dimension.
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
        data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
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
