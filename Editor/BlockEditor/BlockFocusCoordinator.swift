import Foundation
import Observation

/// A one-shot caret placement attached to a focus change after a structural
/// edit (split/merge/delete). Offset is from the END of the block's text in
/// UTF-16 — immune to rendered list/quote prefixes at the head.
struct BlockCaretRequest: Equatable {
    var blockID: UUID
    var utf16OffsetFromEnd: Int
    var token: Int
}

@MainActor
@Observable
final class BlockFocusCoordinator {
    private(set) var focusedBlockID: UUID?
    private(set) var caretRequest: BlockCaretRequest?
    private var registeredBlockIDs: [UUID] = []

    func register(_ blockID: UUID?) {
        guard let blockID, !registeredBlockIDs.contains(blockID) else { return }
        registeredBlockIDs.append(blockID)
    }

    func unregister(_ blockID: UUID?) {
        guard let blockID else { return }
        registeredBlockIDs.removeAll { $0 == blockID }
        if focusedBlockID == blockID {
            focusedBlockID = nil
        }
    }

    func focus(_ blockID: UUID?) {
        guard let blockID else { return }
        register(blockID)
        // Same-value writes still notify Observation — skip them so the
        // per-keystroke focus reaffirmation doesn't re-render every row.
        if focusedBlockID != blockID {
            focusedBlockID = blockID
        }
    }

    /// Focus with an explicit caret placement (used after structural edits).
    func focus(_ blockID: UUID?, caretOffsetFromEnd: Int?) {
        guard let blockID else { return }
        focus(blockID)
        guard let caretOffsetFromEnd else { return }
        caretRequest = BlockCaretRequest(
            blockID: blockID,
            utf16OffsetFromEnd: caretOffsetFromEnd,
            token: (caretRequest?.token ?? 0) + 1
        )
    }

    func commandTargetID(for blockID: UUID?, baseTargetID: String?) -> String? {
        guard let baseTargetID, !baseTargetID.isEmpty else { return nil }
        guard let blockID else { return baseTargetID }

        if focusedBlockID == blockID || (focusedBlockID == nil && registeredBlockIDs.first == blockID) {
            return baseTargetID
        }

        return "\(baseTargetID):block:\(blockID.uuidString)"
    }

    @discardableResult
    func focusNext() -> Bool {
        moveFocus(offset: 1)
    }

    @discardableResult
    func focusPrevious() -> Bool {
        moveFocus(offset: -1)
    }

    func focusInto(elementID: UUID?) {
        focus(elementID)
    }

    func focusOutOf(elementID: UUID?) {
        if focusedBlockID == elementID {
            focusedBlockID = nil
        }
    }

    private func moveFocus(offset: Int) -> Bool {
        guard !registeredBlockIDs.isEmpty else { return false }
        guard let focusedBlockID,
              let currentIndex = registeredBlockIDs.firstIndex(of: focusedBlockID) else {
            return false
        }

        let nextIndex = currentIndex + offset
        guard registeredBlockIDs.indices.contains(nextIndex) else { return false }
        self.focusedBlockID = registeredBlockIDs[nextIndex]
        return true
    }
}
