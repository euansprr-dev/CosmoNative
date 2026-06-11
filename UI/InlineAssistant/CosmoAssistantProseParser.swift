// CosmoOS/UI/InlineAssistant/CosmoAssistantProseParser.swift
// Splits a finalized pane answer into prose runs and document pills, so answers
// cite workspace documents in the same pill language the composer speaks.
// June 2026

import Foundation

enum CosmoAssistantProseSegment: Equatable {
    case text(String)
    case pill(CosmoAssistantSourceRef)
}

struct CosmoAssistantProseParseResult: Equatable {
    var segments: [CosmoAssistantProseSegment]
    /// Refs that became inline pills — the remainder renders as a quieter
    /// "Also read" row instead of duplicating the citation.
    var linkedRefUUIDs: Set<String>
}

/// Two passes over the finalized answer, zero prompt cost:
/// 1. Explicit `[[uuid]]` markers (forward-compat plumbing; unknown ids are
///    stripped so marker grammar never leaks into prose).
/// 2. Title auto-link: the first occurrence of each source-ref title becomes a
///    pill — longest titles first so overlapping titles resolve deterministically.
enum CosmoAssistantProseParser {
    /// Titles shorter than this never auto-link — generic words ("Notes")
    /// would rather stay prose than mislink.
    static let minimumAutoLinkTitleLength = 4

    static func parse(
        answer: String,
        sourceRefs: [CosmoAssistantSourceRef]?
    ) -> CosmoAssistantProseParseResult {
        let refs = sourceRefs ?? []
        guard !answer.isEmpty else {
            return CosmoAssistantProseParseResult(segments: [], linkedRefUUIDs: [])
        }

        var linked = Set<String>()
        var segments = markerPass(answer: answer, refs: refs, linked: &linked)
        segments = autoLinkPass(segments: segments, refs: refs, linked: &linked)
        return CosmoAssistantProseParseResult(segments: segments, linkedRefUUIDs: linked)
    }

    // MARK: - Streaming display scrub

    /// While an answer streams we render plain text, but the model may emit
    /// `[[uuid]]` markers — show the document's title in their place and hide a
    /// trailing half-typed marker so raw grammar never flashes on screen.
    static func streamingDisplayText(
        for content: String,
        sourceRefs: [CosmoAssistantSourceRef]
    ) -> String {
        var text = content

        // Hide an incomplete trailing marker ("…see [[a1b2" mid-stream).
        if let lastOpen = text.range(of: "[[", options: .backwards),
           text.range(of: "]]", options: .backwards, range: lastOpen.upperBound..<text.endIndex) == nil {
            text = String(text[..<lastOpen.lowerBound])
        }

        guard text.contains("[["), let markerRegex else { return text }
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in markerRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let token = nsText.substring(with: match.range(at: 1))
            if let ref = sourceRefs.first(where: { $0.uuid.caseInsensitiveCompare(token) == .orderedSame }) {
                result += ref.title.isEmpty ? "Untitled" : ref.title
            }
            cursor = match.range.location + match.range.length
        }
        result += nsText.substring(from: cursor)
        return result
    }

    // MARK: - Pass 1: explicit [[uuid]] markers

    private static let markerRegex = try? NSRegularExpression(
        pattern: #"\[\[\s*([^\[\]]{1,64}?)\s*\]\]"#
    )

    private static func markerPass(
        answer: String,
        refs: [CosmoAssistantSourceRef],
        linked: inout Set<String>
    ) -> [CosmoAssistantProseSegment] {
        guard let markerRegex else { return [.text(answer)] }
        let nsAnswer = answer as NSString
        let matches = markerRegex.matches(in: answer, range: NSRange(location: 0, length: nsAnswer.length))
        guard !matches.isEmpty else { return [.text(answer)] }

        var segments: [CosmoAssistantProseSegment] = []
        var cursor = 0

        for match in matches {
            let token = nsAnswer.substring(with: match.range(at: 1))
            let ref = refs.first { $0.uuid.caseInsensitiveCompare(token) == .orderedSame }

            var leading = nsAnswer.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if ref == nil {
                // Unknown marker: strip it and collapse the seam so no double
                // space survives where the marker sat.
                let trailingStart = match.range.location + match.range.length
                let nextIsSpace = trailingStart < nsAnswer.length
                    && nsAnswer.substring(with: NSRange(location: trailingStart, length: 1)) == " "
                if nextIsSpace, leading.hasSuffix(" ") {
                    leading = String(leading.dropLast())
                }
            }
            if !leading.isEmpty {
                segments.append(.text(leading))
            }
            if let ref {
                segments.append(.pill(ref))
                linked.insert(ref.uuid)
            }
            cursor = match.range.location + match.range.length
        }

        let tail = nsAnswer.substring(from: cursor)
        if !tail.isEmpty {
            segments.append(.text(tail))
        }
        return segments.isEmpty ? [.text("")] : segments
    }

    // MARK: - Pass 2: title auto-link

    private static func autoLinkPass(
        segments initial: [CosmoAssistantProseSegment],
        refs: [CosmoAssistantSourceRef],
        linked: inout Set<String>
    ) -> [CosmoAssistantProseSegment] {
        let candidates = refs
            .filter { ref in
                guard !linked.contains(ref.uuid) else { return false }
                let title = ref.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.count >= minimumAutoLinkTitleLength
                    && title.caseInsensitiveCompare("Untitled") != .orderedSame
            }
            .sorted { $0.title.count > $1.title.count }

        var segments = initial
        for ref in candidates {
            guard let (segmentIndex, range) = firstTitleOccurrence(of: ref.title, in: segments) else { continue }
            guard case .text(let run) = segments[segmentIndex] else { continue }

            let nsRun = run as NSString
            let before = nsRun.substring(to: range.location)
            let after = nsRun.substring(from: range.location + range.length)

            var replacement: [CosmoAssistantProseSegment] = []
            if !before.isEmpty { replacement.append(.text(before)) }
            replacement.append(.pill(ref))
            if !after.isEmpty { replacement.append(.text(after)) }
            segments.replaceSubrange(segmentIndex...segmentIndex, with: replacement)
            linked.insert(ref.uuid)
        }
        return segments
    }

    /// First case-insensitive, word-bounded occurrence of `title` across the
    /// text segments. Pills are never scanned, so matches can't overlap.
    private static func firstTitleOccurrence(
        of title: String,
        in segments: [CosmoAssistantProseSegment]
    ) -> (segmentIndex: Int, range: NSRange)? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        for (index, segment) in segments.enumerated() {
            guard case .text(let run) = segment else { continue }
            let nsRun = run as NSString
            var searchLocation = 0

            while searchLocation < nsRun.length {
                let searchRange = NSRange(location: searchLocation, length: nsRun.length - searchLocation)
                let found = nsRun.range(of: trimmedTitle, options: [.caseInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }

                if isWordBounded(found, in: nsRun) {
                    return (index, found)
                }
                searchLocation = found.location + max(found.length, 1)
            }
        }
        return nil
    }

    private static func isWordBounded(_ range: NSRange, in text: NSString) -> Bool {
        func isWordCharacter(at location: Int) -> Bool {
            guard location >= 0, location < text.length else { return false }
            let character = text.substring(with: NSRange(location: location, length: 1))
            guard let scalar = character.unicodeScalars.first else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || character == "_"
        }
        return !isWordCharacter(at: range.location - 1)
            && !isWordCharacter(at: range.location + range.length)
    }
}
