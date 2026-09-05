import XCTest
import GRDB
@testable import CosmoOS

final class IdeasGallerySnapshotTests: XCTestCase {
    private func idea(_ id: String, client: String? = "a", title: String? = nil, body: String? = nil,
                      pinned: Bool = false, updated: String = "2026-09-01T12:00:00Z") -> IdeaGalleryItem {
        IdeaGalleryItem(id: id, atomUUID: id, entityId: 1, title: title ?? "Idea \(id)", body: body,
            status: .spark, contentFormat: nil, platform: nil, clientName: client, clientUUID: client,
            tags: [], insightScore: nil, matchingSwipeCount: nil, suggestedFramework: nil,
            isPinned: pinned, contentCount: 0, createdAt: updated, updatedAt: updated)
    }
    private var clients: [IdeaClientCollection] {
        [IdeaClientCollection(clientUUID: "a", name: "A", activeCount: 12, archivedCount: 0),
         IdeaClientCollection(clientUUID: "b", name: "B", activeCount: 8, archivedCount: 0),
         IdeaClientCollection(clientUUID: nil, name: "Personal", activeCount: 1, archivedCount: 0)]
    }
    private func snapshot(_ ideas: [IdeaGalleryItem], scope: PipelineScope = .all,
                          filters: PipelineFilters = .init(), pinned: Bool = false,
                          sort: IdeasGallerySort = .recent, width: CGFloat = 820) -> IdeasGallerySnapshot {
        .make(items: ideas, scope: scope, collections: clients, filters: filters, pinnedOnly: pinned, sort: sort, width: width)
    }

    func testOverviewShowsOneRowAndReportsTheCompleteCollection() {
        let result = snapshot((0..<12).map { idea("a-\($0)") } + (0..<8).map { idea("b-\($0)", client: "b") })
        XCTAssertTrue(result.isOverview)
        XCTAssertEqual(result.columns, 3)
        XCTAssertEqual(result.sections.map(\.items.count), [3, 3])
        XCTAssertEqual(result.sections.map(\.total), [12, 8])
        XCTAssertEqual(result.total, 20)
        XCTAssertEqual(result.sections.map(\.scope), [.client(uuid: "a"), .client(uuid: "b")])
    }

    func testSearchNeverCapsResultsToTheOverviewShelf() {
        let result = snapshot((0..<80).map { idea("\($0)", body: "the specific thought") },
                              filters: .init(query: "thought specific"))
        XCTAssertFalse(result.isOverview)
        XCTAssertEqual(result.items.count, 80)
        XCTAssertEqual(result.total, 80)
    }

    func testClientPersonalAndSpaceViewsShowEveryItem() {
        let ideas = (0..<100).map { idea("\($0)") }
        for scope: PipelineScope in [.client(uuid: "a"), .unassigned, .space(thinkspaceId: "space")] {
            let result = snapshot(ideas, scope: scope)
            XCTAssertFalse(result.isOverview)
            XCTAssertEqual(result.items.count, 100)
        }
    }

    func testMissingClientKeepsItsOwnCollectionAndScope() {
        let result = snapshot([idea("known"), idea("orphan", client: "deleted-client"), idea("personal", client: nil)])
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(Set(result.items.map(\.atomUUID)), ["known", "orphan", "personal"])
        let orphan = result.sections.first { $0.id == "deleted-client" }
        XCTAssertEqual(orphan?.scope, .client(uuid: "deleted-client"))
        XCTAssertEqual(result.sections.first { $0.scope == .unassigned }?.items.map(\.atomUUID), ["personal"])
    }

    func testPinsLeadDeterministicRecencyAndPinFilterDoesNotTruncate() {
        let result = snapshot([idea("z", pinned: true), idea("new", updated: "2026-09-05T12:00:00Z"), idea("a", pinned: true)], scope: .client(uuid: "a"))
        XCTAssertEqual(result.items.map(\.atomUUID), ["a", "z", "new"])
        let pinned = snapshot((0..<20).map { idea("\($0)", pinned: true) } + [idea("not-pinned")], pinned: true)
        XCTAssertEqual(pinned.items.count, 20)
        XCTAssertFalse(pinned.isOverview)
    }

    func testNarrowAndWideLayoutsKeepSensibleColumnCounts() {
        XCTAssertEqual(IdeasGallerySnapshot.columnCount(width: 0), 1)
        XCTAssertEqual(IdeasGallerySnapshot.columnCount(width: 400), 1)
        XCTAssertEqual(IdeasGallerySnapshot.columnCount(width: 600), 2)
        XCTAssertEqual(IdeasGallerySnapshot.columnCount(width: 1050), 3)
        XCTAssertEqual(IdeasGallerySnapshot.columnCount(width: 1500), 5)
    }

