import Foundation

/// Applies reviewed text to one existing block without serializing the rest of
/// the Page through plain text. Structural or ambiguous edits remain in review.
enum UnifiedPageRichTextEdit {
    enum Failure: LocalizedError, Equatable {
        case missingTarget, ambiguousTarget, unsupportedStructure, missingText, missingFormat

        var errorDescription: String? {
            switch self {
            case .missingTarget:
                return "The original text has changed. Ask Cosmo to refresh this edit."
            case .ambiguousTarget:
                return "This text appears more than once. Select a unique paragraph and ask Cosmo to edit it."
            case .unsupportedStructure:
                return "This edit crosses rich blocks or embedded content. Select text within one paragraph and ask Cosmo to edit it."
            case .missingText:
                return "This proposal has no replacement text. Ask Cosmo to refresh it."
            case .missingFormat:
                return "This proposal has no formatting change. Ask Cosmo to refresh it."
            }
        }
    }

    static func applying(_ operation: CosmoAssistantProposalOperation, to document: RichDocument) throws -> RichDocument {
        guard operation.kind != .canvasPlan else { throw Failure.unsupportedStructure }
        let source = document.plainText
        let target = operation.originalText ?? ""
        if operation.kind == .textInsertion && target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let proposed = operation.proposedText else { throw Failure.missingText }
            return try append(proposed, to: document)
        }
        guard !target.isEmpty, let sourceRange = source.range(of: target, options: .literal) else {
            throw Failure.missingTarget
        }
        // Include overlapping matches. A second occurrence must never redirect
        // an accepted edit to an arbitrary block (including a table cell).
        let nextStart = source.index(after: sourceRange.lowerBound)
        guard source.range(of: target, options: .literal, range: nextStart..<source.endIndex) == nil else {
            throw Failure.ambiguousTarget
        }
        let matches = matchingBlocks(in: document.blocks, target: target)
        guard matches.count == 1, let match = matches.first else { throw Failure.unsupportedStructure }
        var blocks = document.blocks

        if operation.kind == .formatMarks {
            guard let mark = operation.formatMark else { throw Failure.missingFormat }
            try mutate(&blocks, id: match.id) { block in
                var result = block
                if let kind = mark.headingBlockKind {
                    guard [.paragraph, .heading1, .heading2, .heading3].contains(block.kind), block.rawKind == nil else {
                        throw Failure.unsupportedStructure
                    }
                    result.kind = kind
                    result.heading = block.heading ?? RichHeadingMetadata()
                } else if let richMark = mark.richTextMark {
                    try validateTextRange(match.range, in: block.inlines)
                    let length = block.plainInlineText.utf16.count
                    let before = try slice(block.inlines, range: NSRange(location: 0, length: match.range.location))
                    let middle = try slice(block.inlines, range: match.range).map { node in
                        var node = node; node.marks.insert(richMark); return node
                    }
                    let after = try slice(block.inlines, range: NSRange(location: NSMaxRange(match.range), length: length - NSMaxRange(match.range)))
                    result.inlines = uniqueIDs(before + middle + after)
                } else { throw Failure.missingFormat }
                return [result]
            }
            return RichDocument(blocks: blocks)
        }

        guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: source) else { throw Failure.missingText }
        guard placement.placementKind == .located else { throw Failure.missingTarget }
        let expectedRange = operation.kind == .textInsertion ? sourceRange.upperBound..<sourceRange.upperBound : sourceRange
        guard placement.range == expectedRange else { throw Failure.unsupportedStructure }
        let localRange = operation.kind == .textInsertion
            ? NSRange(location: NSMaxRange(match.range), length: 0) : match.range
        try mutate(&blocks, id: match.id) { block in
            try replacing(localRange, with: placement.replacementText, in: block)
        }
        let result = RichDocument(blocks: blocks)
        var expected = source
        expected.replaceSubrange(placement.range, with: placement.replacementText)
        // The review must describe the exact words that will land. Prefixes,
        // nested indentation and block semantics can make an edit unsupported.
        guard result.plainText == expected else { throw Failure.unsupportedStructure }
        return result
    }

    private struct Match { var id: UUID; var range: NSRange }

    private static func matchingBlocks(in blocks: [RichBlock], target: String) -> [Match] {
        var matches: [Match] = []
        for block in blocks {
            if block.kind.isTextEditableBlock, block.rawKind == nil,
               let range = block.plainInlineText.range(of: target, options: .literal) {
                matches.append(Match(id: block.id, range: NSRange(range, in: block.plainInlineText)))
            }
            matches += matchingBlocks(in: block.children, target: target)
            matches += matchingBlocks(in: block.heading?.collapsedBlocks ?? [], target: target)
        }
        return matches
    }

    private static func mutate(_ blocks: inout [RichBlock], id: UUID,
                               transform: (RichBlock) throws -> [RichBlock]) throws {
        for index in blocks.indices {
            if blocks[index].id == id {
                blocks.replaceSubrange(index...index, with: try transform(blocks[index]))
                return
            }
            try mutate(&blocks[index].children, id: id, transform: transform)
            if var heading = blocks[index].heading {
                try mutate(&heading.collapsedBlocks, id: id, transform: transform)
                blocks[index].heading = heading
            }
        }
    }

    private static func replacing(_ range: NSRange, with text: String, in block: RichBlock) throws -> [RichBlock] {
        try validateTextRange(range, in: block.inlines)
        let length = block.plainInlineText.utf16.count
        let before = try slice(block.inlines, range: NSRange(location: 0, length: range.location))
        let after = try slice(block.inlines, range: NSRange(location: NSMaxRange(range), length: length - NSMaxRange(range)))
        let lines = text.components(separatedBy: "\n")
        guard !text.contains("\r"), lines.count == 1 || (block.kind == .paragraph && block.children.isEmpty && block.heading == nil) else {
            throw Failure.unsupportedStructure
        }
        let template = textTemplate(in: block.inlines, at: range.location)
        var result: [RichBlock] = []
        var usedIDs = Set<UUID>()
        for (index, line) in lines.enumerated() {
            var next = index == 0 ? block : RichBlock(kind: .paragraph)
            var inserted = template ?? .text("")
            inserted.id = UUID(); inserted.text = line
            next.inlines = (index == 0 ? before : []) + (line.isEmpty ? [] : [inserted]) + (index == lines.count - 1 ? after : [])
            // Both halves of a split run cannot retain the same identity.
            next.inlines = next.inlines.map { node in
                var node = node
                if !usedIDs.insert(node.id).inserted { node.id = UUID(); usedIDs.insert(node.id) }
                return node
            }
            result.append(next)
        }
        return result
    }

    private static func append(_ proposed: String, to document: RichDocument) throws -> RichDocument {
        guard !proposed.contains("\r") else { throw Failure.unsupportedStructure }
        var result = document
        let source = document.plainText
        if source.isEmpty {
            if result.blocks.isEmpty { result.blocks = proposed.components(separatedBy: "\n").map(RichBlock.paragraph) }
            else if result.blocks.count == 1, let block = result.blocks.first, block.kind == .paragraph {
                result.blocks = try replacing(NSRange(location: 0, length: 0), with: proposed, in: block)
            } else { throw Failure.unsupportedStructure }
        } else {
            result.blocks += [RichBlock.paragraph("")] + proposed.components(separatedBy: "\n").map(RichBlock.paragraph)
        }
        let prefix = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        guard result.plainText == source + prefix + proposed else { throw Failure.unsupportedStructure }
        return result
    }

    private static func validateTextRange(_ range: NSRange, in inlines: [RichInlineNode]) throws {
        var offset = 0
        for node in inlines {
            let length = node.plainText.utf16.count
            defer { offset += length }
            guard node.kind != .text else { continue }
            let nodeRange = NSRange(location: offset, length: length)
            if NSIntersectionRange(nodeRange, range).length > 0 ||
                (range.length == 0 && range.location > offset && range.location < offset + length) {
                throw Failure.unsupportedStructure
            }
        }
    }

    /// Copies full runs verbatim and splits only a boundary text run. Colours,
    /// links, unknown fields and marks survive on every retained fragment.
    private static func slice(_ inlines: [RichInlineNode], range: NSRange) throws -> [RichInlineNode] {
        var offset = 0
        var result: [RichInlineNode] = []
        for node in inlines {
            let text = node.plainText
            let length = text.utf16.count
            defer { offset += length }
            let overlap = NSIntersectionRange(NSRange(location: offset, length: length), range)
            guard overlap.length > 0 else { continue }
            if overlap.length == length { result.append(node); continue }
            guard node.kind == .text,
                  let local = Range(NSRange(location: overlap.location - offset, length: overlap.length), in: text) else {
                throw Failure.unsupportedStructure
            }
            var fragment = node; fragment.text = String(text[local]); result.append(fragment)
        }
        return result
    }

    private static func textTemplate(in inlines: [RichInlineNode], at position: Int) -> RichInlineNode? {
        var offset = 0
        for node in inlines {
            let length = node.plainText.utf16.count
            defer { offset += length }
            if node.kind == .text && position >= offset && position <= offset + length { return node }
        }
        return nil
    }

    private static func uniqueIDs(_ inlines: [RichInlineNode]) -> [RichInlineNode] {
        var used = Set<UUID>()
        return inlines.map { node in
            var node = node
            if !used.insert(node.id).inserted { node.id = UUID(); used.insert(node.id) }
            return node
        }
    }
}
