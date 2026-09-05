// CosmoOS/UI/Pipeline/PipelineBoardCard.swift
// The board's card: a management object (sans title), a client tick, the
// meta the stage cares about, a session chip, and ONE context menu. Hover
// verbs swap in over the meta by opacity — never inserted views. The card is
// a drag source for the shared "content:<uuid>" wire format, so it lands on
// calendar days and other columns without adapters.

import SwiftUI

struct PipelineCardActions {
    var open: () -> Void = {}
    var openAsPane: () -> Void = {}
    var quickLook: () -> Void = {}
    var move: (ContentProductionStage) -> Void = { _ in }
    var schedule: () -> Void = {}
    var unschedule: () -> Void = {}
    var bookSession: (Date) -> Void = { _ in }
    var assignClient: (String?) -> Void = { _ in }
    var ship: () -> Void = {}
    var logPerformance: () -> Void = {}
    var archive: () -> Void = {}
    var restore: () -> Void = {}
}

struct PipelineBoardCard: View {
    let card: PipelineBoardSnapshot.ContentCard
    let column: PipelineBoardSnapshot.Column
    let isCursor: Bool
    let clients: [PipelineClient]
    let actions: PipelineCardActions

    @State private var isHovered = false

    private var item: PipelineContentItem { card.item }
    private var clientTint: Color {
        item.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            if let cover = item.coverPath { coverImage(cover) }
            HStack(alignment: .top, spacing: DS.space8) {
                tick
                Text(item.atom.title?.isEmpty == false ? item.atom.title! : "Untitled")
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                badge
            }
            ZStack(alignment: .leading) {
                meta.opacity(isHovered ? 0 : 1)
                hoverVerbs.opacity(isHovered ? 1 : 0)
            }
            .animation(ProMotionSprings.hover, value: isHovered)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        // A piece is a document, so the card is paper — never a tinted wall.
        // A missed date speaks through the date itself.
        .background(DS.documentSurface, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .strokeBorder(isCursor ? DS.accent.opacity(0.55) : DS.palette.sepiaBorder, lineWidth: isCursor ? 1 : 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 6 : 3, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .contentShape(.rect(cornerRadius: DS.radiusMedium))
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { actions.open() }
        .onDrag {
            ShelfDragSession.shared.begin(color: clientTint)
            return NSItemProvider(object: PipelineDropPayload.content(item.id).dragString as NSString)
        }
        .contextMenu { PipelineCardMenu(item: item, clients: clients, actions: actions) }
        .help("\(item.atom.title ?? "Untitled") — double-click opens, Space previews")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(isCursor ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { actions.open() }
    }

    /// Media routed onto the piece rides the top of the card, edge to edge.
    private func coverImage(_ path: String) -> some View {
        LocalFileThumbnail(path: path, maxPixelSize: 640) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            DS.glassSectionFill
        }
        .frame(height: 88)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: DS.radiusSmall))
        .accessibilityHidden(true)
    }

    private var tick: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(clientTint)
            .frame(width: 3, height: 18)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var badge: some View {
        if item.phase == .analyzing {
            Text("analyzing")
                .font(DS.caption2.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space6)
                .padding(.vertical, 2)
                .background(DS.glassSectionFill, in: .capsule)
        }
    }

    /// What the stage cares about: words while drafting, the date once
    /// scheduled, the numbers once shipped.
    private var meta: some View {
        HStack(spacing: DS.space6) {
            if let format = item.format.flatMap(ContentFormat.init(rawValue:)) {
                Text(CollectionEmoji.formatMark(format)).font(DS.caption2)
            }
            if let platform = item.platform {
                PlatformBrandMark(platform: platform.rawValue, size: 10)
            }
            Text(stageMeta)
                .font(DS.caption2)
                .monospacedDigit()
                .foregroundStyle(card.isMissed ? DS.red : DS.textMuted)
                .lineLimit(1)
            if let day = card.sessionDay {
                sessionChip(day)
            }
        }
    }

