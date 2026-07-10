// CosmoOS/UI/InlineAssistant/CosmoInlineEditTransaction.swift
// Transactional multi-operation apply for inline assistant proposals.
//
// The old accept-all path applied operations one at a time, each re-resolving
// against the already-mutated live text. A renumber cascade ("SLIDE 5"→"SLIDE 6",
// "SLIDE 6"→"SLIDE 7", …) then aliased: after the first op applied, the next
// op's first-match hit the line the previous op had just produced, double-
// bumping some headers and leaving others untouched — the "slides moved
// around" corruption.
//
// The transaction compiler resolves EVERY text operation against the ORIGINAL
// snapshot, simulates the applies bottom-to-top (so no application shifts the
// text an unapplied operation must locate), and rewrites each operation into a
// byte-exact, unique replacement against the working document at its apply
// moment. Providers then apply the compiled steps through their existing
// single-operation paths, in compiled order, and reproduce the simulation
// exactly — rich formatting preserved, never-block contract intact
// (unlocatable operations still degrade to live resolution / trailing append).

import Foundation

struct CosmoInlineEditTransactionPlan {
    /// Rewritten operations in apply order. Each keeps the id of the proposal
    /// operation it stands in for, so review status marking is unchanged.
    var steps: [CosmoAssistantProposalOperation] = []
    /// The plain-text result of applying every step in order — used by the
    /// validator's numbering simulation and the after-outline digest.
    var simulatedFinalText: String
    /// Operations whose originalText never located — they degrade to the
    /// never-block trailing append and are worth surfacing to the model.
    var unlocatedOperationIDs: [UUID] = []
}

enum CosmoInlineEditTransaction {
    private static let maxAnchorExpansionLines = 5

    /// Compile a set of proposal operations into an ordered, alias-proof plan
    /// against `sourceText`. Non-text operations (formatMarks, canvasPlan) pass
    /// through unchanged, ordered after the text mutations.
    static func compile(
        operations: [CosmoAssistantProposalOperation],
        sourceText: String
    ) -> CosmoInlineEditTransactionPlan {
        var located: [(operation: CosmoAssistantProposalOperation, range: Range<String.Index>, replacement: String)] = []
        var residualTextOps: [CosmoAssistantProposalOperation] = []
        var formatOps: [CosmoAssistantProposalOperation] = []
        var passthroughOps: [CosmoAssistantProposalOperation] = []
        var unlocatedIDs: [UUID] = []

        for operation in operations {
            switch operation.kind {
            case .formatMarks:
                formatOps.append(operation)
            case .canvasPlan:
                passthroughOps.append(operation)
            case .textReplacement, .structuredFieldReplacement, .textInsertion:
                guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: sourceText) else {
                    passthroughOps.append(operation)
                    continue
                }
                if placement.placementKind == .appendFallback {
                    residualTextOps.append(operation)
                    unlocatedIDs.append(operation.id)
                    continue
                }
                // Overlapping ranges cannot both be pre-resolved — the later
                // operation falls back to live resolution after the others.
                let overlaps = located.contains { existing in
                    ranges(existing.range, overlap: placement.range, in: sourceText)
                }
                if overlaps {
                    residualTextOps.append(operation)
                    continue
                }
                located.append((operation, placement.range, placement.replacementText))
            }
        }

        // Bottom-to-top: applying a lower step never shifts the offsets of the
        // (higher) steps still to come.
        located.sort { lhs, rhs in
            sourceText.distance(from: sourceText.startIndex, to: lhs.range.lowerBound)
                > sourceText.distance(from: sourceText.startIndex, to: rhs.range.lowerBound)
        }

        var working = sourceText
        var steps: [CosmoAssistantProposalOperation] = []

