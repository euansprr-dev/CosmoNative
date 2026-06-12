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
        do {
            boards = try await CosmoDatabase.shared.asyncRead { db in
                try SwipeBoard
                    .filter(Column("isArchived") == false)
                    .order(Column("sortOrder").asc, Column("createdAt").asc)
                    .fetchAll(db)
            }
            isLoaded = true
        } catch {
            print("❌ Failed to load swipe boards: \(error)")
        }
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
            let atoms = try await AtomRepository.shared.search(query: "", types: [.research])
            var tally: [String: Int] = [:]
            for atom in atoms where atom.isSwipeFileAtom {
                for boardID in atom.swipeBoardIDs ?? [] {
                    tally[boardID, default: 0] += 1
                }
            }
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
        } catch {
            print("❌ Failed to update swipe board: \(error)")
        }
    }
}
