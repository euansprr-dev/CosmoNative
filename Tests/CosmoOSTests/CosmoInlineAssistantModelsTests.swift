import XCTest
@testable import CosmoOS

final class CosmoInlineAssistantModelsTests: XCTestCase {
    func testOperationAcceptabilityRequiresPendingStatusAndLocatableOriginalText() {
        let source = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Launch note",
            text: "Rent: $4,556/mo",
            sourceHash: "hash-1",
            anchors: [.init(id: "line-1", label: "Line 1", utf16Start: 0, utf16Length: 15)]
        )
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "note:abc:body",
            anchorID: "line-1",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "hash-1",
            rationale: "Use the requested rent number."
        )

        // Matching hash applies.
        XCTAssertTrue(operation.canApply(against: source))
        // Already-resolved operations never re-apply.
        XCTAssertFalse(operation.marked(.accepted).canApply(against: source))
        // A stale hash still applies while the original text is locatable in the surface…
        XCTAssertTrue(operation.canApply(against: source.withSourceHash("hash-2")))
        // …but once the targeted text is gone, it can no longer apply.
        let movedSource = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Launch note",
            text: "Rent: $9,001/mo",
            sourceHash: "hash-2",
            anchors: []
        )
        XCTAssertFalse(operation.canApply(against: movedSource))
    }

    func testDiffEngineBuildsParagraphReplacementHunks() {
        let hunks = CosmoInlineAssistantDiffEngine.hunks(
            original: "Rent: $4,556/mo\nExpenses: $1,800/mo",
            proposed: "Rent: $5,000/mo\nExpenses: $2,100/mo"
        )

        XCTAssertEqual(hunks.map(\.kind), [.removed, .added, .removed, .added])
        XCTAssertEqual(hunks[0].text, "Rent: $4,556/mo")
        XCTAssertEqual(hunks[1].text, "Rent: $5,000/mo")
        XCTAssertEqual(hunks[2].text, "Expenses: $1,800/mo")
        XCTAssertEqual(hunks[3].text, "Expenses: $2,100/mo")
    }

    func testLocatorMatchesAcrossWhitespaceDrift() {
        let haystack = "Slide 7\n\n1/7   Find an in-demand market\nSearch rooms."
        // The model echoes the original line with collapsed/altered whitespace.
        let range = CosmoInlineDiffLocator.range(of: "1/7 Find an in-demand market", in: haystack)
        XCTAssertNotNil(range)
        if let range {
            XCTAssertEqual(String(haystack[range]), "1/7   Find an in-demand market")
        }
        XCTAssertNil(CosmoInlineDiffLocator.range(of: "a line that is not present", in: haystack))
    }

    func testLocatorMatchesAcrossSmartPunctuation() {
        // Document uses curly quotes and an em dash; the model echoes straight ones.
        let haystack = "He said \u{201C}rooms for rent\u{201D} \u{2014} every time."
        let range = CosmoInlineDiffLocator.range(of: "\"rooms for rent\" - every time.", in: haystack)
        XCTAssertNotNil(range)
        if let range {
            XCTAssertEqual(String(haystack[range]), "\u{201C}rooms for rent\u{201D} \u{2014} every time.")
        }
    }

    func testReviewBuilderProducesOrderedSegmentsFromLiveText() {
        let source = "Intro line.\nRent: $4,556/mo\nOutro line."
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "t",
            anchorID: "a",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "h",
            rationale: "Update rent."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        XCTAssertEqual(segments.count, 3)
        guard case let .change(change) = segments[1] else {
            return XCTFail("Expected the middle segment to be the change block")
        }
        XCTAssertEqual(change.removedLines, ["Rent: $4,556/mo"])
        XCTAssertEqual(change.addedLines, ["Rent: $5,000/mo"])
        XCTAssertFalse(change.isConflicted)
    }

    func testReviewBuilderMarksUnlocatableOperationsConflicted() {
        let source = "Only this text exists."
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "t",
            anchorID: "a",
            originalText: "Something that is not here",
            proposedText: "Replacement",
            sourceHash: "h",
            rationale: "Stale edit."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        guard case let .change(change) = segments.last else {
            return XCTFail("Expected a trailing conflicted change block")
        }
        XCTAssertTrue(change.isConflicted)
    }

    func testEmptyOriginalReplacementIsAdditiveNotConflicted() {
        // The agent's "fill in the slides" case: a replacement with no original text.
        let source = "Existing line one.\nExisting line two."
        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: "t",
            anchorID: nil,
            originalText: "",
            proposedText: "Brand new content.",
            sourceHash: "h",
            rationale: "Add content."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        guard case let .change(change) = segments.last else {
            return XCTFail("Expected a trailing additive change block")
        }
        XCTAssertFalse(change.isConflicted, "Empty original must not be flagged Outdated")
        XCTAssertEqual(change.removedLines, [])
        XCTAssertEqual(change.addedLines, ["Brand new content."])
        // And it must be acceptable against the live surface (additive content always applies).
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "s", targetID: "t", kind: .text, title: "T",
            text: source, sourceHash: "live", anchors: []
        )
        XCTAssertTrue(operation.canApply(against: snapshot))
    }

    func testAnchoredInsertionIsPlacedAfterAnchorNotAtEnd() {
        let source = "SLIDE 7\nSLIDE 8\nSLIDE 9"
        let operation = CosmoAssistantProposalOperation(
            kind: .textInsertion,
            targetID: "t",
            anchorID: nil,
            originalText: "SLIDE 7",
            proposedText: "Find an in-demand market.",
            sourceHash: "h",
            rationale: "Fill slide 7."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        // unchanged("SLIDE 7") / change(added) / unchanged("\nSLIDE 8\nSLIDE 9")
        XCTAssertEqual(segments.count, 3)
        guard case let .change(change) = segments[1] else {
            return XCTFail("Expected the added content to sit right after the anchor, not at the end")
        }
        XCTAssertEqual(change.removedLines, [])
        XCTAssertEqual(change.addedLines, ["Find an in-demand market."])
        guard case let .unchanged(_, trailing) = segments[2] else {
            return XCTFail("Expected trailing unchanged slides")
        }
        XCTAssertTrue(trailing.contains("SLIDE 8"))
    }

    func testSlideHeaderFallbackKeepsStaleHeaderReplacementReviewableInline() {
        let source = """
        SLIDE 4
        Here is the setup.
        --
        SLIDE 5
        --
        SLIDE 6
        --
        """
        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: "t",
            anchorID: "slide-5",
            originalText: "SLIDE 6\n--",
            proposedText: "SLIDE 5\nFirst, I found an owner-listed home on Zillow.",
            sourceHash: "stale",
            rationale: "Convert step 1 to first person."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        let changes = segments.compactMap { segment -> CosmoInlineDiffChange? in
            if case let .change(change) = segment { return change }
            return nil
        }
        XCTAssertEqual(changes.count, 1)
        XCTAssertFalse(changes[0].isConflicted)
        XCTAssertEqual(changes[0].addedLines, [
            "SLIDE 5",
            "First, I found an owner-listed home on Zillow."
        ])
        let rendered = segments.map { segment -> String in
            switch segment {
            case let .unchanged(_, text):
                return text
            case let .change(change):
                return change.addedLines.joined(separator: "\n")
            }
        }.joined()
        XCTAssertTrue(rendered.contains("SLIDE 6\n--"))
    }
}
