// CosmoOS/UI/InlineAssistant/CosmoInlineFormatMarks.swift
// Applies `formatMarks` proposal operations to a RichDocument: rich-text
// formatting (bold/italic/underline/strikethrough) on located text, or heading
// retyping of the located block. The words never change — how they look does.
//
// Location follows the diff engine's text-anchoring model: the operation's
// `originalText` is located inside a block's own plain text via
// CosmoInlineDiffLocator (whitespace-collapse + smart-quote folding), never
// byte equality.

import Foundation

enum CosmoInlineFormatMarksApplier {
    /// Applies the mark to the first block containing `originalText`.
    /// Returns nil when no block contains the target — callers report an
    /// honest skip (never a blocking conflict).
    static func apply(
        mark: CosmoAssistantFormatMark,
        originalText: String?,
        to document: RichDocument
    ) -> RichDocument? {
        guard let target = originalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !target.isEmpty else { return nil }

        var blocks = document.blocks
        guard let index = blocks.firstIndex(where: { block in
            block.kind.isTextEditableBlock &&
            CosmoInlineDiffLocator.range(of: target, in: block.plainInlineText) != nil
        }) else {
            return nil
        }

        if let headingKind = mark.headingBlockKind {
            blocks[index] = retyped(blocks[index], to: headingKind)
        } else if let richMark = mark.richTextMark {
            let blockText = blocks[index].plainInlineText
            guard let range = CosmoInlineDiffLocator.range(of: target, in: blockText) else { return nil }
            let utf16Range = NSRange(range, in: blockText)
            blocks[index].inlines = marked(blocks[index].inlines, targetRange: utf16Range, mark: richMark)
        } else {
            return nil
        }

        var next = document
        next.blocks = blocks
        return next
    }

    /// Retype a block to a heading kind, preserving its inline content.
    private static func retyped(_ block: RichBlock, to kind: RichBlockKind) -> RichBlock {
        RichBlock(
            id: block.id,
            kind: kind,
            inlines: block.inlines,
            checked: nil,
            element: block.element,
            heading: block.heading,
            children: block.children
        )
    }

    /// Adds `mark` to the inline nodes intersecting `targetRange` (UTF-16
    /// offsets into the block's concatenated plain text). Text nodes split at
    /// the boundaries so only the targeted words change; mentions and images
    /// are atomic — an intersecting mention is marked whole.
    static func marked(
        _ inlines: [RichInlineNode],
        targetRange: NSRange,
        mark: RichTextMark
    ) -> [RichInlineNode] {
        var result: [RichInlineNode] = []
        var offset = 0

        for node in inlines {
            let nodeText: String
            switch node.kind {
            case .text:
                nodeText = node.text ?? ""
            case .mention:
                nodeText = node.mention?.displayText ?? ""
            case .imageRef:
                nodeText = ""
            }
            let nodeLength = nodeText.utf16.count
            let nodeRange = NSRange(location: offset, length: nodeLength)
            defer { offset += nodeLength }

            let intersection = NSIntersectionRange(nodeRange, targetRange)
            guard intersection.length > 0 else {
                result.append(node)
                continue
            }

            if node.kind != .text || intersection == nodeRange {
                var markedNode = node
                markedNode.marks.insert(mark)
                result.append(markedNode)
                continue
            }

            // Partial coverage of a text node — split into before / marked / after.
            let ns = nodeText as NSString
            let localStart = intersection.location - nodeRange.location
            let localEnd = localStart + intersection.length

            let before = ns.substring(to: localStart)
            let middle = ns.substring(with: NSRange(location: localStart, length: intersection.length))
            let after = ns.substring(from: localEnd)

            if !before.isEmpty {
                result.append(.text(before, marks: node.marks))
            }
            var middleMarks = node.marks
            middleMarks.insert(mark)
            result.append(.text(middle, marks: middleMarks))
            if !after.isEmpty {
                result.append(.text(after, marks: node.marks))
            }
        }

        return result
    }
}
