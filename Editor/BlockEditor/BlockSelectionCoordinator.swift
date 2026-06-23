import Foundation
import Observation

/// Direction of travel for keyboard-driven block selection.
enum BlockSelectionDirection {
    case up
    case down
}

/// Commands a text block raises into the surrounding block list's selection
/// (Esc selects the block; ⌘A on fully-selected text selects every block;
/// starting to edit any block clears block-level selection).
enum BlockSelectionEditorCommand {
    case selectCurrentBlock
    case selectAllBlocks
    case clearSelection
}

/// Block-level selection (Notion-style): whole blocks become the unit of
/// selection, layered on top of per-block text editing. The anchor is where
/// the selection started; the lead is the edge that moves when the selection
/// is extended with Shift+Arrows or Shift+Click.
///
/// Selection operates on root-level blocks only — selecting a block that
/// contains children (e.g. an element) selects it as one unit.
@MainActor
@Observable
final class BlockSelectionCoordinator {
    private(set) var selectedBlockIDs: Set<UUID> = []
    private(set) var anchorBlockID: UUID?
    private(set) var leadBlockID: UUID?

    var isActive: Bool { !selectedBlockIDs.isEmpty }

    func isSelected(_ blockID: UUID) -> Bool {
        selectedBlockIDs.contains(blockID)
    }

    func select(_ blockID: UUID) {
        selectedBlockIDs = [blockID]
        anchorBlockID = blockID
        leadBlockID = blockID
    }

    /// Shift+Click — keeps the existing anchor and selects everything between
    /// it and the clicked block.
    func selectRange(to blockID: UUID, in document: RichDocument) {
        let order = Self.rootOrder(in: document)
        guard let anchorBlockID,
              let anchorIndex = order.firstIndex(of: anchorBlockID),
              let targetIndex = order.firstIndex(of: blockID) else {
            select(blockID)
            return
        }
        leadBlockID = blockID
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedBlockIDs = Set(order[bounds])
    }

    func selectAll(in document: RichDocument) {
        let order = Self.rootOrder(in: document)
        guard !order.isEmpty else { return }
        selectedBlockIDs = Set(order)
        if anchorBlockID == nil || !order.contains(anchorBlockID!) {
            anchorBlockID = order.first
        }
        leadBlockID = order.last
    }

    func clear() {
        selectedBlockIDs = []
        anchorBlockID = nil
        leadBlockID = nil
    }

    /// Arrow key without Shift — collapses the selection to the single block
    /// past its edge in the direction of travel (clamped at the ends).
    @discardableResult
    func step(_ direction: BlockSelectionDirection, in document: RichDocument) -> Bool {
        let order = Self.rootOrder(in: document)
        guard let edgeIndex = edgeIndex(direction, order: order) else { return false }
        let nextIndex: Int
        switch direction {
        case .up: nextIndex = max(0, edgeIndex - 1)
        case .down: nextIndex = min(order.count - 1, edgeIndex + 1)
        }
        select(order[nextIndex])
        return true
    }

    /// Shift+Arrow — moves the lead edge while the anchor stays put.
    @discardableResult
    func extend(_ direction: BlockSelectionDirection, in document: RichDocument) -> Bool {
        let order = Self.rootOrder(in: document)
        guard let anchorBlockID,
              let anchorIndex = order.firstIndex(of: anchorBlockID) else { return false }
        let leadIndex = leadBlockID.flatMap { order.firstIndex(of: $0) } ?? anchorIndex
        let nextLead: Int
        switch direction {
        case .up: nextLead = max(0, leadIndex - 1)
        case .down: nextLead = min(order.count - 1, leadIndex + 1)
        }
        guard nextLead != leadIndex || selectedBlockIDs.count == 1 else { return false }
        leadBlockID = order[nextLead]
        let bounds = min(anchorIndex, nextLead)...max(anchorIndex, nextLead)
        selectedBlockIDs = Set(order[bounds])
        return true
    }

    /// Drops blocks that no longer exist (e.g. after deletion or external sync).
    func prune(against document: RichDocument) {
        let order = Set(Self.rootOrder(in: document))
        selectedBlockIDs = selectedBlockIDs.intersection(order)
        if let anchorBlockID, !order.contains(anchorBlockID) { self.anchorBlockID = selectedBlockIDs.first }
        if let leadBlockID, !order.contains(leadBlockID) { self.leadBlockID = anchorBlockID }
        if selectedBlockIDs.isEmpty {
            anchorBlockID = nil
            leadBlockID = nil
        }
    }

    /// Replaces the selection wholesale (e.g. after duplicating blocks).
    func setSelection(_ blockIDs: [UUID]) {
        selectedBlockIDs = Set(blockIDs)
        anchorBlockID = blockIDs.first
        leadBlockID = blockIDs.last
    }

    /// Selected ids in document order.
    func orderedSelection(in document: RichDocument) -> [UUID] {
        Self.rootOrder(in: document).filter { selectedBlockIDs.contains($0) }
    }

    static func rootOrder(in document: RichDocument) -> [UUID] {
        document.blocks.map(\.id)
    }

    private func edgeIndex(_ direction: BlockSelectionDirection, order: [UUID]) -> Int? {
        let selectedIndices = order.enumerated()
            .filter { selectedBlockIDs.contains($0.element) }
            .map(\.offset)
        switch direction {
        case .up: return selectedIndices.min()
        case .down: return selectedIndices.max()
        }
    }
}

enum BlockSelectionClipboardAction: Equatable {
    case cut
    case copy
    case selectAll
}

@MainActor
enum BlockSelectionClipboardTarget {
    private final class Target {
        let isActive: () -> Bool
        let perform: (BlockSelectionClipboardAction) -> Bool

        init(
            isActive: @escaping () -> Bool,
            perform: @escaping (BlockSelectionClipboardAction) -> Bool
        ) {
            self.isActive = isActive
            self.perform = perform
        }
    }

    private static var activeTarget: Target?

    static func activate(
        isActive: @escaping () -> Bool,
        perform: @escaping (BlockSelectionClipboardAction) -> Bool
    ) {
        activeTarget = Target(isActive: isActive, perform: perform)
    }

    static func deactivate() {
        activeTarget = nil
    }

    static func send(_ action: BlockSelectionClipboardAction) -> Bool {
        guard let target = activeTarget else { return false }
        guard target.isActive() else {
            activeTarget = nil
            return false
        }
        return target.perform(action)
    }
}
