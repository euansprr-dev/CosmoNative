import XCTest
@testable import CosmoOS

final class CosmoInlineEditTransactionTests: XCTestCase {
    private func slideDeck(count: Int) -> String {
        (1...count).map { number in
            """
            SLIDE \(number)
            Body line for slide \(number) — the copy the user wrote.
            """
        }.joined(separator: "\n\n")
    }

    private func replacement(
        _ original: String,
        _ proposed: String,
        target: String = "content:deck:draft"
    ) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: target,
            anchorID: nil,
            originalText: original,
            proposedText: proposed,
            sourceHash: "hash",
            rationale: "test"
        )
    }

    // MARK: - The resolver hijack (renumber ops touched the WRONG slide)

    func testRenumberReplacementLocatesItsOwnHeaderNotTheDestinationSlide() {
        let deck = slideDeck(count: 8)
        let operation = replacement("SLIDE 5", "SLIDE 6")

        let placement = CosmoInlineTextEditResolver.placement(for: operation, in: deck)

        XCTAssertNotNil(placement)
        XCTAssertEqual(placement?.placementKind, .located)
        // The located range must be slide 5's header — the old slide-header
        // fallback rewrote the EXISTING slide 6 header instead.
        let located = String(deck[placement!.range])
        XCTAssertTrue(located.contains("SLIDE 5"))
        XCTAssertFalse(located.contains("SLIDE 6"))
    }

    // MARK: - Transaction compile: alias-proof renumber cascades

    func testAscendingRenumberCascadeCompilesWithoutAliasing() {
        let deck = slideDeck(count: 6)
        // A naive model emits the cascade top-down — the old sequential apply
        // then double-bumped headers because each op re-resolved against
        // already-renamed text.
        let operations = (3...6).map { replacement("SLIDE \($0)", "SLIDE \($0 + 1)") }

        let plan = CosmoInlineEditTransaction.compile(operations: operations, sourceText: deck)

        let numbers = slideNumbers(in: plan.simulatedFinalText)
        XCTAssertEqual(numbers, [1, 2, 4, 5, 6, 7])
        XCTAssertTrue(plan.unlocatedOperationIDs.isEmpty)
        // Every body line stays under its (renamed) header — nothing moved.
        XCTAssertTrue(plan.simulatedFinalText.contains("SLIDE 4\nBody line for slide 3"))
        XCTAssertTrue(plan.simulatedFinalText.contains("SLIDE 7\nBody line for slide 6"))
    }

    func testCompiledStepsApplySequentiallyThroughAFirstMatchProviderWithoutCorruption() {
        // Simulates exactly what a provider does: re-locate each step's
        // originalText in the LIVE text (first match) and replace. The compiled
        // plan must survive this without aliasing.
        let deck = slideDeck(count: 6)
        let operations = (3...6).map { replacement("SLIDE \($0)", "SLIDE \($0 + 1)") }
        let plan = CosmoInlineEditTransaction.compile(operations: operations, sourceText: deck)

        var live = deck
        for step in plan.steps {
            guard let placement = CosmoInlineTextEditResolver.placement(for: step, in: live) else {
                XCTFail("compiled step failed to locate")
                continue
            }
            XCTAssertNotEqual(placement.placementKind, .appendFallback, "compiled step degraded to append")
            live.replaceSubrange(placement.range, with: placement.replacementText)
        }

        XCTAssertEqual(slideNumbers(in: live), [1, 2, 4, 5, 6, 7])
        XCTAssertEqual(live, plan.simulatedFinalText, "provider apply must reproduce the simulation")
    }

    func testInsertionPlusRenumberKeepsSequenceCleanEndToEnd() {
        let deck = slideDeck(count: 26)
        var operations = CosmoInlineSeriesExpansion.renumberOperations(
            seriesKind: "slideHeaders",
            fromNumber: 7,
            delta: 1,
            sourceText: deck,
            targetID: "content:deck:draft",
            sourceHash: "hash",
            rationale: "make room for the new slide"
        )!
        operations.append(CosmoAssistantProposalOperation(
            kind: .textInsertion,
            targetID: "content:deck:draft",
            anchorID: nil,
            originalText: "Body line for slide 6 — the copy the user wrote.",
            proposedText: "SLIDE 7\nThe brand-new slide the user asked for.",
            sourceHash: "hash",
            rationale: "insert the new slide"
        ))

        let plan = CosmoInlineEditTransaction.compile(operations: operations, sourceText: deck)

        XCTAssertEqual(slideNumbers(in: plan.simulatedFinalText), Array(1...27))
        XCTAssertTrue(plan.simulatedFinalText.contains("The brand-new slide the user asked for."))
        XCTAssertTrue(plan.unlocatedOperationIDs.isEmpty)
        // Old slide 7's body now lives under SLIDE 8 — moved number, not moved copy.
        XCTAssertTrue(plan.simulatedFinalText.contains("SLIDE 8\nBody line for slide 7"))
    }

    func testRepeatedLinesInDifferentSlidesBothGetTheirEdits() {
        let deck = """
        SLIDE 1
        Step 1: buy the property
        Step 2: rent it out

        SLIDE 2
        Step 1: buy the property
        Step 2: refinance
        """
        // Both ops target the same repeated line — the first locates, the
        // second overlaps and degrades to live re-resolution, which lands on
        // the remaining instance after the first applied.
        let operations = [
            replacement("Step 1: buy the property", "Step 1: buy the duplex"),
            replacement("Step 1: buy the property", "Step 1: buy the fourplex")
        ]

        let plan = CosmoInlineEditTransaction.compile(operations: operations, sourceText: deck)

        XCTAssertTrue(plan.simulatedFinalText.contains("buy the duplex"))
        XCTAssertTrue(plan.simulatedFinalText.contains("buy the fourplex"))
        XCTAssertFalse(plan.simulatedFinalText.contains("Step 1: buy the property"))
    }

    func testCompilePreservesOperationIDs() {
        let deck = slideDeck(count: 3)
        let operation = replacement("SLIDE 2", "SLIDE 3")
        let plan = CosmoInlineEditTransaction.compile(operations: [operation], sourceText: deck)
        XCTAssertEqual(plan.steps.first?.id, operation.id)
    }

    // MARK: - Validator: asterisk repair

    func testValidatorConvertsAsteriskBoldIntoFormatMarks() {
        let deck = slideDeck(count: 3)
        let asteriskBold = replacement("SLIDE 2", "**SLIDE 2**")

        let result = CosmoInlineProposalValidator.validate(
            operations: [asteriskBold],
            sourceText: deck,
            summary: "Bolded slide 2's header."
        )

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.repairedOperations.first?.kind, .formatMarks)
        XCTAssertEqual(result.repairedOperations.first?.formatMark, .bold)
        XCTAssertNil(result.repairedOperations.first?.proposedText)
        XCTAssertEqual(result.repairedOperations.first?.id, asteriskBold.id)
    }

    func testValidatorFlagsPartialMarkdownEmphasisIntroduction() {
        let deck = slideDeck(count: 3)
        let sneaky = replacement(
            "Body line for slide 2 — the copy the user wrote.",
            "Body line for **slide 2** — the copy the user wrote."
        )

        let result = CosmoInlineProposalValidator.validate(
            operations: [sneaky],
            sourceText: deck,
            summary: "Emphasized slide 2."
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.first?.contains("formatMarks") == true)
    }

    // MARK: - Validator: anchors must locate

    func testValidatorRejectsUnlocatableOriginalText() {
        let deck = slideDeck(count: 3)
        let phantom = replacement("This line does not exist anywhere", "New text")

        let result = CosmoInlineProposalValidator.validate(
            operations: [phantom],
            sourceText: deck,
            summary: "Edit."
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.first?.contains("does not match the surface text") == true)
    }

    // MARK: - Validator: numbering simulation

    func testValidatorCatchesDuplicateNumberingBeforeStaging() {
        let deck = slideDeck(count: 6)
        // Bump slide 5 to 6 without touching the real slide 6 → duplicate.
        let result = CosmoInlineProposalValidator.validate(
            operations: [replacement("SLIDE 5", "SLIDE 6")],
            sourceText: deck,
            summary: "Renumbered."
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.first?.contains("duplicate slide numbers") == true)
        XCTAssertTrue(result.issues.first?.contains("renumberSequence") == true)
    }

    func testValidatorToleratesPreExistingDuplicateHeaders() {
        // The user's own document already has two SLIDE 4 headers (their typo).
        // An unrelated body edit must NOT be vetoed for a flaw it didn't cause
        // — this exact case blocked a real "fill in the number" edit.
        let deck = """
        SLIDE 3
        You make $850-$1,200 per bed...

        SLIDE 4
        There are X americans in need of transitional housing...

        SLIDE 4
        And this is why your local county will bring you residents

        SLIDE 5
        Luckily, it's stupid simple:
        """
        let result = CosmoInlineProposalValidator.validate(
            operations: [replacement(
                "There are X americans in need of transitional housing...",
                "There are ~40 million americans in need of transitional housing..."
            )],
            sourceText: deck,
            summary: "Filled in the Slide 4 number — ~40 million."
        )

        XCTAssertTrue(result.isValid, result.issues.joined(separator: " | "))
    }

    func testValidatorAcceptsCleanRenumberAndReturnsOutline() {
        let deck = slideDeck(count: 4)
        let operations = CosmoInlineSeriesExpansion.renumberOperations(
            seriesKind: "slideHeaders",
            fromNumber: 3,
            delta: 1,
            sourceText: deck,
            targetID: "t",
            sourceHash: "h",
            rationale: "shift"
        )! + [CosmoAssistantProposalOperation(
            kind: .textInsertion,
            targetID: "t",
            anchorID: nil,
            originalText: "Body line for slide 2 — the copy the user wrote.",
            proposedText: "SLIDE 3\nNew slide body.",
            sourceHash: "h",
            rationale: "insert"
        )]

        let result = CosmoInlineProposalValidator.validate(
            operations: operations,
            sourceText: deck,
            summary: "Inserted the new slide 3 — numbering runs clean 1–5."
        )

        XCTAssertTrue(result.isValid, result.issues.joined(separator: " | "))
        XCTAssertNotNil(result.afterOutline)
        XCTAssertTrue(result.afterOutline!.contains("SLIDE 5"))
    }

    // MARK: - Validator: receipt register

    func testValidatorRejectsProcessNarrationSummary() {
        let deck = slideDeck(count: 2)
        let result = CosmoInlineProposalValidator.validate(
            operations: [replacement("SLIDE 2", "SLIDE 2 — The Payoff")],
            sourceText: deck,
            summary: "I have staged the requested changes to your document."
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.first?.contains("receipt") == true)
    }

    // MARK: - Series expansion

    func testRenumberSequenceExpandsSlideHeadersInAliasSafeOrder() {
        let deck = slideDeck(count: 5)
        let operations = CosmoInlineSeriesExpansion.renumberOperations(
            seriesKind: "slideHeaders",
            fromNumber: 3,
            delta: 1,
            sourceText: deck,
            targetID: "t",
            sourceHash: "h",
            rationale: "shift"
        )

        XCTAssertEqual(operations?.count, 3)
        // Shifting up renames bottom-first so even a naive sequential apply is safe.
        XCTAssertEqual(operations?.first?.originalText, "SLIDE 5")
        XCTAssertEqual(operations?.first?.proposedText, "SLIDE 6")
        XCTAssertEqual(operations?.last?.originalText, "SLIDE 3")
        XCTAssertEqual(operations?.last?.proposedText, "SLIDE 4")
    }

    func testRenumberSequenceExpandsNumberedStepsWithinASlide() {
        let deck = """
        SLIDE 1
        Step 1: find the deal
        Step 2: run the numbers
        Step 3: close

        SLIDE 2
        Step 1: unrelated other list
        """
        let operations = CosmoInlineSeriesExpansion.renumberOperations(
            seriesKind: "numberedSteps",
            fromNumber: 2,
            delta: 1,
            withinSlide: 1,
            sourceText: deck,
            targetID: "t",
            sourceHash: "h",
            rationale: "make room"
        )

        XCTAssertEqual(operations?.count, 2)
        XCTAssertEqual(operations?.first?.originalText, "Step 3: close")
        XCTAssertEqual(operations?.first?.proposedText, "Step 4: close")
        // Slide 2's list is untouched.
        XCTAssertFalse(operations!.contains { $0.originalText?.contains("unrelated") == true })
    }

    func testScopedFormatMarksExpandToEveryHeader() {
        let deck = slideDeck(count: 26)
        let operations = CosmoInlineSeriesExpansion.scopedFormatMarkOperations(
            scope: "allSlideHeaders",
            mark: .bold,
            sourceText: deck,
            targetID: "t",
            sourceHash: "h",
            rationale: "bold all"
        )

        XCTAssertEqual(operations?.count, 26)
        XCTAssertTrue(operations!.allSatisfy { $0.kind == .formatMarks && $0.formatMark == .bold })
        XCTAssertEqual(operations?.first?.originalText, "SLIDE 1")
    }

    // MARK: - The user's bug, end to end

    func testRenumberAndBoldAllHeadersOnTwentySixSlidesStaysClean() {
        let deck = slideDeck(count: 26)
        var operations = CosmoInlineSeriesExpansion.renumberOperations(
            seriesKind: "slideHeaders",
            fromNumber: 10,
            delta: 1,
            sourceText: deck,
            targetID: "t",
            sourceHash: "h",
            rationale: "make room"
        )!
        operations.append(CosmoAssistantProposalOperation(
            kind: .textInsertion,
            targetID: "t",
            anchorID: nil,
            originalText: "Body line for slide 9 — the copy the user wrote.",
            proposedText: "SLIDE 10\nThe extra info slide.",
            sourceHash: "h",
            rationale: "insert"
        ))
        operations.append(contentsOf: CosmoInlineSeriesExpansion.scopedFormatMarkOperations(
            scope: "allSlideHeaders",
            mark: .bold,
            sourceText: deck,
            targetID: "t",
            sourceHash: "h",
            rationale: "bold all"
        )!)

        let validation = CosmoInlineProposalValidator.validate(
            operations: operations,
            sourceText: deck,
            summary: "Inserted slide 10 and bolded all 27 headers — numbering runs clean 1–27."
        )
        XCTAssertTrue(validation.isValid, validation.issues.joined(separator: " | "))

        let plan = CosmoInlineEditTransaction.compile(
            operations: validation.repairedOperations,
            sourceText: deck
        )

        XCTAssertEqual(slideNumbers(in: plan.simulatedFinalText), Array(1...27))
        // No literal asterisks anywhere, no content dumped at the bottom.
        XCTAssertFalse(plan.simulatedFinalText.contains("**"))
        XCTAssertTrue(plan.simulatedFinalText.hasSuffix("Body line for slide 26 — the copy the user wrote."))
        // Every original body line survived exactly once.
        for number in 1...26 {
            let needle = "Body line for slide \(number) — the copy the user wrote."
            XCTAssertNotNil(plan.simulatedFinalText.range(of: needle), "slide \(number) body lost")
        }
    }

    // MARK: - Helpers

    private func slideNumbers(in text: String) -> [Int] {
        var numbers: [Int] = []
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^SLIDE\s+\d+$"#, options: .regularExpression) != nil else { return }
            numbers.append(Int(trimmed.drop { !$0.isNumber }) ?? -1)
        }
        return numbers
    }
}
