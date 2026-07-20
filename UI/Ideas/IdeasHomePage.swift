// CosmoOS/UI/Ideas/IdeasHomePage.swift
// Ideas — a first-class Mac destination (Option A, July 2026). Home is
// curated: the working set in motion, then one shelf per client as a door;
// a client pill opens their full board as a one-column scan of serif hooks.
// The IdeaCard is a title object in the app's paper voice (kept in lockstep
// with the iPhone's IdeaCard): the HOOK as a document-title serif headline,
// the inspired-by swipe as a visual anchor, ONE quiet metadata line (emoji
// format mark + drawn platform glyph + age). Manners are Mac — hover,
// tooltips, arrow keys, drag and drop.

import SwiftUI
import GRDB

// MARK: - Client group

struct IdeasHomeGroup: Identifiable {
    let id: String
    let name: String
    let clientUUID: String?
    let ideas: [IdeaGalleryItem]
}

// MARK: - Model

@MainActor
@Observable
final class IdeasPageModel {
    /// Every live idea, newest first.
    var ideas: [IdeaGalleryItem] = []
    /// idea uuid → linked swipe thumbnail candidates, best first (the durable
    /// mirror can 400 when the upload never ran — the CDN original still
    /// serves; the card walks the list and collapses if every one fails).
    var inspirationThumbs: [String: [String]] = [:]
    /// idea uuid → the next OPEN development session's day (the focus-mode
    /// scheduled chip, card-sized): earliest planned day among the idea's
    /// non-completed linked tasks.
    var scheduledDays: [String: Date] = [:]
    var isLoaded = false
    var toastMessage: String?
    /// A deleted idea waiting out its undo window.
    private(set) var pendingDelete: IdeaGalleryItem?

    private var clientProfiles: [Atom] = []
    private var pendingRemovals: Set<String> = []
    private var deleteCommitTask: Task<Void, Never>?
    private var observation: AnyDatabaseCancellable?

    func start() async {
        await load()
        startObserving()
    }

    /// Launch-time warm: one load so the first visit paints instantly. No
    /// observation — that belongs to the page's visible lifetime (start/stop),
    /// and the page's own start() refreshes anything that moved while away.
    func prewarmIfNeeded() async {
        guard !isLoaded else { return }
        await load()
    }

    func stop() {
        observation?.cancel()
        observation = nil
        deleteCommitTask?.cancel()
    }

