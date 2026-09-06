// CosmoOS/UI/Pipeline/PipelinePage.swift
// Pipeline — the room where content is executed. One query (by client, stage
// and date) behind three views: the Board (stage columns; a drop IS the stage
// change), the Calendar (the month, re-homed here from Upcoming), and the
// List (a Finder-grade ledger with bulk verbs). Client pills scope the whole
// page in the Ideas grammar; search browses everything. Manners are Mac —
// hover, tooltips, ⌘1/2/3, arrows, Space, Esc walks home.

import SwiftUI
import AppKit

struct PipelinePage: View {
    /// Owned by MainView (or the client hub) so revisits keep their data.
    let model: PipelinePageModel
    /// Inside a client hub the masthead and pills belong to the hub.
    var embedded = false
    var workspace = false
    var availableWidth: CGFloat = 1200
    /// Retained workspace pages each keep their own lens over the shared model.
    var displayView: PipelineView? = nil
    var isActive = true
    /// The workspace's Board‖List choice, rendered in this page's own filter
    /// rail (a view mode is a switcher, never a menu). nil = host decides.
    var layout: Binding<Bool>? = nil
    private var currentView: PipelineView { displayView ?? model.view }

    @State private var searchFocused = false
    @State private var contextPillVisible = false
    @State private var scrollHomeRequest = 0
    @State private var hasAppeared = false
    @State private var cursorID: String?
    @State private var ledgerSort: PipelineLedgerSort = .newest
    @State private var selection: Set<String> = []
    @State private var selectionAnchor: String?
    @State private var bulkScheduleRequested = false
    @State private var calendarAnchor = Calendar.current.startOfDay(for: Date())
    @FocusState private var searchFieldFocused: Bool
    @FocusState private var pageFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !embedded && !workspace { SwipePageBackground() }
            if embedded {
                // Inside a host that already scrolls (a client hub, a space's
                // Board view): flow in place — never a scroll inside a scroll.
                embeddedContent
            } else if workspace && currentView == .calendar {
                viewportContent
            } else {
                scrollContent
            }
            if isActive { overlays }
        }
        .task {
            if !workspace { await model.start() }
            if !hasAppeared && !workspace {
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) { hasAppeared = true }
            }
            pageFocused = isActive
        }
        .onDisappear { if !embedded && !workspace { model.stop() } }
        .onChange(of: isActive) { _, active in
            pageFocused = active
            if !active { searchFieldFocused = false; bulkScheduleRequested = false; model.quickLookID = nil; model.pendingExport = nil }
        }
        .onChange(of: currentView) { _, _ in clearTransientState() }
        .onChange(of: model.scope) { _, _ in clearTransientState() }
        .onExitCommand(perform: handleEscape)
        .background { if isActive { keyboardLayer } }
        .overlay(alignment: .bottom) { if isActive { bulkBar } }
        .overlay(alignment: .bottom) { if isActive { SwipeSaveToast(message: toastBinding) } }
    }

    // MARK: Scroll scaffold

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space20) {
                    headerGroup.id("pipeline-top")
                    content
                }
                .padding(.horizontal, embedded ? 0 : DS.space32)
                // Filters ride the masthead: under the workspace header the
                // rail keeps a section gap, not a page gap.
                .padding(.top, embedded ? DS.space8 : (workspace ? DS.space20 : 36))
                .padding(.bottom, 72)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 88 }) { _, shouldShow in
                if shouldShow != contextPillVisible { contextPillVisible = shouldShow }
            }
            .overlay(alignment: .top) { if !embedded && !workspace { contextPill } }
            .focusable()
            .focusEffectDisabled()
            .focused($pageFocused)
            .onMoveCommand { direction in moveCursor(direction) }
            .onKeyPress(.return) { openCursor() ? .handled : .ignored }
            .onKeyPress(.space) { quickLookCursor() ? .handled : .ignored }
            .onKeyPress(.delete) { archiveSelection() ? .handled : .ignored }
            .onChange(of: scrollHomeRequest) { _, _ in
                withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) {
                    proxy.scrollTo("pipeline-top", anchor: .top)
                }
            }
        }
    }

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            headerGroup
            content
        }
        .focusable()
        .focusEffectDisabled()
        .focused($pageFocused)
        .onMoveCommand { direction in moveCursor(direction) }
        .onKeyPress(.return) { openCursor() ? .handled : .ignored }
        .onKeyPress(.space) { quickLookCursor() ? .handled : .ignored }
        .onKeyPress(.delete) { archiveSelection() ? .handled : .ignored }
    }

    /// The calendar is a viewport, not a page: the month fills the height and
    /// the shelf scrolls inside its own bounds — never the whole page.
    private var viewportContent: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            headerGroup
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, DS.space32)
        .padding(.top, DS.space20)
        .padding(.bottom, DS.space20)
        .focusable()
        .focusEffectDisabled()
        .focused($pageFocused)
        .onMoveCommand { direction in moveCursor(direction) }
        .onKeyPress(.return) { openCursor() ? .handled : .ignored }
        .onKeyPress(.space) { quickLookCursor() ? .handled : .ignored }
        .onKeyPress(.delete) { archiveSelection() ? .handled : .ignored }
    }

    // MARK: Header (masthead + switcher + pills + filters)

    private var headerGroup: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if !embedded && !workspace { masthead }
            if !embedded && !workspace { clientPills }
            if embedded { embeddedSwitcherRow }
            filterRail
            if let error = model.errorMessage {
                HStack { Text(error); Spacer(); Button("Retry") { Task { await model.load() } } }
                    .font(DS.callout).foregroundStyle(DS.textSecondary)
            }
        }
        .opacity(workspace || hasAppeared ? 1 : 0)
        .offset(y: workspace || hasAppeared ? 0 : 6)
    }

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space16) {
            SwipeMasthead(title: "Pipeline", detail: mastheadDetail)
            Spacer(minLength: DS.space16)
            viewSwitcher
        }
    }

    private var mastheadDetail: String {
        let inMotion = model.inMotionCount
        let thisWeek = model.publishingThisWeekCount
        var parts = ["\(inMotion) in motion"]
        if thisWeek > 0 { parts.append("\(thisWeek) publish this week") }
        return parts.joined(separator: " · ")
    }

    /// Embedded hosts choose Board or List here (their own chrome decides
    /// whether a Calendar exists beside them).
    private var embeddedSwitcherRow: some View {
        HStack {
            CosmoSegmentedSwitcher(
                options: [PipelineView.board, .list],
                label: { $0.title },
                icon: { $0.cosmoIcon },
                help: { $0.help },
                selection: Binding(get: { currentView == .calendar ? .board : currentView }, set: { switchView($0) })
            )
            Spacer(minLength: 0)
            Text(mastheadDetail)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
        }
    }

    var viewSwitcher: some View {
        CosmoSegmentedSwitcher(
            options: PipelineView.allCases,
            label: { $0.title },
            icon: { $0.cosmoIcon },
            help: { $0.help },
            selection: Binding(get: { currentView }, set: { switchView($0) })
        )
    }

    private var clientPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                ClientObjectPill(name: "Everyone", tint: DS.accent, isSelected: model.scope == .all) {
                    setScope(.all)
                }
                ForEach(model.clients) { client in
                    ClientObjectPill(
                        name: client.name,
                        tint: DS.clientColor(for: client.uuid),
                        isSelected: model.scope == .client(uuid: client.uuid)
                    ) {
                        setScope(model.scope == .client(uuid: client.uuid) ? .all : .client(uuid: client.uuid))
                    }
                }
                ClientObjectPill(name: "Unassigned", tint: DS.textMuted, isSelected: model.scope == .unassigned) {
                    setScope(model.scope == .unassigned ? .all : .unassigned)
                }
            }
            .padding(.vertical, DS.space4)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder private var filterRail: some View {
        if availableWidth < 700 { compactFilterRail }
        else { fullFilterRail }
    }

    private var compactFilterRail: some View {
        HStack(spacing: DS.space12) {
            SwipeLibrarySearchField(
                text: Binding(get: { model.filters.query }, set: { model.filters.query = $0 }),
                isFocused: $searchFieldFocused, placeholder: "Find in content")
                .accessibilityLabel("Search content").help("Find in content (⌘F)")
            Menu {
                platformMenu
                formatMenu
                if currentView == .list {
                    Divider()
                    Button(model.filters.showArchived ? "Show active content" : "Show archived content") { model.filters.showArchived.toggle() }
                    sortMenu
                }
            } label: {
                Label(currentView == .list && model.filters.showArchived ? "Archived" : (model.filters.platform != nil || model.filters.format != nil ? "Filtered" : "Filters"),
                      systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.borderlessButton).fixedSize().font(DS.callout)
            .help("Content filters and display options")
            Spacer(minLength: 0)
            layoutSwitcher
        }
    }

    private var fullFilterRail: some View {
        HStack(spacing: DS.space8) {
            SwipeLibrarySearchField(
                text: Binding(get: { model.filters.query }, set: { model.filters.query = $0 }),
                isFocused: $searchFieldFocused,
                placeholder: "Find in content"
            )
            .frame(maxWidth: 260)
            .accessibilityLabel("Search content")
            .help("Find in content (⌘F)")
            platformMenu
            formatMenu
            if currentView == .list { archivedToggle }
            Spacer(minLength: DS.space8)
            if currentView == .list { sortMenu }
            layoutSwitcher
        }
        .animation(ProMotionSprings.gentle, value: currentView)
    }

    /// Board‖List is a view mode, so it speaks the one switcher voice — docked
    /// at the rail's trailing edge, never a menu in the masthead.
    @ViewBuilder private var layoutSwitcher: some View {
        if let layout, currentView != .calendar {
            CosmoSegmentedSwitcher(
                options: [PipelineView.board, .list],
                label: { $0.title }, icon: { $0.cosmoIcon },
                help: { $0 == .board ? "Board — stages as columns" : "List — every piece as a ledger" },
                selection: Binding(get: { layout.wrappedValue ? .list : .board }, set: { layout.wrappedValue = $0 == .list })
            )
            .fixedSize()
            .accessibilityLabel("Pipeline layout")
        }
    }

    private var platformMenu: some View {
        Menu {
            Button("Any platform") { model.filters.platform = nil }
            Divider()
            ForEach(SocialPlatform.allCases, id: \.self) { platform in
                Button {
                    model.filters.platform = platform
                } label: {
                    if model.filters.platform == platform {
                        Label(platform.displayName, systemImage: "checkmark")
                    } else {
                        Text(platform.displayName)
                    }
                }
            }
        } label: {
            filterChipLabel(model.filters.platform?.displayName ?? "Platform", active: model.filters.platform != nil)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by platform")
        .menuIndicator(.hidden)
    }

    private var formatMenu: some View {
        Menu {
            Button("Any format") { model.filters.format = nil }
            Divider()
            ForEach(ContentFormat.allCases, id: \.self) { format in
                Button {
                    model.filters.format = format
                } label: {
                    if model.filters.format == format {
                        Label(format.displayName, systemImage: "checkmark")
                    } else {
                        Text(format.displayName)
                    }
                }
            }
        } label: {
            filterChipLabel(model.filters.format?.displayName ?? "Format", active: model.filters.format != nil)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by format")
        .menuIndicator(.hidden)
    }

    private func filterChipLabel(_ title: String, active: Bool) -> some View {
        HStack(spacing: DS.space4) {
            Text(title)
                .font(DS.callout.weight(.medium))
            Image(systemName: "chevron.down")
                .font(DS.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(active ? DS.accent : DS.textSecondary)
        .padding(.horizontal, DS.space10)
        .frame(height: 30)
        .background(active ? DS.accentSoft : DS.glassSectionFill, in: .capsule)
    }

    private var archivedToggle: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                model.filters.showArchived.toggle()
                selection.removeAll()
            }
        } label: {
            Text(model.filters.showArchived ? "Archived" : "In motion")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(model.filters.showArchived ? DS.accent : DS.textSecondary)
                .padding(.horizontal, DS.space10)
                .frame(height: 30)
                .background(model.filters.showArchived ? DS.accentSoft : DS.glassSectionFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Show the archived shelf")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PipelineLedgerSort.allCases, id: \.self) { sort in
                Button {
                    withAnimation(ProMotionSprings.snappy) { ledgerSort = sort }
                } label: {
                    if ledgerSort == sort {
                        Label(sort.label, systemImage: "checkmark")
                    } else {
                        Text(sort.label)
                    }
                }
                .help(sort.help)
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DS.caption.weight(.medium))
                    .accessibilityHidden(true)
                Text(ledgerSort.label)
                    .font(DS.callout.weight(.medium))
            }
            .foregroundStyle(DS.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort the ledger")
    }

    // MARK: Content (routed by view)

    @ViewBuilder
    private var content: some View {
        switch currentView {
        case .board:
            PipelineBoardView(
                model: model,
                cursorID: $cursorID,
                selection: $selection,
                selectionAnchor: $selectionAnchor,
                onOpen: { model.open($0) },
                onOpenAsPane: { model.openAsPane($0) },
                onQuickLook: { model.quickLookID = $0 }
            )
            .opacity(workspace || hasAppeared ? 1 : 0)
        case .calendar:
            PipelineCalendarView(model: model, anchor: $calendarAnchor)
                .opacity(workspace || hasAppeared ? 1 : 0)
        case .list:
            PipelineListView(
                model: model,
                sort: ledgerSort,
                selection: $selection,
                selectionAnchor: $selectionAnchor,
                cursorID: $cursorID,
                onOpen: { model.open($0) },
                onOpenAsPane: { model.openAsPane($0) },
                onQuickLook: { model.quickLookID = $0 },
                compact: availableWidth < 720
            )
            .opacity(workspace || hasAppeared ? 1 : 0)
        }
    }

    // MARK: Context pill (orientation never dies)

    @ViewBuilder
    private var contextPill: some View {
        SwipeContextPill(
            title: "Pipeline",
            detail: contextDetail,
            visible: contextPillVisible
        ) {
            scrollHomeRequest += 1
        }
        .padding(.top, DS.space12)
    }

    private var contextDetail: String? {
        switch model.scope {
        case .all: return currentView.title
        case .client(let uuid): return model.client(uuid)?.name ?? currentView.title
        case .unassigned: return "Unassigned"
        case .space: return "This space"
        }
    }

    // MARK: Overlays (quick look, schedule, ship, perf)

    @ViewBuilder
    private var overlays: some View {
        if let id = model.quickLookID, let item = model.item(id) {
            ContentQuickLookPanel(
                item: item,
                sessionDay: model.sessionDaysByContent[id],
                perf: model.perfByContent[id],
                onOpen: { model.quickLookID = nil; model.open(item) },
                onOpenAsPane: { model.quickLookID = nil; model.openAsPane(item) },
                onSchedule: { model.quickLookID = nil; model.pendingSchedule = item },
                onClose: { model.quickLookID = nil }
            )
            .zIndex(10)
        }
        if let atom = model.pendingExport {
            ContentExportOverlay(atom: atom, draft: atom.body ?? "", onClose: { model.pendingExport = nil })
                .zIndex(11)
        }
        Color.clear
            .frame(width: 1, height: 1)
            .popover(item: Binding(get: { model.pendingSchedule }, set: { model.pendingSchedule = $0 })) { item in
                ContentSchedulePopover(
                    title: item.atom.title ?? "Untitled",
                    currentDay: item.scheduledAt,
                    onPick: { day in
                        model.pendingSchedule = nil
                        model.schedule(item.id, on: day)
                    },
                    onUnschedule: {
                        model.pendingSchedule = nil
                        model.schedule(item.id, on: nil)
                    }
                )
            }
            .sheet(item: Binding(get: { model.pendingPerf }, set: { model.pendingPerf = $0 })) { atom in
                ContentPerfEntrySheet(atom: atom, onClose: { model.pendingPerf = nil })
            }
            .popover(isPresented: $bulkScheduleRequested) {
                ContentSchedulePopover(
                    title: "\(selection.count) pieces",
                    currentDay: nil,
                    onPick: { day in
                        bulkScheduleRequested = false
                        for id in selection { model.schedule(id, on: day) }
                        selection.removeAll()
                    }
                )
            }
    }

    /// The list shows the bar for any selection; the board only once there is
    /// a group to act on (a single card's verbs live on the card).
    @ViewBuilder
    private var bulkBar: some View {
        if !selection.isEmpty, currentView == .list || (currentView == .board && selection.count > 1) {
            PipelineBulkBar(
                count: selection.count,
                clients: model.clients,
                onMove: { phase in model.bulkMove(Array(selection), to: phase); selection.removeAll() },
                onSchedule: { bulkScheduleRequested = true },
                onAssign: { client in model.bulkAssign(Array(selection), to: client); selection.removeAll() },
                onArchive: { model.archive(Array(selection)); selection.removeAll() },
                onClear: { withAnimation(ProMotionSprings.snappy) { selection.removeAll() } }
            )
        }
    }

    private var toastBinding: Binding<String?> {
        Binding(get: { model.toastMessage }, set: { model.toastMessage = $0 })
    }

    // MARK: Keyboard manners

    private var keyboardLayer: some View {
        Group {
            Button("") { searchFieldFocused = true }.keyboardShortcut("f", modifiers: .command)
            if !workspace { Button("") { createPiece() }.keyboardShortcut("n", modifiers: .command) }
            Button("") { Task { await model.load() } }.keyboardShortcut("r", modifiers: .command)
            if !embedded && !workspace {
                Button("") { switchView(.board) }.keyboardShortcut("1", modifiers: .command)
                Button("") { switchView(.calendar) }.keyboardShortcut("2", modifiers: .command)
                Button("") { switchView(.list) }.keyboardShortcut("3", modifiers: .command)
            }
            Button("") { selectAll() }.keyboardShortcut("a", modifiers: .command)
            Button("") { exportCursor() }.keyboardShortcut("e", modifiers: .command)
            Button("") { stepCursorStage(forward: true) }.keyboardShortcut(.rightArrow, modifiers: .command)
            Button("") { stepCursorStage(forward: false) }.keyboardShortcut(.leftArrow, modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func switchView(_ view: PipelineView) {
        guard model.view != view else { return }
        withAnimation(ProMotionSprings.focusTransition) { model.view = view }
    }

    private func setScope(_ scope: PipelineScope) {
        withAnimation(ProMotionSprings.snappy) {
            model.scope = scope
            cursorID = nil
            selection.removeAll()
        }
    }

    private func clearTransientState() {
        cursorID = nil
        selection.removeAll()
        selectionAnchor = nil
        model.quickLookID = nil
        model.pendingExport = nil
    }

    private func handleEscape() {
        guard isActive else { return }
        if model.pendingExport != nil {
            model.pendingExport = nil
        } else if model.quickLookID != nil {
            model.quickLookID = nil
        } else if !selection.isEmpty {
            withAnimation(ProMotionSprings.snappy) { selection.removeAll() }
        } else if !model.filters.query.isEmpty {
            model.filters.query = ""
        } else if model.scope != .all, !embedded, !workspace {
            setScope(.all)
        }
    }

    private func createPiece() {
        Task {
            let clientUUID = model.scope.clientUUID
            guard let atom = try? await ContentPipelineService().createContent(
                title: "Untitled",
                body: "",
                platform: nil,
                clientUUID: clientUUID
            ) else { return }
            NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
            await model.load()
            if let id = atom.id, id > 0 {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.content, "id": id]
                )
            }
        }
    }

    private func selectAll() {
        withAnimation(ProMotionSprings.snappy) {
            switch currentView {
            case .list: selection = Set(model.listRows.map(\.id))
            case .board: selection = Set(model.snapshot.cursorOrder.flatMap { $0 }.compactMap { PipelineDropPayload.parse($0)?.uuid })
            case .calendar: break
            }
        }
    }

    /// ⌘E — the deliberate export for the cursored piece.
    private func exportCursor() {
        guard let cursorID else { return }
        let uuid = PipelineDropPayload.parse(cursorID)?.uuid ?? cursorID
        guard model.item(uuid) != nil else { return }
        Task { model.pendingExport = try? await AtomRepository.shared.fetch(uuid: uuid) }
    }

    // MARK: Cursor

    private var cursorSections: [[String]] {
        switch currentView {
        case .board: return model.snapshot.cursorOrder
        case .list: return [ledgerSort.sort(model.listRows).map(\.id)]
        case .calendar: return []
        }
    }

    private func moveCursor(_ direction: MoveCommandDirection) {
        let sections = cursorSections.filter { !$0.isEmpty }
        guard !sections.isEmpty else { return }
        guard let current = cursorID,
              let section = sections.firstIndex(where: { $0.contains(current) }),
              let row = sections[section].firstIndex(of: current) else {
            cursorID = sections[0][0]
            return
        }
        switch direction {
        case .down:
            cursorID = sections[section][min(row + 1, sections[section].count - 1)]
        case .up:
            cursorID = sections[section][max(row - 1, 0)]
        case .right where currentView == .board:
            let next = min(section + 1, sections.count - 1)
            cursorID = sections[next][min(row, sections[next].count - 1)]
        case .left where currentView == .board:
            let prev = max(section - 1, 0)
            cursorID = sections[prev][min(row, sections[prev].count - 1)]
        default:
            break
        }
        // The cursor IS the selection (⇧ extends it from the anchor) on both
        // the ledger and the board.
        guard currentView != .calendar, let cursorID else { return }
        let uuid = PipelineDropPayload.parse(cursorID)?.uuid ?? cursorID
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true, let anchor = selectionAnchor {
            let order = sections.flatMap { $0 }.map { PipelineDropPayload.parse($0)?.uuid ?? $0 }
            if let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: uuid) {
                selection = Set(order[min(a, b)...max(a, b)])
            }
        } else {
            selection = [uuid]
            selectionAnchor = uuid
        }
    }

    private func openCursor() -> Bool {
        guard let cursorID else { return false }
        let uuid = cursorID.replacingOccurrences(of: "content:", with: "")
        guard let item = model.item(uuid) else { return false }
        model.open(item)
        return true
    }

    private func quickLookCursor() -> Bool {
        guard let cursorID else { return false }
        let uuid = cursorID.replacingOccurrences(of: "content:", with: "")
        guard model.item(uuid) != nil else { return false }
        model.quickLookID = model.quickLookID == uuid ? nil : uuid
        return true
    }

    private func archiveSelection() -> Bool {
        guard currentView != .calendar, !selection.isEmpty else { return false }
        model.archive(Array(selection))
        selection.removeAll()
        return true
    }

    /// ⌘→ / ⌘← on the cursored card: the adjacent stage (Scheduled asks for a date).
    private func stepCursorStage(forward: Bool) {
        guard let cursorID else { return }
        let uuid = cursorID.replacingOccurrences(of: "content:", with: "")
        guard let item = model.item(uuid) else { return }
        let column = PipelineBoardSnapshot.Column.column(for: item.productionStage)
        let columns = model.visibleColumns
        guard let index = columns.firstIndex(of: column) else { return }
        let targetIndex = forward ? index + 1 : index - 1
        guard columns.indices.contains(targetIndex) else { return }
        let target = columns[targetIndex]
        // A selection that includes the cursored card moves as one.
        let batch = selection.contains(uuid) && selection.count > 1 ? Array(selection) : [uuid]
        if target == .shipped { model.publish(batch) }
        else if batch.count == 1 { model.move(uuid, to: target.stage) }
        else { model.bulkMove(batch, to: target.stage) }
    }
}
