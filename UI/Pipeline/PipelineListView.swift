// CosmoOS/UI/Pipeline/PipelineListView.swift
// The Pipeline as a Finder-grade ledger (the All Ideas grammar): one grouped
// container, 44pt rows, Finder selection (click, ⌘ toggle, ⇧ range,
// double-click opens), hover verbs by opacity swap, and a floating bulk bar
// over the selection. Sort and the archived shelf ride the page's controls.

import SwiftUI
import AppKit

enum PipelineLedgerSort: String, CaseIterable {
    case newest, stage, client, date

    var label: String {
        switch self {
        case .newest: return "Newest"
        case .stage: return "Stage"
        case .client: return "Client"
        case .date: return "Date"
        }
    }

    var help: String {
        switch self {
        case .newest: return "Most recently touched first"
        case .stage: return "Earliest stage first"
        case .client: return "Grouped by client name"
        case .date: return "Soonest publish day first"
        }
    }

    func sort(_ rows: [PipelineContentItem]) -> [PipelineContentItem] {
        switch self {
        case .newest:
            return rows.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
        case .stage:
            return rows.sorted {
                let a = ContentProductionStage.allCases.firstIndex(of: $0.productionStage) ?? 0
                let b = ContentProductionStage.allCases.firstIndex(of: $1.productionStage) ?? 0
                if a != b { return a < b }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }
        case .client:
            return rows.sorted {
                let a = $0.clientName ?? "~", b = $1.clientName ?? "~"
                return a == b ? $0.updatedAt > $1.updatedAt : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        case .date:
            return rows.sorted {
                switch ($0.scheduledAt, $1.scheduledAt) {
                case let (a?, b?): return a == b ? $0.updatedAt > $1.updatedAt : a < b
                case (nil, _?): return false
                case (_?, nil): return true
                default: return $0.updatedAt > $1.updatedAt
                }
            }
        }
    }
}

struct PipelineListView: View {
    let model: PipelinePageModel
    let sort: PipelineLedgerSort
    @Binding var selection: Set<String>
    @Binding var selectionAnchor: String?
    @Binding var cursorID: String?
    let onOpen: (PipelineContentItem) -> Void
    let onOpenAsPane: (PipelineContentItem) -> Void
    let onQuickLook: (String) -> Void
    var compact = false

    private var rows: [PipelineContentItem] { sort.sort(model.listRows) }

    var body: some View {
        if rows.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: DS.space8) {
                CosmoSectionHeader(label: model.filters.showArchived ? "ARCHIVED" : "IN MOTION", detail: "\(rows.count)") { EmptyView() }
                container
            }
        }
    }

    private var container: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                PipelineLedgerRow(
                    item: item,
                    sessionDay: model.sessionDaysByContent[item.id],
                    perf: model.perfByContent[item.id],
                    isSelected: selection.contains(item.id),
                    isCursor: cursorID == item.id,
                    isLast: index == rows.count - 1,
                    clients: model.clients,
                    onSelect: { select(item.id) },
                    onOpen: { onOpen(item) },
                    onQuickLook: { onQuickLook(item.id) },
                    actions: actions(for: item),
                    compact: compact
                )
            }
        }
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5)
        )
        .clipShape(.rect(cornerRadius: 12))
    }

    private var emptyState: some View {
        IdeasEmptyState(
            icon: "rectangle.split.3x1",
            headline: model.filters.showArchived ? "Nothing archived" : "Nothing in motion",
            teachingLine: model.filters.showArchived
                ? "Archived pieces rest here, out of every column."
                : "Begin writing from an idea, or press ⌘N to start a piece from scratch."
        )
    }

    /// Finder selection: click selects, ⌘ toggles, ⇧ extends from the anchor.
    private func select(_ id: String) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        withAnimation(ProMotionSprings.snappy) {
            if flags.contains(.command) {
                if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                selectionAnchor = id
            } else if flags.contains(.shift), let anchor = selectionAnchor,
                      let a = rows.firstIndex(where: { $0.id == anchor }),
                      let b = rows.firstIndex(where: { $0.id == id }) {
                for row in rows[min(a, b)...max(a, b)] { selection.insert(row.id) }
            } else {
                selection = [id]
                selectionAnchor = id
            }
            cursorID = id
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
            ship: { Task { model.pendingShip = try? await AtomRepository.shared.fetch(uuid: item.id) } },
            logPerformance: { Task { model.pendingPerf = try? await AtomRepository.shared.fetch(uuid: item.id) } },
            archive: { model.archive([item.id]) },
            restore: { model.restore(item.id) }
        )
    }
}

// MARK: - Row

private struct PipelineLedgerRow: View {
    let item: PipelineContentItem
    let sessionDay: Date?
    let perf: ContentPerfSnapshot?
    let isSelected: Bool
    let isCursor: Bool
    let isLast: Bool
    let clients: [PipelineClient]
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onQuickLook: () -> Void
    let actions: PipelineCardActions
    var compact = false

    @State private var isHovered = false

