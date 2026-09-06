// CosmoOS/AI/InboxDestinationAtlas.swift
// The Atlas — a live catalog of every place a captured thought can do work.
//
// The June 2026 router could only see thinkspaces and clusters, scored by
// centroid cosine (the *average* of member embeddings — semantic mush). The
// Atlas replaces geometry with intent: each destination carries a CHARTER, a
// one-to-two-line statement of what belongs there, assembled from signal the
// workspace already persists (cluster intent, connection sections, deep-dive
// understanding, client niches). Charters are embedded and cached; the router
// shortlists across ALL destination kinds before one taught LLM call decides.
//
// Destination kinds:
//   thinkspace / cluster — spatial homes (the classic destinations)
//   connection           — concept pages that mature section by section
//   deepDive             — long-term research topics
//   question             — open inquiry questions (a capture can ADVANCE one)
//   client               — ghostwriting clients (niche-matched, never guessed)
//
// Runs off the main actor; repository fetches hop to @MainActor singletons.
// July 2026 — Atlas routing.

import Foundation

enum InboxAtlasKind: String, Sendable, CaseIterable {
    case thinkspace
    case group
    case page
    case cluster
    case connection
    case deepDive
    case question
    case client
    /// Growing proto-concepts (the global Seedbed) — where insight-shaped
    /// captures accrue mass instead of landing as canvas objects.
    case seedling
}

struct InboxAtlasEntry: Sendable, Equatable {
    /// Stable prompt key, e.g. "cluster-<id>", "question-<uuid>".
    let key: String
    let kind: InboxAtlasKind
    let uuid: String
    let name: String
    /// What belongs here — intentional scope, not an embedding average.
    let charter: String
    /// A few member/example titles so the model sees contents, not just names.
    let examples: [String]
    let parentUUID: String?
    let parentName: String?
    var filingDestination: InboxFilingDestination? = nil
    /// The Space whose Inquiries page hosts this topic/question (research
    /// profiles are one-to-one with Spaces since September 2026). The
    /// shortlist keeps that Space reachable; the card names its key.
    var hostSpaceUUID: String? = nil

    /// Content fingerprint — charter or examples changing invalidates the
    /// cached embedding for this entry.
    var fingerprint: Int {
        var hasher = Hasher()
        hasher.combine(key)
        hasher.combine(charter)
        hasher.combine(examples)
        return hasher.finalize()
    }

    /// The text the entry is embedded under for Stage-A retrieval.
    var embeddingText: String {
        var parts = [name, charter]
        if !examples.isEmpty {
            parts.append(examples.joined(separator: ". "))
        }
        return parts.joined(separator: ". ")
    }
}

