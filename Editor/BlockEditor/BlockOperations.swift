import Foundation

enum BlockOperations {
    static func transformBlock(
        in document: RichDocument,
        at path: BlockPath,
        to kind: RichBlockKind
    ) throws -> BlockOperationResult {
        var document = document
        var block = try block(in: document, at: path)
        block.kind = kind
        block.checked = kind == .checklist ? (block.checked ?? false) : nil
        if kind.headingLevelInt != nil, block.heading == nil {
            block.heading = RichHeadingMetadata()
        }
        if kind.headingLevelInt == nil {
            block.heading = nil
        }
        try replaceBlock(block, in: &document, at: path)
        return BlockOperationResult(document: document, focusPath: path)
    }

    static func replaceBlock(
        in document: RichDocument,
        at path: BlockPath,
        with block: RichBlock
    ) throws -> BlockOperationResult {
        var document = document
        try replaceBlock(block, in: &document, at: path)
        return BlockOperationResult(document: document, focusPath: path)
    }

    static func replaceBlocks(
        in document: RichDocument,
        at path: BlockPath,
        with blocks: [RichBlock]
    ) throws -> BlockOperationResult {
        var document = document
        try mutateChildren(in: &document.blocks, indices: path.indices) { siblings, index in
            siblings.replaceSubrange(index...index, with: blocks)
        }
        let focusIndex = path.indexInParent + max(0, blocks.count - 1)
        let focusPath = path.parent?.appendingChild(index: focusIndex) ?? .root(index: focusIndex)
        return BlockOperationResult(document: document, focusPath: focusPath)
    }

    static func insertBlock(
        _ block: RichBlock,
        in document: RichDocument,
        after path: BlockPath
    ) throws -> BlockOperationResult {
        try insertBlock(block, in: document, at: BlockDropTarget(parent: path.parent, index: path.indexInParent + 1))
    }

    static func insertBlock(
        _ block: RichBlock,
        in document: RichDocument,
        at target: BlockDropTarget
    ) throws -> BlockOperationResult {
        var document = document
        try insert(block, in: &document, at: target)
        let focusPath = target.parent?.appendingChild(index: target.index) ?? .root(index: target.index)
        return BlockOperationResult(document: document, focusPath: focusPath)
    }

    static func splitTextBlock(
        in document: RichDocument,
        at path: BlockPath,
        utf16Offset: Int
    ) throws -> BlockOperationResult {
        var document = document
        let original = try block(in: document, at: path)
        guard original.kind.isTextEditableBlock else {
            throw BlockOperationError.unsupportedBlockKind(original.kind)
        }

        let text = original.plainInlineText
        guard let splitIndex = String.Index(utf16Offset: utf16Offset, in: text) else {
            throw BlockOperationError.invalidTextOffset(utf16Offset)
        }

        var before = original
        before.inlines = [.text(String(text[..<splitIndex]))]

        let after = RichBlock(
            kind: original.kind.splitContinuationKind,
            inlines: [.text(String(text[splitIndex...]))],
            checked: original.kind == .checklist ? false : nil
        )

        try replaceBlock(before, in: &document, at: path)
        let insertionIndex = path.indexInParent + 1
        try insert(after, in: &document, at: BlockDropTarget(parent: path.parent, index: insertionIndex))
        let focusPath = path.parent?.appendingChild(index: insertionIndex) ?? .root(index: insertionIndex)
        return BlockOperationResult(document: document, focusPath: focusPath, caretUTF16Offset: 0)
    }

    static func mergeBackward(
        in document: RichDocument,
        at path: BlockPath
    ) throws -> BlockOperationResult {
        guard path.indexInParent > 0 else {
            throw BlockOperationError.blockNotFound(path)
        }

        var document = document
        let current = try block(in: document, at: path)
        let previousPath = path.parent?.appendingChild(index: path.indexInParent - 1) ?? .root(index: path.indexInParent - 1)
        var previous = try block(in: document, at: previousPath)

        guard previous.kind.isTextEditableBlock, current.kind.isTextEditableBlock else {
            throw BlockOperationError.unsupportedBlockKind(current.kind)
        }

        let mergedText = previous.plainInlineText + current.plainInlineText
        previous.inlines = [.text(mergedText)]
        try replaceBlock(previous, in: &document, at: previousPath)
        try removeBlock(in: &document, at: path)

        return BlockOperationResult(
            document: document,
            focusPath: previousPath,
            caretUTF16Offset: mergedText.utf16.count
        )
    }

    static func exitEmptyListBlock(
        in document: RichDocument,
        at path: BlockPath
    ) throws -> BlockOperationResult {
        var block = try block(in: document, at: path)
        guard [.bulletList, .numberedList, .checklist].contains(block.kind),
              block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BlockOperationError.unsupportedBlockKind(block.kind)
        }

