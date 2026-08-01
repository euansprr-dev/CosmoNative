// CosmoOS/UI/FocusMode/Connection/ConnectionWorkspaceView.swift
// June 2026 — Connection workspace revamp.
// Root adaptive container for the structured 3-pane layout:
// navigator | center (board / outline / manuscript / section detail) | inspector.
// Collapses by width: regular (≥1100) shows all three columns, compact
// (700–1100) collapses the navigator to a rail and overlays the inspector,
// narrow (<700) is a single column with both sides as overlays.

import SwiftUI

struct ConnectionWorkspaceView: View {
    let atom: Atom
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel
    @Binding var title: String
    let sources: ConnectionWorkspaceSources
    var recommendations: ConceptRecommendationModel
    let reviewProposal: CosmoAssistantProposal?
    let reviewSourceText: String
    /// Staged inserts grouped by the section they target — rendered as in-place
    /// ghost rows on the Board and in the Outline (Manuscript still uses the
    /// full-screen `reviewProposal` diff).
    var pendingInsertsBySection: [ConnectionSectionType: [ConnectionPendingInsert]] = [:]
    let isPaneContext: Bool
    let actions: ConnectionWorkspaceActions

    var body: some View {
        GeometryReader { geometry in
            let breakpoint = ConnectionWorkspaceBreakpoint(width: geometry.size.width)
            VStack(spacing: CosmoSurfaceMetrics.chromeGap) {
                ConnectionWorkspaceToolbar(
                    workspace: workspace,
                    breakpoint: breakpoint,
                    isPaneContext: isPaneContext,
                    actions: actions
                )
                workspaceSheet(breakpoint: breakpoint)
            }
            .onChange(of: geometry.size.width, initial: true) { _, width in
                let resolved = ConnectionWorkspaceBreakpoint(width: width)
                if workspace.breakpoint != resolved {
                    workspace.breakpoint = resolved
                }
            }
        }
        .background(DS.bg)
    }

    // MARK: - The workspace sheet (one rounded surface, three columns)

    /// Study-shell anatomy: the chrome islands live in their own band above,
    /// and navigator | center | inspector are welded by hairlines inside ONE
    /// rounded sheet — the sheet is the only rectangle on the screen.
    private func workspaceSheet(breakpoint: ConnectionWorkspaceBreakpoint) -> some View {
        columns(breakpoint: breakpoint)
            .overlay(alignment: .leading) { navigatorOverlay(breakpoint: breakpoint) }
            .overlay(alignment: .trailing) { inspectorOverlay(breakpoint: breakpoint) }
            .background(DS.bg)
            .cosmoInnerWindow()
    }

    // MARK: - Columns

