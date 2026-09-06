// CosmoOS/SwipeFile/Instagram/CreatorImportEngine.swift
// Orchestrates importing a creator's Instagram catalog with engagement data

import Foundation
import SwiftUI

// MARK: - Import State

enum CreatorImportState: Equatable {
    case idle
    case fetchingProfile
    case awaitingConfirmation(ImportCostEstimate)
    case fetchingPosts(fetched: Int, total: Int)
    case saving(saved: Int, total: Int)
    case complete(saved: Int, enriched: Int, failed: Int)
    case error(String)

    static func == (lhs: CreatorImportState, rhs: CreatorImportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.fetchingProfile, .fetchingProfile): return true
        case (.awaitingConfirmation(let a), .awaitingConfirmation(let b)): return a == b
        case (.fetchingPosts(let a1, let a2), .fetchingPosts(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.saving(let a1, let a2), .saving(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.complete(let a1, let a2, let a3), .complete(let b1, let b2, let b3)): return a1 == b1 && a2 == b2 && a3 == b3
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Saved Filter

enum SavedFilter: String, CaseIterable, Sendable {
    case all = "All"
    case unsaved = "Unsaved"
    case saved = "Saved"
}

// MARK: - Creator Import Engine

@MainActor
@Observable
final class CreatorImportEngine {

    // MARK: - Published State

    var importState: CreatorImportState = .idle
    var importedPosts: [ImportedPost] = []
    var creatorProfile: ImportedCreatorProfile?
    var existingShortcodes: Set<String> = []
    var selectedPostIds: Set<String> = []
    var sortOption: ImportSortOption = .bestPerformers
    var autoTranscribe: Bool = true
    var isCachedCatalog: Bool = false
    var catalogAge: String?
    var typeFilter: InstagramContentType? = nil
    var savedFilter: SavedFilter = .all

    /// UUID of the creator atom (set after profile fetch or cache load)
    private(set) var creatorUUID: String?

    // MARK: - Computed

    var sortedPosts: [ImportedPost] {
        var filtered = importedPosts

        if let typeFilter {
            filtered = filtered.filter { $0.contentType == typeFilter }
        }

        switch savedFilter {
        case .all: break
        case .unsaved:
            filtered = filtered.filter { !existingShortcodes.contains($0.shortcode) }
        case .saved:
            filtered = filtered.filter { existingShortcodes.contains($0.shortcode) }
        }

        return sortOption.sort(filtered)
    }

    var selectedPosts: [ImportedPost] {
        importedPosts.filter { selectedPostIds.contains($0.id) }
    }

    var selectableCount: Int {
        importedPosts.count - existingShortcodes.count
    }

    // MARK: - Dependencies

    private let provider: InstagramDataProvider
    private let repository: AtomRepository

    init(
        provider: InstagramDataProvider = ApifyInstagramProvider.shared,
        repository: AtomRepository = .shared
    ) {
        self.provider = provider
        self.repository = repository
    }

    // MARK: - Handle Resolution

    /// Parse an Instagram URL or handle into a clean username
    func resolveHandle(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Direct handle: "@username" or "username"
        if !trimmed.contains("/") && !trimmed.contains(".") {
            return trimmed.replacingOccurrences(of: "@", with: "")
        }

        // URL patterns: instagram.com/username, www.instagram.com/username
        if let url = URL(string: trimmed),
           let host = url.host,
           host.contains("instagram.com") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = path.split(separator: "/")
            if let first = components.first {
                let username = String(first)
                // Skip non-profile paths
                let reserved = ["p", "reel", "reels", "stories", "explore", "accounts", "about"]
                if !reserved.contains(username) {
                    return username
                }
            }
        }

        // Fallback: try extracting from arbitrary text
        if let match = trimmed.range(of: "(?:@|instagram\\.com/)([a-zA-Z0-9._]+)", options: .regularExpression) {
            let captured = trimmed[match]
            let handle = captured.replacingOccurrences(of: "@", with: "")
                .replacingOccurrences(of: "instagram.com/", with: "")
            if !handle.isEmpty { return handle }
        }

        return nil
    }

    // MARK: - Pipeline Steps

    /// Step 1: Fetch the creator's profile
    func fetchProfile(handle: String) async {
        guard provider.isConfigured else {
            importState = .error(ImportError.apiKeyMissing.localizedDescription)
            return
        }

        importState = .fetchingProfile

        do {
            let profile = try await provider.fetchProfile(handle: handle)
            self.creatorProfile = profile

            // Estimate cost
            let estimate = provider.estimateCost(postCount: min(profile.postsCount, 1000))
            importState = .awaitingConfirmation(estimate)
        } catch let error as ImportError {
            importState = .error(error.localizedDescription)
        } catch {
            importState = .error("Failed to fetch profile: \(error.localizedDescription)")
        }
    }

    /// Step 2: Fetch posts (after user confirms cost)
    func fetchPosts(maxPosts: Int) async {
        guard let profile = creatorProfile else { return }

        importState = .fetchingPosts(fetched: 0, total: maxPosts)

        do {
            let posts = try await provider.fetchPosts(
                handle: profile.username,
                maxPosts: maxPosts,
                onProgress: { [weak self] fetched, total in
                    Task { @MainActor in
                        self?.importState = .fetchingPosts(fetched: fetched, total: total)
                    }
                }
            )

            self.importedPosts = posts

            // Check for duplicates
            let shortcodes = posts.map(\.shortcode)
            self.existingShortcodes = try await repository.findExistingShortcodes(shortcodes)

            // Persist catalog to disk
            await persistCatalog(posts: posts)

            importState = .idle
        } catch let error as ImportError {
            importState = .error(error.localizedDescription)
        } catch {
            importState = .error("Failed to fetch posts: \(error.localizedDescription)")
        }
    }

    /// Step 3: Save selected posts as swipe atoms
    func saveSelectedPosts() async -> Int {
        let postsToSave = selectedPosts.filter { !existingShortcodes.contains($0.shortcode) }
        guard !postsToSave.isEmpty else { return 0 }

        importState = .saving(saved: 0, total: postsToSave.count)

        // Resolve or create creator atom
        let creatorAtom: Atom
        do {
            creatorAtom = try await resolveOrCreateCreator()
            self.creatorUUID = creatorAtom.uuid
        } catch {
            importState = .error("Failed to resolve creator: \(error.localizedDescription)")
            return 0
        }

        var savedCount = 0
        var savedAtomUUIDs: [String] = []
        var transcribableUUIDs: [String] = []
        // Track which posts ACTUALLY saved — marking `prefix(savedCount)` as
        // existing mislabeled posts when a failure happened mid-batch.
        var savedShortcodes: [String] = []
        var failedShortcodes: [String] = []

        for post in postsToSave {
            do {
                let atom = try await savePostAsSwipe(post, creatorAtom: creatorAtom)
                savedAtomUUIDs.append(atom.uuid)
                savedShortcodes.append(post.shortcode)
                savedCount += 1
                importState = .saving(saved: savedCount, total: postsToSave.count)

                // Collect UUIDs for batch transcription (video + carousel)
                if autoTranscribe && (post.contentType.isVideo || post.contentType == .carousel) {
                    transcribableUUIDs.append(atom.uuid)
                }
            } catch {
                failedShortcodes.append(post.shortcode)
                print("[CreatorImport] Failed to save post \(post.shortcode): \(error)")
                PersistenceHealth.note(
                    .writeFailure,
                    context: "CreatorImportEngine.saveSelectedPosts",
                    detail: "post \(post.shortcode) failed to save: \(error.localizedDescription)"
                )
            }
        }

        // Fire batch transcription after all saves complete (parallel, max 3 concurrent)
        if !transcribableUUIDs.isEmpty {
            SwipeProcessingService.shared.processBatch(uuids: transcribableUUIDs)
        }

        // Update creator stats
        let enrichedCount = await enrichExistingSwipes(creatorUUID: creatorAtom.uuid)
        await updateCreatorStats(creatorAtom)

        // Add the ACTUALLY-saved shortcodes to the existing set
        for shortcode in savedShortcodes {
            existingShortcodes.insert(shortcode)
        }
        selectedPostIds.removeAll()

        if !failedShortcodes.isEmpty {
            print("[CreatorImport] \(failedShortcodes.count) post(s) failed to save: \(failedShortcodes.joined(separator: ", "))")
        }
        importState = .complete(saved: savedCount, enriched: enrichedCount, failed: failedShortcodes.count)

        // Notify views to refresh
        NotificationCenter.default.post(
            name: CosmoNotification.SwipeFile.creatorDataChanged,
            object: nil,
            userInfo: ["creatorUUID": creatorAtom.uuid]
        )

        return savedCount
    }

    // MARK: - Selection Helpers

    func toggleSelection(_ postId: String) {
        if selectedPostIds.contains(postId) {
            selectedPostIds.remove(postId)
        } else {
            // Only allow selecting non-duplicate posts
            if let post = importedPosts.first(where: { $0.id == postId }),
               !existingShortcodes.contains(post.shortcode) {
                selectedPostIds.insert(postId)
            }
        }
    }

    func selectTopN(_ n: Int) {
        let sorted = sortOption.sort(importedPosts)
        let selectable = sorted.filter { !existingShortcodes.contains($0.shortcode) }
        selectedPostIds = Set(selectable.prefix(n).map(\.id))
    }

    func selectAllReels() {
        let reels = importedPosts.filter {
            $0.contentType == .reel && !existingShortcodes.contains($0.shortcode)
        }
        selectedPostIds = Set(reels.map(\.id))
    }

    func selectAll() {
        let selectable = importedPosts.filter { !existingShortcodes.contains($0.shortcode) }
        selectedPostIds = Set(selectable.map(\.id))
    }

    func deselectAll() {
        selectedPostIds.removeAll()
    }

    func reset() {
        importState = .idle
        importedPosts = []
        creatorProfile = nil
        existingShortcodes = []
        selectedPostIds = []
        isCachedCatalog = false
        catalogAge = nil
        creatorUUID = nil
        typeFilter = nil
        savedFilter = .all
    }

    // MARK: - Catalog Persistence

    /// Load a previously cached catalog from disk for an existing creator
    func loadCachedCatalog(creatorUUID: String) async {
        self.creatorUUID = creatorUUID

        guard let posts = CatalogStore.load(creatorUUID: creatorUUID) else {
            return
        }

        self.importedPosts = posts
        self.isCachedCatalog = true

        // Rebuild profile from creator atom metadata (by uuid — a platform
        // filter would miss a creator the repair sweep has just healed).
        do {
            if let creatorAtom = try await repository.fetch(uuid: creatorUUID),
               let meta = creatorAtom.metadataValue(as: CreatorMetadata.self) {
                creatorProfile = ImportedCreatorProfile(
                    username: meta.handle?.replacingOccurrences(of: "@", with: "") ?? "",
                    fullName: creatorAtom.title,
                    biography: meta.bio,
                    followerCount: meta.followerCount ?? 0,
                    followingCount: meta.followingCount ?? 0,
                    postsCount: meta.postsCount ?? 0,
                    profilePicUrl: meta.thumbnailUrl,
                    isPrivate: false,
                    isVerified: false
                )

                // Compute catalog age
                if let fetchedAt = meta.catalogFetchedAt,
                   let date = ISO8601.date(from: fetchedAt) {
                    catalogAge = formatCatalogAge(from: date)
                }
            }
        } catch {
            print("[CreatorImport] Failed to load creator metadata: \(error)")
        }

        // Rebuild existing shortcodes
        let shortcodes = posts.map(\.shortcode)
        self.existingShortcodes = (try? await repository.findExistingShortcodes(shortcodes)) ?? []
    }

    /// Persist the current catalog to disk and update creator metadata
    private func persistCatalog(posts: [ImportedPost]) async {
        // Resolve creator UUID if not already set
        if creatorUUID == nil {
            do {
                let creatorAtom = try await resolveOrCreateCreator()
                creatorUUID = creatorAtom.uuid
            } catch {
                print("[CreatorImport] Failed to resolve creator for catalog persistence: \(error)")
                return
            }
        }

        guard let uuid = creatorUUID else { return }

        // A pull is cumulative: the newest fetch joins what earlier pulls
        // found (fresh rows win by shortcode), so "pull the latest" never
        // forgets the outliers from a year ago.
        let posts = Self.merge(cached: CatalogStore.load(creatorUUID: uuid) ?? [], fresh: posts)
        importedPosts = posts

        // Save catalog to disk
        do {
            try CatalogStore.save(posts: posts, forCreator: uuid)
        } catch {
            print("[CreatorImport] Failed to save catalog to disk: \(error)")
            return
        }

        // Update creator metadata with catalog info
        do {
            _ = try await repository.update(uuid: uuid) { atom in
                guard var meta = atom.metadataValue(as: CreatorMetadata.self) else { return }
                meta.catalogPostCount = posts.count
                meta.catalogFetchedAt = ISO8601.string(from: Date())
                if let encoded = try? JSONEncoder().encode(meta),
                   let jsonStr = String(data: encoded, encoding: .utf8) {
                    atom.metadata = jsonStr
                }
            }
        } catch {
            print("[CreatorImport] Failed to update creator catalog metadata: \(error)")
        }

        // Notify views to refresh (new creator or catalog update)
        NotificationCenter.default.post(
            name: CosmoNotification.SwipeFile.creatorDataChanged,
            object: nil,
            userInfo: ["creatorUUID": uuid]
        )
    }

    /// Fresh rows replace cached rows with the same shortcode; everything
    /// else survives. Newest first.
    static func merge(cached: [ImportedPost], fresh: [ImportedPost]) -> [ImportedPost] {
        var byShortcode: [String: ImportedPost] = [:]
        for post in cached { byShortcode[post.shortcode] = post }
        for post in fresh { byShortcode[post.shortcode] = post }
        return byShortcode.values.sorted { $0.timestamp > $1.timestamp }
    }

    private func formatCatalogAge(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let hours = Int(interval / 3600)
        if hours < 1 { return "Fetched just now" }
        if hours < 24 { return "Fetched \(hours)h ago" }
        let days = hours / 24
        if days == 1 { return "Fetched yesterday" }
        return "Fetched \(days) days ago"
    }

    // MARK: - Private: Save Post

    private func savePostAsSwipe(_ post: ImportedPost, creatorAtom: Atom) async throws -> Atom {
        // Build research metadata
        let researchMeta = ResearchMetadata(
            url: post.url.absoluteString,
            thumbnailUrl: post.thumbnailUrl?.absoluteString,
            hook: extractHook(from: post.caption),
            isSwipeFile: true,
            contentSource: "creator_import"
        )

        let metadataJSON = try String(data: JSONEncoder().encode(researchMeta), encoding: .utf8)

        // Build swipe analysis with engagement data
        var analysis = SwipeAnalysis(
            analysisVersion: 1,
            isFullyAnalyzed: false,
            creatorUUID: creatorAtom.uuid,
            likesCount: post.engagement.likesCount,
            viewsCount: post.engagement.viewsCount,
            commentsCount: post.engagement.commentsCount,
            sharesCount: post.engagement.sharesCount,
            engagementRate: post.engagement.engagementRate,
            publishedAt: post.timestamp,
            postShortcode: post.shortcode
        )

        // Store hook text from caption
        if let hook = extractHook(from: post.caption) {
            analysis.hookText = hook
        }

        // Create atom
        var atom = Atom.new(
            type: .research,
            title: extractHook(from: post.caption) ?? post.caption?.prefix(100).description ?? "Imported post",
            body: post.caption,
            metadata: metadataJSON,
            links: [.swipeToCreator(creatorAtom.uuid)]
        )

        // Set swipe analysis
        atom = atom.withSwipeAnalysis(analysis)

        // Store autoMetadata for platform detection (used by toSwipeGalleryItem)
        if let structuredStr = atom.structured,
           let data = structuredStr.data(using: .utf8),
           var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var autoMeta: [String: Any] = [
                "sourceType": "instagram",
                "instagramType": post.contentType.rawValue,
                "author": post.ownerUsername
            ]
            if let duration = post.videoUrl != nil ? 0 : nil {
                autoMeta["duration"] = duration
            }
            autoMeta["instagramId"] = post.shortcode
            if let encoded = try? JSONSerialization.data(withJSONObject: autoMeta),
               let autoMetaStr = String(data: encoded, encoding: .utf8) {
                dict["autoMetadata"] = autoMetaStr
            }
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                atom.structured = jsonStr
            }
        }

        // Persist carousel items from Apify so transcription can use them
        if let items = post.carouselItems, !items.isEmpty {
            var rc = atom.richContent ?? ResearchRichContent()
            var igData = rc.instagramData ?? InstagramData(
                originalURL: post.url,
                contentType: .carousel
            )
            igData.carouselItems = items
            rc.instagramData = igData
            rc.sourceType = .instagramCarousel
            rc.instagramType = "carousel"
            atom.setRichContent(rc)
        }

        let savedAtom = try await repository.create(atom)

        // Add inverse link on creator
        _ = try? await repository.update(uuid: creatorAtom.uuid) { creator in
            creator = creator.addingLink(.creatorToSwipe(savedAtom.uuid))
        }

        return savedAtom
    }

