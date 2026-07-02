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

    /// Multi-line paste into a text block, as ONE structural operation
    /// (Notion semantics): the first pasted line merges into the text before
    /// the caret, middle lines become their own blocks, the last line takes
    /// the text after the caret, and the caret lands at the end of the pasted
    /// content. The current block keeps its identity (row stability).
    static func pasteBlocks(
        in document: RichDocument,
        at path: BlockPath,
        utf16Offset: Int,
        pastedText: String
    ) throws -> BlockOperationResult {
        try pasteParsedBlocks(
            in: document,
            at: path,
            utf16Offset: utf16Offset,
            parsed: parsedPasteBlocks(from: pastedText)
        )
    }

    /// Splices already-parsed blocks (structured paste flavor, or the text
    /// flavor after line parsing) into a text block at the caret.
    static func pasteParsedBlocks(
        in document: RichDocument,
        at path: BlockPath,
        utf16Offset: Int,
        parsed: [RichBlock]
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
        let before = String(text[..<splitIndex])
        let after = String(text[splitIndex...])

        var parsed = parsed
        if parsed.isEmpty {
            parsed = [RichBlock(kind: .paragraph, inlines: [.text("")])]
        }

        let splice = pasteSplice(parsed: parsed, original: original, before: before, after: after)
        try mutateChildren(in: &document.blocks, indices: path.indices) { siblings, index in
            siblings.replaceSubrange(index...index, with: splice.blocks)
        }
        let focusIndex = path.indexInParent + splice.focusOffset
        let focusPath = path.parent?.appendingChild(index: focusIndex) ?? .root(index: focusIndex)
        return BlockOperationResult(
            document: document,
            focusPath: focusPath,
            caretUTF16Offset: splice.caretUTF16Offset
        )
    }

    /// Builds the replacement run for a paste — the head keeps the original
    /// block's identity, non-text blocks (dividers) never receive merged text.
    private static func pasteSplice(
        parsed: [RichBlock],
        original: RichBlock,
        before: String,
        after: String
    ) -> (blocks: [RichBlock], focusOffset: Int, caretUTF16Offset: Int) {
        let first = parsed[0]
        let last = parsed[parsed.count - 1]
        // An empty paragraph adopts the first pasted block's kind wholesale.
        let adoptFirstKind = before.isEmpty && original.kind == .paragraph && first.kind.isTextEditableBlock

        if parsed.count == 1 {
            guard first.kind.isTextEditableBlock else {
                // Single non-text block ("---"): before / block / after.
                var blocks: [RichBlock] = []
                var head = original
                head.inlines = [.text(before)]
                let keepsHead = !before.isEmpty
                if keepsHead { blocks.append(head) }
                blocks.append(first)
                var tail = original
                tail.inlines = [.text(after)]
                if keepsHead { tail = tail.withRegeneratedIDs() }
                blocks.append(tail)
                return (blocks, blocks.count - 1, 0)
            }
            var head = adoptFirstKind ? adopting(first, into: original) : original
            let pastedContent = first.plainInlineText
            if adoptFirstKind, after.isEmpty {
                head.inlines = first.inlines
            } else {
                head.inlines = [.text(before + pastedContent + after)]
            }
            return ([head], 0, (before + pastedContent).utf16.count)
        }

        var blocks: [RichBlock] = []

        // Head
        if first.kind.isTextEditableBlock {
            var head = adoptFirstKind ? adopting(first, into: original) : original
            // Keep the pasted block's rich inlines when nothing merges in.
            head.inlines = adoptFirstKind ? first.inlines : [.text(before + first.plainInlineText)]
            blocks.append(head)
        } else if before.isEmpty, original.plainInlineText.isEmpty {
            blocks.append(first)
        } else {
            var head = original
            head.inlines = [.text(before)]
            blocks.append(head)
            blocks.append(first)
        }

        // Middles
        if parsed.count > 2 {
            blocks.append(contentsOf: parsed[1..<(parsed.count - 1)])
        }

        // Tail
        if last.kind.isTextEditableBlock {
            var tail = last
            let tailContent = last.plainInlineText
            if !after.isEmpty {
                tail.inlines = [.text(tailContent + after)]
            }
            blocks.append(tail)
            return (blocks, blocks.count - 1, tailContent.utf16.count)
        }
        blocks.append(last)
        blocks.append(RichBlock(kind: .paragraph, inlines: [.text(after)]))
        return (blocks, blocks.count - 1, 0)
    }

    private static func adopting(_ source: RichBlock, into target: RichBlock) -> RichBlock {
        var result = target
        result.kind = source.kind
        result.checked = source.checked
        result.heading = source.heading
        return result
    }

    /// Line-based paste parser: the app's own serialized prefixes (via the
    /// legacy line parser) plus common markdown habits ("- ", "* ", "> ",
    /// "- [ ] ", "***"). Blank lines stay as empty paragraphs (Notion keeps
    /// them); one trailing empty line from a terminal newline is trimmed.
    static func parsedPasteBlocks(from pastedText: String) -> [RichBlock] {
        let lines = pastedText.normalizingHardNewlines().components(separatedBy: "\n")
        var blocks = lines.map(pasteBlock(fromLine:))
        if blocks.count > 1,
           let lastBlock = blocks.last,
           lastBlock.kind == .paragraph,
           lastBlock.plainInlineText.isEmpty {
            blocks.removeLast()
        }
        return blocks
    }

    private static func pasteBlock(fromLine line: String) -> RichBlock {
        if line.hasPrefix("- [ ] ") {
            return RichBlock(kind: .checklist, inlines: [.text(String(line.dropFirst(6)))], checked: false)
        }
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            return RichBlock(kind: .checklist, inlines: [.text(String(line.dropFirst(6)))], checked: true)
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return RichBlock(kind: .bulletList, inlines: [.text(String(line.dropFirst(2)))])
        }
        if line.hasPrefix("> ") {
            return RichBlock(kind: .quote, inlines: [.text(String(line.dropFirst(2)))])
        }
        if line.trimmingCharacters(in: .whitespaces) == "***" {
            return RichBlock(kind: .divider)
        }
        return RichDocument.block(fromLegacyLine: line)
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

        // Caret lands at the seam — end of the previous block's original text,
        // start of the merged-in text (Notion behavior).
        let seamOffset = previous.plainInlineText.utf16.count
        let mergedText = previous.plainInlineText + current.plainInlineText
        previous.inlines = [.text(mergedText)]
        try replaceBlock(previous, in: &document, at: previousPath)
        try removeBlock(in: &document, at: path)

        return BlockOperationResult(
            document: document,
            focusPath: previousPath,
            caretUTF16Offset: seamOffset
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
        livePlainText: String,
        triggerAlreadyRemoved: Bool = false
    ) throws -> BlockOperationResult {
        switch action {
        case .transform(let kind):
            return try applyTransform(
                kind,
                in: document,
                at: path,
                livePlainText: livePlainText,
                triggerAlreadyRemoved: triggerAlreadyRemoved
            )
        case .replaceOrInsert(let kind):
            return try applyReplaceOrInsert(
                kind,
                in: document,
                at: path,
                livePlainText: livePlainText,
                triggerAlreadyRemoved: triggerAlreadyRemoved
            )
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
        livePlainText: String,
        triggerAlreadyRemoved: Bool = false
    ) throws -> BlockOperationResult {
        var block = try block(in: document, at: path)
        guard kind.isTextEditableBlock else {
            throw BlockOperationError.unsupportedBlockKind(kind)
        }
        block.inlines = triggerAlreadyRemoved
            ? reconciledInlines(from: livePlainText, fallback: block.inlines)
            : cleanedSlashCommandInlines(from: livePlainText, fallback: block.inlines)
        var updated = document
        try replaceBlock(block, in: &updated, at: path)
        return try transformBlock(in: updated, at: path, to: kind)
    }

    private static func applyReplaceOrInsert(
        _ kind: RichBlockKind,
        in document: RichDocument,
        at path: BlockPath,
        livePlainText: String,
        triggerAlreadyRemoved: Bool = false
    ) throws -> BlockOperationResult {
        if kind.isTextEditableBlock {
            return try applyTransform(
                kind,
                in: document,
                at: path,
                livePlainText: livePlainText,
                triggerAlreadyRemoved: triggerAlreadyRemoved
            )
        }

        let block = try block(in: document, at: path)
        // triggerAlreadyRemoved: livePlainText is authoritative, even when
        // empty (a bare "/" block is empty after the trigger is consumed).
        let cleanedText = triggerAlreadyRemoved
            ? livePlainText
            : cleanedSlashCommandText(from: livePlainText, fallback: block.plainInlineText)
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

    /// Live text is authoritative (trigger already consumed by the text
    /// view) — keep the block's rich inlines only when the plain text agrees,
    /// otherwise rebuild from the live string.
    private static func reconciledInlines(
        from livePlainText: String,
        fallback: [RichInlineNode]
    ) -> [RichInlineNode] {
        fallback.plainText == livePlainText ? fallback : [.text(livePlainText)]
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

// MARK: - Multi-Block Operations (block selection)

extension BlockOperations {
    /// Deletes the given root-level blocks. Guarantees the document keeps at
    /// least one editable paragraph so the surface never goes dead.
    static func deleteBlocks(withIDs ids: Set<UUID>, in document: RichDocument) -> BlockOperationResult? {
        let removedIndices = document.blocks.enumerated()
            .filter { ids.contains($0.element.id) }
            .map(\.offset)
        guard let firstRemovedIndex = removedIndices.min() else { return nil }

        var updated = document
        updated.blocks.removeAll { ids.contains($0.id) }
        if updated.blocks.isEmpty {
            updated.blocks = [.paragraph("")]
        }
        let focusIndex = min(max(0, firstRemovedIndex - 1), updated.blocks.count - 1)
        return BlockOperationResult(
            document: updated,
            focusPath: .root(index: focusIndex),
            intent: .end
        )
    }

    /// Duplicates the given root-level blocks (in document order), inserting
    /// the copies directly after the last selected block. Returns the fresh
    /// copies' ids so selection can move onto them.
    static func duplicateBlocks(
        withIDs ids: Set<UUID>,
        in document: RichDocument
    ) -> (result: BlockOperationResult, duplicatedIDs: [UUID])? {
        let selected = document.blocks.enumerated().filter { ids.contains($0.element.id) }
        guard let lastIndex = selected.map(\.offset).max() else { return nil }

        let copies = selected.map { $0.element.withRegeneratedIDs() }
        var updated = document
        updated.blocks.insert(contentsOf: copies, at: lastIndex + 1)
        return (
            BlockOperationResult(document: updated, focusPath: .root(index: lastIndex + copies.count)),
            copies.map(\.id)
        )
    }

    /// Transforms every selected root-level text block to the given kind.
    /// Non-text blocks (dividers, images, elements) are left untouched.
    static func transformBlocks(
        withIDs ids: Set<UUID>,
        in document: RichDocument,
        to kind: RichBlockKind
    ) -> BlockOperationResult? {
        guard kind.isTextEditableBlock else { return nil }
        var updated = document
        var changed = false
        for index in updated.blocks.indices where ids.contains(updated.blocks[index].id) {
            guard updated.blocks[index].kind.isTextEditableBlock else { continue }
            updated.blocks[index].kind = kind
            updated.blocks[index].checked = kind == .checklist ? (updated.blocks[index].checked ?? false) : nil
            if kind.headingLevelInt != nil, updated.blocks[index].heading == nil {
                updated.blocks[index].heading = RichHeadingMetadata()
            }
            if kind.headingLevelInt == nil {
                updated.blocks[index].heading = nil
            }
            changed = true
        }
        guard changed else { return nil }
        return BlockOperationResult(document: updated)
    }

    /// Plaintext of the given root-level blocks in document order — copy/cut.
    static func plainText(ofBlocksWithIDs ids: Set<UUID>, in document: RichDocument) -> String {
        document.blocks
            .filter { ids.contains($0.id) }
            .map(\.plainInlineText)
            .joined(separator: "\n")
    }

    /// Markdown rendering of the given root blocks — what block-selection ⌘C
    /// writes to the plain-text pasteboard, so kinds survive into other apps
    /// (and round-trip through this app's own paste parser).
    static func markdown(ofBlocksWithIDs ids: Set<UUID>, in document: RichDocument) -> String {
        var lines: [String] = []
        var numberedIndex = 0
        for block in document.blocks where ids.contains(block.id) {
            numberedIndex = block.kind == .numberedList ? numberedIndex + 1 : 0
            lines.append(markdownLine(for: block, numberedIndex: max(1, numberedIndex)))
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownLine(for block: RichBlock, numberedIndex: Int) -> String {
        let text = block.plainInlineText
        switch block.kind {
        case .heading1: return "# " + text
        case .heading2: return "## " + text
        case .heading3: return "### " + text
        case .bulletList: return "- " + text
        case .numberedList: return "\(numberedIndex). " + text
        case .checklist: return (block.checked == true ? "- [x] " : "- [ ] ") + text
        case .quote: return "> " + text
        case .divider: return "---"
        default: return text
        }
    }

    /// The selected root blocks themselves, in document order — the
    /// structured (com.cosmo.blocks) copy flavor.
    static func blocks(withIDs ids: Set<UUID>, in document: RichDocument) -> [RichBlock] {
        document.blocks.filter { ids.contains($0.id) }
    }
}

extension RichBlockKind {
    /// Drops the prefix the serializer renders at the head of the text view
    /// ("• ", "1. ", "☐ ", "│ ") so live editor text maps back to block
    /// content. Plain kinds return the text untouched.
    func strippedRenderPrefix(from text: String) -> String {
        switch self {
        case .bulletList:
            return text.hasPrefix("• ") ? String(text.dropFirst(2)) : text
        case .quote:
            return text.hasPrefix("│ ") ? String(text.dropFirst(2)) : text
        case .checklist:
            if text.hasPrefix("☐ ") || text.hasPrefix("☑ ") {
                return String(text.dropFirst(2))
            }
            return text
        case .numberedList:
            guard let dotRange = text.range(of: ". "),
                  !text[..<dotRange.lowerBound].isEmpty,
                  text[..<dotRange.lowerBound].allSatisfy(\.isNumber) else {
                return text
            }
            return String(text[dotRange.upperBound...])
        default:
            return text
        }
    }
}

extension RichBlock {
    /// Deep copy with fresh identities for the block, its inlines, its element
    /// instance, and all children — required when duplicating, since ids drive
    /// focus, selection, and element identity.
    func withRegeneratedIDs() -> RichBlock {
        var copy = self
        copy.id = UUID()
        copy.inlines = inlines.map { inline in
            var next = inline
            next.id = UUID()
            return next
        }
        copy.element?.id = UUID()
        copy.children = children.map { $0.withRegeneratedIDs() }
        return copy
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
