import Foundation
import GRDB
import SwiftUI

/// Source of truth for swipe board definitions. Counts are tallied from swipe
/// atoms' `swipeBoardIDs` — boards never duplicate membership state.
@MainActor
@Observable
final class SwipeBoardStore {

    static let shared = SwipeBoardStore()

    private(set) var boards: [SwipeBoard] = []
    private(set) var counts: [String: Int] = [:]
    private(set) var isLoaded = false

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        await load()
    }

    func load() async {
        await Self.ensureSyncColumnsOnce()
        do {
            boards = try await CosmoDatabase.shared.asyncRead { db in
                try SwipeBoard
                    .filter(Column("isArchived") == false)
                    .filter(sql: "COALESCE(is_deleted, 0) = 0")
                    .order(Column("sortOrder").asc, Column("createdAt").asc)
                    .fetchAll(db)
            }
            isLoaded = true
        } catch {
            print("❌ Failed to load swipe boards: \(error)")
        }
    }

    // MARK: - iOS Companion Sync (ext 2)
    // Boards sync to Supabase `swipe_boards` so the iPhone shows them by name.
    // NOTE: these ALTERs belong in CosmoDatabase's migrator; they live here
    // temporarily because that file is mid-flight in another workstream.
    // Idempotent — ADD COLUMN failures on existing columns are expected.

    private static var syncColumnsEnsured = false

    static func ensureSyncColumnsOnce() async {
        guard !syncColumnsEnsured else { return }
        syncColumnsEnsured = true
        try? await CosmoDatabase.shared.asyncWrite { db in
            for column in [
                "is_deleted INTEGER NOT NULL DEFAULT 0",
                "_local_version INTEGER DEFAULT 1",
                "_server_version INTEGER DEFAULT 0",
                "_sync_version INTEGER DEFAULT 0",
                "_local_pending INTEGER DEFAULT 0",
            ] {
                try? db.execute(sql: "ALTER TABLE swipe_boards ADD COLUMN \(column)")
            }
        }
    }

    /// Push a board to Supabase (fire-and-forget) and queue it for batch retry.
    /// Payload mirrors the cloud swipe_boards schema; `_source = "mac"` so the
    /// iPhone applies it and this Mac never echoes it back.
    private func syncBoardToCloud(uuid: String, deleted: Bool = false) {
        Task { @MainActor in
            guard let client = SupabaseClient.shared, client.isAuthenticated,
                  let userId = client.currentUserId else { return }

            if deleted {
                try? await client.softDelete(table: "swipe_boards", uuid: uuid)
                return
            }

            guard let board = try? await CosmoDatabase.shared.asyncRead({ db in
                try SwipeBoard.filter(Column("uuid") == uuid).fetchOne(db)
            }) else { return }

            let payload: [String: Any] = [
                "uuid": board.uuid,
                "name": board.name,
                "icon": board.icon,
                "tintToken": board.tintToken as Any,
                "sortOrder": board.sortOrder,
                "isArchived": board.isArchived,
                "createdAt": board.createdAt,
                "updatedAt": board.updatedAt,
                "is_deleted": false,
                "user_id": userId,
                "_source": "mac",
            ]
            do {
                try await client.upsert(table: "swipe_boards", data: payload, onConflict: "uuid")
            } catch {
                // Queue for SyncEngine batch retry (same shape as other tables).
                let json = (try? JSONSerialization.data(withJSONObject: payload))
                    .flatMap { String(data: $0, encoding: .utf8) }
                try? await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: """
                        INSERT INTO sync_queue (uuid, table_name, operation, data, local_version, status)
                        VALUES (?, 'swipe_boards', 'INSERT', ?, 1, 'pending')
                        """,
                        arguments: [uuid, json]
                    )
                }
            }
        }
    }

    /// Launch backfill: push every board that has never reached the cloud.
    func backfillCloudBoardsIfNeeded() async {
        let key = "swipeBoardsCloudBackfill_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        await Self.ensureSyncColumnsOnce()
        await loadIfNeeded()
        for board in boards {
            syncBoardToCloud(uuid: board.uuid)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    func board(withID uuid: String) -> SwipeBoard? {
        boards.first { $0.uuid == uuid }
    }

    @discardableResult
    func create(name: String, icon: String = "rectangle.on.rectangle.angled") async -> SwipeBoard? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let now = ISO8601DateFormatter().string(from: Date())
        let board = SwipeBoard(
            uuid: UUID().uuidString,
            name: trimmed,
            icon: icon,
            tintToken: nil,
            sortOrder: (boards.map(\.sortOrder).max() ?? -1) + 1,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                try board.insert(db)
            }
            await load()
            syncBoardToCloud(uuid: board.uuid)
            return board
        } catch {
            print("❌ Failed to create swipe board: \(error)")
            return nil
        }
    }

    func rename(uuid: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await update(uuid: uuid, sql: "UPDATE swipe_boards SET name = ?, updatedAt = ? WHERE uuid = ?", arguments: [trimmed])
    }

    func setIcon(uuid: String, to icon: String) async {
        await update(uuid: uuid, sql: "UPDATE swipe_boards SET icon = ?, updatedAt = ? WHERE uuid = ?", arguments: [icon])
    }

    func archive(uuid: String) async {
        await update(uuid: uuid, sql: "UPDATE swipe_boards SET isArchived = 1, updatedAt = ? WHERE uuid = ?", arguments: [])
    }

    /// Permanent removal — used by tests and destructive delete flows.
    func delete(uuid: String) async {
        do {
            _ = try await CosmoDatabase.shared.asyncWrite { db in
                try SwipeBoard.deleteOne(db, key: ["uuid": uuid])
            }
            await load()
            syncBoardToCloud(uuid: uuid, deleted: true)
        } catch {
            print("❌ Failed to delete swipe board: \(error)")
        }
    }

    /// Tally membership from already-loaded gallery items (free when the library is open).
    func refreshCounts(from items: [SwipeGalleryItem]) {
        var tally: [String: Int] = [:]
        for item in items {
            for boardID in item.boardIDs {
                tally[boardID, default: 0] += 1
            }
        }
        if counts != tally {
            counts = tally
        }
    }

    /// Tally membership straight from the database (sidebar without an open library).
    func refreshCountsFromDatabase() async {
        do {
            let atoms = try await AtomRepository.shared.fetchSwipeFileAtoms()
            // Membership lives in metadata — the decode loop runs off-main.
            let tally = await Task.detached(priority: .userInitiated) {
                var tally: [String: Int] = [:]
                for atom in atoms where atom.isSwipeFileAtom {
                    for boardID in atom.swipeBoardIDs ?? [] {
                        tally[boardID, default: 0] += 1
                    }
                }
                return tally
            }.value
            if counts != tally {
                counts = tally
            }
        } catch {
            print("❌ Failed to refresh swipe board counts: \(error)")
        }
    }

    private func update(uuid: String, sql: String, arguments: [String]) async {
        let now = ISO8601DateFormatter().string(from: Date())
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(sql: sql, arguments: StatementArguments(arguments + [now, uuid]))
            }
            await load()
            syncBoardToCloud(uuid: uuid)
        } catch {
            print("❌ Failed to update swipe board: \(error)")
        }
    }
}