    private var stageMeta: String {
        switch column {
        case .notStarted, .inProgress, .review, .ready:
            let words = item.wordCount > 0 ? "\(item.wordCount)w" : item.updatedAt.cosmoCompactAge
            if let day = item.scheduledAt { return "\(words) · Planned \(PipelinePageModel.dayLabel(day))" }
            return words
        case .shipped:
            if let perf = card.perf { return "\(Self.compact(perf.views)) views" }
            if let published = item.latestPublish { return published.publishedAtDate.formatted(.dateTime.month(.abbreviated).day()) }
            return "shipped"
        }
    }

    private func sessionChip(_ day: Date) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(DS.caption2)
                .accessibilityHidden(true)
            Text(PipelinePageModel.dayLabel(day))
                .font(DS.caption2.weight(.medium))
        }
        .foregroundStyle(DS.textSecondary)
        .help("Writing session booked")
    }

    private var hoverVerbs: some View {
        HStack(spacing: DS.space6) {
            verb("arrow.up.right.square", "Open") { actions.open() }
            verb("eye", "Preview (Space)") { actions.quickLook() }
            if column != .shipped {
                verb("calendar.badge.plus", item.scheduledAt == nil ? "Plan publication…" : "Change publication date…") { actions.schedule() }
            } else {
                verb("chart.bar", "Log performance…") { actions.logPerformance() }
            }
        }
    }

    private func verb(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 24, height: 20)
                .background(DS.glassSectionFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var accessibilitySummary: String {
        var parts = [item.atom.title ?? "Untitled", column.title]
        if let clientName = item.clientName { parts.append(clientName) }
        parts.append(stageMeta)
        return parts.joined(separator: ", ")
    }

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fm", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

// MARK: - The one context menu

struct PipelineCardMenu: View {
    let item: PipelineContentItem
    let clients: [PipelineClient]
    let actions: PipelineCardActions

    var body: some View {
        Button { actions.open() } label: { Label("Open", systemImage: "arrow.up.right.square") }
        Button { actions.openAsPane() } label: { Label("Open in New Pane", systemImage: "rectangle.split.2x1") }
        Divider()
        if item.phase == .archived {
            Button("Restore to Content", systemImage: "arrow.uturn.backward", action: actions.restore)
        }
        Menu {
            ForEach(ContentProductionStage.allCases.filter { $0 != .published }) { phase in
                Button { actions.move(phase) } label: {
                    if phase == item.productionStage {
                        Label(phase.title, systemImage: "checkmark")
                    } else {
                        Label(phase.title, systemImage: phase.icon)
                    }
                }
                .disabled(phase == item.productionStage && item.phase != .archived)
            }
        } label: { Label("Move to Stage", systemImage: "arrow.right.circle") }
        Button { actions.schedule() } label: {
            Label(item.scheduledAt == nil ? "Plan publication…" : "Change publication date…", systemImage: "calendar.badge.plus")
        }
        if item.scheduledAt != nil {
            Button { actions.unschedule() } label: { Label("Remove publication date", systemImage: "calendar.badge.minus") }
        }
        Menu {
            ForEach(quickSessionDays, id: \.day) { entry in
                Button { actions.bookSession(entry.day) } label: { Text(entry.label) }
            }
        } label: { Label("Book Writing Session", systemImage: "pencil.and.list.clipboard") }
        Menu {
            ForEach(clients) { client in
                Button { actions.assignClient(client.uuid) } label: {
                    if client.uuid == item.clientUUID {
                        Label(client.name, systemImage: "checkmark")
                    } else {
                        Text(client.name)
                    }
                }
            }
            if !clients.isEmpty { Divider() }
            Button { actions.assignClient(nil) } label: { Text("No client") }
        } label: { Label("Assign Client", systemImage: "person.crop.circle") }
        Divider()
        Button { actions.ship() } label: { Label("Record publication…", systemImage: "paperplane") }
        Button { actions.logPerformance() } label: { Label("Log Performance…", systemImage: "chart.bar") }
        Divider()
        if item.phase != .archived {
            Button(role: .destructive) { actions.archive() } label: { Label("Archive", systemImage: "archivebox") }
        }
    }

    private var quickSessionDays: [(label: String, day: Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var days: [(String, Date)] = [("Today", today)]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) { days.append(("Tomorrow", tomorrow)) }
        for offset in 2...6 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                days.append((day.formatted(.dateTime.weekday(.wide)), day))
            }
        }
        return days
    }
}
