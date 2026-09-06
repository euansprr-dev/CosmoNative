// CosmoOS/UI/AtomWindow/AtomSwitcherModel.swift
// The Atom window's switcher: one full-window surface where the whole
// database is searchable and browsable, and where "Back" from any item
// lands. Two search tiers (instant in-memory index, then the hybrid
// FTS5 + vector pass) merge in place; results group by kind with the open
// item and pinned items first when the field is empty.

import SwiftUI

// MARK: - Scope

/// The kinds the switcher can narrow to. `everything` is the default; Tab
/// cycles, ⌘1–⌘9 jump.
enum AtomSwitcherScope: String, CaseIterable, Identifiable, Sendable {
    case everything
    case pages
    case ideas
    case content
    case research
    case concepts
    case tasks
    case projects
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything: "Everything"
        case .pages: "Pages"
        case .ideas: "Ideas"
        case .content: "Content"
        case .research: "Research"
        case .concepts: "Concepts"
        case .tasks: "Tasks"
        case .projects: "Projects"
        case .media: "Media"
        }
    }

    /// nil = every user-searchable kind.
    var types: [AtomType]? {
        switch self {
        case .everything: nil
        case .pages: [.note]
        case .ideas: [.idea]
        case .content: [.content]
        case .research: [.research]
        case .concepts: [.connection]
        case .tasks: [.task]
        case .projects: [.project]
        case .media: [.image, .file]
        }
    }

    var icon: CosmoIcon {
        switch self {
        case .everything: .system("circle.grid.2x2")
        case .pages: AtomType.note.cosmoIcon
        case .ideas: AtomType.idea.cosmoIcon
        case .content: AtomType.content.cosmoIcon
        case .research: AtomType.research.cosmoIcon
        case .concepts: AtomType.connection.cosmoIcon
        case .tasks: AtomType.task.cosmoIcon
        case .projects: AtomType.project.cosmoIcon
        case .media: AtomType.image.cosmoIcon
        }
    }

    /// The field names its scope ("Search pages", never a bare "Search").
    var placeholder: String {
        self == .everything ? "Search everything" : "Search \(title.lowercased())"
    }

    /// ⌘-digit, 1-based in declaration order.
    var shortcutDigit: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    func includes(_ type: AtomType) -> Bool {
        types?.contains(type) ?? AtomSwitcherGrouping.searchableTypes.contains(type)
    }

    func cycled(by offset: Int) -> AtomSwitcherScope {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .everything }
        let next = ((index + offset) % all.count + all.count) % all.count
        return all[next]
    }
}

// MARK: - Rows & sections

struct AtomSwitcherRow: Identifiable, Equatable, Sendable {
    let uuid: String
    let type: AtomType
    let isSwipe: Bool
    let title: String
    /// Verbatim window around the matched body text (search hits only).
    let excerpt: String?
    /// Head of the body, for the preview subject.
    let snippet: String?
    let updatedAt: String
    let thumbnailURL: String?
    var isOpen: Bool = false
    var isPinned: Bool = false

    var id: String { uuid }

    var kindLabel: String {
        isSwipe ? "Swipe" : type.displayName
    }

    var age: String {
        guard let date = ISO8601.date(from: updatedAt) else { return "" }
        return date.cosmoCompactAge
    }

    /// "Page · 2m" — the row's quiet second line when there is no excerpt.
    var subtitle: String {
        let age = age
        return age.isEmpty ? kindLabel : "\(kindLabel) · \(age)"
    }

    var accent: Color {
        AtomSwitcherGrouping.accent(for: type, isSwipe: isSwipe)
    }

    var icon: CosmoIcon {
        isSwipe ? .swipe : type.cosmoIcon
    }
}

struct AtomSwitcherSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [AtomSwitcherRow]
    /// The live count — may exceed `rows.count` when a browse is capped.
    let count: Int

    init(id: String, title: String, rows: [AtomSwitcherRow], count: Int? = nil) {
        self.id = id
        self.title = title
        self.rows = rows
        self.count = count ?? rows.count
    }
}

// MARK: - Escape ladder

/// What Esc means, by state: peel the query first, then the layer, then the
/// window — one key, never a dead press.
enum AtomSwitcherEscape: Equatable, Sendable {
    case clearQuery
    case returnToOpenItem
    case closeWindow

