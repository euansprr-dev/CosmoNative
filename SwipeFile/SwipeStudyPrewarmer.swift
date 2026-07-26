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
    /// Reels are ~9 MB. They get their OWN slot, held outside the image
    /// semaphore: three concurrent video downloads used to occupy every prewarm
    /// slot and starve the thumbnails the user is actually looking at.
    private let videoSemaphore = AsyncSemaphore(value: 1)
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
            let deferred = await self.warm(uuid: uuid)
            await self.semaphore.signal()

            // Everything only Swipe Study needs — carousel slides 1..N and the
            // reel MP4 — runs AFTER the image slot is released, on its own
            // one-at-a-time lane. Scrolling past a 10-slide carousel used to
            // enqueue ten full-size downloads in a slot the visible grid's
            // thumbnails were waiting for.
            guard let deferred else { return }
            await self.videoSemaphore.wait()
            await self.warmStudyOnlyMedia(deferred)
            await self.videoSemaphore.signal()
        }
    }

    /// The fast lane: the atom row plus the ONE thumbnail the grid renders.
    /// Returns the handle for the deferred lane.
    private func warm(uuid: String) async -> DeferredWarm? {
        // 1) The row itself + decoded columns. `swipeAnalysis`/`richContent`
        //    populate DecodedColumnCache as a side effect, so the bench's
        //    first decode on open is a cache hit.
        guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
              atom.isSwipeFileAtom else { return nil }
        _ = atom.swipeAnalysis
        let richContent = atom.richContent

        // 2) One fetch, three keys. The card, the Study stage and the IG hero
        //    address the SAME image under different stable keys; resolving each
        //    separately meant three network round trips and three identical
        //    copies on disk. Resolve under the card's key (so the library grid
        //    is warmed too — it never was for non-carousel swipes) and alias
        //    the stage keys onto it: memory shares the decode, disk hard-links.
        await warmSharedThumbnail(atom: atom, uuid: uuid)

        // 3) Carousel pages and the reel MP4 are Study-only — handed to the
        //    deferred lane rather than run here.
        let shortcode = richContent?.instagramId
            ?? atom.url.flatMap(URL.init(string:)).flatMap {
                InstagramExtractor.shared.extractShortcode(from: $0)
            }
        return DeferredWarm(atom: atom, shortcode: shortcode)
    }

    private struct DeferredWarm {
        let atom: Atom
        let shortcode: String?
    }

    /// Carousel slides → on-disk cache (keys match the pager's), then the reel.
    /// Slide 0 is already resident: it is the card's thumbnail, written to the
    /// very same `thumb-ig-carousel-<code>-0.jpg` by the fast lane, so
    /// `cacheCarouselImages` finds it and skips the download.
    private func warmStudyOnlyMedia(_ request: DeferredWarm) async {
        let atom = request.atom
        if let items = atom.richContent?.instagramData?.carouselItems, !items.isEmpty {
            _ = await InstagramCarouselImageCache.cacheCarouselImages(
                items: items,
                shortcode: request.shortcode
            )
        } else if let mirrorItems = SwipeCarouselCloudMirror.mirroredCarouselItems(from: atom.metadata) {
            // No local slide list, but the worker's durable Supabase copies
            // exist — warm those under the same shortcode-indexed keys the
            // stage's mirror fast path will derive on open.
            _ = await InstagramCarouselImageCache.cacheCarouselImages(
                items: mirrorItems,
                shortcode: request.shortcode
            )
        }

        // Reel video → local MP4 cache. Only when a durable source exists;
        // never triggers a live Instagram extraction.
        await prewarmVideoIfNeeded(atom: atom, shortcode: request.shortcode)
    }

    /// Resolves the thumbnail ONCE under the card's own key, then points the
    /// Study stage's keys at the same bytes. The card's URL is derived through
    /// `toSwipeGalleryItem()` rather than read off the atom, because that is
    /// where the durable Supabase mirror overrides the expiring CDN URL — the
    /// two are frequently different, and only the mirror matches what the grid
    /// actually requests.
    private func warmSharedThumbnail(atom: Atom, uuid: String) async {
        guard let item = atom.toSwipeGalleryItem() else { return }
        let model = SwipeCardModel(item: item)
        guard let url = model.mediaURL else { return }

        let cache = ThumbnailCacheService.shared
        let cardKey = cache.cacheKey(for: url, stableKey: model.mediaStableKey)
        guard await cache.image(for: url, key: cardKey, priority: .utility) != nil else { return }
        await cache.alias(key: cardKey, to: ["swipe-stage-\(uuid)", "swipe-ig-thumb-\(uuid)"])
    }

    private func prewarmVideoIfNeeded(atom: Atom, shortcode: String?) async {
        guard let shortcode, !shortcode.isEmpty else { return }
        guard InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) == nil else { return }
        guard videoDownloadsRemaining > 0 else { return }

        // Durable Supabase mirror first; the stored CDN URL (expires in days)
        // as the fallback for freshly captured swipes.
        let source = Self.videoStorageURL(from: atom.metadata)
            ?? richContentVideoURL(atom)
        guard let source else { return }

        videoDownloadsRemaining -= 1
        _ = await InstagramVideoLocalCache.resolvePlayableURL(from: source, shortcode: shortcode)
    }

    /// The worker's durable Supabase copy of a reel. Static so playback
    /// surfaces (the preview rail's stage) share the exact source order.
    static func videoStorageURL(from metadata: String?) -> URL? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stored = dict["videoStorageURL"] as? String else { return nil }
        return URL(string: stored)
    }

    private func richContentVideoURL(_ atom: Atom) -> URL? {
        atom.richContent?.instagramData?.extractedMediaURL
    }
}
