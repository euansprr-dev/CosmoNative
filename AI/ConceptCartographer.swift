// CosmoOS/AI/ConceptCartographer.swift
// The Cartographer: the Gardener's counterpart for the CONCEPT map. Hierarchy
// is only written at crystallization time for the new batch, so old, manual,
// and canvas-born concepts pile up as flat top-level pillars forever. The
// Cartographer re-reads the WHOLE concept map at natural seams
// (crystallization, opening the Map tab, the Tidy button) and PROPOSES —
// never acts:
//   · group — several sibling pillars belong under a new SECTION page
//   · nest  — one pillar belongs under an existing concept
// User pins are law (pinned concepts are never moved), every draft passes a
// deterministic validation ladder (unknown ids, cycles, member caps), and
// every ruling is remembered in the shared decision store so nothing is ever
// re-proposed. A quiet cartographer is trusted; a chatty one is muted.

import Foundation
import GRDB

// MARK: - Proposal

struct ConceptCartographerProposal: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Mint a new section page named `name` over the member pillars.
        case group(name: String, memberUUIDs: [String])
        /// Move an existing pillar under an existing concept.
        case nest(childUUID: String, parentUUID: String)
        /// Fold micro-seedlings' mass into one umbrella seedling — the
        /// seedbed's answer to fragmentation ("Pitch", "Pace", "Prosody" →
        /// facets of "Vocal delivery"). memberKeys are seedling conceptKeys,
        /// not connection UUIDs; nothing becomes a page.
        case foldSeedlings(umbrellaName: String, memberKeys: [String])
    }

    /// Stable fingerprint: one ruling per structural change forever. Group
    /// keys hash the SORTED member set (rename-independent) so a cosmetic
    /// name change can never re-propose a dismissed grouping.
    var key: String
    var kind: Kind
    /// One calm human sentence: why the map wants organizing here.
    var reason: String
    /// group: the proposed section name; nest: the child's title.
    var title: String
    /// group: member titles; nest: [parent title].
    var memberTitles: [String]

    var id: String { key }

    var actionLabel: String {
        switch kind {
        case .group: return "Group"
        case .nest: return "Nest"
        case .foldSeedlings: return "Fold"
        }
    }

    var memberUUIDs: [String] {
        switch kind {
        case .group(_, let members): return members
        case .nest(let child, _): return [child]
        case .foldSeedlings: return []   // Seedling keys are not connection UUIDs.
        }
    }

    static func groupKey(memberUUIDs: [String]) -> String {
        "cartographer.group:" + memberUUIDs.sorted().joined(separator: "~")
    }

    static func nestKey(childUUID: String, parentUUID: String) -> String {
        "cartographer.nest:\(childUUID)~\(parentUUID)"
    }

    static func foldKey(memberKeys: [String]) -> String {
        "cartographer.fold:" + memberKeys.sorted().joined(separator: "~")
    }
}

// MARK: - Pure signals (unit-tested, no database, no model)

enum ConceptCartographerSignals {

    struct ConceptFacts: Sendable {
        var uuid: String
        var title: String
        /// Effective map parent (persisted metadata OR the builder's lexical
        /// fallback) — facts mirror what the map actually renders.
        var parentUUID: String?
        var isPinned: Bool = false
        var isSection: Bool = false
        var noteCount: Int = 0
    }

    struct CanvasClusterFacts: Sendable, Equatable {
        var name: String
        var memberConnectionUUIDs: [String]
    }

    /// One growing seedling as the Cartographer sees it. Facts mirror the
    /// fold guards: pinned, developed, and page-tied seedlings never fold.
    struct SeedlingFacts: Sendable, Equatable {
        var conceptKey: String
        var name: String
        var pendingCount: Int
        var parentConceptName: String?
        var isPinned: Bool = false
        var isFoldable: Bool = true   // incubating, unpinned, no page ties
    }

    /// A draft before validation — from the LLM or from a canvas cluster.
    struct Draft: Equatable, Sendable {
        var kind: ConceptCartographerProposal.Kind
        var reason: String
    }