    // MARK: - Private: Creator Resolution

    private func resolveOrCreateCreator() async throws -> Atom {
        guard let profile = creatorProfile else {
            throw ImportError.apiError("No profile loaded")
        }
        // The one directory: a creator the classifier minted from a captured
        // post (any platform spelling, any handle casing) is the same creator.
        guard let creator = try await CreatorDirectory.shared.resolve(
            handle: profile.username, name: profile.fullName, platform: .instagram
        ) else { throw ImportError.apiError("Could not resolve @\(profile.username)") }
        return try await updateCreatorFromProfile(creator, profile: profile)
    }

    private func updateCreatorFromProfile(_ creator: Atom, profile: ImportedCreatorProfile) async throws -> Atom {
        guard var meta = creator.metadataValue(as: CreatorMetadata.self) else { return creator }

        meta.followerCount = profile.followerCount
        meta.followingCount = profile.followingCount
        meta.postsCount = profile.postsCount
        meta.bio = profile.biography
        meta.thumbnailUrl = profile.profilePicUrl
        meta.profileUrl = "https://www.instagram.com/\(profile.username)/"
        meta.lastImportedAt = ISO8601.string(from: Date())

        var updated = creator
        if let encoded = try? JSONEncoder().encode(meta),
           let jsonStr = String(data: encoded, encoding: .utf8) {
            updated.metadata = jsonStr
        }
        if updated.title?.isEmpty ?? true || updated.title == profile.username {
            updated.title = profile.fullName ?? profile.username
        }
        return try await repository.update(updated)
    }

