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

        issues.append(contentsOf: structuralIssues(operations: repaired, sourceText: sourceText))

        var afterOutline: String?
        if issues.isEmpty {
            let plan = CosmoInlineEditTransaction.compile(operations: repaired, sourceText: sourceText)
            if let numberingIssue = slideNumberingIssue(
                original: sourceText,
                simulated: plan.simulatedFinalText
            ) {
                issues.append(numberingIssue)
            }
            issues.append(contentsOf: stepNumberingIssues(
                original: sourceText,
                simulated: plan.simulatedFinalText
            ))
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
            "i will ", "i'll ", "i am ", "i'm ", "as requested",
            "i just ", "done — i ", "done, i ", "sure — ", "sure, ",
            "okay — ", "okay, ", "here is ", "here's what i"
        ]
        return narrationPrefixes.contains { lower.hasPrefix($0) }
    }

    // MARK: Structural rules (moves + duplication)

    /// State-based guards on what the operations DO to the document, decided
    /// from line-level diffs — never from prompt keywords:
    ///
    /// 1. DUPLICATION — an operation adds a substantial line that already exists
    ///    near the edit and no operation removes that occurrence. Accepting
    ///    would put the same sentence in the document twice. Always blocking.
    /// 2. UNDECLARED MOVE — an added line matches a line some operation removes
    ///    elsewhere: content is being relocated. Legitimate only when the user
    ///    asked for it, which the model declares with `explicitMove: true`.
    ///    Without the flag, blocking — a model must never reorder the user's
    ///    lines as a side effect of an unrelated edit.
    static func structuralIssues(
        operations: [CosmoAssistantProposalOperation],
        sourceText: String
    ) -> [String] {
        // Per-operation line deltas from the same LCS the splitter/hunks use.
        struct Delta {
            let operationIndex: Int
            let explicitMove: Bool
            let locatedLineRange: ClosedRange<Int>?
            var removedKeys: Set<String> = []
            var addedLines: [String] = []
        }

        let sourceLines = sourceText.components(separatedBy: "\n")
        let sourceKeys = sourceLines.map(CosmoInlineLineDiff.contentKey)

        func lineNumber(of index: String.Index) -> Int {
            sourceText[..<index].reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
        }

        var deltas: [Delta] = []
        for (index, operation) in operations.enumerated() {
            let isTextEdit = operation.kind == .textReplacement
                || operation.kind == .structuredFieldReplacement
                || operation.kind == .textInsertion
            guard isTextEdit else { continue }

            let originalLines = (operation.originalText ?? "")
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let proposedLines = (operation.proposedText ?? "")
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            var locatedLineRange: ClosedRange<Int>?
            if let original = operation.originalText,
               !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let range = CosmoInlineDiffLocator.range(of: original, in: sourceText) {
                let start = lineNumber(of: range.lowerBound)
                let end = range.upperBound > range.lowerBound
                    ? lineNumber(of: sourceText.index(before: range.upperBound))
                    : start
                locatedLineRange = start...max(start, end)
            }

            var delta = Delta(
                operationIndex: index,
                explicitMove: operation.explicitMove == true,
                locatedLineRange: locatedLineRange
            )

            if operation.kind == .textInsertion {
                // Everything in an insertion is added; the anchor is untouched.
                delta.addedLines = proposedLines.filter(CosmoInlineLineDiff.isSubstantialContentLine)
            } else {
                for element in CosmoInlineLineDiff.elements(original: originalLines, proposed: proposedLines) {
                    switch element {
                    case .removed(let line) where CosmoInlineLineDiff.isSubstantialContentLine(line):
                        delta.removedKeys.insert(CosmoInlineLineDiff.contentKey(line))
                    case .added(let line) where CosmoInlineLineDiff.isSubstantialContentLine(line):
                        delta.addedLines.append(line)
                    default:
                        break
                    }
                }
            }
            deltas.append(delta)
        }

        let allRemovedKeys = deltas.reduce(into: Set<String>()) { $0.formUnion($1.removedKeys) }
        let coveredLineRanges = deltas.compactMap(\.locatedLineRange)

        var issues: [String] = []
        for delta in deltas {
            for added in delta.addedLines {
                let key = CosmoInlineLineDiff.contentKey(added)
                let preview = String(added.prefix(80))

                if allRemovedKeys.contains(key) {
                    guard !delta.explicitMove else { continue }
                    issues.append(
                        "Operation \(delta.operationIndex + 1) MOVES the line \"\(preview)\" to a new position (it is removed in one place and re-added in another). If the user explicitly asked to move or reorder this content, resubmit with explicitMove: true on that operation. Otherwise leave the line where it is and change only what the request requires."
                    )
                    continue
                }

                // Uncovered occurrence of the same content near the edit →
                // accepting would duplicate the sentence.
                let nearbyDuplicate = sourceKeys.enumerated().contains { sourceIndex, sourceKey in
                    guard sourceKey == key else { return false }
                    let covered = coveredLineRanges.contains { $0.contains(sourceIndex) }
                    guard !covered else { return false }
                    // No located anchor (pure append) → no locality evidence;
                    // deliberate far repetition stays allowed.
                    guard let opRange = delta.locatedLineRange else { return false }
                    let distance = min(
                        abs(sourceIndex - opRange.lowerBound),
                        abs(sourceIndex - opRange.upperBound)
                    )
                    return distance <= 8
                }
                if nearbyDuplicate {
                    issues.append(
                        "Operation \(delta.operationIndex + 1) adds the line \"\(preview)\" but that line ALREADY EXISTS right next to this edit — accepting would duplicate it. Do not re-add existing lines. If you meant to move it, the replacement must also cover its current position (and carry explicitMove: true)."
                    )
                }
            }
        }
        return issues
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

    /// The numbered-step analog of `slideNumberingIssue`: step lists inside each
    /// slide (and in the preamble) must not DEGRADE — no new duplicate numbers,
    /// and a list that was sequential must stay sequential. Pre-existing
    /// imperfections never veto an unrelated edit, mirroring the slide rule.
    static func stepNumberingIssues(original: String, simulated: String) -> [String] {
        let before = stepNumbersBySlide(in: original)
        let after = stepNumbersBySlide(in: simulated)

        var issues: [String] = []
        for (slide, afterNumbers) in after.sorted(by: { $0.key < $1.key }) {
            guard afterNumbers.count >= 2 else { continue }
            let beforeNumbers = before[slide] ?? []
            let scope = slide == 0 ? "the document" : "slide \(slide)"

            let beforeCounts = Dictionary(grouping: beforeNumbers, by: { $0 }).mapValues(\.count)
            let newDuplicates = Dictionary(grouping: afterNumbers, by: { $0 })
                .filter { number, occurrences in
                    occurrences.count > 1 && occurrences.count > (beforeCounts[number] ?? 0)
                }
                .keys
                .sorted()
            if !newDuplicates.isEmpty {
                issues.append(
                    "Applying these operations would corrupt the numbered steps in \(scope): duplicate step numbers (\(newDuplicates.map(String.init).joined(separator: ", "))). Renumber so every step keeps a unique, sequential integer — for series shifts use ONE renumberSequence operation with seriesKind numberedSteps."
                )
                continue
            }

            if isSequential(beforeNumbers), !isSequential(afterNumbers) {
                issues.append(
                    "Applying these operations would break the step numbering in \(scope): the list was sequential and no longer is (resulting order: \(afterNumbers.map(String.init).joined(separator: ", "))). Use ONE renumberSequence operation with seriesKind numberedSteps instead of hand-editing step numbers."
                )
            }
        }
        return issues
    }

    /// Step-numbered lines grouped by the slide that owns them (0 = before any
    /// SLIDE header), in document order.
    private static func stepNumbersBySlide(in text: String) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        var currentSlide = 0
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.range(of: #"^SLIDE\s+(\d+)\b"#, options: [.regularExpression, .caseInsensitive]) {
                let digits = trimmed[match].drop { !$0.isNumber }.prefix { $0.isNumber }
                currentSlide = Int(digits) ?? currentSlide
                return
            }
            if let match = trimmed.range(of: #"^(?:Step\s+)?(\d+)[\.\):]\s"#, options: [.regularExpression, .caseInsensitive]) {
                let digits = trimmed[match].drop { !$0.isNumber }.prefix { $0.isNumber }
                if let value = Int(digits) {
                    result[currentSlide, default: []].append(value)
                }
            }
        }
        return result
    }

    private static func isSequential(_ numbers: [Int]) -> Bool {
        guard let first = numbers.first else { return true }
        for (offset, value) in numbers.enumerated() where value != first + offset {
            return false
        }
        return true
    }
}

