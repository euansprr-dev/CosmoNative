import Foundation
import SwiftUI

// Extracted from the SwipeFileHomeView monolith (June 2026 rebuild). Logic is
// unchanged; additions are the pillar topic scope at the bottom.
@MainActor
@Observable
final class SwipeDiscoverModel {
    var query = SocialDiscoveryQuery()
    var creatorSearchText = ""
    var creatorSortMode: SocialDiscoverySort = .highestOutlier
    private(set) var posts: [SocialPostSnapshot] = []
    private(set) var creators: [SwipeCreatorRecord] = []
    private(set) var isLoading = false
    private(set) var isAddingCreator = false
    var errorMessage: String?
    var saveMessage: String?
    var creatorImportMessage: String?
    var creatorImportError: String?

    private var hasLoaded = false
    private let remoteStore = SocialDiscoveryRemoteStore()
    private let localCache = SocialDiscoveryLocalCache()

    // NOTE: no eager cache restore in init — MainView owns this model from app
    // launch, and reload() already serves the disk cache on first page open.
    init() {}

    var visiblePosts: [SocialPostSnapshot] {
        SocialDiscoveryStore(query: query, posts: posts).visiblePosts
    }

    var filteredCreators: [SwipeCreatorRecord] {
        let trimmedQuery = creatorSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var filtered = creators
        if !trimmedQuery.isEmpty {
            filtered = filtered.filter {
                $0.name.lowercased().contains(trimmedQuery) ||
                $0.handle.lowercased().contains(trimmedQuery) ||
                ($0.niche?.lowercased().contains(trimmedQuery) ?? false)
            }
        }

        switch creatorSortMode {
        case .highestOutlier:
            filtered.sort { ($0.topOutlierMultiplier ?? 0) > ($1.topOutlierMultiplier ?? 0) }
        case .mostViewed:
            filtered.sort { $0.totalViews > $1.totalViews }
        case .mostLiked:
            filtered.sort { $0.totalLikes > $1.totalLikes }
        case .mostCommented:
            filtered.sort { $0.totalComments > $1.totalComments }
        case .mostShared:
            filtered.sort { $0.postCount > $1.postCount }
        case .newest:
            filtered.sort { ($0.latestPostDate ?? .distantPast) > ($1.latestPostDate ?? .distantPast) }
        }
        return filtered
    }

    func creator(id: String) -> SwipeCreatorRecord? {
        creators.first { $0.id == id }
    }

