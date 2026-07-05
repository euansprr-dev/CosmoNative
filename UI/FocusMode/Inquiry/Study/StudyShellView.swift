// CosmoOS/UI/FocusMode/Inquiry/Study/StudyShellView.swift
// The Study: one continuous manuscript (content layer) with exactly four
// pieces of Liquid Glass floating above it (chrome layer) — the chrome
// islands, two quiet side panels, and the thinking bar. No welded columns,
// no full-height dividers; depth comes from the glass, not from strokes.

import SwiftUI

@MainActor
struct StudyShellView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let onClose: () -> Void

    @State private var dockDraft: String = ""
    @FocusState private var dockFocused: Bool
    @State private var hasArrived = false

    var body: some View {
        GeometryReader { proxy in
            let breakpoint = StudyBreakpoint(width: proxy.size.width)
            ZStack {
                contentLayer(breakpoint)
                chromeLayer(breakpoint)
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
        .task { await arrive() }
        .onDisappear { Task { await viewModel.pauseAndPersist() } }
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
        await viewModel.loadDeepDiveAndRoot()
        // One-frame rule: flip after data lands so the page assembles on
        // arrival instead of mounting pre-visible.
        try? await Task.sleep(for: .milliseconds(16))
        hasArrived = true
    }

    // MARK: - Content layer (the manuscript — never glass)

    @ViewBuilder
    private func contentLayer(_ breakpoint: StudyBreakpoint) -> some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            centerColumn
                .padding(.leading, leadingInset(breakpoint))
                .padding(.trailing, trailingInset(breakpoint))
                .animation(ProMotionSprings.focusTransition, value: leadingInset(breakpoint))
                .animation(ProMotionSprings.focusTransition, value: trailingInset(breakpoint))
        }
        .filmGrain(opacity: 0.02)
    }

    @ViewBuilder
    private var centerColumn: some View {
        if let tabId = viewModel.activeReaderSourceId,
           let tab = viewModel.structured.sourceTabs.first(where: { $0.id == tabId }) {
            // The source is a document OBJECT on the desk: a rounded sheet
            // whose corners and insets are concentric with the side panels —
            // never a raw web rectangle butting against the chrome.
            InquiryReaderView(viewModel: viewModel, tab: tab)
                .clipShape(RoundedRectangle(cornerRadius: StudyMetrics.panelCorner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudyMetrics.panelCorner, style: .continuous)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                .padding(.horizontal, StudyMetrics.edgeInset)
                .padding(.top, StudyMetrics.panelTopInset)
                .padding(.bottom, StudyMetrics.panelBottomInset)
                .transition(.opacity)
        } else {
            StudyPageView(viewModel: viewModel, hasArrived: hasArrived)
                .transition(.opacity)
        }
    }

    /// At regular width a docked panel reserves exactly its own width so the
    /// reading column centers on the TRUE page axis between the panels.
    private func leadingInset(_ breakpoint: StudyBreakpoint) -> CGFloat {
        guard breakpoint.panelsDisplace, viewModel.isTrailShowing else { return 0 }
        return StudyMetrics.panelWidth
    }

    private func trailingInset(_ breakpoint: StudyBreakpoint) -> CGFloat {
        guard breakpoint.panelsDisplace, viewModel.isReadingShowing else { return 0 }
        return StudyMetrics.panelWidth
    }

    // MARK: - Chrome layer (glass only)

    @ViewBuilder
    private func chromeLayer(_ breakpoint: StudyBreakpoint) -> some View {
        panelScrim(breakpoint)
        panels(breakpoint)
        VStack(spacing: 0) {
            StudyChromeRow(
                viewModel: viewModel,
                breakpoint: breakpoint,
                isReceded: dockFocused || viewModel.activeReaderSourceId != nil,
                onClose: closeWorkspace
            )
            Spacer()
        }
        bottomInstruments
    }

    /// Inspectors dock edge-to-edge, full height, flush to the window — the
    /// Apple inspector idiom (navigation floats; inspectors sit alongside
    /// content). The chrome islands float above them like Tahoe toolbars.
    private func panels(_ breakpoint: StudyBreakpoint) -> some View {
        HStack(spacing: 0) {
            if viewModel.isTrailShowing {
                StudyTrailPanel(viewModel: viewModel, isOverlay: !breakpoint.panelsDisplace)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if viewModel.isReadingShowing {
                StudyReadingPanel(viewModel: viewModel, isOverlay: !breakpoint.panelsDisplace)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.focusTransition, value: viewModel.isTrailShowing)
        .animation(ProMotionSprings.focusTransition, value: viewModel.isReadingShowing)
    }

    /// Narrow overlays get a whisper of scrim; tap dismisses. Light enough
    /// that the glass behind stays alive.
    @ViewBuilder
    private func panelScrim(_ breakpoint: StudyBreakpoint) -> some View {
        if breakpoint == .narrow, viewModel.isTrailShowing || viewModel.isReadingShowing {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    withAnimation(ProMotionSprings.focusTransition) {
                        viewModel.isTrailShowing = false
                        viewModel.isReadingShowing = false
                    }
                }
                .accessibilityLabel("Dismiss panels")
        }
    }

    private var bottomInstruments: some View {
        VStack(spacing: DS.space8) {
            Spacer()
            StudyReceiptStack(viewModel: viewModel)
                .padding(.horizontal, DS.space24)
            StudyThinkingBar(viewModel: viewModel, draft: $dockDraft, isFocused: $dockFocused)
                .padding(.horizontal, DS.space24)
        }
        .padding(.bottom, StudyMetrics.edgeInset)
        .frame(maxWidth: .infinity)
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

    /// Esc walks back: reader → map → workspace.
    private func handleEscape() {
        if viewModel.activeReaderSourceId != nil {
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
