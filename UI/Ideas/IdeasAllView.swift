// CosmoOS/UI/Ideas/IdeasAllView.swift
// All Ideas — the corpus as a Finder-grade management ledger (Phase 2 of the
// July 2026 Desk reinvention). One grouped container per client, 44pt rows,
// the small-caps ledger header voice, sort (Newest / Ripest / Oldest),
// status filters including the Archived shelf (where Pass sends things),
// Finder selection (click selects, ⌘ toggles, ⇧ ranges, double-click opens),
// hover verbs, and bulk assign/archive over the selection. Search results
// render here too — searching IS browsing.

import SwiftUI
import AppKit

// MARK: - Sort & filter vocabulary

enum IdeasLedgerSort: String, CaseIterable {
    case newest
    case ripest
    case oldest

    var label: String {
        switch self {
        case .newest: return "Newest"
        case .ripest: return "Ripest"
        case .oldest: return "Oldest"
        }
    }

    var help: String {
        switch self {
        case .newest: return "Most recently touched first"
        case .ripest: return "Most developed first (the desk's own ranking)"
        case .oldest: return "Oldest first — resurface the forgotten"
        }
    }
}

enum IdeasLedgerFilter: String, CaseIterable {
    case live
    case spark
    case developing
    case ready
    case archived

    var label: String {
        switch self {
        case .live: return "All"
        case .spark: return "Sparks"
        case .developing: return "Developing"
        case .ready: return "Ready"
        case .archived: return "Archived"
        }
    }

    func matches(_ idea: IdeaGalleryItem) -> Bool {
        switch self {
        case .live: return true
        case .spark: return idea.status == .spark
        case .developing: return idea.status == .developing
        case .ready: return idea.status == .ready
        case .archived: return idea.status == .archived
        }
    }
}

// MARK: - Section computation (one truth for the view AND the shell's cursor)

struct IdeasLedger {
    struct Section: Identifiable {
        let id: String
        let title: String
        let items: [IdeaGalleryItem]
    }

    /// The ledger's visible sections for the current scope/filter/sort.
    /// Search results collapse to one flat section (client shown per row).
    @MainActor
    static func sections(
        model: IdeasPageModel,
        scopedClientId: String?,
        filter: IdeasLedgerFilter,
        sort: IdeasLedgerSort,
        searchResults: [IdeaGalleryItem]?
    ) -> [Section] {
        if let searchResults {
            return searchResults.isEmpty ? [] : [Section(id: "__search__", title: "Results", items: searchResults)]
        }

        let corpus = filter == .archived ? model.archivedIdeas : model.ideas.filter(filter.matches)
        let knownClientIds = Set(model.assignableClients.map(\.uuid))
        var byClient: [String: [IdeaGalleryItem]] = [:]
        var unassigned: [IdeaGalleryItem] = []
        for idea in corpus {
            if let clientUUID = idea.clientUUID, knownClientIds.contains(clientUUID) {
                byClient[clientUUID, default: []].append(idea)
            } else {
                unassigned.append(idea)
            }
        }

        var sections: [Section] = model.assignableClients.compactMap { client in
            guard let items = byClient[client.uuid], !items.isEmpty else { return nil }
            return Section(id: client.uuid, title: client.name, items: sorted(items, by: sort, model: model))
        }
        if !unassigned.isEmpty {
            sections.append(Section(id: "__unassigned__", title: "Unassigned", items: sorted(unassigned, by: sort, model: model)))
        }
        if let scopedClientId {
            sections = sections.filter { $0.id == scopedClientId }
        }
        return sections
    }