actor InboxDestinationAtlas {
    static let shared = InboxDestinationAtlas()

    /// Snapshot freshness window. Assembly is a handful of repository reads —
    /// cheap, but a queue drain classifies items back-to-back and shouldn't
    /// re-fetch the world for each one.
    private let snapshotTTL: TimeInterval = 120

    /// Caps keep the prompt honest and the first embedding pass bounded.
    private let connectionLimit = 40
    private let openQuestionsPerDive = 6
    private let openQuestionTotalLimit = 48
    private let exampleTitleLimit = 3

    private var cachedEntries: [InboxAtlasEntry] = []
    private var cachedAt: Date = .distantPast

    private struct EmbeddingEntry {
        let fingerprint: Int
        let vector: [Float]
    }
    private var embeddingCache: [String: EmbeddingEntry] = [:]

    private init() {}

    // MARK: - Snapshot

    func entries() async -> [InboxAtlasEntry] {
        if Date().timeIntervalSince(cachedAt) < snapshotTTL, !cachedEntries.isEmpty {
            return cachedEntries
        }
        let built = await buildEntries()
        cachedEntries = built
        cachedAt = Date()
        return built
    }

    /// Drop the snapshot (called after placements/destination edits mutate the
    /// world). Embeddings stay — fingerprints already invalidate stale ones.
    func invalidate() {
        cachedEntries = []
        cachedAt = .distantPast
    }

    // MARK: - Stage A retrieval

    struct ScoredEntry: Sendable {
        let entry: InboxAtlasEntry
        let similarity: Double
    }

    /// Cross-kind shortlist for one capture. Per-kind quotas instead of one
    /// global top-K: charters differ wildly in length and register (a client
    /// niche line never out-scores a topical cluster on raw cosine), and the
    /// Stage-B model — not the retriever — makes the final call.
    func shortlist(queryVector: [Float]) async -> [ScoredEntry] {
        let all = await entries()
        guard !all.isEmpty else { return [] }

        var scored: [InboxAtlasKind: [ScoredEntry]] = [:]
        for entry in all {
            guard let vector = await embedding(for: entry) else { continue }
            let similarity = Double(RecallVectorMath.dot(queryVector, vector))
            scored[entry.kind, default: []].append(ScoredEntry(entry: entry, similarity: similarity))
        }
        for kind in scored.keys {
            scored[kind]?.sort { $0.similarity > $1.similarity }
        }

        var result: [ScoredEntry] = []
        func take(_ kind: InboxAtlasKind, _ count: Int) {
            result.append(contentsOf: (scored[kind] ?? []).prefix(count))
        }
        take(.group, 4)
        take(.page, 4)
        take(.cluster, 2)
        take(.thinkspace, 3)
        take(.connection, 3)
        take(.deepDive, 2)
        take(.question, 3)
        take(.seedling, 3)
        // Clients are few and the misattribution stakes are high ("always
        // Josh") — the model always sees the full roster to pick or veto.
        result.append(contentsOf: scored[.client] ?? [])

        // A research topic's ROOM must be reachable: when a topic (or one of
        // its open questions) makes the shortlist, the Space that hosts it
        // rides along even if its own charter scored low — otherwise
        // startInquiry has no valid key and a research capture falls to a
        // folder. Spaces host inquiries (September 2026).
        let present = Set(result.map(\.entry.key))
        var hostSpaceUUIDs = Set<String>()
        for scored in result where scored.entry.kind == .deepDive || scored.entry.kind == .question {
            if let host = scored.entry.hostSpaceUUID { hostSpaceUUIDs.insert(host) }
        }
        for host in hostSpaceUUIDs {
            let key = "thinkspace-\(host)"
            guard !present.contains(key),
                  let entry = scored[.thinkspace]?.first(where: { $0.entry.key == key }) else { continue }
            result.append(entry)
        }

        return result
    }

    private func embedding(for entry: InboxAtlasEntry) async -> [Float]? {
        let fingerprint = entry.fingerprint
        if let cached = embeddingCache[entry.key], cached.fingerprint == fingerprint {
            return cached.vector
        }
        guard let vector = try? await RecallEmbedding.embedText(String(entry.embeddingText.prefix(1000))) else {
            return nil
        }
        embeddingCache[entry.key] = EmbeddingEntry(fingerprint: fingerprint, vector: vector)
        return vector
    }

    // MARK: - Assembly

    private func buildEntries() async -> [InboxAtlasEntry] {
        async let spatialEntries = buildSpatialEntries()
        async let compositionEntries = buildCompositionEntries()
        async let connectionEntries = buildConnectionEntries()
        async let inquiryEntries = buildInquiryEntries()
        async let clientEntries = buildClientEntries()
        async let seedlingEntries = buildSeedlingEntries()
        let inquiries = await inquiryEntries
        let spaces = Self.annotatingInquiries(await spatialEntries, inquiries: inquiries)
        return await spaces + compositionEntries + connectionEntries + inquiries + clientEntries + seedlingEntries
    }

    /// A Space that hosts research says so on its card — the open questions
    /// living there are the best evidence that a research capture belongs
    /// in that Space's Inquiries, and they pull the Space up in retrieval.
    private static func annotatingInquiries(_ spaces: [InboxAtlasEntry], inquiries: [InboxAtlasEntry]) -> [InboxAtlasEntry] {
        var questionsBySpace: [String: [String]] = [:]
        for entry in inquiries where entry.kind == .question {
            guard let host = entry.hostSpaceUUID else { continue }
            questionsBySpace[host, default: []].append(entry.name)
        }
        let hosting = Set(inquiries.filter { $0.kind == .deepDive }.compactMap(\.hostSpaceUUID))
        return spaces.map { space in
            guard space.kind == .thinkspace, hosting.contains(space.uuid) else { return space }
            let questions = Array((questionsBySpace[space.uuid] ?? []).prefix(3))
            let inquiryLine = questions.isEmpty
                ? "Hosts inquiries — research on this workspace's subjects starts here (startInquiry)."
                : "Hosts inquiries such as: \(questions.map { "\"\($0)\"" }.joined(separator: ", ")) — new research on these subjects starts here (startInquiry)."
            return InboxAtlasEntry(
                key: space.key, kind: space.kind, uuid: space.uuid, name: space.name,
                charter: space.charter + " " + inquiryLine,
                examples: space.examples, parentUUID: space.parentUUID, parentName: space.parentName,
                filingDestination: space.filingDestination, hostSpaceUUID: nil
            )
        }
    }

    private func buildCompositionEntries() async -> [InboxAtlasEntry] {
        let destinations = (try? await InboxPlacementService.shared.destinations()) ?? []
        return destinations.filter { $0.kind == .group || $0.kind == .page }.map { destination in
            InboxAtlasEntry(key: "composition-\(destination.id)", kind: destination.kind == .group ? .group : .page,
                uuid: destination.uuid!, name: destination.name,
                charter: "\(destination.path). \(destination.defaultAction.consequence(in: destination))",
                examples: [], parentUUID: destination.spaceID, parentName: destination.path,
                filingDestination: destination)
        }
    }

    private func buildSeedlingEntries() async -> [InboxAtlasEntry] {
        // Every scope: a seedling ripening in a Deep Dive's seedbed must stay
        // reachable by routing, or dive-scoped growth goes deaf to the queue.
        let seedlings = (try? await SeedlingRepository.shared.fetchGrowingAllScopes(limit: 40)) ?? []

        // One title fetch per distinct dive scope — the entry's parent, so
        // receipts can say "Grows \"emotion\" · in Presence".
        var diveTitles: [String: String] = [:]
        for scope in Set(seedlings.compactMap(\.scopeDeepDiveUUID)) {
            if let dive = try? await AtomRepository.shared.fetch(uuid: scope), !dive.isDeleted {
                diveTitles[scope] = dive.title
            }
        }

        return seedlings.map { seedling in
            var charterParts = ["Growing seedling — a proto-concept still accruing thoughts (\(seedling.massSummary))."]
            let aliases = seedling.aliases
            if !aliases.isEmpty {
                charterParts.append("Also phrased as: \(aliases.prefix(3).joined(separator: ", ")).")
            }
            let examples = seedling.pendingThoughts
                .suffix(exampleTitleLimit)
                .map { String($0.text.prefix(80)) }
            return InboxAtlasEntry(
                key: "seedling-\(seedling.uuid)",
                kind: .seedling,
                uuid: seedling.uuid,
                name: seedling.name,
                charter: charterParts.joined(separator: " "),
                examples: examples,
                parentUUID: seedling.scopeDeepDiveUUID,
                parentName: seedling.scopeDeepDiveUUID.flatMap { diveTitles[$0] }
            )
        }
    }

    private func buildSpatialEntries() async -> [InboxAtlasEntry] {
        let thinkspaces = await fetchAtoms(type: .thinkspace)
        guard !thinkspaces.isEmpty else { return [] }

        // One bulk title fetch for every cluster's sample members.
        var sampleUUIDs: [String] = []
        for atom in thinkspaces {
            guard let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else { continue }
            for cluster in metadata.clusters {
                sampleUUIDs.append(contentsOf: cluster.blockUUIDs.prefix(exampleTitleLimit))
            }
        }
        let titlesByUUID = await fetchTitles(uuids: sampleUUIDs)

        var entries: [InboxAtlasEntry] = []
        for atom in thinkspaces {
            guard let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else { continue }

            let clusterNames = metadata.clusters.map(\.name).prefix(6)
            let charter = clusterNames.isEmpty
                ? "Workspace canvas for material that has no tighter home yet."
                : "Workspace canvas whose threads include: \(clusterNames.joined(separator: ", "))."
            entries.append(InboxAtlasEntry(
                key: "thinkspace-\(atom.uuid)",
                kind: .thinkspace,
                uuid: atom.uuid,
                name: metadata.name,
                charter: charter,
                examples: [],
                parentUUID: nil,
                parentName: nil
            ))
        }
        return entries
    }

    private func buildConnectionEntries() async -> [InboxAtlasEntry] {
        let connections = await fetchAtoms(type: .connection)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(connectionLimit)

        return connections.compactMap { atom in
            guard let title = atom.title, !title.isEmpty else { return nil }
            let structured = atom.structured.flatMap { ConnectionStructuredData.fromJSON($0) }
            let filled = (structured?.sections ?? []).filter { !$0.items.isEmpty }

            var charterParts: [String] = ["Concept page."]
            if let goal = filled.first(where: { $0.type == .goal })?.items.first {
                charterParts.append("Goal: \(String(goal.content.prefix(140))).")
            } else if let firstItem = filled.first?.items.first {
                charterParts.append(String(firstItem.content.prefix(140)))
            } else if let body = atom.body, !body.isEmpty {
                charterParts.append(String(body.prefix(140)))
            }
            if !filled.isEmpty {
                charterParts.append("Developed sections: \(filled.map { $0.type.displayName }.joined(separator: ", ")).")
            }

            let examples = filled
                .flatMap(\.items)
                .prefix(exampleTitleLimit)
                .map { String($0.content.prefix(80)) }

            return InboxAtlasEntry(
                key: "connection-\(atom.uuid)",
                kind: .connection,
                uuid: atom.uuid,
                name: title,
                charter: charterParts.joined(separator: " "),
                examples: Array(examples),
                parentUUID: nil,
                parentName: nil
            )
        }
    }

    private func buildInquiryEntries() async -> [InboxAtlasEntry] {
        let deepDives = await fetchAtoms(type: .deepDive)
        guard !deepDives.isEmpty else { return [] }

        // One pass over all questions, grouped by topic — never N fetches.
        let allQuestions = await fetchAtoms(type: .question)
        var openByDive: [String: [Atom]] = [:]
        for question in allQuestions {
            guard let meta = question.questionMetadata,
                  let diveUUID = meta.parentDeepDiveUUID,
                  meta.status == .open || meta.status == .researching || meta.status == .partiallyAnswered
            else { continue }
            openByDive[diveUUID, default: []].append(question)
        }

        var entries: [InboxAtlasEntry] = []
        var questionBudget = openQuestionTotalLimit

        for dive in deepDives.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard let title = dive.title, !title.isEmpty else { continue }
            let metadata = dive.deepDiveMetadata
            let hostSpace = metadata?.primaryThinkspaceUUID ?? metadata?.parentThinkspaceUUIDs?.first

            var charterParts: [String] = ["Research topic."]
            if let hostSpace {
                charterParts.append("Its inquiries live in workspace \"thinkspace-\(hostSpace)\" — new research there uses startInquiry with that key.")
            }
            if let about = dive.body, !about.isEmpty {
                charterParts.append(String(about.prefix(160)))
            }
            if let model = dive.deepDiveStructured?.currentUnderstanding.oneSentenceModel, !model.isEmpty {
                charterParts.append("Current understanding: \(String(model.prefix(160)))")
            }
            if let aliases = metadata?.topicAliases ?? metadata?.aliases, !aliases.isEmpty {
                charterParts.append("Also phrased as: \(aliases.prefix(4).joined(separator: ", ")).")
            }

            let open = (openByDive[dive.uuid] ?? [])
                .sorted { $0.updatedAt > $1.updatedAt }
            let examples = open.prefix(exampleTitleLimit).compactMap(\.title)

            entries.append(InboxAtlasEntry(
                key: "deepdive-\(dive.uuid)",
                kind: .deepDive,
                uuid: dive.uuid,
                name: title,
                charter: charterParts.joined(separator: " "),
                examples: examples,
                parentUUID: nil,
                parentName: nil,
                hostSpaceUUID: hostSpace
            ))

            for question in open.prefix(openQuestionsPerDive) {
                guard questionBudget > 0, let questionTitle = question.title, !questionTitle.isEmpty else { continue }
                questionBudget -= 1
                entries.append(InboxAtlasEntry(
                    key: "question-\(question.uuid)",
                    kind: .question,
                    uuid: question.uuid,
                    name: questionTitle,
                    charter: "Open research question in \(title). Material that helps answer it belongs here.",
                    examples: [],
                    parentUUID: dive.uuid,
                    parentName: title,
                    hostSpaceUUID: hostSpace
                ))
            }
        }
        return entries
    }

    private func buildClientEntries() async -> [InboxAtlasEntry] {
        let clients = await fetchAtoms(type: .clientProfile)
        return clients.compactMap { atom in
            guard let name = atom.title, !name.isEmpty else { return nil }
            let metadata = atom.clientMetadata
            if metadata?.isActive == false { return nil }

            var charterParts: [String] = ["Ghostwriting client."]
            if let niche = metadata?.niche, !niche.isEmpty {
                charterParts.append("Niche: \(String(niche.prefix(160))).")
            }
            if let voice = metadata?.brandVoice, !voice.isEmpty {
                charterParts.append("Voice: \(String(voice.prefix(120))).")
            }
            if charterParts.count == 1, let body = atom.body, !body.isEmpty {
                charterParts.append(String(body.prefix(160)))
            }

            return InboxAtlasEntry(
                key: "client-\(atom.uuid)",
                kind: .client,
                uuid: atom.uuid,
                name: name,
                charter: charterParts.joined(separator: " "),
                examples: [],
                parentUUID: nil,
                parentName: nil
            )
        }
    }

    // MARK: - MainActor hops

    private func fetchAtoms(type: AtomType) async -> [Atom] {
        ((try? await AtomRepository.shared.fetchAll(type: type)) ?? []).filter { !$0.isDeleted }
    }

    private func fetchTitles(uuids: [String]) async -> [String: String] {
        guard !uuids.isEmpty else { return [:] }
        let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: uuids)) ?? []
        var titles: [String: String] = [:]
        for atom in atoms {
            if let title = atom.title, !title.isEmpty {
                titles[atom.uuid] = String(title.prefix(60))
            }
        }
        return titles
    }
}
