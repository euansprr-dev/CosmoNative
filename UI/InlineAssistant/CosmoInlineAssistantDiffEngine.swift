import Foundation

enum CosmoInlineAssistantDiffEngine {
    /// Line-level LCS diff: identical lines render as context wherever they sit,
    /// so an inserted line at the top can no longer cascade every following
    /// (unchanged) line into a removed+added pair the way index-pairing did.
    static func hunks(original: String, proposed: String) -> [CosmoProposalHunk] {
        CosmoInlineLineDiff.elements(
            original: normalizedLines(original),
            proposed: normalizedLines(proposed)
        )
        .map { element in
            switch element {
            case .common(let line): return CosmoProposalHunk(kind: .context, text: line)
            case .removed(let line): return CosmoProposalHunk(kind: .removed, text: line)
            case .added(let line): return CosmoProposalHunk(kind: .added, text: line)
            }
        }
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

// MARK: - Line-level diff primitives

/// Shared line-level LCS diff. Feeds the review hunks, the minimal-edit
/// splitter (which shrinks a fused block replacement down to the lines that
/// actually change), and the validator's move/duplication rules — one diff
/// definition so display, splitting, and validation can never disagree about
/// what changed.
enum CosmoInlineLineDiff {
    enum Element: Equatable {
        /// A line present on both sides. Carries the ORIGINAL side's verbatim
        /// text — the side that can be located in the live document.
        case common(String)
        case removed(String)
        case added(String)
    }

    /// LCS over lines, matched with whitespace collapsed and typography folded
    /// (the same tolerance the locator applies), so a smart-quote drift doesn't
    /// turn an untouched line into a removed+added pair.
    static func elements(original: [String], proposed: [String]) -> [Element] {
        let originalKeys = original.map(matchKey)
        let proposedKeys = proposed.map(matchKey)

        // DP table for LCS length.
        let rows = original.count
        let columns = proposed.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: columns + 1), count: rows + 1)
        if rows > 0, columns > 0 {
            for row in stride(from: rows - 1, through: 0, by: -1) {
                for column in stride(from: columns - 1, through: 0, by: -1) {
                    if originalKeys[row] == proposedKeys[column] {
                        table[row][column] = table[row + 1][column + 1] + 1
                    } else {
                        table[row][column] = max(table[row + 1][column], table[row][column + 1])
                    }
                }
            }
        }

        var elements: [Element] = []
        var row = 0
        var column = 0
        while row < rows, column < columns {
            if originalKeys[row] == proposedKeys[column] {
                elements.append(.common(original[row]))
                row += 1
                column += 1
            } else if table[row + 1][column] >= table[row][column + 1] {
                elements.append(.removed(original[row]))
                row += 1
            } else {
                elements.append(.added(proposed[column]))
                column += 1
            }
        }
        while row < rows {
            elements.append(.removed(original[row]))
            row += 1
        }
        while column < columns {
            elements.append(.added(proposed[column]))
            column += 1
        }
        return elements
    }

    /// Equality key for "is this the same line": whitespace collapsed,
    /// typographic variants folded. Punctuation is content — a period-only
    /// change is a real edit and must NOT match.
    static func matchKey(_ line: String) -> String {
        var result: [Character] = []
        var previousWasSpace = false
        for character in line {
            if character.isWhitespace {
                if !previousWasSpace, !result.isEmpty { result.append(" ") }
                previousWasSpace = true
            } else {
                result.append(foldedTypography(character))
                previousWasSpace = false
            }
        }
        if result.last == " " { result.removeLast() }
        return String(result)
    }

    /// Looser key for the validator's move/duplication rules: the match key
    /// with trailing punctuation stripped, so "…decades." and "…decades…"
    /// count as the same sentence when checking for duplicated content.
    static func contentKey(_ line: String) -> String {
        var key = matchKey(line)
        while let last = key.last, isTrailingPunctuation(last) {
            key.removeLast()
        }
        return key
    }

