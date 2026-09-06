// CosmoOS/UI/Pipeline/PipelineBoardView.swift
// The board: five stage columns over one query. Dropping a card into a
// column IS the stage change. Not started is the backlog — collapsed to a
// rail by default so the board reads short and the count stays honest;
// dragging out of the rail is the literal "activate". Columns are lazy; the
// horizontal scroll is never bound to a ScrollPosition (the 120fps law).

import SwiftUI
import AppKit

struct PipelineBoardView: View {
    let model: PipelinePageModel
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
                        PipelineCollapsedColumn(column: column, model: model)
                    } else {
                        PipelineColumnView(
                            column: column,
                            width: columnWidth,
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
            .padding(.bottom, DS.space8)
            .animation(ProMotionSprings.snappy, value: model.collapsedColumns)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { availableWidth = $0 }
        .scrollIndicators(.automatic)
        .scrollClipDisabled()
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

    private var snapshot: PipelineBoardSnapshot { model.snapshot }
    private var cards: [PipelineBoardSnapshot.ContentCard] { snapshot.cardsByColumn[column] ?? [] }
    private var count: Int { snapshot.countsByColumn[column] ?? cards.count }
    private var dropTint: Color { ShelfDragSession.shared.activeColor ?? column.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            header
            columnBody
            if isTargeted { placeholderSlot }
            if column != .shipped { newRow }
        }
        .frame(width: width, alignment: .top)
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

    /// The column is a status object: its tint, its name in the one header
    /// voice, a live count, and on hover the two verbs a column owns.
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
            if column == .shipped {
                Text("30d")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: DS.space6)
            Text("\(count)")
                .font(DS.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
            HStack(spacing: DS.space2) {
                if column != .shipped {
                    headerVerb("plus", "New piece in \(column.title)") { model.createDraft(stage: column.stage) }
                }
                headerVerb("chevron.left", "Collapse \(column.title)") {
                    withAnimation(ProMotionSprings.snappy) { model.toggleCollapsed(column) }
                }
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title), \(count)")
    }

    private func headerVerb(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 20, height: 18)
                .background(DS.glassSectionFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private var columnBody: some View {
        if cards.isEmpty {
            teachingRow(column.teachingLine)
        } else {
            contentCards
        }
    }

    private var contentCards: some View {
        LazyVStack(spacing: DS.space8) {
            ForEach(cards) { card in
                PipelineBoardCard(
                    card: card,
                    column: column,
                    isCursor: cursorID == card.id,
                    clients: model.clients,
                    actions: actions(for: card.item),
                    isSelected: selection.contains(card.item.id),
                    selectionCount: selection.count,
                    onSelect: { onSelect(card.item) },
                    dragString: { dragString(card.item) }
                )
            }
        }
    }

    /// The gap a dragged card will fill — the drop reads as a place, not a zone.
    private var placeholderSlot: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(dropTint.opacity(0.5))
            .background(dropTint.opacity(0.06), in: .rect(cornerRadius: DS.radiusMedium))
            .frame(height: 56)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .accessibilityHidden(true)
    }

    /// Notion's foot-of-column New: a quiet row that becomes a piece born in
    /// this stage.
    private var newRow: some View {
        PipelineNewRow(title: "New") { model.createDraft(stage: column.stage) }
            .help("New piece in \(column.title)")
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
            restore: { model.restore(item.id) }
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

    @State private var isTargeted = false
    @State private var isHovered = false

    private var count: Int { model.snapshot.count(in: column) }
    private var dropTint: Color { ShelfDragSession.shared.activeColor ?? column.tint }

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { model.toggleCollapsed(column) }
        } label: {
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
            .frame(width: Self.width, height: 220)
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
}

// MARK: - New row

struct PipelineNewRow: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(isHovered ? DS.text : DS.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space6)
                .background(isHovered ? DS.glassSectionFill : Color.clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel("\(title) piece")
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
        case .shipped: return "Published work from the last 30 days appears here."
        }
    }
}
