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
    @State private var dockDraft: String = ""
    @FocusState private var dockFocused: Bool

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
                if viewModel.metadata.layoutMode != .review {
                    Divider().background(DS.borderSubtle)
                    thinkingDock
                }
            }
            if let toast = viewModel.toast {
                toastView(toast)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 54)
                    .padding(.trailing, DS.space20)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.toast)
        .task { await viewModel.loadDeepDiveAndRoot() }
        .onDisappear {
            Task { await viewModel.pauseAndPersist() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.layoutRequested)) { notification in
            guard let payload = CosmoNotification.Inquiry.LayoutPayload(from: notification) else { return }
            viewModel.setLayout(payload.mode)
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.focusThinkingDock)) { _ in
            dockFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.refreshSources)) { _ in
            Task { await viewModel.refreshSourceRecommendations() }
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

            activeQuestionHeader

            Spacer()

            layoutSelector

            crystallizeButton
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    private var activeQuestionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.accent)
                Menu {
                    questionMenuContent
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.activeQuestionTitle)
                            .font(CosmoTypography.label)
                            .foregroundStyle(CosmoColors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(CosmoColors.textTertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)

                Button {
                    dockDraft = "branch: "
                    dockFocused = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CosmoColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Create child question")
            }
            Text(viewModel.activeQuestionBreadcrumb)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    @ViewBuilder
    private var questionMenuContent: some View {
        ForEach(viewModel.orderedQuestionNodes(), id: \.id) { node in
            Button {
                viewModel.setActiveQuestion(node.atomUUID, branchNodeId: node.id)
            } label: {
                let counts = viewModel.counts(for: node.atomUUID)
                Text("\(viewModel.questionTitle(for: node.atomUUID))  \(counts.compactLabel)")
            }
        }
        Divider()
        Button("Pin active question") {
            viewModel.togglePinActiveQuestion()
        }
        Button("Mark researching") {
            Task { await viewModel.updateQuestionStatus(viewModel.activeQuestionUUID, status: .researching) }
        }
        Button("Mark answered") {
            Task { await viewModel.updateQuestionStatus(viewModel.activeQuestionUUID, status: .answered) }
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

    private func toastView(_ toast: InquiryToast) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message)
                    .font(CosmoTypography.label)
                    .foregroundStyle(CosmoColors.textPrimary)
                if let detail = toast.detail {
                    Text(detail)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
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

    // MARK: - Thinking Dock

    private var thinkingDock: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 30, height: 30)
                .background(DS.accentSoft, in: Circle())

            if let activity = viewModel.sourceActivityLine {
                dockActivityLine(activity)
            } else {
                TextField("Think out loud, paste a URL, or route with claim: source: scout: branch:", text: $dockDraft)
                    .textFieldStyle(.plain)
                    .font(CosmoTypography.body)
                    .focused($dockFocused)
                    .onSubmit { submitDockDraft() }
            }

            HStack(spacing: 5) {
                dockPrefixButton("claim:")
                dockPrefixButton("source:")
                dockPrefixButton("scout:")
                dockPrefixButton("branch:")
                dockCommandButton("/sources")
            }

            Button {
                submitDockDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(dockDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DS.surfaceHover : DS.accent, in: Circle())
                    .foregroundStyle(dockDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CosmoColors.textTertiary : DS.textOnAccent)
            }
            .buttonStyle(.plain)
            .disabled(dockDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Route thought")
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space10)
        .background(DS.surface)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.sourceActivityLine)
    }

    private func dockActivityLine(_ activity: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.58)
            Text(activity)
                .font(CosmoTypography.bodySmall)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, 6)
        .background(DS.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.accent.opacity(0.14), lineWidth: 1))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func dockPrefixButton(_ prefix: String) -> some View {
        Button {
            if dockDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dockDraft = "\(prefix) "
            } else {
                dockDraft = "\(prefix) \(dockDraft)"
            }
            dockFocused = true
        } label: {
            Text(prefix)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 5)
                .background(DS.surfaceElevated, in: Capsule())
                .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Route as \(prefix)")
    }

    private func dockCommandButton(_ command: String) -> some View {
        Button {
            dockDraft = command
            submitDockDraft()
        } label: {
            Text(command)
                .font(CosmoTypography.caption)
                .foregroundStyle(DS.accent)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 5)
                .background(DS.accent.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(DS.accent.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Refresh source recommendations")
    }

    private func submitDockDraft() {
        let text = dockDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dockDraft = ""
        Task { await viewModel.submitDockText(text) }
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
            Button("") { viewModel.goToParentQuestion() }
                .keyboardShortcut("[", modifiers: [.command])
            Button("") { viewModel.cycleQuestion(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command])
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
