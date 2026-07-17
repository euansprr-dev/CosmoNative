// CosmoOS/Data/Repositories/SeedlingRepository.swift
// The global Seedbed's store. Seedlings sync Mac ↔ iPhone through the shared
// ChangeTracker pipeline (the CapturedItemRepository pattern). Feeding a
// seedling is deliberately low-stakes: no atom is created, no canvas block is
// placed — mass accrues until a development conversation births the page.

import Combine
import Foundation
import GRDB

@MainActor
final class SeedlingRepository: ObservableObject {
    static let shared = SeedlingRepository()

    /// Global growing seedlings, ripest first — the Growing section's source.
    @Published private(set) var growing: [Seedling] = []

    private let database = CosmoDatabase.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeGrowing()
    }

    private func observeGrowing() {
        guard database.isReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.observeGrowing()
            }
            return
        }

        database.observe { db in
            try Seedling
                .filter(Column("status") == SeedlingStatus.growing.rawValue)
                .filter(Column("scopeDeepDiveUUID") == nil)
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .order(Column("lastTouchedAt").desc)
                .limit(100)
                .fetchAll(db)
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("SeedlingRepository observation failed: \(error)")
                }
            },
            receiveValue: { [weak self] seedlings in
                self?.growing = seedlings.sorted { lhs, rhs in
                    if lhs.isRipe != rhs.isRipe { return lhs.isRipe }
                    return lhs.lastTouchedAt > rhs.lastTouchedAt
                }
            }
        )
        .store(in: &cancellables)
    }

    var ripeCount: Int {
        growing.filter(\.isRipe).count
    }

    // MARK: - Create

    @discardableResult
    func create(_ seedling: Seedling) async throws -> Seedling {
        let saved = try await database.asyncWrite { db in
            var mutable = seedling
            mutable.syncUpdatedAt = ISO8601.string(from: Date())
            try mutable.insert(db)
            return mutable
        }
        await ChangeTracker.shared.trackInsert(table: Seedling.databaseTableName, entity: saved)
        return saved
    }

    // MARK: - Tracked mutations

    /// Version-bump + stamp shared by tracked mutations (the Atom pattern:
    /// the write and the ChangeTracker payload carry the same post-bump
    /// `_local_version`, so push bookkeeping can mark the queue row synced).
    private nonisolated static func prepareTrackedUpdate(_ seedling: inout Seedling) {
        seedling.localVersion += 1
        let now = ISO8601.string(from: Date())
        seedling.updatedAt = now
        seedling.syncUpdatedAt = now
    }

    private func track(_ seedling: Seedling?) async {
        guard let seedling else { return }
        await ChangeTracker.shared.trackUpdate(
            table: Seedling.databaseTableName,
            entity: seedling,
            skipVersionIncrement: true
        )
    }

    @discardableResult
    private func trackedMutation(
        uuid: String,
        _ mutate: @Sendable @escaping (inout Seedling) -> Bool
    ) async throws -> Seedling? {
        let updated = try await database.asyncWrite { db -> Seedling? in
            guard var seedling = try Seedling.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            guard mutate(&seedling) else { return nil }
            Self.prepareTrackedUpdate(&seedling)
            try seedling.update(db)
            return seedling
        }
        await track(updated)
        return updated
    }

    /// A captured thought lands in the seedling — the "grow" verb's write.
    @discardableResult
    func feed(uuid: String, thought: SeedlingThought) async throws -> Seedling? {
        try await trackedMutation(uuid: uuid) { seedling in
            // Idempotent per source capture: routing the same capture twice
            // (retry, undo/redo echo) must not double a thought.
            if let sourceUUID = thought.sourceUUID,
               seedling.thoughts.contains(where: { $0.sourceUUID == sourceUUID }) {
                return false
            }
            seedling.appendThought(thought)
            if seedling.status == .folded {
                // Feeding a folded seedling revives it.
                seedling.status = .growing
            }
            return true
        }
    }

    /// Undo for a feed: remove the thought that a specific capture added.
    @discardableResult
    func removeThought(uuid: String, sourceUUID: String) async throws -> Seedling? {
        try await trackedMutation(uuid: uuid) { seedling in
            var thoughts = seedling.thoughts
            let before = thoughts.count
            thoughts.removeAll { $0.sourceUUID == sourceUUID }
            guard thoughts.count != before else { return false }
            seedling.setThoughts(thoughts)
            return true
        }
    }

    /// Remove one thought by its own id (detail-surface row delete).
    @discardableResult
    func removeThought(uuid: String, thoughtId: String) async throws -> Seedling? {
        try await trackedMutation(uuid: uuid) { seedling in
            var thoughts = seedling.thoughts
            let before = thoughts.count
            thoughts.removeAll { $0.id == thoughtId }
            guard thoughts.count != before else { return false }
            seedling.setThoughts(thoughts)
            return true
        }
    }

    func rename(uuid: String, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await trackedMutation(uuid: uuid) { seedling in
            guard seedling.name != trimmed else { return false }
            // The old name survives as an alias so the router keeps matching
            // thoughts captured in the old vocabulary.
            var aliases = seedling.aliases
            if !aliases.contains(seedling.name) { aliases.append(seedling.name) }
            seedling.setAliases(aliases)
            seedling.name = trimmed
            seedling.conceptKey = ConceptResolver.conceptKey(trimmed)
            return true
        }
    }

    /// Pin = "this is ripe, I want to develop it" regardless of mass.
    func setPinned(uuid: String, pinned: Bool) async throws {
        _ = try await trackedMutation(uuid: uuid) { seedling in
            let stamp = pinned ? ISO8601.string(from: Date()) : nil
            guard seedling.pinnedAt != stamp else { return false }
            seedling.pinnedAt = stamp
            return true
        }
    }

    func setStatus(uuid: String, status: SeedlingStatus) async throws {
        _ = try await trackedMutation(uuid: uuid) { seedling in
            guard seedling.status != status else { return false }
            seedling.status = status
            return true
        }
    }

    /// A page was born: record the link, consume the pending thoughts that
    /// seeded it, and settle the seedling.
    func markDeveloped(uuid: String, connectionUUID: String) async throws {
        let now = ISO8601.string(from: Date())
        _ = try await trackedMutation(uuid: uuid) { seedling in
            seedling.status = .developed
            seedling.developedConnectionUUID = connectionUUID
            var thoughts = seedling.thoughts
            for index in thoughts.indices where thoughts[index].consumedAt == nil {
                thoughts[index].consumedAt = now
            }
            seedling.setThoughts(thoughts)
            return true
        }
    }

    /// Undo support: restore a seedling row to an exact prior snapshot.
    func restore(_ snapshot: Seedling) async throws {
        _ = try await trackedMutation(uuid: snapshot.uuid) { seedling in
            seedling.name = snapshot.name
            seedling.conceptKey = snapshot.conceptKey
            seedling.aliasesJSON = snapshot.aliasesJSON
            seedling.thoughtsJSON = snapshot.thoughtsJSON
            seedling.status = snapshot.status
            seedling.pinnedAt = snapshot.pinnedAt
            seedling.mergeTargetConnectionUUID = snapshot.mergeTargetConnectionUUID
            seedling.developedConnectionUUID = snapshot.developedConnectionUUID
            seedling.lastTouchedAt = snapshot.lastTouchedAt
            return true
        }
    }

    /// Soft-delete. Sync tombstones the cloud copy; never a hard delete.
    func delete(uuid: String) async throws {
        _ = try await trackedMutation(uuid: uuid) { seedling in
            seedling.isDeleted = true
            return true
        }
    }

    /// Re-insert a soft-deleted seedling (undo of delete).
    func undelete(uuid: String) async throws {
        _ = try await trackedMutation(uuid: uuid) { seedling in
            guard seedling.isDeleted else { return false }
            seedling.isDeleted = false
            return true
        }
    }

    // MARK: - Queries

    func fetch(uuid: String) async throws -> Seedling? {
        try await database.asyncRead { db in
            try Seedling.filter(Column("uuid") == uuid).fetchOne(db)
        }
    }

    /// Live (growing or folded, never developed/deleted) seedling for a
    /// concept key — the router's dedup anchor.
    func fetchLive(conceptKey: String) async throws -> Seedling? {
        try await database.asyncRead { db in
            try Seedling
                .filter(Column("conceptKey") == conceptKey)
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .filter(Column("status") != SeedlingStatus.developed.rawValue)
                .fetchOne(db)
        }
    }

    /// All growing global seedlings (router shortlist, badges). The published
    /// `growing` array serves UI; this serves actors off the main path.
    func fetchGrowing(limit: Int = 100) async throws -> [Seedling] {
        try await database.asyncRead { db in
            try Seedling
                .filter(Column("status") == SeedlingStatus.growing.rawValue)
                .filter(Column("scopeDeepDiveUUID") == nil)
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .order(Column("lastTouchedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Dive scope (the unified seedbed)

    /// Every live seedling scoped to one Deep Dive — all statuses, oldest
    /// first (stable ordering for the seedbed adapters).
    func fetchScoped(deepDiveUUID: String) async throws -> [Seedling] {
        try await database.asyncRead { db in
            try Seedling
                .filter(Column("scopeDeepDiveUUID") == deepDiveUUID)
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    /// Live seedling for a concept key inside one scope (nil scope = global).
    func fetchLive(conceptKey: String, scopeDeepDiveUUID: String?) async throws -> Seedling? {
        try await database.asyncRead { db in
            var request = Seedling
                .filter(Column("conceptKey") == conceptKey)
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .filter(Column("status") != SeedlingStatus.developed.rawValue)
            if let scopeDeepDiveUUID {
                request = request.filter(Column("scopeDeepDiveUUID") == scopeDeepDiveUUID)
            } else {
                request = request.filter(Column("scopeDeepDiveUUID") == nil)
            }
            return try request.fetchOne(db)
        }
    }

    /// Cross-dive collision lookup: every growing seedling carrying this
    /// concept key, in ANY scope. The same idea ripening in two places is a
    /// link to propose, never an automatic merge.
    func fetchGrowingEverywhere(conceptKey: String) async throws -> [Seedling] {
        try await database.asyncRead { db in
            try Seedling
                .filter(Column("conceptKey") == conceptKey)
                .filter(Column("status") == SeedlingStatus.growing.rawValue)
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .fetchAll(db)
        }
    }

    /// Generic tracked mutation for the seedbed adapters (dive service):
    /// return false from the transform to skip the write.
    @discardableResult
    func mutate(uuid: String, _ transform: @Sendable @escaping (inout Seedling) -> Bool) async throws -> Seedling? {
        try await trackedMutation(uuid: uuid, transform)
    }
}
