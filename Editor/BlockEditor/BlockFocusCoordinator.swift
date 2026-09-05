import Foundation
import Observation

/// A one-shot caret placement attached to a focus change after a structural
/// edit (split/merge/delete). Offset is from the END of the block's text in
/// UTF-16 — immune to rendered list/quote prefixes at the head.
struct BlockCaretRequest: Equatable {
    var blockID: UUID
    var utf16OffsetFromEnd: Int
    var token: Int
    var windowPoint: CGPoint? = nil
}

/// Per-row focus signals. Row bodies read ONLY their own instance, so a focus
/// change invalidates the two affected rows instead of every mounted row —
/// Observation tracks whole properties, and a `focusedBlockID` read from every
/// row body made each click/split/merge re-render O(rows) text editors.
/// Instances are created on demand and NEVER removed: a mounted row's tracked
/// dependency is on the instance, so replacing it would silently orphan the
/// row from future focus writes.
@MainActor
@Observable
final class BlockRowFocusState {
    var isFocused = false
    /// Whether commands with no explicit target route to this row (it is
    /// focused, or it is the first registered row while nothing is focused).
    var isCommandTarget = false
    /// One-shot caret placement narrowed to this row.
    var caretRequest: BlockCaretRequest?
}

@MainActor
@Observable
final class BlockFocusCoordinator {
    private(set) var focusedBlockID: UUID?
    /// Whether ANY block is focused. Tracked separately so row chrome that
    /// only cares about the nil transition (paragraph-focus dimming) doesn't
    /// re-render on every focus MOVE — that signal rides the per-row states.
    private(set) var hasFocusedBlock = false
    @ObservationIgnored private(set) var caretRequest: BlockCaretRequest?
    /// Per-row focus signals keyed by block ID — see `BlockRowFocusState`.
    @ObservationIgnored private var rowStates: [UUID: BlockRowFocusState] = [:]
    /// The row currently flagged `isCommandTarget` (focused ?? first registered).
    @ObservationIgnored private var commandTargetBlockID: UUID?
    /// Self-authored content ledger: the last block value each ROW ITSELF
    /// wrote into the document (per-keystroke content syncs). The row
    /// Equatable gates consult it so a row's own write echoing back through
    /// the whole-document binding does not re-render that row — its text
    /// view is already showing the content it just produced. External writes
    /// never pass through here, so they always fail the gate and re-render.
    @ObservationIgnored private var selfAuthoredBlocks: [UUID: RichBlock] = [:]

    func noteSelfAuthoredBlock(_ block: RichBlock) {
        selfAuthoredBlocks[block.id] = block
    }

    func selfAuthoredBlock(for blockID: UUID) -> RichBlock? {
        selfAuthoredBlocks[blockID]
    }

    /// Whether a block-value change between two row snapshots is the row's
    /// own per-keystroke write echoing back through the document binding —
    /// safe to skip re-rendering (the row's text view already shows it).
    /// Deliberately conservative: any change of kind, heading, children, or
    /// emptiness re-renders (those drive row chrome, typing-attribute seeds,
    /// and placeholder visibility), as does anything not EXACTLY equal to
    /// the last self-written value (i.e. every external write).
    func isSelfAuthoredEcho(previous: RichBlock, next: RichBlock) -> Bool {
        guard previous.id == next.id,
              previous.kind == next.kind,
              next.kind != .element,
              previous.heading == next.heading,
              previous.children.isEmpty, next.children.isEmpty,
              previous.plainInlineText.isEmpty == next.plainInlineText.isEmpty,
              let written = selfAuthoredBlocks[next.id],
              written == next else {
            return false
        }
        return true
    }
    /// Blocks that currently have a live editor row (membership). Maintained by
    /// register/unregister on row appear/disappear. Order here reflects AppKit
    /// onAppear timing, NOT document order — do not navigate by it directly.
    /// Observation-ignored: it is only read imperatively (key handlers), and a
    /// long note registers every row on mount — tracking it from row bodies
    /// made each registration invalidate every mounted row (quadratic open).
    @ObservationIgnored private var registeredBlockIDs: [UUID] = []
    /// The first registered row — the command-routing default while nothing is
    /// focused. Observation-ignored: rows learn about command routing through
    /// their own `BlockRowFocusState.isCommandTarget`, so this changing (first
    /// mount, first-row delete) touches at most two row states instead of
    /// invalidating every row body.
    @ObservationIgnored private(set) var firstRegisteredBlockID: UUID?
    /// The document's visual (top-to-bottom) block order, supplied by the block
    /// list. Keyboard navigation walks THIS order so ⬆/⬇ always match what the
    /// user sees, regardless of the order rows happened to mount in.
    @ObservationIgnored private var navigationOrder: [UUID] = []