    // MARK: - Private: Enrichment

    /// Match imported posts to existing swipes and merge engagement data
    private func enrichExistingSwipes(creatorUUID: String) async -> Int {
        guard !importedPosts.isEmpty else { return 0 }

        do {
            let existingSwipes = try await repository.fetchSwipesByTaxonomy(creatorUUID: creatorUUID)
            var enrichedCount = 0

            // Build lookup by URL and shortcode
            var postByShortcode: [String: ImportedPost] = [:]
            for post in importedPosts {
                postByShortcode[post.shortcode] = post
            }

            for swipe in existingSwipes {
                guard var analysis = swipe.swipeAnalysis else { continue }

                // Already has engagement data? Skip
                if analysis.likesCount != nil { continue }

                // Try matching by shortcode
                if let shortcode = analysis.postShortcode,
                   let post = postByShortcode[shortcode] {
                    analysis.likesCount = post.engagement.likesCount
                    analysis.viewsCount = post.engagement.viewsCount
                    analysis.commentsCount = post.engagement.commentsCount
                    analysis.sharesCount = post.engagement.sharesCount
                    analysis.engagementRate = post.engagement.engagementRate
                    analysis.publishedAt = post.timestamp
                    let updated = swipe.withSwipeAnalysis(analysis)
                    _ = try await repository.update(updated)
                    enrichedCount += 1
                    continue
                }

                // Try matching by URL
                if let swipeURL = swipe.researchMetadata?.url {
                    let matchingPost = importedPosts.first { post in
                        swipeURL.contains(post.shortcode)
                    }
                    if let post = matchingPost {
                        analysis.likesCount = post.engagement.likesCount
                        analysis.viewsCount = post.engagement.viewsCount
                        analysis.commentsCount = post.engagement.commentsCount
                        analysis.sharesCount = post.engagement.sharesCount
                        analysis.engagementRate = post.engagement.engagementRate
                        analysis.publishedAt = post.timestamp
                        analysis.postShortcode = post.shortcode
                        let updated = swipe.withSwipeAnalysis(analysis)
                        _ = try await repository.update(updated)
                        enrichedCount += 1
                    }
                }
            }

            return enrichedCount
        } catch {
            print("[CreatorImport] Enrichment failed: \(error)")
            return 0
        }
    }