    /// Any idea-table write re-queries — local edits, sync applies, drops.
    private func startObserving() {
        guard observation == nil, let db = CosmoDatabase.shared.dbPool else { return }
        // Tasks ride the same trigger: scheduling an idea writes only a task
        // atom (the link lives ON the task), and the cards' scheduled chips
        // must follow it live.
        let tracked = ValueObservation
            .tracking { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) || ':' || COALESCE(MAX(updated_at), '') FROM atoms WHERE type IN ('idea', 'task') AND is_deleted = 0"
                ) ?? ""
            }
            .removeDuplicates()
        observation = tracked.start(in: db, onError: { _ in }) { [weak self] _ in
            Task { @MainActor in await self?.load() }
        }
    }

    func load() async {
        let atoms = (try? await AtomRepository.shared.fetchAll(type: .idea)) ?? []
        clientProfiles = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? clientProfiles

        let clientNames = Dictionary(
            uniqueKeysWithValues: clientProfiles.map { ($0.uuid, $0.title ?? "Client") }
        )
        // Activated ideas (Begin Writing → inProduction/published/archived) are
        // content pieces now — reachable via the content's sources, not the boards.
        let live = atoms
            .filter { !pendingRemovals.contains($0.uuid) }
            .filter { !($0.ideaMetadata?.ideaStatus?.isActivated ?? false) }
            .sorted { $0.updatedAt > $1.updatedAt }

        let items = live.compactMap { atom in
            atom.toIdeaGalleryItem(clientName: atom.ideaMetadata?.clientUUID.flatMap { clientNames[$0] })
        }
        let thumbs = await Self.resolveInspiration(for: live)
        let scheduled = await Self.resolveScheduledDays()

        withAnimation(ProMotionSprings.gentle) {
            ideas = items
            inspirationThumbs = thumbs
            scheduledDays = scheduled
            isLoaded = true
        }
    }

    /// The cards' scheduled chips: walk the task table once and keep, per
    /// linked idea, the earliest open session day (the reverse of
    /// `IdeaTaskLinkService.scheduledTasks`, batched for the whole page).
    private static func resolveScheduledDays() async -> [String: Date] {
        let tasks = (try? await AtomRepository.shared.fetchAll(type: .task)) ?? []
        var days: [String: Date] = [:]
        for task in tasks {
            guard task.metadataValue(as: TaskMetadata.self)?.isCompleted != true,
                  let day = IdeaTaskLinkService.plannedDay(task) else { continue }
            for link in IdeaTaskLinkService.linkedAtoms(of: task) where link.atomType == AtomType.idea.rawValue {
                if let existing = days[link.atomUUID], existing <= day { continue }
                days[link.atomUUID] = day
            }
        }
        return days
    }

    /// The card's anchor: the linked swipe's thumbnail, cheapest source first.
    private static func resolveInspiration(for atoms: [Atom]) async -> [String: [String]] {
        var swipeByIdea: [String: String] = [:]
        for atom in atoms {
            let meta = atom.ideaMetadata
            guard let swipeUUID = meta?.linkedSwipeIds?.first
                ?? meta?.originSwipeUUID
                ?? meta?.supportingSwipeUUIDs?.first else { continue }
            swipeByIdea[atom.uuid] = swipeUUID
        }

        var thumbsBySwipe: [String: [String]] = [:]
        for swipeUUID in Set(swipeByIdea.values) {
            guard let swipe = try? await AtomRepository.shared.fetch(uuid: swipeUUID) else { continue }
            // Preferred (the Supabase mirror when present) first, the origin
            // CDN url second — mirrors are durable but occasionally missing.
            var candidates: [String] = []
            if let preferred = swipe.toSwipeGalleryItem()?.thumbnailUrl { candidates.append(preferred) }
            if let cdn = swipe.researchMetadata?.thumbnailUrl, !candidates.contains(cdn) { candidates.append(cdn) }
            if !candidates.isEmpty { thumbsBySwipe[swipeUUID] = candidates }
        }

        return swipeByIdea.compactMapValues { thumbsBySwipe[$0] }
    }

    // MARK: Grouping (the ⌘K board grammar)

    /// Clients alphabetical, Unassigned last; orphaned client ids fall into
    /// Unassigned rather than vanishing.
    var clientGroups: [IdeasHomeGroup] {
        var byClient: [String: [IdeaGalleryItem]] = [:]
        var unassigned: [IdeaGalleryItem] = []
        let knownClientIds = Set(clientProfiles.map(\.uuid))

        for idea in ideas {
            if let clientUUID = idea.clientUUID, knownClientIds.contains(clientUUID) {
                byClient[clientUUID, default: []].append(idea)
            } else {
                unassigned.append(idea)
            }
        }

        var groups: [IdeasHomeGroup] = clientProfiles
            .sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
            .compactMap { client in
                guard let items = byClient[client.uuid], !items.isEmpty else { return nil }
                return IdeasHomeGroup(id: client.uuid, name: client.title ?? "Client", clientUUID: client.uuid, ideas: items)
            }
        if !unassigned.isEmpty {
            groups.append(IdeasHomeGroup(id: "__unassigned__", name: "Unassigned", clientUUID: nil, ideas: unassigned))
        }
        return groups
    }

    /// The working set: ideas touched in the last week, newest first.
    var inMotion: [IdeaGalleryItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return Array(
            ideas
                .filter { (ISO8601.date(from: $0.updatedAt) ?? .distantPast) > cutoff }
                .prefix(8)
        )
    }

    // MARK: Deferred delete (card leaves now, atom later — undo in between)

    func deferDelete(_ idea: IdeaGalleryItem) {
        deleteCommitTask?.cancel()
        if let previous = pendingDelete {
            commitDelete(previous)
        }
        pendingRemovals.insert(idea.atomUUID)
        withAnimation(ProMotionSprings.snappy) {
            ideas.removeAll { $0.atomUUID == idea.atomUUID }
            pendingDelete = idea
        }
        deleteCommitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled else { return }
            self.commitDelete(idea)
            withAnimation(ProMotionSprings.gentle) { self.pendingDelete = nil }
        }
    }

    func undoDelete() {
        deleteCommitTask?.cancel()
        deleteCommitTask = nil
        guard let idea = pendingDelete else { return }
        pendingRemovals.remove(idea.atomUUID)
        withAnimation(ProMotionSprings.snappy) { pendingDelete = nil }
        Task { await load() }
    }

    private func commitDelete(_ idea: IdeaGalleryItem) {
        pendingRemovals.remove(idea.atomUUID)
        Task {
            try? await AtomRepository.shared.delete(uuid: idea.atomUUID)
            NotificationCenter.default.post(
                name: Notification.Name("ideaDeleted"),
                object: nil,
                userInfo: ["uuid": idea.atomUUID]
            )
        }
    }

    // MARK: Drag grammar — a swipe dropped on an idea becomes inspiration

    /// Appends the swipe to `linkedSwipeIds` through the key-preserving
    /// metadata merge — the iPhone reads the same field for the card thumb.
    func linkSwipe(uuid swipeUUID: String, toIdea ideaUUID: String) {
        guard swipeUUID != ideaUUID else { return }
        Task {
            guard let swipe = try? await AtomRepository.shared.fetch(uuid: swipeUUID),
                  swipe.type == .research, swipe.isSwipeFileAtom else {
                withAnimation(ProMotionSprings.gentle) { toastMessage = "Drop a swipe to link inspiration" }
                return
            }
            guard var idea = try? await AtomRepository.shared.fetch(uuid: ideaUUID) else { return }

            let existing = idea.ideaMetadata?.linkedSwipeIds ?? []
            guard !existing.contains(swipeUUID) else {
                withAnimation(ProMotionSprings.gentle) { toastMessage = "Already linked to this idea" }
                return
            }

            idea = idea.withUpdatedIdeaMetadata { meta in
                var ids = meta.linkedSwipeIds ?? []
                ids.append(swipeUUID)
                meta.linkedSwipeIds = ids
            }
            idea.updatedAt = ISO8601.string(from: Date())
            idea.localVersion += 1
            _ = try? await AtomRepository.shared.update(idea)

            withAnimation(ProMotionSprings.gentle) { toastMessage = "Swipe linked as inspiration" }
            await load()
        }
    }

    // MARK: Creation (⌘N — client prefilled on a board)

    func createIdea(clientUUID: String?) {
        Task {
            var atom = Atom.new(type: .idea, title: "Untitled Idea", body: nil, metadata: nil)
            if let clientUUID {
                let clientName = clientProfiles.first { $0.uuid == clientUUID }?.title
                atom = atom.withUpdatedIdeaMetadata { meta in
                    meta.clientUUID = clientUUID
                    if let clientName { meta.clientName = clientName }
                }
                atom = atom.addingLink(.ideaToClient(clientUUID))
            }
            guard let created = try? await AtomRepository.shared.create(atom), let id = created.id else { return }
            await load()
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": id]
            )
        }
    }
}

