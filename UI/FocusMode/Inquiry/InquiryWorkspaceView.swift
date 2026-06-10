// CosmoOS/UI/FocusMode/Inquiry/InquiryWorkspaceView.swift
// "Stele" redesign — thin shell hosting top bar, 3-pane row (Your Notes · Stele · Sources),
// bottom dock, Crystallize sheet, Map overlay, and toasts.
// Modes collapse to Explore / Crystallize (Cmd+1 / Cmd+2). Cmd+M toggles the Map overlay.

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
            shellStack
            if let toast = viewModel.toast {
                toastOverlay(toast)
            }
            if viewModel.isMapOverlayPresented {
                InquiryMapOverlay(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .filmGrain(opacity: 0.02)
        .animation(ProMotionSprings.gentle, value: viewModel.toast)
        .animation(ProMotionSprings.focusTransition, value: viewModel.isMapOverlayPresented)
        .task { await viewModel.loadDeepDiveAndRoot() }
        .onDisappear { Task { await viewModel.pauseAndPersist() } }
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
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.crystallizeActive)) { _ in
            viewModel.setPhase(.crystallize)
        }
        .sheet(isPresented: crystallizeBinding) {
            InquiryCrystallizeSheet(viewModel: viewModel) {
                viewModel.setPhase(.explore)
            }
        }
        .background(InquiryShortcuts(viewModel: viewModel, onClose: closeWorkspace, focusDock: { dockFocused = true }))
    }

    // MARK: - Shell stack

    private var shellStack: some View {
        VStack(spacing: 0) {
            InquiryTopBar(
                viewModel: viewModel,
                onClose: closeWorkspace,
                onFocusDock: { dockFocused = true }
            )
            Divider().background(DS.borderSubtle)
            paneRow
            Divider().background(DS.borderSubtle)
            dockRegion
        }
    }

    // MARK: - Pane row (Your Notes · Stele · Sources)

    private var paneRow: some View {
        HStack(spacing: 0) {
            InquiryNotesRail(viewModel: viewModel)
                .frame(width: 280)
                .background(DS.surface)
            paneDivider
            centerColumn
                .frame(maxWidth: .infinity)
                .background(DS.bg)
            paneDivider
            InquirySourcesRail(viewModel: viewModel)
                .frame(width: 280)
                .background(DS.surface)
        }
    }

    private var paneDivider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(width: 1)
    }

    private var centerColumn: some View {
        Group {
            if let tabId = viewModel.activeReaderSourceId,
               let tab = viewModel.structured.sourceTabs.first(where: { $0.id == tabId }) {
                InquiryReaderView(viewModel: viewModel, tab: tab)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                InquirySteleView(viewModel: viewModel) { dockFocused = true }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(ProMotionSprings.focusTransition, value: viewModel.activeReaderSourceId)
    }

    // MARK: - Dock region

    private var dockRegion: some View {
        VStack(spacing: DS.space6) {
            if !viewModel.ephemeralAIReplies.isEmpty {
                InquiryEphemeralAICardsStack(viewModel: viewModel)
                    .padding(.horizontal, DS.space20)
                    .padding(.top, DS.space8)
                    .transition(.opacity)
            }
            if !viewModel.routingReceipts.isEmpty {
                InquiryRoutingReceiptStack(viewModel: viewModel)
                    .padding(.horizontal, DS.space20)
                    .transition(.opacity)
            }
            InquiryAssistantDock(viewModel: viewModel, dockDraft: $dockDraft, dockFocused: $dockFocused)
        }
        .animation(ProMotionSprings.gentle, value: viewModel.ephemeralAIReplies.count)
        .animation(ProMotionSprings.gentle, value: viewModel.routingReceipts.count)
    }

    // MARK: - Toast overlay

    private func toastOverlay(_ toast: InquiryToast) -> some View {
        toastView(toast)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 54)
            .padding(.trailing, DS.space20)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func toastView(_ toast: InquiryToast) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.accent)
                .padding(.top, 2)
                .accessibilityHidden(true)
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
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    // MARK: - Bindings

    private var crystallizeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .crystallize },
            set: { isPresented in
                if !isPresented { viewModel.setPhase(.explore) }
            }
        )
    }

    private func closeWorkspace() {
        Task {
            await viewModel.pauseAndPersist()
            onClose()
        }
    }
}

// MARK: - Top Bar

@MainActor
private struct InquiryTopBar: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let onClose: () -> Void
    let onFocusDock: () -> Void

    var body: some View {
        HStack(spacing: DS.space12) {
            closeButton
            activeQuestionHeader
            Spacer(minLength: DS.space12)
            InquiryPhaseToggle(viewModel: viewModel)
            crystallizeButton
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Close")
            }
            .font(CosmoTypography.label)
            .foregroundStyle(CosmoColors.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 6)
            .background(DS.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Close inquiry workspace")
    }

    private var activeQuestionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
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
                .accessibilityLabel("Switch active question")

                Button {
                    onFocusDock()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CosmoColors.textSecondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add a branch question")
                .accessibilityLabel("Add a branch question")
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

    private var crystallizeButton: some View {
        Button {
            viewModel.setPhase(.crystallize)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Crystallize")
                    .font(CosmoTypography.label)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(DS.accent.opacity(0.55), lineWidth: 1))
            .foregroundStyle(DS.accent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [.command])
        .accessibilityLabel("Crystallize inquiry session")
    }
}

// MARK: - Phase Toggle (Explore | Crystallize)

@MainActor
private struct InquiryPhaseToggle: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        HStack(spacing: 0) {
            chip(.explore)
            chip(.crystallize)
        }
        .padding(2)
        .background(DS.surface, in: Capsule())
        .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
    }

    private func chip(_ phase: InquiryPhase) -> some View {
        let isActive = viewModel.phase == phase
        return Button {
            viewModel.setPhase(phase)
        } label: {
            Text(phase.displayName)
                .font(CosmoTypography.label)
                .foregroundStyle(isActive ? DS.textOnAccent : CosmoColors.textSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 5)
                .background(isActive ? DS.accent : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(phase.displayName) phase")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Shortcuts

@MainActor
private struct InquiryShortcuts: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let onClose: () -> Void
    let focusDock: () -> Void

    var body: some View {
        // Hidden zero-size buttons hosting keyboard shortcuts.
        VStack(spacing: 0) {
            Button("") { viewModel.setPhase(.explore) }
                .keyboardShortcut("1", modifiers: [.command])
            Button("") { viewModel.setPhase(.crystallize) }
                .keyboardShortcut("2", modifiers: [.command])
            Button("") { viewModel.toggleMap() }
                .keyboardShortcut("m", modifiers: [.command])
            Button("") { viewModel.goToParentQuestion() }
                .keyboardShortcut("[", modifiers: [.command])
            Button("") { viewModel.cycleQuestion(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command])
            Button("") { focusDock() }
                .keyboardShortcut("k", modifiers: [.command])
            Button("") {
                if viewModel.activeReaderSourceId != nil {
                    viewModel.dismissReader()
                } else if viewModel.isMapOverlayPresented {
                    viewModel.dismissMap()
                }
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
