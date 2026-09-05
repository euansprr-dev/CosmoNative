// Canvas/CommandCenter/IdeaWorkShelfRail.swift
// July 2026 — The Shelf on Upcoming's SCHEDULE lens.
//
// The Content lens' shelf answers "when does this go out". This one answers the
// question the app could never answer: "when do I sit down and make it". Rows
// are unscheduled ideas ranked by the Ideas Desk's own engine, dragged onto the
// week board to book a real writing session.
//
// The two calendars talk: an idea whose content already has a publish date wears
// it, and one publishing soon with nothing booked to write it rides a lane of
// its own — the gap that actually bites.

import SwiftUI
import GRDB

// MARK: - Row model

/// One shelf row, fully derived at load. Nothing here is computed in a view
/// body — score parses two ISO dates per item, and a rail that recomputed it
/// per scroll frame would crawl.
struct WorkShelfIdea: Identifiable, Equatable {
    let atomUUID: String
    let title: String
    let clientUUID: String?
    let clientName: String?
    let updatedAt: String
    /// The Desk's ranking and its one-line reason.
    let score: Double
    let whyLine: String
    /// The day an OPEN development session is already booked for, if any.
    let bookedDay: Date?
    /// The soonest publish date across this idea's content lineage, if any.
    let publishDay: Date?

    var id: String { atomUUID }
    var color: Color {
        guard let clientUUID else { return DS.entityIdea }
        return DS.clientColor(for: clientUUID)
    }

    /// Publishing within the horizon with no session booked to write it.
    func isPublishingSoon(now: Date, horizonDays: Int, calendar: Calendar) -> Bool {
        guard bookedDay == nil, let publishDay else { return false }
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: calendar.startOfDay(for: now)) else {
            return false
        }
        return publishDay < horizon
    }
}

// MARK: - Loader

enum IdeaWorkShelfLoader {
    /// How far ahead a publish date counts as "soon".
    static let publishHorizonDays = 14

    static func load(now: Date = .now, calendar: Calendar = .current) async -> [WorkShelfIdea] {
        let shelfIdeas = await ContentShelfLoader.loadIdeas()

        // Activated ideas are content pieces now (the Ideas boards drop them for
        // the same reason) — their work belongs to the draft, not the seed.
        let live = shelfIdeas.filter { $0.atom.ideaMetadata?.ideaStatus != .archived }

        // "Came from a saved swipe", from metadata alone. The Desk derives this
        // while resolving thumbnails (one fetch per swipe); for SCORING only the
        // key set matters, so the rail reads the link fields directly and stays
        // query-free.
        let inspiration = Set(live.compactMap { idea -> String? in
            let meta = idea.atom.ideaMetadata
            let hasSwipe = meta?.linkedSwipeIds?.first
                ?? meta?.originSwipeUUID
                ?? meta?.supportingSwipeUUIDs?.first
            return hasSwipe == nil ? nil : idea.atom.uuid
        })

        async let bookedDaysTask = openSessionDays()
        async let publishDaysTask = publishDays()
        let bookedDays = await bookedDaysTask
        let publishByContent = await publishDaysTask

        return live.compactMap { shelf -> WorkShelfIdea? in
            guard let item = shelf.atom.toIdeaGalleryItem(clientName: shelf.clientName) else { return nil }
            let publish = shelf.contentUUIDs
                .compactMap { publishByContent[$0] }
                .min()
            return WorkShelfIdea(
                atomUUID: shelf.atom.uuid,
                title: shelf.title,
                clientUUID: shelf.clientUUID,
                clientName: shelf.clientName,
                updatedAt: shelf.atom.updatedAt,
                score: IdeasDeskEngine.score(for: item, inspiration: inspiration, now: now),
                whyLine: IdeasDeskEngine.whyLine(for: item, inspiration: inspiration, now: now),
                bookedDay: bookedDays[shelf.atom.uuid],
                publishDay: publish
            )
        }
    }

    /// idea uuid → soonest OPEN session day, from the one shared resolver, so
    /// the shelf's "BOOKED" lane can never disagree with the Ideas Desk chip or
    /// with what a drop decides to move.
    private static func openSessionDays() async -> [String: Date] {
        let tasks = (try? await AtomRepository.shared.fetchAll(type: .task)) ?? []
        return IdeaTaskLinkService.openSessionDaysByIdea(in: tasks)
    }

    /// content uuid → publish day, for the bridge.
    private static func publishDays() async -> [String: Date] {
        let content = await ContentQueueLoader.load()
        var days: [String: Date] = [:]
        for item in content {
            guard let scheduled = item.scheduledAt else { continue }
            days[item.id] = scheduled
        }
        return days
    }
}

// MARK: - The Rail

struct IdeaWorkShelfRail: View {
    var viewModel: CommandCenterDashboardViewModel

    /// The three lanes, derived ONCE per (data, search, client) change.
    /// Never computed in a body: each lane sorts, and a rail that re-sorted on
    /// every body evaluation is exactly the stall the Ideas Desk perf pass fixed.
    struct ShelfLanes: Equatable {
        var publishingSoon: [WorkShelfIdea] = []
        var choosable: [WorkShelfIdea] = []
        var booked: [WorkShelfIdea] = []

        var isEmpty: Bool { publishingSoon.isEmpty && choosable.isEmpty && booked.isEmpty }
        /// What still needs a session — the header's count. Booked rows are done.
        var unbookedCount: Int { publishingSoon.count + choosable.count }
    }

