import XCTest
@testable import CosmoOS

/// The Inbox's swipe route. A swipe is now a first-class destination the
/// classifier can recommend — not just a verb button hidden behind a URL gate.
@MainActor
final class InboxSwipeRouteTests: XCTestCase {

    private func item(rawText: String, attachments: [String] = []) -> InboxItem {
        var made = InboxItem.new(source: .quickCapture, rawText: rawText)
        if !attachments.isEmpty {
            let json = try! JSONSerialization.data(withJSONObject: ["attachmentUUIDs": attachments])
            made.metadata = String(data: json, encoding: .utf8)
        }
        return made
    }

    // MARK: - The verb's gate

    /// The old gate was `detectedSwipeURL != nil`, which hid the verb on
    /// exactly the captures the artifact spine exists for: a screenshot, or a
    /// headline someone typed.
    func testLinksImagesAndCopyCanAllBecomeSwipes() {
        XCTAssertTrue(item(rawText: "https://someone.com/sales").canBecomeSwipe)
        XCTAssertTrue(item(rawText: "", attachments: ["a1"]).canBecomeSwipe)
        XCTAssertTrue(item(rawText: "The hook that made me stop scrolling").canBecomeSwipe)
    }

    func testAnEmptyCaptureCannotBecomeASwipe() {
        XCTAssertFalse(item(rawText: "   \n ").canBecomeSwipe)
    }

    // MARK: - Predicted kind (what the verb's label promises)

    func testPredictedKindMatchesTheRoutersLadder() {
        XCTAssertEqual(item(rawText: "https://www.instagram.com/reel/ABC/").predictedSwipeKind, .post)
        XCTAssertEqual(item(rawText: "https://someone.com/sales").predictedSwipeKind, .page)
        XCTAssertEqual(item(rawText: "", attachments: ["a1", "a2"]).predictedSwipeKind, .frame)
        XCTAssertEqual(item(rawText: "A headline worth stealing").predictedSwipeKind, .note)
    }

    /// A link buried in prose still predicts by the link — the Inbox verb acts
    /// on the capture's link when it has one, unlike the pasteboard ladder
    /// where surrounding prose means the prose IS the capture.
    func testProseAroundALinkStillPredictsFromTheLink() {
        let captured = item(rawText: "look at this funnel https://someone.com/sales")
        XCTAssertNotNil(captured.detectedSwipeURL)
        XCTAssertEqual(captured.predictedSwipeKind, .page)
    }

    /// The link wins over images: the original post beats a screenshot of it,
    /// and the images ride along rather than being stranded.
    func testALinkBeatsAttachedImages() {
        let captured = item(rawText: "https://someone.com/sales", attachments: ["a1"])
        XCTAssertEqual(captured.predictedSwipeKind, .page)
    }

    // MARK: - Route kind vocabulary

    func testSwipeRoutesCarryTheSwipeIdentity() {
        XCTAssertEqual(InboxRouteKind.fileAsSwipe.outcomeNoun(suggestedAtomType: "research"), "Swipe file")
        XCTAssertEqual(InboxRouteKind.addToFlow.outcomeNoun(suggestedAtomType: nil), "Step in a flow")
        XCTAssertEqual(InboxRouteKind.fileAsSwipe.primaryVerbLabel, "Swipe")
        XCTAssertEqual(InboxRouteKind.addToFlow.primaryVerbLabel, "Add step")
        XCTAssertEqual(InboxRouteKind.fileAsSwipe.outcomeIcon, SwipeKind.post.iconName)
        XCTAssertEqual(InboxRouteKind.addToFlow.outcomeIcon, SwipeKind.flow.iconName)
    }

    /// A routed swipe must render as an actionable suggestion, or the pill and
    /// the primary accept button never appear.
    func testSwipeRoutesRenderAsActionableSuggestions() {
        XCTAssertEqual(InboxRouteKind.fileAsSwipe.legacyClassification, .place)
        XCTAssertEqual(InboxRouteKind.addToFlow.legacyClassification, .place)
    }

    func testSwipeRoutesAreNotSeedlingKinds() {
        XCTAssertFalse(InboxRouteKind.fileAsSwipe.isSeedlingKind)
        XCTAssertFalse(InboxRouteKind.addToFlow.isSeedlingKind)
    }

    // MARK: - Classifier prompt

    /// The router can only recommend a swipe if its prompt teaches the move.
    /// The FORM TEST is the operative rule — it decides on what the user would
    /// re-open the capture FOR, not on whether it happens to carry a link.
    func testAtlasPromptTeachesTheSwipeMove() {
        XCTAssertTrue(InboxAtlasRouter.MoveKind.allCases.contains(.fileAsSwipe))
    }

    // MARK: - Flow membership

    func testRepackingKeepsIndexEqualToStepNumber() {
        let units = [
            SwipeArtifactUnit(index: 0, memberSwipeUUID: "a"),
            SwipeArtifactUnit(index: 2, memberSwipeUUID: "c"),
            SwipeArtifactUnit(index: 5, memberSwipeUUID: "d")
        ]
        let repacked = SwipeFlowStore.repacked(units)
        XCTAssertEqual(repacked.map(\.index), [0, 1, 2])
        XCTAssertEqual(repacked.map(\.memberSwipeUUID), ["a", "c", "d"])
    }

    /// A flow's units point at OTHER swipes — that is the whole design, and it
    /// is why cards, boards, study, search and sync carry over unchanged.
    func testFlowUnitsPointAtMemberSwipes() {
        let flow = SwipeArtifact(kind: .flow, units: [
            SwipeArtifactUnit(index: 0, memberSwipeUUID: "swipe-a"),
            SwipeArtifactUnit(index: 1, memberSwipeUUID: "swipe-b")
        ])
        XCTAssertEqual(flow.orderedUnits.compactMap(\.memberSwipeUUID), ["swipe-a", "swipe-b"])
        XCTAssertTrue(flow.units.allSatisfy { $0.attachmentUUID == nil })
    }
}