    @MainActor
    private static func sorted(_ items: [IdeaGalleryItem], by sort: IdeasLedgerSort, model: IdeasPageModel) -> [IdeaGalleryItem] {
        switch sort {
        case .newest:
            return items.sorted { $0.updatedAt == $1.updatedAt ? $0.atomUUID < $1.atomUUID : $0.updatedAt > $1.updatedAt }
        case .oldest:
            return items.sorted { $0.updatedAt == $1.updatedAt ? $0.atomUUID < $1.atomUUID : $0.updatedAt < $1.updatedAt }
        case .ripest:
            // Scores are precomputed at load — sorting never parses a date.
            let scores = model.ripenessScores
            return items.sorted {
                let a = scores[$0.atomUUID] ?? 0
                let b = scores[$1.atomUUID] ?? 0
                if a != b { return a > b }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.atomUUID < $1.atomUUID
            }
        }
    }
}

// MARK: - Ledger view

struct IdeasAllView: View {
    let model: IdeasPageModel
    var scopedClientId: String?
    /// Non-nil = search mode: one flat Results section, client shown per row.
    var searchResults: [IdeaGalleryItem]?
    let filter: IdeasLedgerFilter
    let sort: IdeasLedgerSort
    @Binding var selection: Set<String>
    @Binding var selectionAnchor: String?
    @Binding var cursorID: String?
    let hasAppeared: Bool
    let onOpen: (IdeaGalleryItem) -> Void
    let onOpenAsPane: (IdeaGalleryItem) -> Void
    let onQuickLook: (IdeaGalleryItem) -> Void

    /// The reading measure — a ledger is a scan surface, not a wall.
    private static let ledgerMeasure: CGFloat = 760

    private var sections: [IdeasLedger.Section] {
        IdeasLedger.sections(
            model: model,
            scopedClientId: scopedClientId,
            filter: filter,
            sort: sort,
            searchResults: searchResults
        )
    }

    var body: some View {
        let sections = self.sections
        VStack(alignment: .leading, spacing: DS.space24) {
            if sections.isEmpty {
                emptyState
            } else {
                let flatOrder = sections.flatMap { $0.items.map(\.atomUUID) }
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    ledgerSection(section, flatOrder: flatOrder)
                        .cascadeIn(hasAppeared, index: min(index, 8))
                }
            }
        }
        .frame(maxWidth: Self.ledgerMeasure, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    // MARK: Sections

    private func ledgerSection(_ section: IdeasLedger.Section, flatOrder: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            CosmoSectionHeader(label: section.title, detail: "\(section.items.count)")
            // LAZY — a plain VStack constructs every row (gestures, tooltips,
            // thumbs) the moment the view mounts; hundreds of rows stall the
            // Desk⇄All switch and tax every body evaluation.
            LazyVStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.atomUUID) { index, idea in
                    IdeaLedgerRow(
                        idea: idea,
                        inspirationThumbs: model.inspirationThumbs[idea.atomUUID] ?? [],
                        showsClient: searchResults != nil,
                        clientTint: idea.clientUUID.map { DS.clientColor(for: $0) },
                        isSelected: selection.contains(idea.atomUUID),
                        isCursor: cursorID == idea.atomUUID,
                        isLast: index == section.items.count - 1,
                        selectionCount: selection.count,
                        actions: actions(for: idea),
                        selectedItems: { selectedItems() },
                        onSelect: { handleTap(idea, flatOrder: flatOrder) },
                        onOpen: { onOpen(idea) },
                        onQuickLook: { onQuickLook(idea) },
                        bulkAssign: { model.bulkAssign(selectedItems(), to: $0) },
                        bulkArchive: { model.bulkArchive(selectedItems()) }
                    )
                    .id(idea.atomUUID)
                }
            }
            .background(DS.surfaceElevated)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5)
            )
            .dsRestingShadow()
        }
    }

    // MARK: Selection (the Finder grammar)

    private func handleTap(_ idea: IdeaGalleryItem, flatOrder: [String]) {
        let id = idea.atomUUID
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        if mods.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            selectionAnchor = id
        } else if mods.contains(.shift),
                  let anchor = selectionAnchor,
                  let a = flatOrder.firstIndex(of: anchor),
                  let b = flatOrder.firstIndex(of: id) {
            selection = Set(flatOrder[min(a, b)...max(a, b)])
        } else {
            selection = [id]
            selectionAnchor = id
        }
        cursorID = id
    }

    /// The selection as items, ledger order (bulk verbs act on these).
    private func selectedItems() -> [IdeaGalleryItem] {
        sections.flatMap(\.items).filter { selection.contains($0.atomUUID) }
    }

    // MARK: Empty states (absence teaches)

    private var emptyState: some View {
        let (icon, headline, line): (String, String, String) = {
            if searchResults != nil {
                return ("magnifyingglass", "No ideas match", "Tokens match in any order — try fewer or different words.")
            }
            switch filter {
            case .archived:
                return ("archivebox", "Nothing archived", "Pass an idea on the desk and it rests here, recoverable forever.")
            case .ready:
                return ("checkmark.seal", "Nothing marked ready", "Ripen an idea in its bench — or set status right from a card's menu.")
            case .developing:
                return ("hammer", "Nothing in development", "Open a spark and start shaping it; it moves here on its own.")
            case .spark:
                return ("sparkles", "No raw sparks", "Every capture starts as a spark — ⌘N or spin one out of a swipe.")
            case .live:
                return ("lightbulb", "Nothing here yet", "Capture an idea with ⌘N, or open a swipe and spin one out of it.")
            }
        }()
        return IdeasEmptyState(icon: icon, headline: headline, teachingLine: line)
    }

    // MARK: Plumbing

    private func actions(for idea: IdeaGalleryItem) -> IdeaDeskActions {
        IdeaDeskActions(
            open: { onOpen(idea) },
            openAsPane: { onOpenAsPane(idea) },
            togglePin: { model.togglePin(idea) },
            pass: { model.pass(idea) },
            setStatus: { model.setStatus(idea, to: $0) },
            assignClient: { model.assignClient(idea, to: $0) },
            schedule: { model.scheduleDevelopment(idea, on: $0) },
            delete: { model.deferDelete(idea) },
            dropSwipe: { model.linkSwipe(uuid: $0, toIdea: idea.atomUUID) },
            assignableClients: model.assignableClients
        )
    }
}