// MARK: - Page

/// The Ideas destination. One grammar with the iPhone's Ideas surface: bare
/// masthead, intent search, client object pills, editorial shelves, the
/// context pill.
struct IdeasHomePage: View {
    /// A ⌘K jump can land directly on a client's board.
    @Binding var boardRequest: String?

    /// Owned by MainView (not this view) so launch prewarming can load it
    /// before the first visit and revisits keep their data.
    let model: IdeasPageModel
    @State private var selectedClientId: String?
    @State private var searchQuery = ""
    @State private var contextPillVisible = false
    @State private var scrollPosition = ScrollPosition()
    @State private var hasAppeared = false
    /// Keyboard cursor across cards (↑↓ move, ⏎ opens).
    @State private var cursorID: String?
    @State private var boardWidth: CGFloat = 0
    /// The content column's live width — shelf cards tile to it exactly.
    @State private var contentWidth: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @FocusState private var pageFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The reading measure: hooks are for scanning, not masonry.
    private static let columnMeasure: CGFloat = 660
    /// Two columns only when the board has true panoramic room.
    private static let twoColumnThreshold: CGFloat = 1400

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            scrollContent
        }
        .task {
            await model.start()
            consumeBoardRequest()
            if !hasAppeared {
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) { hasAppeared = true }
            }
            pageFocused = true
        }
        .onDisappear { model.stop() }
        .onChange(of: boardRequest) { _, _ in consumeBoardRequest() }
        .onExitCommand(perform: handleEscape)
        .background(keyboardLayer)
        .overlay(alignment: .bottom) { undoToast }
        .overlay(alignment: .bottom) { SwipeSaveToast(message: toastBinding) }
    }

    // MARK: Content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space24) {
                    masthead
                        .id("ideas-top")
                    if model.clientGroups.count > 1 {
                        clientPills
                    }
                    content
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 72)
                .swipeContentMeasure()
            }
            .scrollPosition($scrollPosition)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, new in
                let shouldShow = new > 88
                if shouldShow != contextPillVisible {
                    contextPillVisible = shouldShow
                }
            }
            .overlay(alignment: .top) { contextPill }
            .focusable()
            .focusEffectDisabled()
            .focused($pageFocused)
            .onMoveCommand { direction in moveCursor(direction) }
            .onKeyPress(.return) { openCursor() ? .handled : .ignored }
            .onChange(of: cursorID) { _, new in
                guard let new else { return }
                withAnimation(ProMotionSprings.gentle) { proxy.scrollTo(new, anchor: nil) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            searchResults
        } else if let selectedClientId {
            clientBoard(selectedClientId)
        } else if model.isLoaded && model.ideas.isEmpty {
            IdeasEmptyState(
                icon: "lightbulb",
                headline: "Ideas take shape here",
                teachingLine: "Capture one with ⌘N, or open a swipe and spin an idea out of it."
            )
        } else {
            home
        }
    }

    /// Home: the working set first, then each client's shelf as a door.
    /// A single-group library skips the shelf indirection — a shelf that
    /// doors into the same list it previews is a runaround.
    @ViewBuilder
    private var home: some View {
        if model.clientGroups.count <= 1 {
            cardColumn(model.ideas, surface: "all")
        } else {
            shelvesHome
        }
    }

    @ViewBuilder
    private var shelvesHome: some View {
        // "In motion" earns its shelf only on a library big enough that the
        // client shelves alone can't surface recency (small/fresh libraries:
        // EVERYTHING is recent, and a working-set digest would just mirror
        // the shelves below).
        let motionShelf = model.ideas.count >= 10 && model.inMotion.count >= 2
            ? Array(model.inMotion.prefix(5))
            : []

        if !motionShelf.isEmpty {
            shelf(title: "In motion", ideas: motionShelf, surface: "motion", detail: nil, onTap: nil)
                .ideasCascade(hasAppeared, index: 0)
        }

        // Shelves carry the client's FULL list (the swipe shelves' uncapped
        // rule): the scroller is lazy, so arrows/cursor can walk every idea
        // without detouring through the board.
        ForEach(Array(model.clientGroups.enumerated()), id: \.element.id) { index, group in
            shelf(
                title: group.name,
                ideas: group.ideas,
                surface: "shelf-\(group.id)",
                detail: "\(group.ideas.count)",
                onTap: { openBoard(group.id) }
            )
            .ideasCascade(hasAppeared, index: min(index + 1, 8))
        }
    }

    /// The scroller's card spacing (SwipeShelfScroller's LazyHStack).
    private static let shelfSpacing: CGFloat = 14
    /// Ideal shelf card width — the tiling math snaps to whole cards.
    private static let shelfIdealCardWidth: CGFloat = 300
    /// Uniform shelf card height: room for a 3-line serif hook + the meta
    /// line. Text cards at mixed heights clip in a shelf row; posters never
    /// showed this because every poster is the same size.
    private static let shelfCardHeight: CGFloat = 138

    /// Cards tile the shelf viewport EXACTLY: a whole number of cards per
    /// page, so nothing is ever sliced at the measure edge (a poster cut
    /// mid-image reads as a crop; a hook cut mid-word reads as a bug).
    private var shelfCardWidth: CGFloat {
        guard contentWidth > 0 else { return Self.shelfIdealCardWidth }
        let count = max(2, Int((contentWidth + Self.shelfSpacing) / (Self.shelfIdealCardWidth + Self.shelfSpacing)))
        return (contentWidth - Self.shelfSpacing * CGFloat(count - 1)) / CGFloat(count)
    }

    /// An editorial shelf: the header is a door, the cards ride the Swipe
    /// File's view-aligned scroller — clipped at the measure (no card ever
    /// runs off the window edge), hover chevrons page in the margins.
    private func shelf(
        title: String,
        ideas: [IdeaGalleryItem],
        surface: String,
        detail: String?,
        onTap: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CosmoShelfHeader(title: title, detail: detail, onTap: onTap)
            SwipeShelfScroller {
                ForEach(ideas, id: \.atomUUID) { idea in
                    ideaCard(idea, surface: surface, fixedHeight: Self.shelfCardHeight)
                        .frame(width: shelfCardWidth, alignment: .topLeading)
                }
            }
        }
    }

    /// A client's full board — serif hooks at a reading measure, centered on
    /// the page; a second column only when the window earns it.
    private func clientBoard(_ clientId: String) -> some View {
        let group = model.clientGroups.first { $0.id == clientId }
        let ideas = group?.ideas ?? []
        let twoColumns = boardWidth > Self.twoColumnThreshold && !ideas.isEmpty
        return VStack(alignment: .leading, spacing: DS.space12) {
            CosmoShelfHeader(title: group?.name ?? "Ideas", detail: "\(ideas.count)")
            if model.isLoaded && ideas.isEmpty {
                IdeasEmptyState(
                    icon: "lightbulb",
                    headline: "Nothing here yet",
                    teachingLine: "New ideas for \(group?.name ?? "this client") land on this board."
                )
            } else if twoColumns {
                twoColumnBoard(ideas)
            } else {
                column(ideas, surface: "board")
            }
        }
        .frame(maxWidth: twoColumns ? Self.columnMeasure * 2 + DS.space16 : Self.columnMeasure, alignment: .leading)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { boardWidth = $0 }
    }

    @ViewBuilder
    private var searchResults: some View {
        if model.isLoaded && searched.isEmpty {
            IdeasEmptyState(
                icon: "magnifyingglass",
                headline: "No ideas match",
                teachingLine: "Tokens match in any order — try fewer or different words."
            )
        } else {
            cardColumn(searched, surface: "search")
        }
    }

    /// A centered reading column — the page's one list form.
    private func cardColumn(_ ideas: [IdeaGalleryItem], surface: String) -> some View {
        column(ideas, surface: surface)
            .frame(maxWidth: Self.columnMeasure, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    private func column(_ ideas: [IdeaGalleryItem], surface: String) -> some View {
        LazyVStack(alignment: .leading, spacing: DS.space12) {
            ForEach(ideas, id: \.atomUUID) { idea in
                ideaCard(idea, surface: surface)
            }
        }
    }

    private func twoColumnBoard(_ ideas: [IdeaGalleryItem]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(maximum: Self.columnMeasure), spacing: DS.space16, alignment: .top),
                GridItem(.flexible(maximum: Self.columnMeasure), spacing: DS.space16, alignment: .top),
            ],
            alignment: .leading,
            spacing: DS.space12
        ) {
            ForEach(ideas, id: \.atomUUID) { idea in
                ideaCard(idea, surface: "board")
            }
        }
    }

    private func ideaCard(_ idea: IdeaGalleryItem, surface: String, fixedHeight: CGFloat? = nil) -> some View {
        IdeaCardView(
            idea: idea,
            inspirationThumbs: model.inspirationThumbs[idea.atomUUID] ?? [],
            clientTint: idea.clientUUID.map { DS.clientColor(for: $0) },
            // Inside a client's shelf or board the header already names the
            // client — the card stays silent (redundancy law).
            showsClient: surface == "motion" || surface == "search" || surface == "all",
            // Shelf-width cards drop the format/platform WORDS — the emoji
            // mark and the drawn glyph carry identity alone.
            compactMeta: surface == "motion" || surface.hasPrefix("shelf-"),
            scheduledDay: model.scheduledDays[idea.atomUUID],
            fixedHeight: fixedHeight,
            isCursor: cursorID == idea.atomUUID,
            onOpen: { open(idea) },
            onOpenAsPane: { openAsPane(idea) },
            onDelete: { model.deferDelete(idea) },
            onDropSwipe: { swipeUUID in model.linkSwipe(uuid: swipeUUID, toIdea: idea.atomUUID) }
        )
        .id(idea.atomUUID)
    }

    // MARK: Masthead (a bare title — the masthead law)

    private var masthead: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            SwipeMasthead(title: "Ideas")
            Spacer(minLength: DS.space16)
            SwipeLibrarySearchField(
                text: $searchQuery,
                isFocused: $searchFocused,
                placeholder: "Find in ideas"
            )
        }
    }

    private var contextPill: some View {
        SwipeContextPill(
            title: "Ideas",
            detail: activeClientName,
            visible: contextPillVisible
        ) {
            withAnimation(ProMotionSprings.gentle) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .padding(.top, DS.space12)
    }

    private var activeClientName: String? {
        guard let selectedClientId else { return nil }
        return model.clientGroups.first { $0.id == selectedClientId }?.name
    }

    // MARK: Client pills (App Store objects: identity, not abstract filters)

    private var clientPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                ForEach(model.clientGroups) { group in
                    ClientObjectPill(
                        name: group.name,
                        tint: group.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted,
                        isSelected: selectedClientId == group.id
                    ) {
                        withAnimation(ProMotionSprings.snappy) {
                            // Tap the selected client again to come home.
                            selectedClientId = selectedClientId == group.id ? nil : group.id
                            cursorID = nil
                        }
                    }
                }
            }
            .padding(.vertical, DS.space4)
        }
        .scrollClipDisabled()
    }

    // MARK: Search (tokens match in any order, every honest field)

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searched: [IdeaGalleryItem] {
        let tokens = searchQuery.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return model.ideas }
        return model.ideas.filter { idea in
            let haystack = ([
                idea.title,
                idea.body,
                idea.hooks.joined(separator: " "),
                idea.clientName,
                idea.contentFormat?.displayName,
                idea.platform?.displayName,
            ] as [String?])
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: Keyboard manners

    private var keyboardLayer: some View {
        Group {
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { model.createIdea(clientUUID: selectedClientId == "__unassigned__" ? nil : selectedClientId) }
                .keyboardShortcut("n", modifiers: .command)
            Button("") { Task { await model.load() } }.keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func handleEscape() {
        if searchFocused {
            searchFocused = false
            pageFocused = true
        } else if !searchQuery.isEmpty {
            withAnimation(ProMotionSprings.snappy) { searchQuery = "" }
        } else if cursorID != nil {
            cursorID = nil
        } else if selectedClientId != nil {
            withAnimation(ProMotionSprings.snappy) { selectedClientId = nil }
        }
    }

    /// The flat order the keyboard cursor walks — the visible cards, in
    /// reading order for the current surface.
    private var cursorOrder: [String] {
        if isSearching { return searched.map(\.atomUUID) }
        if let selectedClientId {
            return (model.clientGroups.first { $0.id == selectedClientId }?.ideas ?? []).map(\.atomUUID)
        }
        if model.clientGroups.count <= 1 { return model.ideas.map(\.atomUUID) }
        let motion = model.ideas.count >= 10 && model.inMotion.count >= 2
            ? model.inMotion.prefix(5).map(\.atomUUID)
            : []
        return motion + model.clientGroups.flatMap { $0.ideas.map(\.atomUUID) }
    }

    private func moveCursor(_ direction: MoveCommandDirection) {
        let order = cursorOrder
        guard !order.isEmpty else { return }
        let step = (direction == .down || direction == .right) ? 1 : -1
        guard let current = cursorID, let index = order.firstIndex(of: current) else {
            cursorID = step > 0 ? order.first : order.last
            return
        }
        let next = index + step
        guard order.indices.contains(next) else { return }
        cursorID = order[next]
    }

    private func openCursor() -> Bool {
        guard let cursorID,
              let idea = model.ideas.first(where: { $0.atomUUID == cursorID }) else { return false }
        open(idea)
        return true
    }

    // MARK: Actions

    private func openBoard(_ groupId: String) {
        withAnimation(ProMotionSprings.snappy) {
            selectedClientId = groupId
            cursorID = nil
        }
        withAnimation(ProMotionSprings.gentle) {
            scrollPosition.scrollTo(edge: .top)
        }
    }

    private func open(_ idea: IdeaGalleryItem) {
        guard idea.entityId > 0 else { return }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.idea, "id": idea.entityId]
        )
    }

    private func openAsPane(_ idea: IdeaGalleryItem) {
        guard idea.entityId > 0 else { return }
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openAsPane,
            object: nil,
            userInfo: ["type": EntityType.idea, "id": idea.entityId]
        )
    }

    private func consumeBoardRequest() {
        guard let request = boardRequest else { return }
        boardRequest = nil
        withAnimation(ProMotionSprings.snappy) {
            selectedClientId = model.clientGroups.contains { $0.id == request } ? request : selectedClientId
        }
    }

    // MARK: Toasts

    private var toastBinding: Binding<String?> {
        Binding(
            get: { model.toastMessage },
            set: { model.toastMessage = $0 }
        )
    }

    @ViewBuilder
    private var undoToast: some View {
        if model.pendingDelete != nil {
            HStack(spacing: DS.space12) {
                Text("Idea deleted")
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.text)
                Button("Undo") { model.undoDelete() }
                    .buttonStyle(.plain)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo delete (⌘Z)")
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 24)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - Cascade (first-load arrival only)

private extension View {
    func ideasCascade(_ hasAppeared: Bool, index: Int) -> some View {
        opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
            .animation(ProMotionSprings.gentle.delay(Double(min(index, 8)) * 0.05), value: hasAppeared)
    }
}

// MARK: - Idea card (the honest object)

/// An idea is a title object in the app's paper voice (lockstep with the
/// iPhone's IdeaCard): the HOOK as a document-title serif headline, the
/// inspired-by swipe as a visual anchor, ONE quiet metadata line. Format
/// marks come from the emoji identity register and platforms from the drawn
/// glyph set, never SF stand-ins. The card surface is the adaptive elevated
/// paper (`surfaceElevated` — the token the iPhone's documentSurface maps
/// to), so dark palettes get dark cards with palette-matched sepia hairlines.
/// Drag it to a canvas; drop a swipe on it to link inspiration.
private struct IdeaCardView: View {
    let idea: IdeaGalleryItem
    var inspirationThumbs: [String] = []
    var clientTint: Color?
    /// Client identity renders only in mixed contexts (In motion, search) —
    /// inside a client's shelf or board the header already says it.
    var showsClient = true
    /// Shelf-width cards drop the format/platform WORDS — the emoji mark and
    /// the drawn glyph carry identity alone.
    var compactMeta = false
    /// The next open development session's day — renders the focus-mode
    /// scheduled chip (calendar glyph + idea-accent day) on the meta line.
    var scheduledDay: Date? = nil
    /// Shelf cards share one height (uniform rows scroll clean); the meta
    /// line drops to the bottom edge and shorter hooks breathe.
    var fixedHeight: CGFloat? = nil
    var isCursor = false
    let onOpen: () -> Void
    let onOpenAsPane: () -> Void
    let onDelete: () -> Void
    let onDropSwipe: (String) -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false

    private static let cornerRadius: CGFloat = 14

    /// The headline is the hook — the line that would stop the scroll.
    private var headline: String {
        if let hook = idea.hooks.first, !hook.isEmpty { return hook }
        return idea.title
    }

    /// "x" is stored bare; the glyph family answers to x_post.
    private var platformFamily: String? {
        guard let raw = idea.platform?.rawValue else { return nil }
        return raw == "x" ? "x_post" : raw
    }

    private var age: String {
        guard let date = ISO8601.date(from: idea.updatedAt) else { return "" }
        return date.cosmoCompactAge
    }

    /// The adaptive sepia hairline — palette-matched, not the paper-doctrine
    /// document token (which stays light in dark palettes).
    private var hairline: Color { DS.palette.sepiaBorder }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: DS.space12) {
                VStack(alignment: .leading, spacing: DS.space10) {
                    Text(headline)
                        .font(DS.blockTitleSerif)
                        .foregroundStyle(DS.text)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if fixedHeight != nil {
                        Spacer(minLength: 0)
                    }

                    metaRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !inspirationThumbs.isEmpty {
                    IdeaInspirationThumb(candidates: inspirationThumbs, hairline: hairline)
                }
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: fixedHeight)
            .background(isDropTarget ? DS.entityIdea.opacity(0.06) : .clear)
            .background(DS.surfaceElevated)
            .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isDropTarget ? DS.entityIdea.opacity(0.45)
                            : isCursor ? DS.focusRing
                            : hairline,
                        lineWidth: isDropTarget ? 2 : isCursor ? 1.5 : 0.5
                    )
            )
            .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(IdeaCardPressStyle())
        .dsRestingShadow()
        .shadow(color: .black.opacity(isHovered ? 0.07 : 0), radius: 10, y: 3)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(ProMotionSprings.snappy, value: isDropTarget)
        .onHover { isHovered = $0 }
        .modifier(CommandKDragOutModifier(
            uuid: idea.atomUUID,
            title: headline,
            subtitle: idea.clientName ?? "Idea",
            accent: DS.entityIdea,
            symbolName: "lightbulb",
            thumbnailURL: inspirationThumbs.first
        ))
        .dropDestination(for: String.self) { items, _ in
            guard let dropped = items.first.flatMap({ CommandKDragSession.Payload.uuids(fromDropped: $0).first }),
                  dropped != idea.atomUUID else { return false }
            onDropSwipe(dropped)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .contextMenu {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button(action: onOpenAsPane) {
                Label("Open in New Pane", systemImage: "rectangle.split.2x1")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Idea", systemImage: "trash")
            }
        }
        .help("Open \(headline) (⏎)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// ONE quiet line: [client ·] format · platform · age.
    private var metaRow: some View {
        HStack(spacing: DS.space6) {
            if showsClient, let clientName = idea.clientName, !clientName.isEmpty {
                Circle()
                    .fill(clientTint ?? DS.textMuted)
                    .frame(width: 6, height: 6)
                Text(clientName)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text("·")
            }
            if let format = idea.contentFormat {
                Text(CollectionEmoji.formatMark(format))
                    .font(.system(size: 12))
                if !compactMeta {
                    Text(format.displayName)
                        .lineLimit(1)
                }
                Text("·")
            }
            if let family = platformFamily, let platform = idea.platform {
                SwipePlatformGlyph(source: family)
                    .frame(width: 9, height: 9)
                if !compactMeta {
                    Text(platform.displayName)
                        .lineLimit(1)
                }
                Text("·")
            }
            Text(age)
                .monospacedDigit()
            if let scheduledLabel {
                Text("·")
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .accessibilityHidden(true)
                    Text(scheduledLabel)
                        .lineLimit(1)
                }
                .foregroundStyle(DS.entityIdea.opacity(0.9))
            }
        }
        .font(DS.caption2)
        .foregroundStyle(DS.textMuted)
    }

    /// The scheduled chip's day, in the focus-mode chip's own words.
    private var scheduledLabel: String? {
        guard let scheduledDay else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(scheduledDay) { return "Today" }
        if calendar.isDateInTomorrow(scheduledDay) { return "Tomorrow" }
        return scheduledDay.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private var cardAccessibilityLabel: String {
        var parts = [headline]
        if let format = idea.contentFormat { parts.append(format.displayName) }
        if let platform = idea.platform { parts.append(platform.displayName) }
        if showsClient, let client = idea.clientName { parts.append(client) }
        if let scheduledLabel { parts.append("Scheduled \(scheduledLabel)") }
        return parts.joined(separator: ", ")
    }
}

/// The inspired-by swipe thumb with a fallback chain: the durable Supabase
/// mirror first, the origin CDN url second. If every candidate fails the
/// thumb collapses — an empty grey well is worse than no anchor at all.
/// Shared with the Idea Focus inspector so a swipe wears the same face
/// everywhere it appears (identity outranks type).
struct IdeaInspirationThumb: View {
    let candidates: [String]
    let hairline: Color
    var width: CGFloat = 44
    var height: CGFloat = 56

    @State private var index = 0
    @State private var exhausted = false

    var body: some View {
        if !exhausted, candidates.indices.contains(index) {
            let candidate = candidates[index]
            CachedAsyncImage(url: URL(string: candidate), stableKey: candidate) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    Rectangle().fill(DS.glassSectionFill)
                case .failure:
                    Rectangle().fill(DS.glassSectionFill)
                        .onAppear { advance() }
                }
            }
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 0.5)
            )
            .accessibilityHidden(true)
        }
    }

    private func advance() {
        if index + 1 < candidates.count {
            index += 1
        } else {
            exhausted = true
        }
    }
}