        for entry in located {
            // The range is still valid in `working`: every already-applied step
            // was strictly below this one.
            var segmentRange = entry.range
            var segmentOriginal: String
            var segmentProposed: String

            if segmentRange.isEmpty {
                // Insertion point (right after its anchor). Convert to a
                // replacement over the anchor so the provider applies one
                // byte-exact edit: anchor → anchor + inserted text.
                let anchorText = entry.operation.originalText ?? ""
                guard !anchorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let anchorRange = CosmoInlineDiffLocator.range(of: anchorText, in: working) else {
                    residualTextOps.append(entry.operation)
                    continue
                }
                segmentRange = anchorRange
                segmentOriginal = String(working[anchorRange])
                segmentProposed = segmentOriginal + entry.replacement
            } else {
                segmentOriginal = String(working[segmentRange])
                segmentProposed = entry.replacement
            }

            // Expand the anchor upward (stable text — applied steps are all
            // below) until it matches uniquely in the working document, so the
            // provider's first-match IS this location.
            var expansions = 0
            while !CosmoInlineDiffLocator.isUnique(segmentOriginal, in: working),
                  expansions < maxAnchorExpansionLines,
                  let expanded = expandedSegmentUpward(range: segmentRange, in: working) {
                let prefix = String(working[expanded.lowerBound..<segmentRange.lowerBound])
                segmentRange = expanded
                segmentOriginal = prefix + segmentOriginal
                segmentProposed = prefix + segmentProposed
                expansions += 1
            }

            // Still ambiguous after expansion: a provider's first-match could
            // land on a different instance than the simulation — demote to
            // live resolution instead of risking divergence.
            guard CosmoInlineDiffLocator.isUnique(segmentOriginal, in: working) else {
                residualTextOps.append(entry.operation)
                continue
            }

            var rewritten = entry.operation
            rewritten.kind = .textReplacement
            rewritten.originalText = segmentOriginal
            rewritten.proposedText = segmentProposed
            steps.append(rewritten)

            working.replaceSubrange(segmentRange, with: segmentProposed)
        }

        // Residual text ops resolve live, in order, exactly as the provider
        // will — keep the simulation faithful.
        for operation in residualTextOps {
            steps.append(operation)
            if let placement = CosmoInlineTextEditResolver.placement(for: operation, in: working) {
                if placement.placementKind == .appendFallback, !unlocatedIDs.contains(operation.id) {
                    unlocatedIDs.append(operation.id)
                }
                working.replaceSubrange(placement.range, with: placement.replacementText)
            }
        }

        // Formatting mutates appearance, never the plain text — apply after all
        // text mutations so marks land on the final wording.
        steps.append(contentsOf: formatOps)
        steps.append(contentsOf: passthroughOps)

        return CosmoInlineEditTransactionPlan(
            steps: steps,
            simulatedFinalText: working,
            unlocatedOperationIDs: unlocatedIDs
        )
    }

    private static func ranges(
        _ lhs: Range<String.Index>,
        overlap rhs: Range<String.Index>,
        in text: String
    ) -> Bool {
        if lhs.isEmpty && rhs.isEmpty { return lhs.lowerBound == rhs.lowerBound }
        if lhs.isEmpty { return rhs.contains(lhs.lowerBound) }
        if rhs.isEmpty { return lhs.contains(rhs.lowerBound) }
        return lhs.overlaps(rhs)
    }

    /// Extend a range to start one full line earlier. Returns nil at the top of
    /// the document.
    private static func expandedSegmentUpward(
        range: Range<String.Index>,
        in text: String
    ) -> Range<String.Index>? {
        guard range.lowerBound > text.startIndex else { return nil }
        // Step past the newline immediately before the segment, then to the
        // start of that previous line.
        var cursor = text.index(before: range.lowerBound)
        if text[cursor] == "\n" {
            guard cursor > text.startIndex else { return nil }
            cursor = text.index(before: cursor)
        }
        while cursor > text.startIndex, text[text.index(before: cursor)] != "\n" {
            cursor = text.index(before: cursor)
        }
        guard cursor < range.lowerBound else { return nil }
        return cursor..<range.upperBound
    }
}

// MARK: - Proposal validation + deterministic repair

struct CosmoInlineProposalValidationResult {
    var repairedOperations: [CosmoAssistantProposalOperation]
    /// Blocking problems, written for the model — returned as a structured
    /// tool error so it can fix the proposal within the same run.
    var issues: [String]
    /// Structural digest of the simulated post-apply document.
    var afterOutline: String?

    var isValid: Bool { issues.isEmpty }
}

