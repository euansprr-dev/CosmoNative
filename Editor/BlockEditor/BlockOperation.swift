import Foundation

enum BlockOperationError: Error, Equatable {
    case blockNotFound(BlockPath)
    case parentNotFound(BlockPath)
    case unsupportedBlockKind(RichBlockKind)
    case invalidTextOffset(Int)
    case cannotMoveBlockIntoItself
}

struct BlockOperationResult: Equatable {
    var document: RichDocument
    var focusPath: BlockPath?
    var caretUTF16Offset: Int?
    var intent: BlockCaretIntent

    init(
        document: RichDocument,
        focusPath: BlockPath? = nil,
        caretUTF16Offset: Int? = nil,
        intent: BlockCaretIntent? = nil
    ) {
        self.document = document
        self.focusPath = focusPath
        self.caretUTF16Offset = caretUTF16Offset
        self.intent = intent ?? (caretUTF16Offset == nil ? .preserveCaret : .explicitOffset)
    }

    var focusBlockID: UUID? {
        guard let focusPath else { return nil }
        return try? BlockOperations.currentBlock(in: document, at: focusPath).id
    }

    /// Converts this result's caret intent into an offset-from-end for the
    /// focused block — the representation the text views consume (immune to
    /// rendered list/quote prefixes at the head of the text).
    func caretOffsetFromEnd(for block: RichBlock) -> Int? {
        let contentLength = block.plainInlineText.utf16.count
        switch intent {
        case .preserveCaret:
            return nil
        case .start:
            return contentLength
        case .end:
            return 0
        case .explicitOffset:
            guard let caretUTF16Offset else { return nil }
            return max(0, contentLength - caretUTF16Offset)
        }
    }
}

enum BlockCaretIntent: Equatable, Hashable, Sendable {
    case preserveCaret
    case start
    case end
    case explicitOffset
}

struct BlockDropTarget: Equatable, Hashable, Sendable {
    var parent: BlockPath?
    var index: Int

    init(parent: BlockPath?, index: Int) {
        precondition(index >= 0, "Drop index must be non-negative")
        self.parent = parent
        self.index = index
    }
}

struct BlockSlashRequest: Equatable {
    var path: BlockPath
    var queryRange: NSRange
    var query: String
    var caretRect: CGRect
}

struct BlockTextSelection: Equatable {
    var path: BlockPath
    var utf16Offset: Int
    var selectedLength: Int
}

@MainActor
final class BlockUndoRegistrar: NSObject {
    var applyDocument: ((RichDocument) -> Void)?

    func register(
        undoManager: UndoManager?,
        before: RichDocument,
        after: RichDocument,
        actionName: String
    ) {
        guard let undoManager,
              before != after else {
            return
        }

        undoManager.registerUndo(withTarget: self) { registrar in
            registrar.applyDocument?(before)
            registrar.register(
                undoManager: undoManager,
                before: after,
                after: before,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
    }
}
