// CosmoOS/Navigation/PaneContentView.swift
// Renders the content of a single pane — routes to the correct focus mode or thinkspace canvas

import SwiftUI

struct PaneContentView: View {
    let content: PaneContent
    let isActive: Bool
    let onClose: () -> Void

    @State private var loadedAtom: Atom?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Content
            contentBody

            // Close button (for thinkspace and command center panes — entity focus modes handle their own)
            if content.thinkspaceId != nil || content.id == "commandCenter" || content.dimension != nil {
                paneCloseButton
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.border, lineWidth: 1)
        )
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

        case .thinkspace(let thinkspaceId):
            PaneCanvasView(thinkspaceId: thinkspaceId)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)

        case .commandCenter:
            CommandCenterDashboard()
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, isActive)

        case .dimension(let dimension):
            DimensionWorkspaceView(
                dimension: dimension,
                preferredPresentation: .pane
            )
            .environment(\.isPaneContext, true)
            .environment(\.isPaneActive, isActive)
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
                .foregroundColor(DS.textMuted)
                .frame(width: 28, height: 28)
                .background(DS.border, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}
