// CosmoOS/UI/FocusMode/Inquiry/Study/StudyShellView.swift
// The Study, Slack-anatomy edition: a dedicated navigation band up top (the
// chrome islands in their own space), and beneath it the whole working area —
// trail | manuscript | reading — clipped together into ONE rounded sheet.
// The columns are welded inside the sheet by hairlines; the sheet itself is
// the only rectangle, so everything reads as one window-within-the-window.

import SwiftUI

@MainActor
struct StudyShellView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let onClose: () -> Void

    @State private var dockDraft: String = ""
    @FocusState private var dockFocused: Bool
    @State private var hasArrived = false
    @State private var scanController = InquiryScanController()
    @State private var showScanImporter = false

    private static let sheetCorner: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let breakpoint = StudyBreakpoint(width: proxy.size.width)
            ZStack {
                DS.bg.ignoresSafeArea()
                VStack(spacing: DS.space8) {
                    StudyChromeRow(
                        viewModel: viewModel,
                        breakpoint: breakpoint,
                        isReceded: dockFocused
                    )
                    workspaceSheet(breakpoint)
                        .padding(.horizontal, DS.space10)
                        .padding(.bottom, DS.space10)
                }
                bottomInstruments
                if let toast = viewModel.toast {
                    toastOverlay(toast)
                }
                if viewModel.isMapOverlayPresented {
                    mapOverlay
                }
            }
            .animation(ProMotionSprings.focusTransition, value: viewModel.isMapOverlayPresented)
            .animation(ProMotionSprings.gentle, value: viewModel.toast)
            .animation(ProMotionSprings.focusTransition, value: viewModel.activeReaderSourceId)
        }
        .background(StudyShortcuts(viewModel: viewModel, onEscape: handleEscape))
        .fileImporter(
            isPresented: $showScanImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            scanController.ingestImageFiles(scoped)
            scoped.forEach { $0.stopAccessingSecurityScopedResource() }
        }
        .task { await arrive() }
        .onDisappear {
            scanController.teardown()
            Task { await viewModel.pauseAndPersist() }
        }
        .sheet(isPresented: crystallizeBinding) {
            InquiryCrystallizeSheet(viewModel: viewModel) {
                viewModel.setPhase(.explore)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.focusThinkingDock)) { _ in
            viewModel.focusDock()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.refreshSources)) { _ in
            Task { await viewModel.refreshSourceRecommendations() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.crystallizeActive)) { _ in
            viewModel.setPhase(.crystallize)
        }
    }

    private func arrive() async {
        scanController.configure(viewModel: viewModel)
        // One-frame rule, with a cap: the cascade flips when the hydrate
        // lands OR after 400ms — a slow (or hung) load must never hold the
        // manuscript at opacity 0. The question title is already known, so
        // arriving before the full hydrate still paints an honest hero
        // (this was the session's pure-white-void bug).
        let cap = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, !hasArrived else { return }
            hasArrived = true
        }
        await viewModel.loadDeepDiveAndRoot()
        cap.cancel()
        try? await Task.sleep(for: .milliseconds(16))
        if !hasArrived { hasArrived = true }
    }

    // MARK: - The workspace sheet (one rounded surface, three columns)

    private func workspaceSheet(_ breakpoint: StudyBreakpoint) -> some View {
        ZStack {
            columns(breakpoint)
            if breakpoint == .narrow, viewModel.isTrailShowing || viewModel.isReadingShowing {
                panelScrim
            }
            if !breakpoint.panelsDisplace {
                overlayPanels(breakpoint)
            }
        }
        .background(DS.bg)
        .clipShape(RoundedRectangle(cornerRadius: Self.sheetCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.sheetCorner, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    /// At regular width the panels are true columns of the sheet — welded by
    /// their hairlines, clipped by the sheet's one rounded edge.
    private func columns(_ breakpoint: StudyBreakpoint) -> some View {
        HStack(spacing: 0) {
            if breakpoint.panelsDisplace, viewModel.isTrailShowing {
                StudyTrailPanel(viewModel: viewModel)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            centerColumn
                .frame(maxWidth: .infinity)
            if breakpoint.panelsDisplace, viewModel.isReadingShowing {
                StudyReadingPanel(viewModel: viewModel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.focusTransition, value: viewModel.isTrailShowing)
        .animation(ProMotionSprings.focusTransition, value: viewModel.isReadingShowing)
    }

    /// Below regular width the panels slide OVER the center inside the sheet.
    private func overlayPanels(_ breakpoint: StudyBreakpoint) -> some View {
        HStack(spacing: 0) {
            if viewModel.isTrailShowing {
                StudyTrailPanel(viewModel: viewModel, isOverlay: true)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if viewModel.isReadingShowing {
                StudyReadingPanel(viewModel: viewModel, isOverlay: true)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.focusTransition, value: viewModel.isTrailShowing)
        .animation(ProMotionSprings.focusTransition, value: viewModel.isReadingShowing)
    }

    @ViewBuilder
    private var centerColumn: some View {
        if let tabId = viewModel.activeReaderSourceId,
           let tab = viewModel.structured.sourceTabs.first(where: { $0.id == tabId }) {
            // Flush inside the sheet — the panels' hairlines are the only
            // separation; the sheet's corners do the framing.
            InquiryReaderView(viewModel: viewModel, tab: tab)
                .transition(.opacity)
        } else {
            StudyPageView(viewModel: viewModel, hasArrived: hasArrived)
                .filmGrain(opacity: 0.02)
                .transition(.opacity)
        }
    }

    /// Narrow overlays get a whisper of scrim; tap dismisses.
    private var panelScrim: some View {
        Color.black.opacity(0.10)
            .transition(.opacity)
            .onTapGesture {
                withAnimation(ProMotionSprings.focusTransition) {
                    viewModel.isTrailShowing = false
                    viewModel.isReadingShowing = false
                }
            }
            .accessibilityLabel("Dismiss panels")
    }

    private var bottomInstruments: some View {
        VStack(spacing: DS.space8) {
            Spacer()
            if scanController.isPanelVisible {
                InquiryScanPanel(controller: scanController)
                    .padding(.horizontal, DS.space24)
            }
            StudyReceiptStack(viewModel: viewModel)
                .padding(.horizontal, DS.space24)
            StudyThinkingBar(
                viewModel: viewModel,
                draft: $dockDraft,
                isFocused: $dockFocused,
                onScanUpload: { showScanImporter = true },
                onScanPhone: { Task { await scanController.requestPhoneScan() } }
            )
            .padding(.horizontal, DS.space24)
        }
        .padding(.bottom, DS.space24)
        .frame(maxWidth: .infinity)
        .animation(ProMotionSprings.gentle, value: scanController.isPanelVisible)
    }

    // MARK: - Overlays

    private var mapOverlay: some View {
        InquiryMapOverlay(viewModel: viewModel)
            .transition(.opacity)
    }

    private func toastOverlay(_ toast: InquiryToast) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "checkmark.circle.fill")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.accent)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.text)
                if let detail = toast.detail {
                    Text(detail)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 64)
        .padding(.trailing, StudyMetrics.edgeInset)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(ProMotionSprings.gentle, value: viewModel.toast)
    }

    // MARK: - Bindings & exits

    private var crystallizeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .crystallize },
            set: { isPresented in
                if !isPresented { viewModel.setPhase(.explore) }
            }
        )
    }

    /// Esc walks back: dock focus → reader → map → workspace. The dock peels
    /// first — with the field focused, Esc previously fell through and read
    /// as dead (or worse, closed the whole session mid-thought).
    private func handleEscape() {
        if dockFocused {
            dockFocused = false
        } else if viewModel.activeReaderSourceId != nil {
            withAnimation(ProMotionSprings.focusTransition) { viewModel.dismissReader() }
        } else if viewModel.isMapOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) { viewModel.dismissMap() }
        } else {
            closeWorkspace()
        }
    }

    private func closeWorkspace() {
        Task {
            await viewModel.pauseAndPersist()
            onClose()
        }
    }
}