    static func resolve(queryIsEmpty: Bool, hasOpenItem: Bool) -> AtomSwitcherEscape {
        if !queryIsEmpty { return .clearQuery }
        return hasOpenItem ? .returnToOpenItem : .closeWindow
    }
}

// MARK: - Grouping (pure)

enum AtomSwitcherGrouping {
    /// Every kind the switcher indexes — the repository's own allowlist.
    static let searchableTypes: [AtomType] = AtomType.userSearchableTypes

    /// Display order for kind sections when tiers tie.
    static let kindOrder: [AtomType] = [
        .note, .idea, .content, .research, .connection,
        .task, .project, .journalEntry, .image, .file
    ]

    static let browseCap = 200
    static let continueCap = 8

    static func sectionID(for type: AtomType, isSwipe: Bool) -> String {
        isSwipe ? "swipes" : type.rawValue
    }

    static func sectionTitle(for type: AtomType, isSwipe: Bool) -> String {
        if isSwipe { return "Swipes" }
        switch type {
        case .note: return "Pages"
        case .idea: return "Ideas"
        case .content: return "Content"
        case .research: return "Research"
        case .connection: return "Concepts"
        case .task: return "Tasks"
        case .project: return "Projects"
        case .journalEntry: return "Journal"
        case .image: return "Images"
        case .file: return "Files"
        default: return type.displayName
        }
    }

    static func accent(for type: AtomType, isSwipe: Bool) -> Color {
        if isSwipe { return DS.entitySwipe }
        switch type {
        case .project: return DS.entityIdea
        case .file: return DS.entityFile
        default: return AtomWindowViewModel.entityColor(for: type)
        }
    }

    /// Search results, grouped by kind. Sections order by their best hit
    /// (tier, then relevance) so an exact-title section always leads; rows
    /// keep the incoming (already ranked) order.
    static func searchSections(
        results: [RankedResult],
        swipeUUIDs: Set<String>,
        thumbnails: [String: String],
        openUUID: String?,
        pinnedUUIDs: Set<String>
    ) -> [AtomSwitcherSection] {
        struct Bucket {
            let type: AtomType
            let isSwipe: Bool
            var rows: [AtomSwitcherRow] = []
            var bestTier: LexicalTier = .semanticOnly
            var bestRelevance: Double = 0
        }
        var buckets: [String: Bucket] = [:]
        var order: [String] = []
        var seen: Set<String> = []

        for result in results {
            guard !seen.contains(result.atomUUID) else { continue }
            seen.insert(result.atomUUID)
            let isSwipe = swipeUUIDs.contains(result.atomUUID)
            let key = sectionID(for: result.atomType, isSwipe: isSwipe)
            if buckets[key] == nil {
                buckets[key] = Bucket(type: result.atomType, isSwipe: isSwipe)
                order.append(key)
            }
            let row = AtomSwitcherRow(
                uuid: result.atomUUID,
                type: result.atomType,
                isSwipe: isSwipe,
                title: result.title,
                excerpt: result.lexicalTier >= .phraseInBody ? result.matchedExcerpt : nil,
                snippet: result.snippet,
                updatedAt: result.updatedAt,
                thumbnailURL: thumbnails[result.atomUUID],
                isOpen: result.atomUUID == openUUID,
                isPinned: pinnedUUIDs.contains(result.atomUUID)
            )
            buckets[key]?.rows.append(row)
            if result.lexicalTier < buckets[key]!.bestTier
                || (result.lexicalTier == buckets[key]!.bestTier && result.relevance > buckets[key]!.bestRelevance) {
                buckets[key]?.bestTier = result.lexicalTier
                buckets[key]?.bestRelevance = result.relevance
            }
        }

        let sorted = order.compactMap { buckets[$0] }.sorted { lhs, rhs in
            if lhs.bestTier != rhs.bestTier { return lhs.bestTier < rhs.bestTier }
            if lhs.bestRelevance != rhs.bestRelevance { return lhs.bestRelevance > rhs.bestRelevance }
            return kindRank(lhs.type, isSwipe: lhs.isSwipe) < kindRank(rhs.type, isSwipe: rhs.isSwipe)
        }
        return sorted.map { bucket in
            AtomSwitcherSection(
                id: sectionID(for: bucket.type, isSwipe: bucket.isSwipe),
                title: sectionTitle(for: bucket.type, isSwipe: bucket.isSwipe),
                rows: bucket.rows
            )
        }
    }