    /// Whether a line carries enough substance for move/duplication analysis.
    /// Short lines (separators, "SLIDE 7", "Step 3:") repeat legitimately and
    /// must never trip structural rules.
    static func isSubstantialContentLine(_ line: String) -> Bool {
        let key = contentKey(line)
        guard key.count >= 15 else { return false }
        guard key.contains(where: { $0.isLetter }) else { return false }
        // Bare slide headers repeat by design during renumber cascades.
        if key.range(of: #"^(?:-{2,}\s*)?SLIDE\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        return true
    }

    private static func isTrailingPunctuation(_ character: Character) -> Bool {
        character == "." || character == "…" || character == "!" || character == "?"
            || character == "," || character == ";" || character == ":"
    }

    private static func foldedTypography(_ character: Character) -> Character {
        switch character {
        case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{2033}": return "\""
        case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}", "\u{2032}": return "'"
        case "\u{2014}", "\u{2013}", "\u{2212}", "\u{2012}", "\u{2015}": return "-"
        default: return character
        }
    }
}

// MARK: - Locator

/// Finds where a proposal's `originalText` lives inside the *current* surface text.
///
/// LLM-supplied `originalText` rarely byte-matches the live document — whitespace,
/// blank lines, and smart punctuation drift. The locator first tries an exact match,
/// then a whitespace-normalized match that maps back to a real range in the source.
/// This is the single source of truth for "can this edit still apply" and "where do we
/// splice the inline diff", so matching and applying never disagree.
enum CosmoInlineDiffLocator {
    /// Best-effort range of `needle` within `haystack`.
    ///
    /// Fallback chain, most precise first:
    /// 1. exact byte match
    /// 2. trimmed exact match
    /// 3. whitespace-normalized + typography-folded match
    /// 4. paragraph-anchored match (multi-line needles whose middle lines drifted)
    /// 5. bounded fuzzy line match — unique candidate only
    ///
    /// Every stage either locates with confidence or returns nil — a diff that lands
    /// in the wrong place once costs more trust than a hundred misses, so ambiguity
    /// never resolves to a mid-document guess. When the locator gives up, placement
    /// falls back to an explicit append at the end of the document instead: always
    /// applicable, and the review diff shows exactly where the text will land.
    static func range(of needle: String, in haystack: String) -> Range<String.Index>? {
        let trimmedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNeedle.isEmpty else { return nil }

        if let exact = haystack.range(of: needle) { return exact }
        if let trimmed = haystack.range(of: trimmedNeedle) { return trimmed }
        if let normalized = normalizedRange(of: trimmedNeedle, in: haystack) { return normalized }
        if let anchored = paragraphAnchoredRange(of: trimmedNeedle, in: haystack) { return anchored }
        return boundedFuzzyLineRange(of: trimmedNeedle, in: haystack)
    }

    /// Whether `needle` can be located in `haystack` (exact or whitespace-normalized).
    static func matches(_ needle: String, in haystack: String) -> Bool {
        range(of: needle, in: haystack) != nil
    }

    /// Whether `needle` locates exactly once — a second locatable occurrence
    /// after the first match means a sequential apply's "first match" could hit
    /// the wrong instance. Used by the edit transaction to expand anchors until
    /// they are unambiguous.
    static func isUnique(_ needle: String, in haystack: String) -> Bool {
        guard let first = range(of: needle, in: haystack) else { return false }
        let remainder = String(haystack[first.upperBound...])
        return range(of: needle, in: remainder) == nil
    }

    private static func normalizedRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        // Build a whitespace-collapsed projection of the haystack while remembering,
        // for every projected character, the real source indices it came from.
        var projected: [Character] = []
        var startIndex: [String.Index] = []
        var endIndex: [String.Index] = []
        var previousWasSpace = false

        var cursor = haystack.startIndex
        while cursor < haystack.endIndex {
            let character = haystack[cursor]
            let next = haystack.index(after: cursor)

            if character.isWhitespace {
                if previousWasSpace, let last = endIndex.indices.last {
                    endIndex[last] = next // extend the run the single space already represents
                } else if !projected.isEmpty {
                    projected.append(" ")
                    startIndex.append(cursor)
                    endIndex.append(next)
                }
                previousWasSpace = true
            } else {
                projected.append(canonical(character))
                startIndex.append(cursor)
                endIndex.append(next)
                previousWasSpace = false
            }
            cursor = next
        }

        if projected.last == " " {
            projected.removeLast()
            startIndex.removeLast()
            endIndex.removeLast()
        }

        let needleChars = Array(collapseWhitespace(needle))
        guard !needleChars.isEmpty,
              let matchStart = firstIndex(of: needleChars, in: projected) else { return nil }

