import XCTest
@testable import CosmoOS

final class InboxIdentityTests: XCTestCase {
    @MainActor
    func testRepositoryUpdateAppliesImmediatelyAndPreservesDraft() {
        let model = InboxViewModel()
        let first = makeItem(title: "First")
        let second = makeItem(title: "Second")
        model.captureText = "My next thought"
        model.applyItems([first, second])
        model.focusedItemId = first.uuid
        model.isInspectorOpen = true
        model.selectedItemIds = [first.uuid, second.uuid]

        var updated = first
        updated.title = "Classified"
        model.applyItems([updated, second])
        XCTAssertEqual(model.focusedItem?.title, "Classified")
        XCTAssertTrue(model.isInspectorOpen)
        XCTAssertEqual(model.captureText, "My next thought")

        model.applyItems([second])
        XCTAssertEqual(model.groupedItems.flatMap(\.items).map(\.uuid), [second.uuid])
        XCTAssertEqual(model.selectedItemIds, [second.uuid])
        XCTAssertNil(model.focusedItemId)
        XCTAssertFalse(model.isInspectorOpen)
    }

    func testSectionIdentityIgnoresItemContentChangesButTracksOrder() {
        let first = makeItem(title: "First")
        let second = makeItem(title: "Second")
        var updatedFirst = first
        updatedFirst.title = "First updated"

        XCTAssertEqual(
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today", items: [first, second])
            ]),
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today renamed", items: [updatedFirst, second])
            ])
        )
        XCTAssertNotEqual(
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today", items: [first, second])
            ]),
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today", items: [second, first])
            ])
        )
        XCTAssertNotEqual(
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today", items: [first, second])
            ]),
            InboxSectionIdentity(sections: [
                InboxSection(id: "older", title: "Older", items: [first, second])
            ])
        )
    }

    // MARK: - Routing contract

    func testTriageableTypesExcludeSystemAtoms() {
        // Agent conversation transcripts are .systemEvent — the worst merge
        // polluter. The allowlist must never admit system or structural types.
        XCTAssertFalse(AtomType.triageable.contains(.systemEvent))
        XCTAssertFalse(AtomType.triageable.contains(.thinkspace))
        XCTAssertFalse(AtomType.triageable.contains(.clientProfile))
        XCTAssertFalse(AtomType.triageable.contains(.task))

        XCTAssertTrue(AtomType.triageable.contains(.note))
        XCTAssertTrue(AtomType.triageable.contains(.idea))
        XCTAssertTrue(AtomType.triageable.contains(.research))
        XCTAssertTrue(AtomType.triageable.contains(.content))
        XCTAssertTrue(AtomType.triageable.contains(.connection))
    }

    func testUnsortedIsNotAnActionableSuggestion() {
        var item = makeItem(title: "Loose thought")
        item.classification = .unsorted
        XCTAssertFalse(item.hasActionableSuggestion)

        item.classification = .place
        XCTAssertTrue(item.hasActionableSuggestion)

        item.classification = .merge
        XCTAssertTrue(item.hasActionableSuggestion)

        // Legacy "new" rows render as plain captures, like unsorted.
        item.classification = .new
        XCTAssertFalse(item.hasActionableSuggestion)
    }

    func testStandaloneRouteMapsToUnsorted() {
        // v2 only emits createStandaloneAtom on abstain — it must read as
        // unsorted, never as a suggestion classification.
        XCTAssertEqual(InboxRouteKind.createStandaloneAtom.legacyClassification, .unsorted)
        XCTAssertEqual(InboxRouteKind.mergeAtom.legacyClassification, .merge)
        XCTAssertEqual(InboxRouteKind.placeInExistingCluster.legacyClassification, .place)
    }

    func testHistoryEntriesIncludeDeletedCaptureLanesBeforeOlderCaptures() {
        var capture = makeItem(title: "Placed capture")
        capture.status = .actioned
        capture.actionedAt = "2026-06-15T01:00:00Z"

        var lane = CaptureDestination.make(name: "Client ideas", aliases: ["client"])
        lane.isArchived = true
        lane.isEnabled = false
        lane.itemCount = 12
        lane.updatedAt = "2026-06-15T02:00:00Z"

        let entries = InboxHistoryEntry.merged(captures: [capture], deletedLanes: [lane], limit: 5)

        XCTAssertEqual(entries.map(\.id), ["lane-\(lane.uuid)", "capture-\(capture.uuid)"])
        XCTAssertEqual(entries.first?.title, "Client ideas")
        XCTAssertEqual(entries.first?.subtitle, "Deleted lane · 12 captures · client:")
        XCTAssertTrue(entries.first?.isRestorable == true)
    }

    func testRecommendationBundleDecodesWithoutRelatedAtoms() throws {
        // Pre-June-2026 rows have no relatedAtomUUIDs key — decode must succeed.
        let legacyJSON = """
        {"bundleId":"b1","title":"T","createdAt":"2026-01-01T00:00:00Z","recommendations":[]}
        """
        let bundle = try JSONDecoder().decode(
            InboxRecommendationBundle.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertNil(bundle.relatedAtomUUIDs)
    }

    func testOverridingBlockPositionRewritesOnlyTheLandingSpot() {
        let plan = InboxPlacementPlan(
            targetThinkspaceId: "ts-1",
            targetThinkspaceName: "Philosophy",
            targetClusterId: "c-1",
            targetClusterName: "Stoicism",
            clusterViewMode: nil,
            blockPositionX: 100,
            blockPositionY: 200,
            clusterRect: nil,
            operations: [],
            summary: "Place"
        )
        let recommendation = InboxRecommendation(
            kind: .placeInExistingCluster,
            confidence: 0.8,
            suggestedAtomType: AtomType.note.rawValue,
            destinationPath: "Philosophy › Stoicism",
            rationale: "fits",
            thinkspaceId: "ts-1",
            thinkspaceName: "Philosophy",
            clusterId: "c-1",
            clusterName: "Stoicism",
            placementPlan: plan
        )

        let adjusted = recommendation.overridingBlockPosition(CGPoint(x: 640, y: 480))
        XCTAssertEqual(adjusted.placementPlan?.blockPositionX, 640)
        XCTAssertEqual(adjusted.placementPlan?.blockPositionY, 480)
        XCTAssertEqual(adjusted.placementPlan?.targetClusterId, "c-1")
        XCTAssertEqual(adjusted.id, recommendation.id)
        XCTAssertEqual(adjusted.thinkspaceId, "ts-1")
    }

    private func makeItem(title: String) -> InboxItem {
        InboxItem.new(
            source: .quickCapture,
            rawText: title,
            title: title
        )
    }
}
