// CosmoOS/Navigation/PaneManager.swift
// State manager for the split-pane system
// Tracks open panes, divider positions, and active pane for singleton coordination

import SwiftUI

// MARK: - Pane Content

enum PaneChromeStyle: Equatable {
    case standard
    case minimal
}

/// What a single pane displays — either a focus mode for an atom or a thinkspace canvas
enum PaneContent: Identifiable, Equatable {
    case entity(EntitySelection)
    case thinkspace(thinkspaceId: String)
    case commandCenter
    case swipeGallery
    case webBrowser(url: URL, title: String?)
    case cosmoWindow
    case collaborator(target: CollaborationTarget, presetId: String?)
    case inlineAssistant

    var id: String {
        switch self {
        case .entity(let entity):
            return "entity_\(entity.type.rawValue)_\(entity.id)"
        case .thinkspace(let thinkspaceId):
            return "thinkspace_\(thinkspaceId)"
        case .commandCenter:
            return "commandCenter"
        case .swipeGallery:
            return "swipeGallery"
        case .webBrowser(let url, _):
            return "web_\(url.absoluteString)"
        case .cosmoWindow:
            return "cosmoWindow"
        case .collaborator:
            return "collaborator"
        case .inlineAssistant:
            return "inlineAssistant"
        }
    }

    /// The entity ID if this is an entity pane (for duplicate prevention)
    var entityId: Int64? {
        switch self {
        case .entity(let entity): return entity.id
        case .thinkspace, .commandCenter, .swipeGallery, .webBrowser, .cosmoWindow, .collaborator, .inlineAssistant: return nil
        }
    }

    /// The entity selection if this is an entity pane
    var entitySelection: EntitySelection? {
        switch self {
        case .entity(let entity): return entity
        case .thinkspace, .commandCenter, .swipeGallery, .webBrowser, .cosmoWindow, .collaborator, .inlineAssistant: return nil
        }
    }

    /// The thinkspace ID if this is a thinkspace pane
    var thinkspaceId: String? {
        switch self {
        case .entity, .commandCenter, .swipeGallery, .webBrowser, .cosmoWindow, .collaborator, .inlineAssistant: return nil
        case .thinkspace(let id): return id
        }
    }

    var webURL: URL? {
        guard case .webBrowser(let url, _) = self else { return nil }
        return url
    }

    var collaborationTarget: CollaborationTarget? {
        guard case .collaborator(let target, _) = self else { return nil }
        return target
    }