        let matchEnd = matchStart + needleChars.count
        return startIndex[matchStart]..<endIndex[matchEnd - 1]
    }

    // MARK: Paragraph-anchored fallback

    /// Multi-line needles whose middle lines drifted (re-wraps, edited list items)
    /// can still be located by their first and last lines. Both anchors must locate
    /// via the precise stages, appear in order, and the spanned region must be
    /// size-plausible — otherwise nil, never a guess.
    private static func paragraphAnchoredRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        let needleLines = needle
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard needleLines.count >= 3,
              let firstLine = needleLines.first,
              let lastLine = needleLines.last,
              firstLine != lastLine else {
            return nil
        }

        guard let firstRange = preciseRange(of: firstLine, in: haystack) else { return nil }
        // Search the tail as its own String and map back by character offset —
        // String and Substring indices are not interchangeable.
        let tailString = String(haystack[firstRange.upperBound...])
        guard let lastRangeInTail = preciseRange(of: lastLine, in: tailString) else { return nil }

        let offsetUpper = tailString.distance(from: tailString.startIndex, to: lastRangeInTail.upperBound)
        let lastUpper = haystack.index(firstRange.upperBound, offsetBy: offsetUpper)

        let span = firstRange.lowerBound..<lastUpper

        // Plausibility: the located span shouldn't be wildly larger than the needle —
        // a last-line match pages below the first line means we anchored the wrong block.
        let spanLength = haystack.distance(from: span.lowerBound, to: span.upperBound)
        let needleLength = needle.count
        guard spanLength <= max(needleLength * 2, needleLength + 200) else { return nil }

        return span
    }

    /// Exact / trimmed / normalized matching only — used for anchor lines, where
    /// fuzzy matching would compound uncertainty.
    private static func preciseRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        if let exact = haystack.range(of: needle) { return exact }
        let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let trimmedMatch = haystack.range(of: trimmed) { return trimmedMatch }
        return normalizedRange(of: trimmed, in: haystack)
    }

    // MARK: Bounded fuzzy fallback

    /// Last resort for single-line needles: find a haystack line within a small
    /// edit distance (≤ 10% of the needle, minimum 2). Applies only when exactly
    /// ONE line qualifies — two plausible candidates mean ambiguity, and ambiguity
    /// resolves to conflict, never to a guess.
    private static func boundedFuzzyLineRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        let collapsedNeedle = collapseWhitespace(needle)
        guard !collapsedNeedle.isEmpty,
              !needle.contains("\n"),
              collapsedNeedle.count >= 12 // tiny fragments are too ambiguous to fuzz
        else { return nil }

        let maxDistance = max(2, collapsedNeedle.count / 10)
        let needleChars = Array(collapsedNeedle)

        var bestRange: Range<String.Index>? = nil
        var bestDistance = Int.max
        var bestIsUnique = true

        var lineStart = haystack.startIndex
        while lineStart < haystack.endIndex {
            let lineEnd = haystack[lineStart...].firstIndex(of: "\n") ?? haystack.endIndex
            defer {
                lineStart = lineEnd < haystack.endIndex ? haystack.index(after: lineEnd) : haystack.endIndex
            }

            let line = String(haystack[lineStart..<lineEnd])
            let collapsedLine = collapseWhitespace(line)
            // Cheap length gate before paying for edit distance.
            guard abs(collapsedLine.count - needleChars.count) <= maxDistance else { continue }

            let distance = boundedLevenshtein(needleChars, Array(collapsedLine), limit: maxDistance)
            guard let distance else { continue }

            if distance < bestDistance {
                bestDistance = distance
                bestIsUnique = true
                // Trim the matched line's surrounding whitespace from the range.
                bestRange = trimmedLineRange(lineStart..<lineEnd, in: haystack)
            } else if distance == bestDistance {
                bestIsUnique = false
            }
        }

        guard bestIsUnique, bestDistance <= maxDistance else { return nil }
        return bestRange
    }

    private static func trimmedLineRange(
        _ range: Range<String.Index>,
        in haystack: String
    ) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, haystack[lower].isWhitespace {
            lower = haystack.index(after: lower)
        }
        while upper > lower, haystack[haystack.index(before: upper)].isWhitespace {
            upper = haystack.index(before: upper)
        }
        return lower..<upper
    }

    /// Levenshtein distance with an early-exit bound: returns nil as soon as the
    /// distance provably exceeds `limit`, keeping the scan O(lines × needle × limit).
    private static func boundedLevenshtein(_ a: [Character], _ b: [Character], limit: Int) -> Int? {
        if abs(a.count - b.count) > limit { return nil }
        if a == b { return 0 }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution
                )
                rowMin = Swift.min(rowMin, current[j])
            }
            if rowMin > limit { return nil }
            swap(&previous, &current)
        }

        let distance = previous[b.count]
        return distance <= limit ? distance : nil
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var result: [Character] = []
        var previousWasSpace = false
        for character in text {
            if character.isWhitespace {
                if !previousWasSpace, !result.isEmpty { result.append(" ") }
                previousWasSpace = true
            } else {
                result.append(canonical(character))
                previousWasSpace = false
            }
        }
        if result.last == " " { result.removeLast() }
        return String(result)
    }

    /// Folds typographic variants the model commonly substitutes (smart quotes, dashes)
    /// to a canonical form. Each fold is 1:1, so the source index map stays valid and the
    /// red "removed" lines still render with the document's real characters.
    private static func canonical(_ character: Character) -> Character {
        switch character {
        case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{2033}": return "\""
        case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}", "\u{2032}": return "'"
        case "\u{2014}", "\u{2013}", "\u{2212}", "\u{2012}", "\u{2015}": return "-"
        default: return character
        }
    }

    private static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        let lastStart = haystack.count - needle.count
        var start = 0
        while start <= lastStart {
            var offset = 0
            while offset < needle.count, haystack[start + offset] == needle[offset] {
                offset += 1
            }
            if offset == needle.count { return start }
            start += 1
        }
        return nil
    }
}

