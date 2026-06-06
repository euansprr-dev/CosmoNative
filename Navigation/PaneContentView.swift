// CosmoOS/Navigation/PaneContentView.swift
// Renders the content of a single pane — routes to the correct focus mode or thinkspace canvas

import SwiftUI

struct PaneContentView: View {
    let content: PaneContent
    let isActive: Bool
    let isContextOwner: Bool
    let onClose: () -> Void

    @State private var loadedAtom: Atom?
    @StateObject private var swipeLibraryViewModel = SwipeLibraryViewModel()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Content
            contentBody

            // Close button (for generic panes — entity focus modes and browser panes handle their own)
            if content.thinkspaceId != nil || content.id == "commandCenter" || content.id == "swipeGallery" {
                paneCloseButton
            }
        }
        .background(backgroundFill)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(borderOverlay)
        .task {
            guard case .entity(let entity) = content else { return }
            if let atom = try? await AtomRepository.shared.fetch(id: entity.id) {
                loadedAtom = atom
            }
        }
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
            PaneCanvasView(thinkspaceId: thinkspaceId)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .commandCenter:
            CommandCenterDashboard()
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .swipeGallery:
            SwipeFileHomeView(viewModel: swipeLibraryViewModel, section: .all)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .webBrowser(let url, let title):
            CosmoWebBrowserPane(url: url, title: title, onClose: onClose)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)
                .environment(\.isPaneContextOwner, isContextOwner)

        case .cosmoWindow:
            CosmoWindowView(
                isVisible: .constant(true),
                isPaneMode: true,
                onClose: onClose,
                showsPlaceAsPaneButton: false
            )
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

        default:
            ZStack {
                CosmoColors.thinkspaceVoid
                Text("Unsupported type")
                    .foregroundStyle(.white.opacity(0.4))
                    .font(.system(size: 13))
            }
        }
    }

    // MARK: - Close Button

    private var paneCloseButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, height: 28)
                .background(DS.border, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
    }

    private var backgroundFill: some View {
        Group {
            switch content.chromeStyle {
            case .standard:
                DS.bg
            case .minimal:
                DS.bg
            }
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch content.chromeStyle {
        case .standard:
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(DS.border, lineWidth: 1)
        case .minimal:
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isActive ? DS.borderSubtle : DS.borderSubtle.opacity(0.7), lineWidth: 1)
        }
    }

    private var cornerRadius: CGFloat {
        switch content.chromeStyle {
        case .standard:
            return 8
        case .minimal:
            return 14
        }
    }
}
