// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeView.swift
// Idea Focus Mode v3 — the development bench.
// July 2026 overhaul: the page is one warm sheet (the Notes/Content focus
// paper doctrine + vignette), the head carries a live ripening control and an
// editable identity line, hooks are a lab (working-hook star, AI ghost
// suggestions, ⌥↑/⌥↓ reorder), the outline wears its framework beats, and the
// chrome recedes while writing. Editors live in IdeaManuscriptEditors.swift;
// intelligence panels in IdeaInspectorView.swift; chrome state in
// IdeaWorkspaceModel.swift.

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Idea Focus Mode View

struct IdeaFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - State

    @State private var viewModel: IdeaFocusModeViewModel
    @State private var workspace = IdeaWorkspaceModel()
    /// The bench's width, quantized — feeds the chrome row's title budget.
    @State private var chromeWidth: CGFloat = 0
    @State private var newHookText: String = ""
    /// The view OWNS its context provider — the editable-surface registry holds
    /// it weakly; the old single global slot deallocated it on any other view's
    /// registration, unbinding this surface from the assistant.
    @State private var ownedContextProvider: IdeaContextProvider?
    @State private var isPromoting: Bool = false
    @State private var showProfileEditor: Bool = false
    @State private var atelierScrollMetrics = CortexScrollMetricsStore()
    @State private var bodyReviewProposal: CosmoAssistantProposal?
    /// First-load arrival — the page assembles once, then never again.
    @State private var hasArrived = false
    /// Chrome recede: true while keystrokes are landing; the islands quiet
    /// to a whisper until typing pauses (~1.4s) — they wake on hover.
    @State private var isActivelyTyping = false
    @State private var typingActivityTask: Task<Void, Never>?
    @State private var hoveredHookIndex: Int?
    @State private var hoveredSlideID: UUID?
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContextFocused: Bool
    @FocusState private var focusedHookEditor: HookEditorFocus?
    @FocusState private var focusedOutlineSlideID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The idea's own accent — used sparingly for the focus rule.
    private let ideaAccent = DS.entityIdea

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner

    // MARK: - Focus surface tokens (the Notes/Content paper doctrine)

    private var focusBackground: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBackground : DS.documentBackground }
    private var focusSurface: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveSurface : DS.documentSurface }
    private var focusText: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveText : DS.documentText }
    private var focusTextSecondary: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveTextSecondary : DS.documentTextSecondary }
    private var focusTextMuted: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveTextMuted : DS.documentTextMuted }
    private var focusBorder: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBorder : DS.documentBorder }

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        _viewModel = State(initialValue: IdeaFocusModeViewModel(atom: atom))
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            // Resolved in-pass, exactly as the Study and Swipe Study shells do
            // it. Routing this through `.onChange` -> state instead would draw
            // one pass late: the sheet would seat its columns against the
            // width from BEFORE the resize, so mid-drag (and for one frame
            // after the drop) it lays out wider than the container it was
            // given and gets clipped instead of reflowing.
            let breakpoint = IdeaWorkspaceBreakpoint(
                width: geometry.size.width,
                columns: workspace.requestedColumnCount
            )
            ZStack {
                DS.bg.ignoresSafeArea()
                VStack(spacing: CosmoSurfaceMetrics.chromeGap) {
                    chromeRow
                    workbenchSheet(breakpoint: breakpoint)
                }
                overlayPresentations
            }
            .onChange(of: breakpoint, initial: true) { _, resolved in
                // The toolbar and keyboard shortcuts read the model, and can
                // afford to trail a pass — the layout above cannot.
                workspace.breakpoint = resolved
            }
            .onChange(of: geometry.size.width, initial: true) { _, width in
                // Quantized: a pane-divider drag must not invalidate the
                // chrome row on every frame.
                let quantized = CosmoChromeMetrics.quantizedWidth(width)
                if chromeWidth != quantized {
                    chromeWidth = quantized
                }
            }
        }
        .background {
            FocusModeEditorBlurClickMonitor {
                clearManuscriptEditingFocus()
            }
        }
        .cosmoSurfaceKeyWindowActivation(surfaceID: "idea:\(atom.uuid)")
        .focusImmersiveEntryTransition()
        .onAppear(perform: handleAppear)
        .onChange(of: isPaneContextOwner) { _, isOwner in
            if isOwner { registerContextProvider() }
        }
        .onReceive(CosmoInlineAssistantStore.shared.$proposals) { proposals in
            let surfaceID = "idea:\(atom.uuid)"
            bodyReviewProposal = proposals.last { proposal in
                proposal.surfaceID == surfaceID && proposal.hasReviewableOperations
            }
        }
        .onDisappear {
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
            typingActivityTask?.cancel()
            viewModel.saveOnClose()
            // Assistant scope and window context follow presence: leaving the
            // idea releases both.
            if let owned = ownedContextProvider {
                CosmoEditableSurfaceRegistry.shared.unregister(owned)
                CosmoWindowViewModel.shared.releaseContext(provider: owned)
                ownedContextProvider = nil
            }
        }
        // The termination flush belongs to the MOUNTED view, never to the model
        // (the Content/Notes idiom). `State(initialValue:)` is not lazy, so this
        // view's initializer builds a model on every re-render and SwiftUI
        // discards all but the first; when the model subscribed in its own init,
        // quitting made every discarded copy flush its pre-edit text over the
        // live one. Only one view is mounted, so only one flush can fire.
        .onReceive(NotificationCenter.default.publisher(for: .cosmoAppWillTerminate)) { _ in
            viewModel.flushForTermination()
        }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress { handleKeyCommand($0) }
        .overlay { profileEditorOverlay }
    }

    // MARK: - The bench (chrome band + one rounded worksheet)

    private var chromeRow: some View {
        IdeaWorkspaceToolbar(
            viewModel: viewModel,
            workspace: workspace,
            isPaneContext: isPaneContext,
            availableWidth: chromeWidth,
            isPromoting: isPromoting,
            isReceded: isActivelyTyping,
            actions: workspaceActions
        )
    }

    /// The worksheet: conversation | manuscript | swipe wall, welded into one
    /// rounded sheet (the bench anatomy shared with the Study).
    private func workbenchSheet(breakpoint: IdeaWorkspaceBreakpoint) -> some View {
        WorkbenchShell(
            panelsDisplace: breakpoint == .regular,
            isLeadingShowing: workspace.isConversationShowing(at: breakpoint),
            isTrailingShowing: workspace.isInspectorShowing(at: breakpoint),
            showsScrim: breakpoint == .compact,
            onScrimTap: {
                withAnimation(ProMotionSprings.focusTransition) {
                    workspace.isConversationOverlayPresented = false
                    workspace.isInspectorOverlayPresented = false
                }
            }
        ) {
            IdeaConversationPanel(
                store: CosmoInlineAssistantStore.shared,
                isOverlay: breakpoint == .compact
            )
        } center: {
            centerColumn
        } trailing: {
            IdeaInspectorView(
                viewModel: viewModel,
                actions: workspaceActions,
                isOverlay: breakpoint == .compact
            )
        }
    }

    /// The manuscript's paper column — the focus surface inside the sheet;
    /// during promotion a warm bloom rises behind it (the one earned delight).
    private var centerColumn: some View {
        ScrollView {
            manuscriptColumn
                .padding(.horizontal, DS.space24)
                .padding(.top, DS.space24)
                .padding(.bottom, DS.space48)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(
                    CortexScrollViewIntrospector { metrics in
                        atelierScrollMetrics.publish(metrics)
                    }
                )
        }
        .scrollIndicators(.hidden)
        .cortexThinScrollbar(store: atelierScrollMetrics)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background {
            ZStack {
                focusBackground
                if isPromoting {
                    PromotionBloom(tint: ideaAccent)
                }
            }
        }
        .filmGrain(opacity: 0.02)
    }

    private var workspaceActions: IdeaWorkspaceActions {
        IdeaWorkspaceActions(
            onShowLinkSwipes: { viewModel.showLinkSwipesOverlay = true },
            onOpenAtomInPane: { openAtomInPane($0) },
            onShowProfileEditor: { showProfileEditor = true },
            onBeginWriting: beginWriting,
            onClose: onClose
        )
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
        // The loader ladder runs here, not in the model's init — only the model
        // that actually got mounted should touch the database. Idempotent.
        viewModel.start()
        registerContextProvider()
        guard !hasArrived else { return }
        // One frame after mount so the cascade actually animates (views
        // mounted already-visible never animate their entrance).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            hasArrived = true
        }
    }

    /// Presence, not ownership — see `CosmoEditableSurfaceRegistry.registerPresence`.
    /// Every open document registers so the assistant's scope switcher can list
    /// it; only one pane at a time may own the *window* context.
    private func registerContextProvider() {
        let provider = ownedContextProvider ?? IdeaContextProvider(atom: atom, viewModel: viewModel)
        ownedContextProvider = provider
        CosmoEditableSurfaceRegistry.shared.registerPresence(provider)
        guard !isPaneContext || isPaneContextOwner else { return }
        CosmoWindowViewModel.shared.updateContext(provider: provider)
    }

    // MARK: - Chrome recede

    /// Marks the user as actively writing; the chrome islands recede until
    /// typing pauses (~1.4s) — the bench manner (they wake on hover).
    private func registerTypingActivity() {
        isActivelyTyping = true
        typingActivityTask?.cancel()
        typingActivityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            isActivelyTyping = false
        }
    }

    // MARK: - Keyboard

    private func handleEscape() -> KeyPress.Result {
        if viewModel.showMentionOverlay {
            viewModel.showMentionOverlay = false
            viewModel.mentionSearchText = ""
            return .handled
        }
        if viewModel.showLinkSwipesOverlay {
            viewModel.showLinkSwipesOverlay = false
            return .handled
        }
        if viewModel.showLinkConnectionsOverlay {
            viewModel.showLinkConnectionsOverlay = false
            return .handled
        }
        if workspace.isConversationOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.isConversationOverlayPresented = false
            }
            return .handled
        }
        if workspace.isInspectorOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.isInspectorOverlayPresented = false
            }
            return .handled
        }
        onClose()
        return .handled
    }

    private func handleKeyCommand(_ keyPress: KeyPress) -> KeyPress.Result {
        guard keyPress.modifiers.contains(.command) else { return .ignored }
        if keyPress.modifiers.contains(.option), keyPress.key == KeyEquivalent("i") {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleInspector()
            }
            return .handled
        }
        if keyPress.key == KeyEquivalent("0"), !keyPress.modifiers.contains(.shift), !keyPress.modifiers.contains(.option) {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleConversation()
            }
            return .handled
        }
        if keyPress.modifiers.contains(.shift) {
            if keyPress.key == KeyEquivalent("h") {
                focusedHookEditor = .draft
                return .handled
            }
            if keyPress.key == KeyEquivalent("l") {
                viewModel.showLinkSwipesOverlay = true
                return .handled
            }
            if keyPress.key == KeyEquivalent("t") {
                viewModel.showSchedulePopover = true
                return .handled
            }
        }
        return .ignored
    }

    // MARK: - Actions

    private func beginWriting() {
        let isBodyEmpty = viewModel.editableBody
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !isPromoting, !isBodyEmpty else { return }
        withAnimation(ProMotionSprings.gentle) { isPromoting = true }
        Task {
            await viewModel.promoteToContent()
            isPromoting = false
        }
    }

    private func openAtomInPane(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid, "asPane": true]
        )
    }

    // MARK: - Overlay Presentations

    @ViewBuilder
    private var overlayPresentations: some View {
        if viewModel.showLinkSwipesOverlay {
            LinkSwipesOverlay(
                viewModel: viewModel,
                isPresented: Bindable(viewModel).showLinkSwipesOverlay
            )
            .transition(.opacity)
            .zIndex(100)
        }

        if viewModel.showLinkConnectionsOverlay {
            LinkConnectionsOverlay(
                viewModel: viewModel,
                isPresented: Bindable(viewModel).showLinkConnectionsOverlay
            )
            .transition(.opacity)
            .zIndex(100)
        }
    }

    @ViewBuilder
    private var profileEditorOverlay: some View {
        if showProfileEditor {
            ZStack {
                FloatingOverlayBackdrop { showProfileEditor = false }
                CosmoSettingsView(
                    onClose: { showProfileEditor = false },
                    launchStudio: .create,
                    onProfileCreated: { newProfile in
                        Task { await viewModel.assignClient(newProfile) }
                        Task { await viewModel.loadClientProfiles() }
                    }
                )
                .settingsGlassPanel()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}

// MARK: - Manuscript Column

extension IdeaFocusModeView {
    /// The centered manuscript — head, angle, hooks, outline. Content is the
    /// hero: no card chrome, hairline dividers carry structure. Sections rise
    /// in once on arrival (the cascade), top to bottom.
    private var manuscriptColumn: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            titleHero
                .atelierStaggerIn(delay: 0.0, appeared: hasArrived, duration: 0.4)
            contextEditor
                .atelierStaggerIn(delay: 0.05, appeared: hasArrived, duration: 0.4)
            if !atom.attachmentUUIDs.isEmpty {
                capturedSection
                    .atelierStaggerIn(delay: 0.08, appeared: hasArrived, duration: 0.4)
            }
            hooksSection
                .atelierStaggerIn(delay: 0.1, appeared: hasArrived, duration: 0.4)
            outlineSection
                .atelierStaggerIn(delay: 0.14, appeared: hasArrived, duration: 0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(manuscriptWhitespaceBlurLayer)
        .opacity(isPromoting ? 0.85 : 1)
        .animation(ProMotionSprings.gentle, value: isPromoting)
    }

    /// The pages/photos the capture carried in when it was filed as this idea
    /// — the spark's visual seed. Click a page to open the original.
    private var capturedSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            sectionLabel("CAPTURED", count: atom.attachmentUUIDs.count)
            AttachmentRail(
                attachmentUUIDs: atom.attachmentUUIDs,
                thumbSize: CGSize(width: 64, height: 84)
            )
        }
    }

    private var manuscriptWhitespaceBlurLayer: some View {
        DS.bg.opacity(0.001)
            .contentShape(Rectangle())
            .onTapGesture {
                clearManuscriptEditingFocus()
            }
            .accessibilityHidden(true)
    }

    private func clearManuscriptEditingFocus() {
        isTitleFocused = false
        isContextFocused = false
        focusedHookEditor = nil
        focusedOutlineSlideID = nil
        FocusModeEditorBlur.clearFirstResponder()
    }

    /// The one section-header voice on this page: small caps, a live count
    /// that ticks (never re-layouts), and a hair-rule carrying the width.
    private func sectionLabel(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: DS.space12) {
            HStack(spacing: DS.space6) {
                Text(title)
                    .font(DS.smallCaps)
                    .tracking(1.4)
                    .foregroundStyle(focusTextMuted)
                    .fixedSize()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(focusTextMuted.opacity(0.75))
                        .contentTransition(.numericText())
                        .animation(ProMotionSprings.gentle, value: count)
                }
            }
            Divider().overlay(focusBorder.opacity(0.6))
        }
        .frame(height: 12)
    }

    // MARK: Title hero — the head

    private var titleHero: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ripeningControl

            TextField("Untitled idea", text: Bindable(viewModel).editableTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.displaySerif)
                .foregroundStyle(focusText)
                .tracking(-0.5)
                .lineLimit(1...3)
                .focused($isTitleFocused)
                .onChange(of: viewModel.editableTitle) { _, _ in
                    registerTypingActivity()
                    viewModel.scheduleAutoSave()
                }
                .accessibilityLabel("Idea title")

            identityRow
        }
    }

    /// The kicker is alive: five development ticks fill as the idea ripens
    /// (the IdeaCard's ticks, grown up), and the whole cluster is the status
    /// control — no dead "IDEA · SPARK" caption, no separate toolbar menu.
    private var ripeningControl: some View {
        Menu {
            ForEach(IdeaStatus.allCases, id: \.self) { status in
                Button {
                    Task { await viewModel.updateStatus(status) }
                } label: {
                    Label(status.displayName, systemImage: status.iconName)
                }
            }
        } label: {
            HStack(spacing: DS.space8) {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(tickFill(index))
                            .frame(width: 12, height: 3)
                    }
                }
                .accessibilityHidden(true)
                Text(viewModel.selectedStatus.displayName.uppercased())
                    .font(DS.smallCaps)
                    .tracking(1.4)
                    .foregroundStyle(isArchived ? focusTextMuted : ideaAccent.opacity(0.9))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .animation(ProMotionSprings.snappy, value: viewModel.selectedStatus)
        .help("Idea stage: \(viewModel.selectedStatus.displayName) — click to change")
        .accessibilityLabel("Idea stage: \(viewModel.selectedStatus.displayName)")
    }

    private var isArchived: Bool { viewModel.selectedStatus == .archived }

    private func tickFill(_ index: Int) -> Color {
        guard !isArchived else { return focusTextMuted.opacity(0.22) }
        return index <= min(viewModel.selectedStatus.sortOrder, 4)
            ? ideaAccent
            : focusTextMuted.opacity(0.22)
    }

    /// ONE quiet identity line, and it's the editing surface: date · format ·
    /// platform · client, each a borderless menu (the IdeaCard meta grammar).
    private var identityRow: some View {
        // Wraps rather than runs off the edge. Every item here is a
        // `.fixedSize()` menu — they hug their label so the menu doesn't
        // stretch, which also means none of them will truncate. Strung along
        // one HStack that made the line, and therefore the whole manuscript
        // column, incompressible below the sum of its labels: at pane widths
        // and in the narrow band where both bench columns are seated, the
        // sheet then demanded more width than it was given and got clipped.
        // Flowing them costs nothing at full width and always fits.
        CosmoFlowLayout(spacing: DS.space6) {
            Text(formattedCreatedDate)
                .foregroundStyle(focusTextMuted)
            identityItem { formatMenu }
            identityItem { platformMenu }
            identityItem { clientMenu }
            if let label = scheduledChipLabel {
                identityItem { scheduledChip(label) }
            }
        }
        .font(DS.caption)
    }

    /// The separator rides with the item it precedes, so a wrap never strands
    /// a lone dot at the head of a line.
    private func identityItem<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: DS.space6) {
            metaDot
            content()
        }
    }

    /// Quiet echo of the toolbar's schedule state: the next open development
    /// session's day, in the identity line's own voice. Click opens the
    /// schedule popover (anchored at the toolbar's calendar button).
    private var scheduledChipLabel: String? {
        let next = viewModel.scheduledTasks.first {
            $0.metadataValue(as: TaskMetadata.self)?.isCompleted != true
        }
        guard let next, let day = IdeaTaskLinkService.plannedDay(next) else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Scheduled · Today" }
        if calendar.isDateInTomorrow(day) { return "Scheduled · Tomorrow" }
        return "Scheduled · " + day.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func scheduledChip(_ label: String) -> some View {
        Button {
            viewModel.showSchedulePopover = true
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "calendar")
                    .font(DS.caption2)
                    .accessibilityHidden(true)
                Text(label)
            }
            .foregroundStyle(ideaAccent.opacity(0.9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("This idea has a scheduled development session — click to manage")
        .accessibilityLabel(label)
    }

    private var metaDot: some View {
        Text("·")
            .foregroundStyle(focusTextMuted.opacity(0.6))
            .accessibilityHidden(true)
    }

    private var formatMenu: some View {
        Menu {
            ForEach(formatMenuChoices, id: \.self) { format in
                Button {
                    viewModel.updateFormat(format)
                } label: {
                    Text("\(CollectionEmoji.formatMark(format))  \(format.displayName)")
                }
            }
            if viewModel.selectedFormat != nil {
                Divider()
                Button("Remove Format") {
                    viewModel.updateFormat(nil)
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                if let format = viewModel.selectedFormat {
                    Text(CollectionEmoji.formatMark(format))
                        .font(DS.caption)
                        .accessibilityHidden(true)
                    Text(format.displayName)
                        .foregroundStyle(focusTextMuted)
                } else {
                    Text("Add format")
                        .foregroundStyle(focusTextMuted.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Content format")
        .accessibilityLabel("Content format: \(viewModel.selectedFormat?.displayName ?? "none")")
    }

    /// Platform first narrows the format menu to what that platform carries.
    private var formatMenuChoices: [ContentFormat] {
        if let platform = viewModel.selectedPlatform {
            return platform.supportedFormats
        }
        return ContentFormat.allCases
    }

    private var platformMenu: some View {
        Menu {
            ForEach(IdeaPlatform.allCases, id: \.self) { platform in
                Button(platform.displayName) {
                    viewModel.selectedPlatform = platform
                    viewModel.scheduleAutoSave()
                }
            }
            if viewModel.selectedPlatform != nil {
                Divider()
                Button("Remove Platform") {
                    viewModel.selectedPlatform = nil
                    viewModel.scheduleAutoSave()
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                if let platform = viewModel.selectedPlatform {
                    SwipePlatformGlyph(source: platformGlyphFamily(platform))
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(platform.displayName)
                        .foregroundStyle(focusTextMuted)
                } else {
                    Text("Add platform")
                        .foregroundStyle(focusTextMuted.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Publishing platform")
        .accessibilityLabel("Platform: \(viewModel.selectedPlatform?.displayName ?? "none")")
    }

    /// "x" is stored bare; the glyph family answers to x_post.
    private func platformGlyphFamily(_ platform: IdeaPlatform) -> String {
        platform.rawValue == "x" ? "x_post" : platform.rawValue
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
                showProfileEditor = true
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
            HStack(spacing: DS.space4) {
                if let client = viewModel.linkedClient {
                    Circle()
                        .fill(DS.clientColor(for: client.uuid))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(client.title ?? "Client")
                        .foregroundStyle(focusTextMuted)
                } else {
                    Text("Add client")
                        .foregroundStyle(focusTextMuted.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Client profile")
        .accessibilityLabel("Client: \(viewModel.linkedClient?.title ?? "none")")
    }

    private var formattedCreatedDate: String {
        guard let date = ISO8601.date(from: viewModel.idea.createdAt) else {
            return "Undated"
        }
        return CosmoDateFormatters.monthDay.string(from: date)
    }

    // MARK: Context editor — chromeless manuscript

    private var contextEditor: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            contextMentionChips

            if let review = bodyReviewProposal {
                // Inline assistant review: the manuscript becomes the diff until
                // every change is accepted or rejected — same surface, same type.
                CosmoInlineDiffReviewView(
                    store: CosmoInlineAssistantStore.shared,
                    proposal: review,
                    sourceText: viewModel.editableBody,
                    bodyFont: .system(size: 17, weight: .regular, design: .serif),
                    textColor: focusText
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                contextEditingSurface
            }
        }
    }

    private var contextEditingSurface: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ZStack(alignment: .topLeading) {
                if viewModel.editableBody.isEmpty {
                    Text("What's the angle?")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(focusTextMuted)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }

                IdeaContextTextEditor(
                    text: Bindable(viewModel).editableBody,
                    isFocused: $isContextFocused
                ) { newValue in
                    registerTypingActivity()
                    viewModel.scheduleAutoSave()
                    viewModel.autoEnrich()
                    handleMentionTrigger(newValue)
                }
                .frame(maxWidth: .infinity, minHeight: IdeaContextTextView.minimumHeight, alignment: .topLeading)
                .accessibilityLabel("Idea context and direction")
            }
            .overlay(alignment: .leading) {
                // Focus rule — the only affordance. Slides in from -12 on focus.
                Rectangle()
                    .fill(ideaAccent)
                    .frame(width: 2)
                    .padding(.vertical, 6)
                    .opacity(isContextFocused ? 1 : 0)
                    .offset(x: isContextFocused ? -12 : -24)
                    .animation(ProMotionSprings.snappy, value: isContextFocused)
            }
            .overlay(alignment: .topLeading) { mentionOverlay }
        }
    }

    @ViewBuilder
    private var mentionOverlay: some View {
        if viewModel.showMentionOverlay {
            CosmoMentionOverlay(
                isVisible: Bindable(viewModel).showMentionOverlay,
                searchText: Bindable(viewModel).mentionSearchText,
                onSelect: { mentioned in
                    // Truncate the "@query" BEFORE addMention schedules
                    // the autosave, so the snapshot captures the final body.
                    if let atIndex = viewModel.editableBody.lastIndex(of: "@") {
                        viewModel.editableBody = String(viewModel.editableBody[viewModel.editableBody.startIndex..<atIndex])
                    }
                    viewModel.addMention(mentioned)
                },
                onDismiss: {
                    viewModel.showMentionOverlay = false
                    viewModel.mentionSearchText = ""
                }
            )
            .frame(width: 360)
            .frame(maxHeight: 340)
            .offset(y: 28)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .zIndex(10)
        }
    }

    private func handleMentionTrigger(_ newValue: String) {
        if newValue.hasSuffix("@") && !viewModel.showMentionOverlay {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.showMentionOverlay = true
                viewModel.mentionSearchText = ""
            }
        }
        if viewModel.showMentionOverlay {
            if let atIndex = newValue.lastIndex(of: "@") {
                let afterAt = String(newValue[newValue.index(after: atIndex)...])
                viewModel.mentionSearchText = afterAt
            }
        }
    }

    @ViewBuilder
    private var contextMentionChips: some View {
        if !viewModel.mentionedAtoms.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space6) {
                    ForEach(viewModel.mentionedAtoms, id: \.uuid) { mentioned in
                        contextMentionChip(mentioned)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func contextMentionChip(_ mentioned: Atom) -> some View {
        let entityType = EntityType(rawValue: mentioned.type.rawValue) ?? .idea
        let chipColor = CosmoMentionColors.color(for: entityType)
        return HStack(spacing: DS.space4) {
            Image(systemName: mentioned.type.iconName)
                .font(DS.caption2)
                .accessibilityHidden(true)
            Text(mentioned.title ?? "Untitled")
                .font(DS.caption)
                .lineLimit(1)
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.removeMention(mentioned)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.bold))
                    .foregroundStyle(chipColor.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove mention \(mentioned.title ?? "untitled")")
        }
        .foregroundStyle(chipColor.opacity(0.85))
        .padding(.horizontal, DS.space6)
        .padding(.vertical, 2)
        .background(chipColor.opacity(0.08), in: Capsule())
    }
}

// MARK: - Hooks Section (the lab)

extension IdeaFocusModeView {
    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            sectionLabel("HOOKS", count: viewModel.editableHooks.count)

            VStack(alignment: .leading, spacing: DS.space10) {
                ForEach(Array(viewModel.editableHooks.enumerated()), id: \.offset) { index, hook in
                    hookRow(hook, at: index)
                }
                addHookRow
            }
            .padding(.horizontal, DS.space4)
        }
    }

    private func hookRow(_ hook: String, at index: Int) -> some View {
        let isChosen = viewModel.selectedHookIndex == index
        let isHovered = hoveredHookIndex == index
        return HStack(alignment: .top, spacing: DS.space12) {
            Text(romanNumeral(for: index + 1) + ".")
                .font(DS.caption.monospacedDigit().weight(isChosen ? .semibold : .regular))
                .foregroundStyle(isChosen ? ideaAccent : focusTextMuted)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 3)
                .accessibilityHidden(true)

            HookLineEditor(
                text: hookBinding(at: index),
                editorID: .existing(index),
                focusedEditor: $focusedHookEditor,
                placeholder: "hook",
                font: hookEditorFont(),
                textColor: NSColor(focusText),
                placeholderColor: NSColor(focusTextMuted.opacity(0.55)),
                onReturn: finishHookEditing,
                onDeleteEmpty: {
                    guard viewModel.editableHooks.indices.contains(index) else { return false }
                    removeHook(at: index)
                    return true
                },
                onMoveLine: { direction in moveHook(at: index, direction) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DS.space8)

            HStack(spacing: DS.space2) {
                hookStarButton(at: index, isChosen: isChosen, isHovered: isHovered)

                Button {
                    removeHook(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.caption2.weight(.medium))
                        .foregroundStyle(focusTextMuted.opacity(0.5))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .marginaliaHoverReveal(isHovered)
                .help("Remove hook")
                .accessibilityLabel("Remove hook")
            }
            .padding(.top, 2)
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                if hovering {
                    hoveredHookIndex = index
                } else if hoveredHookIndex == index {
                    hoveredHookIndex = nil
                }
            }
        }
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// The verdict affordance: exactly one hook can be "on" — the working
    /// hook, carried forward as the piece's title at promotion.
    private func hookStarButton(at index: Int, isChosen: Bool, isHovered: Bool) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.selectedHookIndex = isChosen ? nil : index
                viewModel.scheduleAutoSave()
            }
        } label: {
            Image(systemName: isChosen ? "star.fill" : "star")
                .font(DS.caption2.weight(.medium))
                .foregroundStyle(isChosen ? ideaAccent : focusTextMuted.opacity(0.6))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marginaliaHoverReveal(isChosen || isHovered)
        .help(isChosen ? "The working hook — leads the piece into writing" : "Mark as the working hook")
        .accessibilityLabel(isChosen ? "Working hook" : "Mark as working hook")
    }

    // MARK: Hook mutations

    private var addHookRow: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            Text("+")
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(focusTextMuted)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 3)
                .accessibilityHidden(true)

            HookLineEditor(
                text: $newHookText,
                editorID: .draft,
                focusedEditor: $focusedHookEditor,
                placeholder: "Add a hook to test the angle (⌘⇧H)",
                font: hookEditorFont(italic: true),
                textColor: NSColor(focusTextSecondary),
                placeholderColor: NSColor(focusTextMuted.opacity(0.65)),
                onReturn: addHook,
                onDeleteEmpty: { false }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("New hook text")
        }
        .padding(.top, DS.space4)
        .onChange(of: newHookText) { _, _ in registerTypingActivity() }
    }

    private func hookBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.editableHooks.indices.contains(index) else { return "" }
                return viewModel.editableHooks[index]
            },
            set: { newValue in
                guard viewModel.editableHooks.indices.contains(index) else { return }
                viewModel.editableHooks[index] = newValue
                registerTypingActivity()
                viewModel.scheduleAutoSave()
            }
        )
    }

    private func removeHook(at index: Int) {
        guard viewModel.editableHooks.indices.contains(index) else { return }
        withAnimation(ProMotionSprings.snappy) {
            focusedHookEditor = nil
            viewModel.editableHooks.remove(at: index)
            // The star rides its hook: clear it if its hook left, shift it if
            // an earlier row left.
            if let chosen = viewModel.selectedHookIndex {
                if chosen == index {
                    viewModel.selectedHookIndex = nil
                } else if chosen > index {
                    viewModel.selectedHookIndex = chosen - 1
                }
            }
            viewModel.scheduleAutoSave()
        }
    }

    /// ⌥↑ / ⌥↓ while a hook is focused — the numerals renumber with a spring
    /// and the working-hook star rides its line.
    private func moveHook(at index: Int, _ direction: OutlineSlideNavigationDirection) {
        let target = direction == .previous ? index - 1 : index + 1
        guard viewModel.editableHooks.indices.contains(index),
              viewModel.editableHooks.indices.contains(target) else { return }
        withAnimation(ProMotionSprings.snappy) {
            viewModel.editableHooks.swapAt(index, target)
            if let chosen = viewModel.selectedHookIndex {
                if chosen == index {
                    viewModel.selectedHookIndex = target
                } else if chosen == target {
                    viewModel.selectedHookIndex = index
                }
            }
            viewModel.scheduleAutoSave()
        }
        focusedHookEditor = .existing(target)
    }

    private func hookEditorFont(italic: Bool = false) -> NSFont {
        let font = NSFont.systemFont(ofSize: 15)
        guard italic else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private func finishHookEditing() {
        focusedHookEditor = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func romanNumeral(for value: Int) -> String {
        let numerals: [(Int, String)] = [
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
        ]
        var result = ""
        var n = value
        for (val, letters) in numerals {
            while n >= val {
                result += letters
                n -= val
            }
        }
        return result.isEmpty ? "\(value)" : result
    }

    private func addHook() {
        let trimmed = newHookText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
            viewModel.editableHooks.append(trimmed)
            newHookText = ""
            focusedHookEditor = nil
            viewModel.scheduleAutoSave()
        }
    }
}

// MARK: - Outline Section (simple mode only)

extension IdeaFocusModeView {
    @ViewBuilder
    private var outlineSection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            outlineHeader

            if let outline = viewModel.codexOutline {
                outlineSlides(outline)
            }
        }
        .onAppear {
            if viewModel.codexOutline == nil {
                viewModel.replaceCodexOutline(CodexOutlineModel(arcShape: nil, slides: [
                    CodexOutlineSlide(id: UUID(), position: 1, speechAct: nil,
                        readerDeltas: [], frame: nil, distance: nil,
                        techniques: [], transition: nil, note: nil)
                ]))
            }
        }
    }

    private var outlineHeader: some View {
        HStack(spacing: DS.space12) {
            sectionLabel("OUTLINE", count: viewModel.codexOutline?.slides.count)

            Button { addNewSlide() } label: {
                Label("Slide", systemImage: "plus")
                    .font(DS.caption)
                    .foregroundStyle(focusTextSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Add a slide")
            .accessibilityLabel("Add slide")
        }
    }

    private func outlineSlides(_ outline: CodexOutlineModel) -> some View {
        VStack(alignment: .leading, spacing: IdeaOutlineLayoutMetrics.normalRowSpacing) {
            ForEach(outline.slides) { slide in
                outlineSlideRow(slide)
            }
        }
        .padding(.horizontal, DS.space4)
    }

    private func outlineSlideRow(_ slide: CodexOutlineSlide) -> some View {
        let isHovered = hoveredSlideID == slide.id
        return HStack(alignment: .top, spacing: DS.space16) {
            Text(romanNumeral(for: slide.position))
                .font(DS.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(focusTextMuted)
                .frame(width: 36, height: IdeaOutlineLayoutMetrics.minimumEditorHeight, alignment: .topLeading)
                .contentTransition(.numericText())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space2) {
                // The framework's beat, when the outline knows it — the slide
                // teaches what it should do before a word is written.
                if let beat = slide.speechAct, !beat.isEmpty {
                    Text(beat.uppercased())
                        .font(DS.smallCaps)
                        .tracking(1.2)
                        .foregroundStyle(DS.giltMuted)
                        .help("This slide's beat in the framework")
                }

                OutlineSlideNoteEditor(
                    text: slideNoteBinding(for: slide.id),
                    slideID: slide.id,
                    focusedSlideID: $focusedOutlineSlideID,
                    placeholder: "what should this slide do?",
                    onReturn: { insertSlideAfterFocusedSlide(slide.id) },
                    onMoveFocus: { direction in
                        focusAdjacentOutlineSlide(from: slide.id, direction: direction)
                    },
                    onDeleteEmpty: { handleDeleteOnSlide(slide.id) == .handled },
                    onMoveLine: { direction in moveSlide(slide.id, direction) }
                )
                // Focus-paired ink is baked at makeNSView only — remake on
                // theme swap so outline notes don't keep the old palette.
                .recreateOnThemeChange()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button { removeSlide(slide.id) } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(focusTextMuted.opacity(0.4))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .marginaliaHoverReveal(isHovered)
            .help("Remove slide")
            .accessibilityLabel("Remove slide \(slide.position)")
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                if hovering {
                    hoveredSlideID = slide.id
                } else if hoveredSlideID == slide.id {
                    hoveredSlideID = nil
                }
            }
        }
    }

    private func slideNoteBinding(for slideId: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.codexOutline?.slides.first(where: { $0.id == slideId })?.note ?? ""
            },
            set: { newValue in
                registerTypingActivity()
                viewModel.updateOutlineSlideNote(slideId: slideId, note: newValue)
            }
        )
    }

    // MARK: Outline Mutations

    /// Apply a structural outline change and register it with CosmoUndoManager
    /// so ⌘Z restores the previous outline (deleted slides come back with
    /// their notes). Weak capture: undo silently no-ops once the focus
    /// session is gone.
    private func applyOutlineChange(_ actionDescription: String, _ newOutline: CodexOutlineModel) {
        let previousOutline = viewModel.codexOutline
        withAnimation(ProMotionSprings.snappy) {
            viewModel.replaceCodexOutline(newOutline)
        }
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: actionDescription,
            undo: { [weak viewModel] in
                withAnimation(ProMotionSprings.snappy) {
                    viewModel?.replaceCodexOutline(previousOutline)
                }
            },
            redo: { [weak viewModel] in
                withAnimation(ProMotionSprings.snappy) {
                    viewModel?.replaceCodexOutline(newOutline)
                }
            }
        ))
    }

    private func addNewSlide() {
        guard var outline = viewModel.codexOutline else { return }
        _ = CodexOutlineEditing.insertSlide(after: outline.slides.last?.id ?? UUID(), in: &outline)
        applyOutlineChange("Add Slide", outline)
    }

    private func removeSlide(_ id: UUID) {
        guard var outline = viewModel.codexOutline else { return }
        outline.slides.removeAll { $0.id == id }
        CodexOutlineEditing.renumberSlides(in: &outline)
        applyOutlineChange("Remove Slide", outline)
    }

    /// ⌥↑ / ⌥↓ while a slide is focused — reorder without leaving the keys.
    private func moveSlide(_ slideID: UUID, _ direction: OutlineSlideNavigationDirection) {
        guard var outline = viewModel.codexOutline else { return }
        let offset = direction == .previous ? -1 : 1
        guard CodexOutlineEditing.moveSlide(slideID, offset: offset, in: &outline) else { return }
        applyOutlineChange("Move Slide", outline)
        focusOutlineSlide(slideID)
    }

    private func insertSlideAfterFocusedSlide(_ slideID: UUID) {
        guard var outline = viewModel.codexOutline else { return }
        let newID = CodexOutlineEditing.insertSlide(after: slideID, in: &outline)
        applyOutlineChange("Add Slide", outline)
        focusOutlineSlide(newID)
    }

    private func handleDeleteOnSlide(_ slideID: UUID) -> KeyPress.Result {
        guard var outline = viewModel.codexOutline,
              let previousID = CodexOutlineEditing.removeSlideIfEmpty(slideID, in: &outline) else {
            return .ignored
        }

        applyOutlineChange("Remove Slide", outline)
        focusOutlineSlide(previousID)
        return .handled
    }

    private func focusOutlineSlide(_ slideID: UUID) {
        DispatchQueue.main.async {
            focusedOutlineSlideID = nil
            focusedOutlineSlideID = slideID
            OutlineSlideFocusRegistry.shared.requestFocus(slideID)
        }
    }

    private func focusAdjacentOutlineSlide(from slideID: UUID, direction: OutlineSlideNavigationDirection) {
        guard let slides = viewModel.codexOutline?.slides,
              let currentIndex = slides.firstIndex(where: { $0.id == slideID }) else { return }

        let targetIndex: Int
        switch direction {
        case .previous:
            targetIndex = currentIndex - 1
        case .next:
            targetIndex = currentIndex + 1
        }

        guard slides.indices.contains(targetIndex) else { return }
        focusOutlineSlide(slides[targetIndex].id)
    }
}

