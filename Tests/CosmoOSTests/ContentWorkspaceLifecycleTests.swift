import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class ContentWorkspaceLifecycleTests: XCTestCase {
    #if DEBUG
    func testReturningToObservedIdeasDoesNotFetchAgain() async {
        let model = IdeasPageModel()
        await model.start()
        let before = model.loadInvocationCount
        await model.start()
        await model.start()
        XCTAssertEqual(model.loadInvocationCount, before, "A warm tab activation must not query and decode the idea library again")
        model.stop()
    }

    func testConcurrentIdeasStartupSharesOneLoad() async {
        let model = IdeasPageModel()
        async let first: Void = model.start()
        async let second: Void = model.start()
        _ = await (first, second)
        XCTAssertEqual(model.loadInvocationCount, 1, "The workspace and its child must not race two startup loads")
        model.stop()
    }

    func testConcurrentPipelineStartupSharesOneLoad() async {
        let model = PipelinePageModel()
        async let first: Void = model.start()
        async let second: Void = model.start()
        _ = await (first, second)
        XCTAssertEqual(model.loadInvocationCount, 1, "Pipeline startup should have one data load and one observer")
        model.stop()
    }

    func testReenteringWorkspaceRefreshesAfterObservationStopped() async {
        let model = IdeasPageModel()
        await model.start()
        let before = model.loadInvocationCount
        model.stop()
        await model.start()
        XCTAssertGreaterThan(model.loadInvocationCount, before, "Retaining tabs must not turn into a stale cache across workspace visits")
        model.stop()
    }

    func testRetainedPagesObserveEditsWithoutAnotherStart() async throws {
        let idea = Atom.new(type: .idea, title: "Before retained-page edit", body: nil)
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync { try idea.insert(db) }
        }
        addTeardownBlock {
            try await CosmoDatabase.shared.asyncWrite { db in
                try CanvasBlockSyncObserver.suppressingSync {
                    try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [idea.uuid])
                }
            }
        }
        let ideas = IdeasPageModel()
        let pipeline = PipelinePageModel()
        defer { ideas.stop(); pipeline.stop() }
        await ideas.start()
        await pipeline.start()
        XCTAssertTrue(ideas.ideas.contains { $0.atomUUID == idea.uuid })
        XCTAssertTrue(pipeline.ideas.contains { $0.atomUUID == idea.uuid })

        // A local edit may share updated_at with the previous write. Keeping
        // the page alive must still pick it up through the version change.
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                try db.execute(sql: "UPDATE atoms SET title = ?, _local_version = _local_version + 1 WHERE uuid = ?",
                               arguments: ["After retained-page edit", idea.uuid])
            }
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if ideas.ideas.first(where: { $0.atomUUID == idea.uuid })?.title == "After retained-page edit",
               pipeline.ideas.first(where: { $0.atomUUID == idea.uuid })?.title == "After retained-page edit" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(ideas.ideas.first { $0.atomUUID == idea.uuid }?.title, "After retained-page edit")
        XCTAssertEqual(pipeline.ideas.first { $0.atomUUID == idea.uuid }?.title, "After retained-page edit")
    }
    #endif
}
