// CosmoOS/Data/Models/Codex/CodexOutlineEditing.swift
// Pure outline editing helpers shared by focus-mode UI and tests.

import Foundation

enum CodexOutlineEditing {
    @discardableResult
    static func insertSlide(after slideID: UUID, in outline: inout CodexOutlineModel) -> UUID {
        let newID = UUID()
        let newSlide = CodexOutlineSlide(
            id: newID,
            position: 0,
            speechAct: nil,
            readerDeltas: [],
            frame: nil,
            distance: nil,
            techniques: [],
            transition: nil,
            note: nil
        )

        if let index = outline.slides.firstIndex(where: { $0.id == slideID }) {
            outline.slides.insert(newSlide, at: outline.slides.index(after: index))
        } else {
            outline.slides.append(newSlide)
        }

        renumberSlides(in: &outline)
        return newID
    }

    static func removeSlideIfEmpty(_ slideID: UUID, in outline: inout CodexOutlineModel) -> UUID? {
        guard let index = outline.slides.firstIndex(where: { $0.id == slideID }),
              index > outline.slides.startIndex,
              outline.slides[index].note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return nil
        }

        let previousID = outline.slides[outline.slides.index(before: index)].id
        outline.slides.remove(at: index)
        renumberSlides(in: &outline)
        return previousID
    }

    static func renumberSlides(in outline: inout CodexOutlineModel) {
        for index in outline.slides.indices {
            outline.slides[index].position = index + 1
        }
    }

    /// Move a slide up (-1) or down (+1) one position. Returns false when the
    /// slide is missing or already at the edge, so callers can skip the
    /// animation and focus churn.
    @discardableResult
    static func moveSlide(_ slideID: UUID, offset: Int, in outline: inout CodexOutlineModel) -> Bool {
        guard let index = outline.slides.firstIndex(where: { $0.id == slideID }) else { return false }
        let target = index + offset
        guard outline.slides.indices.contains(target) else { return false }
        outline.slides.swapAt(index, target)
        renumberSlides(in: &outline)
        return true
    }
}

/// Pure splice computation for "Insert into post": places an outline item's
/// text into the SLIDE N section of a slide-format draft. Returns a range +
/// replacement so callers can apply it to the rich document without
/// flattening formatting elsewhere.
enum ContentSlideDraftInsertion {
    struct Splice: Equatable {
        let range: NSRange
        let replacement: String
    }

    static func splice(slideNumber: Int, text: String, in draft: String) -> Splice {
        let ns = draft as NSString
        var lines: [(range: NSRange, content: String)] = []
        var cursor = 0
        while cursor < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let content = ns.substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append((lineRange, content))
            cursor = NSMaxRange(lineRange)
        }

        guard let headingIndex = lines.firstIndex(where: { isHeading($0.content, forSlide: slideNumber) }) else {
            return appendSplice(slideNumber: slideNumber, text: text, draft: draft, length: ns.length)
        }

        // Section body = lines after the heading, up to the -- separator or the
        // next SLIDE heading.
        var bodyIndices: [Int] = []
        var scan = lines.index(after: headingIndex)
        while scan < lines.count,
              !isSeparator(lines[scan].content),
              !isAnyHeading(lines[scan].content) {
            bodyIndices.append(scan)
            scan += 1
        }

        let hasContent = bodyIndices.contains { !lines[$0].content.isEmpty }

        if !hasContent {
            // Empty writing space — replace the whole (whitespace) body with the text.
            guard let first = bodyIndices.first, let last = bodyIndices.last else {
                // Heading is immediately followed by a separator or another
                // heading (or end of draft) — insert a fresh line after the heading.
                let insertAt = NSMaxRange(lines[headingIndex].range)
                let headingHasNewline = ns.substring(with: lines[headingIndex].range).hasSuffix("\n")
                return Splice(
                    range: NSRange(location: insertAt, length: 0),
                    replacement: headingHasNewline ? "\(text)\n" : "\n\(text)"
                )
            }
            let start = lines[first].range.location
            let end = NSMaxRange(lines[last].range)
            let endsWithNewline = ns.substring(with: lines[last].range).hasSuffix("\n")
            return Splice(
                range: NSRange(location: start, length: end - start),
                replacement: endsWithNewline ? "\(text)\n" : text
            )
        }

        // Existing writing in the slide — append below it as a new paragraph.
        guard let lastFilled = bodyIndices.last(where: { !lines[$0].content.isEmpty }) else {
            return appendSplice(slideNumber: slideNumber, text: text, draft: draft, length: ns.length)
        }
        let lineEnd = NSMaxRange(lines[lastFilled].range)
        let endsWithNewline = ns.substring(with: lines[lastFilled].range).hasSuffix("\n")
        return Splice(
            range: NSRange(location: lineEnd, length: 0),
            replacement: endsWithNewline ? "\n\(text)\n" : "\n\n\(text)"
        )
    }

    private static func appendSplice(slideNumber: Int, text: String, draft: String, length: Int) -> Splice {
        let section = "SLIDE \(slideNumber)\n\(text)\n--"
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Splice(range: NSRange(location: 0, length: length), replacement: section)
        }
        let prefix = draft.hasSuffix("\n") ? "" : "\n"
        return Splice(range: NSRange(location: length, length: 0), replacement: "\(prefix)\(section)")
    }

    private static func isHeading(_ content: String, forSlide number: Int) -> Bool {
        let upper = content.uppercased()
        return upper == "SLIDE \(number)" || upper == "SLIDE \(number):"
    }

    private static func isAnyHeading(_ content: String) -> Bool {
        let upper = content.uppercased()
        guard upper.hasPrefix("SLIDE ") else { return false }
        let remainder = upper.dropFirst("SLIDE ".count)
        return !remainder.isEmpty && remainder.allSatisfy { $0.isNumber || $0 == ":" }
    }

    private static func isSeparator(_ content: String) -> Bool {
        !content.isEmpty && content.allSatisfy { $0 == "-" || $0 == "—" || $0 == "–" }
    }
}

enum CodexOutlineDraftTemplate {
    private static let linesPerSlide = 1

    static func make(from outline: CodexOutlineModel) -> String? {
        guard outline.slides.count > 1 else { return nil }

        return outline.slides.enumerated()
            .map { index, _ in slideSection(number: index + 1) }
            .joined(separator: "\n")
    }

    private static func slideSection(number: Int) -> String {
        let writingSpace = Array(repeating: "", count: linesPerSlide).joined(separator: "\n")
        return "SLIDE \(number)\n\(writingSpace)\n--"
    }
}