    private var clientTint: Color { item.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted }

    var body: some View {
        HStack(spacing: DS.space12) {
            stageGlyph
            VStack(alignment: .leading, spacing: DS.space4) {
            Text(item.atom.title?.isEmpty == false ? item.atom.title! : "Untitled")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(item.phase == .archived ? DS.textSecondary : DS.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if compact {
                Text([item.productionStage.title, item.clientName, item.scheduledAt.map { $0.formatted(.dateTime.month(.abbreviated).day()) }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(DS.caption2).foregroundStyle(DS.textMuted).lineLimit(1)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact, let clientName = item.clientName {
                HStack(spacing: DS.space4) {
                    Circle().fill(clientTint).frame(width: 6, height: 6)
                    Text(clientName)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.space8)
            if !compact {
            ZStack(alignment: .trailing) {
                trailingMeta.opacity(isHovered ? 0 : 1)
                hoverVerbs.opacity(isHovered ? 1 : 0)
            }
            .animation(ProMotionSprings.hover, value: isHovered)
            }
        }
        .padding(.horizontal, DS.space12)
        .frame(height: compact ? 60 : 44)
        .contentShape(.rect)
        .background(rowWash)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DS.palette.sepiaBorder.opacity(0.6))
                    .frame(height: 0.5)
                    .padding(.leading, 42)
            }
        }
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .onDrag {
            ShelfDragSession.shared.begin(color: clientTint)
            return NSItemProvider(object: PipelineDropPayload.content(item.id).dragString as NSString)
        }
        .contextMenu { PipelineCardMenu(item: item, clients: clients, actions: actions) }
        .help("\(item.atom.title ?? "Untitled") — click selects, double-click opens, Space previews")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.atom.title ?? "Untitled"), \(item.productionStage.title)\(item.clientName.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: "Preview") { onQuickLook() }
    }

    @ViewBuilder
    private var rowWash: some View {
        if isSelected {
            DS.entityContent.opacity(0.10)
        } else if isCursor {
            DS.glassSectionFill
        } else if isHovered {
            DS.glassSectionFill.opacity(0.5)
        } else {
            Color.clear
        }
    }

    private var stageGlyph: some View {
        Image(systemName: item.productionStage.icon)
            .font(DS.caption.weight(.medium))
            .foregroundStyle(item.phase.isShipped ? DS.entityContent.opacity(0.8) : DS.textMuted)
            .frame(width: 18)
            .help(item.productionStage.title)
            .accessibilityHidden(true)
    }

    private var trailingMeta: some View {
        HStack(spacing: DS.space8) {
            if let platform = item.platform {
                PlatformBrandMark(platform: platform.rawValue, size: 10)
            }
            Text(item.productionStage.title)
                .font(DS.caption2.weight(.medium))
                .foregroundStyle(DS.textSecondary)
            if let day = item.scheduledAt {
                Text(PipelinePageModel.dayLabel(day))
                    .font(DS.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
            } else if let perf {
                Text("\(PipelineBoardCard.compact(perf.views)) views")
                    .font(DS.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
            }
            if sessionDay != nil {
                Image(systemName: "calendar")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .help("Writing session booked")
            }
            Text(item.updatedAt.cosmoCompactAge)
                .font(DS.caption2)
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
        }
    }

    private var hoverVerbs: some View {
        HStack(spacing: DS.space6) {
            verb("eye", "Preview (Space)") { onQuickLook() }
            verb("calendar.badge.plus", item.scheduledAt == nil ? "Plan publication…" : "Change publication date…") { actions.schedule() }
            verb("arrow.up.right.square", "Open") { onOpen() }
        }
    }

    private func verb(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, height: 22)
                .background(DS.glassSectionFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Bulk bar (floats over the selection)

struct PipelineBulkBar: View {
    let count: Int
    let clients: [PipelineClient]
    let onMove: (ContentProductionStage) -> Void
    let onSchedule: () -> Void
    let onAssign: (String?) -> Void
    let onArchive: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: DS.space10) {
            Text("\(count) selected")
                .font(DS.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.text)
            Divider().frame(height: 16)
            Menu {
                ForEach(ContentProductionStage.allCases.filter { $0 != .published }) { phase in
                    Button(phase.title) { onMove(phase) }
                }
            } label: { Label("Move", systemImage: "arrow.right.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            Button { onSchedule() } label: { Label("Schedule", systemImage: "calendar.badge.plus") }
                .buttonStyle(.plain)
            Menu {
                ForEach(clients) { client in Button(client.name) { onAssign(client.uuid) } }
                Divider()
                Button("No client") { onAssign(nil) }
            } label: { Label("Assign", systemImage: "person.crop.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            Button { onArchive() } label: { Label("Archive", systemImage: "archivebox") }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: [])
            Button { onClear() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Clear selection (Esc)")
                .accessibilityLabel("Clear selection")
        }
        .font(DS.callout)
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, DS.space16)
        .frame(height: 44)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
        .padding(.bottom, DS.space24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
