// CosmoOS/Canvas/CanvasMediaBlockStateCache.swift
// Per-atom derived media state for canvas media cards, surviving unmount/remount.
//
// The render pipeline culls block hosts against the viewport, so panning across
// a large canvas unmounts and remounts MediaBlockViews continuously. Before this
// cache every remount re-ran the whole media resolution ladder — atom fetch,
// carousel decode, local-video probe, and (worst) an AVAssetImageGenerator
// video-frame decode whose result lived only in view @State. A remount now
// hydrates synchronously from here and renders its first frame complete.

import AppKit
import Foundation

@MainActor
final class CanvasMediaBlockStateCache {
    static let shared = CanvasMediaBlockStateCache()

    struct Entry {
        /// Version stamp of the atom this state was derived from — a newer
        /// atom (edit, reprocess, sync) invalidates the entry.
        let atomLocalVersion: Int64
        let atomUpdatedAt: String

        var carouselItems: [CarouselItem]?
        var localVideoURL: URL?
        var generatedThumbnail: NSImage?
        /// Character count of the transcript — cards show the count in the
        /// collapsed transcript row; caching it means card bodies never decode
        /// the transcript JSON (see perf_decode_memoization law).
        var transcriptCharCount: Int?
        /// True once the media resolution ladder ran to completion for this
        /// atom version — a hydrated card skips loadMedia entirely.
        var mediaResolved: Bool

        var stampedAt: Date = Date()

        func matches(_ atom: Atom) -> Bool {
            atomLocalVersion == atom.localVersion && atomUpdatedAt == atom.updatedAt
        }
    }

    private var entriesByUUID: [String: Entry] = [:]
    /// Generated reel thumbnails cost ~1.3 MB each; everything else is small.
    /// 400 entries comfortably covers several large canvases.
    private let capacity = 400

    private init() {}

    /// Entry for the atom, or nil when none exists or the cached state was
    /// derived from an older atom version (stale entries are dropped).
    func entry(forAtomUuid uuid: String, matching atom: Atom?) -> Entry? {
        guard let entry = entriesByUUID[uuid] else { return nil }
        if let atom, !entry.matches(atom) {
            entriesByUUID.removeValue(forKey: uuid)
            return nil
        }
        return entry
    }

    /// Raw entry lookup for hydration paths that have no atom yet.
    func entry(forAtomUuid uuid: String) -> Entry? {
        entriesByUUID[uuid]
    }

    func store(_ entry: Entry, forAtomUuid uuid: String) {
        guard !uuid.isEmpty else { return }
        var stamped = entry
        stamped.stampedAt = Date()
        entriesByUUID[uuid] = stamped
        trimIfNeeded()
    }

    /// Merge-update the entry for an atom, creating it (stamped with the
    /// atom's version) when absent. A stale entry is replaced wholesale.
    func update(forAtom atom: Atom, _ mutate: (inout Entry) -> Void) {
        let uuid = atom.uuid
        guard !uuid.isEmpty else { return }
        var entry: Entry
        if let existing = entriesByUUID[uuid], existing.matches(atom) {
            entry = existing
        } else {
            entry = Entry(
                atomLocalVersion: atom.localVersion,
                atomUpdatedAt: atom.updatedAt,
                mediaResolved: false
            )
        }
        mutate(&entry)
        store(entry, forAtomUuid: uuid)
    }

    /// Drop cached state — forceReload paths demand a fresh resolution.
    func invalidate(atomUuid: String) {
        entriesByUUID.removeValue(forKey: atomUuid)
    }

    private func trimIfNeeded() {
        guard entriesByUUID.count > capacity else { return }
        let victims = entriesByUUID
            .sorted { $0.value.stampedAt < $1.value.stampedAt }
            .prefix(entriesByUUID.count - capacity)
            .map(\.key)
        for uuid in victims {
            entriesByUUID.removeValue(forKey: uuid)
        }
    }
}

extension CanvasMediaBlockStateCache.Entry {
    init(atom: Atom, mediaResolved: Bool = false) {
        self.init(
            atomLocalVersion: atom.localVersion,
            atomUpdatedAt: atom.updatedAt,
            mediaResolved: mediaResolved
        )
    }
}