    /// A kind browse (scope chosen, field empty): most recent first, capped
    /// for layout but counted in full. Swipes split from research so the
    /// two collections never interleave.
    static func browseSections(
        rows: [AtomSwitcherRow]
    ) -> [AtomSwitcherSection] {
        var groups: [String: [AtomSwitcherRow]] = [:]
        var order: [String] = []
        for row in rows.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let key = sectionID(for: row.type, isSwipe: row.isSwipe)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return order
            .sorted { lhs, rhs in
                guard let l = groups[lhs]?.first, let r = groups[rhs]?.first else { return false }
                return kindRank(l.type, isSwipe: l.isSwipe) < kindRank(r.type, isSwipe: r.isSwipe)
            }
            .compactMap { key in
                guard let all = groups[key], let first = all.first else { return nil }
                return AtomSwitcherSection(
                    id: key,
                    title: sectionTitle(for: first.type, isSwipe: first.isSwipe),
                    rows: Array(all.prefix(browseCap)),
                    count: all.count
                )
            }
    }

    /// Home: the open item leads Continue, then recent work; pinned items
    /// follow. Nothing appears twice.
    static func homeSections(
        open: AtomSwitcherRow?,
        recents: [AtomSwitcherRow],
        pinned: [AtomSwitcherRow]
    ) -> [AtomSwitcherSection] {
        var sections: [AtomSwitcherSection] = []
        var seen: Set<String> = []
        var continueRows: [AtomSwitcherRow] = []
        if let open {
            continueRows.append(open)
            seen.insert(open.uuid)
        }
        for row in recents where !seen.contains(row.uuid) && continueRows.count < continueCap {
            continueRows.append(row)
            seen.insert(row.uuid)
        }
        if !continueRows.isEmpty {
            sections.append(AtomSwitcherSection(id: "continue", title: "Continue", rows: continueRows))
        }
        let pinnedRows = pinned.filter { !seen.contains($0.uuid) }
        if !pinnedRows.isEmpty {
            sections.append(AtomSwitcherSection(id: "pinned", title: "Pinned", rows: pinnedRows))
        }
        return sections
    }

    /// Keyboard travel through the flattened rows. nil current → the first
    /// row (or the last when travelling up).
    static func nextSelection(from current: String?, in rows: [AtomSwitcherRow], offset: Int) -> String? {
        guard !rows.isEmpty else { return nil }
        guard let current, let index = rows.firstIndex(where: { $0.id == current }) else {
            return offset < 0 ? rows.last?.id : rows.first?.id
        }
        let next = max(0, min(rows.count - 1, index + offset))
        return rows[next].id
    }

    /// Hybrid results only know the entity family — the index knows the
    /// real kind. Unknown families are dropped rather than mislabelled.
    static func atomType(for entityType: EntityType) -> AtomType? {
        switch entityType {
        case .idea: .idea
        case .task: .task
        case .research: .research
        case .content: .content
        case .connection: .connection
        case .project: .project
        case .journal: .journalEntry
        case .note: .note
        case .image: .image
        case .file: .file
        default: nil
        }
    }

    private static func kindRank(_ type: AtomType, isSwipe: Bool) -> Int {
        let base = kindOrder.firstIndex(of: type) ?? kindOrder.count
        // Swipes sit right after research.
        return base * 2 + (isSwipe ? 1 : 0)
    }
}

// MARK: - Model

@Observable @MainActor
final class AtomSwitcherModel {
    var query = ""
    private(set) var scope: AtomSwitcherScope = .everything
    private(set) var sections: [AtomSwitcherSection] = []
    private(set) var selectedID: String?
    /// The deep (hybrid) pass is in flight — the rail never spins for it;
    /// the footer whispers.
    private(set) var isDeepSearching = false
    private(set) var isIndexReady = false
    private(set) var isPresented = false

    private(set) var openUUID: String?
    private(set) var openTitle: String?
    private(set) var pinnedUUIDs: Set<String> = []