// MARK: - Promotion bloom (the one earned delight)

/// A warm radial bloom that rises behind the manuscript while Begin Writing
/// carries the idea into Content focus — the room warming up for the handoff.
/// Reduce Motion keeps the crossfade and drops the swell.
private struct PromotionBloom: View {
    let tint: Color

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RadialGradient(
            colors: [tint.opacity(0.12), Color.clear],
            center: .center,
            startRadius: 80,
            endRadius: 640
        )
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(ProMotionSprings.gentle) { appeared = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Idea Focus Mode") {
    IdeaFocusModeView(
        atom: Atom.new(
            type: .idea,
            title: "The Paradox of Productivity",
            body: "Most people optimize for output when they should be optimizing for clarity. The real bottleneck is not time -- it is attention quality."
        ),
        onClose: {}
    )
    .frame(width: 1280, height: 800)
}
#endif

// MARK: - Cosmo Context Provider

@MainActor
class IdeaContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    private let atom: Atom
    private weak var viewModel: IdeaFocusModeViewModel?

    init(atom: Atom, viewModel: IdeaFocusModeViewModel) {
        self.atom = atom
        self.viewModel = viewModel
    }

    var contextType: CosmoContextType { .ideaFocusMode }

    var surfaceID: String {
        "idea:\(atom.uuid)"
    }