enum CosmoInlineResolvedPlacementKind: Equatable, Sendable {
    /// originalText located precisely in the source.
    case located
    /// Landed via the SLIDE-header fallback (originalText did not locate).
    case slideHeader
    /// Nothing located — never-block trailing append at document end.
    case appendFallback
}

struct CosmoInlineResolvedTextEdit {
    let range: Range<String.Index>
    let replacementText: String
    var placementKind: CosmoInlineResolvedPlacementKind = .located
}

enum CosmoInlineTextEditResolver {
    /// Always resolves SOME placement for a text edit — precise location first, slide
    /// header next, an explicit append at the end of the document as the last resort.
    /// A reviewable best-effort beats a blocked "conflicted" state: the user sees in
    /// the diff exactly where the text will land and decides there. Returns nil only
    /// when there is genuinely nothing to apply (canvas plans, missing proposed text).
    static func placement(
        for operation: CosmoAssistantProposalOperation,
        in sourceText: String
    ) -> CosmoInlineResolvedTextEdit? {
        guard operation.kind != .canvasPlan,
              let proposed = operation.proposedText else {
            return nil
        }

        let edit: CosmoInlineResolvedTextEdit
        switch operation.kind {
        case .textReplacement, .structuredFieldReplacement:
            edit = replacementPlacement(for: operation, proposed: proposed, in: sourceText)
        case .textInsertion:
            edit = insertionPlacement(for: operation, proposed: proposed, in: sourceText)
        case .canvasPlan:
            return nil
        case .formatMarks:
            // Formatting never resolves as a text edit — it applies marks via
            // CosmoInlineFormatMarksApplier, keeping the words untouched.
            return nil
        }
        return slideHeaderReconciled(edit, in: sourceText)
    }

    private static func replacementPlacement(
        for operation: CosmoAssistantProposalOperation,
        proposed: String,
        in sourceText: String
    ) -> CosmoInlineResolvedTextEdit {
        let original = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if shouldPreferSlideHeaderFallback(for: operation, proposed: proposed),
           let fallback = slideHeaderFallback(for: operation, proposed: proposed, in: sourceText) {
            return fallback
        }
        if !original.isEmpty,
           let range = CosmoInlineDiffLocator.range(of: operation.originalText ?? "", in: sourceText) {
            return CosmoInlineResolvedTextEdit(range: range, replacementText: proposed)
        }
        if let fallback = slideHeaderFallback(for: operation, proposed: proposed, in: sourceText) {
            return fallback
        }
        return appendPlacement(proposed, in: sourceText)
    }

