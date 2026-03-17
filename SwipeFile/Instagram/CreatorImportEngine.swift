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
    case complete(saved: Int, enriched: Int)
    case error(String)

    static func == (lhs: CreatorImportState, rhs: CreatorImportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.fetchingProfile, .fetchingProfile): return true
        case (.awaitingConfirmation(let a), .awaitingConfirmation(let b)): return a == b
        case (.fetchingPosts(let a1, let a2), .fetchingPosts(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.saving(let a1, let a2), .saving(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.complete(let a1, let a2), .complete(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
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

    // MARK: - Computed

    var sortedPosts: [ImportedPost] {
        sortOption.sort(importedPosts)
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
        } catch {
            importState = .error("Failed to resolve creator: \(error.localizedDescription)")
            return 0
        }

        var savedCount = 0
        var savedAtomUUIDs: [String] = []

        for post in postsToSave {
            do {
                let atom = try await savePostAsSwipe(post, creatorAtom: creatorAtom)
                savedAtomUUIDs.append(atom.uuid)
                savedCount += 1
                importState = .saving(saved: savedCount, total: postsToSave.count)

                // Trigger auto-transcription for video content
                if autoTranscribe && post.contentType.isVideo {
                    SwipeProcessingService.shared.processSwipeInBackground(uuid: atom.uuid)
                }
            } catch {
                print("[CreatorImport] Failed to save post \(post.shortcode): \(error)")
            }
        }

        // Update creator stats
        let enrichedCount = await enrichExistingSwipes(creatorUUID: creatorAtom.uuid)
        await updateCreatorStats(creatorAtom)

        // Add saved shortcodes to existing set
        for post in postsToSave.prefix(savedCount) {
            existingShortcodes.insert(post.shortcode)
        }
        selectedPostIds.removeAll()

        importState = .complete(saved: savedCount, enriched: enrichedCount)
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

        let handle = "@\(profile.username)"

        // Check if creator already exists
        let existingCreators = try await repository.fetchCreators(platform: "instagram")
        if let existing = existingCreators.first(where: {
            $0.metadataValue(as: CreatorMetadata.self)?.handle?.lowercased() == handle.lowercased()
        }) {
            // Update with latest profile data
            return try await updateCreatorFromProfile(existing, profile: profile)
        }

        // Create new creator
        var creator = try await repository.createCreator(
            name: profile.fullName ?? profile.username,
            handle: handle,
            platform: "instagram"
        )

        // Enrich with profile data
        creator = try await updateCreatorFromProfile(creator, profile: profile)
        return creator
    }

    private func updateCreatorFromProfile(_ creator: Atom, profile: ImportedCreatorProfile) async throws -> Atom {
        guard var meta = creator.metadataValue(as: CreatorMetadata.self) else { return creator }

        meta.followerCount = profile.followerCount
        meta.followingCount = profile.followingCount
        meta.postsCount = profile.postsCount
        meta.bio = profile.biography
        meta.thumbnailUrl = profile.profilePicUrl
        meta.profileUrl = "https://www.instagram.com/\(profile.username)/"
        meta.lastImportedAt = ISO8601DateFormatter().string(from: Date())

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
