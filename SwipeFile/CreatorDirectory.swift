// CosmoOS/SwipeFile/CreatorDirectory.swift
// The one door to creator atoms: find-or-create by identity, link swipes,
// and the repair sweep that folds twins into one creator. Every writer of
// `SwipeAnalysis.creatorUUID` goes through here, so a post saved from any
// path — capture, Apify import, Discover, the Study picker — lands on the
// same creator, and a creator page shows every post ever saved from them.
// September 2026

import Foundation

@MainActor
final class CreatorDirectory {
    static let shared = CreatorDirectory()

    struct RepairReport: Equatable, Sendable {
        var mergedCreators = 0
        var relinkedSwipes = 0
        var attributedSwipes = 0
        var healedCreators = 0
        var isEmpty: Bool { mergedCreators == 0 && relinkedSwipes == 0 && attributedSwipes == 0 && healedCreators == 0 }
    }

    private var cache: (atoms: [Atom], fetchedAt: Date)?
    private var repairTask: Task<RepairReport, Never>?

    private init() {}

    // MARK: - Reads

    /// Every live creator, cached for 60s (batch classification resolved a
    /// creator per swipe with a full-table fetch each time).
    func creators() async throws -> [Atom] {
        if let cache, Date().timeIntervalSince(cache.fetchedAt) < 60 { return cache.atoms }
        let fresh = try await AtomRepository.shared.fetchCreators()
        cache = (fresh, Date())
        return fresh
    }

    func invalidate() { cache = nil }

    // MARK: - Resolve

    /// Find-or-create the creator a handle belongs to. Returns nil when the
    /// handle cannot be keyed (empty, or a leaked numeric id).
    func resolve(handle: String?, name: String?, platform: SocialPlatform?, derivedFromName: Bool = false) async throws -> Atom? {
        guard let key = CreatorIdentity.key(handle) else { return nil }
        let existing = try await creators()
        if let match = CreatorIdentity.match(key: key, platform: platform, derivedFromName: derivedFromName, in: existing) {
            return try await heal(match, key: key, platform: platform)
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let created = try await AtomRepository.shared.createCreator(
            name: trimmedName.isEmpty ? CreatorIdentity.displayHandle(key) : trimmedName,
            handle: CreatorIdentity.displayHandle(key),
            platform: platform?.rawValue ?? "unknown"
        )
        invalidate()
        return created
    }

    /// A match teaches the creator what it didn't know: a real platform
    /// replaces a capture-channel one, a stored handle takes the one spelling.
    @discardableResult
    private func heal(_ creator: Atom, key: String, platform: SocialPlatform?) async throws -> Atom {
        guard var meta = creator.metadataValue(as: CreatorMetadata.self) else { return creator }
        var changed = false
        let canonical = CreatorIdentity.displayHandle(key)
        if meta.handle != canonical, CreatorIdentity.key(meta.handle) == key {
            meta.handle = canonical; changed = true
        }
        if CreatorIdentity.platform(fromCreatorPlatform: meta.platform) == nil, let platform {
            meta.platform = platform.rawValue; changed = true
        }
        guard changed else { return creator }
        let updated = try await AtomRepository.shared.update(creator.withMetadata(meta))
        invalidate()
        return updated
    }

    // MARK: - Links

    /// Attach a swipe to a creator: `creatorUUID` on its analysis plus both
    /// graph links. Idempotent.
    func link(swipeUUID: String, to creatorUUID: String) async {
        guard let swipe = try? await AtomRepository.shared.fetch(uuid: swipeUUID) else { return }
        var updated = swipe
        if var analysis = swipe.swipeAnalysis, analysis.creatorUUID != creatorUUID {
            analysis.creatorUUID = creatorUUID
            updated = updated.withSwipeAnalysis(analysis)
        }
        let linked = updated.linksList.contains { $0.linkType == .swipeToCreator && $0.uuid == creatorUUID }
        if !linked {
            updated = updated.removingLinks(ofType: .swipeToCreator).addingLink(.swipeToCreator(creatorUUID))
        }
        if updated.structured != swipe.structured || updated.links != swipe.links {
            _ = try? await AtomRepository.shared.update(updated)
        }
        _ = try? await AtomRepository.shared.update(uuid: creatorUUID) { creator in
            let already = creator.linksList.contains { $0.linkType == .creatorToSwipe && $0.uuid == swipeUUID }
            if !already { creator = creator.addingLink(.creatorToSwipe(swipeUUID)) }
        }
    }

    /// Detach a swipe from its creator (the analysis field and both links).
    func unlink(swipeUUID: String, from creatorUUID: String) async {
        if let swipe = try? await AtomRepository.shared.fetch(uuid: swipeUUID) {
            var updated = swipe.removingLinks(ofType: .swipeToCreator)
            if var analysis = swipe.swipeAnalysis, analysis.creatorUUID == creatorUUID {
                analysis.creatorUUID = nil
                updated = updated.withSwipeAnalysis(analysis)
            }
            _ = try? await AtomRepository.shared.update(updated)
        }
        _ = try? await AtomRepository.shared.update(uuid: creatorUUID) { creator in
            creator = creator.removingLink(ofType: .creatorToSwipe, toUUID: swipeUUID)
        }
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil,
                                        userInfo: ["creatorUUID": creatorUUID])
    }

