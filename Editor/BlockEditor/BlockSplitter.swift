import Foundation

enum BlockRegionKind: Equatable {
    case text
    case element
    case unsupported
}

struct BlockRegion: Identifiable, Equatable {
    let kind: BlockRegionKind
    let range: Range<Int>
    let blocks: [RichBlock]

    var id: String {
        switch kind {
        case .text:
            return "text:\(blocks.first?.id.uuidString ?? "empty")"
        case .element:
            return "element:\(blocks.first?.id.uuidString ?? "missing")"
        case .unsupported:
            return "unsupported:\(blocks.first?.id.uuidString ?? "missing")"
        }
    }

    var focusID: UUID? {
        blocks.first?.id
    }
}

enum BlockSplitter {
    static func split(_ blocks: [RichBlock]) -> [BlockRegion] {
        var regions: [BlockRegion] = []
        var cursor = blocks.startIndex

        while cursor < blocks.endIndex {
            let block = blocks[cursor]

            if block.kind == .element {
                regions.append(BlockRegion(kind: .element, range: cursor..<(cursor + 1), blocks: [block]))
                cursor += 1
                continue
            }

            guard isTextRegionBlock(block) else {
                regions.append(BlockRegion(kind: .unsupported, range: cursor..<(cursor + 1), blocks: [block]))
                cursor += 1
                continue
            }

            let start = cursor
            cursor += 1
            while cursor < blocks.endIndex, isTextRegionBlock(blocks[cursor]) {
                cursor += 1
            }

            regions.append(BlockRegion(kind: .text, range: start..<cursor, blocks: Array(blocks[start..<cursor])))
        }

        return regions
    }

    static func isTextRegionBlock(_ block: RichBlock) -> Bool {
        switch block.kind {
        case .paragraph, .heading1, .heading2, .heading3, .quote, .bulletList, .numberedList, .checklist, .content, .research, .callout, .toggle, .code, .section:
            return true
        case .divider, .image, .element, .sketch, .table:
            return false
        }
    }
}

enum BlockRegionReplacement {
    static func resolvedRange(for region: BlockRegion, in blocks: [RichBlock]) -> Range<Int> {
        let lower = min(max(0, region.range.lowerBound), blocks.count)
        guard lower < blocks.count else {
            return lower..<lower
        }

        switch region.kind {
        case .text:
            var upper = lower
            while upper < blocks.count, BlockSplitter.isTextRegionBlock(blocks[upper]) {
                upper += 1
            }
            return lower..<max(lower, upper)
        case .element, .unsupported:
            return lower..<min(lower + 1, blocks.count)
        }
    }

    static func replacingBlocks(
        in blocks: [RichBlock],
        range: Range<Int>,
        with replacement: [RichBlock]
    ) -> [RichBlock] {
        let safeRange = clampedRange(range, in: blocks)
        if blocksMatch(replacement, in: blocks, startingAt: safeRange.lowerBound) {
            return blocks
        }

        var updated = blocks
        updated.replaceSubrange(safeRange, with: replacement)
        return updated
    }

    private static func clampedRange(_ range: Range<Int>, in blocks: [RichBlock]) -> Range<Int> {
        let lower = min(max(0, range.lowerBound), blocks.count)
        let upper = min(max(lower, range.upperBound), blocks.count)
        return lower..<upper
    }

    private static func blocksMatch(_ replacement: [RichBlock], in blocks: [RichBlock], startingAt start: Int) -> Bool {
        guard !replacement.isEmpty else { return false }
        let end = start + replacement.count
        guard start >= 0, end <= blocks.count else { return false }
        return Array(blocks[start..<end]) == replacement
    }
}