    private static func insertionPlacement(
        for operation: CosmoAssistantProposalOperation,
        proposed: String,
        in sourceText: String
    ) -> CosmoInlineResolvedTextEdit {
        let anchor = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if shouldPreferSlideHeaderFallback(for: operation, proposed: proposed),
           let fallback = slideHeaderFallback(for: operation, proposed: proposed, in: sourceText) {
            return fallback
        }
        if !anchor.isEmpty,
           let range = CosmoInlineDiffLocator.range(of: operation.originalText ?? "", in: sourceText) {
            return CosmoInlineResolvedTextEdit(
                range: range.upperBound..<range.upperBound,
                replacementText: insertionText(proposed)
            )
        }
        if let fallback = slideHeaderFallback(for: operation, proposed: proposed, in: sourceText) {
            return fallback
        }
        return appendPlacement(proposed, in: sourceText)
    }

    /// The destination-slide fallback exists for CONTENT edits whose anchor is
    /// stale but whose explicit slide target is clear ("put this under slide
    /// 5"). A pure header RENAME (bare "SLIDE N" → bare "SLIDE M") is the edit
    /// itself — diverting it used to rewrite the DESTINATION slide's header
    /// and corrupt every renumber cascade, so renames always locate precisely.
    private static func shouldPreferSlideHeaderFallback(
        for operation: CosmoAssistantProposalOperation,
        proposed: String
    ) -> Bool {
        guard let explicitTarget = explicitTargetSlideNumber(for: operation, proposed: proposed),
              let originalSlide = leadingSlideNumber(in: operation.originalText ?? "") else {
            return false
        }
        guard explicitTarget != originalSlide else { return false }
        if isBareSlideHeaderLine(operation.originalText), isBareSlideHeaderLine(operation.proposedText) {
            return false
        }
        return true
    }

    private static func isBareSlideHeaderLine(_ text: String?) -> Bool {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: #"^(?:-{2,}\s*)?SLIDE\s+\d+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func slideHeaderFallback(
        for operation: CosmoAssistantProposalOperation,
        proposed: String,
        in sourceText: String
    ) -> CosmoInlineResolvedTextEdit? {
        guard let slideNumber = targetSlideNumber(for: operation, proposed: proposed),
              let headerRange = slideHeaderRange(slideNumber: slideNumber, in: sourceText) else {
            return nil
        }

        if leadingSlideNumber(in: proposed) == slideNumber {
            return CosmoInlineResolvedTextEdit(
                range: headerRange,
                replacementText: proposed,
                placementKind: .slideHeader
            )
        }

        return CosmoInlineResolvedTextEdit(
            range: headerRange.upperBound..<headerRange.upperBound,
            replacementText: insertionText(proposed),
            placementKind: .slideHeader
        )
    }

    // MARK: Slide-header reconciliation

    /// State-based invariant applied to every resolved edit: applying a change never
    /// deletes a slide header the proposal didn't explicitly rewrite, and never
    /// duplicates the header that already governs the edit's position. Decided from
    /// the document's actual state — not prompt keywords — so it holds for every
    /// phrasing, every surface, and every apply path that shares this resolver.
    private static func slideHeaderReconciled(
        _ edit: CosmoInlineResolvedTextEdit,
        in sourceText: String
    ) -> CosmoInlineResolvedTextEdit {
        let replacement = edit.replacementText
        guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return edit // an empty replacement is a deletion — never resurrect a header into it
        }

        let rangeHeader = leadingSlideHeaderLine(in: String(sourceText[edit.range]))
        let replacementHeader = leadingSlideHeaderLine(in: replacement)

        // The edit swallows "SLIDE N" but offers no header back — keep the document's own.
        if let rangeHeader, replacementHeader == nil {
            let separator = replacement.hasPrefix("\n") ? "" : "\n"
            return CosmoInlineResolvedTextEdit(
                range: edit.range,
                replacementText: rangeHeader.line + separator + replacement,
                placementKind: edit.placementKind
            )
        }

        // The replacement re-states the header that already governs this position — drop it.
        if rangeHeader == nil,
           let replacementHeader,
           governingSlideNumber(before: edit.range.lowerBound, in: sourceText) == replacementHeader.number {
            return CosmoInlineResolvedTextEdit(
                range: edit.range,
                replacementText: strippedLeadingSlideHeader(from: replacement),
                placementKind: edit.placementKind
            )
        }

