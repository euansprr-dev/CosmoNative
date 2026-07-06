import XCTest
@testable import CosmoOS

/// The Gardener's signal contracts: promotion needs mass + drift (or gravity),
/// merges need real title convergence, graduation needs topic scale — and a
/// quiet garden yields no proposals at all.
final class InquiryGardenerSignalsTests: XCTestCase {

    // MARK: - Quiet gardens stay quiet

    func testSmallHealthyTreeYieldsNoProposals() {
        let facts = [
            question("root", title: "How do I become my best self?", parent: nil, extracts: 5,
                     concepts: ["Discipline", "Identity"]),
            question("child", title: "What role does sleep play in becoming my best self?", parent: "root",
                     extracts: 3, concepts: ["Sleep", "Identity"])
        ]
        XCTAssertTrue(InquiryGardenerSignals.proposals(facts: facts).isEmpty)
    }

    // MARK: - Promotion

    func testMassAndDriftPromotesAnOutgrownChild() {
        let facts = [
            question("root", title: "How do I become my best self?", parent: nil, extracts: 6,
                     concepts: ["Discipline", "Identity", "Habits"]),
            question("sleep", title: "How does sleep architecture work?", parent: "root", extracts: 14,
                     concepts: ["REM cycles", "Adenosine", "Circadian rhythm", "Chronotypes"])
        ]
        let proposals = InquiryGardenerSignals.proposals(facts: facts)
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.kind, .promote)
        XCTAssertEqual(proposals.first?.questionUUID, "sleep")
        XCTAssertEqual(proposals.first?.key, "promote:sleep")
    }

    func testHighOverlapChildStaysNestedDespiteMass() {
        // Big but still feeding the parent's territory — a true decomposition.
        let facts = [
            question("root", title: "How do I become my best self?", parent: nil, extracts: 6,
                     concepts: ["Discipline", "Identity", "Habits"]),
            question("habits", title: "Which habits compound the most?", parent: "root", extracts: 14,
                     concepts: ["Habits", "Discipline", "Identity"])
        ]
        XCTAssertTrue(InquiryGardenerSignals.proposals(facts: facts).isEmpty)
    }

    func testGravityPromotesAFrameEvenWithoutDrift() {
        let facts = [
            question("root", title: "How do I become my best self?", parent: nil, extracts: 20,
                     concepts: ["Discipline"]),
            question("env", title: "What role does environment play?", parent: "root", extracts: 4,
                     concepts: ["Discipline"]),
            question("env1", title: "How should a workspace be designed?", parent: "env", extracts: 4,
                     concepts: ["Discipline"]),
            question("env2", title: "Who you surround yourself with?", parent: "env", extracts: 4,
                     concepts: ["Discipline"])
        ]
        let proposals = InquiryGardenerSignals.proposals(facts: facts)
        XCTAssertEqual(proposals.first?.kind, .promote)
        XCTAssertEqual(proposals.first?.questionUUID, "env")
    }

    func testArchivedQuestionsNeverPropose() {
        var archived = question("sleep", title: "How does sleep architecture work?", parent: "root",
                                extracts: 20, concepts: ["REM", "Adenosine"])
        archived.isArchived = true
        let facts = [
            question("root", title: "How do I become my best self?", parent: nil, extracts: 4,
                     concepts: ["Discipline", "Identity"]),
            archived
        ]
        XCTAssertTrue(InquiryGardenerSignals.proposals(facts: facts).isEmpty)
    }

    // MARK: - Merge

    func testConvergedTitlesProposeMergeIntoTheLargerThread() {
        let facts = [
            question("a", title: "How does morning sunlight affect energy levels?", parent: nil,
                     extracts: 3, concepts: []),
            question("b", title: "How does morning sunlight affect energy?", parent: nil,
                     extracts: 9, concepts: [])
        ]
        let proposals = InquiryGardenerSignals.proposals(facts: facts)
        XCTAssertEqual(proposals.first?.kind, .merge)
        XCTAssertEqual(proposals.first?.questionUUID, "a", "The smaller thread folds")
        XCTAssertEqual(proposals.first?.targetUUID, "b", "The larger thread survives")
    }

    func testAncestorAndDescendantNeverMerge() {
        let facts = [
            question("parent", title: "How does morning sunlight affect energy levels?", parent: nil,
                     extracts: 4, concepts: []),
            question("child", title: "How does morning sunlight affect energy?", parent: "parent",
                     extracts: 4, concepts: [])
        ]
        let proposals = InquiryGardenerSignals.proposals(facts: facts)
        XCTAssertFalse(proposals.contains { $0.kind == .merge })
    }

    // MARK: - Graduation

    func testTopicScaleRootProposesGraduation() {
        var facts = [
            question("big", title: "How does sleep work?", parent: nil, extracts: 10, concepts: [])
        ]
        for index in 0..<3 {
            facts.append(question("c\(index)", title: "Sleep sub-question \(index)?", parent: "big",
                                  extracts: 12, concepts: []))
        }
        let proposals = InquiryGardenerSignals.proposals(facts: facts)
        XCTAssertEqual(proposals.first?.kind, .graduate)
        XCTAssertEqual(proposals.first?.questionUUID, "big")
    }

    // MARK: - Pure helpers

    func testConceptOverlapUsesTheSmallerSide() {
        let overlap = InquiryGardenerSignals.conceptOverlap(
            ["Sleep", "REM"], ["sleep", "Habits", "Discipline", "Identity"]
        )
        XCTAssertEqual(overlap, 0.5, accuracy: 0.001)
    }

    func testTitleOverlapIgnoresQuestionScaffolding() {
        XCTAssertGreaterThanOrEqual(
            InquiryGardenerSignals.titleOverlap(
                "How does morning sunlight affect energy levels?",
                "What does morning sunlight do to energy levels?"
            ),
            0.6
        )
    }

    // MARK: - Helper

    private func question(
        _ uuid: String,
        title: String,
        parent: String?,
        extracts: Int,
        concepts: Set<String>
    ) -> InquiryGardenerSignals.QuestionFacts {
        InquiryGardenerSignals.QuestionFacts(
            uuid: uuid,
            title: title,
            parentUUID: parent,
            directExtracts: extracts,
            concepts: concepts
        )
    }
}