    // Index — the instant tier. Bounded entries; built off the main actor.
    private var index = CommandKSearchIndex()
    private var typeByUUID: [String: AtomType] = [:]
    private var swipeUUIDs: Set<String> = []
    private var thumbnailByUUID: [String: String] = [:]
    private var indexStamp: String?
    private var indexTask: Task<Void, Never>?

    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var generation = 0
    private var userMovedSelection = false
    private var changeObserver: NSObjectProtocol?

    static let instantLimit = 80
    static let deepLimit = 60
    static let deepDelay: Duration = .milliseconds(120)

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .atomsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.atomsDidChange() }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let changeObserver {
                NotificationCenter.default.removeObserver(changeObserver)
            }
        }
    }

    // MARK: Presentation

    func present(openAtom: Atom?, pinnedUUIDs: Set<String>) {
        isPresented = true
        openUUID = openAtom?.uuid
        openTitle = openAtom?.title
        self.pinnedUUIDs = pinnedUUIDs
        userMovedSelection = false
        refreshIndexIfNeeded()
        reload()
    }

    func dismiss() {
        isPresented = false
        searchTask?.cancel()
        loadTask?.cancel()
        searchTask = nil
        loadTask = nil
        isDeepSearching = false
    }

    /// Full reset — the window unloaded its session.
    func reset() {
        dismiss()
        query = ""
        scope = .everything
        sections = []
        selectedID = nil
        openUUID = nil
        openTitle = nil
    }

    func setPinned(_ uuids: Set<String>) {
        pinnedUUIDs = uuids
        sections = sections.map { section in
            AtomSwitcherSection(
                id: section.id,
                title: section.title,
                rows: section.rows.map { row in
                    var row = row
                    row.isPinned = uuids.contains(row.uuid)
                    return row
                },
                count: section.count
            )
        }
        if query.isEmpty, scope == .everything { reload() }
    }

    // MARK: Query & scope

    func queryDidChange() {
        userMovedSelection = false
        reload()
    }

    func clearQuery() {
        query = ""
        queryDidChange()
    }

    func setScope(_ scope: AtomSwitcherScope) {
        guard scope != self.scope else { return }
        self.scope = scope
        userMovedSelection = false
        reload()
    }

    func cycleScope(by offset: Int) {
        setScope(scope.cycled(by: offset))
    }

    // MARK: Selection

    var flatRows: [AtomSwitcherRow] {
        sections.flatMap(\.rows)
    }

    var selectedRow: AtomSwitcherRow? {
        guard let selectedID else { return nil }
        return flatRows.first { $0.id == selectedID }
    }

    var hasOpenItem: Bool { openUUID != nil }

    func select(_ id: String?) {
        userMovedSelection = true
        selectedID = id
    }

    func moveSelection(by offset: Int) {
        userMovedSelection = true
        selectedID = AtomSwitcherGrouping.nextSelection(from: selectedID, in: flatRows, offset: offset)
    }

    var escapeAction: AtomSwitcherEscape {
        AtomSwitcherEscape.resolve(queryIsEmpty: query.isEmpty, hasOpenItem: hasOpenItem)
    }

    /// The preview pane's subject for a row: the same adapter Command-K
    /// uses, so one detail pane serves both surfaces.
    func previewSubject(for row: AtomSwitcherRow) -> CortexDetailSubject {
        .recent(RecentDisplayItem(
            id: row.uuid,
            title: row.title,
            type: row.type,
            entityId: 0,
            relativeDate: row.age,
            thumbnailURL: row.thumbnailURL,
            preview: row.excerpt ?? row.snippet,
            isSwipeFile: row.isSwipe
        ))
    }

    // MARK: Loading

    private func reload() {
        generation += 1
        searchTask?.cancel()
        loadTask?.cancel()
        isDeepSearching = false
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if scope == .everything {
                loadHome()
            } else {
                loadBrowse()
            }
        } else {
            search(trimmed)
        }
    }

    private func loadHome() {
        let gen = generation
        let openUUID = openUUID
        let pinned = pinnedUUIDs
        loadTask = Task { @MainActor in
            var openAtom: Atom?
            if let openUUID {
                openAtom = CanvasAtomWarmStore.shared.atom(uuid: openUUID)
                if openAtom == nil {
                    openAtom = try? await AtomRepository.shared.fetch(uuid: openUUID)
                }
            }
            let recents = (try? await AtomRepository.shared.fetchRecent(limit: AtomSwitcherGrouping.continueCap + 4)) ?? []
            let pinnedAtoms = pinned.isEmpty ? [] : ((try? await AtomRepository.shared.fetch(uuids: Array(pinned))) ?? [])
            guard !Task.isCancelled, gen == generation else { return }
            let sections = AtomSwitcherGrouping.homeSections(
                open: openAtom.map { row(for: $0) },
                recents: recents.filter { !$0.isDeleted }.map { row(for: $0) },
                pinned: pinnedAtoms
                    .filter { !$0.isDeleted }
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .map { row(for: $0) }
            )
            apply(sections)
        }
    }

    private func loadBrowse() {
        let gen = generation
        let scope = scope
        guard let types = scope.types else { return }
        if isIndexReady {
            let snapshot = index
            let swipes = swipeUUIDs
            let thumbnails = thumbnailByUUID
            let openUUID = openUUID
            let pinned = pinnedUUIDs
            loadTask = Task { @MainActor in
                let rows = await Task.detached(priority: .userInitiated) {
                    snapshot.entries
                        .filter { types.contains($0.atomType) }
                        .map { entry in
                            AtomSwitcherRow(
                                uuid: entry.atomUUID,
                                type: entry.atomType,
                                isSwipe: swipes.contains(entry.atomUUID),
                                title: entry.title,
                                excerpt: nil,
                                snippet: entry.snippet.map { String($0.prefix(160)) },
                                updatedAt: entry.updatedAt,
                                thumbnailURL: thumbnails[entry.atomUUID],
                                isOpen: entry.atomUUID == openUUID,
                                isPinned: pinned.contains(entry.atomUUID)
                            )
                        }
                }.value
                guard !Task.isCancelled, gen == generation else { return }
                apply(AtomSwitcherGrouping.browseSections(rows: rows))
            }
        } else {
            loadTask = Task { @MainActor in
                let atoms = (try? await AtomRepository.shared.fetchAll(types: types)) ?? []
                guard !Task.isCancelled, gen == generation else { return }
                apply(AtomSwitcherGrouping.browseSections(rows: atoms.map { row(for: $0) }))
            }
        }
    }

    private func search(_ query: String) {
        let gen = generation
        let scope = scope
        let snapshot = index
        let indexReady = isIndexReady
        searchTask = Task { @MainActor in
            // Tier 1 — instant, from memory.
            var instant: [RankedResult] = []
            if indexReady {
                instant = await Task.detached(priority: .userInitiated) {
                    snapshot.search(query, limit: Self.instantLimit, shouldCancel: { Task.isCancelled })
                }.value
                guard !Task.isCancelled, gen == generation else { return }
                apply(sections(for: instant.filter { scope.includes($0.atomType) }))
            }

            // Tier 2 — the hybrid pass (FTS5 over the whole body + vectors).
            try? await Task.sleep(for: Self.deepDelay)
            guard !Task.isCancelled, gen == generation else { return }
            isDeepSearching = true
            defer { if gen == generation { isDeepSearching = false } }
            let hybrid = (try? await HybridSearchEngine.shared.search(
                query: query, limit: Self.deepLimit, entityTypes: nil
            )) ?? []
            guard !Task.isCancelled, gen == generation else { return }

            let normalized = CommandKSearchMatcher.normalizeQuery(query)
            var deep: [RankedResult] = []
            deep.reserveCapacity(hybrid.count)
            for result in hybrid {
                guard let uuid = result.entityUUID else { continue }
                guard let type = typeByUUID[uuid] ?? AtomSwitcherGrouping.atomType(for: result.entityType),
                      AtomSwitcherGrouping.searchableTypes.contains(type),
                      scope.includes(type) else { continue }
                deep.append(CommandKHybridResultMapper.rankedResult(
                    from: result, atomType: type, normalizedQuery: normalized
                ))
            }
            deep.sort()
            let merged = CommandKViewModel.mergeRankedResults(
                primary: deep,
                additional: instant.filter { scope.includes($0.atomType) }
            )
            apply(sections(for: merged))
        }
    }

    private func sections(for results: [RankedResult]) -> [AtomSwitcherSection] {
        AtomSwitcherGrouping.searchSections(
            results: results,
            swipeUUIDs: swipeUUIDs,
            thumbnails: thumbnailByUUID,
            openUUID: openUUID,
            pinnedUUIDs: pinnedUUIDs
        )
    }

    private func apply(_ sections: [AtomSwitcherSection]) {
        self.sections = sections
        let rows = flatRows
        if userMovedSelection, let selectedID, rows.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = rows.first?.id
    }

    private func row(for atom: Atom) -> AtomSwitcherRow {
        let isSwipe = atom.isSwipeFileAtom
        let thumbnail = atom.type == .image
            ? atom.imageMetadata?.imagePath
            : (atom.type == .research ? atom.thumbnailUrl : nil)
        let title = atom.title ?? ""
        return AtomSwitcherRow(
            uuid: atom.uuid,
            type: atom.type,
            isSwipe: isSwipe,
            title: title.isEmpty ? "Untitled" : title,
            excerpt: nil,
            snippet: atom.body.map { String($0.prefix(160)) },
            updatedAt: atom.updatedAt,
            thumbnailURL: thumbnail,
            isOpen: atom.uuid == openUUID,
            isPinned: pinnedUUIDs.contains(atom.uuid)
        )
    }

    // MARK: Index

    /// Builds the instant index on first use, then refreshes incrementally
    /// (tombstones included, so deletions never linger as ghosts).
    private func refreshIndexIfNeeded() {
        guard indexTask == nil else { return }
        let since = indexStamp
        indexTask = Task { @MainActor in
            defer { indexTask = nil }
            let fetched = (try? await AtomRepository.shared.fetchUserSearchableUpdatedSince(since ?? "")) ?? []
            guard !Task.isCancelled else { return }
            if since != nil, fetched.isEmpty { return }

            let live = fetched.filter { !$0.isDeleted }
            struct Built: Sendable {
                let entries: [CommandKSearchIndex.Entry]
                let swipes: Set<String>
                let thumbnails: [String: String]
                let types: [String: AtomType]
            }
            let built = await Task.detached(priority: .userInitiated) {
                var swipes: Set<String> = []
                var thumbnails: [String: String] = [:]
                var types: [String: AtomType] = [:]
                types.reserveCapacity(live.count)
                for atom in live {
                    types[atom.uuid] = atom.type
                    if atom.type == .research {
                        if atom.isSwipeFileAtom { swipes.insert(atom.uuid) }
                        if let url = atom.thumbnailUrl, !url.isEmpty { thumbnails[atom.uuid] = url }
                    } else if atom.type == .image, let path = atom.imageMetadata?.imagePath, !path.isEmpty {
                        thumbnails[atom.uuid] = path
                    }
                }
                return Built(
                    entries: CommandKSearchIndex.entries(for: live),
                    swipes: swipes,
                    thumbnails: thumbnails,
                    types: types
                )
            }.value
            guard !Task.isCancelled else { return }

            if since == nil {
                index.replace(built.entries)
                swipeUUIDs = built.swipes
                thumbnailByUUID = built.thumbnails
                typeByUUID = built.types
            } else {
                let touched = Set(fetched.map(\.uuid))
                var entries = index.entries.filter { !touched.contains($0.atomUUID) }
                entries.append(contentsOf: built.entries)
                index.replace(entries)
                for uuid in touched {
                    swipeUUIDs.remove(uuid)
                    thumbnailByUUID[uuid] = nil
                    typeByUUID[uuid] = nil
                }
                swipeUUIDs.formUnion(built.swipes)
                thumbnailByUUID.merge(built.thumbnails) { _, new in new }
                typeByUUID.merge(built.types) { _, new in new }
            }
            indexStamp = fetched.map(\.updatedAt).max() ?? since ?? ISO8601.string(from: Date())
            let wasReady = isIndexReady
            isIndexReady = true
            // A query typed before the index landed only had the deep tier;
            // a browse waited on the database. Both re-paint from memory now.
            if isPresented, !wasReady || !query.isEmpty || scope != .everything {
                reload()
            }
        }
    }

    private func atomsDidChange() {
        guard isPresented else { return }
        changeTask?.cancel()
        changeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, isPresented else { return }
            refreshIndexIfNeeded()
            if query.isEmpty { reload() }
        }
    }
}
