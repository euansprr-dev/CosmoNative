// CosmoOS/SwipeFile/SwipeThumbnailPrewarmer.swift
// Gets swipe card thumbnails into the MEMORY cache before the cell that needs
// them ever mounts. Three ladders, coldest to warmest:
//
//   1. Launch manifest — the keys the library showed last session, replayed at
//      app start. Needs no DB query, so the warm begins immediately instead of
//      waiting behind the ⌘K/canvas prewarms.
//   2. Library warm — the real card models, once the library decode lands.
//   3. Scroll-ahead — the masonry's prefetch band, several viewports beyond the
//      cells it actually mounts.
//
// Why memory and not disk: `CachedAsyncImage.init` probes the memory cache
// synchronously and paints on frame 1 with no flicker. A disk-only hit still
// costs an async hop and at least one frame of `.empty` — which is the grey
// wash you see on a cold open.
//
// Strictly cache-filling: never a model call, never a DB write.
// July 2026

import Foundation

@MainActor
final class SwipeThumbnailPrewarmer {
    static let shared = SwipeThumbnailPrewarmer()

    /// A cold library open shows ~30–60 cells; 240 covers the first several
    /// flicks without a single decode on the render path.
    private static let launchWarmCount = 240
    /// Cap per scroll-ahead batch so jumping to the bottom of a 2,000-swipe
    /// catalog can't enqueue the whole thing.
    private static let scrollWarmCount = 160
    /// Bounded so a long browsing session resets rather than growing forever.
    private static let requestedCeiling = 4000

    /// Keys already handed to the cache this launch.
    private var requested: Set<String> = []
    private var manifestWriteTask: Task<Void, Never>?

    private init() {}

    // MARK: - Ladder 1 — launch manifest

    /// Replays last session's visible keys. Safe to call before the database is
    /// ready: it reads a small JSON file and nothing else.
    func warmFromManifest() {
        Task.detached(priority: .utility) {
            guard let entries = Self.loadManifest() else { return }
            let targets = entries.compactMap { entry -> Target? in
                guard let url = URL(string: entry.url) else { return nil }
                return Target(url: url, key: entry.key)
            }
            await Self.run(targets: targets, priority: .utility, concurrency: 6)
        }
        Task { await ThumbnailCacheService.shared.pruneDiskCacheIfNeeded() }
    }

    // MARK: - Ladder 2 — library warm

    /// Called when the library's card models land (launch prewarm, first visit,
    /// and every filter/search recompute). Warms the head of the list — what
    /// the user is about to be looking at.
    ///
    /// `recordAsLaunchManifest` must be false for filtered or searched results:
    /// the manifest is what a COLD LAUNCH replays, and a manifest written from
    /// "swipes matching 'hook'" would warm the wrong 240 images tomorrow.
    func warmLibrary(models: [SwipeCardModel], recordAsLaunchManifest: Bool) {
        let targets = Self.targets(from: models.prefix(Self.launchWarmCount))
        enqueue(targets, priority: .utility, concurrency: 6)
        if recordAsLaunchManifest {
            scheduleManifestWrite(models: models)
        }
    }

    // MARK: - Ladder 3 — scroll-ahead

    /// The masonry's prefetch band: cells several viewports out that have not
    /// been mounted yet. Runs at `.utility` so it always yields to the cells
    /// actually on screen.
    func warmAhead(models: [SwipeCardModel]) {
        let targets = Self.targets(from: models.prefix(Self.scrollWarmCount))
        enqueue(targets, priority: .utility, concurrency: 4)
    }

    // MARK: - Queue

    private func enqueue(_ targets: [Target], priority: _Concurrency.TaskPriority, concurrency: Int) {
        if requested.count > Self.requestedCeiling { requested.removeAll() }
        let pending = targets.filter { requested.insert($0.key).inserted }
        guard !pending.isEmpty else { return }

        Task.detached(priority: priority) {
            await Self.run(targets: pending, priority: priority, concurrency: concurrency)
        }
    }

    /// Bounded fan-out: the cache decodes in parallel now, but an unbounded
    /// burst would still put hundreds of requests on Instagram's CDN at once.
    /// `nonisolated` so the fan-out never touches the main actor.
    private nonisolated static func run(targets: [Target], priority: _Concurrency.TaskPriority, concurrency: Int) async {
        guard !targets.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = targets.makeIterator()
            for _ in 0..<concurrency {
                guard let target = iterator.next() else { break }
                group.addTask { await target.warm(priority: priority) }
            }
            while await group.next() != nil {
                guard let target = iterator.next() else { continue }
                group.addTask { await target.warm(priority: priority) }
            }
        }
    }

    private static func targets(from models: some Sequence<SwipeCardModel>) -> [Target] {
        let cache = ThumbnailCacheService.shared
        return models.compactMap { model -> Target? in
            guard let url = model.mediaURL else { return nil }
            let key = cache.cacheKey(for: url, stableKey: model.mediaStableKey)
            // Synchronous, nonisolated memory probe — already-resident images
            // never reach the queue at all.
            guard cache.cachedImage(for: key) == nil else { return nil }
            return Target(url: url, key: key)
        }
    }

    private struct Target: Sendable {
        let url: URL
        let key: String

        func warm(priority: _Concurrency.TaskPriority) async {
            _ = await ThumbnailCacheService.shared.image(for: url, key: key, priority: priority)
        }
    }

    // MARK: - Manifest

    private struct ManifestEntry: Codable, Sendable {
        let key: String
        let url: String
    }

    private nonisolated static var manifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/swipe-warm-manifest.json")
    }

    /// Debounced: the library recomputes on every keystroke in search.
    private func scheduleManifestWrite(models: [SwipeCardModel]) {
        let cache = ThumbnailCacheService.shared
        let entries = models.prefix(Self.launchWarmCount).compactMap { model -> ManifestEntry? in
            guard let url = model.mediaURL else { return nil }
            return ManifestEntry(
                key: cache.cacheKey(for: url, stableKey: model.mediaStableKey),
                url: url.absoluteString
            )
        }
        guard !entries.isEmpty else { return }

        manifestWriteTask?.cancel()
        manifestWriteTask = Task { [entries] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .background) { Self.writeManifest(entries) }.value
        }
    }

    private nonisolated static func writeManifest(_ entries: [ManifestEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let url = manifestURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private nonisolated static func loadManifest() -> [ManifestEntry]? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode([ManifestEntry].self, from: data)
    }
}
