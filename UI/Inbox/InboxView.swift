// CosmoOS/UI/Inbox/InboxView.swift
// The triage queue. One calm ledger of explicit captures, a hero capture
// field, and a floating glass inspector — clearable end-to-end from the
// keyboard. Command Center masthead grammar, Connection workspace inspector
// dialect.
// June 2026 rebuild (INBOX_REVAMP_PLAN.md §3)

import SwiftUI

struct InboxView: View {
    @State private var viewModel = InboxViewModel()
    @Binding private var route: SidebarInboxRoute

    init(route: Binding<SidebarInboxRoute> = .constant(.global)) {
        _route = route
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent
            batchBarOverlay
            undoToastOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
        .sheet(isPresented: $viewModel.showOverrideSheet) { overrideSheet }
        .modifier(InboxKeyboardModel(viewModel: viewModel))
        .onAppear { viewModel.isInboxVisible = true }
        .onDisappear { viewModel.isInboxVisible = false }
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
                masthead
                CaptureLanesView(showsLaneSidebar: false, triageModel: viewModel)
            }
        case .captureLane(let id):
            VStack(spacing: 0) {
                masthead
                CaptureLanesView(showsLaneSidebar: false, selectedDestinationId: id, triageModel: viewModel)
            }
        case .manageCommands:
            VStack(spacing: 0) {
                masthead
                CaptureLanesView(showsLaneSidebar: false, showsCommandRegistryOnly: true, triageModel: viewModel)
            }
        }
    }

    private var queuePage: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                masthead
                captureHero
                queueOrEmptyState
            }
            inspectorOverlay
        }
    }

    // MARK: - Masthead (Command Center grammar)

    private var masthead: some View {
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
        .padding(.horizontal, DS.space32)
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
                Text("Placed: \(entry.title)")
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
            .padding(.horizontal, DS.space32)
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
                // The Seedbed rides below the queue: proto-concepts accruing
                // mass, ripest first — the "what should I develop?" answer.
                InboxGrowingSection()
            }
            // Rows sit slightly inside the masthead margin — the same
            // title-to-content rhythm as the Today page's task list.
            .padding(.horizontal, DS.space24)
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
                onToggleSelect: { viewModel.toggleSelection(for: item) }
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(ProMotionSprings.snappy, value: viewModel.isMultiSelectActive)
        }
    }

    @ViewBuilder
    private var undoToastOverlay: some View {
        if viewModel.showUndoToast {
            // Bottom-trailing, not bottom-center — the floating assistant bar
            // owns the bottom-center lane and was covering the toast.
            InboxUndoToast(viewModel: viewModel)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, DS.space24)
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

                // Inbox zero never hides the nursery — growing seedlings are
                // the queue's continuation, not its clutter.
                LazyVStack(spacing: 0) {
                    InboxGrowingSection()
                }
                .frame(maxWidth: 420)

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