    var chromeStyle: PaneChromeStyle {
        switch self {
        case .cosmoWindow, .collaborator, .inlineAssistant:
            return .minimal
        case .entity, .thinkspace, .commandCenter, .swipeGallery, .webBrowser:
            return .standard
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

    /// Ordered list of open panes (right column deck, in opening order)
    @Published var panes: [PaneContent] = [] {
        didSet {
            // From the first pane until the deck's slide-out completes (its
            // onDisappear in SplitPaneContainer), canvas screenshot capture is
            // suppressed — the deck would otherwise be composited into a
            // thinkspace's stored thumbnail.
            if !panes.isEmpty {
                PaneDeckPresentationState.shared.setOnScreen(true)
            }
        }
    }

    /// The pane expanded to full reading width. Every other pane collapses to a spine.
    @Published var focusedPaneId: String? = nil

    /// Optional second pane kept expanded beside the focused one (60/40 split).
    /// Pinning the focused pane keeps it visible while focus moves elsewhere.
    @Published var pinnedPaneId: String? = nil

    /// Horizontal split ratio between left (main content) and right (pane column).
    /// 1.0 = full width (no panes visible). Animates to 0.5 when first pane opens.
    @Published var mainSplitRatio: CGFloat = 1.0

    /// ID of the pane the user last interacted with (tap/focus).
    /// Used to determine which pane's context the CosmoWindow and voice system see.
    @Published var activePaneId: String? = nil

    /// ID of the pane whose entity currently owns global context while another pane
    /// (such as the collaborator) may be focused.
    @Published var contextOwnerPaneId: String? = nil

    // MARK: - Constants

    /// Maximum number of simultaneous panes in the deck (spines are cheap)
    let maxPanes: Int = 6

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

    /// Set of web URLs currently open in panes.
    var openBrowserURLs: Set<URL> {
        Set(panes.compactMap { $0.webURL })
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

    /// Check if Command Center can be opened as a pane.
    func canOpenCommandCenter() -> Bool {
        guard !panes.contains(where: { $0.id == PaneContent.commandCenter.id }) else { return false }
        guard panes.count < maxPanes else { return false }
        return true
    }

    /// Check if Swipe Gallery can be opened as a pane.
    func canOpenSwipeGallery() -> Bool {
        guard !panes.contains(where: { $0.id == PaneContent.swipeGallery.id }) else { return false }
        guard panes.count < maxPanes else { return false }
        return true
    }

    /// Check if a browser pane can be opened for the URL.
    func canOpenBrowser(url: URL) -> Bool {
        guard !openBrowserURLs.contains(url) else { return false }
        guard panes.count < maxPanes else { return false }
        return true
    }

    // MARK: - Pane Lifecycle

    /// Open a new pane. Silently ignores if content is already open or max reached.
    func openPane(_ content: PaneContent) {
        // Check duplicates
        guard !panes.contains(where: { $0.id == content.id }) else { return }
        guard panes.count < maxPanes else { return }

        let isFirst = panes.isEmpty
        panes.append(content)

        // New panes open focused; the previous focus collapses to a spine
        focusedPaneId = content.id

        // Auto-activate the newly opened pane
        activePaneId = content.id
        contextOwnerPaneId = content.entitySelection != nil ? content.id : contextOwnerPaneId

        // Animate split ratio when first pane opens
        if isFirst {
            withAnimation(ProMotionSprings.snappy) {
                mainSplitRatio = 0.5
            }
        }
    }

    /// Close a pane at a specific index.
    func closePane(at index: Int) {
        guard panes.indices.contains(index) else { return }
        let closedPane = panes[index]
        let closedId = closedPane.id
        panes.remove(at: index)

        if pinnedPaneId == closedId {
            pinnedPaneId = nil
        }
        if focusedPaneId == closedId {
            // Focus falls back to the most recently opened remaining pane
            focusedPaneId = panes.last?.id
        }

        if closedId == "collaborator" {
            Task { @MainActor in
                await CosmoWindowViewModel.shared.deactivateCollaborator()
            }
        }

        // If the closed pane was active, activate the last remaining pane
        if activePaneId == closedId {
            activePaneId = panes.last?.id
        }

        if contextOwnerPaneId == closedId {
            if let collaborator = panes.first(where: { $0.id == "collaborator" }),
               let targetPaneID = collaborator.collaborationTarget?.paneID,
               panes.contains(where: { $0.id == targetPaneID }) {
                contextOwnerPaneId = targetPaneID
            } else {
                contextOwnerPaneId = panes.reversed().first(where: { $0.entitySelection != nil })?.id
            }
        } else if closedPane.id == "collaborator" {
            contextOwnerPaneId = panes.reversed().first(where: { $0.entitySelection != nil })?.id
        }

        // Animate split ratio back to full width when all panes are closed
        if panes.isEmpty {
            withAnimation(ProMotionSprings.snappy) {
                mainSplitRatio = 1.0
            }
            activePaneId = nil
            contextOwnerPaneId = nil
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

    /// Close the focused pane (Esc). Falls back to the most recent pane.
    func closeFocusedPane() {
        if let focusedPaneId,
           let index = panes.firstIndex(where: { $0.id == focusedPaneId }) {
            closePane(at: index)
        } else {
            closeLastPane()
        }
    }

    /// Close all panes and reset state.
    func closeAllPanes() {
        panes.removeAll()
        focusedPaneId = nil
        pinnedPaneId = nil
        withAnimation(ProMotionSprings.snappy) {
            mainSplitRatio = 1.0
        }
        activePaneId = nil
        contextOwnerPaneId = nil
    }

    // MARK: - Focus & Pin (deck model)

    /// Expand a pane to reading width; everything else collapses to spines.
    func focusPane(_ id: String) {
        guard panes.contains(where: { $0.id == id }) else { return }
        focusedPaneId = id
        activatePane(id)
    }

    /// Focus the pane at a deck position (Cmd+Ctrl+1…6).
    func focusPane(atPosition index: Int) {
        guard panes.indices.contains(index) else { return }
        focusPane(panes[index].id)
    }

    /// Cycle focus through the deck in opening order (Cmd+Shift+] / [).
    func cycleFocus(forward: Bool) {
        guard !panes.isEmpty else { return }
        guard let current = focusedPaneId ?? panes.last?.id,
              let index = panes.firstIndex(where: { $0.id == current }) else {
            focusPane(panes[0].id)
            return
        }
        let next = forward
            ? (index + 1) % panes.count
            : (index - 1 + panes.count) % panes.count
        focusPane(panes[next].id)
    }

    /// Pin (or unpin) a pane so it stays expanded beside the focused one.
    /// With no id, toggles the focused pane.
    func togglePin(_ id: String? = nil) {
        guard let target = id ?? focusedPaneId,
              panes.contains(where: { $0.id == target }) else { return }
        pinnedPaneId = (pinnedPaneId == target) ? nil : target
    }

    // MARK: - Active Pane Management

    /// Set the active pane and update singleton contexts accordingly.
    func activatePane(_ id: String) {
        guard activePaneId != id else { return }
        activePaneId = id

        if let pane = panes.first(where: { $0.id == id }) {
            if let entity = pane.entitySelection {
                contextOwnerPaneId = id
                VoiceContextStore.shared.focusedEntity = entity
            } else if let targetPaneID = pane.collaborationTarget?.paneID,
                      panes.contains(where: { $0.id == targetPaneID }) {
                contextOwnerPaneId = targetPaneID
            }
        }
    }

    func openOrActivateCollaborator(target: CollaborationTarget, presetId: String?) {
        let collaborator = PaneContent.collaborator(target: target, presetId: presetId)

        if let existingIndex = panes.firstIndex(where: { $0.id == collaborator.id }) {
            panes[existingIndex] = collaborator
            activePaneId = collaborator.id
            focusedPaneId = collaborator.id
        } else {
            guard panes.count < maxPanes else { return }
            let isFirst = panes.isEmpty

            if let targetPaneID = target.paneID,
               let targetIndex = panes.firstIndex(where: { $0.id == targetPaneID }) {
                panes.insert(collaborator, at: min(targetIndex + 1, panes.count))
            } else {
                panes.append(collaborator)
            }
            activePaneId = collaborator.id
            focusedPaneId = collaborator.id

            if isFirst {
                withAnimation(ProMotionSprings.snappy) {
                    mainSplitRatio = 0.5
                }
            }
        }

        contextOwnerPaneId = target.paneID
    }

    func openOrActivateCosmoWindow() {
        let cosmoWindow = PaneContent.cosmoWindow

        if panes.contains(where: { $0.id == cosmoWindow.id }) {
            activePaneId = cosmoWindow.id
            focusedPaneId = cosmoWindow.id
            return
        }

        guard panes.count < maxPanes else { return }
        let isFirst = panes.isEmpty
        panes.append(cosmoWindow)
        activePaneId = cosmoWindow.id
        focusedPaneId = cosmoWindow.id

        if isFirst {
            withAnimation(ProMotionSprings.snappy) {
                mainSplitRatio = 0.5
            }
        }
    }

    func openOrActivateInlineAssistant() {
        let assistant = PaneContent.inlineAssistant

        if panes.contains(where: { $0.id == assistant.id }) {
            activePaneId = assistant.id
            focusedPaneId = assistant.id
            return
        }

        guard panes.count < maxPanes else { return }
        let isFirst = panes.isEmpty
        panes.append(assistant)
        activePaneId = assistant.id
        focusedPaneId = assistant.id

        if isFirst {
            withAnimation(ProMotionSprings.snappy) {
                mainSplitRatio = 0.5
            }
        }
    }

    func closeCollaborator() {
        guard let index = panes.firstIndex(where: { $0.id == "collaborator" }) else { return }
        closePane(at: index)
    }

    func updateCollaboratorTarget(_ target: CollaborationTarget, presetId: String?) {
        guard let index = panes.firstIndex(where: { $0.id == "collaborator" }) else { return }
        panes[index] = .collaborator(target: target, presetId: presetId)
        contextOwnerPaneId = target.paneID
    }

    var collaboratorTarget: CollaborationTarget? {
        panes.first(where: { $0.id == "collaborator" })?.collaborationTarget
    }

    func entitySelection(forPaneID id: String?) -> EntitySelection? {
        guard let id else { return nil }
        return panes.first(where: { $0.id == id })?.entitySelection
    }

    func paneID(for selection: EntitySelection) -> String? {
        panes.first(where: { $0.entitySelection == selection })?.id
    }

    func pushContextOwnerToVoiceStore() {
        if let entity = entitySelection(forPaneID: contextOwnerPaneId) {
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

}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int, default defaultValue: Element) -> Element {
        indices.contains(index) ? self[index] : defaultValue
    }
}
