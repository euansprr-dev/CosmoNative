// CosmoOS/UI/Inbox/InboxView.swift
// The triage queue. One calm ledger of explicit captures, a hero capture
// field, and a floating glass inspector — clearable end-to-end from the
// keyboard. Command Center masthead grammar, Connection workspace inspector
// dialect.
// June 2026 rebuild (INBOX_REVAMP_PLAN.md §3)

import SwiftUI

struct InboxView: View {
    @State private var viewModel: InboxViewModel
    @Binding private var route: SidebarInboxRoute

    init(viewModel: InboxViewModel, route: Binding<SidebarInboxRoute> = .constant(.global)) {
        _viewModel = State(initialValue: viewModel)
        _route = route
    }

    /// The page's width — the toast hangs off the ledger column's leading
    /// rail, which moves when the composed group centers on wide windows.
    @State private var pageWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            mainContent
            batchBarOverlay
            undoToastOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .sheet(isPresented: $viewModel.showOverrideSheet) { overrideSheet }
        .modifier(InboxKeyboardModel(viewModel: viewModel))
        .onAppear {
            viewModel.startIfNeeded()
            viewModel.isInboxVisible = true
        }
        .onDisappear { viewModel.isInboxVisible = false }
        // A verb's "Open" follow-up (moved to a lane → that lane's ledger).
        .onChange(of: viewModel.pendingRoute) { _, next in
            guard let next else { return }
            withAnimation(ProMotionSprings.snappy) { route = next }
            viewModel.pendingRoute = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: SpaceCompositionService.didFailUndo)) { notification in
            if let message = notification.userInfo?["message"] as? String { viewModel.presentLaneToast(message, isError: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inbox.focusCaptureField)) { _ in
            route = .global
            viewModel.requestCaptureFieldFocus()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch route {
        case .global:
            queuePage
        case .captureLanes:
            VStack(spacing: 0) {
                masthead(rail: DS.pageTitleRail)
                CaptureLanesView(showsLaneSidebar: false, triageModel: viewModel)
            }
        case .captureLane(let id):
            VStack(spacing: 0) {
                masthead(rail: DS.pageTitleRail)
                CaptureLanesView(showsLaneSidebar: false, selectedDestinationId: id, triageModel: viewModel)
            }
        case .manageCommands:
            VStack(spacing: 0) {
                masthead(rail: DS.pageTitleRail)
                CaptureLanesView(showsLaneSidebar: false, showsCommandRegistryOnly: true, triageModel: viewModel)
            }
        }
    }

    private var queuePage: some View {
        // ONE composed group — masthead, capture, queue, and the inspector's
        // seat — capped at Today's ledger measure and CENTERED in the page,
        // exactly as the Command Center composes its own group. Below the cap
        // the group is the page (identical rails to Today at every common
        // window width); above it the margins balance instead of pooling on
        // the trailing side, which is what read as "the inbox sits left".
        GeometryReader { geometry in
            let seated = geometry.size.width >= Self.inspectorSeatMinimumWidth
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    masthead(rail: DS.space12)
                    HStack(alignment: .top, spacing: DS.space24) {
                        VStack(spacing: 0) {
                            captureHero
                            queueOrEmptyState
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // The inspector is a COLUMN beside the queue (Today's
                        // timeline seat), not a panel floating over the rows
                        // it describes. Narrow panes collapse it back to the
                        // floating overlay — the LAW: collapse, never shrink
                        // the two columns into each other.
                        if seated, viewModel.isInspectorOpen, let item = viewModel.focusedItem {
                            InboxInspector(item: item, viewModel: viewModel)
                                .padding(.bottom, DS.space16)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: Self.ledgerGroupWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.pageTitleRail - DS.space12)

                if !seated { inspectorOverlay }
            }
        }
    }

    /// Today's composed group caps at 1500 — the same measure here, so the
    /// two ledger pages share rails at every width (derived, not invented).
    static let ledgerGroupWidth: CGFloat = 1500

    /// Below this page width the 390pt inspector would squeeze the queue
    /// under a readable measure, so it floats instead of seating.
    static let inspectorSeatMinimumWidth: CGFloat = 1040

    /// Where the queue's leading rail sits for the current width — the
    /// group's centred offset plus the title rail — so the toast hangs off
    /// the same line the rows and title do.
    private var ledgerLeadingRail: CGFloat {
        guard route == .global else { return DS.pageTitleRail }
        let gutter = DS.pageTitleRail - DS.space12
        let overflow = max(0, pageWidth - gutter * 2 - Self.ledgerGroupWidth)
        return DS.pageTitleRail + overflow / 2
    }

    // MARK: - Masthead (Command Center grammar)

    /// `rail` is the title's leading inset. The queue page passes
    /// `DS.space12` because its ledger column already carries the outer
    /// gutters (rail composition mirrors the Command Center masthead);
    /// flat lane pages pass `DS.pageTitleRail` whole.
    private func masthead(rail: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inbox")
                    .font(DS.pageTitle)
                    .foregroundStyle(DS.text)

                Spacer()

                historyMenu
                lanesButton
            }

            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
                .padding(.top, DS.space4)
        }
        // Same breathing room as the Command Center masthead — the shared
        // clearance keeps the title below the floating back/forward trail
        // chrome and the sidebar toggle at the window's top-left.
        .padding(.horizontal, rail)
        .padding(.top, DS.navChromeClearance)
        .padding(.bottom, DS.space10)
    }

    /// Recently triaged captures — reachable even when the queue is non-empty,
    /// so a mistaken dismiss is always recoverable.
    private var historyMenu: some View {
        Menu {
            if viewModel.recentHistoryEntries.isEmpty {
                Text("Nothing triaged recently")
            } else {
                ForEach(viewModel.recentHistoryEntries) { entry in
                    historyMenuRow(entry)
                }
            }
        } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space6)
                .background(DS.glassSectionFill, in: .capsule)
                .overlay(Capsule().strokeBorder(DS.borderSubtle, lineWidth: 0.5))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Recently placed captures, dismissed captures, and deleted lanes")
    }

    @ViewBuilder
    private func historyMenuRow(_ entry: InboxHistoryEntry) -> some View {
        switch entry.kind {
        case .capture(let item):
            if item.status == .dismissed {
                Button {
                    Task { await viewModel.restoreFromHistory(item) }
                } label: {
                    Label("Restore “\(entry.title)”", systemImage: "arrow.uturn.backward")
                }
            } else {
                Text(entry.title)
                Text(entry.subtitle)
                if let receipt = item.placementReceipt, !receipt.isUndone {
                    Button("Open saved item") {
                        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.openAtomFromCommandK, object: nil,
                            userInfo: ["atomUUID": receipt.resultAtomUUID])
                    }
                    Button("Undo filing") { Task { await viewModel.undoFilingFromHistory(item) } }
                }
            }
        case .deletedLane(let lane):
            Button {
                Task { await viewModel.restoreDeletedLane(lane) }
            } label: {
                Label("Restore Lane “\(entry.title)”", systemImage: "arrow.uturn.backward")
            }
            Text(entry.subtitle)
        }
    }

    private var lanesButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                route = route == .global ? .captureLanes : .global
            }
        } label: {
            Label(route == .global ? "Lanes" : "Queue", systemImage: route == .global ? "tray.2" : "tray")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space6)
                .background(DS.glassSectionFill, in: .capsule)
                .overlay(Capsule().strokeBorder(DS.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(route == .global ? "Capture lanes" : "Back to the queue")
    }

    // MARK: - Capture hero

    private var captureHero: some View {
        InboxCaptureBar(viewModel: viewModel)
            // On the title rail within the ledger column, like Today's
            // brief card on its content rail.
            .padding(.horizontal, DS.space12)
            .padding(.top, DS.space6)
            .padding(.bottom, DS.space10)
    }

    // MARK: - Queue

    @ViewBuilder
    private var queueOrEmptyState: some View {
        if viewModel.items.isEmpty {
            InboxEmptyState(viewModel: viewModel)
        } else {
            queueList
        }
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.groupedItems) { section in
                    Section {
                        sectionRows(section)
                    } header: {
                        InboxSectionHeader(title: section.title, itemCount: section.items.count)
                    }
                }
            }
            // Rows run to the ledger column's edges, outdenting the title
            // by the space12 rail — the same title-to-content rhythm as
            // the Today page's task list against its masthead.
            .padding(.bottom, viewModel.isMultiSelectActive ? 88 : DS.space24)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .animation(ProMotionSprings.gentle, value: viewModel.groupedItemsIdentity)
    }

    private func sectionRows(_ section: InboxSection) -> some View {
        ForEach(Array(section.items.enumerated()), id: \.element.uuid) { index, item in
            InboxQueueRow(
                item: item,
                isFocused: viewModel.focusedItemId == item.uuid,
                isSelected: viewModel.selectedItemIds.contains(item.uuid),
                isProcessing: viewModel.processingItemIds.contains(item.uuid),
                onOpen: { viewModel.focusItem(item) },
                onAccept: { Task { await viewModel.acceptSuggestion(for: item) } },
                onDismiss: { Task { await viewModel.dismiss(item: item) } },
                onToggleSelect: { viewModel.toggleSelection(for: item) },
                lanes: viewModel.lanes,
                inquirySpaces: viewModel.inquirySpaces,
                seedlings: viewModel.seedlings,
                onMoveToLane: { lane in Task { await viewModel.moveToLane(item, lane: lane) } },
                onStartInquiry: { space in
                    if let space {
                        Task { await viewModel.startInquiry(item, in: .existing(space)) }
                    } else {
                        // "New Space…" names the Space in the destination sheet.
                        viewModel.showOverride(for: item, focus: .inquiry)
                    }
                },
                onGrowSeedling: { seedling in
                    if let seedling {
                        Task { await viewModel.growSeedling(item, seedling: seedling) }
                    } else {
                        viewModel.showOverride(for: item, focus: .concepts)
                    }
                },
                onSaveAsResearch: { viewModel.showOverride(for: item, focus: .research) },
                onChooseDestination: { viewModel.showOverride(for: item) }
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.97))
            ))
            .animation(ProMotionSprings.staggered(index: min(index, 8)), value: item.uuid)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorOverlay: some View {
        if viewModel.isInspectorOpen, let item = viewModel.focusedItem {
            InboxInspector(item: item, viewModel: viewModel)
                .padding(.trailing, DS.space16)
                .padding(.top, 96)
                .padding(.bottom, DS.space16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    // MARK: - Batch bar & undo toast

    @ViewBuilder
    private var batchBarOverlay: some View {
        if viewModel.isMultiSelectActive {
            InboxBatchBar(viewModel: viewModel)
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(ProMotionSprings.snappy, value: viewModel.isMultiSelectActive)
        }
    }

    @ViewBuilder
    private var undoToastOverlay: some View {
        if viewModel.showUndoToast {
            // Bottom-LEADING, hanging off the ledger's own rail. The
            // companion owns the bottom-trailing corner on every page
            // (CompanionDockMetrics) and sat on top of the toast there; the
            // bottom-centre lane belongs to the batch bar. The leading rail
            // is the one place nothing else lives — and it keeps the receipt
            // beside the rows it reports on, the Gmail undo grammar.
            InboxUndoToast(viewModel: viewModel)
                .padding(.leading, ledgerLeadingRail)
                .padding(.bottom, viewModel.isMultiSelectActive ? 92 : DS.space20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Override sheet

    @ViewBuilder
    private var overrideSheet: some View {
        if let item = viewModel.overrideItem {
            InboxOverrideSheet(item: item, viewModel: viewModel)
        }
    }
}

// MARK: - Keyboard model

/// The whole queue is clearable without the mouse:
/// ↑↓ move · ⏎ accept · ⌘⏎ place & go · ⌫ dismiss · space quick-look ·
/// T task · A ask · I idea · C connect · esc close/deselect · ⌘A select all.
private struct InboxKeyboardModel: ViewModifier {
    let viewModel: InboxViewModel

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow) {
                guard !viewModel.isCaptureFieldFocused else { return .ignored }
                viewModel.moveFocusUp()
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard !viewModel.isCaptureFieldFocused else { return .ignored }
                viewModel.moveFocusDown()
                return .handled
            }
            .onKeyPress(.return) {
                guard !viewModel.isCaptureFieldFocused, viewModel.focusedItem != nil else { return .ignored }
                Task { await viewModel.acceptFocused() }
                return .handled
            }
            .onKeyPress(.delete) {
                guard !viewModel.isCaptureFieldFocused, viewModel.focusedItem != nil else { return .ignored }
                Task { await viewModel.dismissFocused() }
                return .handled
            }
            .onKeyPress(.space) {
                guard !viewModel.isCaptureFieldFocused, viewModel.focusedItem != nil else { return .ignored }
                viewModel.toggleInspectorForFocused()
                return .handled
            }
            .onKeyPress(.escape) {
                if viewModel.isInspectorOpen {
                    viewModel.closeInspector()
                } else {
                    viewModel.deselectAll()
                }
                return .handled
            }
            .onKeyPress(KeyEquivalent("t")) { runVerb { await viewModel.makeTask($0) } }
            .onKeyPress(KeyEquivalent("a")) { runVerb { await viewModel.askInDeepDive($0) } }
            .onKeyPress(KeyEquivalent("i")) { runVerb { await viewModel.fileAsIdea($0) } }
            .onKeyPress(KeyEquivalent("c")) { runVerb { await viewModel.connectCapture($0) } }
            .onKeyPress(KeyEquivalent("g")) { runVerb { await viewModel.growSeedling($0) } }
            .background {
                Button("") { viewModel.selectAll() }
                    .keyboardShortcut("a", modifiers: .command)
                    .hidden()
                Button("") {
                    if let item = viewModel.focusedItem {
                        Task { await viewModel.placeAndGo(item) }
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .hidden()
            }
    }

    private func runVerb(_ verb: @escaping (InboxItem) async -> Void) -> KeyPress.Result {
        guard !viewModel.isCaptureFieldFocused, let item = viewModel.focusedItem else { return .ignored }
        Task { await verb(item) }
        viewModel.moveFocusDown()
        return .handled
    }
}

// MARK: - Undo toast

private struct InboxUndoToast: View {
    @Bindable var viewModel: InboxViewModel

    var body: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: viewModel.undoToastIsError ? "exclamationmark.triangle.fill" : "arrow.uturn.backward.circle.fill")
                .font(DS.callout)
                .foregroundStyle(viewModel.undoToastIsError ? DS.red : DS.accent)
                .accessibilityHidden(true)

            Text(viewModel.undoToastMessage)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer(minLength: DS.space8)

            // The follow-up choice ("Develop now" after a grow) — doing
            // nothing is "later"; the toast just fades.
            if let actionLabel = viewModel.undoToastActionLabel, !viewModel.undoToastIsError {
                Button {
                    viewModel.runUndoToastAction()
                } label: {
                    Text(actionLabel)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, DS.space10)
                        .padding(.vertical, DS.space4 + 1)
                        .background(DS.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                .help(actionLabel == "Open" ? "Open the filed item" : "Open the development conversation")
            }

            if !viewModel.undoToastIsError {
                Button("Undo") {
                    Task { await viewModel.undoLastInboxAction() }
                }
                .font(DS.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
                .keyboardShortcut("z", modifiers: .command)
            }

            Button {
                viewModel.dismissUndoToast()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Empty state

private struct InboxEmptyState: View {
    let viewModel: InboxViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: DS.space24) {
                Spacer(minLength: DS.space48)

                if viewModel.triagedThisWeek > 0 {
                    inboxZero
                } else {
                    firstRun
                }

                recentActivitySection

                Spacer(minLength: DS.space32)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space40)
        }
    }

    private var inboxZero: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "tray")
                .font(DS.displaySerif)
                .foregroundStyle(DS.gilt)
                .accessibilityHidden(true)

            Text("Inbox zero")
                .font(DS.title2)
                .foregroundStyle(DS.text)

            Text("\(viewModel.triagedThisWeek) capture\(viewModel.triagedThisWeek == 1 ? "" : "s") placed this week.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .contentTransition(.numericText())
        }
    }

    private var firstRun: some View {
        VStack(spacing: DS.space16) {
            VStack(spacing: DS.space8) {
                Image(systemName: "tray")
                    .font(DS.displaySerif)
                    .foregroundStyle(DS.textMuted.opacity(0.5))
                    .accessibilityHidden(true)

                Text("Captures land here")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)

                Text("Send anything to your Telegram bot, prefix a message with “inbox:”, or type in the field above — then place each thought with a single keystroke.")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
    }

    @ViewBuilder
    private var recentActivitySection: some View {
        if !viewModel.recentHistory.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Recently placed")
                    .dsSmallCapsLabel()

                ForEach(viewModel.recentHistory) { item in
                    historyRow(item)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    private func historyRow(_ item: InboxItem) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: item.status == .actioned ? "checkmark.circle.fill" : "xmark.circle")
                .font(DS.caption)
                .foregroundStyle(item.status == .actioned ? DS.accent : DS.textMuted)
                .accessibilityHidden(true)

            Text(item.title ?? String(item.rawText.prefix(40)))
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)

            Spacer()

            if item.status == .actioned, let destination = item.destinationPath ?? item.placeThinkspaceName {
                Text(destination)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            } else if item.status == .dismissed {
                Button("Restore") {
                    Task { await viewModel.restoreFromHistory(item) }
                }
                .font(DS.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
                .help("Put this capture back in the queue")
                .accessibilityLabel("Restore dismissed capture")
            }
        }
    }
}
