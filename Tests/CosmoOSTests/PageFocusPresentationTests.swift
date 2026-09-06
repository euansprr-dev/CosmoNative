import XCTest
@testable import CosmoOS

@MainActor
final class PageFocusPresentationTests: XCTestCase {
    func testFocusIsWindowLocalAndEscapeReturnsToNormalPresentation() {
        let firstWindow = PageFocusPresentation()
        let secondWindow = PageFocusPresentation()
        firstWindow.toggle(pageUUID: "page")
        XCTAssertTrue(firstWindow.isFocused)
        XCTAssertFalse(secondWindow.isFocused)
        XCTAssertTrue(firstWindow.exit())
        XCTAssertFalse(firstWindow.isFocused)
        XCTAssertNil(firstWindow.focusedPaneID)
        XCTAssertFalse(firstWindow.exit())
    }

    func testFocusRemembersItsPaneAndUnrelatedHostTeardownDoesNotExitIt() {
        let presentation = PageFocusPresentation()
        presentation.toggle(pageUUID: "page", paneID: "right-pane")
        presentation.end(pageUUID: "page")
        presentation.end(pageUUID: "other", paneID: "right-pane")
        XCTAssertEqual(presentation.focusedPageUUID, "page")
        XCTAssertEqual(presentation.focusedPaneID, "right-pane")
        presentation.end(pageUUID: "page", paneID: "right-pane")
        XCTAssertFalse(presentation.isFocused)
    }

    func testFocusCanTransferBetweenHostsOfTheSamePage() {
        let presentation = PageFocusPresentation()
        presentation.toggle(pageUUID: "page")
        presentation.toggle(pageUUID: "page", paneID: "pane")
        XCTAssertTrue(presentation.isFocused)
        XCTAssertEqual(presentation.focusedPaneID, "pane")
        presentation.toggle(pageUUID: "page", paneID: "pane")
        XCTAssertFalse(presentation.isFocused)
    }

    func testGlobalOpenNeverChoosesAnUnrelatedMembership() {
        XCTAssertNil(PageOpenLocationPolicy.destination(exactSpaceID: nil,
            preferredSpaceID: nil, reachableSpaceIDs: ["unrelated", "another"]))
        XCTAssertNil(PageOpenLocationPolicy.destination(exactSpaceID: nil,
            preferredSpaceID: "current", reachableSpaceIDs: ["unrelated"]))
    }

    func testExplicitLocationWinsAndUnavailableExactLocationDoesNotFallBack() {
        XCTAssertEqual(PageOpenLocationPolicy.destination(exactSpaceID: "chosen",
            preferredSpaceID: "current", reachableSpaceIDs: ["current", "chosen"]), "chosen")
        XCTAssertNil(PageOpenLocationPolicy.destination(exactSpaceID: "missing",
            preferredSpaceID: "current", reachableSpaceIDs: ["current"]))
        XCTAssertEqual(PageOpenLocationPolicy.destination(exactSpaceID: nil,
            preferredSpaceID: "current", reachableSpaceIDs: ["other", "current"]), "current")
    }

    func testGlobalContainersRetainTheirReachableWorkspace() {
        for kind in [SpaceCompositionKind.group, .book, .course, .guide] {
            XCTAssertTrue(PageOpenLocationPolicy.requiresSpace(for: kind))
            XCTAssertEqual(PageOpenLocationPolicy.destination(exactSpaceID: nil,
                preferredSpaceID: nil, reachableSpaceIDs: ["containing-space", "another"],
                compositionKind: kind), "containing-space")
            XCTAssertEqual(PageOpenLocationPolicy.destination(exactSpaceID: nil,
                preferredSpaceID: "source-without-container", reachableSpaceIDs: ["containing-space"],
                compositionKind: kind), "containing-space")
        }
        XCTAssertFalse(PageOpenLocationPolicy.requiresSpace(for: .page))
    }

