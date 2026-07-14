// CosmoOS/UI/FocusMode/Ideas/IdeaWorkspaceToolbar.swift
// June 2026 — Idea Focus Mode v2 (Greenhouse clean).
// Floating chrome islands: back, idea status, client picker, the Begin Writing
// hero action, and the inspector toggle. Same island grammar as the Content &
// Connection workspace toolbars (CosmoChromeRow / CosmoChromeIsland) — glass
// hugs each control group, never a full-width bar.

import SwiftUI

struct IdeaWorkspaceToolbar: View {
    var viewModel: IdeaFocusModeViewModel
    var workspace: IdeaWorkspaceModel
    let isPaneContext: Bool
    let isPromoting: Bool
    let actions: IdeaWorkspaceActions

    @Environment(\.atomWindowChromeContext) private var atomChrome

    private var isBodyEmpty: Bool {
        viewModel.editableBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        // Chrome islands, not a full-width bar: nav | primary action | tools,
        // grouped by function on the shared chrome baseline. Same grammar as the
        // Content & Connection workspace toolbars (CosmoChromeIsland). The parent
        // safeAreaInset already provides the row insets.
        CosmoChromeRow(insetsEnabled: false) {
            if atomChrome == nil, !isPaneContext {
                NavigationTrailIsland()
            }
            CosmoChromeIsland { leadingControls }
        } center: {
            EmptyView()
        } trailing: {
            beginWritingButton
            CosmoChromeIsland { trailingControls }
        }
    }

    // MARK: - Leading

    @ViewBuilder
    private var leadingControls: some View {
        if let atomChrome {
            AtomWindowChromeLeadingControls(context: atomChrome)
            AtomWindowChromeDivider()
        }
        statusMenu
        clientMenu
    }

    private var statusMenu: some View {
        Menu {
            ForEach(IdeaStatus.allCases, id: \.self) { status in
                Button {
                    Task { await viewModel.updateStatus(status) }
                } label: {
                    Label(status.displayName, systemImage: status.iconName)
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: viewModel.selectedStatus.iconName)
                    .font(DS.caption2.weight(.medium))
                    .accessibilityHidden(true)
                Text(viewModel.selectedStatus.displayName)
                    .font(DS.buttonText)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Idea status")
        .accessibilityLabel("Idea status: \(viewModel.selectedStatus.displayName)")
    }

    private var clientMenu: some View {
        Menu {
            ForEach(viewModel.clientProfiles, id: \.uuid) { client in
                Button(client.title ?? "Client") {
                    Task { await viewModel.assignClient(client) }
                }
            }
            if viewModel.clientProfiles.isEmpty {
                Text("No client profiles")
            }
            Divider()
            Button {
                actions.onShowProfileEditor()
            } label: {
                Label("Create New Profile", systemImage: "plus.circle")
            }
            if viewModel.linkedClient != nil {
                Divider()
                Button(role: .destructive) {
                    Task { await viewModel.assignClient(nil) }
                } label: {
                    Label("Remove Client", systemImage: "xmark.circle")
                }
            }
        } label: {
            clientMenuLabel
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Client profile")
        .accessibilityLabel("Client profile")
    }

    private var clientMenuLabel: some View {
        HStack(spacing: DS.space6) {
            if let client = viewModel.linkedClient {
                Circle()
                    .fill(DS.clientColor(for: client.uuid))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(client.title ?? "Client")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.textSecondary)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text("No client")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .contentShape(Capsule())
    }

    // MARK: - Trailing

    /// The tools island: inspector toggle plus the window/pane close affordance.
    @ViewBuilder
    private var trailingControls: some View {
        inspectorToggle
        if let atomChrome {
            AtomWindowChromeDivider()
            AtomWindowChromeTrailingControls(context: atomChrome)
        } else if isPaneContext {
            closeButton
        }
    }

    /// The single accent affordance on this screen.
    private var beginWritingButton: some View {
        Button(action: actions.onBeginWriting) {
            HStack(spacing: DS.space6) {
                if isPromoting {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "square.and.pencil")
                        .font(DS.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(isPromoting ? "Writing…" : "Begin Writing")
                    .font(DS.buttonText.weight(.semibold))
            }
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space6)
            .background(DS.accent.opacity(isBodyEmpty || isPromoting ? 0.45 : 1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPromoting || isBodyEmpty)
        .keyboardShortcut(.return, modifiers: [.command])
        .help("Begin writing — promotes this idea to content (⌘↩)")
        .accessibilityLabel("Begin writing")
    }

    private var inspectorToggle: some View {
        toolbarButton(
            icon: "sidebar.right",
            help: workspace.isInspectorShowing ? "Hide inspector (⌘⌥I)" : "Show inspector (⌘⌥I)",
            isActive: workspace.isInspectorShowing
        ) {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleInspector()
            }
        }
    }

    private var closeButton: some View {
        toolbarButton(icon: "xmark", help: "Close (Esc)", action: actions.onClose)
    }

    // MARK: - Button factory

    private func toolbarButton(
        icon: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.buttonText)
                .foregroundStyle(isActive ? DS.text : DS.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