// MARK: - Minimal-edit splitting

/// Shrinks a fused block replacement down to the lines that actually change.
///
/// The over-rewrite failure mode: a "fill in the number" ask comes back as ONE
/// textReplacement whose originalText is an entire slide body and whose
/// proposedText rewrites all of it. Every downstream layer then over-states —
/// the review strikes through untouched lines, the scope guard's word test
/// can't see reordering, and an accidental duplication hides inside the block.
///
/// This splitter line-diffs originalText against proposedText and rewrites the
/// operation into one operation per changed region, dropping unchanged lines
/// entirely. Split anchors are expanded with the op's own preceding lines until
/// they locate uniquely in the live document; if any region cannot be made
/// unambiguous the ORIGINAL fused operation is kept (locatable beats minimal).
/// Deterministic and state-based: model behavior is normalized, never trusted.
enum CosmoInlineMinimalEditSplitter {
    private static let maxRegionOperations = 12
    private static let maxAnchorContextLines = 4

    static func split(
        operations: [CosmoAssistantProposalOperation],
        sourceText: String
    ) -> [CosmoAssistantProposalOperation] {
        operations.flatMap { split(operation: $0, sourceText: sourceText) }
    }

    static func split(
        operation: CosmoAssistantProposalOperation,
        sourceText: String
    ) -> [CosmoAssistantProposalOperation] {
        guard operation.kind == .textReplacement,
              let originalText = operation.originalText,
              let proposedText = operation.proposedText else {
            return [operation]
        }

        let originalLines = lines(of: originalText)
        let proposedLines = lines(of: proposedText)
        // Single-line replacements are already minimal.
        guard originalLines.count >= 2 else { return [operation] }
        // Splitting only makes sense when the fused block itself locates —
        // otherwise the validator flags it as-is.
        guard CosmoInlineDiffLocator.range(of: originalText, in: sourceText) != nil else {
            return [operation]
        }

        let elements = CosmoInlineLineDiff.elements(original: originalLines, proposed: proposedLines)
        let commonCount = elements.filter {
            if case .common = $0 { return true } else { return false }
        }.count
        // Nothing shared between the sides — the model genuinely rewrote the
        // block; there is no smaller edit to extract.
        guard commonCount > 0 else { return [operation] }

        let regions = changedRegions(from: elements)
        guard !regions.isEmpty, regions.count <= maxRegionOperations else {
            return regions.isEmpty ? [] : [operation]
        }

        var splitOperations: [CosmoAssistantProposalOperation] = []
        for region in regions {
            guard let regionOperation = self.operation(
                for: region,
                template: operation,
                sourceText: sourceText
            ) else {
                // Any un-anchorable region invalidates the whole split — the
                // fused original at least locates as one block.
                return [operation]
            }
            splitOperations.append(regionOperation)
        }
        return splitOperations
    }

