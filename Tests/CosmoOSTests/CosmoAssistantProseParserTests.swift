import XCTest
@testable import CosmoOS

/// Document pills in prose: markers and title auto-links become pill segments;
/// everything ambiguous stays plain text. False positives are worse than misses.
final class CosmoAssistantProseParserTests: XCTestCase {
    private let pricing = CosmoAssistantSourceRef(uuid: "uuid-pricing", title: "Pricing psychology", kind: "research")
    private let retention = CosmoAssistantSourceRef(uuid: "uuid-retention", title: "Retention thread", kind: "content")

    func testExplicitMarkerBecomesPill() {
        let result = CosmoAssistantProseParser.parse(
            answer: "The hook leans on [[uuid-pricing]] for its claim.",
            sourceRefs: [pricing]
        )

        XCTAssertEqual(result.segments, [
            .text("The hook leans on "),
            .pill(pricing),
            .text(" for its claim.")
        ])
        XCTAssertEqual(result.linkedRefUUIDs, ["uuid-pricing"])
    }

    func testUnknownMarkerIsStrippedWithoutResidue() {
        let result = CosmoAssistantProseParser.parse(
            answer: "See [[no-such-uuid]] the research.",
            sourceRefs: [pricing]
        )

        // Marker gone, seam collapsed to a single space — but the title
        // "Pricing psychology" doesn't appear, so no pill either.
        let flattened = result.segments.compactMap { segment -> String? in
            if case .text(let text) = segment { return text }
            return nil
        }.joined()
        XCTAssertEqual(flattened, "See the research.")
        XCTAssertTrue(result.linkedRefUUIDs.isEmpty)
    }

    func testTitleAutoLinksFirstOccurrenceOnly() {
        let result = CosmoAssistantProseParser.parse(
            answer: "Pricing psychology drives this. Pricing psychology appears twice.",
            sourceRefs: [pricing]
        )

        let pillCount = result.segments.filter {
            if case .pill = $0 { return true }
            return false
        }.count
        XCTAssertEqual(pillCount, 1)
        XCTAssertEqual(result.segments.first, .pill(pricing))
        XCTAssertEqual(result.segments.last, .text(" drives this. Pricing psychology appears twice."))
    }

    func testLongestTitleWinsOverlap() {
        let short = CosmoAssistantSourceRef(uuid: "uuid-short", title: "Pricing", kind: "note")
        let result = CosmoAssistantProseParser.parse(
            answer: "Pricing psychology explains the gap.",
            sourceRefs: [short, pricing]
        )

        XCTAssertEqual(result.segments.first, .pill(pricing))
        // The shorter title has no remaining standalone occurrence.
        XCTAssertEqual(result.linkedRefUUIDs, ["uuid-pricing"])
    }

    func testWordBoundariesPreventMidWordLinks() {
        let notes = CosmoAssistantSourceRef(uuid: "uuid-notes", title: "Notes", kind: "note")
        let result = CosmoAssistantProseParser.parse(
            answer: "Notesworthy ideas — but your Notes say otherwise.",
            sourceRefs: [notes]
        )

        XCTAssertEqual(result.segments, [
            .text("Notesworthy ideas — but your "),
            .pill(notes),
            .text(" say otherwise.")
        ])
    }

    func testMatchingIsCaseInsensitive() {
        let result = CosmoAssistantProseParser.parse(
            answer: "the pricing psychology angle works.",
            sourceRefs: [pricing]
        )

        XCTAssertEqual(result.segments[1], .pill(pricing))
        XCTAssertEqual(result.segments.first, .text("the "))
    }

    func testShortAndUntitledTitlesNeverAutoLink() {
        let tiny = CosmoAssistantSourceRef(uuid: "uuid-tiny", title: "Q3", kind: "note")
        let untitled = CosmoAssistantSourceRef(uuid: "uuid-untitled", title: "Untitled", kind: "note")
        let result = CosmoAssistantProseParser.parse(
            answer: "Q3 went fine; the Untitled doc says so.",
            sourceRefs: [tiny, untitled]
        )

        XCTAssertEqual(result.segments, [.text("Q3 went fine; the Untitled doc says so.")])
        XCTAssertTrue(result.linkedRefUUIDs.isEmpty)
    }

    func testNoRefsPassesAnswerThrough() {
        let result = CosmoAssistantProseParser.parse(answer: "Plain take.", sourceRefs: nil)
        XCTAssertEqual(result.segments, [.text("Plain take.")])
        XCTAssertTrue(result.linkedRefUUIDs.isEmpty)
    }

    func testMarkerPlusTitleInTextYieldsExactlyOnePill() {
        let result = CosmoAssistantProseParser.parse(
            answer: "[[uuid-pricing]] is the anchor — Pricing psychology covers the rest.",
            sourceRefs: [pricing]
        )

        let pillCount = result.segments.filter {
            if case .pill = $0 { return true }
            return false
        }.count
        XCTAssertEqual(pillCount, 1, "A marker-linked ref must not auto-link its title again")
    }

    func testMultipleRefsLinkAcrossSegments() {
        let result = CosmoAssistantProseParser.parse(
            answer: "Pricing psychology pairs with the Retention thread here.",
            sourceRefs: [pricing, retention]
        )

        XCTAssertEqual(result.segments, [
            .pill(pricing),
            .text(" pairs with the "),
            .pill(retention),
            .text(" here.")
        ])
        XCTAssertEqual(result.linkedRefUUIDs, ["uuid-pricing", "uuid-retention"])
    }

    func testPunctuationAdjacentTitleStillLinks() {
        let result = CosmoAssistantProseParser.parse(
            answer: "It's all in “Pricing psychology”.",
            sourceRefs: [pricing]
        )

        XCTAssertEqual(result.segments, [
            .text("It's all in “"),
            .pill(pricing),
            .text("”.")
        ])
    }

    func testEmptyAnswerProducesNoSegments() {
        let result = CosmoAssistantProseParser.parse(answer: "", sourceRefs: [pricing])
        XCTAssertTrue(result.segments.isEmpty)
    }

    func testStreamingDisplayResolvesMarkersAndHidesTrailingPartial() {
        XCTAssertEqual(
            CosmoAssistantProseParser.streamingDisplayText(
                for: "See [[uuid-pricing]] for the claim, plus [[",
                sourceRefs: [pricing]
            ),
            "See Pricing psychology for the claim, plus "
        )
        XCTAssertEqual(
            CosmoAssistantProseParser.streamingDisplayText(for: "Plain text so far", sourceRefs: [pricing]),
            "Plain text so far"
        )
        // Unknown markers vanish (cheap path; finalize cleans the seam properly).
        XCTAssertFalse(
            CosmoAssistantProseParser.streamingDisplayText(for: "See [[nope]] now", sourceRefs: [pricing])
                .contains("[[")
        )
    }
}
