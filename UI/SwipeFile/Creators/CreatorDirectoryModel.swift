// CosmoOS/UI/SwipeFile/Creators/CreatorDirectoryModel.swift
// The one model behind Explore ▸ Creators and every creator page: every
// creator atom, summarized ONCE off the main actor from the creator rows and
// every saved swipe (a view body never decodes metadata), the catalog a pull
// left on disk, and the verbs — pull the latest posts, save from the
// catalog, link/unlink, edit, delete. Runs the directory's repair sweep on
// arrival so twins fold before anyone sees them.
// September 2026

import SwiftUI
import Observation

// MARK: - Summary (built off-main, consumed by views)

struct CreatorTally: Identifiable, Equatable, Sendable {
    let label: String
    let count: Int
    var id: String { label }
}

struct CreatorProfileSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let handle: String
    let handleKey: String?
    let platform: SocialPlatform?
    let avatarURL: URL?
    let followerCount: Int?
    let niche: String?
    let bio: String?
    let profileURL: URL?
    let notes: String?
    let isTracked: Bool
    let savedCount: Int
    let studiedCount: Int
    let averageHookScore: Double?
    let latestSavedAt: Date?
    let topNarratives: [CreatorTally]
    let topFrameworks: [CreatorTally]
    let topFormats: [CreatorTally]
    /// Best saved swipes by hook score — the card strip and the Best Hooks shelf.
    let bestSwipeUUIDs: [String]
    let thumbnailURLs: [URL]
    let catalogCount: Int
    let catalogFetchedAt: Date?
    let createdAt: Date?

    var hasCatalog: Bool { catalogCount > 0 }
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    static func build(creators: [Atom], swipes: [Atom], catalogCounts: [String: Int]) -> [CreatorProfileSummary] {
        let byCreator: [String: [Atom]] = Dictionary(grouping: swipes) { $0.swipeAnalysis?.creatorUUID ?? "" }
        var out: [CreatorProfileSummary] = []
        out.reserveCapacity(creators.count)
        for creator in creators {
            if let summary = summary(for: creator, mine: byCreator[creator.uuid] ?? [], catalogCount: catalogCounts[creator.uuid]) {
                out.append(summary)
            }
        }
        return out
    }

    /// One creator's summary from its row and its swipes. Every derived value
    /// is a named local — the type checker gave up on the inline form.
    static func summary(for creator: Atom, mine: [Atom], catalogCount: Int?) -> CreatorProfileSummary? {
        guard let meta = creator.metadataValue(as: CreatorMetadata.self) else { return nil }
        let analyses: [SwipeAnalysis] = mine.compactMap { $0.swipeAnalysis }
        let scores: [Double] = analyses.compactMap { $0.hookScore }.filter { $0 > 0 }
        let ranked: [Atom] = mine.sorted { ($0.swipeAnalysis?.hookScore ?? 0) > ($1.swipeAnalysis?.hookScore ?? 0) }
        var thumbs: [URL] = []
        for swipe in ranked.prefix(12) where thumbs.count < 3 {
            if let url = swipe.toSwipeGalleryItem()?.thumbnailUrl.flatMap(URL.init(string:)) { thumbs.append(url) }
        }
        let handleKey: String? = CreatorIdentity.key(meta.handle)
        let displayHandle: String = handleKey.map(CreatorIdentity.displayHandle) ?? (meta.handle ?? "")
        let fallbackName: String = handleKey.map(CreatorIdentity.displayHandle) ?? "Creator"
        let title: String = (creator.title?.isEmpty == false) ? creator.title! : fallbackName
        let storedPlatform: SocialPlatform? = CreatorIdentity.platform(fromCreatorPlatform: meta.platform)
        var inferredPlatform: SocialPlatform? = storedPlatform
        if inferredPlatform == nil {
            for swipe in mine {
                if let platform = CreatorIdentity.platform(for: swipe) { inferredPlatform = platform; break }
            }
        }
        let averageScore: Double? = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let latest: Date? = mine.compactMap { ISO8601.date(from: $0.createdAt) }.max()
        let narratives: [CreatorTally] = creatorTally(analyses.compactMap { $0.primaryNarrative?.displayName })
        let frameworks: [CreatorTally] = creatorTally(analyses.compactMap { $0.frameworkType?.displayName })
        let formats: [CreatorTally] = creatorTally(analyses.compactMap { $0.swipeContentFormat?.displayName })
        let studied: Int = analyses.filter { $0.studiedAt != nil }.count
        let resolvedCatalogCount: Int = catalogCount ?? meta.catalogPostCount ?? 0
        let fetchedAt: Date? = meta.catalogFetchedAt.flatMap { ISO8601.date(from: $0) }
        let best: [String] = ranked.prefix(8).map { $0.uuid }
        return CreatorProfileSummary(
            id: creator.uuid,
            name: title,
            handle: displayHandle,
            handleKey: handleKey,
            platform: inferredPlatform,
            avatarURL: meta.thumbnailUrl.flatMap(URL.init(string:)),
            followerCount: meta.followerCount,
            niche: meta.niche,
            bio: meta.bio,
            profileURL: meta.profileUrl.flatMap(URL.init(string:)),
            notes: meta.notes,
            isTracked: meta.isActive ?? true,
            savedCount: mine.count,
            studiedCount: studied,
            averageHookScore: averageScore,
            latestSavedAt: latest,
            topNarratives: narratives,
            topFrameworks: frameworks,
            topFormats: formats,
            bestSwipeUUIDs: best,
            thumbnailURLs: thumbs,
            catalogCount: resolvedCatalogCount,
            catalogFetchedAt: fetchedAt,
            createdAt: ISO8601.date(from: creator.createdAt)
        )
    }
}