    // MARK: Regions

    struct ChangedRegion {
        var removed: [String] = []
        var added: [String] = []
        /// Common lines directly above the region, nearest last — anchor context.
        var precedingCommon: [String] = []
        /// The first common line below the region, when one exists.
        var followingCommon: String?
    }

    private static func changedRegions(from elements: [CosmoInlineLineDiff.Element]) -> [ChangedRegion] {
        var regions: [ChangedRegion] = []
        var commonSoFar: [String] = []
        var current: ChangedRegion?

        func closeCurrent(followedBy common: String?) {
            guard var region = current else { return }
            region.followingCommon = common
            regions.append(region)
            current = nil
        }

        for element in elements {
            switch element {
            case .common(let line):
                closeCurrent(followedBy: line)
                commonSoFar.append(line)
            case .removed(let line):
                if current == nil { current = ChangedRegion(precedingCommon: commonSoFar) }
                current?.removed.append(line)
            case .added(let line):
                if current == nil { current = ChangedRegion(precedingCommon: commonSoFar) }
                current?.added.append(line)
            }
        }
        closeCurrent(followedBy: nil)
        return regions
    }

    // MARK: Region → operation

    private static func operation(
        for region: ChangedRegion,
        template: CosmoAssistantProposalOperation,
        sourceText: String
    ) -> CosmoAssistantProposalOperation? {
        var candidateOriginal: String
        var candidateProposed: String

        if !region.removed.isEmpty {
            // Replacement (or deletion when nothing is added).
            candidateOriginal = region.removed.joined(separator: "\n")
            candidateProposed = region.added.joined(separator: "\n")
        } else if let anchor = region.precedingCommon.last {
            // Pure insertion mid-block: replace the preceding line with
            // itself + the new lines, so one located edit carries it.
            candidateOriginal = anchor
            candidateProposed = anchor + "\n" + region.added.joined(separator: "\n")
        } else if let following = region.followingCommon {
            // Insertion at the very top of the block: replace the first
            // common line with the new lines + itself.
            candidateOriginal = following
            candidateProposed = region.added.joined(separator: "\n") + "\n" + following
        } else {
            return nil
        }

        // Expand upward through the op's own preceding lines until the anchor
        // is unique in the live document — a split must never relocate an edit
        // to a different first-match than the fused block occupied.
        var contextLines = region.precedingCommon
        if region.removed.isEmpty, !region.added.isEmpty, region.precedingCommon.last != nil {
            contextLines = Array(contextLines.dropLast())
        }
        var expansions = 0
        while !CosmoInlineDiffLocator.isUnique(candidateOriginal, in: sourceText) {
            guard expansions < maxAnchorContextLines, let context = contextLines.popLast() else {
                return nil
            }
            candidateOriginal = context + "\n" + candidateOriginal
            candidateProposed = context + "\n" + candidateProposed
            expansions += 1
        }

        return CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: template.targetID,
            anchorID: template.anchorID,
            originalText: candidateOriginal,
            proposedText: candidateProposed,
            sourceHash: template.sourceHash,
            rationale: template.rationale,
            explicitMove: template.explicitMove
        )
    }

    private static func lines(of text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