    static func targetID(for atomUUID: String) -> String {
        "idea:\(atomUUID):body"
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let body = viewModel?.editableBody ?? atom.body ?? ""
        let hooks = viewModel?.editableHooks ?? []

        // Hooks ride along as anchors so the model can target them with
        // structuredFieldReplacement (anchorID "hook-N") without the hook text
        // living inside the body — body diffs stay locate-exact.
        var anchors: [CosmoEditableAnchor] = [
            .init(id: "body", label: "Idea context", utf16Start: 0, utf16Length: body.utf16.count)
        ]
        for (index, hook) in hooks.enumerated() {
            anchors.append(.init(id: "hook-\(index)", label: hook, utf16Start: 0, utf16Length: 0))
        }

        let title = (viewModel?.editableTitle ?? atom.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: Self.targetID(for: atom.uuid),
            kind: .text,
            title: title.isEmpty ? "Untitled idea" : title,
            text: body,
            sourceHash: CosmoEditableSurfaceHasher.hash(body),
            anchors: anchors
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard let viewModel else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Idea editor is unavailable"
            )
        }
        guard operation.targetID == Self.targetID(for: atom.uuid) else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Target changed"
            )
        }
        return try await viewModel.applyInlineAssistantEdit(operation)
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }

    var contextSummary: String {
        let status = viewModel?.selectedStatus.rawValue ?? "spark"
        return "Idea: \(atom.title ?? "Untitled") — \(status)"
    }

    var contextData: CosmoContextData {
        var viewData: [String: String] = [:]

        if let vm = viewModel {
            viewData["status"] = vm.selectedStatus.rawValue
            if let format = vm.selectedFormat {
                viewData["format"] = format.rawValue
            }
            if let platform = vm.selectedPlatform {
                viewData["platform"] = platform.rawValue
            }
            if !vm.editableBody.isEmpty {
                viewData["bodyPreview"] = String(vm.editableBody.prefix(500))
            }
            if let insight = vm.insight,
               let swipes = insight.matchingSwipes, !swipes.isEmpty {
                viewData["matchedSwipes"] = "\(swipes.count)"
            }
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "idea",
            currentAtomTitle: atom.title,
            viewSpecificData: viewData
        )
    }

    var availableActions: [CosmoWindowAction] {
        guard let viewModel else { return [] }

        return [
            CosmoWindowAction(
                id: "idea-append-body",
                name: "Insert into Body",
                description: "Append text to the current idea body.",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing inserted." }
                await MainActor.run {
                    if viewModel.editableBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.editableBody = trimmed
                    } else {
                        viewModel.editableBody += "\n\n" + trimmed
                    }
                }
                await viewModel.save()
                return "Inserted into the idea body."
            },
            CosmoWindowAction(
                id: "idea-add-hook",
                name: "Add Hook",
                description: "Add a hook line without overwriting existing hooks.",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing added." }
                await MainActor.run {
                    viewModel.editableHooks.append(trimmed)
                }
                await viewModel.save()
                return "Added a hook."
            }
        ]
    }
}