    // MARK: - Private: Stats Update

    private func updateCreatorStats(_ creatorAtom: Atom) async {
        do {
            let swipes = try await repository.fetchSwipesByTaxonomy(creatorUUID: creatorAtom.uuid)
            guard var meta = creatorAtom.metadataValue(as: CreatorMetadata.self) else { return }

            meta.swipeCount = swipes.count
            meta.totalPostsImported = importedPosts.count

            // Compute aggregate engagement
            let analyses = swipes.compactMap(\.swipeAnalysis)
            let likes = analyses.compactMap(\.likesCount)
            let views = analyses.compactMap(\.viewsCount)
            let comments = analyses.compactMap(\.commentsCount)

            if !likes.isEmpty {
                meta.averageLikes = Double(likes.reduce(0, +)) / Double(likes.count)
            }
            if !views.isEmpty {
                meta.averageViews = Double(views.reduce(0, +)) / Double(views.count)
            }
            if !comments.isEmpty {
                meta.averageComments = Double(comments.reduce(0, +)) / Double(comments.count)
            }

            // Median engagement rate
            let rates = analyses.compactMap(\.engagementRate).sorted()
            if !rates.isEmpty {
                meta.medianEngagementRate = rates[rates.count / 2]
            }

            // Average hook score
            let hookScores = analyses.compactMap(\.hookScore)
            if !hookScores.isEmpty {
                meta.averageHookScore = hookScores.reduce(0, +) / Double(hookScores.count)
            }

            // Top narratives
            let narrativeCounts = Dictionary(
                analyses.compactMap(\.primaryNarrative).map { ($0.rawValue, 1) },
                uniquingKeysWith: +
            )
            meta.topNarratives = Array(narrativeCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key))

            // Top formats
            let formatCounts = Dictionary(
                analyses.compactMap(\.swipeContentFormat).map { ($0.rawValue, 1) },
                uniquingKeysWith: +
            )
            meta.topFormats = Array(formatCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key))

            var updated = creatorAtom
            if let encoded = try? JSONEncoder().encode(meta),
               let jsonStr = String(data: encoded, encoding: .utf8) {
                updated.metadata = jsonStr
            }
            _ = try await repository.update(updated)
        } catch {
            print("[CreatorImport] Stats update failed: \(error)")
        }
    }

    // MARK: - Private: Helpers

    private func extractHook(from caption: String?) -> String? {
        guard let caption, !caption.isEmpty else { return nil }
        // First sentence or first line, up to 500 chars
        let firstLine = caption.components(separatedBy: CharacterSet.newlines).first ?? caption
        let hook = String(firstLine.prefix(500))
        return hook.isEmpty ? nil : hook
    }
}
