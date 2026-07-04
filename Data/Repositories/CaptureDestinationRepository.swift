// CosmoOS/Data/Repositories/CaptureDestinationRepository.swift
// Persistence and command lookup for custom capture lanes.

import Combine
import Foundation
import GRDB

@MainActor
final class CaptureDestinationRepository: ObservableObject {
    static let shared = CaptureDestinationRepository()

    @Published private(set) var destinations: [CaptureDestination] = []

    private let database = CosmoDatabase.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeDestinations()
    }

    private func observeDestinations() {
        guard database.isReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.observeDestinations()
            }
            return
        }

        database.observe { db in
            try CaptureDestination
                .filter(Column("isArchived") == false)
                .order(Column("lastUsedAt").desc, Column("createdAt").desc)
                .fetchAll(db)
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("CaptureDestinationRepository observation failed: \(error)")
                }
            },
            receiveValue: { [weak self] destinations in
                self?.destinations = destinations
            }
        )
        .store(in: &cancellables)
    }

    @discardableResult
    func create(_ destination: CaptureDestination) async throws -> CaptureDestination {
        let saved = try await database.asyncWrite { db in
            var mutable = destination
            mutable.syncUpdatedAt = ISO8601.string(from: Date())
            try mutable.insert(db)
            return mutable
        }
        await ChangeTracker.shared.trackInsert(table: CaptureDestination.databaseTableName, entity: saved)
        return saved
    }

    /// Refetch + track after a raw-SQL mutation. The SQL is expected to have
    /// bumped `_local_version` itself so the tracked payload carries the
    /// post-bump version (push bookkeeping is scoped to it).
    private func trackAfterRawWrite(uuid: String) async {
        guard let fresh = try? await fetch(uuid: uuid) else { return }
        await ChangeTracker.shared.trackUpdate(
            table: CaptureDestination.databaseTableName,
            entity: fresh,
            skipVersionIncrement: true
        )
    }

    @discardableResult
    func createLane(named name: String, type: CaptureDestinationType? = nil, description: String? = nil) async throws -> CaptureDestination {
        if let existing = try await findByName(name) {
            return existing
        }
        return try await create(.make(name: name, description: description, type: type))
    }

    func update(_ destination: CaptureDestination) async throws {
        let saved = try await database.asyncWrite { db in
            var mutable = destination
            let now = ISO8601.string(from: Date())
            mutable.updatedAt = now
            mutable.syncUpdatedAt = now
            mutable.localVersion += 1
            try mutable.update(db)
            return mutable
        }
        await ChangeTracker.shared.trackUpdate(
            table: CaptureDestination.databaseTableName,
            entity: saved,
            skipVersionIncrement: true
        )
    }

    func archive(uuid: String) async throws {
        try await database.asyncWrite { db in
            let now = ISO8601.string(from: Date())
            try db.execute(
                sql: """
                    UPDATE capture_destinations
                    SET isArchived = 1, isEnabled = 0, updatedAt = ?,
                        updated_at = ?, _local_version = _local_version + 1
                    WHERE uuid = ?
                    """,
                arguments: [now, now, uuid]
            )
        }
        await trackAfterRawWrite(uuid: uuid)
        NotificationCenter.default.post(
            name: CosmoNotification.Inbox.captureLaneChanged,
            object: nil,
            userInfo: ["uuid": uuid]
        )
    }

    func restore(uuid: String) async throws {
        try await database.asyncWrite { db in
            let now = ISO8601.string(from: Date())
            try db.execute(
                sql: """
                    UPDATE capture_destinations
                    SET isArchived = 0, isEnabled = 1, updatedAt = ?,
                        updated_at = ?, _local_version = _local_version + 1
                    WHERE uuid = ?
                    """,
                arguments: [now, now, uuid]
            )
        }
        await trackAfterRawWrite(uuid: uuid)
        NotificationCenter.default.post(
            name: CosmoNotification.Inbox.captureLaneChanged,
            object: nil,
            userInfo: ["uuid": uuid]
        )
    }

    func markUsed(uuid: String) async {
        try? await database.asyncWrite { db in
            let now = ISO8601.string(from: Date())
            try db.execute(
                sql: """
                    UPDATE capture_destinations
                    SET lastUsedAt = ?, updatedAt = ?, itemCount = itemCount + 1,
                        updated_at = ?, _local_version = _local_version + 1
                    WHERE uuid = ?
                    """,
                arguments: [now, now, now, uuid]
            )
        }
        await trackAfterRawWrite(uuid: uuid)
    }

    func fetch(uuid: String) async throws -> CaptureDestination? {
        try await database.asyncRead { db in
            try CaptureDestination
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
    }

    func fetchActive() async throws -> [CaptureDestination] {
        try await database.asyncRead { db in
            try CaptureDestination
                .filter(Column("isArchived") == false)
                .filter(Column("isEnabled") == true)
                .order(Column("lastUsedAt").desc, Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchArchived(limit: Int? = nil) async throws -> [CaptureDestination] {
        try await database.asyncRead { db in
            var request = CaptureDestination
                .filter(Column("isArchived") == true)
                .order(Column("updatedAt").desc)
            if let limit {
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    func findByName(_ rawName: String) async throws -> CaptureDestination? {
        let normalized = CaptureDestination.normalizeAlias(rawName)
        return try await database.asyncRead { db in
            let all = try CaptureDestination
                .filter(Column("isArchived") == false)
                .fetchAll(db)
            return all.first { CaptureDestination.normalizeAlias($0.name) == normalized }
        }
    }

    func resolveCommand(_ rawCommand: String) async throws -> CaptureDestination? {
        let command = CaptureDestination.normalizeAlias(rawCommand)
        guard !command.isEmpty else { return nil }
        let active = try await fetchActive()

        let exact = active.first { destination in
            destination.aliases.contains { CaptureDestination.normalizeAlias($0) == command }
        }
        if exact != nil { return exact }

        return active.first { destination in
            CaptureDestination.normalizeAlias(destination.name) == command
        }
    }

    func closestAlias(to rawCommand: String) async -> String? {
        let command = CaptureDestination.normalizeAlias(rawCommand)
        guard !command.isEmpty else { return nil }
        let aliases = (try? await fetchActive())?.flatMap(\.aliases) ?? []
        let scored = aliases.map { ($0, levenshtein(CaptureDestination.normalizeAlias($0), command)) }
        guard let best = scored.min(by: { $0.1 < $1.1 }), best.1 <= 2 else { return nil }
        return best.0
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[bChars.count]
    }
}
