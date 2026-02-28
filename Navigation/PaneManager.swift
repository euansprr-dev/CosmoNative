// CosmoOS/Navigation/PaneManager.swift
// State manager for the split-pane system
// Tracks open panes, divider positions, and active pane for singleton coordination

import SwiftUI

// MARK: - Pane Content

/// What a single pane displays — either a focus mode for an atom or a thinkspace canvas
enum PaneContent: Identifiable, Equatable {
    case entity(EntitySelection)
    case thinkspace(thinkspaceId: String)

    var id: String {
        switch self {
        case .entity(let entity):
            return "entity_\(entity.type.rawValue)_\(entity.id)"
        case .thinkspace(let thinkspaceId):
            return "thinkspace_\(thinkspaceId)"
        }
    }

    /// The entity ID if this is an entity pane (for duplicate prevention)
    var entityId: Int64? {
        switch self {
        case .entity(let entity): return entity.id
        case .thinkspace: return nil
        }
    }

    /// The entity selection if this is an entity pane
    var entitySelection: EntitySelection? {
        switch self {
        case .entity(let entity): return entity
        case .thinkspace: return nil
        }
    }

    /// The thinkspace ID if this is a thinkspace pane
    var thinkspaceId: String? {
        switch self {
        case .entity: return nil
        case .thinkspace(let id): return id
        }
    }

    static func == (lhs: PaneContent, rhs: PaneContent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Pane Manager

@MainActor
class PaneManager: ObservableObject {

    // MARK: - Published State

    /// Ordered list of open panes (right column, top to bottom)
    @Published var panes: [PaneContent] = []

    /// Proportional height for each pane in the right column.
    /// Count always matches `panes.count`. Values sum to 1.0.
    @Published var paneSizes: [CGFloat] = []

    /// Horizontal split ratio between left (main content) and right (pane column).
    /// 0.5 = equal split. Clamped to 0.25...0.75.
    @Published var mainSplitRatio: CGFloat = 0.5

    /// ID of the pane the user last interacted with (tap/focus).
    /// Used to determine which pane's context the CosmoWindow and voice system see.
    @Published var activePaneId: String? = nil

    // MARK: - Constants

    /// Maximum number of simultaneous panes in the right column
    let maxPanes: Int = 4

    /// Minimum proportional height per pane (prevents panes from being too small)
    private let minPaneSize: CGFloat = 0.15

    /// Minimum/maximum main split ratio
    private let minMainRatio: CGFloat = 0.25
    private let maxMainRatio: CGFloat = 0.75

    // MARK: - Computed Properties

    /// Whether the split-pane layout is active (at least one pane open)
    var isActive: Bool { !panes.isEmpty }

    /// Set of all entity IDs currently open in panes (for duplicate prevention)
    var openEntityIds: Set<Int64> {
        Set(panes.compactMap { $0.entityId })
    }

    /// Set of all thinkspace IDs currently open in panes
    var openThinkspaceIds: Set<String> {
        Set(panes.compactMap { $0.thinkspaceId })
    }

    // MARK: - Duplicate Prevention

    /// Check if an entity can be opened as a pane.
    /// Returns false if the entity is already open in another pane or as the main focus mode.
    func canOpen(entityId: Int64, appState: AppState) -> Bool {
        // Already open in a pane?
        guard !openEntityIds.contains(entityId) else { return false }
        // Already open as the main focus mode?
        guard appState.focusedEntity?.id != entityId else { return false }
        // Room for more panes?
        guard panes.count < maxPanes else { return false }
        return true
    }

    /// Check if a thinkspace can be opened as a pane.
    func canOpenThinkspace(thinkspaceId: String) -> Bool {
        guard !openThinkspaceIds.contains(thinkspaceId) else { return false }
        guard panes.count < maxPanes else { return false }
        return true
    }

    // MARK: - Pane Lifecycle

    /// Open a new pane. Silently ignores if content is already open or max reached.
    func openPane(_ content: PaneContent) {
        // Check duplicates
        guard !panes.contains(where: { $0.id == content.id }) else { return }
        guard panes.count < maxPanes else { return }

        panes.append(content)
        redistributeSizes()

        // Auto-activate the newly opened pane
        activePaneId = content.id
    }

    /// Close a pane at a specific index.
    func closePane(at index: Int) {
        guard panes.indices.contains(index) else { return }
        let closedId = panes[index].id
        panes.remove(at: index)
        redistributeSizes()

        // If the closed pane was active, activate the last remaining pane
        if activePaneId == closedId {
            activePaneId = panes.last?.id
        }

        // Reset split ratio when all panes are closed
        if panes.isEmpty {
            mainSplitRatio = 0.5
            activePaneId = nil
        }
    }

    /// Close a pane by its content.
    func closePane(_ content: PaneContent) {
        guard let index = panes.firstIndex(where: { $0.id == content.id }) else { return }
        closePane(at: index)
    }

    /// Close the most recently opened pane (last in the array). Used by escape key.
    func closeLastPane() {
        guard !panes.isEmpty else { return }
        closePane(at: panes.count - 1)
    }

    /// Close all panes and reset state.
    func closeAllPanes() {
        panes.removeAll()
        paneSizes.removeAll()
        mainSplitRatio = 0.5
        activePaneId = nil
    }

    // MARK: - Active Pane Management

    /// Set the active pane and update singleton contexts accordingly.
    func activatePane(_ id: String) {
        guard activePaneId != id else { return }
        activePaneId = id

        // Push active pane's entity to VoiceContextStore
        if let pane = panes.first(where: { $0.id == id }),
           let entity = pane.entitySelection {
            VoiceContextStore.shared.focusedEntity = entity
        }
    }

    // MARK: - Divider Management

    /// Update the main horizontal split ratio from a drag delta.
    func updateMainSplit(delta: CGFloat, totalWidth: CGFloat) {
        guard totalWidth > 0 else { return }
        let deltaRatio = delta / totalWidth
        let newRatio = mainSplitRatio + deltaRatio
        mainSplitRatio = max(minMainRatio, min(maxMainRatio, newRatio))
    }

    /// Update a vertical divider between pane at `index` and `index + 1`.
    func updateDivider(at index: Int, delta: CGFloat, totalHeight: CGFloat) {
        guard totalHeight > 0 else { return }
        guard index < paneSizes.count - 1 else { return }

        let deltaRatio = delta / totalHeight
        let newTop = paneSizes[index] + deltaRatio
        let newBottom = paneSizes[index + 1] - deltaRatio

        // Enforce minimum sizes
        guard newTop >= minPaneSize, newBottom >= minPaneSize else { return }

        paneSizes[index] = newTop
        paneSizes[index + 1] = newBottom
    }

    // MARK: - Internal

    /// Redistribute pane sizes evenly after add/remove.
    private func redistributeSizes() {
        let count = panes.count
        guard count > 0 else {
            paneSizes = []
            return
        }
        paneSizes = Array(repeating: 1.0 / CGFloat(count), count: count)
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int, default defaultValue: Element) -> Element {
        indices.contains(index) ? self[index] : defaultValue
    }
}
