// CosmoOS/Navigation/PaneManager.swift
// State manager for the split-pane system
// Tracks open panes, divider positions, and active pane for singleton coordination

import SwiftUI

// MARK: - Pane Content

enum PaneChromeStyle: Equatable {
    case standard
    case minimal
}

/// How a pane's body follows a continuous width stream (main-split divider
/// drag or window live resize).
enum PaneWidthStreamBehavior: Equatable {
    /// Re-lay-out at every width the stream produces. This is the default and
    /// what resizing should look like: the body reflows under the cursor.
    case tracksLive
    /// Follow a coarse width ladder instead of every pixel. Reserved for
    /// bodies deep enough that a per-event re-layout queues transactions
    /// faster than they finish and wedges the main thread (the July 28
    /// assistant-pane resize livelock).
    case tracksSteps
}

/// What a single pane displays — either a focus mode for an atom or a thinkspace canvas
enum PaneContent: Identifiable, Equatable {
    case entity(EntitySelection)
    case thinkspace(thinkspaceId: String)
    case commandCenter
    case swipeGallery
    case webBrowser(instanceId: UUID, url: URL, title: String?)
    case cosmoWindow
    case collaborator(target: CollaborationTarget, presetId: String?)
    case inlineAssistant

    /// Browser panes carry instance identity, not URL identity — two panes on
    /// the same page are legal (the URL is only the launch destination).
    static func webBrowser(url: URL, title: String?) -> PaneContent {
        .webBrowser(instanceId: UUID(), url: url, title: title)
    }

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
        case .webBrowser(let instanceId, _, _):
            return "web_\(instanceId.uuidString)"
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
        guard case .webBrowser(_, let url, _) = self else { return nil }
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

    /// Only the assistant family pays the width ladder. Its transcript is one
    /// deep stack of streamed blocks whose re-layout cost is superlinear in
    /// depth; every other pane kind is a normal focus mode, canvas, or web
    /// view that reflows in a frame and must resize live under the cursor.
    ///
    /// This split coincides with `chromeStyle` today by accident, not by rule
    /// — a pane can be chromeless and cheap, or standard and expensive. Keep
    /// the two switches independent.
    var widthStreamBehavior: PaneWidthStreamBehavior {
        switch self {
        case .cosmoWindow, .collaborator, .inlineAssistant:
            return .tracksSteps
        case .entity, .thinkspace, .commandCenter, .swipeGallery, .webBrowser:
            return .tracksLive
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
    @Published var panes: [PaneContent] = []

    /// The pane expanded to full reading width. Every other pane collapses
    /// into the tab rail.
    @Published var focusedPaneId: String? = nil

    /// Optional second pane kept expanded beside the focused one (60/40 split).
    /// Pinning the focused pane keeps it visible while focus moves elsewhere.
    @Published var pinnedPaneId: String? = nil

    /// Horizontal split ratio between left (main content) and right (pane column).
    /// 1.0 = full width (no panes visible). Animates to 0.5 when first pane opens.
    @Published var mainSplitRatio: CGFloat = 1.0

    /// True while the user is dragging the main split divider — one of the two
    /// continuous width streams.
    @Published private(set) var isDraggingMainSplit = false

    /// True while the hosting window is in a live resize. Window resize is
    /// the same continuous width stream as a divider drag, just delivered by
    /// AppKit instead of a gesture, so it feeds the same flag.
    @Published private(set) var isWidthStreamWindowResize = false

    /// The one flag the deck consults. It does NOT freeze layout: every pane
    /// whose `widthStreamBehavior` is `.tracksLive` reflows under the cursor
    /// as normal. It only tells `.tracksSteps` panes to follow the coarse
    /// width ladder for the duration of the stream.
    var isWidthStreamActive: Bool {
        isDraggingMainSplit || isWidthStreamWindowResize
    }

    /// ID of the pane the user last interacted with (tap/focus).
    /// Used to determine which pane's context the CosmoWindow and voice system see.
    @Published var activePaneId: String? = nil

    /// ID of the pane whose entity currently owns global context while another pane
    /// (such as the collaborator) may be focused.
    @Published var contextOwnerPaneId: String? = nil

    // MARK: - Constants

    /// Maximum number of simultaneous panes in the deck (tabs are cheap)
    let maxPanes: Int = 6

    /// Maximum simultaneous browser panes. Each keeps a live WKWebView, and
    /// the cap is also the anti-sprawl stance: this is a research browser,
    /// not a tab hoard.
    let maxBrowserPanes: Int = 3

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

    /// Browser panes currently in the deck (opening order).
    var browserPanes: [PaneContent] {
        panes.filter { $0.webURL != nil }
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

    /// Check if another browser pane can be opened. URL-level routing (reuse
    /// vs new pane) is BrowserPaneRouter's job — the manager only budgets.
    func canOpenBrowserPane() -> Bool {
        guard browserPanes.count < maxBrowserPanes else { return false }
        guard panes.count < maxPanes else { return false }
        return true
    }

    // MARK: - Pane Lifecycle

    /// Open a new pane. Silently ignores if content is already open or max reached.
    func openPane(_ content: PaneContent) {
        // Check duplicates
        guard !panes.contains(where: { $0.id == content.id }) else { return }
        guard panes.count < maxPanes else { return }
        if content.webURL != nil {
            guard browserPanes.count < maxBrowserPanes else { return }
        }

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

    /// Open a pane focused while keeping the currently focused pane visible
    /// beside it — the "open in split" gesture (new pane 60%, source pinned
    /// at 40%). An existing pin is never stolen.
    func openPaneBeside(_ content: PaneContent) {
        let sourceId = focusedPaneId
        openPane(content)
        guard focusedPaneId == content.id else { return }
        if let sourceId,
           sourceId != content.id,
           pinnedPaneId == nil,
           panes.contains(where: { $0.id == sourceId }) {
            pinnedPaneId = sourceId
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
            // Focus moves to the tab-rail neighbor (the closed tab's slot,
            // clamped) — the Safari close behavior.
            focusedPaneId = panes.isEmpty ? nil : panes[min(index, panes.count - 1)].id
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

    /// Close every pane except the kept one (the tab rail's "Close Other Panes").
    func closeOtherPanes(keeping id: String) {
        guard panes.contains(where: { $0.id == id }) else { return }
        for pane in panes where pane.id != id {
            closePane(pane)
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

    /// Expand a pane to reading width; everything else collapses into the tab rail.
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

    /// Move a pane to a new deck position (tab drag-reorder / context menu).
    /// Focus, pin, and active state ride the pane id, not the position; the
    /// ⌘⌃-digit shortcuts follow deck order, so reordering retargets them —
    /// the Safari contract.
    func movePane(_ id: String, toIndex newIndex: Int) {
        guard let index = panes.firstIndex(where: { $0.id == id }),
              panes.indices.contains(newIndex),
              index != newIndex else { return }
        let pane = panes.remove(at: index)
        panes.insert(pane, at: newIndex)
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

    func beginMainSplitDrag() {
        isDraggingMainSplit = true
    }

    func endMainSplitDrag() {
        isDraggingMainSplit = false
    }

    // MARK: - Window Live Resize

    func beginWindowLiveResize() {
        isWidthStreamWindowResize = true
    }

    func endWindowLiveResize() {
        isWidthStreamWindowResize = false
    }

}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int, default defaultValue: Element) -> Element {
        indices.contains(index) ? self[index] : defaultValue
    }
}