        return edit
    }

    private struct SlideHeaderLine {
        let line: String
        let number: String
    }

    private static func leadingSlideHeaderLine(in text: String) -> SlideHeaderLine? {
        let pattern = #"^\s*((?:-{2,}\s*)?SLIDE\s+(\d+))[ \t]*(?:\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(location: 0, length: (text as NSString).length)
              ),
              match.numberOfRanges > 2 else {
            return nil
        }
        let nsText = text as NSString
        return SlideHeaderLine(
            line: nsText.substring(with: match.range(at: 1)),
            number: nsText.substring(with: match.range(at: 2))
        )
    }

    /// Number of the nearest slide header at or above `position` — the slide that
    /// owns that location in the document.
    private static func governingSlideNumber(
        before position: String.Index,
        in sourceText: String
    ) -> String? {
        let prefix = String(sourceText[..<position])
        let pattern = #"(?im)^\s*(?:-{2,}\s*)?SLIDE\s+(\d+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(
            in: prefix,
            range: NSRange(location: 0, length: (prefix as NSString).length)
        )
        guard let last = matches.last, last.numberOfRanges > 1 else { return nil }
        return (prefix as NSString).substring(with: last.range(at: 1))
    }

    private static func strippedLeadingSlideHeader(from text: String) -> String {
        let hadLeadingNewline = text.hasPrefix("\n")
        let pattern = #"^\s*(?:-{2,}\s*)?SLIDE\s+\d+[ \t]*(?:\n+)?"#
        let stripped = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Insertions arrive with a leading newline separating them from their anchor —
        // stripping the header must not glue the content onto the anchor line.
        guard hadLeadingNewline, !stripped.hasPrefix("\n") else { return stripped }
        return "\n" + stripped
    }

    private static func appendPlacement(_ proposed: String, in sourceText: String) -> CosmoInlineResolvedTextEdit {
        let prefix = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        return CosmoInlineResolvedTextEdit(
            range: sourceText.endIndex..<sourceText.endIndex,
            replacementText: prefix + proposed,
            placementKind: .appendFallback
        )
    }

    private static func insertionText(_ proposed: String) -> String {
        proposed.hasPrefix("\n") ? proposed : "\n" + proposed
    }

    private static func targetSlideNumber(
        for operation: CosmoAssistantProposalOperation,
        proposed: String
    ) -> String? {
        explicitTargetSlideNumber(for: operation, proposed: proposed)
            ?? leadingSlideNumber(in: operation.originalText ?? "")
    }

    private static func explicitTargetSlideNumber(
        for operation: CosmoAssistantProposalOperation,
        proposed: String
    ) -> String? {
        leadingSlideNumber(in: proposed)
            ?? slideNumber(inLooseText: operation.anchorID)
            ?? slideNumber(inLooseText: operation.rationale)
    }

    private static func leadingSlideNumber(in text: String) -> String? {
        let pattern = #"(?im)^\s*SLIDE\s+(\d+)\s*$"#
        return firstCapture(pattern: pattern, in: text)
    }

    private static func slideNumber(inLooseText text: String?) -> String? {
        guard let text else { return nil }
        let pattern = #"(?i)\bslide[\s\-_#]*(\d+)\b"#
        return firstCapture(pattern: pattern, in: text)
    }

    private static func slideHeaderRange(slideNumber: String, in sourceText: String) -> Range<String.Index>? {
        let pattern = #"(?im)^\s*SLIDE\s+\#(slideNumber)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: sourceText,
                range: NSRange(location: 0, length: (sourceText as NSString).length)
              ) else {
            return nil
        }
        return Range(match.range, in: sourceText)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(location: 0, length: (text as NSString).length)
              ),
              match.numberOfRanges > 1 else {
            return nil
        }
        return (text as NSString).substring(with: match.range(at: 1))
    }
}

// MARK: - Inline review segments

/// A single located change in the live document, derived from one proposal operation.
struct CosmoInlineDiffChange: Identifiable, Equatable {
    /// Matches the originating operation's id so accept/reject route back correctly.
    let id: UUID
    let removedLines: [String]
    let addedLines: [String]
    let rationale: String
    let status: CosmoProposalStatus
    /// True only when there is genuinely nothing to apply on this surface (canvas
    /// plans, empty proposals) — dismiss-only. Drifted text edits are never
    /// conflicted: they relocate or append, and stay acceptable.
    let isConflicted: Bool
    /// Set for formatting changes — the review renders the added lines with the
    /// mark actually applied (real bold, real heading scale), not a text diff.
    var formatMark: CosmoAssistantFormatMark? = nil
}

