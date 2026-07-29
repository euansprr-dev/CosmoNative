import XCTest
@testable import CosmoOS

/// Flows: an ordered container of member swipes.
///
/// The design's whole payoff is that a flow IS a swipe — its units point at
/// other swipes instead of carrying media — so cards, boards, study, search,
/// undo and sync all carry over with no new plumbing. These tests pin the
/// membership rules and the reading prompt that rely on that shape.
@MainActor
final class SwipeFlowTests: XCTestCase {

    private func flowArtifact(_ memberUUIDs: [String]) -> SwipeArtifact {
        SwipeArtifact(
            kind: .flow,
            units: memberUUIDs.enumerated().map { index, uuid in
                SwipeArtifactUnit(index: index, memberSwipeUUID: uuid)
            }
        )
    }

    // MARK: - Step numbering

    func testRepackingKeepsIndicesDenseAndOrdered() {
        let units = [
            SwipeArtifactUnit(index: 0, memberSwipeUUID: "a"),
            SwipeArtifactUnit(index: 7, memberSwipeUUID: "b"),
            SwipeArtifactUnit(index: 12, memberSwipeUUID: "c")
        ]
        let repacked = SwipeFlowStore.repacked(units)
        XCTAssertEqual(repacked.map(\.index), [0, 1, 2])
        XCTAssertEqual(repacked.map(\.memberSwipeUUID), ["a", "b", "c"])
    }

    func testRepackingPreservesEverythingButTheIndex() {
        let unit = SwipeArtifactUnit(
            index: 9, role: .offer, headline: "The stack",
            mechanic: "prices the delay", memberSwipeUUID: "m"
        )
        let repacked = SwipeFlowStore.repacked([unit])
        XCTAssertEqual(repacked[0].index, 0)
        XCTAssertEqual(repacked[0].role, .offer)
        XCTAssertEqual(repacked[0].headline, "The stack")
        XCTAssertEqual(repacked[0].mechanic, "prices the delay")
    }

    // MARK: - Recorder session

    func testPillLabelReadsNaturally() {
        XCTAssertEqual(
            SwipeFlowRecorder.Session(flowUUID: "f", name: "Client X funnel", stepCount: 1).pillLabel,
            "Client X funnel · 1 step")
        XCTAssertEqual(
            SwipeFlowRecorder.Session(flowUUID: "f", name: "Client X funnel", stepCount: 4).pillLabel,
            "Client X funnel · 4 steps")
        XCTAssertEqual(
            SwipeFlowRecorder.Session(flowUUID: "f", name: "Client X funnel", stepCount: 0).pillLabel,
            "Client X funnel · 0 steps")
    }

    /// A prefilled name and one Return — starting a recording must cost one
    /// click, or it is a feature used once and never again.
    func testDefaultNameIsUsableWithoutTyping() {
        let name = SwipeFlowRecorder.defaultName()
        XCTAssertTrue(name.hasPrefix("Funnel · "))
        XCTAssertGreaterThan(name.count, "Funnel · ".count)
    }

    func testRecorderStartsIdle() {
        // A brand-new session must never be mid-recording: every capture would
        // silently land in a funnel the user never opened.
        let recorder = SwipeFlowRecorder.shared
        recorder.stop()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.session)
    }

    func testStoppingKeepsNothingBehind() {
        let recorder = SwipeFlowRecorder.shared
        recorder.stop()
        XCTAssertNil(recorder.session, "stopping clears the session but never deletes the flow")
    }

    // MARK: - The receipt

    /// A capture that joins a flow says so INSTEAD of saying "Swiped" — two
    /// messages in sequence would contradict each other.
    func testFlowReceiptReplacesThePlainOne() {
        let plain = SwipeIntakeReceipt(kind: .page, unitCount: 12, atomUUID: "u")
        let joined = SwipeIntakeReceipt(kind: .page, unitCount: 12, atomUUID: "u", flowName: "Client X funnel")
        XCTAssertEqual(plain.message, "Swiped · Page · 12 sections")
        XCTAssertEqual(joined.message, "Added to Client X funnel · Page")
    }

    // MARK: - Reading a funnel

    /// The prompt is built from SIGNATURE CARDS, never transcripts or page
    /// text — that is what makes reading a twelve-step funnel one small call
    /// rather than a hundred thousand tokens of sales copy.
    func testReadFunnelPromptCarriesEveryStepAndTheRoleVocabulary() {
        var first = Atom.new(type: .research, title: "Opt-in page")
        first.updateResearchMetadata { $0.isSwipeFile = true; $0.url = "https://x.com/optin" }
        first = first.withSwipeAnalysis(SwipeAnalysis(
            keyInsight: "trades a checklist for an email", analysisVersion: 4
        ))
        var second = Atom.new(type: .research, title: "Sales page")
        second.updateResearchMetadata { $0.isSwipeFile = true }

        let prompt = SwipeFlowStore.readFunnelPrompt(
            flowName: "Client X funnel", members: [first, second]
        )
        XCTAssertTrue(prompt.contains("Client X funnel"))
        XCTAssertTrue(prompt.contains("[1]"))
        XCTAssertTrue(prompt.contains("[2]"))
        XCTAssertTrue(prompt.contains("Opt-in page"))
        XCTAssertTrue(prompt.contains("https://x.com/optin"))
        XCTAssertTrue(prompt.contains("2 entries, 1 through 2"))
        for role in SwipeUnitRole.allCases {
            XCTAssertTrue(prompt.contains(role.rawValue), "\(role.rawValue) missing from the funnel prompt")
        }
    }

    /// The operative instruction is the LADDER, stated concretely. Abstract
    /// answers ("builds trust") are exactly what this system exists to avoid.
    func testReadFunnelPromptDemandsAConcreteLadder() {
        let prompt = SwipeFlowStore.readFunnelPrompt(
            flowName: "F", members: [Atom.new(type: .research, title: "A")]
        )
        XCTAssertTrue(prompt.contains("LADDER"))
        XCTAssertTrue(prompt.contains("never abstractly"))
        XCTAssertTrue(prompt.contains("where the price first appears"))
    }

    // MARK: - Shape

    func testFlowUnitsCarryMembersNotMedia() {
        let artifact = flowArtifact(["a", "b", "c"])
        XCTAssertEqual(artifact.orderedUnits.compactMap(\.memberSwipeUUID), ["a", "b", "c"])
        XCTAssertTrue(artifact.units.allSatisfy { $0.attachmentUUID == nil },
                      "a flow's content is its members — it owns no media of its own")
    }

    func testAFlowIsNotCloudProcessable() {
        XCTAssertFalse(SwipeKind.flow.isCloudProcessable)
        XCTAssertFalse(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://www.instagram.com/p/ABC/",
            contentSource: "instagram_post",
            swipeKind: SwipeKind.flow.rawValue))
    }

    func testFlowUnitNounIsStep() {
        XCTAssertEqual(SwipeKind.flow.unitNoun, "step")
        XCTAssertEqual(SwipeKind.flow.unitCountLabel(1), "1 step")
        XCTAssertEqual(SwipeKind.flow.unitCountLabel(5), "5 steps")
    }
}