/// Validates a staged proposal against the bound surface text BEFORE it reaches
/// review: repairs asterisk-formatting deterministically, verifies every anchor
/// locates, and simulates the full transaction to catch numbering corruption.
/// The never-block contract is untouched — validation stops garbage from being
/// staged silently; it never blocks the user's accept.
enum CosmoInlineProposalValidator {
    static func validate(
        operations: [CosmoAssistantProposalOperation],
        sourceText: String,
        summary: String?
    ) -> CosmoInlineProposalValidationResult {
        var repaired: [CosmoAssistantProposalOperation] = []
        var issues: [String] = []

        for (index, operation) in operations.enumerated() {
            var operation = operation

            if let converted = formatMarkRepair(for: operation) {
                operation = converted
            } else if introducesMarkdownEmphasis(operation) {
                issues.append(
                    "Operation \(index + 1) expresses formatting with markdown symbols (**, __, ~~) in proposedText. Use kind \"formatMarks\" with formatMark set and originalText = the exact text to format — the words must stay identical."
                )
            }

            switch operation.kind {
            case .textReplacement, .structuredFieldReplacement:
                let original = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !original.isEmpty,
                   CosmoInlineDiffLocator.range(of: operation.originalText ?? "", in: sourceText) == nil {
                    issues.append(
                        "Operation \(index + 1): originalText does not match the surface text (\"\(String(original.prefix(80)))…\"). Copy the ENTIRE target line verbatim from the active surface text."
                    )
                }
            case .textInsertion:
                let anchor = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !anchor.isEmpty,
                   CosmoInlineDiffLocator.range(of: operation.originalText ?? "", in: sourceText) == nil {
                    issues.append(
                        "Operation \(index + 1): the insertion anchor does not match the surface text (\"\(String(anchor.prefix(80)))…\"). Set originalText to an existing line copied verbatim."
                    )
                }
            case .formatMarks:
                if operation.formatMark == nil {
                    issues.append("Operation \(index + 1) is formatMarks but formatMark is missing.")
                } else if let target = operation.originalText,
                          CosmoInlineDiffLocator.range(of: target, in: sourceText) == nil {
                    issues.append(
                        "Operation \(index + 1): the formatting target does not match the surface text (\"\(String(target.prefix(80)))…\")."
                    )
                }
            case .canvasPlan:
                break
            }

            repaired.append(operation)
        }

        if let summary, isProcessNarration(summary) {
            issues.append(
                "The summary is process narration. Write it as a one-line receipt of the result state (e.g. \"Bolded all 9 slide headers — numbering runs clean 1–9.\")."
            )
        }

        var afterOutline: String?
        if issues.isEmpty {
            let plan = CosmoInlineEditTransaction.compile(operations: repaired, sourceText: sourceText)
            if let numberingIssue = slideNumberingIssue(
                original: sourceText,
                simulated: plan.simulatedFinalText
            ) {
                issues.append(numberingIssue)
            }
            afterOutline = CosmoInlineAssistantInstructionPrompt.documentOutline(for: plan.simulatedFinalText)
        }

        return CosmoInlineProposalValidationResult(
            repairedOperations: repaired,
            issues: issues,
            afterOutline: afterOutline
        )
    }

    // MARK: Asterisk → formatMarks repair

    /// A textReplacement whose proposedText is the originalText wrapped in
    /// markdown emphasis (or turned into a markdown heading) converts to the
    /// formatMarks operation the model should have emitted.
    static func formatMarkRepair(
        for operation: CosmoAssistantProposalOperation
    ) -> CosmoAssistantProposalOperation? {
        guard operation.kind == .textReplacement,
              operation.formatMark == nil,
              let original = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              let proposed = operation.proposedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !original.isEmpty, !proposed.isEmpty else {
            return nil
        }

        let wrappers: [(prefix: String, suffix: String, mark: CosmoAssistantFormatMark)] = [
            ("**", "**", .bold),
            ("__", "__", .bold),
            ("~~", "~~", .strikethrough),
            ("*", "*", .italic),
            ("_", "_", .italic)
        ]
        for wrapper in wrappers {
            if proposed == wrapper.prefix + original + wrapper.suffix {
                return converted(operation, to: wrapper.mark)
            }
        }

        let headings: [(prefix: String, mark: CosmoAssistantFormatMark)] = [
            ("### ", .heading3),
            ("## ", .heading2),
            ("# ", .heading1)
        ]
        for heading in headings {
            if proposed == heading.prefix + original {
                return converted(operation, to: heading.mark)
            }
        }

        return nil
    }

