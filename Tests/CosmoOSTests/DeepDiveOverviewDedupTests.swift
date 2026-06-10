// CosmoOS/Tests/CosmoOSTests/DeepDiveOverviewDedupTests.swift

import XCTest
@testable import CosmoOS

final class DeepDiveOverviewDedupTests: XCTestCase {

    private func question(_ uuid: String, title: String, updatedAt: String = "2026-06-01T00:00:00Z") -> Atom {
        var atom = Atom.new(type: .question, title: title)
        atom.uuid = uuid
        atom.updatedAt = updatedAt
        return atom
    }

    func testCaseAndPunctuationVariantsCollapse() {
        let questions = [
            question("q-1", title: "What is pranayama?"),
            question("q-2", title: "what is pranayama"),
            question("q-3", title: "What is Pranayama?!")
        ]
        let deduped = DeepDiveOverviewViewModel.dedupeQuestions(questions, extractCount: { _ in 0 })
        XCTAssertEqual(deduped.count, 1)
    }

    func testRichestCopyWins() {
        let questions = [
            question("q-empty", title: "What is pranayama?"),
            question("q-rich", title: "What is pranayama")
        ]
        let counts = ["q-empty": 0, "q-rich": 7]
        let deduped = DeepDiveOverviewViewModel.dedupeQuestions(questions, extractCount: { counts[$0.uuid] ?? 0 })
        XCTAssertEqual(deduped.first?.uuid, "q-rich")
    }

    func testDistinctQuestionsAllSurviveInOrder() {
        let questions = [
            question("q-1", title: "What is pranayama?"),
            question("q-2", title: "How does CO2 tolerance adapt?"),
            question("q-3", title: "Why was breath linked to spirit?")
        ]
        let deduped = DeepDiveOverviewViewModel.dedupeQuestions(questions, extractCount: { _ in 0 })
        XCTAssertEqual(deduped.map(\.uuid), ["q-1", "q-2", "q-3"])
    }

    func testEmptyTitlesAreDropped() {
        let questions = [question("q-1", title: "  ?  "), question("q-2", title: "Real question?")]
        let deduped = DeepDiveOverviewViewModel.dedupeQuestions(questions, extractCount: { _ in 0 })
        XCTAssertEqual(deduped.map(\.uuid), ["q-2"])
    }
}
