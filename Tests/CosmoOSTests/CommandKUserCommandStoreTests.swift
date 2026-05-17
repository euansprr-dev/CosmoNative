import XCTest
@testable import CosmoOS

final class CommandKUserCommandStoreTests: XCTestCase {
    func testQuicklinksPersistAndSearchByAlias() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        let quicklink = CommandKQuicklink(
            id: "today",
            alias: "today",
            title: "Today",
            route: .commandCenter,
            query: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        try await store.saveQuicklink(quicklink)

        let reloaded = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        let results = try await reloaded.searchQuicklinks("tod")
        XCTAssertEqual(results.map(\.id), ["today"])
    }

    func testBuiltInQuicklinksAreSeededOnFirstLoad() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url)

        let results = try await store.searchQuicklinks("swipes")

        XCTAssertEqual(results.first?.route, .commandKDomain("swipeGallery"))
        XCTAssertEqual(results.first?.alias, "swipes")
    }

    func testQuicklinkComposerCreatesExecutableDomainAction() {
        let quicklink = CommandKQuicklink(
            id: "swipes",
            alias: "swipes",
            title: "Swipe Gallery",
            route: .commandKDomain("swipeGallery"),
            query: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        let rows = CommandKUserCommandSearchComposer().rows(for: [quicklink])

        XCTAssertEqual(rows.first?.action.kind, .openDomain)
        XCTAssertEqual(rows.first?.action.payload.domain, "swipeGallery")
    }
}
