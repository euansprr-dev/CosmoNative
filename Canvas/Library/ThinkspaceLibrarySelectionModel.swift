// CosmoOS/Canvas/Library/ThinkspaceLibrarySelectionModel.swift
// The Finder selection engine: multi-select with ⌘/⇧ modifiers, geometric
// arrow-key navigation, rubber-band marquee, and type-to-select. One model
// serves every lens — cells register their frames in the browser coordinate
// space and the model does pure geometry, so icons, list, and gallery all
// share identical muscle memory.

import SwiftUI
import AppKit

@MainActor
@Observable
final class ThinkspaceLibrarySelectionModel {

    // MARK: State

    private(set) var selected: Set<String> = []
    /// The range anchor for ⇧-clicks — the last plainly-clicked entry.
    private var anchorID: String?
    /// The entry keyboard navigation moves from (last touched).
    private(set) var focusedID: String?
    /// The entry currently renaming inline, if any — lenses render the field.
    var renamingID: String?

    /// Live marquee rectangle in browser-content space, while dragging.
    private(set) var marqueeRect: CGRect?
    private var marqueeBase: Set<String> = []

    // MARK: Registry (fed by the active lens)

    /// Cell frames in the browser coordinate space — content space, so they
    /// hold still while the page scrolls (the Today reorder lesson).
    private var frames: [String: CGRect] = [:]
    /// Visual order of everything selectable (folders first, then items).
    private(set) var orderedIDs: [String] = []
    private var titles: [String: String] = [:]

    private var typeBuffer = ""
    private var typeBufferStamp = Date.distantPast

    // MARK: Registration

    func register(id: String, frame: CGRect) {
        frames[id] = frame
    }

    /// Called whenever the visible set changes (folder navigation, search,
    /// sort). Prunes selection and frames so stale entries can never be
    /// selected, dragged, or keyboard-reached.
    func syncVisible(ids: [String], titles newTitles: [String: String]) {
        orderedIDs = ids
        titles = newTitles
        let visible = Set(ids)
        selected = selected.intersection(visible)
        frames = frames.filter { visible.contains($0.key) }
        if let anchorID, !visible.contains(anchorID) { self.anchorID = nil }
        if let focusedID, !visible.contains(focusedID) { self.focusedID = nil }
        if let renamingID, !visible.contains(renamingID) { self.renamingID = nil }
    }

    // MARK: Queries

    func isSelected(_ id: String) -> Bool { selected.contains(id) }
    var count: Int { selected.count }
    var isEmpty: Bool { selected.isEmpty }
    /// The representative entry for single-target actions (peek, rename).
    var primaryID: String? { focusedID ?? selected.first }
    var selectedIDs: [String] { orderedIDs.filter { selected.contains($0) } }

    // MARK: Clicks

    /// Finder's click grammar: plain = select one, ⌘ = toggle, ⇧ = range
    /// from the anchor. Right-clicks route through `prepareForMenu`.
    func click(_ id: String, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selected.contains(id) {
                selected.remove(id)
                if focusedID == id { focusedID = selected.first }
            } else {
                selected.insert(id)
                focusedID = id
                anchorID = id
            }
        } else if modifiers.contains(.shift), let anchorID,
                  let anchorIndex = orderedIDs.firstIndex(of: anchorID),
                  let clickedIndex = orderedIDs.firstIndex(of: id) {
            let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
            selected = Set(orderedIDs[range])
            focusedID = id
        } else {
            selected = [id]
            anchorID = id
            focusedID = id
        }
    }

    /// Right-click convention: a context menu over an unselected entry first
    /// makes it the selection; over a selected entry it keeps the group.
    func prepareForMenu(_ id: String) {
        guard !selected.contains(id) else { return }
        selected = [id]
        anchorID = id
        focusedID = id
    }

    func selectAll() {
        selected = Set(orderedIDs)
        focusedID = focusedID ?? orderedIDs.first
    }

    func clear() {
        selected = []
        anchorID = nil
        focusedID = nil
    }

    /// Replace the selection with one entry (used after mutations like rename).
    func select(only id: String) {
        selected = [id]
        anchorID = id
        focusedID = id
    }

    // MARK: Keyboard movement (geometric)

    enum MoveDirection {
        case up, down, left, right
    }

    /// Moves the focus to the geometrically nearest cell in a direction —
    /// works identically for a grid, a list (up/down), and a filmstrip
    /// (left/right) because it reads real frames, not indices. With `extend`
    /// (⇧) the selection grows; otherwise it follows the focus.
    /// Returns the new focused id so the view can scroll it into view.
    @discardableResult
    func move(_ direction: MoveDirection, extend: Bool = false) -> String? {
        guard let currentID = focusedID ?? selected.first ?? orderedIDs.first,
              let origin = frames[currentID] else {
            // Nothing focused yet: land on the first visible entry.
            if let first = orderedIDs.first {
                selected = [first]
                anchorID = first
                focusedID = first
                return first
            }
            return nil
        }
        guard focusedID != nil || !selected.isEmpty else {
            selected = [currentID]
            focusedID = currentID
            return currentID
        }

        let center = CGPoint(x: origin.midX, y: origin.midY)
        var best: (id: String, score: CGFloat)?
        for (id, frame) in frames where id != currentID {
            let candidate = CGPoint(x: frame.midX, y: frame.midY)
            let dx = candidate.x - center.x
            let dy = candidate.y - center.y
            let (primary, ortho): (CGFloat, CGFloat)
            switch direction {
            case .up: (primary, ortho) = (-dy, dx)
            case .down: (primary, ortho) = (dy, dx)
            case .left: (primary, ortho) = (-dx, dy)
            case .right: (primary, ortho) = (dx, dy)
            }
            guard primary > 1 else { continue }
            let score = primary + abs(ortho) * 2.5
            if best == nil || score < best!.score {
                best = (id, score)
            }
        }
        guard let target = best?.id else { return nil }
        if extend {
            selected.insert(target)
        } else {
            selected = [target]
            anchorID = target
        }
        focusedID = target
        return target
    }

    // MARK: Type-to-select

    /// Finder's type-ahead: typed characters accumulate for a second and jump
    /// the selection to the first title with that prefix.
    @discardableResult
    func typeToSelect(_ characters: String) -> String? {
        let now = Date()
        if now.timeIntervalSince(typeBufferStamp) > 1.0 { typeBuffer = "" }
        typeBufferStamp = now
        typeBuffer += characters.lowercased()

        let match = orderedIDs.first { id in
            (titles[id] ?? "").lowercased().hasPrefix(typeBuffer)
        }
        if let match {
            selected = [match]
            anchorID = match
            focusedID = match
        }
        return match
    }

    // MARK: Marquee

    /// Begin/extend the rubber band. `additive` (⌘ held at drag start) keeps
    /// the existing selection as a base and unions the swept entries.
    func marqueeChanged(_ rect: CGRect, additive: Bool) {
        if marqueeRect == nil {
            marqueeBase = additive ? selected : []
        }
        marqueeRect = rect
        let swept = Set(frames.filter { $0.value.intersects(rect) }.keys)
        selected = marqueeBase.union(swept)
        if let last = swept.first { focusedID = last }
    }

    func marqueeEnded() {
        marqueeRect = nil
        marqueeBase = []
    }
}
