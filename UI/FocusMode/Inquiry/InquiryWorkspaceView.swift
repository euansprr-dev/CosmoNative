// CosmoOS/UI/FocusMode/Inquiry/InquiryWorkspaceView.swift
// The 3-pane Inquiry Workspace: Notebook + Source + AI Copilot.
// Layout modes Cmd+1..5 (Research / Read / Write / Map / Review).
// All actions auto-attach provenance: Deep Dive · Session · Question · Source · Branch.

import SwiftUI

@MainActor
struct InquiryWorkspaceView: View {
    let sessionAtom: Atom
    let onClose: () -> Void

    @State private var viewModel: InquiryWorkspaceViewModel

    init(sessionAtom: Atom, onClose: @escaping () -> Void) {
        self.sessionAtom = sessionAtom
        self.onClose = onClose
        self._viewModel = State(initialValue: InquiryWorkspaceViewModel(session: sessionAtom))
    }

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Divider().background(DS.borderSubtle)
                paneRow
            }
        }
        .task { await viewModel.loadDeepDiveAndRoot() }
        .onDisappear {
            Task { await viewModel.pauseAndPersist() }
        }
        .background(layoutShortcuts)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: DS.space12) {
            Button(action: closeWorkspace) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Close")
                }
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 6)
                .background(DS.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)

            breadcrumb

            Spacer()

            layoutSelector

            crystallizeButton
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.3x1.fill")
                .font(.system(size: 11))
                .foregroundStyle(DS.accent)
            if let dd = viewModel.deepDive {
                Text(dd.title ?? "Deep Dive")
                    .font(CosmoTypography.label)
                    .foregroundStyle(CosmoColors.textPrimary)
                Text("›")
                    .foregroundStyle(CosmoColors.textTertiary)
            }
            Text(sessionAtom.title ?? "Inquiry")
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textSecondary)
        }
    }

    private var layoutSelector: some View {
        HStack(spacing: 4) {
            ForEach(InquiryLayoutMode.allCases, id: \.self) { mode in
                layoutChip(mode)
            }
        }
    }

    private func layoutChip(_ mode: InquiryLayoutMode) -> some View {
        let isActive = viewModel.metadata.layoutMode == mode
        return Button {
            viewModel.setLayout(mode)
        } label: {
            Text(mode.displayName)
                .font(CosmoTypography.caption)
                .foregroundStyle(isActive ? DS.textOnAccent : CosmoColors.textSecondary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 4)
                .background(isActive ? DS.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(mode.displayName)
    }

    private var crystallizeButton: some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.crystallizeActive,
                object: nil
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("Crystallize")
                    .font(CosmoTypography.label)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(DS.accent.opacity(0.55), lineWidth: 1))
            .foregroundStyle(DS.accent)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [.command])
    }

    // MARK: - Pane row

    private var paneRow: some View {
        Group {
            if viewModel.metadata.layoutMode == .review {
                InquiryReviewView(viewModel: viewModel)
                    .background(DS.bg)
            } else {
                GeometryReader { geo in
                    let widths = paneWidths(total: geo.size.width)
                    HStack(spacing: 0) {
                        if widths.notebook > 0 {
                            InquiryNotebookPane(viewModel: viewModel)
                                .frame(width: widths.notebook)
                                .background(DS.surface)
                            paneDivider
                        }
                        if widths.source > 0 {
                            InquirySourcePane(viewModel: viewModel)
                                .frame(width: widths.source)
                                .background(DS.bg)
                            paneDivider
                        }
                        if widths.copilot > 0 {
                            InquiryCopilotPane(viewModel: viewModel)
                                .frame(width: widths.copilot)
                                .background(DS.surface)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.crystallizeActive)) { _ in
            viewModel.setLayout(.review)
        }
    }

    private var paneDivider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(width: 1)
    }

    private struct PaneWidths { let notebook: CGFloat; let source: CGFloat; let copilot: CGFloat }

    private func paneWidths(total: CGFloat) -> PaneWidths {
        switch viewModel.metadata.layoutMode {
        case .research:
            return PaneWidths(notebook: total * 0.30, source: total * 0.46, copilot: total * 0.24)
        case .read:
            return PaneWidths(notebook: 0, source: total * 0.78, copilot: total * 0.22)
        case .write:
            return PaneWidths(notebook: total * 0.70, source: 0, copilot: total * 0.30)
        case .map:
            return PaneWidths(notebook: total, source: 0, copilot: 0)
        case .review:
            return PaneWidths(notebook: total, source: 0, copilot: 0)
        }
    }

    // MARK: - Shortcuts

    @ViewBuilder
    private var layoutShortcuts: some View {
        // Hidden buttons to attach Cmd+1..5 keyboard shortcuts.
        VStack(spacing: 0) {
            Button("") { viewModel.setLayout(.research) }
                .keyboardShortcut("1", modifiers: [.command])
            Button("") { viewModel.setLayout(.read) }
                .keyboardShortcut("2", modifiers: [.command])
            Button("") { viewModel.setLayout(.write) }
                .keyboardShortcut("3", modifiers: [.command])
            Button("") { viewModel.setLayout(.map) }
                .keyboardShortcut("4", modifiers: [.command])
            Button("") { viewModel.setLayout(.review) }
                .keyboardShortcut("5", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func closeWorkspace() {
        Task {
            await viewModel.pauseAndPersist()
            onClose()
        }
    }
}