/// Top three labels by count — ties break alphabetically so the order is stable.
private func creatorTally(_ labels: [String]) -> [CreatorTally] {
    var counts: [String: Int] = [:]
    for label in labels { counts[label, default: 0] += 1 }
    let sorted = counts.sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key < rhs.key
    }
    return sorted.prefix(3).map { CreatorTally(label: $0.key, count: $0.value) }
}

// MARK: - Directory grammar

enum CreatorDirectorySort: String, CaseIterable, Identifiable {
    case recent, mostSaved, hookScore, followers, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "Recently saved"
        case .mostSaved: return "Most saved"
        case .hookScore: return "Hook score"
        case .followers: return "Followers"
        case .name: return "Name"
        }
    }
}

enum CreatorDirectoryScope: String, CaseIterable, Identifiable {
    case all, catalogued, fromSwipes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .catalogued: return "Catalogued"
        case .fromSwipes: return "From swipes"
        }
    }
}

/// A creator's pulled catalog, scored for outliers — the Catalog and
/// Outliers lanes read this; nothing in a body maps or scores.
struct CreatorCatalog: Equatable {
    var posts: [SocialPostSnapshot] = []
    var importedByID: [String: ImportedPost] = [:]
    var savedShortcodes: Set<String> = []
    var fetchedAt: Date?
    var outliers: [SocialPostSnapshot] {
        posts.filter { ($0.derived.outlierMultiplier ?? 0) >= 2 }
            .sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }
    }
    static func == (lhs: CreatorCatalog, rhs: CreatorCatalog) -> Bool {
        lhs.posts == rhs.posts && lhs.savedShortcodes == rhs.savedShortcodes && lhs.fetchedAt == rhs.fetchedAt
    }
}

// MARK: - Model

@MainActor
@Observable
final class CreatorDirectoryModel {
    private(set) var summaries: [CreatorProfileSummary] = []
    private(set) var swipesByCreator: [String: [Atom]] = [:]
    private(set) var catalogs: [String: CreatorCatalog] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var repairReport: CreatorDirectory.RepairReport?
    var errorMessage: String?
    var toast: String?