    /// Tunables — one place, so taste changes don't hunt through logic.
    enum Thresholds {
        static let organizeMinTopLevel = 7
        static let thinPillarMaxNotes = 1
        static let organizeMinThinPillars = 4
        static let groupMinMembers = 2
        static let groupMaxMembers = 6
        static let maxProposalsPerPass = 3
        /// The fragmentation signature that consults the model about
        /// seedling folds: this many thin seedlings (≤ thinSeedlingMaxItems
        /// captures each) growing at once.
        static let foldMinThinSeedlings = 4
        static let thinSeedlingMaxItems = 2
        static let foldMinMembers = 2
        static let foldMaxMembers = 6
    }

    /// Whether the top level is crowded enough to consult the model at all.
    static func wantsOrganization(facts: [ConceptFacts]) -> Bool {
        let topLevel = facts.filter { $0.parentUUID == nil && !$0.isSection }
        guard topLevel.count > Thresholds.groupMinMembers else { return false }
        if topLevel.count >= Thresholds.organizeMinTopLevel { return true }
        let thin = topLevel.filter { $0.noteCount <= Thresholds.thinPillarMaxNotes }
        return thin.count >= Thresholds.organizeMinThinPillars
    }

    /// The seedbed fragmentation signature: many thin seedlings at once
    /// (a video session that minted nine one-capture names) — worth
    /// consulting the model about umbrella folds even when the page map is
    /// quiet.
    static func wantsSeedlingConsolidation(seedlings: [SeedlingFacts]) -> Bool {
        let thin = seedlings.filter { $0.isFoldable && $0.pendingCount <= Thresholds.thinSeedlingMaxItems }
        return thin.count >= Thresholds.foldMinThinSeedlings
    }

    /// Zero-LLM fold drafts from the resolver's own hierarchy: the tidy pass
    /// stamps parentConceptName on seedlings, so siblings that share a parent
    /// were ALREADY judged facets of one umbrella — formalizing that needs no
    /// model, just consent. Deterministic order: parent name.
    static func parentFoldDrafts(seedlings: [SeedlingFacts]) -> [Draft] {
        let foldable = seedlings.filter { $0.isFoldable && !$0.isPinned }
        let byParent = Dictionary(grouping: foldable.compactMap { seedling -> (parent: String, seedling: SeedlingFacts)? in
            guard let parent = seedling.parentConceptName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !parent.isEmpty,
                  ConceptResolver.conceptKey(parent) != seedling.conceptKey else { return nil }
            return (parent, seedling)
        }, by: { ConceptResolver.conceptKey($0.parent) })
        return byParent.values
            .compactMap { members -> Draft? in
                guard members.count >= Thresholds.foldMinMembers,
                      members.count <= Thresholds.foldMaxMembers,
                      let parentName = members.first?.parent else { return nil }
                return Draft(
                    kind: .foldSeedlings(
                        umbrellaName: parentName,
                        memberKeys: members.map(\.seedling.conceptKey).sorted()
                    ),
                    reason: "The debrief filed these as facets of \(parentName)"
                )
            }
            .sorted { lhs, rhs in
                guard case .foldSeedlings(let a, _) = lhs.kind,
                      case .foldSeedlings(let b, _) = rhs.kind else { return false }
                return a < b
            }
    }

