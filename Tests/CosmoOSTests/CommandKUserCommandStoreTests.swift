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

    /// Built-ins that duplicated system commands are retired: only quicklinks
    /// with no system-command equivalent ship seeded.
    func testOnlyNonDuplicateBuiltInsAreSeeded() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url)

        let all = try await store.searchQuicklinks("")

        XCTAssertEqual(all.map(\.id), ["inquiries"])
    }

    /// Users who already have the old built-ins on disk get them removed on
    /// next load — but only while they still point at the original route.
    func testRetiredBuiltInsAreMigratedAway() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let legacyStore = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        let now = Date(timeIntervalSince1970: 1)
        try await legacyStore.saveQuicklink(CommandKQuicklink(
            id: "swipes", alias: "swipes", title: "Swipe Gallery",
            route: .commandKDomain("swipeGallery"), query: nil, createdAt: now, updatedAt: now
        ))
        // Repurposed retired id: the user pointed "ideas" somewhere else —
        // migration must not touch it.
        try await legacyStore.saveQuicklink(CommandKQuicklink(
            id: "ideas", alias: "ideas", title: "Idea search",
            route: .savedSearch("spark"), query: "spark", createdAt: now, updatedAt: now
        ))

        let migrated = CommandKUserCommandStore(fileURL: url)
        let all = try await migrated.searchQuicklinks("")

        XCTAssertEqual(Set(all.map(\.id)), ["ideas", "inquiries"])
        XCTAssertEqual(all.first { $0.id == "ideas" }?.route, .savedSearch("spark"))
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