    @State private var ideas: [WorkShelfIdea] = []
    @State private var clients: [ShelfClient] = []
    @State private var lanes = ShelfLanes()
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedClientUUID: String?
    @State private var isLoading = true

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            railHeader
            searchField
            clientPills
            shelfList
        }
        .task { await reload() }
        .onChange(of: searchText) { _, _ in rebuildLanes() }
        .onChange(of: selectedClientUUID) { _, _ in rebuildLanes() }
        .onReceive(NotificationCenter.default.publisher(for: .contentShelfFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .contentCalendarNeedsReload)) { _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        async let clientsTask = ContentShelfLoader.loadClients()
        async let ideasTask = IdeaWorkShelfLoader.load()
        clients = await clientsTask
        ideas = await ideasTask
        isLoading = false
        rebuildLanes()
    }

    /// One filter pass, then one sort per lane.
    private func rebuildLanes() {
        let tokens = searchTokens
        let now = Date()
        let matching = ideas.filter { idea in
            if let selectedClientUUID, idea.clientUUID != selectedClientUUID { return false }
            guard !tokens.isEmpty else { return true }
            let haystack = "\(idea.title) \(idea.clientName ?? "")".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }

        var soon: [WorkShelfIdea] = []
        var choose: [WorkShelfIdea] = []
        var done: [WorkShelfIdea] = []
        for idea in matching {
            if idea.bookedDay != nil {
                done.append(idea)
            } else if idea.isPublishingSoon(
                now: now,
                horizonDays: IdeaWorkShelfLoader.publishHorizonDays,
                calendar: calendar
            ) {
                soon.append(idea)
            } else {
                choose.append(idea)
            }
        }

        // Deadline pressure first.
        soon.sort { ($0.publishDay ?? .distantFuture) < ($1.publishDay ?? .distantFuture) }
        // The Desk's order, order-locked: score desc → updatedAt desc → uuid,
        // so the same input always deals the same hand.
        choose.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.atomUUID < rhs.atomUUID
        }
        done.sort { ($0.bookedDay ?? .distantFuture) < ($1.bookedDay ?? .distantFuture) }

        lanes = ShelfLanes(publishingSoon: soon, choosable: choose, booked: done)
    }

    // MARK: Header + search + pills

    private var railHeader: some View {
        HStack(spacing: DS.space6) {
            Text("TO SCHEDULE")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text("\(lanes.unbookedCount)")
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
            TextField("Search ideas", text: $searchText)
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
        .help(uuid == nil ? "Every unscheduled idea" : "Only \(label)'s ideas")
        .accessibilityLabel("\(label) filter")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Filtering + lanes

    private var searchTokens: [String] {
        searchText
            .split(separator: " ")
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    // MARK: List

    private var shelfList: some View {
        CosmoSlimScroll {
            LazyVStack(alignment: .leading, spacing: DS.space12) {
                if isLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.space16)
                } else if lanes.isEmpty {
                    teachingState
                } else {
                    lane("PUBLISHING SOON", rows: lanes.publishingSoon)
                    lane("IDEAS", rows: lanes.choosable)
                    lane("BOOKED", rows: lanes.booked)
                }
            }
            .padding(.trailing, DS.space8)
            .padding(.bottom, DS.space24)
        }
    }

    @ViewBuilder
    private func lane(_ label: String, rows: [WorkShelfIdea]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                sectionHeader(label, count: rows.count)
                ForEach(rows) { idea in
                    WorkShelfRow(
                        idea: idea,
                        dayWord: { UpcomingDropActions.dayWord($0, calendar: calendar) },
                        onOpen: { open(idea.atomUUID) }
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

    private var teachingState: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(searchTokens.isEmpty ? "Nothing waiting" : "No matches")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)
            Text(searchTokens.isEmpty
                ? "Capture ideas and they queue up here, ready to drag onto a day to book the writing."
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

/// Same anatomy as the Content shelf's row (3pt spine, title, one meta line,
/// hover grip) — a different meta model, so a sibling rather than a contortion
/// of that file's private type.
private struct WorkShelfRow: View {
    let idea: WorkShelfIdea
    let dayWord: (Date) -> String
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(idea.color)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(idea.title)
                    .font(DS.caption)
                    .foregroundStyle(idea.bookedDay == nil ? DS.text : DS.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                metaLine
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
        .opacity(idea.bookedDay == nil ? 1 : 0.7)
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
            ShelfDragSession.shared.begin(color: idea.color)
            return NSItemProvider(object: ContentShelfPayload.idea(idea.atomUUID).dragString as NSString)
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: DS.space4) {
            if let booked = idea.bookedDay {
                Image(systemName: "calendar.badge.checkmark")
                    .font(DS.caption2.weight(.semibold))
                    .imageScale(.small)
                    .foregroundStyle(idea.color.opacity(0.8))
                    .accessibilityHidden(true)
                Text(dayWord(booked))
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
            } else if let publish = idea.publishDay {
                Text("publishes \(dayWord(publish))")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.gilt)
            } else {
                Text(idea.whyLine)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var helpText: String {
        if let booked = idea.bookedDay {
            return "Session booked \(dayWord(booked)) — drag onto another day to move it"
        }
        if let publish = idea.publishDay {
            return "Publishes \(dayWord(publish)) · nothing booked to write it — drag onto a day to book the session"
        }
        return "Drag onto a day to book a writing session — or click to open"
    }
}