    /// A user-built canvas cluster holding ≥2 of the dive's pillars is already
    /// a grouping claim in the user's own hand — formalizing it needs no
    /// model, just consent. Deterministic order: cluster name.
    static func clusterDrafts(
        facts: [ConceptFacts],
        clusters: [CanvasClusterFacts]
    ) -> [Draft] {
        clusters
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.name < $1.name }
            .compactMap { cluster in
                let members = cluster.memberConnectionUUIDs.sorted()
                guard members.count >= Thresholds.groupMinMembers else { return nil }
                return Draft(
                    kind: .group(name: cluster.name, memberUUIDs: members),
                    reason: "You already grouped these on the canvas as “\(cluster.name)”"
                )
            }
    }

    /// The validation ladder every draft must climb. Drops: unknown or pinned
    /// members, non-top-level group members, section children, self-nests,
    /// ancestry cycles, undersized groups, members claimed by an earlier
    /// draft. A group named after an EXISTING concept converts into nest
    /// drafts under it (the section already exists — don't mint a twin).
    /// Fold drafts climb their own rungs: every member must be a known,
    /// foldable, unpinned seedling not claimed by an earlier fold, member
    /// count within bounds, and the umbrella name must not collide with a
    /// member's own key.
    static func validated(
        _ drafts: [Draft],
        facts: [ConceptFacts],
        seedlings: [SeedlingFacts] = []
    ) -> [ConceptCartographerProposal] {
        let byUUID = Dictionary(facts.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let parentByUUID = facts.reduce(into: [String: String]()) { partial, fact in
            if let parent = fact.parentUUID { partial[fact.uuid] = parent }
        }
        let uuidByTitleKey = Dictionary(
            facts.compactMap { fact -> (String, String)? in
                let key = ConceptResolver.conceptKey(fact.title)
                return key.isEmpty ? nil : (key, fact.uuid)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let seedlingsByKey = Dictionary(
            seedlings.map { ($0.conceptKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var claimed = Set<String>()
        var claimedSeedlingKeys = Set<String>()
        var seenKeys = Set<String>()
        var groups: [ConceptCartographerProposal] = []
        var nests: [ConceptCartographerProposal] = []
        var folds: [ConceptCartographerProposal] = []

        func validNest(childUUID: String, parentUUID: String, reason: String) -> ConceptCartographerProposal? {
            guard let child = byUUID[childUUID],
                  let parent = byUUID[parentUUID],
                  childUUID != parentUUID,
                  !child.isPinned,
                  !child.isSection,
                  child.parentUUID != parentUUID,
                  !claimed.contains(childUUID),
                  !ConnectionPromotionService.createsCycle(
                      child: childUUID, parent: parentUUID, parentByUUID: parentByUUID
                  ) else { return nil }
            let key = ConceptCartographerProposal.nestKey(childUUID: childUUID, parentUUID: parentUUID)
            guard !seenKeys.contains(key) else { return nil }
            return ConceptCartographerProposal(
                key: key,
                kind: .nest(childUUID: childUUID, parentUUID: parentUUID),
                reason: reason,
                title: child.title,
                memberTitles: [parent.title]
            )
        }

        for draft in drafts {
            switch draft.kind {
            case .group(let name, let memberUUIDs):
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { continue }
                // Name collides with an existing page → nest under it instead.
                if let existingUUID = uuidByTitleKey[ConceptResolver.conceptKey(trimmedName)] {
                    for member in memberUUIDs where member != existingUUID {
                        if let nest = validNest(childUUID: member, parentUUID: existingUUID, reason: draft.reason) {
                            nests.append(nest)
                            seenKeys.insert(nest.key)
                            claimed.insert(member)
                        }
                    }
                    continue
                }
                let members = memberUUIDs.filter { uuid in
                    guard let fact = byUUID[uuid] else { return false }
                    return fact.parentUUID == nil
                        && !fact.isPinned
                        && !fact.isSection
                        && !claimed.contains(uuid)
                }
                guard members.count >= Thresholds.groupMinMembers,
                      members.count <= Thresholds.groupMaxMembers else { continue }
                let key = ConceptCartographerProposal.groupKey(memberUUIDs: members)
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                claimed.formUnion(members)
                groups.append(ConceptCartographerProposal(
                    key: key,
                    kind: .group(name: trimmedName, memberUUIDs: members),
                    reason: draft.reason,
                    title: trimmedName,
                    memberTitles: members.compactMap { byUUID[$0]?.title }
                ))

            case .nest(let childUUID, let parentUUID):
                if let nest = validNest(childUUID: childUUID, parentUUID: parentUUID, reason: draft.reason) {
                    nests.append(nest)
                    seenKeys.insert(nest.key)
                    claimed.insert(childUUID)
                }

            case .foldSeedlings(let umbrellaName, let memberKeys):
                let trimmedName = umbrellaName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { continue }
                let umbrellaKey = ConceptResolver.conceptKey(trimmedName)
                let members = memberKeys.filter { key in
                    guard key != umbrellaKey,
                          let seedling = seedlingsByKey[key] else { return false }
                    return seedling.isFoldable
                        && !seedling.isPinned
                        && !claimedSeedlingKeys.contains(key)
                }.sorted()
                guard members.count >= Thresholds.foldMinMembers,
                      members.count <= Thresholds.foldMaxMembers else { continue }
                let key = ConceptCartographerProposal.foldKey(memberKeys: members)
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                claimedSeedlingKeys.formUnion(members)
                folds.append(ConceptCartographerProposal(
                    key: key,
                    kind: .foldSeedlings(umbrellaName: trimmedName, memberKeys: members),
                    reason: draft.reason,
                    title: trimmedName,
                    memberTitles: members.compactMap { seedlingsByKey[$0]?.name }
                ))
            }
        }

        // Groups first — the big structural wins — then folds (they stop
        // fragmentation at the source), then nests.
        return Array((groups + folds + nests).prefix(Thresholds.maxProposalsPerPass))
    }

    /// Concept pairs that keep getting captured together (shared extract
    /// tags) — the strongest "these belong near each other" signal we own.
    /// Deterministic: count desc, then pair key.
    static func coOccurrencePairs(
        conceptNamesPerExtract: [[String]],
        uuidByConceptKey: [String: String],
        titleByUUID: [String: String],
        limit: Int = 8
    ) -> [(a: String, b: String, count: Int)] {
        var tally: [String: Int] = [:]
        for names in conceptNamesPerExtract {
            let uuids = Set(names.compactMap { uuidByConceptKey[ConceptResolver.conceptKey($0)] })
            guard uuids.count >= 2 else { continue }
            let sorted = uuids.sorted()
            for i in sorted.indices {
                for j in sorted.indices where j > i {
                    tally["\(sorted[i])~\(sorted[j])", default: 0] += 1
                }
            }
        }
        return tally
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .compactMap { entry in
                let parts = entry.key.split(separator: "~").map(String.init)
                guard parts.count == 2,
                      let a = titleByUUID[parts[0]],
                      let b = titleByUUID[parts[1]] else { return nil }
                return (a: a, b: b, count: entry.value)
            }
    }
}

// MARK: - The Cartographer (LLM judgment + persistence at the seams)

final class ConceptCartographer {
    static let shared = ConceptCartographer()
    private init() {}

    /// Throttle: one pass per topic per interval unless forced (crystallize
    /// and the Tidy button force).
    private var lastRunByTopic: [String: Date] = [:]
    private let minimumInterval: TimeInterval = 30 * 60

    /// `preloadedConnections`/`preloadedExtracts` let a caller that already
    /// fetched the topic's atoms (DeepDiveOverviewViewModel.load) share them
    /// instead of re-running the same queries; nil falls back to self-fetch.
    /// Returns nil when the throttle skipped the pass (callers keep whatever
    /// proposals they're already showing), [] when the map genuinely needs
    /// nothing.
    func review(
        deepDive: Atom,
        force: Bool = false,
        preloadedConnections: [Atom]? = nil,
        preloadedExtracts: [Atom]? = nil
    ) async -> [ConceptCartographerProposal]? {
        if !force,
           let last = lastRunByTopic[deepDive.uuid],
           Date().timeIntervalSince(last) < minimumInterval {
            return nil
        }
        lastRunByTopic[deepDive.uuid] = Date()

        let connections: [Atom]
        if let preloadedConnections {
            connections = preloadedConnections
        } else {
            connections = (try? await InquiryRepository.shared.fetchConnections(forDeepDive: deepDive)) ?? []
        }
        let seedlingFacts = await Self.makeSeedlingFacts(deepDiveUUID: deepDive.uuid)
        // A quiet page map with a fragmented seedbed still deserves a pass —
        // the seedbed is where fragmentation starts.
        guard connections.count > ConceptCartographerSignals.Thresholds.groupMinMembers
            || ConceptCartographerSignals.wantsSeedlingConsolidation(seedlings: seedlingFacts)
            || !ConceptCartographerSignals.parentFoldDrafts(seedlings: seedlingFacts).isEmpty
        else { return [] }
        let extracts: [Atom]
        if let preloadedExtracts {
            extracts = preloadedExtracts
        } else {
            extracts = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: deepDive.uuid)) ?? []
        }

        let facts = Self.makeFacts(connections: connections, extracts: extracts)
        let clusters = await canvasClusterFacts(deepDive: deepDive, connections: connections)

        var drafts = ConceptCartographerSignals.clusterDrafts(facts: facts, clusters: clusters)
        drafts += ConceptCartographerSignals.parentFoldDrafts(seedlings: seedlingFacts)
        if ConceptCartographerSignals.wantsOrganization(facts: facts)
            || ConceptCartographerSignals.wantsSeedlingConsolidation(seedlings: seedlingFacts) {
            drafts += await llmDrafts(deepDive: deepDive, facts: facts, extracts: extracts, seedlings: seedlingFacts)
        }

        let decided = await InquiryGardenerDecisionStore.shared.decidedKeys(deepDiveUUID: deepDive.uuid)
        return ConceptCartographerSignals.validated(drafts, facts: facts, seedlings: seedlingFacts)
            .filter { !decided.contains($0.key) }
    }

    /// Accepts a proposal: applies the structure (section mint + parent
    /// writes + canvas mirror; seedling folds go to the seedbed service —
    /// they never touch pages or canvas) and records the ruling. Returns the
    /// section page's UUID for groups (the "Develop now?" moment) — nil
    /// otherwise.
    @discardableResult
    func accept(_ proposal: ConceptCartographerProposal, deepDive: Atom) async -> String? {
        if case .foldSeedlings(let umbrellaName, let memberKeys) = proposal.kind {
            await ConceptSeedbedService.shared.foldSeedlings(
                deepDiveUUID: deepDive.uuid,
                umbrellaName: umbrellaName,
                memberKeys: memberKeys
            )
            await InquiryGardenerDecisionStore.shared.record(
                key: proposal.key, decision: .accepted, deepDiveUUID: deepDive.uuid
            )
            return nil
        }
        let sectionUUID = await ConnectionPromotionService.shared.applyCartographerProposal(
            proposal, deepDive: deepDive
        )
        await InquiryGardenerDecisionStore.shared.record(
            key: proposal.key, decision: .accepted, deepDiveUUID: deepDive.uuid
        )
        return sectionUUID
    }

    func dismiss(_ proposal: ConceptCartographerProposal, deepDiveUUID: String) async {
        await InquiryGardenerDecisionStore.shared.record(
            key: proposal.key, decision: .dismissed, deepDiveUUID: deepDiveUUID
        )
    }

    /// Crystallization moved the ground — the next look at the map should
    /// re-review regardless of the throttle.
    func invalidateThrottle(deepDiveUUID: String) {
        lastRunByTopic[deepDiveUUID] = nil
    }

    // MARK: - Facts

    /// Pure facts assembly — mirrors exactly what the map renders (persisted
    /// hierarchy + the builder's lexical fallback).
    static func makeFacts(connections: [Atom], extracts: [Atom]) -> [ConceptCartographerSignals.ConceptFacts] {
        let connectionsByUUID = Dictionary(
            connections.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let parentByUUID = MindMapBuilder.conceptParents(
            connections: connections, connectionsByUUID: connectionsByUUID
        )
        var noteCounts: [String: Int] = [:]
        for extract in extracts {
            if let target = extract.extractMetadata?.promotedToUUID {
                noteCounts[target, default: 0] += 1
            }
        }
        return connections.map { connection in
            let hierarchy = connection.metadataValue(as: ConnectionHierarchyMetadata.self)
            return ConceptCartographerSignals.ConceptFacts(
                uuid: connection.uuid,
                title: connection.title ?? "Untitled concept",
                parentUUID: parentByUUID[connection.uuid],
                isPinned: hierarchy?.parentPinnedByUser == true,
                isSection: hierarchy?.isSection == true,
                noteCount: noteCounts[connection.uuid] ?? 0
            )
        }
    }

    /// The dive's growing seedlings as fold candidates. Foldability mirrors
    /// the reducer's guards exactly (GUARD-TWIN of
    /// ConceptSeedbedReducer.foldSeedlings): incubating, unpinned, no page
    /// ties.
    @MainActor
    static func makeSeedlingFacts(deepDiveUUID: String) async -> [ConceptCartographerSignals.SeedlingFacts] {
        let seedbed = await ConceptSeedbedService.shared.seedbed(deepDiveUUID: deepDiveUUID)
        return seedbed
            .filter { $0.status != .dismissed }
            .map { seedling in
                ConceptCartographerSignals.SeedlingFacts(
                    conceptKey: seedling.conceptKey,
                    name: seedling.name,
                    pendingCount: seedling.pendingItems.count,
                    parentConceptName: seedling.parentConceptName,
                    isPinned: seedling.pinnedAt != nil,
                    isFoldable: seedling.status == .incubating
                        && seedling.pinnedAt == nil
                        && seedling.mergeTargetConnectionUUID == nil
                        && seedling.developedConnectionUUID == nil
                )
            }
    }

    /// User-created canvas clusters on the dive's thinkspaces that hold ≥2 of
    /// this dive's concept blocks (block ids → entity uuids via canvas_blocks).
    private func canvasClusterFacts(
        deepDive: Atom,
        connections: [Atom]
    ) async -> [ConceptCartographerSignals.CanvasClusterFacts] {
        let connectionUUIDs = Set(connections.map(\.uuid))
        var results: [ConceptCartographerSignals.CanvasClusterFacts] = []
        for thinkspaceUUID in InquiryRepository.thinkspaceScopeUUIDs(for: deepDive) {
            guard let thinkspace = try? await AtomRepository.shared.fetch(uuid: thinkspaceUUID),
                  let metadata = thinkspace.metadataValue(as: ThinkspaceMetadata.self),
                  !metadata.clusters.isEmpty else { continue }
            for cluster in metadata.clusters where !cluster.blockUUIDs.isEmpty {
                let entityUUIDs = (try? await Self.entityUUIDs(
                    forBlockIds: cluster.blockUUIDs, thinkspaceUUID: thinkspaceUUID
                )) ?? []
                let members = entityUUIDs.filter { connectionUUIDs.contains($0) }
                guard members.count >= ConceptCartographerSignals.Thresholds.groupMinMembers else { continue }
                results.append(ConceptCartographerSignals.CanvasClusterFacts(
                    name: cluster.name, memberConnectionUUIDs: members
                ))
            }
        }
        return results
    }

    private static func entityUUIDs(forBlockIds blockIds: [String], thinkspaceUUID: String) async throws -> [String] {
        guard !blockIds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: blockIds.count).joined(separator: ",")
        return try await CosmoDatabase.shared.asyncRead { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT entity_uuid FROM canvas_blocks
                    WHERE id IN (\(placeholders)) AND thinkspace_id = ?
                      AND entity_type = 'connection' AND is_deleted = 0
                """,
                arguments: StatementArguments(blockIds + [thinkspaceUUID])
            )
        }
    }

    // MARK: - LLM judgment

    static let systemPrompt = """
    You are Cosmo's Cartographer. You look at the concept map of one research \
    topic — a flat, ever-growing list of top-level concept pillars, plus the \
    GROWING SEEDLINGS still accruing captures before they earn a page — and \
    propose a small amount of STRUCTURE: group sibling pillars under a new \
    broader section, nest a pillar under an existing concept it clearly \
    belongs to, or fold several micro-seedlings into the one concept they are \
    all facets of.

    RULES:
    - Propose at most 3 changes, and ONLY changes that clearly improve \
    navigation. An empty proposals array is a good answer for a map that is \
    fine as it is.
    - Section names are broad, plain domains in the topic's own vocabulary \
    ("Epistemics", "Practice", "Feedback loops") — never clever, never jargon \
    the user hasn't used.
    - Groups take 2–6 members. Never group everything under one giant section.
    - A concept is nested only when the parent genuinely contains it — \
    thematic neighborhood is a GROUP, containment is a NEST.
    - FOLD is for seedlings only, and it is the encyclopedia-entry test in \
    reverse: when several thin seedlings are ASPECTS of one topic a reader \
    would look up ("Pitch", "Pace", "Prosody" are all facets of vocal \
    delivery), fold them into that one umbrella concept. The umbrella may be \
    a listed seedling's own name or a new plain name in the topic's \
    vocabulary. Folds take 2–6 members. Never fold seedlings that are \
    genuinely distinct topics just because they are small — a fold you are \
    unsure of is a fold you do not propose.
    - Use only the ids given (c… for concept pages, s… for seedlings). \
    Respond with JSON only, no prose.

    FORMAT:
    {"proposals":[
      {"kind":"group","name":"<section name>","members":["c2","c3"],"reason":"<one calm sentence>"},
      {"kind":"nest","child":"c9","parent":"c4","reason":"<one calm sentence>"},
      {"kind":"fold","umbrella":"<concept name>","members":["s1","s3"],"reason":"<one calm sentence>"}
    ]}
    """

    private func llmDrafts(
        deepDive: Atom,
        facts: [ConceptCartographerSignals.ConceptFacts],
        extracts: [Atom],
        seedlings: [ConceptCartographerSignals.SeedlingFacts] = []
    ) async -> [ConceptCartographerSignals.Draft] {
        // Stable aliases (c1, c2, …) — models mangle raw UUIDs.
        let ordered = facts.sorted { lhs, rhs in
            if lhs.noteCount != rhs.noteCount { return lhs.noteCount > rhs.noteCount }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.uuid < rhs.uuid
        }
        var uuidByAlias: [String: String] = [:]
        var lines: [String] = []
        var nestedLines: [String] = []
        let titleByUUID = Dictionary(
            facts.map { ($0.uuid, $0.title) }, uniquingKeysWith: { first, _ in first }
        )
        for (index, fact) in ordered.enumerated() {
            let alias = "c\(index + 1)"
            uuidByAlias[alias] = fact.uuid
            var tags: [String] = []
            if fact.isSection { tags.append("section") }
            if fact.isPinned { tags.append("pinned — do not move") }
            let notes = fact.noteCount == 1 ? "1 note" : "\(fact.noteCount) notes"
            let suffix = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
            if fact.parentUUID == nil {
                lines.append("\(alias) · \(fact.title) · \(notes)\(suffix)")
            } else {
                let parent = fact.parentUUID.flatMap { titleByUUID[$0] } ?? "?"
                nestedLines.append("\(alias) · \(fact.title) → under \(parent)\(suffix)")
            }
        }

        let uuidByConceptKey = Dictionary(
            facts.compactMap { fact -> (String, String)? in
                let key = ConceptResolver.conceptKey(fact.title)
                return key.isEmpty ? nil : (key, fact.uuid)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let pairs = ConceptCartographerSignals.coOccurrencePairs(
            conceptNamesPerExtract: extracts.compactMap { $0.extractMetadata?.conceptNames },
            uuidByConceptKey: uuidByConceptKey,
            titleByUUID: titleByUUID
        )

        // Seedling aliases (s1, s2, …) — foldable ones only; a pinned or
        // page-tied seedling the model can't fold shouldn't tempt it.
        let foldableSeedlings = seedlings.filter { $0.isFoldable && !$0.isPinned }
        var seedlingKeyByAlias: [String: String] = [:]
        var seedlingLines: [String] = []
        for (index, seedling) in foldableSeedlings.enumerated() {
            let alias = "s\(index + 1)"
            seedlingKeyByAlias[alias] = seedling.conceptKey
            let captures = seedling.pendingCount == 1 ? "1 capture" : "\(seedling.pendingCount) captures"
            seedlingLines.append("\(alias) · \(seedling.name) · \(captures)")
        }

        var prompt = "TOPIC: \(deepDive.title ?? "Deep Dive")\n\nTOP-LEVEL PILLARS:\n"
        prompt += lines.joined(separator: "\n")
        if !nestedLines.isEmpty {
            prompt += "\n\nALREADY NESTED:\n" + nestedLines.joined(separator: "\n")
        }
        if !seedlingLines.isEmpty {
            prompt += "\n\nGROWING SEEDLINGS (fold candidates):\n" + seedlingLines.joined(separator: "\n")
        }
        if !pairs.isEmpty {
            prompt += "\n\nCAPTURED TOGETHER (shared notes):\n"
            prompt += pairs.map { "“\($0.a)” + “\($0.b)” · \($0.count)×" }.joined(separator: "\n")
        }
        prompt += "\n\nPropose structure per the rules. JSON only."

        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: Self.systemPrompt,
                tier: .strategist,
                maxTokens: 900,
                disableReasoning: true  // structured JSON on Sonnet 5: thinking would share this budget
            )
            return Self.parseDrafts(raw: raw, uuidByAlias: uuidByAlias, seedlingKeyByAlias: seedlingKeyByAlias)
        } catch {
            print("[ConceptCartographer] LLM failed: \(error) — canvas-cluster drafts only")
            return []
        }
    }

    /// Defensive parse: iterate arrays, drop malformed entries and unknown
    /// aliases entry-by-entry. Never trusts model keys as dictionary keys.
    static func parseDrafts(
        raw: String,
        uuidByAlias: [String: String],
        seedlingKeyByAlias: [String: String] = [:]
    ) -> [ConceptCartographerSignals.Draft] {
        guard let object = ConceptResolver.jsonObject(from: raw),
              let entries = object["proposals"] as? [[String: Any]] else { return [] }
        var drafts: [ConceptCartographerSignals.Draft] = []
        for entry in entries {
            let reason = (entry["reason"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch entry["kind"] as? String {
            case "fold":
                guard let umbrella = (entry["umbrella"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !umbrella.isEmpty,
                      let aliases = entry["members"] as? [String] else { continue }
                let members = aliases.compactMap { seedlingKeyByAlias[$0.trimmingCharacters(in: .whitespaces)] }
                guard members.count == aliases.count, !members.isEmpty else { continue }
                drafts.append(ConceptCartographerSignals.Draft(
                    kind: .foldSeedlings(umbrellaName: umbrella, memberKeys: members),
                    reason: reason.isEmpty ? "These seedlings are facets of one concept" : reason
                ))
            case "group":
                guard let name = (entry["name"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                      let aliases = entry["members"] as? [String] else { continue }
                let members = aliases.compactMap { uuidByAlias[$0.trimmingCharacters(in: .whitespaces)] }
                guard members.count == aliases.count, !members.isEmpty else { continue }
                drafts.append(ConceptCartographerSignals.Draft(
                    kind: .group(name: name, memberUUIDs: members),
                    reason: reason.isEmpty ? "These pillars cover one territory" : reason
                ))
            case "nest":
                guard let childAlias = entry["child"] as? String,
                      let parentAlias = entry["parent"] as? String,
                      let child = uuidByAlias[childAlias.trimmingCharacters(in: .whitespaces)],
                      let parent = uuidByAlias[parentAlias.trimmingCharacters(in: .whitespaces)] else { continue }
                drafts.append(ConceptCartographerSignals.Draft(
                    kind: .nest(childUUID: child, parentUUID: parent),
                    reason: reason.isEmpty ? "It sits inside the broader concept" : reason
                ))
            default:
                continue
            }
        }
        return drafts
    }
}
