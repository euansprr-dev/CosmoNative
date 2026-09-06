// CosmoOS/UI/Pipeline/PipelineBoardView.swift
// The board: five stage columns over one query. Dropping a card into a
// column IS the stage change. Not started is the backlog — collapsed to a
// rail by default so the board reads short and the count stays honest;
// dragging out of the rail is the literal "activate".
//
// Viewport law (September 2026): the board is a VIEWPORT, not a page. Each
// column scrolls inside its own bounds under a pinned header and above a
// pinned foot, so a 130-piece backlog mounts a dozen cards, never a wall.
// (A LazyVStack under a horizontal scroll inside the page scroll has no
// viewport to be lazy in — it mounted every card, shadows, tooltips, menus
// and drag providers included.) Embedded hosts that already scroll get the
// flow layout — never a scroll inside a scroll. The horizontal scroll is
// never bound to a ScrollPosition (the 120fps law).

import SwiftUI
import AppKit

/// How the board sits in its host: a viewport whose columns scroll, or a
/// flow the host page scrolls.
enum PipelineBoardLayout: Sendable {
    case viewport, flow
}

struct PipelineBoardView: View {
    let model: PipelinePageModel
    var layout: PipelineBoardLayout = .flow
    @Binding var cursorID: String?
    /// Finder selection over the board (item uuids): click, ⌘ toggle, ⇧ range
    /// across columns in visible order. A drag from a selected card moves them all.
    @Binding var selection: Set<String>
    @Binding var selectionAnchor: String?
    let onOpen: (PipelineContentItem) -> Void
    let onOpenAsPane: (PipelineContentItem) -> Void
    let onQuickLook: (String) -> Void

    @State private var availableWidth: CGFloat = 900

    private var expandedCount: Int { model.visibleColumns.filter { !model.isCollapsed($0) }.count }
    private var columnWidth: CGFloat {
        let columns = model.visibleColumns.count
        let rails = CGFloat(columns - expandedCount) * (PipelineCollapsedColumn.width + DS.space12)
        let gaps = CGFloat(max(0, expandedCount - 1)) * DS.space12
        let free = availableWidth - rails - gaps
        return max(236, min(360, free / CGFloat(max(1, expandedCount)) - DS.space12))
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: DS.space12) {
                ForEach(model.visibleColumns) { column in
                    if model.isCollapsed(column) {
                        PipelineCollapsedColumn(column: column, model: model, fillsHeight: layout == .viewport)
                    } else {
                        PipelineColumnView(
                            column: column,
                            width: columnWidth,
                            layout: layout,
                            model: model,
                            cursorID: $cursorID,
                            selection: $selection,
                            onOpen: onOpen,
                            onOpenAsPane: onOpenAsPane,
                            onQuickLook: onQuickLook,
                            onSelect: select,
                            dragString: dragString
                        )
                    }
                }
            }
            .frame(maxHeight: layout == .viewport ? .infinity : nil, alignment: .top)
            .padding(.bottom, layout == .viewport ? 0 : DS.space8)
            .animation(ProMotionSprings.snappy, value: model.collapsedColumns)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { availableWidth = $0 }
        .scrollIndicators(.automatic)
        .scrollClipDisabled(layout == .flow)
    }

    /// Visible order, column by column — what ⇧-click ranges walk.
    private var visibleOrder: [String] {
        model.snapshot.cursorOrder.flatMap { $0 }.map { PipelineDropPayload.parse($0)?.uuid ?? $0 }
    }

    /// Finder selection: click selects, ⌘ toggles, ⇧ ranges from the anchor —
    /// across columns in visible order. Pure state; nothing here re-layouts.
    private func select(_ item: PipelineContentItem) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            selectionAnchor = item.id
        } else if flags.contains(.shift), let anchor = selectionAnchor,
                  let a = visibleOrder.firstIndex(of: anchor), let b = visibleOrder.firstIndex(of: item.id) {
            selection = Set(visibleOrder[min(a, b)...max(a, b)])
        } else {
            selection = [item.id]
            selectionAnchor = item.id
        }
        cursorID = PipelineDropPayload.content(item.id).dragString
    }

    /// One provider, every chosen piece: a drag from a selected card carries
    /// the whole selection, in visible order.
    private func dragString(for item: PipelineContentItem) -> String {
        guard selection.contains(item.id), selection.count > 1 else {
            return PipelineDropPayload.content(item.id).dragString
        }
        let ordered = visibleOrder.filter { selection.contains($0) }
        return PipelineDropPayload.batchDragString(ordered.map(PipelineDropPayload.content))
    }
}