    /// The per-row focus signal for `blockID`. Stable identity for the
    /// coordinator's lifetime — row bodies read their own instance so focus
    /// writes invalidate only the rows they concern.
    func rowState(for blockID: UUID) -> BlockRowFocusState {
        if let state = rowStates[blockID] { return state }
        let state = BlockRowFocusState()
        rowStates[blockID] = state
        return state
    }

    func register(_ blockID: UUID?) {
        guard let blockID, !registeredBlockIDs.contains(blockID) else { return }
        registeredBlockIDs.append(blockID)
        if firstRegisteredBlockID == nil {
            firstRegisteredBlockID = blockID
            refreshCommandTarget()
        }
    }

    func unregister(_ blockID: UUID?) {
        guard let blockID else { return }
        registeredBlockIDs.removeAll { $0 == blockID }
        if firstRegisteredBlockID == blockID {
            firstRegisteredBlockID = registeredBlockIDs.first
        }
        if focusedBlockID == blockID {
            setFocusedBlockID(nil)
        } else {
            refreshCommandTarget()
        }
    }

    /// The one writer of `focusedBlockID` — keeps the per-row `isFocused`
    /// flags and the command-target flag in lockstep with the tracked value.
    private func setFocusedBlockID(_ newValue: UUID?) {
        guard focusedBlockID != newValue else { return }
        let previous = focusedBlockID
        focusedBlockID = newValue
        if hasFocusedBlock != (newValue != nil) {
            hasFocusedBlock = (newValue != nil)
        }
        if let previous, let state = rowStates[previous], state.isFocused {
            state.isFocused = false
            state.caretRequest = nil
        }
        if let newValue {
            let state = rowState(for: newValue)
            if !state.isFocused {
                state.isFocused = true
            }
        }
        refreshCommandTarget()
    }

    private func refreshCommandTarget() {
        let target = focusedBlockID ?? firstRegisteredBlockID
        guard target != commandTargetBlockID else { return }
        if let previous = commandTargetBlockID, let state = rowStates[previous], state.isCommandTarget {
            state.isCommandTarget = false
        }
        commandTargetBlockID = target
        if let target {
            let state = rowState(for: target)
            if !state.isCommandTarget {
                state.isCommandTarget = true
            }
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
        // setFocusedBlockID dedups same-value writes so the per-keystroke
        // focus reaffirmation doesn't notify Observation.
        setFocusedBlockID(blockID)
    }

    /// Focus with an explicit caret placement (used after structural edits).
    func focus(_ blockID: UUID?, caretOffsetFromEnd: Int?, windowPoint: CGPoint? = nil) {
        guard let blockID else { return }
        focus(blockID)
        guard let caretOffsetFromEnd else { return }
        caretRequest = BlockCaretRequest(
            blockID: blockID,
            utf16OffsetFromEnd: caretOffsetFromEnd,
            token: (caretRequest?.token ?? 0) + 1,
            windowPoint: windowPoint
        )
        // Only the target row observes its own request — placing the caret
        // after a split must not re-render every other mounted row.
        rowState(for: blockID).caretRequest = caretRequest
    }

    func commandTargetID(for blockID: UUID?, baseTargetID: String?) -> String? {
        guard let baseTargetID, !baseTargetID.isEmpty else { return nil }
        guard let blockID else { return baseTargetID }

        // Reads the per-row flag so a body calling this depends on its own
        // row state, not on the coordinator-wide focus properties.
        if rowState(for: blockID).isCommandTarget {
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
            setFocusedBlockID(nil)
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
        lastNavigationOffset = offset
        setFocusedBlockID(order[nextIndex])
        return true
    }

    /// The direction of the last ⬆/⬇ navigation (−1 = moved up, +1 = moved
    /// down). A container that gains focus this way (a table) enters at its
    /// last row when the user came from below. Imperative read only — never
    /// tracked from a row body.
    @ObservationIgnored private(set) var lastNavigationOffset = 1

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
