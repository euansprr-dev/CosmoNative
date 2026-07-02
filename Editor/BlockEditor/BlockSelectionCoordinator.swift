import AppKit
import Foundation
import Observation
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// Structured block copy: JSON-encoded [RichBlock] — kinds, checked
    /// state, and nesting survive copy/paste within the app.
    static let cosmoBlocks = NSPasteboard.PasteboardType("com.cosmo.blocks")
}

/// Phase of a mouse drag that started inside a block row's text view.
enum BlockDragPhase {
    case began
    case changed
    case ended
}

/// What the block list decided about a drag point: `textLocal` keeps the
/// origin text view's native character selection; `escalated` means the drag
/// crossed a block boundary and whole-block selection has taken over.
enum BlockDragResolution {
    case textLocal
    case escalated
}

/// Bridges mouse drags from per-block NSTextViews up to the block list
/// (Notion model: drag within a block = native text selection; crossing a
/// block boundary escalates to whole-block range selection; dragging back
/// into the origin de-escalates). NSTextView tracks selection drags in a
/// modal loop inside mouseDown, so CosmoTextView owns its own loop in
/// block-row mode and consults this controller per event. The block list
/// wires the closures; text views reach the controller through the
/// environment, mirroring EditorOverlayPresenter.
@MainActor
final class BlockDragSelectionController {
    /// Wired by the owning BlockListView. Receives the drag point in WINDOW
    /// coordinates (AppKit, bottom-left origin) plus the text view for
    /// coordinate conversion context.
    var handleDrag: ((_ windowPoint: NSPoint, _ phase: BlockDragPhase, _ textView: NSTextView) -> BlockDragResolution)?
    /// Shift+Click in a block row while another block holds focus/selection —
    /// returns true when the list consumed it as a range-selection extension.
    var handleShiftClick: ((_ windowPoint: NSPoint, _ textView: NSTextView) -> Bool)?

    /// Session state, managed by the list's handleDrag.
    var originBlockID: UUID?
    var isEscalated = false
    /// The block list's frame in SwiftUI .global space — lives HERE (plain
    /// class) instead of view @State because a .global frame changes on
    /// every scroll tick, and writing it into @State re-rendered the entire
    /// block list continuously while scrolling.
    var listGlobalFrame: CGRect = .zero
}

private struct BlockDragSelectionControllerKey: EnvironmentKey {
    static let defaultValue: BlockDragSelectionController? = nil
}

extension EnvironmentValues {
    /// Set by the top-level BlockListView; block-row text views route their
    /// selection drags through it.
    var blockDragSelectionController: BlockDragSelectionController? {
        get { self[BlockDragSelectionControllerKey.self] }
        set { self[BlockDragSelectionControllerKey.self] = newValue }
    }
}

/// Root-block frames in the block list's coordinate space, for hit-testing a
/// drag point to a block. Plain class (not @Observable) — frame updates must
/// not invalidate any view body.
@MainActor
final class BlockLayoutIndex {
    private(set) var frames: [UUID: CGRect] = [:]

    func update(_ frame: CGRect, for blockID: UUID) {
        frames[blockID] = frame
    }

    func remove(_ blockID: UUID) {
        frames[blockID] = nil
    }

    /// The root block under (or nearest to) the given Y, restricted to the
    /// document's current root order so stale frames of deleted blocks never
    /// win.
    func blockID(atY y: CGFloat, rootOrder: [UUID]) -> UUID? {
        var best: (id: UUID, distance: CGFloat)?
        for id in rootOrder {
            guard let frame = frames[id] else { continue }
            if y >= frame.minY, y <= frame.maxY { return id }
            let distance = y < frame.minY ? frame.minY - y : y - frame.maxY
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }
        return best?.id
    }
}

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

/// Routes keyboard input to an active block selection at the AppKit level.
/// The SwiftUI path (focusable + @FocusState + onKeyPress) races the
/// makeFirstResponder(nil) handoff and can drop keys — with this monitor,
/// ⌫/arrows/Return/Esc/⌘D/⌘A work the instant blocks are selected.
@MainActor
final class BlockSelectionKeyMonitor {
    private var monitor: Any?

    /// Installs the local keyDown monitor (idempotent). The handler returns
    /// true when it consumed the event.
    func install(_ handler: @escaping (NSEvent) -> Bool) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
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