// MARK: - Column

struct PipelineColumnView: View {
    let column: PipelineBoardSnapshot.Column
    var width: CGFloat = 236
    var layout: PipelineBoardLayout = .flow
    let model: PipelinePageModel
    @Binding var cursorID: String?
    @Binding var selection: Set<String>
    let onOpen: (PipelineContentItem) -> Void
    let onOpenAsPane: (PipelineContentItem) -> Void
    let onQuickLook: (String) -> Void
    let onSelect: (PipelineContentItem) -> Void
    let dragString: (PipelineContentItem) -> String

    @State private var isTargeted = false
    @State private var isHeaderHovered = false
    /// Cards have slid under the header / are still waiting below the foot:
    /// the edges dissolve only then, never on a column at rest.
    @State private var scrolledUnderHeader = false
    @State private var scrolledAboveFoot = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snapshot: PipelineBoardSnapshot { model.snapshot }
    private var cards: [PipelineBoardSnapshot.ContentCard] { snapshot.cardsByColumn[column] ?? [] }
    private var count: Int { snapshot.countsByColumn[column] ?? cards.count }
    private var dropTint: Color { ShelfDragSession.shared.activeColor ?? column.tint }
    private var scrolls: Bool { layout == .viewport }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if scrolls { scrollingCards } else { flowingCards }
            foot
        }
        .frame(width: width, alignment: .top)
        .frame(maxHeight: scrolls ? .infinity : nil, alignment: .top)
        .padding(DS.space6)
        .background(isTargeted ? dropTint.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTargeted ? dropTint.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .animation(ProMotionSprings.snappy, value: isTargeted)
        .dropDestination(for: String.self) { payloads, _ in
            let handled = model.handleDrop(payloads, on: column)
            ShelfDragSession.shared.end()
            return handled
        } isTargeted: { targeting in
            isTargeted = targeting
        }
    }

    // MARK: Header

    /// The column is a status object: its tint, its name in the one header
    /// voice, a live count, and on hover the two verbs a column owns. Right-
    /// click opens the same verbs as a menu; Published adds its window.
    private var header: some View {
        HStack(alignment: .center, spacing: DS.space6) {
            Circle()
                .fill(column.tint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(column.title.uppercased())
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
                .foregroundStyle(DS.giltInk)
            if column == .shipped { windowChip }
            Spacer(minLength: DS.space6)
            Text("\(count)")
                .font(DS.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
            headerVerbs
                .opacity(isHeaderHovered ? 1 : 0)
                .animation(ProMotionSprings.hover, value: isHeaderHovered)
        }
        .frame(minHeight: 22)
        .padding(.horizontal, DS.space6)
        .padding(.bottom, DS.space4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.commandChromeSeparatorStrong).frame(height: 0.5)
        }
        .contentShape(.rect)
        .onHover { isHeaderHovered = $0 }
        .contextMenu { columnMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title), \(count)")
    }

    private var headerVerbs: some View {
        HStack(spacing: DS.space2) {
            if column == .shipped {
                headerVerb("tray.and.arrow.down", clearAllHelp, disabled: clearableCount == 0) { model.clearPublishedColumn() }
            } else {
                headerVerb("plus", "New piece in \(column.title)") { model.createDraft(stage: column.stage) }
            }
            headerVerb("chevron.left", "Collapse \(column.title)") {
                withAnimation(ProMotionSprings.snappy) { model.toggleCollapsed(column) }
            }
        }
    }

    private func headerVerb(_ icon: String, _ help: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 20, height: 18)
                .background(DS.glassSectionFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(help)
        .accessibilityLabel(help)
    }

    /// The Published window, worn as the header's own chip: a menu, not a
    /// label — 7/30/90 days or all time, plus the clearing verbs.
    private var windowChip: some View {
        Menu { publishedMenuItems } label: {
            HStack(spacing: 2) {
                Text(model.publishedWindow.chip)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(DS.caption2.weight(.medium))
            .foregroundStyle(DS.textMuted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Published shows \(model.publishedWindow.title.lowercased()) — click to change")
        .accessibilityLabel("Published window, \(model.publishedWindow.title)")
    }

    // MARK: Menus

    @ViewBuilder
    private var columnMenu: some View {
        if column == .shipped {
            publishedMenuItems
        } else {
            Button("New piece in \(column.title)", systemImage: "plus") { model.createDraft(stage: column.stage) }
        }
        Divider()
        Button("Collapse \(column.title)", systemImage: "chevron.left") {
            withAnimation(ProMotionSprings.snappy) { model.toggleCollapsed(column) }
        }
    }

    /// Clearing takes shipped pieces off the board and nowhere else — the
    /// ledger, the calendar, ⌘K and the client hub keep them. Undo is ⌘Z;
    /// the foot row can show them again.
    @ViewBuilder
    private var publishedMenuItems: some View {
        Section("Show") {
            ForEach(PipelinePublishedWindow.allCases) { window in
                Button { model.publishedWindow = window } label: {
                    if window == model.publishedWindow {
                        Label(window.title, systemImage: "checkmark")
                    } else {
                        Text(window.title)
                    }
                }
            }
        }
        Divider()
        Button(clearAllTitle, systemImage: "tray.and.arrow.down") { model.clearPublishedColumn() }
            .disabled(clearableCount == 0)
        if snapshot.clearedShippedCount > 0 {
            Button(model.showsClearedPublished ? "Hide cleared pieces" : "Show \(snapshot.clearedShippedCount) cleared",
                   systemImage: model.showsClearedPublished ? "eye.slash" : "eye") {
                model.showsClearedPublished.toggle()
            }
            Button("Return all \(snapshot.clearedShippedCount) to board", systemImage: "tray.and.arrow.up") {
                model.returnAllToBoard()
            }
        }
    }

    private var clearableCount: Int { cards.count { !$0.item.isClearedFromBoard } }

    private var clearAllTitle: String {
        switch clearableCount {
        case 0: return "Clear from board"
        case 1: return "Clear 1 piece from board"
        default: return "Clear \(clearableCount) pieces from board"
        }
    }

    private var clearAllHelp: String {
        "Clear from board — stays in List, Calendar and search (⌘Z undoes)"
    }

    // MARK: Cards

    /// The viewport column: cards scroll inside their own bounds. The header
    /// and foot stay put; the edges dissolve only once cards pass under them.
    private var scrollingCards: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: DS.space8) {
                    if isTargeted { placeholderSlot }
                    if cards.isEmpty { teachingRow(column.teachingLine) } else { cardList }
                }
                .padding(.horizontal, DS.space6)
                .padding(.top, DS.space8)
                .padding(.bottom, DS.space10)
            }
            .scrollIndicators(.automatic)
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 1 }) { _, under in
                scrolledUnderHeader = under
            }
            .onScrollGeometryChange(for: Bool.self, of: { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
            }) { _, above in
                scrolledAboveFoot = above
            }
            .overlay(alignment: .top) { edgeFade(.top).opacity(scrolledUnderHeader ? 1 : 0) }
            .overlay(alignment: .bottom) { edgeFade(.bottom).opacity(scrolledAboveFoot ? 1 : 0) }
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: scrolledUnderHeader)
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: scrolledAboveFoot)
            .onChange(of: cursorID) { _, id in reveal(id, in: proxy) }
        }
    }

    /// The flow column (embedded hosts): the page scrolls, the column flows.
    private var flowingCards: some View {
        LazyVStack(spacing: DS.space8) {
            if isTargeted { placeholderSlot }
            if cards.isEmpty { teachingRow(column.teachingLine) } else { cardList }
        }
        .padding(.horizontal, DS.space6)
        .padding(.top, DS.space8)
        .padding(.bottom, DS.space10)
    }

    private var cardList: some View {
        ForEach(cards) { card in
            PipelineBoardCard(
                card: card,
                column: column,
                isCursor: cursorID == card.id,
                showsClient: snapshot.showsClientNames,
                clients: model.clients,
                actions: actions(for: card.item),
                isSelected: selection.contains(card.item.id),
                selectionCount: selection.count,
                onSelect: { onSelect(card.item) },
                dragString: { dragString(card.item) }
            )
        }
    }

    /// The keyboard cursor stays in view: the minimum scroll that reveals it.
    private func reveal(_ id: String?, in proxy: ScrollViewProxy) {
        guard let id, cards.contains(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : ProMotionSprings.snappy) { proxy.scrollTo(id) }
    }

    /// The page colour dissolving the first/last card under the pinned rows.
    private func edgeFade(_ edge: VerticalEdge) -> some View {
        LinearGradient(
            colors: [DS.bg, DS.bg.opacity(0)],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: 14)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The gap a dragged card will fill — at the top, where a moved piece
    /// lands (newest edit first), so the drop reads as a place, not a zone.
    private var placeholderSlot: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(dropTint.opacity(0.5))
            .background(dropTint.opacity(0.06), in: .rect(cornerRadius: DS.radiusMedium))
            .frame(height: 56)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .accessibilityHidden(true)
    }

    private func teachingRow(_ line: String) -> some View {
        Text(line)
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space16)
            .padding(.horizontal, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))
                    .foregroundStyle(DS.commandChromeSeparatorStrong)
            )
    }

    // MARK: Foot

    /// Notion's foot-of-column New for working columns; for Published, an
    /// honest count of what the window and the clearing keep off the board.
    @ViewBuilder
    private var foot: some View {
        if column == .shipped {
            publishedFoot
        } else {
            PipelineFootRow(title: "New", icon: "plus") { model.createDraft(stage: column.stage) }
                .help("New piece in \(column.title)")
        }
    }

    @ViewBuilder
    private var publishedFoot: some View {
        let older = snapshot.olderShippedCount
        let cleared = snapshot.clearedShippedCount
        if older > 0 || cleared > 0 {
            HStack(spacing: DS.space4) {
                if older > 0 {
                    PipelineFootRow(title: older == 1 ? "1 older" : "\(older) older", icon: "clock.arrow.circlepath") {
                        model.publishedWindow = .allTime
                    }
                    .help("Published before the window opened — show all time")
                }
                if cleared > 0 {
                    PipelineFootRow(
                        title: model.showsClearedPublished ? "Hide cleared" : (cleared == 1 ? "1 cleared" : "\(cleared) cleared"),
                        icon: model.showsClearedPublished ? "eye.slash" : "tray"
                    ) {
                        model.showsClearedPublished.toggle()
                    }
                    .help(model.showsClearedPublished ? "Hide the pieces cleared from the board" : "Show the pieces cleared from the board")
                }
                Spacer(minLength: 0)
            }
            .animation(ProMotionSprings.snappy, value: model.showsClearedPublished)
        }
    }

    private func actions(for item: PipelineContentItem) -> PipelineCardActions {
        PipelineCardActions(
            open: { onOpen(item) },
            openAsPane: { onOpenAsPane(item) },
            quickLook: { onQuickLook(item.id) },
            move: { model.move(item.id, to: $0) },
            schedule: { model.pendingSchedule = item },
            unschedule: { model.schedule(item.id, on: nil) },
            bookSession: { model.bookSession(item.id, on: $0) },
            assignClient: { model.assignClient(item.id, to: $0) },
            export: { Task { model.pendingExport = try? await AtomRepository.shared.fetch(uuid: item.id) } },
            logPerformance: { Task { model.pendingPerf = try? await AtomRepository.shared.fetch(uuid: item.id) } },
            archive: { model.archive([item.id]) },
            restore: { model.restore(item.id) },
            clearFromBoard: { model.clearFromBoard([item.id]) },
            returnToBoard: { model.returnToBoard([item.id]) }
        )
    }
}

