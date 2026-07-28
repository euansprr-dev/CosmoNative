// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift
// Swipe Study — the bench for one saved swipe (July 2026, the workbench
// conversion). A navigation band up top (navigate · the swipe pill · session
// + actions, with Use in Idea as the screen's ONE tinted glass element), and
// beneath it the worksheet: the analysis rail as the LEADING column, the
// object of study — serif hero, media stage, transcript — owning the center.
// Same WorkbenchShell mechanics as the Study and the Idea bench; the page
// still sits on SwipePageBackground so the hero zoom from the library lands
// on the same paper. State + persistence live in SwipeStudyModel.

import SwiftUI
import AVKit

struct SwipeStudyFocusModeView: View {
    let atom: Atom
    let onClose: () -> Void

    @State private var model: SwipeStudyModel
    /// Scroll metrics live behind @Observable so per-frame scroll ticks
    /// invalidate ONLY the thin scrollbar host — never this whole view
    /// (which would run updateNSView on every slide's NSTextView per frame).
    @State private var scrollMetrics = CortexScrollMetricsStore()
    /// The analysis rail as a true column (regular widths) — the choice
    /// persists; studying is the room's point, so it defaults on.
    @State private var isRailVisible: Bool
    /// Compact/narrow widths: the rail slides OVER the center, never persisted.
    @State private var isRailOverlayPresented = false
    /// Width class, kept in sync by the host geometry (the bench breakpoints).
    @State private var breakpoint: StudyBreakpoint = .regular
    @State private var isCreatingIdea = false

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPeekContext) private var isPeekContext
    @Environment(\.isPaneActive) private var isPaneActive
    @Environment(\.atomWindowChromeContext) private var atomChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let railDefaultsKey = "swipe.workbench.rail"

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        _model = State(initialValue: SwipeStudyModel(atom: atom, onClose: onClose))
        _isRailVisible = State(
            initialValue: UserDefaults.standard.object(forKey: Self.railDefaultsKey) as? Bool ?? true
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SwipePageBackground()

                if let displayAtom = model.currentAtom {
                    bench(atom: displayAtom)
                        .opacity(model.hasAppeared ? 1 : 0)
                        .scaleEffect(model.hasAppeared ? 1 : 0.985)
                        .sheet(isPresented: $model.showEditTranscript) {
                            SwipeStudyEditTranscriptSheet(model: model)
                        }
                } else {
                    loadingState
                }
            }
            .onChange(of: geo.size.width, initial: true) { _, width in
                let resolved = StudyBreakpoint(width: width)
                if breakpoint != resolved {
                    breakpoint = resolved
                }
            }
        }
        .onAppear {
            model.onClose = onClose
            model.contextPublishingEnabled = !isPaneContext || isPaneActive
            model.start()
            // Tells the launching swipe page its zoom-through hero has been
            // relieved — the page holds the hero until this arrives.
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.swipeStudyDidAppear,
                object: nil
            )
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
        .onKeyPress(.escape) { handleEscape() }
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

    // MARK: - The bench (chrome band + one rounded worksheet)

    private func bench(atom: Atom) -> some View {
        ScrollViewReader { proxy in
            VStack(spacing: DS.space8) {
                SwipeStudyChromeRow(
                    model: model,
                    atom: atom,
                    breakpoint: breakpoint,
                    isRailShowing: isRailShowing,
                    isPaneContext: isPaneContext,
                    isPeekContext: isPeekContext,
                    atomChrome: atomChrome,
                    isCreatingIdea: isCreatingIdea,
                    onToggleRail: toggleRail,
                    onUseInIdea: { useInIdea(atom: atom) },
                    onClose: onClose
                )
                workbenchSheet(atom: atom, proxy: proxy)
            }
        }
    }

    /// The worksheet: analysis | the swipe itself. One leading panel — the
    /// shell's trailing column stays empty on this bench.
    private func workbenchSheet(atom: Atom, proxy: ScrollViewProxy) -> some View {
        WorkbenchShell(
            panelsDisplace: breakpoint.panelsDisplace,
            isLeadingShowing: isRailShowing,
            isTrailingShowing: false,
            showsScrim: breakpoint == .narrow,
            onScrimTap: {
                withAnimation(ProMotionSprings.focusTransition) { isRailOverlayPresented = false }
            }
        ) {
            SwipeStudyAnalysisPanel(
                model: model,
                atom: atom,
                isOverlay: !breakpoint.panelsDisplace
            ) { section in
                handleBeatTap(section, atom: atom, proxy: proxy)
            }
        } center: {
            centerColumn(atom: atom)
        } trailing: {
            EmptyView()
        }
    }

    // MARK: - Center (the object of study)

    /// Hero title, media stage, transcript — one reading measure, assembled
    /// top to bottom on arrival.
    private func centerColumn(atom: Atom) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                SwipeStudyHeroBlock(model: model, atom: atom)
                    .studyStagger(0, appeared: model.hasAppeared, reduceMotion: reduceMotion)
                SwipeStudyStagePane(model: model, atom: atom)
                    .studyStagger(1, appeared: model.hasAppeared, reduceMotion: reduceMotion)
                SwipeStudyTranscriptBlock(model: model, atom: atom)
                    .studyStagger(2, appeared: model.hasAppeared, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, DS.space24)
            .padding(.top, DS.space24)
            .padding(.bottom, DS.space48)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                CortexScrollViewIntrospector { [scrollMetrics] metrics in
                    scrollMetrics.publish(metrics)
                }
            )
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .overlay(alignment: .trailing) {
            CortexThinScrollbarHost(store: scrollMetrics)
                .padding(.trailing, DS.space4)
                .padding(.vertical, DS.space16)
        }
    }

    // MARK: - Rail state

    private var isRailShowing: Bool {
        breakpoint.panelsDisplace ? isRailVisible : isRailOverlayPresented
    }

    private func toggleRail() {
        withAnimation(ProMotionSprings.focusTransition) {
            if breakpoint.panelsDisplace {
                isRailVisible.toggle()
                UserDefaults.standard.set(isRailVisible, forKey: Self.railDefaultsKey)
            } else {
                isRailOverlayPresented.toggle()
            }
        }
    }

    // MARK: - Use in Idea (the bench's primary action)

    /// Start an idea from this swipe: the swipe rides along as linked
    /// inspiration, and the idea inherits the swipe's classified format and
    /// platform — so the Idea bench's recommended shelf wakes up matched.
    private func useInIdea(atom: Atom) {
        guard !isCreatingIdea else { return }
        isCreatingIdea = true
        Task {
            var ideaAtom = Atom.new(type: .idea, title: "Untitled Idea", body: nil, metadata: nil)
            ideaAtom = ideaAtom.withUpdatedIdeaMetadata { meta in
                meta.linkedSwipeIds = [atom.uuid]
                if let format = model.analysis?.swipeContentFormat {
                    meta.contentFormat = format
                }
                if let platform = ideaPlatform(for: atom) {
                    meta.platform = platform
                }
            }
            guard let created = try? await AtomRepository.shared.create(ideaAtom),
                  let id = created.id else {
                isCreatingIdea = false
                return
            }
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": id]
            )
            isCreatingIdea = false
        }
    }

    private func ideaPlatform(for atom: Atom) -> IdeaPlatform? {
        guard let source = model.detectSourceType(for: atom)?.rawValue.lowercased() else { return nil }
        if source.hasPrefix("instagram") { return .instagram }
        if source.hasPrefix("youtube") { return .youtube }
        return nil
    }

    // MARK: - Beat anchors

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

    // MARK: - Keyboard

    /// Esc peels the overlay rail first (compact widths), then closes.
    private func handleEscape() -> KeyPress.Result {
        if !breakpoint.panelsDisplace, isRailOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) { isRailOverlayPresented = false }
            return .handled
        }
        onClose()
        return .handled
    }

    private var keyboardLayer: some View {
        Group {
            Button("") { toggleRail() }.keyboardShortcut("0", modifiers: .command)
            Button("") { model.goPrevious() }.keyboardShortcut("[", modifiers: .command)
            Button("") { model.goNext() }.keyboardShortcut("]", modifiers: .command)
            Button("") { model.copyTranscript() }.keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
}

// MARK: - Chrome band (navigate · the swipe pill · session + actions)

private struct SwipeStudyChromeRow: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom
    let breakpoint: StudyBreakpoint
    let isRailShowing: Bool
    let isPaneContext: Bool
    let isPeekContext: Bool
    let atomChrome: AtomWindowChromePayload?
    let isCreatingIdea: Bool
    let onToggleRail: () -> Void
    let onUseInIdea: () -> Void
    let onClose: () -> Void

    @Environment(\.paneDeckChrome) private var paneDeckChrome

    var body: some View {
        // Absolute centering needs regular width AND full-screen hosting —
        // beside the open pane deck main content can be squeezed to pane
        // widths, where the pill flows between the clusters instead.
        CosmoChromeRow(centersAbsolutely: !isPaneContext && breakpoint == .regular) {
            if atomChrome == nil, !isPaneContext {
                NavigationTrailIsland()
            }
            if let paneDeckChrome {
                CosmoChromeIsland { PaneDeckTabStrip(context: paneDeckChrome) }
            }
            CosmoChromeIsland { leadingControls }
        } center: {
            // The focused tab already names the swipe in pane context — a
            // center pill would say it twice (its vitals move to the
            // session island).
            if paneDeckChrome == nil {
                CosmoChromeIsland { swipePill }
            }
        } trailing: {
            sessionIsland
            CosmoChromeIsland { trailingControls }
            useInIdeaIsland
        }
    }

    // MARK: Navigate island

    @ViewBuilder
    private var leadingControls: some View {
        if let atomChrome {
            AtomWindowChromeLeadingControls(context: atomChrome)
            AtomWindowChromeDivider()
        }
        StudyToolbarButton(
            icon: "sidebar.squares.left",
            help: isRailShowing ? "Hide analysis (⌘0)" : "Show analysis (⌘0)",
            isActive: isRailShowing,
            action: onToggleRail
        )
    }

    // MARK: The swipe pill (orientation — the center island)

    /// The swipe's own mark, its hook, and where you are in the study queue.
    /// The serif hero in the manuscript stays the hero; this is the bench's
    /// inline title.
    private var swipePill: some View {
        HStack(spacing: DS.space6) {
            SwipePlatformGlyph(source: model.detectSourceType(for: atom)?.rawValue)
                .frame(width: 11, height: 11)
                .foregroundStyle(DS.textSecondary)
            Text(model.heroTitle)
                .font(DS.buttonText.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: breakpoint == .narrow ? 180 : 320)
            if model.analysis?.studiedAt != nil {
                Image(systemName: "checkmark.seal.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent.opacity(0.7))
                    .help("Studied")
                    .accessibilityLabel("Studied")
            }
            if let position = SwipeStudySession.shared.positionLabel {
                Text("·")
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text(position)
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, DS.space4)
        .help(model.sourceDescriptor(for: atom))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Swipe: \(model.heroTitle)")
        .animation(ProMotionSprings.gentle, value: SwipeStudySession.shared.positionLabel)
    }

    // MARK: Session island (the study queue)

    @ViewBuilder
    private var sessionIsland: some View {
        let session = SwipeStudySession.shared
        if session.hasPrevious || session.hasNext {
            CosmoChromeIsland {
                StudyToolbarButton(icon: "chevron.left", help: "Previous swipe (⌘[)") {
                    model.goPrevious()
                }
                .disabled(!session.hasPrevious)
                .opacity(session.hasPrevious ? 1 : 0.35)

                // In pane context the center pill is gone (the tab names the
                // swipe) — the queue position and studied seal ride between
                // the session chevrons instead.
                if paneDeckChrome != nil {
                    if let position = session.positionLabel {
                        Text(position)
                            .font(DS.caption.monospacedDigit())
                            .foregroundStyle(DS.textMuted)
                            .contentTransition(.numericText())
                            .animation(ProMotionSprings.gentle, value: session.positionLabel)
                    }
                    if model.analysis?.studiedAt != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(DS.caption2)
                            .foregroundStyle(DS.accent.opacity(0.7))
                            .help("Studied")
                            .accessibilityLabel("Studied")
                    }
                }

                StudyToolbarButton(icon: "chevron.right", help: "Next swipe (⌘])") {
                    model.goNext()
                }
                .disabled(!session.hasNext)
                .opacity(session.hasNext ? 1 : 0.35)
            }
        }
    }

    // MARK: Tools island

    @ViewBuilder
    private var trailingControls: some View {
        overflowMenu
        if let atomChrome {
            AtomWindowChromeDivider()
            AtomWindowChromeTrailingControls(context: atomChrome)
        }
        // Pane close lives in the deck tab (the strip's ✕) — no mode-owned
        // xmark in pane context anymore.
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
                .font(DS.buttonText)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28)
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    // MARK: Use in Idea (the one tinted glass element)

    /// The bench's primary action wears the screen's only glass tint —
    /// Crystallize's role in the Study, Begin Writing's in the Idea bench.
    private var useInIdeaIsland: some View {
        Button(action: onUseInIdea) {
            HStack(spacing: DS.space4) {
                if isCreatingIdea {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "lightbulb")
                        .font(DS.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                if breakpoint != .narrow || isCreatingIdea {
                    Text(isCreatingIdea ? "Starting…" : "Use in Idea")
                        .font(DS.buttonText.weight(.semibold))
                }
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, DS.space12)
            .frame(height: CosmoChromeMetrics.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(DS.accentSoft).interactive(), in: .capsule)
        .disabled(isCreatingIdea)
        .keyboardShortcut(.return, modifiers: [.command])
        .help("Start an idea from this swipe — links it and carries the format (⌘⏎)")
        .accessibilityLabel("Use in idea")
    }
}

// MARK: - Analysis panel (the leading column)

/// The insight rail as a bench panel: INSIGHT → STRUCTURE → PATTERNS →
/// DETAILS on the study panel surface, scrolling independently of the
/// manuscript. Beat taps anchor into the center column.
private struct SwipeStudyAnalysisPanel: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom
    var isOverlay: Bool = false
    let onBeatTap: (SwipeSection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                SwipeStudyInsightRail(model: model, atom: atom, onBeatTap: onBeatTap)
                    .padding(.horizontal, DS.space16)
                    .padding(.bottom, DS.space16)
            }
            .scrollIndicators(.never)
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .frame(width: StudyMetrics.panelWidth)
        .studyPanelSurface(edge: .leading, isOverlay: isOverlay)
    }

    private var header: some View {
        HStack(spacing: DS.space6) {
            Text("ANALYSIS")
                .dsSmallCapsLabel()
            Spacer()
            if model.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            } else if let beats = model.analysis?.sections?.count, beats > 0 {
                Text("\(beats)")
                    .font(DS.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space10)
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
