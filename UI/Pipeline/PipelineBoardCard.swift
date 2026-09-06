// CosmoOS/UI/Pipeline/PipelineBoardCard.swift
// The board's card: a management object (sans title), a client tick, the
// meta the stage cares about, a session chip, and ONE context menu. Hover
// verbs swap in over the meta by opacity — never inserted views. The card is
// a drag source for the shared "content:<uuid>" wire format, so it lands on
// calendar days and other columns without adapters.
//
// Split (September 2026): the shell owns chrome and manners (surface,
// hairline, lift, gestures, drag, menu); the face owns what the card says.
// Both bodies stay short, and a column re-render touches only the mounted
// dozen — the viewport column keeps the rest unmounted.

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
    var export: () -> Void = {}
    var logPerformance: () -> Void = {}
    var archive: () -> Void = {}
    var restore: () -> Void = {}
    /// Board-only: a shipped piece leaves the Published column and nothing else.
    var clearFromBoard: () -> Void = {}
    var returnToBoard: () -> Void = {}
}

struct PipelineBoardCard: View {
    let card: PipelineBoardSnapshot.ContentCard
    let column: PipelineBoardSnapshot.Column
    let isCursor: Bool
    /// Name the client on the card — only when the board mixes owners.
    var showsClient = false
    let clients: [PipelineClient]
    let actions: PipelineCardActions
    var isSelected = false
    var selectionCount = 0
    var onSelect: () -> Void = {}
    /// The wire payload for a drag from this card — the whole selection when
    /// the card is part of one, so one gesture moves every chosen piece.
    var dragString: () -> String = { "" }

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: PipelineContentItem { card.item }
    private var clientTint: Color {
        item.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted
    }

    var body: some View {
        PipelineCardFace(card: card, column: column, showsClient: showsClient, isHovered: isHovered, actions: actions)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .modifier(PipelineCardChrome(isCursor: isCursor, isSelected: isSelected, isHovered: isHovered, isCleared: item.isClearedFromBoard))
            .contentShape(.rect(cornerRadius: DS.radiusMedium))
            .onHover { isHovered = $0 }
            // Finder manners: click selects (⌘ toggles, ⇧ ranges), double-click opens.
            .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
            .simultaneousGesture(TapGesture(count: 2).onEnded { actions.open() })
            .onDrag {
                ShelfDragSession.shared.begin(color: clientTint)
                let payload = dragString()
                return NSItemProvider(object: (payload.isEmpty ? PipelineDropPayload.content(item.id).dragString : payload) as NSString)
            } preview: {
                PipelineDragPreview(title: item.title, count: isSelected ? max(1, selectionCount) : 1, tint: clientTint)
            }
            .contextMenu { PipelineCardMenu(item: item, clients: clients, actions: actions) }
            .help("\(item.title) — double-click opens, Space previews")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(isCursor || isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { actions.open() }
            .accessibilityAction(named: "Select") { onSelect() }
    }

    private var accessibilitySummary: String {
        var parts = [item.title, column.title]
        if let clientName = item.clientName { parts.append(clientName) }
        parts.append(PipelineCardFace.stageMeta(for: card, in: column))
        if item.isClearedFromBoard { parts.append("cleared from the board") }
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

// MARK: - Chrome

/// A management object wears the theme's elevated surface (the Ideas card's
/// exact chrome) — never paper: documentSurface stays white in every dark
/// palette while DS.text flips light. Constant structure: every state is a
/// value, so hover, selection and the cursor ring all interpolate.
private struct PipelineCardChrome: ViewModifier {
    let isCursor: Bool
    let isSelected: Bool
    let isHovered: Bool
    let isCleared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(isSelected ? DS.accentSoft.opacity(0.6) : DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .strokeBorder(isCursor ? DS.focusRing : (isSelected ? DS.accent.opacity(0.5) : DS.commandChromeBorder),
                                  lineWidth: isCursor || isSelected ? 1.5 : 0.75)
            )
            .shadow(color: DS.text.opacity(isHovered ? 0.07 : 0.025), radius: isHovered ? 8 : 3, y: isHovered ? 3 : 1)
            .offset(y: isHovered && !reduceMotion ? -1 : 0)
            .opacity(isCleared ? 0.62 : 1)
            .animation(ProMotionSprings.hover, value: isSelected)
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isHovered)
    }
}

// MARK: - Face

/// What the card says: cover, tick, title, badge, then the meta the stage
/// cares about — words while drafting, the date once shipped, the numbers
/// once logged. Hover verbs swap in over the meta by opacity.
struct PipelineCardFace: View {
    let card: PipelineBoardSnapshot.ContentCard
    let column: PipelineBoardSnapshot.Column
    var showsClient = false
    let isHovered: Bool
    let actions: PipelineCardActions