    /// LAW (shared with WorkbenchShell): the shell never animates panel
    /// insertion itself — an implicit `.animation(value:)` here also animated
    /// breakpoint- and mount-driven seats, and on macOS 26 a seat riding a
    /// transaction it doesn't own gets its slide orphaned: the panel commits
    /// layout but never composites (invisible-but-hit-testable inspector,
    /// stale board raster clipped at the new width — July 2026). Toggle sites
    /// supply the transaction via `withAnimation`; breakpoint seats are
    /// instant by design.
    private func columns(breakpoint: ConnectionWorkspaceBreakpoint) -> some View {
        HStack(spacing: 0) {
            if breakpoint == .regular {
                regularNavigator
                Divider().overlay(DS.borderSubtle)
            } else if breakpoint == .compact {
                ConnectionNavigatorRail(viewModel: viewModel, workspace: workspace) {
                    withAnimation(ProMotionSprings.focusTransition) {
                        workspace.isNavigatorOverlayPresented = true
                    }
                }
                Divider().overlay(DS.borderSubtle)
            }

            centerColumn(breakpoint: breakpoint)

            if breakpoint == .regular, workspace.isInspectorVisible {
                Divider().overlay(DS.borderSubtle)
                inspector
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var regularNavigator: some View {
        if workspace.isNavigatorCollapsed {
            ConnectionNavigatorRail(viewModel: viewModel, workspace: workspace) {
                withAnimation(ProMotionSprings.focusTransition) {
                    workspace.isNavigatorCollapsed = false
                }
            }
        } else {
            navigator
        }
    }

    private var navigator: some View {
        ConnectionNavigatorView(
            viewModel: viewModel,
            workspace: workspace,
            title: $title,
            sources: sources,
            actions: actions
        )
    }

    private var inspector: some View {
        ConnectionInspectorView(
            viewModel: viewModel,
            workspace: workspace,
            sources: sources,
            attachmentUUIDs: atom.attachmentUUIDs,
            recommendations: recommendations,
            actions: actions
        )
    }

    // MARK: - Center

    private func centerColumn(breakpoint: ConnectionWorkspaceBreakpoint) -> some View {
        centerContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Select→mint on the user's own bullets, in EVERY center mode:
            // Outline rows and the pushed section detail both report
            // selections via ConnectionLinkedProseView — one host serves all.
            .conceptMintPillHost()
    }

    @ViewBuilder
    private var centerContent: some View {
        if let pushed = workspace.pushedSection {
            ConnectionSectionDetailView(
                sectionType: pushed,
                viewModel: viewModel,
                workspace: workspace,
                actions: actions
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            switch workspace.viewMode {
            case .board:
                ConnectionBoardView(
                    viewModel: viewModel,
                    workspace: workspace,
                    actions: actions,
                    pendingInsertsBySection: pendingInsertsBySection
                )
            case .outline:
                ConnectionOutlineView(
                    viewModel: viewModel,
                    workspace: workspace,
                    actions: actions,
                    pendingInsertsBySection: pendingInsertsBySection
                )
            case .manuscript:
                // Manuscript keeps the full-screen woven diff while a proposal
                // is pending; Board/Outline stage in place instead.
                if let reviewProposal {
                    ConnectionWorkspaceReviewView(
                        proposal: reviewProposal,
                        sourceText: reviewSourceText
                    )
                } else {
                    ManuscriptModeView(
                        title: title,
                        conceptType: viewModel.state.conceptType,
                        sections: viewModel.state.sections,
                        media: viewModel.state.orderedMedia,
                        mediaAtoms: viewModel.mediaAtoms,
                        onOpenMedia: actions.onOpenMedia,
                        onDismiss: {
                            withAnimation(ProMotionSprings.focusTransition) {
                                workspace.viewMode = .board
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Overlays (compact / narrow)

    @ViewBuilder
    private func navigatorOverlay(breakpoint: ConnectionWorkspaceBreakpoint) -> some View {
        if breakpoint != .regular, workspace.isNavigatorOverlayPresented {
            navigator
                .overlay(alignment: .trailing) {
                    Divider().overlay(DS.borderSubtle)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, x: 6)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(2)
                .onTapGesture {} // swallow taps inside the panel
                .background(dismissScrim {
                    workspace.isNavigatorOverlayPresented = false
                })
        }
    }

    @ViewBuilder
    private func inspectorOverlay(breakpoint: ConnectionWorkspaceBreakpoint) -> some View {
        // At pane widths the inspector covers board content, so it is opt-in
        // (toolbar toggle / ⌘⌥I) rather than on by default like the regular
        // side column.
        if breakpoint != .regular, workspace.isInspectorOverlayPresented {
            inspector
                .overlay(alignment: .leading) {
                    Divider().overlay(DS.borderSubtle)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, x: -6)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
        }
    }

    private func dismissScrim(_ dismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.001)
            .frame(width: 4000)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
    }
}

// MARK: - Staged-edit review

/// Shown in the center column while the inline assistant (the Concept skill)
/// has a reviewed diff pending against this connection. Renders the serialized
/// section text with changes woven inline; accept/reject route through the
/// assistant store to the connection's editable surface.
struct ConnectionWorkspaceReviewView: View {
    let proposal: CosmoAssistantProposal
    let sourceText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                banner
                CosmoInlineDiffReviewView(
                    store: CosmoInlineAssistantStore.shared,
                    proposal: proposal,
                    sourceText: sourceText,
                    bodyFont: DS.body,
                    textColor: DS.text
                )
            }
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var banner: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(proposal.title.isEmpty ? "Staged changes" : proposal.title)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                Text("Review each change below — accepted items land in their sections.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
        .padding(DS.space12)
        .background(DS.accentSoft.opacity(0.6), in: .rect(cornerRadius: 10))
    }
}
