// Canvas/CommandCenter/ContentShelfRail.swift
// The Shelf: Upcoming's right rail while the Content lens is up. Every
// idea and unscheduled draft, searchable and scoped per client, each row
// draggable onto a calendar day to lock it in. The shelf is the composer —
// the calendar itself never grows a create button.
// July 2026

import SwiftUI
import GRDB

// MARK: - Shelf Models

struct ShelfClient: Identifiable, Equatable {
    let uuid: String
    let name: String

    var id: String { uuid }
    var color: Color { DS.clientColor(for: uuid) }
}

struct ShelfIdea: Identifiable, Equatable {
    let atom: Atom
    let clientUUID: String?
    let clientName: String?
    let format: String?
    /// Content atoms this idea has already spawned (lineage).
    let contentUUIDs: [String]

    var id: String { atom.uuid }
    var title: String { atom.title?.isEmpty == false ? atom.title! : "Untitled idea" }
    var color: Color {
        guard let clientUUID else { return DS.entityIdea }
        return DS.clientColor(for: clientUUID)
    }
}

// MARK: - Loader

enum ContentShelfLoader {
    static func loadClients() async -> [ShelfClient] {
        let atoms: [Atom] = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.clientProfile.rawValue)
                .filter(Column("is_deleted") == false)
                .order(Column("title").asc)
                .fetchAll(db)
        }) ?? []
        return atoms.compactMap { atom in
            guard let name = atom.title, !name.isEmpty else { return nil }
            return ShelfClient(uuid: atom.uuid, name: name)
        }
    }

    static func loadIdeas() async -> [ShelfIdea] {
        let atoms: [Atom] = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.idea.rawValue)
                .filter(Column("is_deleted") == false)
                .order(Column("updated_at").desc)
                .limit(400)
                .fetchAll(db)
        }) ?? []
        return atoms.map { atom in
            let meta = atom.metadataValue(as: IdeaMetadata.self)
            return ShelfIdea(
                atom: atom,
                clientUUID: meta?.clientUUID,
                clientName: meta?.clientName,
                format: meta?.contentFormat?.rawValue,
                contentUUIDs: meta?.contentUUIDs ?? []
            )
        }
    }
}

// MARK: - The Rail

struct ContentShelfRail: View {
    var viewModel: CommandCenterDashboardViewModel