/// The compress-and-spring press — the card answers the click before the
/// focus transition begins.
private struct IdeaCardPressStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ProMotionSprings.snappy, value: configuration.isPressed)
    }
}

// MARK: - Client pill (the App Store object pill)

/// A client as a thing with identity — elevated surface, soft shadow, emoji
/// or color-dot mark. Selection is the app's one selection language.
private struct ClientObjectPill: View {
    let name: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let identity = CollectionEmoji.resolve(name: name, matchKeywords: false)
        Button(action: action) {
            HStack(spacing: DS.space8) {
                if let emoji = identity.emoji {
                    Text(emoji)
                        .font(.system(size: 14))
                } else {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                }
                Text(identity.label)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.space16)
            .frame(height: 34)
            .background(isSelected ? AnyShapeStyle(tint.opacity(0.14)) : AnyShapeStyle(DS.surfaceElevated))
            .clipShape(.capsule)
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? tint.opacity(0.42) : DS.palette.sepiaBorder,
                    lineWidth: isSelected ? 1 : 0.5
                )
            )
            .shadow(color: .black.opacity(isSelected ? 0 : 0.07), radius: 5, y: 2)
            .contentShape(.capsule)
        }
        .buttonStyle(IdeaCardPressStyle())
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(isSelected ? "Back to all ideas" : "\(identity.label)'s board")
        .accessibilityLabel("\(identity.label) ideas")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Empty state (absence teaches the fix)

private struct IdeasEmptyState: View {
    let icon: String
    let headline: String
    let teachingLine: String

    var body: some View {
        VStack(spacing: DS.space10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(DS.entityIdea.opacity(0.45))
            Text(headline)
                .font(DS.headline)
                .foregroundStyle(DS.textSecondary)
            Text(teachingLine)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
        .accessibilityElement(children: .combine)
    }
}