    func testContainerExactLocationsNeverFallBackAndCurrentLocationWins() {
        for kind in [SpaceCompositionKind.group, .book, .course, .guide] {
            XCTAssertNil(PageOpenLocationPolicy.destination(exactSpaceID: "missing",
                preferredSpaceID: "current", reachableSpaceIDs: ["current"], compositionKind: kind))
            XCTAssertEqual(PageOpenLocationPolicy.destination(exactSpaceID: nil,
                preferredSpaceID: "current", reachableSpaceIDs: ["another", "current"],
                compositionKind: kind), "current")
            XCTAssertEqual(PageOpenLocationPolicy.destination(exactSpaceID: "exact",
                preferredSpaceID: "current", reachableSpaceIDs: ["current", "exact"],
                compositionKind: kind), "exact")
        }
    }

    func testUnreachableContainersRequireAnErrorInsteadOfAStandalonePage() {
        for kind in [SpaceCompositionKind.group, .book, .course, .guide] {
            XCTAssertTrue(PageOpenLocationPolicy.requiresSpace(for: kind))
            XCTAssertNil(PageOpenLocationPolicy.destination(exactSpaceID: nil,
                preferredSpaceID: nil, reachableSpaceIDs: [], compositionKind: kind))
        }
    }

    func testHistoryPreparationAwaitsEditorAndPropagatesSaveFailure() async {
        let registry = AtomRestoreAdopterRegistry.shared
        let uuid = UUID().uuidString
        var prepared = false
        registry.register(uuid: uuid, prepare: {
            await Task.yield()
            prepared = true
            return false
        }, adopt: { _ in })
        defer { registry.unregister(uuid: uuid) }
        let result = await registry.prepare(uuid: uuid)
        XCTAssertTrue(prepared)
        XCTAssertFalse(result)
    }

    func testLegacyHistoryAdopterHasNoNewSaveBarrier() async {
        let registry = AtomRestoreAdopterRegistry.shared
        let uuid = UUID().uuidString
        registry.register(uuid: uuid, prepare: { false }, adopt: { _ in })
        registry.register(uuid: uuid, adopt: { _ in })
        let legacyResult = await registry.prepare(uuid: uuid)
        XCTAssertTrue(legacyResult)
        registry.unregister(uuid: uuid)
        let closedResult = await registry.prepare(uuid: uuid)
        XCTAssertTrue(closedResult)
    }

    func testLegacyHistoryRestoresRichWordsAndRetainsCurrentMetadata() throws {
        var current = Atom.new(type: .note, title: "Current", body: "Current body")
        current.metadata = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: "{\"customStyle\":\"warm\",\"spaceParent\":\"book\"}",
            titleDocument: RichDocument.migrateLegacy("Current"),
            bodyDocument: RichDocument.migrateLegacy("Current body")
        ).metadata
        var old = current
        old.title = "Earlier"
        old.body = "Earlier body"
        old.metadata = nil
        let restored = AtomHistoryRestoreContent.applying(AtomRevision(of: old, source: .userEdit), to: current)
        XCTAssertEqual(restored.title, "Earlier")
        XCTAssertEqual(restored.body, "Earlier body")
        XCTAssertEqual(RichDocumentPersistence.loadAtomDocument(field: .body,
            metadata: restored.metadata, fallbackPlainText: restored.body).plainText, "Earlier body")
        let metadata = try XCTUnwrap(restored.metadata?.data(using: .utf8))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata) as? [String: Any])
        XCTAssertEqual(values["customStyle"] as? String, "warm")
        XCTAssertEqual(values["spaceParent"] as? String, "book")
    }

    func testEmptyLegacyRevisionClearsBothRichDocumentsAndMirrors() {
        var current = Atom.new(type: .note, title: "Current", body: "Current body")
        current.metadata = RichDocumentPersistence.writeAtomDocuments(existingMetadata: nil,
            titleDocument: RichDocument.migrateLegacy("Current"),
            bodyDocument: RichDocument.migrateLegacy("Current body")).metadata
        var old = current
        old.title = nil
        old.body = nil
        old.metadata = nil
        let restored = AtomHistoryRestoreContent.applying(AtomRevision(of: old, source: .userEdit), to: current)
        XCTAssertNil(restored.title)
        XCTAssertNil(restored.body)
        XCTAssertEqual(RichDocumentPersistence.loadAtomDocument(field: .title,
            metadata: restored.metadata, fallbackPlainText: restored.title).plainText, "")
        XCTAssertEqual(RichDocumentPersistence.loadAtomDocument(field: .body,
            metadata: restored.metadata, fallbackPlainText: restored.body).plainText, "")
    }
}
