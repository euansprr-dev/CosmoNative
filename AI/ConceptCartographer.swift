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
        }
    }

    var memberUUIDs: [String] {
        switch kind {
        case .group(_, let members): return members
        case .nest(let child, _): return [child]
        }
    }

    static func groupKey(memberUUIDs: [String]) -> String {
        "cartographer.group:" + memberUUIDs.sorted().joined(separator: "~")
    }

    static func nestKey(childUUID: String, parentUUID: String) -> String {
        "cartographer.nest:\(childUUID)~\(parentUUID)"
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
    }

    /// Whether the top level is crowded enough to consult the model at all.
    static func wantsOrganization(facts: [ConceptFacts]) -> Bool {
        let topLevel = facts.filter { $0.parentUUID == nil && !$0.isSection }
        guard topLevel.count > Thresholds.groupMinMembers else { return false }
        if topLevel.count >= Thresholds.organizeMinTopLevel { return true }
        let thin = topLevel.filter { $0.noteCount <= Thresholds.thinPillarMaxNotes }
        return thin.count >= Thresholds.organizeMinThinPillars
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
    static func validated(
        _ drafts: [Draft],
        facts: [ConceptFacts]
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

        var claimed = Set<String>()
        var seenKeys = Set<String>()
        var groups: [ConceptCartographerProposal] = []
        var nests: [ConceptCartographerProposal] = []

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
            }
        }

        // Groups first — they are the big structural wins — then nests.
        return Array((groups + nests).prefix(Thresholds.maxProposalsPerPass))
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
        guard connections.count > ConceptCartographerSignals.Thresholds.groupMinMembers else { return [] }
        let extracts: [Atom]
        if let preloadedExtracts {
            extracts = preloadedExtracts
        } else {
            extracts = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: deepDive.uuid)) ?? []
        }

        let facts = Self.makeFacts(connections: connections, extracts: extracts)
        let clusters = await canvasClusterFacts(deepDive: deepDive, connections: connections)

        var drafts = ConceptCartographerSignals.clusterDrafts(facts: facts, clusters: clusters)
        if ConceptCartographerSignals.wantsOrganization(facts: facts) {
            drafts += await llmDrafts(deepDive: deepDive, facts: facts, extracts: extracts)
        }

        let decided = await InquiryGardenerDecisionStore.shared.decidedKeys(deepDiveUUID: deepDive.uuid)
        return ConceptCartographerSignals.validated(drafts, facts: facts)
            .filter { !decided.contains($0.key) }
    }

    /// Accepts a proposal: applies the structure (section mint + parent
    /// writes + canvas mirror) and records the ruling. Returns the section
    /// page's UUID for groups (the "Develop now?" moment) — nil for nests.
    @discardableResult
    func accept(_ proposal: ConceptCartographerProposal, deepDive: Atom) async -> String? {
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
    topic — a flat, ever-growing list of top-level concept pillars — and \
    propose a small amount of STRUCTURE: group sibling pillars under a new \
    broader section, or nest a pillar under an existing concept it clearly \
    belongs to.

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
    - Use only the ids given. Respond with JSON only, no prose.

    FORMAT:
    {"proposals":[
      {"kind":"group","name":"<section name>","members":["c2","c3"],"reason":"<one calm sentence>"},
      {"kind":"nest","child":"c9","parent":"c4","reason":"<one calm sentence>"}
    ]}
    """

    private func llmDrafts(
        deepDive: Atom,
        facts: [ConceptCartographerSignals.ConceptFacts],
        extracts: [Atom]
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

        var prompt = "TOPIC: \(deepDive.title ?? "Deep Dive")\n\nTOP-LEVEL PILLARS:\n"
        prompt += lines.joined(separator: "\n")
        if !nestedLines.isEmpty {
            prompt += "\n\nALREADY NESTED:\n" + nestedLines.joined(separator: "\n")
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
                maxTokens: 900
            )
            return Self.parseDrafts(raw: raw, uuidByAlias: uuidByAlias)
        } catch {
            print("[ConceptCartographer] LLM failed: \(error) — canvas-cluster drafts only")
            return []
        }
    }

    /// Defensive parse: iterate arrays, drop malformed entries and unknown
    /// aliases entry-by-entry. Never trusts model keys as dictionary keys.
    static func parseDrafts(raw: String, uuidByAlias: [String: String]) -> [ConceptCartographerSignals.Draft] {
        guard let object = ConceptResolver.jsonObject(from: raw),
              let entries = object["proposals"] as? [[String: Any]] else { return [] }
        var drafts: [ConceptCartographerSignals.Draft] = []
        for entry in entries {
            let reason = (entry["reason"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch entry["kind"] as? String {
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
