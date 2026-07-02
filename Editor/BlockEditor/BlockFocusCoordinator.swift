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
    /// Blocks that currently have a live editor row (membership). Maintained by
    /// register/unregister on row appear/disappear. Order here reflects AppKit
    /// onAppear timing, NOT document order — do not navigate by it directly.
    private var registeredBlockIDs: [UUID] = []
    /// The document's visual (top-to-bottom) block order, supplied by the block
    /// list. Keyboard navigation walks THIS order so ⬆/⬇ always match what the
    /// user sees, regardless of the order rows happened to mount in.
    private var navigationOrder: [UUID] = []

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

    /// Feeds the coordinator the document's visual block order (a flattened,
    /// pre-order list of every block ID, including nested element children).
    /// Called by the top-level block list whenever the structure changes, so
    /// arrow navigation can move in document order instead of mount order.
    func syncNavigationOrder(_ orderedBlockIDs: [UUID]) {
        guard navigationOrder != orderedBlockIDs else { return }
        navigationOrder = orderedBlockIDs
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
        let order = navigableOrder()
        guard !order.isEmpty,
              let focusedBlockID,
              let currentIndex = order.firstIndex(of: focusedBlockID) else {
            return false
        }

        let nextIndex = currentIndex + offset
        guard order.indices.contains(nextIndex) else { return false }
        self.focusedBlockID = order[nextIndex]
        return true
    }

    /// The blocks reachable by ⬆/⬇, in document order. We start from the visual
    /// `navigationOrder` and keep only IDs that currently have a live editor
    /// (so dividers/images and collapsed-away rows are skipped), then append any
    /// registered rows the order hasn't caught up with yet (a row that mounted
    /// before the next order sync) so navigation never strands a block. Falls
    /// back to registration order when no document order has been supplied
    /// (e.g. the coordinator used standalone in tests).
    private func navigableOrder() -> [UUID] {
        guard !navigationOrder.isEmpty else { return registeredBlockIDs }
        let registered = Set(registeredBlockIDs)
        var ordered = navigationOrder.filter { registered.contains($0) }
        let known = Set(ordered)
        ordered.append(contentsOf: registeredBlockIDs.filter { !known.contains($0) })
        return ordered
    }
}