    func posts(for creator: SwipeCreatorRecord) -> [SocialPostSnapshot] {
        posts.filter { $0.author.platformID == creator.id || "@\($0.author.handle)" == creator.handle }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        errorMessage = nil

        do {
            if remoteStore.isConfigured {
                if let cached = localCache.load() {
                    applyCachedDiscovery(cached)
                    isLoading = false
                    return
                }

                await loadRemoteDiscovery(showLoading: true)
                return
            }

            isLoading = true
            let loaded = try await loadLocalCatalog()
            creators = loaded.records
            posts = loaded.posts
            hasLoaded = true
        } catch {
            do {
                let loaded = try await loadLocalCatalog()
                creators = loaded.records
                posts = loaded.posts
                errorMessage = "Cloud discovery failed: \(error.localizedDescription). Showing local imports."
                hasLoaded = true
            } catch {
                errorMessage = "Could not load discovery data: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    private func restoreCachedDiscoveryIfAvailable() {
        guard remoteStore.isConfigured, let cached = localCache.load() else { return }
        applyCachedDiscovery(cached)
        isLoading = false
    }

    private func applyCachedDiscovery(_ cached: SocialDiscoveryLocalCache.Payload) {
        posts = cached.posts
        creators = remoteCreatorRecords(creators: cached.creators, posts: cached.posts)
        hasLoaded = true
    }

    private func loadRemoteDiscovery(showLoading: Bool) async {
        if showLoading {
            isLoading = true
        }
        errorMessage = nil

        var remoteQuery = query
        remoteQuery.searchText = ""
        remoteQuery.platforms = []
        remoteQuery.minimumOutlierMultiplier = nil
        remoteQuery.postedWindow = .allTime
        remoteQuery.limit = 1_000

        do {
            let remoteCreators = try await remoteStore.fetchCreators()
            if posts.isEmpty {
                creators = remoteCreatorRecords(creators: remoteCreators, posts: posts)
                hasLoaded = true
            }

            do {
                let remotePosts = try await remoteStore.fetchPosts(query: remoteQuery, creators: remoteCreators)
                posts = remotePosts
                creators = remoteCreatorRecords(creators: remoteCreators, posts: remotePosts)
                try? localCache.save(posts: remotePosts, creators: remoteCreators)
            } catch {
                errorMessage = "Cloud posts are still loading: \(error.localizedDescription)"
            }

            hasLoaded = true
        } catch {
            if posts.isEmpty {
                do {
                    let loaded = try await loadLocalCatalog()
                    creators = loaded.records
                    posts = loaded.posts
                    errorMessage = "Cloud discovery failed: \(error.localizedDescription). Showing local imports."
                    hasLoaded = true
                } catch {
                    errorMessage = "Could not load discovery data: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Cloud discovery failed: \(error.localizedDescription). Showing cached results."
            }
        }

        if showLoading {
            isLoading = false
        }
    }

    func refreshDiscovery() async {
        guard remoteStore.isConfigured else {
            await reload()
            return
        }

        isLoading = true
        errorMessage = nil

        await loadRemoteDiscovery(showLoading: false)
        saveMessage = "Discovery reloaded"
        isLoading = false
    }

    func save(_ post: SocialPostSnapshot, boardID: String? = nil) {
        Task {
            do {
                try await savePost(post, boardID: boardID)
                saveMessage = boardID == nil ? "Saved to All Swipes" : "Saved to board"
            } catch {
                saveMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    func addCreatorFromSearch() {
        let rawInput = creatorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }
        guard remoteStore.isConfigured else {
            creatorImportError = "Discovery API is not configured. Add the Discovery API Base URL and Discovery API Key in Settings."
            return
        }
        guard let identity = SocialPlatformResolver.resolve(input: rawInput) else {
            creatorImportError = "Paste a profile URL or use platform:handle, like youtube:aliabdaal."
            return
        }
        guard !isAddingCreator else { return }

        isAddingCreator = true
        creatorImportError = nil
        creatorImportMessage = "Adding \(identity.handle) to the discovery graph..."
        creatorSearchText = ""

        Task {
            defer { isAddingCreator = false }

            do {
                let sourceID = try await remoteStore.addCreator(identity: identity)
                creatorImportMessage = "Creator added. Loading profile..."
                hasLoaded = false
                await reload()
                creatorImportMessage = "Creator added. Importing posts from Apify. This can take a few minutes..."

                do {
                    let result = try await remoteStore.refreshSource(sourceID: sourceID)
                    creatorImportMessage = "Import finished. \(result.upserted) posts added from \(result.provider). Reloading creators..."
                } catch {
                    creatorImportError = "Creator was added, but the import did not finish: \(error.localizedDescription)"
                }

                await loadRemoteDiscovery(showLoading: false)
                if creatorImportError == nil {
                    creatorImportMessage = "Creator imported"
                    saveMessage = "Creator imported"
                }
            } catch {
                creatorImportError = "Could not add creator: \(error.localizedDescription)"
                creatorImportMessage = nil
            }
        }
    }

    private func loadLocalCatalog() async throws -> (posts: [SocialPostSnapshot], records: [SwipeCreatorRecord]) {
        let creatorAtoms = try await AtomRepository.shared.fetchCreators()
        return loadCatalogSnapshots(from: creatorAtoms)
    }

    private func remoteCreatorRecords(
        creators remoteCreators: [SocialDiscoveryRemoteCreator],
        posts: [SocialPostSnapshot]
    ) -> [SwipeCreatorRecord] {
        let postsByCreator = Dictionary(grouping: posts, by: { $0.author.platformID })

        let records = remoteCreators.map { creator in
            let creatorPosts = postsByCreator[creator.uuid] ?? []
            return SwipeCreatorRecord(
                id: creator.uuid,
                name: creator.displayName ?? creator.handle,
                handle: "@\(creator.handle)",
                platform: creator.platform,
                avatarURL: creator.avatarURL,
                followerCount: creator.followerCount,
                niche: nil,
                bio: creator.bio,
                postCount: creatorPosts.count,
                totalViews: creatorPosts.compactMap(\.metrics.views).reduce(0, +),
                totalLikes: creatorPosts.compactMap(\.metrics.likes).reduce(0, +),
                totalComments: creatorPosts.compactMap(\.metrics.comments).reduce(0, +),
                topOutlierMultiplier: creatorPosts.compactMap(\.derived.outlierMultiplier).max(),
                latestPostDate: creatorPosts.compactMap(\.publishedAt).max(),
                topPosts: Array(creatorPosts.sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }.prefix(3))
            )
        }

        if !records.isEmpty {
            return records
        }

        return postsByCreator.map { creatorID, creatorPosts in
            let firstPost = creatorPosts[0]
            return SwipeCreatorRecord(
                id: creatorID,
                name: firstPost.author.displayName,
                handle: "@\(firstPost.author.handle)",
                platform: firstPost.platform,
                avatarURL: firstPost.author.avatarURL,
                followerCount: firstPost.author.followerCount,
                niche: nil,
                bio: nil,
                postCount: creatorPosts.count,
                totalViews: creatorPosts.compactMap(\.metrics.views).reduce(0, +),
                totalLikes: creatorPosts.compactMap(\.metrics.likes).reduce(0, +),
                totalComments: creatorPosts.compactMap(\.metrics.comments).reduce(0, +),
                topOutlierMultiplier: creatorPosts.compactMap(\.derived.outlierMultiplier).max(),
                latestPostDate: creatorPosts.compactMap(\.publishedAt).max(),
                topPosts: Array(creatorPosts.sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }.prefix(3))
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func loadCatalogSnapshots(from creatorAtoms: [Atom]) -> (posts: [SocialPostSnapshot], records: [SwipeCreatorRecord]) {
        var allPosts: [SocialPostSnapshot] = []
        var records: [SwipeCreatorRecord] = []

        for creator in creatorAtoms {
            guard let metadata = creator.metadataValue(as: CreatorMetadata.self),
                  let catalogPosts = CatalogStore.load(creatorUUID: creator.uuid),
                  !catalogPosts.isEmpty else {
                continue
            }

            let handle = (metadata.handle ?? creator.title ?? "unknown")
                .replacingOccurrences(of: "@", with: "")
            let profile = ImportedCreatorProfile(
                username: handle,
                fullName: creator.title,
                biography: metadata.bio,
                followerCount: metadata.followerCount ?? 0,
                followingCount: metadata.followingCount ?? 0,
                postsCount: metadata.postsCount ?? catalogPosts.count,
                profilePicUrl: metadata.thumbnailUrl,
                isPrivate: false,
                isVerified: false
            )

            let basePosts = catalogPosts.map {
                SocialInstagramMapper.snapshot(post: $0, profile: profile)
            }
            let scoredPosts = score(posts: basePosts)
            allPosts.append(contentsOf: scoredPosts)

            records.append(
                SwipeCreatorRecord(
                    id: creator.uuid,
                    name: creator.title ?? profile.fullName ?? handle,
                    handle: "@\(handle)",
                    platform: .instagram,
                    avatarURL: metadata.thumbnailUrl.flatMap(URL.init(string:)),
                    followerCount: metadata.followerCount,
                    niche: metadata.niche,
                    bio: metadata.bio,
                    postCount: scoredPosts.count,
                    totalViews: scoredPosts.compactMap(\.metrics.views).reduce(0, +),
                    totalLikes: scoredPosts.compactMap(\.metrics.likes).reduce(0, +),
                    totalComments: scoredPosts.compactMap(\.metrics.comments).reduce(0, +),
                    topOutlierMultiplier: scoredPosts.compactMap(\.derived.outlierMultiplier).max(),
                    latestPostDate: scoredPosts.compactMap(\.publishedAt).max(),
                    topPosts: Array(scoredPosts.sorted { ($0.derived.outlierMultiplier ?? 0) > ($1.derived.outlierMultiplier ?? 0) }.prefix(3))
                )
            )
        }

        return (allPosts, records)
    }

    private func score(posts: [SocialPostSnapshot]) -> [SocialPostSnapshot] {
        posts.map { post in
            let score = SocialOutlierScorer.score(post: post, creatorPosts: posts)
            let derived = SocialDerivedMetrics(
                outlierMultiplier: score.multiplier,
                outlierGrade: score.grade,
                engagementRate: engagementRate(for: post)
            )
            return post.replacingDerived(derived)
        }
    }

    private func engagementRate(for post: SocialPostSnapshot) -> Double? {
        guard let followerCount = post.author.followerCount, followerCount > 0 else { return nil }
        let engagements = (post.metrics.likes ?? 0)
            + (post.metrics.comments ?? 0)
            + (post.metrics.shares ?? 0)
            + (post.metrics.reposts ?? 0)
        return Double(engagements) / Double(followerCount)
    }

    private func savePost(_ post: SocialPostSnapshot, boardID: String?) async throws {
        if post.provider == "cloud-discovery", remoteStore.isConfigured {
            try await remoteStore.savePost(postID: post.id, boardID: boardID)
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil)
            return
        }

        _ = try await createLocalSwipeAtom(from: post, boardID: boardID)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil)
    }

    /// Creates a local Swipe File atom from a discovered post and returns it (with its row id).
    /// Used both by the board-save flow and the Transcript launch flow, where we need the
    /// atom's id immediately to open the swipe teardown focus mode.
    @discardableResult
    private func createLocalSwipeAtom(from post: SocialPostSnapshot, boardID: String?) async throws -> Atom {
        let hook = post.title ?? post.body?.components(separatedBy: .newlines).first
        var atom = Research.newSwipeFile(
            url: post.canonicalURL.absoluteString,
            hook: hook,
            sourceType: sourceType(for: post),
            contentSource: .import_
        )
        atom.title = hook ?? post.author.displayName
        atom.body = post.body
        atom.thumbnailUrl = post.media.first(where: { $0.kind == .thumbnail || $0.kind == .image })?.url.absoluteString
        atom.contentSource = "creator_import"
        atom.swipeBoardIDs = boardID.map { [$0] }

        // Instagram swipes must enter the SAME background pipeline the clipboard/Telegram
        // capture path uses (see CommandKInstantSwipeCapture.capture + shouldProcessInBackground):
        // mark "pending" here and kick off processing at SAVE time, below. Previously the
        // Discovery save path created the atom with only a thumbnail and never triggered
        // processing — so a saved reel had no downloaded video and SwipeStudy was forced into
        // a cold, flaky live extraction on every open (it only "worked the next day" once the
        // launch/foreground scanner happened to process it). Starting processing at save makes
        // the video download + transcribe in the background, ready to load from the store on open.
        let needsBackgroundProcessing = post.platform == .instagram
        if needsBackgroundProcessing {
            atom.processingStatus = "pending"
        }

        var analysis = SwipeAnalysis(
            analysisVersion: 1,
            isFullyAnalyzed: false,
            likesCount: post.metrics.likes,
            viewsCount: post.metrics.views,
            commentsCount: post.metrics.comments,
            sharesCount: post.metrics.shares,
            engagementRate: post.derived.engagementRate,
            publishedAt: post.publishedAt,
            postShortcode: post.providerPostID
        )
        analysis.hookText = hook
        atom = atom.withSwipeAnalysis(analysis)

        let saved = try await AtomRepository.shared.create(atom)

        if needsBackgroundProcessing {
            SwipeProcessingService.shared.processSwipeInBackground(uuid: saved.uuid)
        }

        return saved
    }

    /// Transcript-button flow: save the post into "All Swipes" locally, then open the swipe
    /// teardown focus mode. `SwipeStudyFocusModeView` auto-starts transcription on appear when
    /// the atom has no transcript yet, so this single hop covers save + teardown + transcription.
    func saveAndOpenForTranscription(_ post: SocialPostSnapshot) async {
        do {
            let atom = try await createLocalSwipeAtom(from: post, boardID: nil)
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil)
            saveMessage = "Saved to All Swipes — transcribing…"
            guard let id = atom.id else { return }
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.research, "id": id]
            )
        } catch {
            saveMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func sourceType(for post: SocialPostSnapshot) -> ResearchRichContent.SourceType {
        switch post.platform {
        case .instagram:
            switch post.format {
            case .shortVideo: return .instagramReel
            case .carousel: return .instagramCarousel
            default: return .instagramPost
            }
        case .youtube: return post.format == .shortVideo ? .youtubeShort : .youtube
        case .tiktok: return .tiktok
        case .threads: return .threads
        case .x, .twitter: return .xPost
        default: return .website
        }
    }
}

struct SwipeCreatorRecord: Identifiable, Equatable {
    let id: String
    let name: String
    let handle: String
    let platform: SocialPlatform
    let avatarURL: URL?
    let followerCount: Int?
    let niche: String?
    let bio: String?
    let postCount: Int
    let totalViews: Int
    let totalLikes: Int
    let totalComments: Int
    let topOutlierMultiplier: Double?
    let latestPostDate: Date?
    let topPosts: [SocialPostSnapshot]
}

// MARK: - Pillar topic scope

extension SwipeDiscoverModel {
    var activePillar: SwipeDiscoverPillar? {
        get {
            SwipeDiscoverPillar.allCases.first { $0.searchTerms.map { $0.lowercased() } == query.topicTerms }
        }
        set {
            query.topicTerms = newValue?.searchTerms ?? []
        }
    }

    func togglePillar(_ pillar: SwipeDiscoverPillar) {
        activePillar = activePillar == pillar ? nil : pillar
    }
}

// MARK: - Derived-metrics helper (shared with the discover scorer)

extension SocialPostSnapshot {
    func replacingDerived(_ derived: SocialDerivedMetrics) -> SocialPostSnapshot {
        SocialPostSnapshot(
            id: id,
            platform: platform,
            provider: provider,
            providerPostID: providerPostID,
            canonicalURL: canonicalURL,
            title: title,
            body: body,
            media: media,
            author: author,
            publishedAt: publishedAt,
            detectedLanguage: detectedLanguage,
            format: format,
            metrics: metrics,
            derived: derived,
            transcriptState: transcriptState,
            saveState: saveState,
            rawProviderPayload: rawProviderPayload
        )
    }
}
