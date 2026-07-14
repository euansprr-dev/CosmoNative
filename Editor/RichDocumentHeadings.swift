import AppKit
import Foundation

struct RichHeadingOutlineEntry: Identifiable, Equatable {
    let id: UUID
    let level: Int
    let title: String
    let blockIndex: Int
    let parentID: UUID?
    let isCollapsed: Bool
    let hasCollapsedBlocks: Bool
}

enum RichDocumentHeadings {
    static func outline(in document: RichDocument) -> [RichHeadingOutlineEntry] {
        var stack: [(level: Int, id: UUID)] = []
        var entries: [RichHeadingOutlineEntry] = []

        for (index, block) in document.blocks.enumerated() {
            guard let level = block.kind.headingLevelInt else { continue }
            while let last = stack.last, last.level >= level {
                stack.removeLast()
            }
            let parentID = stack.last?.id
            let title = block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(RichHeadingOutlineEntry(
                id: block.id,
                level: level,
                title: title.isEmpty ? "Untitled heading" : title,
                blockIndex: index,
                parentID: parentID,
                isCollapsed: block.heading?.isCollapsed ?? false,
                hasCollapsedBlocks: !(block.heading?.collapsedBlocks.isEmpty ?? true)
            ))
            stack.append((level, block.id))
        }

        return entries
    }

    static func toggledCollapse(headingID: UUID, in document: RichDocument) -> RichDocument {
        var blocks = document.blocks
        guard let index = blocks.firstIndex(where: { $0.id == headingID }),
              let level = blocks[index].kind.headingLevelInt else {
            return document
        }

        var heading = blocks[index]
        var metadata = heading.heading ?? RichHeadingMetadata()
        // Collapsing is the affordance — a heading that folds is collapsible.
        metadata.isCollapsible = true

        if metadata.isCollapsed {
            metadata.isCollapsed = false
            let restored = metadata.collapsedBlocks
            metadata.collapsedBlocks = []
            heading.heading = metadata
            blocks[index] = heading
            blocks.insert(contentsOf: restored, at: index + 1)
        } else {
            let end = sectionEndIndex(startingAt: index, level: level, in: blocks)
            let ownedRange = (index + 1)..<end
            metadata.isCollapsed = true
            metadata.collapsedBlocks = Array(blocks[ownedRange])
            heading.heading = metadata
            blocks[index] = heading
            blocks.removeSubrange(ownedRange)
        }

        return RichDocument(blocks: blocks)
    }

    static func insertParagraphAfterCollapsedHeading(headingID: UUID, in document: RichDocument) -> RichDocument {
        var blocks = document.blocks
        guard let index = blocks.firstIndex(where: { $0.id == headingID }),
              blocks[index].heading?.isCollapsed == true else {
            return document
        }
        blocks.insert(RichBlock(kind: .paragraph, inlines: [.text("")]), at: index + 1)
        return RichDocument(blocks: blocks)
    }

    static func sectionEndIndex(startingAt startIndex: Int, level: Int, in blocks: [RichBlock]) -> Int {
        var cursor = startIndex + 1
        while cursor < blocks.count {
            if let nextLevel = blocks[cursor].kind.headingLevelInt, nextLevel <= level {
                break
            }
            cursor += 1
        }
        return cursor
    }
}