        block.kind = .paragraph
        block.checked = nil
        var document = document
        try replaceBlock(block, in: &document, at: path)
        return BlockOperationResult(document: document, focusPath: path, caretUTF16Offset: 0)
    }

    static func deleteEmptyBlockBackward(
        in document: RichDocument,
        at path: BlockPath
    ) throws -> BlockOperationResult {
        let block = try block(in: document, at: path)
        guard block.kind.isTextEditableBlock,
              block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              path.indexInParent > 0 else {
            throw BlockOperationError.unsupportedBlockKind(block.kind)
        }

        var document = document
        try removeBlock(in: &document, at: path)
        let focusPath = path.parent?.appendingChild(index: path.indexInParent - 1) ?? .root(index: path.indexInParent - 1)
        return BlockOperationResult(document: document, focusPath: focusPath)
    }

    static func clearAbandonedSlashTrigger(
        in document: RichDocument,
        at path: BlockPath
    ) throws -> BlockOperationResult {
        var block = try block(in: document, at: path)
        guard block.kind.isTextEditableBlock else {
            throw BlockOperationError.unsupportedBlockKind(block.kind)
        }

        guard block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines) == "/" else {
            return BlockOperationResult(document: document, focusPath: path)
        }

        block.inlines = [.text("")]
        var document = document
        try replaceBlock(block, in: &document, at: path)
        return BlockOperationResult(document: document, focusPath: path, caretUTF16Offset: 0)
    }

    static func moveBlock(
        in document: RichDocument,
        from source: BlockPath,
        to target: BlockDropTarget
    ) throws -> BlockOperationResult {
        guard BlockDropController.canMove(from: source, to: target) else {
            throw BlockOperationError.cannotMoveBlockIntoItself
        }
        if let parent = target.parent, parent.indices.starts(with: source.indices) {
            throw BlockOperationError.cannotMoveBlockIntoItself
        }

        var document = document
        let moving = try block(in: document, at: source)
        try removeBlock(in: &document, at: source)

        var adjustedTarget = target
        if source.parent == target.parent, source.indexInParent < target.index {
            adjustedTarget.index -= 1
        }

        try insert(moving, in: &document, at: adjustedTarget)
        let focusPath = adjustedTarget.parent?.appendingChild(index: adjustedTarget.index) ?? .root(index: adjustedTarget.index)
        return BlockOperationResult(document: document, focusPath: focusPath)
    }

    static func currentBlock(in document: RichDocument, at path: BlockPath) throws -> RichBlock {
        try block(in: document, at: path)
    }

    static func apply(
        _ action: BlockCommand.Action,
        in document: RichDocument,
        at path: BlockPath,
        livePlainText: String
    ) throws -> BlockOperationResult {
        switch action {
        case .transform(let kind):
            return try applyTransform(kind, in: document, at: path, livePlainText: livePlainText)
        case .replaceOrInsert(let kind):
            return try applyReplaceOrInsert(kind, in: document, at: path, livePlainText: livePlainText)
        case .insertElement(let definition):
            return try replaceBlock(
                in: document,
                at: path,
                with: RichBlock.element(definition)
            )
        case .createElement, .openElementsSubmenu, .openWritingAI:
            throw BlockOperationError.unsupportedBlockKind(try block(in: document, at: path).kind)
        }
    }

    static func path(of blockID: UUID, in document: RichDocument) -> BlockPath? {
        path(of: blockID, in: document.blocks, prefix: [])
    }

    private static func applyTransform(
        _ kind: RichBlockKind,
        in document: RichDocument,
        at path: BlockPath,
        livePlainText: String
    ) throws -> BlockOperationResult {
        var block = try block(in: document, at: path)
        guard kind.isTextEditableBlock else {
            throw BlockOperationError.unsupportedBlockKind(kind)
        }
        block.inlines = cleanedSlashCommandInlines(from: livePlainText, fallback: block.inlines)
        var updated = document
        try replaceBlock(block, in: &updated, at: path)
        return try transformBlock(in: updated, at: path, to: kind)
    }

    private static func applyReplaceOrInsert(
        _ kind: RichBlockKind,
        in document: RichDocument,
        at path: BlockPath,
        livePlainText: String
    ) throws -> BlockOperationResult {
        if kind.isTextEditableBlock {
            return try applyTransform(kind, in: document, at: path, livePlainText: livePlainText)
        }

        let block = try block(in: document, at: path)
        let cleanedText = cleanedSlashCommandText(from: livePlainText, fallback: block.plainInlineText)
        let replacement = RichBlock(kind: kind)
        let shouldReplaceTrigger = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if shouldReplaceTrigger {
            var updated = document
            try replaceBlock(replacement, in: &updated, at: path)
            let insertionIndex = path.indexInParent + 1
            try insert(
                .paragraph(""),
                in: &updated,
                at: BlockDropTarget(parent: path.parent, index: insertionIndex)
            )
            let focusPath = path.parent?.appendingChild(index: insertionIndex) ?? .root(index: insertionIndex)
            return BlockOperationResult(document: updated, focusPath: focusPath, caretUTF16Offset: 0)
        }

        var updated = document
        var current = block
        current.inlines = [.text(cleanedText)]
        try replaceBlock(current, in: &updated, at: path)
        let dividerIndex = path.indexInParent + 1
        try insert(
            replacement,
            in: &updated,
            at: BlockDropTarget(parent: path.parent, index: dividerIndex)
        )
        let paragraphIndex = dividerIndex + 1
        try insert(
            .paragraph(""),
            in: &updated,
            at: BlockDropTarget(parent: path.parent, index: paragraphIndex)
        )
        let focusPath = path.parent?.appendingChild(index: paragraphIndex) ?? .root(index: paragraphIndex)
        return BlockOperationResult(document: updated, focusPath: focusPath, caretUTF16Offset: 0)
    }

    private static func block(in document: RichDocument, at path: BlockPath) throws -> RichBlock {
        guard let block = block(in: document.blocks, indices: path.indices) else {
            throw BlockOperationError.blockNotFound(path)
        }
        return block
    }

    private static func block(in blocks: [RichBlock], indices: [Int]) -> RichBlock? {
        guard let first = indices.first, blocks.indices.contains(first) else { return nil }
        if indices.count == 1 { return blocks[first] }
        return block(in: blocks[first].children, indices: Array(indices.dropFirst()))
    }

    private static func path(of blockID: UUID, in blocks: [RichBlock], prefix: [Int]) -> BlockPath? {
        for (index, block) in blocks.enumerated() {
            let indices = prefix + [index]
            if block.id == blockID {
                return BlockPath(indices: indices)
            }
            if let childPath = path(of: blockID, in: block.children, prefix: indices) {
                return childPath
            }
        }
        return nil
    }

    private static func replaceBlock(_ block: RichBlock, in document: inout RichDocument, at path: BlockPath) throws {
        try mutateChildren(in: &document.blocks, indices: path.indices) { siblings, index in
            siblings[index] = block
        }
    }

    private static func removeBlock(in document: inout RichDocument, at path: BlockPath) throws {
        try mutateChildren(in: &document.blocks, indices: path.indices) { siblings, index in
            siblings.remove(at: index)
        }
    }

    private static func insert(_ block: RichBlock, in document: inout RichDocument, at target: BlockDropTarget) throws {
        if let parent = target.parent {
            try mutateBlock(in: &document.blocks, indices: parent.indices) { parentBlock in
                guard target.index <= parentBlock.children.count else {
                    throw BlockOperationError.parentNotFound(parent)
                }
                parentBlock.children.insert(block, at: target.index)
            }
        } else {
            guard target.index <= document.blocks.count else {
                throw BlockOperationError.parentNotFound(.root(index: max(0, target.index)))
            }
            document.blocks.insert(block, at: target.index)
        }
    }

    private static func cleanedSlashCommandInlines(
        from livePlainText: String,
        fallback: [RichInlineNode]
    ) -> [RichInlineNode] {
        let cleanedText = cleanedSlashCommandText(from: livePlainText, fallback: fallback.plainText)
        if cleanedText != livePlainText || fallback.plainText != livePlainText {
            return [.text(cleanedText)]
        }

        var result = fallback
        for index in result.indices.reversed() where result[index].kind == .text {
            guard var text = result[index].text,
                  let slashIndex = text.lastIndex(of: "/") else {
                continue
            }
            text.remove(at: slashIndex)
            result[index].text = text
            return result
        }
        return result
    }

    private static func cleanedSlashCommandText(from livePlainText: String, fallback: String) -> String {
        let source = livePlainText.isEmpty ? fallback : livePlainText
        guard let slashIndex = source.lastIndex(of: "/") else { return source }
        var result = source
        result.remove(at: slashIndex)
        return result
    }

    private static func mutateChildren(
        in blocks: inout [RichBlock],
        indices: [Int],
        mutation: (inout [RichBlock], Int) throws -> Void
    ) throws {
        guard let first = indices.first, blocks.indices.contains(first) else {
            throw BlockOperationError.blockNotFound(BlockPath(indices: indices) ?? .root(index: 0))
        }
        if indices.count == 1 {
            try mutation(&blocks, first)
        } else {
            try mutateChildren(in: &blocks[first].children, indices: Array(indices.dropFirst()), mutation: mutation)
        }
    }

    private static func mutateBlock(
        in blocks: inout [RichBlock],
        indices: [Int],
        mutation: (inout RichBlock) throws -> Void
    ) throws {
        guard let first = indices.first, blocks.indices.contains(first) else {
            throw BlockOperationError.blockNotFound(BlockPath(indices: indices) ?? .root(index: 0))
        }
        if indices.count == 1 {
            try mutation(&blocks[first])
        } else {
            try mutateBlock(in: &blocks[first].children, indices: Array(indices.dropFirst()), mutation: mutation)
        }
    }
}

private extension String.Index {
    init?(utf16Offset: Int, in string: String) {
        guard utf16Offset >= 0,
              let utf16Index = string.utf16.index(string.utf16.startIndex, offsetBy: utf16Offset, limitedBy: string.utf16.endIndex),
              let index = String.Index(utf16Index, within: string) else {
            return nil
        }
        self = index
    }
}

private extension Array where Element == RichInlineNode {
    var plainText: String {
        map(\.plainText).joined()
    }
}