// MARK: - Collapsed column (the rail)

/// A collapsed column is a count you can still drop on: the tint dot, the
/// live count, the name running up the rail. Click expands; a drop moves.
struct PipelineCollapsedColumn: View {
    static let width: CGFloat = 40

    let column: PipelineBoardSnapshot.Column
    let model: PipelinePageModel
    var fillsHeight = false

    @State private var isTargeted = false
    @State private var isHovered = false

    private var count: Int { model.snapshot.count(in: column) }
    private var dropTint: Color { ShelfDragSession.shared.activeColor ?? column.tint }

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { model.toggleCollapsed(column) }
        } label: {
            rail
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(ProMotionSprings.snappy, value: isTargeted)
        .help("Expand \(column.title) (\(count))")
        .accessibilityLabel("\(column.title), \(count), collapsed")
        .dropDestination(for: String.self) { payloads, _ in
            let handled = model.handleDrop(payloads, on: column)
            ShelfDragSession.shared.end()
            return handled
        } isTargeted: { isTargeted = $0 }
    }

    private var rail: some View {
        VStack(spacing: DS.space8) {
            Circle()
                .fill(column.tint)
                .frame(width: 7, height: 7)
            Text("\(count)")
                .font(DS.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
            Text(column.title.uppercased())
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
                .foregroundStyle(DS.giltInk)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: 112)
            Spacer(minLength: 0)
        }
        .padding(.top, DS.space12)
        .frame(width: Self.width)
        .frame(height: fillsHeight ? nil : 220)
        .frame(maxHeight: fillsHeight ? .infinity : nil)
        .background(
            isTargeted ? dropTint.opacity(0.10) : (isHovered ? DS.glassSectionFill : DS.glassSectionFill.opacity(0.6)),
            in: .rect(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isTargeted ? dropTint.opacity(0.45) : DS.commandChromeBorder, lineWidth: isTargeted ? 1 : 0.5)
        )
        .contentShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Foot row

/// The quiet row at the foot of a column: a glyph and a word, ink on hover.
/// "New" in working columns; the hidden counts under Published.
struct PipelineFootRow: View {
    let title: String
    var icon = "plus"
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(DS.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(isHovered ? DS.text : DS.textMuted)
                .lineLimit(1)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space6)
                .background(isHovered ? DS.glassSectionFill : Color.clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel(title)
    }
}

extension PipelineBoardSnapshot.Column {
    /// One low-saturation tint per stage: categorical identity, never a wall.
    var tint: Color {
        switch self {
        case .notStarted: return DS.textMuted
        case .inProgress: return DS.accent
        case .review: return DS.gilt
        case .ready: return DS.green
        case .shipped: return DS.textSecondary
        }
    }

    /// Absence teaches the next action, in the column's own voice.
    var teachingLine: String {
        switch self {
        case .notStarted: return "Pieces you have started but not touched wait here."
        case .inProgress: return "Begin writing from an idea, or drag a piece in."
        case .review: return "Move work here when it needs feedback."
        case .ready: return "Finished pieces ready for publication."
        case .shipped: return "Published work from the window above appears here."
        }
    }
}
