// CosmoOS/Tests/CosmoOSTests/InquiryNotesGroupingTests.swift
// Pure grouping logic for the destination-grouped notes rail.

import XCTest
@testable import CosmoOS

final class InquiryNotesGroupingTests: XCTestCase {

    private func extract(
        _ uuid: String,
        body: String,
        kind: ExtractKind = .note,
        questionUUID: String?,
        concepts: [String] = [],
        committedAt: String = "2026-06-10T00:00:00Z",
        status: ExtractStatus = .committed
    ) -> Atom {
        var atom = Atom.new(type: .extract, title: String(body.prefix(40)), body: body)
        atom.uuid = uuid
        atom = atom.withMetadata(ExtractMetadata(
            kind: kind,
            parentSessionUUID: "session-1",
            parentQuestionUUID: questionUUID,
            status: status,
            committedAt: committedAt,
            conceptNames: concepts.isEmpty ? nil : concepts
        ))
        return atom
    }

    private func titles(_ uuid: String?) -> String {
        switch uuid {
        case "q-1": return "What is pranayama?"
        case "q-2": return "How does CO2 tolerance adapt?"
        default: return "Unassigned"
        }
    }

    func testGroupsByQuestionWithActiveFirst() {
        let groups = InquiryNotesGrouping.groups(
            extracts: [
                extract("e-1", body: "About CO2", questionUUID: "q-2", committedAt: "2026-06-10T12:00:00Z"),
                extract("e-2", body: "About pranayama", questionUUID: "q-1", committedAt: "2026-06-10T08:00:00Z")
            ],
            captures: [],
            activeQuestionUUID: "q-1",
            questionTitle: titles
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].questionUUID, "q-1")   // Active pinned first despite older item
        XCTAssertEqual(groups[0].title, "What is pranayama?")
        XCTAssertEqual(groups[1].questionUUID, "q-2")
    }

    func testItemsWithinGroupAreNewestFirst() {
        let groups = InquiryNotesGrouping.groups(
            extracts: [
                extract("e-old", body: "older", questionUUID: "q-1", committedAt: "2026-06-09T00:00:00Z"),
                extract("e-new", body: "newer", questionUUID: "q-1", committedAt: "2026-06-10T00:00:00Z")
            ],
            captures: [],
            activeQuestionUUID: "q-1",
            questionTitle: titles
        )
        XCTAssertEqual(groups.first?.items.map(\.feedId), ["extract-e-new", "extract-e-old"])
    }

    func testCapturesJoinActiveQuestionGroupWhenUnattached() {
        let capture = SessionCapture(body: "A floating thought", source: .type)
        let groups = InquiryNotesGrouping.groups(
            extracts: [extract("e-1", body: "Saved", questionUUID: "q-1")],
            captures: [capture],
            activeQuestionUUID: "q-1",
            questionTitle: titles
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.items.count, 2)
    }

    func testConceptCountsTallied() {
        let groups = InquiryNotesGrouping.groups(
            extracts: [
                extract("e-1", body: "a", questionUUID: "q-1", concepts: ["Pranayama"]),
                extract("e-2", body: "b", questionUUID: "q-1", concepts: ["Pranayama", "Vagal tone"])
            ],
            captures: [],
            activeQuestionUUID: "q-1",
            questionTitle: titles
        )
        let counts = groups.first?.conceptCounts ?? []
        XCTAssertEqual(counts.first?.name, "Pranayama")
        XCTAssertEqual(counts.first?.count, 2)
        XCTAssertEqual(counts.count, 2)
    }

    func testProvisionalFlagMapsFromTemporaryStatus() {
        let provisional = InquiryNoteFeedItem.extract(
            extract("e-1", body: "pending", questionUUID: "q-1", status: .temporary)
        )
        let settled = InquiryNoteFeedItem.extract(
            extract("e-2", body: "done", questionUUID: "q-1", status: .committed)
        )
        XCTAssertTrue(provisional.isProvisional)
        XCTAssertFalse(settled.isProvisional)
    }
}