    private static func converted(
        _ operation: CosmoAssistantProposalOperation,
        to mark: CosmoAssistantFormatMark
    ) -> CosmoAssistantProposalOperation {
        var repaired = operation
        repaired.kind = .formatMarks
        repaired.formatMark = mark
        repaired.proposedText = nil
        return repaired
    }

    private static func introducesMarkdownEmphasis(
        _ operation: CosmoAssistantProposalOperation
    ) -> Bool {
        guard operation.kind == .textReplacement || operation.kind == .textInsertion,
              let proposed = operation.proposedText else {
            return false
        }
        let original = operation.originalText ?? ""
        for token in ["**", "__", "~~"] where proposed.contains(token) && !original.contains(token) {
            return true
        }
        return false
    }

    // MARK: Receipt register

    private static func isProcessNarration(_ summary: String) -> Bool {
        let lower = summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let narrationPrefixes = [
            "i have ", "i've ", "i applied", "i updated", "i staged",
            "i will ", "i'll ", "i am ", "i'm ", "as requested"
        ]
        return narrationPrefixes.contains { lower.hasPrefix($0) }
    }

    // MARK: Numbering simulation

    /// Compares the SLIDE-header number sequence before and after the simulated
    /// apply. Only DEGRADATIONS the edit itself causes are blocking — a
    /// document whose numbering was already imperfect (a pre-existing duplicate
    /// header the user typed) must never veto an unrelated body edit. The model
    /// gets the resulting outline and fixes its operations in-run.
    static func slideNumberingIssue(original: String, simulated: String) -> String? {
        let before = slideNumbers(in: original)
        let after = slideNumbers(in: simulated)
        guard !after.isEmpty else { return nil }

        // A number is a blocking duplicate only when the edit INCREASED how
        // often it appears (new collision), not when the document already had it.
        let beforeCounts = Dictionary(grouping: before, by: { $0 }).mapValues(\.count)
        let newDuplicates = Dictionary(grouping: after, by: { $0 })
            .filter { number, occurrences in
                occurrences.count > 1 && occurrences.count > (beforeCounts[number] ?? 0)
            }
            .keys
            .sorted()
        if !newDuplicates.isEmpty {
            return numberingMessage(
                "the edit introduces duplicate slide numbers (\(newDuplicates.map(String.init).joined(separator: ", ")))",
                after: after
            )
        }

        let beforeWasSequential = isSequential(before)
        if beforeWasSequential, !isSequential(after) {
            return numberingMessage("the slide numbering is no longer sequential", after: after)
        }

        return nil
    }

    private static func numberingMessage(_ problem: String, after: [Int]) -> String {
        "Applying these operations would corrupt the document: \(problem). Resulting header order: \(after.map { "SLIDE \($0)" }.joined(separator: ", ")). Renumber so every header keeps a unique, sequential integer — for series shifts, use ONE renumberSequence operation instead of individual header rewrites."
    }

    private static func slideNumbers(in text: String) -> [Int] {
        var numbers: [Int] = []
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.range(of: #"^SLIDE\s+(\d+)\b"#, options: [.regularExpression, .caseInsensitive]) {
                let digits = trimmed[match].drop { !$0.isNumber }.prefix { $0.isNumber }
                if let value = Int(digits) { numbers.append(value) }
            }
        }
        return numbers
    }

    private static func isSequential(_ numbers: [Int]) -> Bool {
        guard let first = numbers.first else { return true }
        for (offset, value) in numbers.enumerated() where value != first + offset {
            return false
        }
        return true
    }
}

// MARK: - Deterministic series expansion (renumberSequence / scoped formatMarks)