    var searchText = ""
    var sort: CreatorDirectorySort = .recent
    var scope: CreatorDirectoryScope = .all
    /// A creator another surface asked to open (the Study chip, ⌘K).
    var openRequest: String?

    // Pull state — one engine, one creator at a time.
    private(set) var pullEngine: CreatorImportEngine?
    private(set) var pullingCreatorID: String?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var didRepair = false

    init() {}

    // MARK: Lifecycle

    func start() async {
        if observers.isEmpty {
            for name in [CosmoNotification.SwipeFile.creatorDataChanged, CosmoNotification.SwipeFile.libraryDidChange] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.scheduleReload() }
                })
            }
        }
        guard !hasLoaded else { return }
        await load()
        if !didRepair {
            didRepair = true
            let report = await CreatorDirectory.shared.repair()
            if !report.isEmpty {
                repairReport = report
                toast = report.mergedCreators > 0
                    ? "Merged \(report.mergedCreators) duplicate creator\(report.mergedCreators == 1 ? "" : "s")"
                    : "Attributed \(report.attributedSwipes + report.relinkedSwipes) swipes to their creators"
                await load()
            }
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func load() async {
        generation += 1
        let mine = generation
        isLoading = summaries.isEmpty
        do {
            async let creatorsRead = AtomRepository.shared.fetchCreators()
            async let swipesRead = AtomRepository.shared.fetchSwipesByTaxonomy()
            let (creators, swipes) = try await (creatorsRead, swipesRead)
            let counts = Dictionary(uniqueKeysWithValues: creators.map { ($0.uuid, CatalogStore.load(creatorUUID: $0.uuid)?.count ?? 0) })
            let built = await Task.detached(priority: .userInitiated) {
                CreatorProfileSummary.build(creators: creators, swipes: swipes, catalogCounts: counts)
            }.value
            guard mine == generation else { return }
            summaries = built
            swipesByCreator = Dictionary(grouping: swipes.filter { $0.swipeAnalysis?.creatorUUID != nil }) { $0.swipeAnalysis!.creatorUUID! }
            errorMessage = nil
            hasLoaded = true
            // Catalogs already opened stay live (saved ticks follow the library).
            for id in catalogs.keys { await loadCatalog(for: id, force: true) }
        } catch {
            guard mine == generation else { return }
            errorMessage = "Couldn't load creators. Try again."
        }
        isLoading = false
    }

    // MARK: Reads

    func summary(id: String) -> CreatorProfileSummary? { summaries.first { $0.id == id } }

    func swipes(for id: String) -> [Atom] { swipesByCreator[id] ?? [] }

    var filtered: [CreatorProfileSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items = summaries
        if !query.isEmpty {
            let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
            items = items.filter { creator in
                let haystack = [creator.name, creator.handle, creator.niche ?? "", creator.bio ?? ""].joined(separator: " ").lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }
        switch scope {
        case .all: break
        case .catalogued: items = items.filter(\.hasCatalog)
        case .fromSwipes: items = items.filter { !$0.hasCatalog }
        }
        return sorted(items)
    }

    func sorted(_ items: [CreatorProfileSummary]) -> [CreatorProfileSummary] {
        switch sort {
        case .recent: return items.sorted { ($0.latestSavedAt ?? .distantPast) > ($1.latestSavedAt ?? .distantPast) }
        case .mostSaved: return items.sorted { $0.savedCount == $1.savedCount ? $0.name < $1.name : $0.savedCount > $1.savedCount }
        case .hookScore: return items.sorted { ($0.averageHookScore ?? 0) > ($1.averageHookScore ?? 0) }
        case .followers: return items.sorted { ($0.followerCount ?? 0) > ($1.followerCount ?? 0) }
        case .name: return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var catalogued: [CreatorProfileSummary] { filtered.filter(\.hasCatalog) }
    var fromSwipes: [CreatorProfileSummary] { filtered.filter { !$0.hasCatalog } }

    // MARK: Catalog (Apify pull, scored)

    func loadCatalog(for id: String, force: Bool = false) async {
        if !force, catalogs[id] != nil { return }
        guard let summary = summary(id: id), let posts = CatalogStore.load(creatorUUID: id), !posts.isEmpty else {
            catalogs[id] = CreatorCatalog()
            return
        }
        let profile = ImportedCreatorProfile(
            username: summary.handleKey ?? "", fullName: summary.name, biography: summary.bio,
            followerCount: summary.followerCount ?? 0, followingCount: 0, postsCount: posts.count,
            profilePicUrl: summary.avatarURL?.absoluteString, isPrivate: false, isVerified: false
        )
        let saved = (try? await AtomRepository.shared.findExistingShortcodes(posts.map(\.shortcode))) ?? []
        let built = await Task.detached(priority: .userInitiated) { () -> CreatorCatalog in
            let base = posts.map { SocialInstagramMapper.snapshot(post: $0, profile: profile) }
            let scored = base.map { post -> SocialPostSnapshot in
                let score = SocialOutlierScorer.score(post: post, creatorPosts: base)
                let rate: Double? = profile.followerCount > 0
                    ? Double((post.metrics.likes ?? 0) + (post.metrics.comments ?? 0)) / Double(profile.followerCount) : nil
                return post.replacingDerived(SocialDerivedMetrics(outlierMultiplier: score.multiplier, outlierGrade: score.grade, engagementRate: rate))
            }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            return CreatorCatalog(
                posts: scored,
                importedByID: Dictionary(uniqueKeysWithValues: posts.map { ("instagram:\($0.id)", $0) }),
                savedShortcodes: saved,
                fetchedAt: summary.catalogFetchedAt
            )
        }.value
        catalogs[id] = built
    }

    func catalog(for id: String) -> CreatorCatalog { catalogs[id] ?? CreatorCatalog() }

    func isSaved(_ post: SocialPostSnapshot, in id: String) -> Bool {
        guard let imported = catalogs[id]?.importedByID[post.id] else { return false }
        return catalogs[id]?.savedShortcodes.contains(imported.shortcode) ?? false
    }

    // MARK: Pull (the Apify catalog)

    var isPulling: Bool {
        guard let state = pullEngine?.importState else { return false }
        switch state {
        case .fetchingProfile, .fetchingPosts, .saving: return true
        default: return false
        }
    }

    var pullEstimate: ImportCostEstimate? {
        if case .awaitingConfirmation(let estimate) = pullEngine?.importState { return estimate }
        return nil
    }

    var pullProgress: (fetched: Int, total: Int)? {
        if case .fetchingPosts(let fetched, let total) = pullEngine?.importState { return (fetched, total) }
        return nil
    }

    var pullError: String? {
        if case .error(let message) = pullEngine?.importState { return message }
        return nil
    }

    var apifyConfigured: Bool { ApifyInstagramProvider.shared.isConfigured }

    /// Step 1: look the profile up so the estimate can be shown. Cheap.
    func preparePull(for id: String) async {
        guard let summary = summary(id: id), let handle = summary.handleKey else { return }
        let engine = CreatorImportEngine()
        pullEngine = engine
        pullingCreatorID = id
        await engine.loadCachedCatalog(creatorUUID: id)
        await engine.fetchProfile(handle: handle)
    }

    /// Step 2: the user confirmed the cost — pull, persist, reload.
    func confirmPull(count: Int) async {
        guard let engine = pullEngine, let id = pullingCreatorID else { return }
        await engine.fetchPosts(maxPosts: count)
        if case .error = engine.importState { return }
        await load()
        await loadCatalog(for: id, force: true)
        toast = "Pulled \(engine.importedPosts.count) posts"
        pullEngine = nil
        pullingCreatorID = nil
    }

    func cancelPull() {
        pullEngine = nil
        pullingCreatorID = nil
    }

    // MARK: Save from the catalog

    /// Saves catalog posts as swipes attributed to this creator, through the
    /// import engine (dedupe by shortcode, links both ways, batch transcription).
    func save(posts: [ImportedPost], for id: String) async -> Int {
        guard !posts.isEmpty else { return 0 }
        let engine = CreatorImportEngine()
        await engine.loadCachedCatalog(creatorUUID: id)
        for post in posts { engine.toggleSelection(post.id) }
        let saved = await engine.saveSelectedPosts()
        toast = saved == 1 ? "Saved to your swipes" : "Saved \(saved) posts to your swipes"
        await load()
        await loadCatalog(for: id, force: true)
        return saved
    }

    func save(post: SocialPostSnapshot, for id: String) async -> Atom? {
        guard let imported = catalogs[id]?.importedByID[post.id] else { return nil }
        let engine = CreatorImportEngine()
        await engine.loadCachedCatalog(creatorUUID: id)
        engine.toggleSelection(imported.id)
        _ = await engine.saveSelectedPosts()
        await load()
        await loadCatalog(for: id, force: true)
        let swipes = try? await AtomRepository.shared.fetchSwipesByTaxonomy(creatorUUID: id)
        return swipes?.first { $0.swipeAnalysis?.postShortcode == imported.shortcode }
    }

    // MARK: Verbs

    func addCreator(input: String) async -> CreatorProfileSummary? {
        let platform = CreatorIdentity.platform(fromURL: input) ?? .instagram
        guard let creator = try? await CreatorDirectory.shared.resolve(handle: input, name: nil, platform: platform) else {
            errorMessage = "Paste a profile URL or a handle, like @aliabdaal."
            return nil
        }
        await load()
        return summary(id: creator.uuid)
    }

    func update(_ id: String, name: String?, handle: String?, niche: String?, notes: String?, tracked: Bool?) async {
        _ = try? await AtomRepository.shared.update(uuid: id) { atom in
            guard var meta = atom.metadataValue(as: CreatorMetadata.self) else { return }
            if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { atom.title = name }
            if let handle, let key = CreatorIdentity.key(handle) { meta.handle = CreatorIdentity.displayHandle(key) }
            if let niche { meta.niche = niche.isEmpty ? nil : niche }
            if let notes { meta.notes = notes.isEmpty ? nil : notes }
            if let tracked { meta.isActive = tracked }
            atom = atom.withMetadata(meta)
        }
        CreatorDirectory.shared.invalidate()
        await load()
    }

    func unlink(swipeUUID: String, from id: String) async {
        await CreatorDirectory.shared.unlink(swipeUUID: swipeUUID, from: id)
        await load()
    }

    func deleteSwipe(_ uuid: String) async {
        try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: uuid)
        await load()
    }

    /// Deletes the creator record and its catalog; the saved swipes stay in
    /// the library and re-attach if the creator is ever added again.
    func delete(_ id: String) async {
        for swipe in swipes(for: id) { await CreatorDirectory.shared.unlink(swipeUUID: swipe.uuid, from: id) }
        CatalogStore.delete(creatorUUID: id)
        try? await AtomRepository.shared.delete(uuid: id)
        CreatorDirectory.shared.invalidate()
        catalogs[id] = nil
        toast = "Creator removed"
        await load()
    }

    // MARK: Opening

    func openStudy(_ atom: Atom, within order: [Atom]) {
        guard let id = atom.id, id > 0 else { return }
        SwipeStudySession.shared.begin(order: order.compactMap(\.id), current: id)
        NotificationCenter.default.post(name: .enterFocusMode, object: nil,
                                        userInfo: ["type": EntityType.research, "id": id])
    }
}