// MARK: - Row (44pt, one line, honest marks)

private struct IdeaLedgerRow: View {
    let idea: IdeaGalleryItem
    var inspirationThumbs: [String] = []
    var showsClient = false
    var clientTint: Color?
    let isSelected: Bool
    let isCursor: Bool
    let isLast: Bool
    /// Live selection size — >1 flips the context menu to bulk verbs.
    let selectionCount: Int
    let actions: IdeaDeskActions
    let selectedItems: () -> [IdeaGalleryItem]
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onQuickLook: () -> Void
    let bulkAssign: (String) -> Void
    let bulkArchive: () -> Void

    @State private var isHovered = false

    private var isArchived: Bool { idea.status == .archived }

    private var headline: String {
        if let hook = idea.hooks.first, !hook.isEmpty { return hook }
        return idea.title
    }

    var body: some View {
        HStack(spacing: DS.space12) {
            statusGlyph
            Text(headline)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(isArchived ? DS.textSecondary : DS.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if showsClient, let clientName = idea.clientName {
                HStack(spacing: DS.space4) {
                    Circle()
                        .fill(clientTint ?? DS.textMuted)
                        .frame(width: 6, height: 6)
                    Text(clientName)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.space8)
            // Verbs swap in over the meta on hover (opacity, never layout —
            // a row that reflows under the pointer reads as jank).
            ZStack(alignment: .trailing) {
                trailingMeta
                    .opacity(isHovered ? 0 : 1)
                hoverVerbs
                    .opacity(isHovered ? 1 : 0)
            }
            .animation(ProMotionSprings.hover, value: isHovered)
            if !inspirationThumbs.isEmpty {
                IdeaInspirationThumb(
                    candidates: inspirationThumbs,
                    hairline: DS.palette.sepiaBorder,
                    width: 28,
                    height: 36
                )
            }
        }
        .padding(.horizontal, DS.space12)
        .frame(height: 44)
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
        .contextMenu { rowMenu }
        .help("\(headline) — click selects, double-click opens, Space previews")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: "Preview") { onQuickLook() }
    }

    /// Selection is the one wash; the keyboard cursor alone is a whisper.
    @ViewBuilder
    private var rowWash: some View {
        if isSelected {
            DS.entityIdea.opacity(0.10)
        } else if isCursor {
            DS.glassSectionFill
        } else if isHovered {
            DS.glassSectionFill.opacity(0.5)
        } else {
            Color.clear
        }
    }

    private var statusGlyph: some View {
        Image(systemName: idea.status.iconName)
            .font(DS.caption.weight(.medium))
            .foregroundStyle(
                idea.status == .ready ? DS.entityIdea.opacity(0.8) : DS.textMuted
            )
            .frame(width: 18)
            .help(idea.status.displayName)
            .accessibilityHidden(true)
    }

    private var trailingMeta: some View {
        HStack(spacing: DS.space6) {
            if let format = idea.contentFormat {
                Text(CollectionEmoji.formatMark(format))
                    .font(.system(size: 11))
            }
            if let family = platformFamily {
                SwipePlatformGlyph(source: family)
                    .frame(width: 9, height: 9)
            }
            Text(ageText)
                .font(DS.caption2)
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private var hoverVerbs: some View {
        HStack(spacing: DS.space6) {
            if isArchived {
                DeskVerbButton(
                    systemName: "arrow.uturn.backward",
                    help: "Restore to Sparks",
                    action: { actions.setStatus(.spark) }
                )
            } else {
                DeskVerbButton(
                    systemName: idea.isPinned ? "pin.slash" : "pin",
                    help: idea.isPinned ? "Remove from Up Next" : "Move Up Next (P)",
                    action: actions.togglePin
                )
                DeskVerbButton(
                    systemName: "archivebox",
                    help: "Pass — archive this idea",
                    action: actions.pass
                )
            }
        }
        .accessibilityHidden(!isHovered)
    }

    /// One menu per row: bulk verbs when the row belongs to a multi-selection
    /// (Finder acts on the selection), single-row verbs otherwise.
    @ViewBuilder
    private var rowMenu: some View {
        if selectionCount > 1, isSelected {
            let count = selectionCount
            if !actions.assignableClients.isEmpty {
                Menu("Assign \(count) to Client") {
                    ForEach(actions.assignableClients, id: \.uuid) { client in
                        Button(client.name) { bulkAssign(client.uuid) }
                    }
                }
            }
            Button {
                bulkArchive()
            } label: {
                Label("Archive \(count) Ideas", systemImage: "archivebox")
            }
        } else if isArchived {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button(action: actions.openAsPane) {
                Label("Open in New Pane", systemImage: "rectangle.split.2x1")
            }
            Divider()
            Button {
                actions.setStatus(.spark)
            } label: {
                Label("Restore to Sparks", systemImage: "arrow.uturn.backward")
            }
            Divider()
            Button(role: .destructive, action: actions.delete) {
                Label("Delete Idea", systemImage: "trash")
            }
        } else {
            IdeaDeskMenu(idea: idea, actions: actions)
        }
    }

    private var platformFamily: String? {
        guard let raw = idea.platform?.rawValue else { return nil }
        return raw == "x" ? "x_post" : raw
    }

    private var ageText: String {
        guard let date = ISO8601.date(from: idea.updatedAt) else { return "" }
        return date.cosmoCompactAge
    }

    private var accessibilitySummary: String {
        var parts = [headline, idea.status.displayName]
        if showsClient, let client = idea.clientName { parts.append(client) }
        return parts.joined(separator: ", ")
    }
}
