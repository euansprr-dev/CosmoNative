// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift
// Swipe Study — the reading room for one saved swipe. Rebuilt July 2026 on
// the Swipe File page grammar: one serif hero (the title), sans chrome, a
// media stage, the transcript manuscript, and a single analysis rail fed by
// the insight pass. State + persistence live in SwipeStudyModel.

import SwiftUI
import AVKit

struct SwipeStudyFocusModeView: View {
    let atom: Atom
    let onClose: () -> Void

    @State private var model: SwipeStudyModel
    @State private var scrollMetrics = CortexScrollMetrics()

    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPeekContext) private var isPeekContext
    @Environment(\.isPaneActive) private var isPaneActive
    @Environment(\.atomWindowChromeContext) private var atomChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        _model = State(initialValue: SwipeStudyModel(atom: atom, onClose: onClose))
    }

    var body: some View {
        ZStack {
            SwipePageBackground()

            if let displayAtom = model.currentAtom {
                VStack(spacing: 0) {
                    SwipeStudyTopBar(
                        model: model,
                        atom: displayAtom,
                        isSidebarHidden: $isSidebarHidden,
                        isPaneContext: isPaneContext,
                        isPeekContext: isPeekContext,
                        atomChrome: atomChrome,
                        onClose: onClose
                    )
                    workspace(atom: displayAtom)
                }
                .opacity(model.hasAppeared ? 1 : 0)
                .scaleEffect(model.hasAppeared ? 1 : 0.985)
                .sheet(isPresented: $model.showEditTranscript) {
                    SwipeStudyEditTranscriptSheet(model: model)
                }
            } else {
                loadingState
            }
        }
        .onAppear {
            model.onClose = onClose
            model.contextPublishingEnabled = !isPaneContext || isPaneActive
            model.start()
        }
        .onDisappear {
            model.stop()
        }
        .onChange(of: isPaneActive) { _, isActive in
            model.contextPublishingEnabled = !isPaneContext || isActive
            if isActive {
                model.publishContextProvider()
            }
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .focusImmersiveEntryTransition()
        .background(keyboardLayer)
        .overlay {
            if model.showTaxonomyManagement {
                ZStack {
                    FloatingOverlayBackdrop { model.showTaxonomyManagement = false }
                    TaxonomyManagementView(onClose: { model.showTaxonomyManagement = false })
                        .frame(maxWidth: 520, maxHeight: 560)
                        .floatingOverlayPanel()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .alert("Delete Swipe?", isPresented: $model.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { model.deleteSwipe() }
        } message: {
            Text("This permanently removes the swipe and all its analysis.")
        }
    }

    // MARK: - Workspace

    private func workspace(atom: Atom) -> some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    layout(atom: atom, size: geo.size, proxy: proxy)
                        .background(
                            CortexScrollViewIntrospector { metrics in
                                if metrics != scrollMetrics {
                                    scrollMetrics = metrics
                                }
                            }
                        )
                }
                .scrollIndicators(.hidden)
                .overlay(alignment: .trailing) {
                    CortexThinScrollbar(metrics: scrollMetrics)
                        .padding(.trailing, DS.space4)
                        .padding(.vertical, DS.space16)
                }
            }
        }
    }

    /// Three width tiers, one grammar. Wide keeps the full reading room;
    /// medium (a normal pane) pairs the media with the title + analysis so the
    /// transcript stops dominating the fold; compact (a narrow pane) leads
    /// with a small header card and gives the width to the transcript.
    @ViewBuilder
    private func layout(atom: Atom, size: CGSize, proxy: ScrollViewProxy) -> some View {
        if size.width >= 980 {
            wideLayout(atom: atom, size: size, proxy: proxy)
        } else if size.width >= 620 {
            mediumLayout(atom: atom, size: size, proxy: proxy)
        } else {
            compactLayout(atom: atom, proxy: proxy)
        }
    }

    private func wideLayout(atom: Atom, size: CGSize, proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .top, spacing: DS.space40) {
            VStack(alignment: .leading, spacing: DS.space24) {
                stage(atom: atom)
                rail(atom: atom, proxy: proxy)
            }
            .frame(width: min(460, max(360, size.width * 0.3)), alignment: .top)
            .studyStagger(0, appeared: model.hasAppeared, reduceMotion: reduceMotion)

            manuscript(atom: atom)
                .frame(maxWidth: 680, alignment: .topLeading)
                .studyStagger(1, appeared: model.hasAppeared, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: 1280, alignment: .top)
        .padding(.horizontal, DS.space32)
        .padding(.top, DS.space24)
        .padding(.bottom, DS.space48)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Normal pane width: media beside title + insight + structure — an
    /// editorial header — then the transcript at full width, then the rest.
    private func mediumLayout(atom: Atom, size: CGSize, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: DS.space32) {
            HStack(alignment: .top, spacing: DS.space24) {
                stage(atom: atom)
                    .frame(width: min(300, size.width * 0.42), alignment: .top)

                VStack(alignment: .leading, spacing: DS.space20) {
                    SwipeStudyHeroBlock(model: model, atom: atom, compact: true)
                    SwipeStudyInsightRail(
                        model: model,
                        atom: atom,
                        visibleSections: [.insight, .structure]
                    ) { section in
                        handleBeatTap(section, atom: atom, proxy: proxy)
                    }
                }
            }
            .studyStagger(0, appeared: model.hasAppeared, reduceMotion: reduceMotion)

            SwipeStudyTranscriptBlock(model: model, atom: atom)
                .studyStagger(1, appeared: model.hasAppeared, reduceMotion: reduceMotion)

            SwipeStudyInsightRail(
                model: model,
                atom: atom,
                visibleSections: [.patterns, .details]
            ) { section in
                handleBeatTap(section, atom: atom, proxy: proxy)
            }
            .studyStagger(2, appeared: model.hasAppeared, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, DS.space24)
        .padding(.top, DS.space16)
        .padding(.bottom, DS.space40)
    }

    /// Narrow pane: a small header card (thumb + title + insight), then the
    /// transcript owns the width.
    private func compactLayout(atom: Atom, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            SwipeStudyCompactHeader(model: model, atom: atom)
                .studyStagger(0, appeared: model.hasAppeared, reduceMotion: reduceMotion)

            SwipeStudyTranscriptBlock(model: model, atom: atom)
                .studyStagger(1, appeared: model.hasAppeared, reduceMotion: reduceMotion)

            SwipeStudyInsightRail(
                model: model,
                atom: atom,
                visibleSections: [.structure, .patterns, .details]
            ) { section in
                handleBeatTap(section, atom: atom, proxy: proxy)
            }
            .studyStagger(2, appeared: model.hasAppeared, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space40)
    }

    private func stage(atom: Atom) -> some View {
        SwipeStudyStagePane(model: model, atom: atom)
    }

    private func manuscript(atom: Atom) -> some View {
        SwipeStudyManuscript(model: model, atom: atom)
    }

    private func rail(atom: Atom, proxy: ScrollViewProxy) -> some View {
        SwipeStudyInsightRail(model: model, atom: atom) { section in
            handleBeatTap(section, atom: atom, proxy: proxy)
        }
    }

    /// A structure beat is an anchor: slides scroll, videos seek.
    private func handleBeatTap(_ section: SwipeSection, atom: Atom, proxy: ScrollViewProxy) {
        if model.isInstagramSwipe(atom), let slideStart = section.slideStart,
           model.transcriptSlides.count > 1 {
            withAnimation(ProMotionSprings.gentle) {
                proxy.scrollTo(SwipeStudyScrollTarget.slide(slideStart), anchor: .center)
            }
            if model.isCarouselContent {
                withAnimation(ProMotionSprings.snappy) {
                    model.carouselCurrentIndex = min(
                        max(slideStart - 1, 0),
                        (model.igMediaData?.carouselItems?.count ?? 1) - 1
                    )
                }
            }
            return
        }

        // Video sources: seek to the beat's cumulative start position.
        guard model.videoDuration > 0, let sections = model.analysis?.sections else {
            withAnimation(ProMotionSprings.gentle) {
                proxy.scrollTo(SwipeStudyScrollTarget.transcript, anchor: .top)
            }
            return
        }
        var startFraction: Double = 0
        for candidate in sections {
            if candidate.id == section.id { break }
            startFraction += candidate.sizePercent ?? (1.0 / Double(sections.count))
        }
        let time = min(max(startFraction, 0), 1) * model.videoDuration
        model.currentTimestamp = time
        if let player = model.igPlayer {
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        } else if !model.isPlayerActive {
            model.isPlayerActive = true
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: DS.space16) {
            ProgressView().controlSize(.small)
            Text("Opening swipe…")
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Keyboard

    private var keyboardLayer: some View {
        Group {
            Button("") { model.goPrevious() }.keyboardShortcut("[", modifiers: .command)
            Button("") { model.goNext() }.keyboardShortcut("]", modifiers: .command)
            Button("") { model.copyTranscript() }.keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Top bar

private struct SwipeStudyTopBar: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom
    @Binding var isSidebarHidden: Bool
    let isPaneContext: Bool
    let isPeekContext: Bool
    let atomChrome: AtomWindowChromePayload?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: DS.space12) {
            leading
            Spacer()
            center
            Spacer()
            trailing
        }
        .padding(.horizontal, DS.space20)
        .frame(height: 56)
    }

    @ViewBuilder
    private var leading: some View {
        if let atomChrome {
            AtomWindowChromeLeadingControls(context: atomChrome)
        } else if !isPaneContext {
            Button {
                withAnimation(ProMotionSprings.sidebar) { isSidebarHidden.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(DS.navTitle)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSidebarHidden ? "Show sidebar (⌘\\)" : "Hide sidebar (⌘\\)")
            .accessibilityLabel("Toggle sidebar")

            NavigationTrailIsland()
        }
    }

    @ViewBuilder
    private var center: some View {
        HStack(spacing: DS.space6) {
            Text(model.analysis?.studiedAt != nil ? "Studied" : "Studying")
                .foregroundStyle(DS.textMuted)
            if let position = SwipeStudySession.shared.positionLabel {
                Text("·").foregroundStyle(DS.textMuted)
                Text(position)
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .font(DS.caption)
        .animation(ProMotionSprings.gentle, value: SwipeStudySession.shared.positionLabel)
    }

    @ViewBuilder
    private var trailing: some View {
        let session = SwipeStudySession.shared

        if session.hasPrevious || session.hasNext {
            HStack(spacing: 2) {
                navButton("chevron.left", enabled: session.hasPrevious, help: "Previous swipe (⌘[)") {
                    model.goPrevious()
                }
                navButton("chevron.right", enabled: session.hasNext, help: "Next swipe (⌘])") {
                    model.goNext()
                }
            }
        }

        overflowMenu

        if let atomChrome {
            AtomWindowChromeTrailingControls(context: atomChrome)
        } else if isPaneContext, !isPeekContext {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close pane")
            .accessibilityLabel("Close pane")
        }
    }

    private func navButton(_ systemName: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(enabled ? DS.textSecondary : DS.textMuted.opacity(0.4))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private var overflowMenu: some View {
        Menu {
            Button("Copy Transcript", systemImage: "doc.on.doc") {
                model.copyTranscript()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Reanalyze", systemImage: "sparkles") {
                model.reanalyze()
            }

            if model.isInstagramSwipe(atom) {
                Button("Re-transcribe", systemImage: "arrow.triangle.2.circlepath") {
                    model.retranscribeInstagram()
                }
                Button("Refresh Stats", systemImage: "chart.line.uptrend.xyaxis") {
                    model.refreshEngagementStats()
                }
            } else if !model.transcriptText.isEmpty {
                Button("Edit Transcript", systemImage: "pencil") {
                    model.editTranscriptText = model.transcriptText
                    model.showEditTranscript = true
                }
            }

            Button("Manage Taxonomy", systemImage: "tag") {
                model.showTaxonomyManagement = true
            }

            Divider()

            Button("Delete Swipe", systemImage: "trash", role: .destructive) {
                model.showDeleteConfirmation = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(DS.navTitle)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
        .help("More actions")
        .accessibilityLabel("More actions")
    }
}

// MARK: - Edit transcript sheet (YouTube / plain sources)

private struct SwipeStudyEditTranscriptSheet: View {
    @Bindable var model: SwipeStudyModel

    var body: some View {
        VStack(spacing: DS.space16) {
            HStack {
                Text("Edit Transcript")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
                Spacer()
                Button("Cancel") { model.showEditTranscript = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textSecondary)
            }

            TextEditor(text: $model.editTranscriptText)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200, maxHeight: 400)
                .padding(DS.space12)
                .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Text("\(model.editTranscriptText.split(separator: " ").count) words")
                    .font(DS.subheadline.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Button {
                    model.saveEditedTranscript()
                } label: {
                    Text("Save & Reanalyze")
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, DS.space16)
                        .padding(.vertical, DS.space10)
                        .background(DS.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.editTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(DS.space20)
        .frame(width: 560)
        .background(DS.bg)
    }
}

// MARK: - Entrance stagger

private extension View {
    func studyStagger(_ index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.985)
            .offset(y: reduceMotion || appeared ? 0 : 8)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : ProMotionSprings.cardEntrance.delay(Double(index) * 0.06),
                value: appeared
            )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let previewAtom = Atom(
        id: 1,
        uuid: UUID().uuidString,
        type: .research,
        title: "Preview Swipe",
        body: nil,
        structured: nil,
        metadata: nil,
        links: nil,
        createdAt: ISO8601.string(from: Date()),
        updatedAt: ISO8601.string(from: Date()),
        isDeleted: false,
        localVersion: 0,
        serverVersion: 0,
        syncVersion: 0
    )
    SwipeStudyFocusModeView(
        atom: previewAtom,
        onClose: {}
    )
    .frame(width: 1200, height: 800)
}
#endif