    // MARK: - Repair

    /// One creator per handle. Twins (same key, or a name-spelled handle
    /// beside the real username) fold into the richest one: every swipe is
    /// re-keyed, metadata merges, the catalog file follows, the twin is
    /// deleted. Unlinked swipes whose author already has a creator attach.
    /// Idempotent and cheap once clean — the Creators page runs it on arrival.
    func repair() async -> RepairReport {
        if let repairTask { return await repairTask.value }
        let task = Task<RepairReport, Never> { await performRepair() }
        repairTask = task
        let report = await task.value
        repairTask = nil
        return report
    }

    private func performRepair() async -> RepairReport {
        var report = RepairReport()
        guard let all = try? await AtomRepository.shared.fetchCreators(),
              let swipes = try? await AtomRepository.shared.fetchSwipesByTaxonomy() else { return report }

        var survivors = all
        for group in Self.twinGroups(in: all) {
            guard group.count > 1 else { continue }
            let canonical = Self.canonical(among: group, swipes: swipes)
            for twin in group where twin.uuid != canonical.uuid {
                report.relinkedSwipes += await rekey(swipes: swipes, from: twin.uuid, to: canonical.uuid)
                await fold(twin, into: canonical)
                try? await AtomRepository.shared.delete(uuid: twin.uuid)
                survivors.removeAll { $0.uuid == twin.uuid }
                report.mergedCreators += 1
            }
        }
        invalidate()

        // Legacy platforms ("clipboard") and unnormalized handles heal from
        // the creator's own swipes.
        let refreshed = (try? await creators()) ?? survivors
        let swipesByCreator = Dictionary(grouping: swipes) { $0.swipeAnalysis?.creatorUUID ?? "" }
        for creator in refreshed {
            guard let meta = creator.metadataValue(as: CreatorMetadata.self), let key = CreatorIdentity.key(meta.handle) else { continue }
            let known = CreatorIdentity.platform(fromCreatorPlatform: meta.platform)
            let inferred = known ?? (swipesByCreator[creator.uuid] ?? []).lazy.compactMap { CreatorIdentity.platform(for: $0) }.first
                ?? CreatorIdentity.platform(fromURL: meta.profileUrl)
            if meta.handle != CreatorIdentity.displayHandle(key) || (known == nil && inferred != nil) {
                if (try? await heal(creator, key: key, platform: inferred)) != nil { report.healedCreators += 1 }
            }
        }

        report.attributedSwipes = await attributeUnlinked(swipes: swipes)
        if !report.isEmpty {
            invalidate()
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.creatorDataChanged, object: nil)
        }
        return report
    }

    /// Groups of creators that are one person: exact key, plus a name-spelled
    /// handle beside an imported creator whose separator-blind key matches.
    static func twinGroups(in creators: [Atom]) -> [[Atom]] {
        let indexed = CreatorIdentity.index(creators)
        var byKey: [String: [CreatorIdentity.Indexed]] = [:]
        for entry in indexed { byKey[entry.key, default: []].append(entry) }
        // Fold name-spelled keys into the imported creator sharing the loose key.
        var keyToGroup: [String: String] = [:]
        for key in byKey.keys { keyToGroup[key] = key }
        let imported = indexed.filter(\.hasProfile)
        for key in byKey.keys where !(byKey[key]?.contains(where: \.hasProfile) ?? false) {
            if let host = imported.first(where: { CreatorIdentity.looseKey($0.key) == CreatorIdentity.looseKey(key) && $0.key != key }) {
                keyToGroup[key] = host.key
            }
        }
        var groups: [String: [Atom]] = [:]
        for (key, entries) in byKey {
            groups[keyToGroup[key] ?? key, default: []].append(contentsOf: entries.map(\.atom))
        }
        return groups.values.filter { $0.count > 1 }.map { $0.sorted { $0.createdAt < $1.createdAt } }
    }

    /// The richest twin survives: a pulled catalog, then a real profile, then
    /// the most saved posts, then the oldest.
    static func canonical(among group: [Atom], swipes: [Atom]) -> Atom {
        func score(_ atom: Atom) -> (Int, Int, Int, String) {
            let meta = atom.metadataValue(as: CreatorMetadata.self)
            let catalog = CatalogStore.exists(creatorUUID: atom.uuid) ? 1 : 0
            let profile = (meta?.followerCount != nil || meta?.thumbnailUrl != nil) ? 1 : 0
            let saved = swipes.count { $0.swipeAnalysis?.creatorUUID == atom.uuid }
            return (catalog, profile, saved, atom.createdAt)
        }
        return group.max { a, b in
            let sa = score(a), sb = score(b)
            if sa.0 != sb.0 { return sa.0 < sb.0 }
            if sa.1 != sb.1 { return sa.1 < sb.1 }
            if sa.2 != sb.2 { return sa.2 < sb.2 }
            return sa.3 > sb.3
        } ?? group[0]
    }

    private func rekey(swipes: [Atom], from twin: String, to canonical: String) async -> Int {
        var count = 0
        for swipe in swipes where swipe.swipeAnalysis?.creatorUUID == twin
            || swipe.linksList.contains(where: { $0.linkType == .swipeToCreator && $0.uuid == twin }) {
            await link(swipeUUID: swipe.uuid, to: canonical)
            count += 1
        }
        return count
    }

    /// Metadata the twin knew flows into the survivor; the catalog file follows.
    private func fold(_ twin: Atom, into canonical: Atom) async {
        let twinMeta = twin.metadataValue(as: CreatorMetadata.self)
        _ = try? await AtomRepository.shared.update(uuid: canonical.uuid) { atom in
            guard var meta = atom.metadataValue(as: CreatorMetadata.self) else { return }
            if let twinMeta {
                meta.followerCount = max(meta.followerCount ?? 0, twinMeta.followerCount ?? 0).nonZero
                meta.thumbnailUrl = meta.thumbnailUrl ?? twinMeta.thumbnailUrl
                meta.profileUrl = meta.profileUrl ?? twinMeta.profileUrl
                meta.bio = meta.bio ?? twinMeta.bio
                meta.niche = meta.niche ?? twinMeta.niche
                meta.followingCount = meta.followingCount ?? twinMeta.followingCount
                meta.postsCount = meta.postsCount ?? twinMeta.postsCount
                if let notes = twinMeta.notes, !notes.isEmpty {
                    meta.notes = [meta.notes, notes].compactMap { $0 }.joined(separator: "\n")
                }
            }
            var links = atom.links(ofType: .creatorToSwipe).map(\.uuid)
            for link in twin.links(ofType: .creatorToSwipe) where !links.contains(link.uuid) {
                atom = atom.addingLink(.creatorToSwipe(link.uuid)); links.append(link.uuid)
            }
            atom = atom.withMetadata(meta)
        }
        if !CatalogStore.exists(creatorUUID: canonical.uuid), let posts = CatalogStore.load(creatorUUID: twin.uuid) {
            try? CatalogStore.save(posts: posts, forCreator: canonical.uuid)
            _ = try? await AtomRepository.shared.update(uuid: canonical.uuid) { atom in
                guard var meta = atom.metadataValue(as: CreatorMetadata.self) else { return }
                meta.catalogPostCount = posts.count
                meta.catalogFetchedAt = twinMeta?.catalogFetchedAt ?? meta.catalogFetchedAt
                atom = atom.withMetadata(meta)
            }
        }
        CatalogStore.delete(creatorUUID: twin.uuid)
    }

    /// Swipes with an author but no (or a dangling) creator attach when a
    /// creator already exists for that handle. Never mints creators.
    private func attributeUnlinked(swipes: [Atom]) async -> Int {
        guard let creators = try? await creators() else { return 0 }
        let live = Set(creators.map(\.uuid))
        var count = 0
        for swipe in swipes {
            let current = swipe.swipeAnalysis?.creatorUUID
            if let current, live.contains(current) { continue }
            let resolution = CreatorIdentity.effectiveCreator(aiHandle: nil, aiName: nil, atom: swipe)
            guard let key = CreatorIdentity.key(resolution.handle),
                  let match = CreatorIdentity.match(key: key, platform: CreatorIdentity.platform(for: swipe),
                                                    derivedFromName: resolution.derivedFromDisplayName, in: creators) else { continue }
            await link(swipeUUID: swipe.uuid, to: match.uuid)
            count += 1
        }
        return count
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