// MARK: - Keyboard map (one source of truth)

@MainActor
private struct StudyShortcuts: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let onEscape: () -> Void

    var body: some View {
        // Hidden zero-size buttons hosting the workspace's keyboard map.
        VStack(spacing: 0) {
            Button("") { onEscape() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("") {
                withAnimation(ProMotionSprings.focusTransition) { viewModel.toggleTrail() }
            }
            .keyboardShortcut("0", modifiers: [.command])
            Button("") {
                withAnimation(ProMotionSprings.focusTransition) { viewModel.toggleReading() }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Button("") {
                withAnimation(ProMotionSprings.focusTransition) { viewModel.toggleMap() }
            }
            .keyboardShortcut("m", modifiers: [.command])
            Button("") { viewModel.focusDock() }
                .keyboardShortcut("k", modifiers: [.command])
            Button("") { viewModel.goToParentQuestion() }
                .keyboardShortcut("[", modifiers: [.command])
            Button("") { viewModel.cycleQuestion(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command])
            quickActionShortcuts
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var quickActionShortcuts: some View {
        VStack(spacing: 0) {
            Button("") {
                Task { await viewModel.runAIPrompt("Summarize the current state of inquiry on \(viewModel.activeQuestionTitle) into 4–5 sentences with hedges.") }
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            Button("") {
                Task { await viewModel.submitDockText("/challenge") }
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])
            Button("") {
                Task { await viewModel.runAIPrompt("Propose 3 child branch questions that would advance the inquiry on \(viewModel.activeQuestionTitle).") }
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])
            Button("") {
                Task { await viewModel.refreshSourceRecommendations(query: nil, mode: .deepScout) }
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])
        }
    }
}