    private var item: PipelineContentItem { card.item }
    private var clientTint: Color {
        item.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            if let cover = item.coverPath { coverImage(cover) }
            HStack(alignment: .top, spacing: DS.space8) {
                tick
                Text(item.title)
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
        if item.isClearedFromBoard {
            pill("cleared", icon: "tray")
        } else if item.phase == .analyzing {
            pill("analyzing", icon: nil)
        }
    }

    private func pill(_ word: String, icon: String?) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(DS.caption2.weight(.medium))
                    .accessibilityHidden(true)
            }
            Text(word)
                .font(DS.caption2.weight(.medium))
        }
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, DS.space6)
        .padding(.vertical, 2)
        .background(DS.glassSectionFill, in: .capsule)
    }

    private var meta: some View {
        HStack(spacing: DS.space6) {
            if let format = item.contentFormat {
                Text(CollectionEmoji.formatMark(format)).font(DS.caption2)
            }
            if let platform = item.platform {
                PlatformBrandMark(platform: platform.rawValue, size: 10)
            }
            Text(Self.stageMeta(for: card, in: column))
                .font(DS.caption2)
                .monospacedDigit()
                .foregroundStyle(card.isMissed ? DS.red : DS.textMuted)
                .lineLimit(1)
            if showsClient, let clientName = item.clientName {
                Text("·").font(DS.caption2).foregroundStyle(DS.textMuted)
                Text(clientName)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let day = card.sessionDay {
                sessionChip(day)
            }
        }
    }

    /// What the stage cares about: words while drafting, the date once
    /// scheduled, the numbers once shipped.
    static func stageMeta(for card: PipelineBoardSnapshot.ContentCard, in column: PipelineBoardSnapshot.Column) -> String {
        let item = card.item
        switch column {
        case .notStarted, .inProgress, .review, .ready:
            let words = item.wordCount > 0 ? "\(item.wordCount)w" : item.updatedAt.cosmoCompactAge
            if let day = item.scheduledAt { return "\(words) · Planned \(PipelinePageModel.dayLabel(day))" }
            return words
        case .shipped:
            if let perf = card.perf { return "\(PipelineBoardCard.compact(perf.views)) views" }
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
                verb("square.and.arrow.up", "Export… (⌘E)") { actions.export() }
            } else {
                verb("chart.bar", "Log performance…") { actions.logPerformance() }
                if item.isClearedFromBoard {
                    verb("tray.and.arrow.up", "Return to board") { actions.returnToBoard() }
                } else {
                    verb("tray.and.arrow.down", "Clear from board — stays in List, Calendar and search") { actions.clearFromBoard() }
                }
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
        stageMenu
        Button { actions.schedule() } label: {
            Label(item.scheduledAt == nil ? "Plan publication…" : "Change publication date…", systemImage: "calendar.badge.plus")
        }
        if item.scheduledAt != nil {
            Button { actions.unschedule() } label: { Label("Remove publication date", systemImage: "calendar.badge.minus") }
        }
        sessionMenu
        clientMenu
        Divider()
        Button { actions.export() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
        if !item.isShipped {
            Button { actions.move(.published) } label: { Label("Mark Published", systemImage: "paperplane") }
        }
        Button { actions.logPerformance() } label: { Label("Log Performance…", systemImage: "chart.bar") }
        Divider()
        removalItems
    }

    private var stageMenu: some View {
        Menu {
            ForEach(ContentProductionStage.allCases) { phase in
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
    }

    private var sessionMenu: some View {
        Menu {
            ForEach(quickSessionDays, id: \.day) { entry in
                Button { actions.bookSession(entry.day) } label: { Text(entry.label) }
            }
        } label: { Label("Book Writing Session", systemImage: "pencil.and.list.clipboard") }
    }

    private var clientMenu: some View {
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
    }

    /// Two ways off the board, in order of weight: a shipped piece is CLEARED
    /// (the ledger, the calendar and search keep it); anything can be archived.
    @ViewBuilder
    private var removalItems: some View {
        if item.isShipped, item.phase != .archived {
            if item.isClearedFromBoard {
                Button("Return to Board", systemImage: "tray.and.arrow.up", action: actions.returnToBoard)
            } else {
                Button("Clear from Board", systemImage: "tray.and.arrow.down", action: actions.clearFromBoard)
            }
        }
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

// MARK: - Drag preview

/// What the pointer carries: the piece's name on its paper and, for a
/// multi-select, a count badge with a second sheet peeking out behind.
struct PipelineDragPreview: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            if count > 1 {
                sheet.opacity(0.75).offset(x: 6, y: 6)
            }
            HStack(spacing: DS.space8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: 3, height: 18)
                Text(title)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if count > 1 {
                    Text("\(count)")
                        .font(DS.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, DS.space8)
                        .frame(height: 20)
                        .background(DS.accent, in: .capsule)
                }
            }
            .padding(.horizontal, DS.space10)
            .frame(width: 240, height: 44)
            .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .strokeBorder(DS.commandChromeBorder, lineWidth: 0.75)
            )
            .shadow(color: DS.text.opacity(0.12), radius: 10, y: 4)
        }
        .padding(DS.space8)
        .accessibilityLabel(count > 1 ? "\(count) pieces" : title)
    }

    private var sheet: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .fill(DS.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .strokeBorder(DS.commandChromeBorder, lineWidth: 0.75)
            )
            .frame(width: 240, height: 44)
    }
}