/// Expands semantic series instructions into exact per-line operations from the
/// live surface text — the document's own state decides what changes, instead
/// of trusting a model to hand-copy N mechanical header rewrites.
enum CosmoInlineSeriesExpansion {
    /// Expand a `renumberSequence` instruction into per-line textReplacements.
    /// `delta > 0` shifts numbers up (inserting an item), `delta < 0` shifts
    /// down (removing one). Returns nil when nothing in the series matches.
    static func renumberOperations(
        seriesKind: String,
        fromNumber: Int,
        delta: Int,
        throughNumber: Int? = nil,
        withinSlide: Int? = nil,
        sourceText: String,
        targetID: String,
        sourceHash: String,
        rationale: String
    ) -> [CosmoAssistantProposalOperation]? {
        guard delta != 0 else { return nil }

        let lines: [(line: String, number: Int)]
        switch seriesKind {
        case "slideHeaders":
            lines = numberedLines(in: sourceText, pattern: #"^\s*SLIDE\s+(\d+)\b"#)
        case "numberedSteps":
            let scope = withinSlide.flatMap { slideBody(number: $0, in: sourceText) } ?? sourceText
            lines = numberedLines(in: scope, pattern: #"^\s*(?:Step\s+)?(\d+)[\.\):]\s"#)
        default:
            return nil
        }

        let affected = lines.filter { entry in
            entry.number >= fromNumber && (throughNumber.map { entry.number <= $0 } ?? true)
        }
        guard !affected.isEmpty else { return nil }

        // Emit in the alias-safe order for sequential application: shifting up
        // renames bottom-first, shifting down renames top-first.
        let ordered = delta > 0
            ? affected.sorted { $0.number > $1.number }
            : affected.sorted { $0.number < $1.number }

        return ordered.compactMap { entry in
            let newNumber = entry.number + delta
            guard newNumber >= 1 else { return nil }
            guard let numberRange = entry.line.range(of: "\(entry.number)") else { return nil }
            var newLine = entry.line
            newLine.replaceSubrange(numberRange, with: "\(newNumber)")
            return CosmoAssistantProposalOperation(
                kind: .textReplacement,
                targetID: targetID,
                anchorID: nil,
                originalText: entry.line,
                proposedText: newLine,
                sourceHash: sourceHash,
                rationale: rationale
            )
        }
    }

    /// Expand a scoped formatMarks instruction ("allSlideHeaders") into one
    /// exact operation per header line.
    static func scopedFormatMarkOperations(
        scope: String,
        mark: CosmoAssistantFormatMark,
        sourceText: String,
        targetID: String,
        sourceHash: String,
        rationale: String
    ) -> [CosmoAssistantProposalOperation]? {
        guard scope == "allSlideHeaders" else { return nil }
        let headers = numberedLines(in: sourceText, pattern: #"^\s*SLIDE\s+(\d+)\b"#)
        guard !headers.isEmpty else { return nil }

        return headers.map { entry in
            CosmoAssistantProposalOperation(
                kind: .formatMarks,
                targetID: targetID,
                anchorID: nil,
                originalText: entry.line,
                proposedText: nil,
                sourceHash: sourceHash,
                rationale: rationale,
                formatMark: mark
            )
        }
    }

    private static func numberedLines(
        in text: String,
        pattern: String
    ) -> [(line: String, number: Int)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        var results: [(String, Int)] = []
        text.enumerateLines { line, _ in
            let range = NSRange(location: 0, length: (line as NSString).length)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges > 1,
                  let value = Int((line as NSString).substring(with: match.range(at: 1))) else {
                return
            }
            results.append((line, value))
        }
        return results
    }

    /// The body of slide N: from its header line to the next SLIDE header (or
    /// end of document).
    private static func slideBody(number: Int, in text: String) -> String? {
        var collecting = false
        var body: [String] = []
        text.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let headerNumber: Int?
            if let match = trimmed.range(of: #"^SLIDE\s+(\d+)\b"#, options: [.regularExpression, .caseInsensitive]) {
                headerNumber = Int(trimmed[match].drop { !$0.isNumber }.prefix { $0.isNumber })
            } else {
                headerNumber = nil
            }

            if let headerNumber {
                if collecting {
                    stop = true
                    return
                }
                collecting = headerNumber == number
                return
            }
            if collecting {
                body.append(line)
            }
        }
        return body.isEmpty ? nil : body.joined(separator: "\n")
    }
}