/// An ordered slice of the document review: untouched prose or a change block.
enum CosmoInlineDiffSegment: Identifiable, Equatable {
    case unchanged(id: String, text: String)
    case change(CosmoInlineDiffChange)

    var id: String {
        switch self {
        case let .unchanged(id, _): return id
        case let .change(change): return "change-\(change.id.uuidString)"
        }
    }
}

/// Turns a live source string + a proposal's operations into an ordered, in-document
/// diff. Removed text is read straight from the *current* document (not the model's
/// echo), so the red lines always match what is really there.
enum CosmoInlineDiffReviewBuilder {
    static func segments(
        sourceText: String,
        operations: [CosmoAssistantProposalOperation]
    ) -> [CosmoInlineDiffSegment] {
        let reviewable = operations.filter { $0.status == .pending || $0.status == .conflicted }

        // Positioned edits are woven into the document at a real location — text edits
        // always resolve (worst case as an explicit trailing append). Only operations
        // with nothing to apply on a text surface (canvas plans, empty proposals)
        // fall through as dismiss-only.
        var positioned: [PositionedChange] = []
        var overlapping: [CosmoAssistantProposalOperation] = []
        var unplaceable: [CosmoAssistantProposalOperation] = []

        for operation in reviewable {
            if operation.kind == .canvasPlan {
                unplaceable.append(operation)
                continue
            }

            if operation.kind == .formatMarks {
                // Formatting keeps the words — locate the target and render the
                // styled result in place (no red lines, no replacement text).
                if let target = operation.originalText,
                   let range = CosmoInlineDiffLocator.range(of: target, in: sourceText) {
                    positioned.append(PositionedChange(
                        operation: operation,
                        edit: CosmoInlineResolvedTextEdit(range: range, replacementText: String(sourceText[range]))
                    ))
                } else {
                    unplaceable.append(operation)
                }
                continue
            }

            if let edit = CosmoInlineTextEditResolver.placement(for: operation, in: sourceText) {
                positioned.append(PositionedChange(operation: operation, edit: edit))
            } else {
                unplaceable.append(operation)
            }
        }

        positioned.sort { $0.sortIndex < $1.sortIndex }

        var segments: [CosmoInlineDiffSegment] = []
        var cursor = sourceText.startIndex

        for change in positioned {
            let range = change.edit.range
            // An edit colliding with one already woven in can't render inline, but it
            // stays fully acceptable — accept re-resolves it against the live text.
            guard range.lowerBound >= cursor else {
                overlapping.append(change.operation)
                continue
            }
            if range.lowerBound > cursor {
                appendUnchanged(String(sourceText[cursor..<range.lowerBound]), to: &segments)
            }
            let isFormatting = change.operation.kind == .formatMarks
            segments.append(.change(CosmoInlineDiffChange(
                id: change.operation.id,
                removedLines: (isFormatting || range.isEmpty) ? [] : displayLines(String(sourceText[range])),
                addedLines: displayLines(change.edit.replacementText),
                rationale: change.operation.rationale,
                status: change.operation.status,
                isConflicted: false,
                formatMark: isFormatting ? change.operation.formatMark : nil
            )))
            cursor = range.upperBound
        }

        if cursor < sourceText.endIndex {
            appendUnchanged(String(sourceText[cursor...]), to: &segments)
        }

        for operation in overlapping {
            segments.append(.change(CosmoInlineDiffChange(
                id: operation.id,
                removedLines: displayLines(operation.originalText ?? ""),
                addedLines: displayLines(operation.proposedText ?? ""),
                rationale: operation.rationale,
                status: operation.status,
                isConflicted: false
            )))
        }

        for operation in unplaceable {
            segments.append(.change(CosmoInlineDiffChange(
                id: operation.id,
                removedLines: displayLines(operation.originalText ?? ""),
                addedLines: displayLines(operation.proposedText ?? ""),
                rationale: operation.rationale,
                status: operation.status,
                isConflicted: true
            )))
        }

        return segments
    }

    private struct PositionedChange {
        let operation: CosmoAssistantProposalOperation
        let edit: CosmoInlineResolvedTextEdit

        var sortIndex: String.Index {
            edit.range.lowerBound
        }
    }

    private static func appendUnchanged(_ text: String, to segments: inout [CosmoInlineDiffSegment]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        segments.append(.unchanged(id: "unchanged-\(segments.count)", text: text))
    }

    private static func displayLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
            .filter { !$0.isEmpty }
    }
}