    func testArrowsFollowGridRowsIncludingPartialClientRows() {
        let result = snapshot([idea("a1"), idea("a2"), idea("b1", client: "b"), idea("b2", client: "b"), idea("b3", client: "b")])
        XCTAssertEqual(result.nextID(from: "a2", direction: .down), "b2")
        XCTAssertEqual(result.nextID(from: "b3", direction: .up), "a2")
        XCTAssertEqual(result.nextID(from: "a1", direction: .left), "a1")
        XCTAssertEqual(result.nextID(from: "b3", direction: .right), "b3")
        XCTAssertEqual(result.nextID(from: nil, direction: .down), "a1")
    }

    func testArrowsReachFinalPartialRowOfAClientGallery() {
        let result = snapshot((1...7).map { idea("a\($0)") }, scope: .client(uuid: "a"))
        XCTAssertEqual(result.nextID(from: "a6", direction: .down), "a7")
        XCTAssertEqual(result.nextID(from: "a7", direction: .up), "a4")
    }

    func testExcerptDoesNotRepeatTheTitleOrExposeMarkdownEmphasis() {
        XCTAssertNil(IdeasGallerySnapshot.excerpt(for: idea("1", title: "A thought", body: " A   thought \n")))
        XCTAssertEqual(IdeasGallerySnapshot.excerpt(for: idea("1", title: "A thought", body: "Some **useful**\ncontext")), "Some useful context")
    }

    func testEmptyCollectionsHaveNoFictitiousCards() {
        let result = snapshot([])
        XCTAssertEqual(result.total, 0)
        XCTAssertTrue(result.sections.isEmpty)
        XCTAssertNil(result.nextID(from: nil, direction: .down))
    }
    func testSmallCollectionsShareTheAvailableShelfWidth() {
        let ideas = [idea("a1"), idea("a2"), idea("b1", client: "b")]
        let result = snapshot(ideas)
        XCTAssertEqual(result.shelves.count, 1)
        XCTAssertEqual(result.shelves.first?.sections.map(\.id), ["a", "b"])
        XCTAssertEqual(result.items.map(\.atomUUID), ["a1", "a2", "b1"])
        XCTAssertEqual(result.nextID(from: "a2", direction: .right), "b1")
        XCTAssertEqual(result.nextID(from: "a2", direction: .down), "a2")
    }

    func testRecentlyActiveCollectionComesFirstWithoutReorderingByOldPins() {
        let result = snapshot([idea("old-pin", pinned: true, updated: "2026-01-01T00:00:00Z"),
                               idea("current", client: "b", updated: "2026-09-05T00:00:00Z")])
        XCTAssertEqual(result.sections.map(\.id), ["b", "a"])
    }

    func testCaptureAttributionIsOmittedFromTheIdeaExcerpt() {
        let capture = "Inspired by: a source headline\nReference: https://instagram.com/reel/example\nMy original observation."
        XCTAssertEqual(IdeasGallerySnapshot.excerpt(for: idea("1", body: capture)), "My original observation.")
        XCTAssertNil(IdeasGallerySnapshot.excerpt(for: idea("2", body: "Inspired by: source\nReference: https://example.com")))
    }

    func testCollectionCountsIncludeReusableIdeasAndSeparateArchiveAndFormerClients() async throws {
        let client = UUID().uuidString
        let former = UUID().uuidString
        let empty = UUID().uuidString
        let atoms = [
            Atom.new(type: .idea, title: "Active", metadata: "{\"clientUUID\":\"\(client)\"}"),
            Atom.new(type: .idea, title: "Reusable", metadata: "{\"clientUUID\":\"\(client)\",\"ideaStatus\":\"inProduction\"}"),
            Atom.new(type: .idea, title: "Archived", metadata: "{\"clientUUID\":\"\(client)\",\"ideaStatus\":\"archived\"}"),
            Atom.new(type: .idea, title: "Former", metadata: "{\"clientUUID\":\"\(former)\",\"clientName\":\"Old name\"}"),
            Atom.new(type: .idea, title: "Malformed", metadata: "{invalid")
        ]
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                for atom in atoms { var saved = atom; try saved.insert(db) }
            }
        }
        do {
            let result = try await IdeaClientCollection.load(clients: [(client, "Current name"), (empty, "Empty")])
            XCTAssertEqual(result.first { $0.clientUUID == client }?.activeCount, 2)
            XCTAssertEqual(result.first { $0.clientUUID == client }?.archivedCount, 1)
            XCTAssertEqual(result.first { $0.clientUUID == client }?.name, "Current name")
            XCTAssertEqual(result.first { $0.clientUUID == former }?.name, "Old name")
            XCTAssertEqual(result.first { $0.clientUUID == former }?.scope, .client(uuid: former))
            XCTAssertEqual(result.first { $0.clientUUID == empty }?.activeCount, 0)
        } catch {
            try await remove(atoms)
            throw error
        }
        try await remove(atoms)
    }

    private func remove(_ atoms: [Atom]) async throws {
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                for atom in atoms { try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [atom.uuid]) }
            }
        }
    }

}
