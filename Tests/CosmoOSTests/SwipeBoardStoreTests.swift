import XCTest
@testable import CosmoOS

@MainActor
final class SwipeBoardStoreTests: XCTestCase {

    func testSeededDefaultBoardsExist() async throws {
        let store = SwipeBoardStore()
        await store.load()

        let uuids = Set(store.boards.map(\.uuid))
        XCTAssertTrue(uuids.contains("thread-hooks"))
        XCTAssertTrue(uuids.contains("reel-ideas"))
        XCTAssertTrue(uuids.contains("client-proof"))
    }

    func testCreateRenameArchiveRoundTrip() async throws {
        let store = SwipeBoardStore()
        await store.load()

        let name = "Test Board \(UUID().uuidString.prefix(8))"
        guard let board = await store.create(name: name) else {
            return XCTFail("Board creation failed")
        }
        defer { Task { await store.delete(uuid: board.uuid) } }

        XCTAssertTrue(store.boards.contains { $0.uuid == board.uuid && $0.name == name })
        XCTAssertGreaterThanOrEqual(board.sortOrder, store.boards.filter { $0.uuid != board.uuid }.map(\.sortOrder).max() ?? 0)

        await store.rename(uuid: board.uuid, to: "Renamed Board")
        XCTAssertEqual(store.board(withID: board.uuid)?.name, "Renamed Board")

        await store.archive(uuid: board.uuid)
        XCTAssertNil(store.board(withID: board.uuid), "Archived boards must not appear in the loaded list")

        await store.delete(uuid: board.uuid)
    }

    func testCreateRejectsBlankNames() async throws {
        let store = SwipeBoardStore()
        let board = await store.create(name: "   ")
        XCTAssertNil(board)
    }

    func testCountsTallyFromGalleryItems() {
        let store = SwipeBoardStore()
        let items = [
            makeItem(boardIDs: ["thread-hooks"]),
            makeItem(boardIDs: ["thread-hooks", "reel-ideas"]),
            makeItem(boardIDs: []),
            makeItem(boardIDs: ["reel-ideas"])
        ]

        store.refreshCounts(from: items)

        XCTAssertEqual(store.counts["thread-hooks"], 2)
        XCTAssertEqual(store.counts["reel-ideas"], 2)
        XCTAssertNil(store.counts["client-proof"])
    }

    private func makeItem(boardIDs: [String]) -> SwipeGalleryItem {
        SwipeGalleryItem(
            atomUUID: UUID().uuidString,
            title: "Swipe",
            hookText: "Swipe",
            createdAt: "2026-06-01T00:00:00Z",
            boardIDs: boardIDs
        )
    }
}
