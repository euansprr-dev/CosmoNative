// CosmoOS/Navigation/PaneContentView.swift
// Renders the content of a single pane — routes to the correct focus mode or thinkspace canvas

import SwiftUI

struct PaneContentView: View {
    let content: PaneContent
    let isActive: Bool
    let isContextOwner: Bool
    let onClose: () -> Void

    @Environment(\.paneDeckChrome) private var paneDeckChrome

    @State private var loadedAtom: Atom?
    @State private var swipeLibraryViewModel = SwipeLibraryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Shell-owned tab row, STACKED above content (never overlaid), for
            // pane kinds whose surface has no chrome row of its own — and for
            // entity panes while the atom loads, so no pane is ever tab-less.
            if let paneDeckChrome, showsStandaloneDeckChrome {
                PaneDeckStandaloneChrome(context: paneDeckChrome)
            }
            contentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundFill)
        .clipShape(CosmoSurfaceMetrics.containerShape)
        .overlay(borderOverlay)
        // Declares the pane as the concentric container: every
        // `cosmoInnerWindow()` inside resolves its corner against this shape.
        .cosmoSurfaceContainer()
        .task(id: content.entitySelection) {
            guard case .entity(let entity) = content else {
                loadedAtom = nil
                return
            }
            loadedAtom = nil
            if let atom = try? await AtomRepository.shared.fetch(id: entity.id) {
                guard !Task.isCancelled else { return }
                loadedAtom = atom
            }
        }
    }

    /// The mode-hosted strip takes over only once the routed mode is actually
    /// on screen — an entity pane shows the shell row while its atom loads.
    private var showsStandaloneDeckChrome: Bool {
        guard PaneDeckChromeAdoption.modeHostsDeckChrome(content) else { return true }
        if case .entity = content { return loadedAtom == nil }
        return false
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        switch content {
        case .entity(let entity):
            entityView(for: entity)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .thinkspace(let thinkspaceId):
            // Study-shell anatomy (same as Connection/Swipe focus modes): the
            // tab row lives in its own band above, and the canvas is ONE
            // rounded sheet inset on DS.bg — not an edge-to-edge void the
            // chrome floats over.
            PaneCanvasView(thinkspaceId: thinkspaceId)
                .cosmoInnerWindow(insetTop: true)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .commandCenter:
            CommandCenterDashboard()
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .swipeGallery:
            SwipeLibraryPage(viewModel: swipeLibraryViewModel, section: .all)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .webBrowser(_, let url, let title):
            CosmoWebBrowserPane(paneId: content.id, url: url, title: title, onClose: onClose)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .cosmoWindow:
            // One Cosmo: the legacy chat-window pane kind now renders the same
            // inline assistant pane (persisted pane layouts keep working).
            CosmoInlineAssistantPaneView(store: CosmoInlineAssistantStore.shared, onClose: onClose)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .collaborator(let target, let presetId):
            CosmoCollaboratorPaneView(target: target, presetId: presetId, onClose: onClose)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .inlineAssistant:
            CosmoInlineAssistantPaneView(store: CosmoInlineAssistantStore.shared, onClose: onClose)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)
        }
    }

    // MARK: - Entity Routing

    @ViewBuilder
    private func entityView(for entity: EntitySelection) -> some View {
        if let atom = loadedAtom {
            routedFocusMode(for: entity.type, atom: atom)
        } else {
            ZStack {
                CosmoColors.thinkspaceVoid
                ProgressView("Loading...")
                    .tint(.white)
            }
        }
    }

    @ViewBuilder
    private func routedFocusMode(for type: EntityType, atom: Atom) -> some View {
        switch type {
        case .research:
            if atom.isSwipeFileAtom {
                SwipeStudyFocusModeView(atom: atom, onClose: onClose)
            } else {
                ResearchFocusModeView(atom: atom, onClose: onClose)
            }

        case .connection:
            ConnectionFocusModeView(atom: atom, onClose: onClose)

        case .idea:
            IdeaFocusModeView(atom: atom, onClose: onClose)

        case .content:
            ContentFocusModeView(atom: atom, onClose: onClose)

        case .note:
            NoteFocusModeView(atom: atom, onClose: onClose)

        case .cosmoAI:
            CosmoAIFocusModeView(atom: atom, onClose: onClose)

        case .file:
            FilePortalPreviewSurface(atom: atom, onClose: onClose)

        case .extract:
            ExtractPeekView(atom: atom, onClose: onClose)

        default:
            ZStack {
                CosmoColors.thinkspaceVoid
                Text("Unsupported type")
                    .foregroundStyle(.white.opacity(0.4))
                    .font(.system(size: 13))
            }
        }
    }

    private var backgroundFill: some View {
        DS.bg
    }

    /// Pane kind decides border WEIGHT (an inactive minimal pane recedes),
    /// never geometry. Letting `chromeStyle` fork the corner radius is what
    /// gave the assistant pane 14 and the idea pane 8 — the same rung of the
    /// ladder rendering two different shapes side by side.
    private var borderOverlay: some View {
        CosmoSurfaceMetrics.containerShape
            .stroke(borderTint, lineWidth: 1)
    }

    private var borderTint: Color {
        switch content.chromeStyle {
        case .standard:
            return DS.borderSubtle
        case .minimal:
            return isActive ? DS.borderSubtle : DS.borderSubtle.opacity(0.7)
        }
    }
}
