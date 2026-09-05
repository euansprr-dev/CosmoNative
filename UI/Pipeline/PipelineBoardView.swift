// CosmoOS/UI/Pipeline/PipelineBoardView.swift
// The board: six stage columns over one query. Dropping a card into a column
// IS the stage change; the Ideas column is the Desk's Up-next lane and a
// drag out of it runs Begin Writing. Columns are lazy; the horizontal scroll
// is never bound to a ScrollPosition (the 120fps law applies to scrolling).

import SwiftUI

struct PipelineBoardView: View {
    let model: PipelinePageModel
    @Binding var cursorID: String?
    let onOpen: (PipelineContentItem) -> Void
    let onOpenAsPane: (PipelineContentItem) -> Void
    let onQuickLook: (String) -> Void

    @State private var availableWidth: CGFloat = 900
    private var columnWidth: CGFloat { max(236, min(360, (availableWidth - CGFloat(model.visibleColumns.count - 1) * DS.space12) / CGFloat(model.visibleColumns.count) - DS.space12)) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: DS.space12) {
                ForEach(model.visibleColumns) { column in
                    PipelineColumnView(
                        column: column,
                        width: columnWidth,
                        model: model,
                        cursorID: $cursorID,
                        onOpen: onOpen,
                        onOpenAsPane: onOpenAsPane,
                        onQuickLook: onQuickLook
                    )
                }
            }
            .padding(.bottom, DS.space8)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { availableWidth = $0 }
        .scrollIndicators(.automatic)
        .scrollClipDisabled()
    }
}

// MARK: - Column

struct PipelineColumnView: View {
    let column: PipelineBoardSnapshot.Column
    var width: CGFloat = 236
    let model: PipelinePageModel
    @Binding var cursorID: String?
    let onOpen: (PipelineContentItem) -> Void
    let onOpenAsPane: (PipelineContentItem) -> Void
    let onQuickLook: (String) -> Void

    @State private var isTargeted = false

    private var snapshot: PipelineBoardSnapshot { model.snapshot }
    private var cards: [PipelineBoardSnapshot.ContentCard] { snapshot.cardsByColumn[column] ?? [] }
    private var count: Int { snapshot.countsByColumn[column] ?? cards.count }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            header
            columnBody
        }
        .frame(width: width, alignment: .top)
        .padding(DS.space6)
        .background(isTargeted ? (ShelfDragSession.shared.activeColor ?? DS.accent).opacity(0.10) : Color.clear, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTargeted ? (ShelfDragSession.shared.activeColor ?? DS.accent).opacity(0.55) : Color.clear, lineWidth: 1)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
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
        }
        .padding(.horizontal, DS.space6)
        .padding(.bottom, DS.space4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.palette.sepiaBorder).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(column.title), \(count)")
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
        LazyVStack(spacing: DS.space6) {
            ForEach(cards) { card in
                if model.groupByClient, isGroupLead(card) {
                    groupLabel(card.clientGroup ?? "Unassigned")
                }
                PipelineBoardCard(
                    card: card,
                    column: column,
                    isCursor: cursorID == card.id,
                    clients: model.clients,
                    actions: actions(for: card.item)
                )
                .onTapGesture { cursorID = card.id }
            }
        }
    }

    private func isGroupLead(_ card: PipelineBoardSnapshot.ContentCard) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return false }
        return index == 0 || cards[index - 1].clientGroup != card.clientGroup
    }

    private func groupLabel(_ name: String) -> some View {
        Text(name)
            .font(DS.caption2.weight(.semibold))
            .foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space6)
            .padding(.top, DS.space4)
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
                    .foregroundStyle(DS.palette.sepiaBorder)
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
            ship: { Task { model.pendingShip = try? await AtomRepository.shared.fetch(uuid: item.id) } },
            logPerformance: { Task { model.pendingPerf = try? await AtomRepository.shared.fetch(uuid: item.id) } },
            archive: { model.archive([item.id]) },
            restore: { model.restore(item.id) }
        )
    }
}

extension PipelineBoardSnapshot.Column {
    /// Absence teaches the next action, in the column's own voice.
    var teachingLine: String {
        switch self {
        case .inProgress: return "Start a piece from an idea, or create a new draft."
        case .review: return "Move work here when it needs feedback."
        case .ready: return "Finished pieces ready for publication."
        case .shipped: return "Published work from the last 30 days appears here."
        }
    }
}
