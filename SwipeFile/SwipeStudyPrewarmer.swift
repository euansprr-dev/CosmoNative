// CosmoOS/SwipeFile/SwipeStudyPrewarmer.swift
// Prewarms everything the Swipe Study bench needs for a swipe that is
// VISIBLE in the library, so clicking it opens with zero loading:
//   • the atom row + its decoded swipeAnalysis / richContent (DecodedColumnCache)
//   • the stage's hero/thumbnail images under the exact stable keys the
//     stage pane uses (they differ from the card's keys)
//   • every carousel page image into the on-disk carousel cache
//   • the reel MP4 into InstagramVideoLocalCache — from the durable Supabase
//     mirror first (metadata.videoStorageURL), CDN URL as the fallback
//
// Strictly cache-filling: never a model call, never an extraction run, never
// a DB write. Bounded concurrency so a fast scroll can't stampede the network.
// July 2026

import Foundation

@MainActor
final class SwipeStudyPrewarmer {
    static let shared = SwipeStudyPrewarmer()

    /// Parallel prewarms — small so scrolling stays smooth and Instagram's
    /// CDN never sees a burst.
    private let semaphore = AsyncSemaphore(value: 3)
    /// UUIDs already warmed (or in flight) this launch. Bounded — a very long
    /// browsing session resets rather than growing forever.
    private var warmed: Set<String> = []
    /// Video downloads are ~9 MB each — cap them per launch so scrolling the
    /// whole library doesn't quietly pull gigabytes.
    private var videoDownloadsRemaining = 60

    private init() {}

    /// Called when a swipe card lands on screen. Fire-and-forget.
    func prewarm(uuid: String) {
        guard !warmed.contains(uuid) else { return }
        if warmed.count > 1500 { warmed.removeAll() }
        warmed.insert(uuid)

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.semaphore.wait()
            defer { Task { await self.semaphore.signal() } }
            await self.warm(uuid: uuid)
        }
    }

    private func warm(uuid: String) async {
        // 1) The row itself + decoded columns. `swipeAnalysis`/`richContent`
        //    populate DecodedColumnCache as a side effect, so the bench's
        //    first decode on open is a cache hit.
        guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
              atom.isSwipeFileAtom else { return }
        _ = atom.swipeAnalysis
        let richContent = atom.richContent

        // 2) Stage hero images — the SAME stable keys SwipeStudyStagePane
        //    uses, so its CachedAsyncImage resolves instantly.
        if let thumb = (atom.thumbnailUrl ?? richContent?.thumbnailUrl),
           let url = URL(string: thumb) {
            _ = await ThumbnailCacheService.shared.image(
                for: url,
                key: ThumbnailCacheService.shared.cacheKey(for: url, stableKey: "swipe-ig-thumb-\(uuid)")
            )
            _ = await ThumbnailCacheService.shared.image(
                for: url,
                key: ThumbnailCacheService.shared.cacheKey(for: url, stableKey: "swipe-stage-\(uuid)")
            )
        }

        // 3) Carousel pages → on-disk cache (keys match the pager's).
        let shortcode = richContent?.instagramId
            ?? atom.url.flatMap(URL.init(string:)).flatMap {
                InstagramExtractor.shared.extractShortcode(from: $0)
            }
        if let items = richContent?.instagramData?.carouselItems, !items.isEmpty {
            _ = await InstagramCarouselImageCache.cacheCarouselImages(
                items: items,
                shortcode: shortcode
            )
        }

        // 4) Reel video → local MP4 cache. Only when a durable source exists;
        //    never triggers a live Instagram extraction.
        await prewarmVideoIfNeeded(atom: atom, shortcode: shortcode)
    }

    private func prewarmVideoIfNeeded(atom: Atom, shortcode: String?) async {
        guard let shortcode, !shortcode.isEmpty else { return }
        guard InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) == nil else { return }
        guard videoDownloadsRemaining > 0 else { return }

        // Durable Supabase mirror first; the stored CDN URL (expires in days)
        // as the fallback for freshly captured swipes.
        let source = videoStorageURL(from: atom.metadata)
            ?? richContentVideoURL(atom)
        guard let source else { return }

        videoDownloadsRemaining -= 1
        _ = await InstagramVideoLocalCache.resolvePlayableURL(from: source, shortcode: shortcode)
    }

    private func videoStorageURL(from metadata: String?) -> URL? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stored = dict["videoStorageURL"] as? String else { return nil }
        return URL(string: stored)
    }

    private func richContentVideoURL(_ atom: Atom) -> URL? {
        atom.richContent?.instagramData?.extractedMediaURL
    }
}