    @State private var searchText = ""
    @State private var selectedClientUUID: String?
    @State private var clients: [ShelfClient] = []
    @State private var ideas: [ShelfIdea] = []
    @State private var drafts: [ContentQueueItem] = []
    /// Content uuids currently on the calendar — ideas whose lineage touches
    /// this set wear the "planned" tick and sink below fresh ideas.
    @State private var plannedContentUUIDs: Set<String> = []
    @State private var isLoading = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            railHeader
            searchField
            clientPills
            shelfList
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .contentShelfFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .contentCalendarNeedsReload)) { _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        clients = await ContentShelfLoader.loadClients()
        ideas = await ContentShelfLoader.loadIdeas()
        let allContent = await ContentQueueLoader.load()
        drafts = allContent.filter { $0.scheduledAt == nil && !$0.isPublished }
        plannedContentUUIDs = Set(
            allContent.filter { $0.scheduledAt != nil || $0.isPublished }.map(\.id)
        )
        isLoading = false
    }

    /// This idea already has a post on the calendar (or shipped).
    private func hasActivePlan(_ idea: ShelfIdea) -> Bool {
        idea.contentUUIDs.contains { plannedContentUUIDs.contains($0) }
    }

    // MARK: Header + Search + Pills

    private var railHeader: some View {
        HStack(spacing: DS.space6) {
            Text("SHELF")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text("\(filteredIdeas.count + filteredDrafts.count)")
                .font(DS.footnote.monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
        }
    }

    private var searchField: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "magnifyingglass")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            TextField("Search ideas & drafts", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 32)
        .dsGlassInput(isFocused: searchFocused, cornerRadius: 10)
    }

    private var clientPills: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.space6) {
                clientPill(nil, label: "All")
                ForEach(clients) { client in
                    clientPill(client.uuid, label: client.name, color: client.color)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func clientPill(_ uuid: String?, label: String, color: Color = DS.accent) -> some View {
        let isSelected = selectedClientUUID == uuid
        return Button {
            withAnimation(ProMotionSprings.snappy) {
                selectedClientUUID = uuid
            }
        } label: {
            HStack(spacing: DS.space4) {
                if uuid != nil {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(DS.caption)
                    .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.12) : Color.clear, in: Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected ? color.opacity(0.4) : DS.borderSubtle,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(uuid == nil ? "Everything on the shelf" : "Only \(label)'s ideas and drafts")
        .accessibilityLabel("\(label) filter")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Filtering

    private var searchTokens: [String] {
        searchText
            .split(separator: " ")
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    private func matches(_ haystack: String) -> Bool {
        let lowered = haystack.lowercased()
        return searchTokens.allSatisfy { lowered.contains($0) }
    }

    private var filteredIdeas: [ShelfIdea] {
        let matching = ideas.filter { idea in
            if let selectedClientUUID, idea.clientUUID != selectedClientUUID { return false }
            guard !searchTokens.isEmpty else { return true }
            return matches("\(idea.title) \(idea.clientName ?? "") \(idea.format ?? "")")
        }
        // Fresh ideas first; already-planned ones sink (still reachable —
        // a second drag is a deliberate re-use, not an accident). Loader
        // order (updated desc) holds within each band.
        return matching.filter { !hasActivePlan($0) } + matching.filter { hasActivePlan($0) }
    }

    private var filteredDrafts: [ContentQueueItem] {
        drafts.filter { draft in
            if let selectedClientUUID, draft.clientUUID != selectedClientUUID { return false }
            guard !searchTokens.isEmpty else { return true }
            return matches("\(draft.title) \(draft.clientName ?? "")")
        }
    }

    // MARK: List

    private var shelfList: some View {
        CosmoSlimScroll {
            LazyVStack(alignment: .leading, spacing: DS.space12) {
                if isLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.space16)
                } else if filteredIdeas.isEmpty && filteredDrafts.isEmpty {
                    shelfTeachingState
                } else {
                    draftsSection
                    ideasSection
                }
            }
            .padding(.trailing, DS.space8)
            .padding(.bottom, DS.space24)
        }
        // The symmetric gesture: drag a calendar chip back onto the shelf
        // to unschedule it — it returns to DRAFTS.
        .dropDestination(for: String.self) { payloads, _ in
            var handled = false
            for raw in payloads {
                if case .content(let uuid) = ContentShelfPayload(string: raw) {
                    handled = true
                    Task {
                        await ContentQueueLoader.setSchedule(nil, status: nil, for: uuid)
                        await reload()
                        NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
                    }
                }
            }
            return handled
        }
    }

    @ViewBuilder
    private var draftsSection: some View {
        if !filteredDrafts.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                sectionHeader("DRAFTS", count: filteredDrafts.count)
                ForEach(filteredDrafts) { draft in
                    ShelfRow(
                        title: draft.title,
                        detail: draft.clientName,
                        age: ISO8601.date(from: draft.atom.updatedAt)?.cosmoCompactAge,
                        color: draft.clientColor,
                        payload: .content(draft.id),
                        onOpen: { open(draft.atom.uuid) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var ideasSection: some View {
        if !filteredIdeas.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                sectionHeader("IDEAS", count: filteredIdeas.count)
                ForEach(filteredIdeas) { idea in
                    ShelfRow(
                        title: idea.title,
                        detail: idea.clientName,
                        age: ISO8601.date(from: idea.atom.updatedAt)?.cosmoCompactAge,
                        color: idea.color,
                        payload: .idea(idea.id),
                        isPlanned: hasActivePlan(idea),
                        onOpen: { open(idea.atom.uuid) }
                    )
                }
            }
        }
    }

    private func sectionHeader(_ label: String, count: Int) -> some View {
        HStack(spacing: DS.space6) {
            Text(label)
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text("\(count)")
                .font(DS.footnote.monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
        }
    }

    private var shelfTeachingState: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(searchTokens.isEmpty ? "The shelf is empty" : "No matches")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)
            Text(searchTokens.isEmpty
                ? "Capture ideas and they queue up here, ready to drag onto a day."
                : "Try fewer words — the shelf matches every word you type.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.space8)
    }

    private func open(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )
    }
}

// MARK: - Row

private struct ShelfRow: View {
    let title: String
    let detail: String?
    let age: String?
    let color: Color
    let payload: ContentShelfPayload
    var isPlanned: Bool = false
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: DS.space4) {
                    if isPlanned {
                        // This seed already has a post on the calendar —
                        // dragging again is a deliberate second use.
                        Image(systemName: "calendar.badge.checkmark")
                            .font(DS.caption2.weight(.semibold))
                            .imageScale(.small)
                            .foregroundStyle(color.opacity(0.8))
                            .help("Already planned — drag again to spawn another post from this idea")
                            .accessibilityLabel("Already has a planned post")
                    }
                    if let detail {
                        Text(detail)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                    if let age {
                        Text(age)
                            .font(DS.caption2.monospacedDigit())
                            .foregroundStyle(DS.textMuted.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Image(systemName: "line.3.horizontal")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(
            isHovered ? DS.surfaceHover.opacity(0.4) : Color.clear,
            in: .rect(cornerRadius: 8)
        )
        .contentShape(.rect(cornerRadius: 8))
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .onDrag {
            ShelfDragSession.shared.begin(color: color)
            return NSItemProvider(object: payload.dragString as NSString)
        }
        .help("Drag onto a calendar day to lock it in — or click to open")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
