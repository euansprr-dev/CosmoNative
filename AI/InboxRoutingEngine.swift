// CosmoOS/AI/InboxRoutingEngine.swift
// Staged inbox router — meaning over mass, abstain by default.
//
// v2 (June 2026, INBOX_REVAMP_PLAN.md §2). The v1 additive-weights heuristic
// rewarded big clusters (membership mass × 0.40) and recently-opened
// thinkspaces (recency boost up to +0.20) with a pass bar of just 0.22 — which
// is why every capture routed to the largest, most-recent cluster. v2 replaces
// that with three stages:
//
//   Stage 0  Intent gate     — what *kind* of thing is this (task/idea/note…)?
//                              Determines the verbs offered, never forces a folder.
//   Stage 1  Merge check     — near-duplicates only (high score + title overlap).
//   Stage 2  Placement       — cosine similarity against cluster/thinkspace
//                              *centroids* with a required margin over the
//                              runner-up. No membership mass, no recency boost.
//
// Anything that doesn't clear the bars abstains to `unsorted` — an honest
// state, not a fake suggestion. Stage 3 (the batched Atlas sweep for unsorted
// items — the SAME move grammar as capture time) lives in `atlasSweep(items:)`
// and is driven by InboxIngestService when the inbox becomes visible.
//
// Runs OFF the main actor: scoring, embedding math, and caching happen here;
// only repository/search/planner calls hop to @MainActor singletons.

import Foundation

actor InboxRoutingEngine {
    static let shared = InboxRoutingEngine()

    private let config = InboxRoutingConfig.shared
    private let flashModel = "google/gemini-3.1-flash-lite-preview"

    // Capture-text embeddings, keyed by content hash — repeated classification
    // of the same capture (retry, reconcile pass) never re-embeds.
    private var captureEmbeddingCache: [Int: [Float]] = [:]

    // Cluster/thinkspace centroids, keyed by destination id. The fingerprint
    // covers the sampled member list, so placements invalidate automatically.
    private struct CentroidEntry {
        let fingerprint: Int
        let vector: [Float]
    }
    private var centroidCache: [String: CentroidEntry] = [:]

    private init() {}

    // MARK: - Result

    struct RoutingResult: Sendable {
        let title: String
        let bundle: InboxRecommendationBundle
        /// True when no stage cleared its confidence bar — the item is honestly unsorted.
        let abstained: Bool
    }

    // MARK: - Classify

    func classify(
        text: String,
        source: InboxSource,
        excludedAtomUUIDs: [String] = [],
        preferredTitle: String? = nil
    ) async -> RoutingResult {
        let title = await extractTitle(from: text, preferredTitle: preferredTitle)
        let suggestedAtomType = suggestAtomType(text: text)
        let queryTokens = normalizedTokens(from: "\(title) \(text)")
        let excludedUUIDs = Set(excludedAtomUUIDs)

        // Single candidate-pool query, filtered to user content at the source —
        // system atoms (agent conversation transcripts, telemetry) never enter.
        let searchResults = await runTriageSearch(text: text, excludedAtomUUIDs: excludedAtomUUIDs)

        let atomUUIDs = searchResults.compactMap(\.entityUUID).filter { !excludedUUIDs.contains($0) }
        let atoms = await fetchAtoms(uuids: atomUUIDs)
        let atomsByUUID = Dictionary(uniqueKeysWithValues: atoms.map { ($0.uuid, $0) })

        var recommendations: [InboxRecommendation] = []

        // Stage 1 — merge: rare by design.
        if let merge = mergeRecommendation(
            title: title,
            suggestedAtomType: suggestedAtomType,
            searchResults: searchResults,
            atomsByUUID: atomsByUUID,
            excludedUUIDs: excludedUUIDs
        ) {
            recommendations.append(merge)
        }

        // Stage 2 — Atlas routing: cross-kind shortlist (Stage A, local
        // embeddings) → one taught sensor-tier call (Stage B) that answers
        // with typed moves. The pre-Atlas centroid path survives below as the
        // offline fallback — routing never regresses when no LLM is reachable.
        var routedTitle = title
        var effectiveAtomType = suggestedAtomType
        var atlasDecided = false

        if let queryVector = await captureEmbedding(for: text) {
            let shortlist = await InboxDestinationAtlas.shared.shortlist(queryVector: queryVector)
            if !shortlist.isEmpty {
                let corrections = await InboxRoutingCorrectionLedger.shared
                    .recentExamples(limit: config.atlasCorrectionExamples)
                if let decision = await InboxAtlasRouter.shared.route(
                    text: text,
                    heuristicTitle: title,
                    candidates: shortlist,
                    corrections: corrections
                ) {
                    atlasDecided = true
                    // The router names the capture too (title extraction folded
                    // into the same call) — but a user-provided title always wins.
                    let userTitled = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    if !userTitled, let cleaned = decision.title {
                        routedTitle = String(cleaned.prefix(80))
                    }
                    effectiveAtomType = Self.atomType(forCaptureType: decision.captureType) ?? suggestedAtomType
                    let moveRecommendations = await atlasRecommendations(
                        fromDecision: decision,
                        shortlist: shortlist,
                        title: routedTitle,
                        fallbackAtomType: effectiveAtomType,
                        searchResultUUIDs: Set(atomUUIDs)
                    )
                    recommendations.append(contentsOf: moveRecommendations)
                }
            }
        }

        if !atlasDecided {
            // Offline fallback — placement against centroids (pre-Atlas Stage 2).
            let placement = await placementRecommendations(
                title: title,
                text: text,
                suggestedAtomType: suggestedAtomType,
                queryTokens: queryTokens,
                searchResultUUIDs: Set(atomUUIDs)
            )
            recommendations.append(contentsOf: placement)
        }

        let abstained = recommendations.isEmpty

        if abstained {
            // The verb grid still needs a default for manual filing — a quiet,
            // low-confidence standalone option that the UI never renders as a pill.
            recommendations.append(
                InboxRecommendation(
                    kind: .createStandaloneAtom,
                    confidence: 0.30,
                    suggestedAtomType: effectiveAtomType.rawValue,
                    destinationPath: effectiveAtomType.displayName,
                    rationale: "No destination cleared the confidence bar, so this capture stays unsorted until you decide."
                )
            )
        }

        // Strong-but-not-duplicate matches power the Connect verb: a capture
        // that bridges existing material is a connection, not a merge.
        let relatedAtomUUIDs = searchResults
            .filter { result in
                guard let uuid = result.entityUUID,
                      let atom = atomsByUUID[uuid],
                      AtomType.triageable.contains(atom.type),
                      !atom.isDeleted else { return false }
                return result.combinedScore >= 0.60
            }
            .compactMap(\.entityUUID)
            .prefix(3)

        return RoutingResult(
            title: routedTitle,
            bundle: InboxRecommendationBundle(
                title: routedTitle,
                recommendations: recommendations,
                relatedAtomUUIDs: relatedAtomUUIDs.isEmpty ? nil : Array(relatedAtomUUIDs)
            ),
            abstained: abstained
        )
    }

    // MARK: - Stage 2 (Atlas) — decision → recommendations

    /// The router's capture-shape verdict mapped onto atom types. Replaces the
    /// keyword intent gate whenever the Atlas call succeeds.
    static func atomType(forCaptureType captureType: String?) -> AtomType? {
        switch captureType {
        case "task": return .task
        case "question", "idea": return .idea
        case "insight", "note": return .note
        case "source": return .research
        default: return nil
        }
    }

    /// Maps validated Atlas moves onto recommendation rows the executor and
    /// UI already understand. Spatial moves reuse the classic kinds (and get
    /// real placement plans); knowledge-graph moves carry an `InboxAtlasMove`.
    private func atlasRecommendations(
        fromDecision decision: InboxAtlasRouter.Decision,
        shortlist: [InboxDestinationAtlas.ScoredEntry],
        title: String,
        fallbackAtomType: AtomType,
        searchResultUUIDs: Set<String>
    ) async -> [InboxRecommendation] {
        let entriesByKey = Dictionary(uniqueKeysWithValues: shortlist.map { ($0.entry.key, $0.entry) })
        var results: [InboxRecommendation] = []
        // Fetched lazily — only spatial moves need the thinkspace metadata.
        var thinkspaceAtoms: [Atom]?

        for move in decision.moves where move.confidence >= config.atlasMoveMinConfidence {
            let rationale = move.growth.isEmpty
                ? "The Atlas router matched this capture against your workspace's destinations."
                : move.growth

            switch move.kind {
            case .fileToDestination:
                guard let key = move.targetKey, let destination = entriesByKey[key]?.filingDestination else { continue }
                results.append(InboxRecommendation(kind: .fileToDestination, confidence: move.confidence,
                    suggestedAtomType: AtomType.note.rawValue, destinationPath: destination.path,
                    rationale: rationale, thinkspaceId: destination.spaceID,
                    filingDestination: destination, filingAction: destination.defaultAction))
            case .advanceQuestion:
                guard let key = move.targetKey, let entry = entriesByKey[key],
                      let deepDiveUUID = entry.parentUUID else { continue }
                results.append(InboxRecommendation(
                    kind: .advanceQuestion,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.note.rawValue,
                    destinationPath: "\(entry.parentName ?? "Inquiry") › \(entry.name)",
                    rationale: rationale,
                    atlasMove: InboxAtlasMove(
                        deepDiveUUID: deepDiveUUID,
                        deepDiveName: entry.parentName,
                        questionUUID: entry.uuid,
                        questionTitle: entry.name
                    )
                ))

            case .spawnQuestion:
                guard let key = move.targetKey, let entry = entriesByKey[key],
                      let newTitle = move.newTitle else { continue }
                let parentQuestion = move.parentQuestionKey.flatMap { entriesByKey[$0] }
                results.append(InboxRecommendation(
                    kind: .spawnQuestion,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.idea.rawValue,
                    destinationPath: "\(entry.name) › new question",
                    rationale: rationale,
                    atlasMove: InboxAtlasMove(
                        deepDiveUUID: entry.uuid,
                        deepDiveName: entry.name,
                        newQuestionTitle: newTitle,
                        parentQuestionUUID: parentQuestion?.uuid
                    )
                ))

            case .feedConnection:
                guard let key = move.targetKey, let entry = entriesByKey[key],
                      let sectionRaw = move.section,
                      let section = ConnectionSectionType(rawValue: sectionRaw) else { continue }
                results.append(InboxRecommendation(
                    kind: .feedConnection,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.note.rawValue,
                    destinationPath: "\(entry.name) › \(section.displayName)",
                    rationale: rationale,
                    atlasMove: InboxAtlasMove(
                        connectionUUID: entry.uuid,
                        connectionName: entry.name,
                        connectionSection: sectionRaw
                    )
                ))

            case .attachClient:
                guard let key = move.targetKey, let entry = entriesByKey[key] else { continue }
                results.append(InboxRecommendation(
                    kind: .attachClient,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.idea.rawValue,
                    destinationPath: "Idea for \(entry.name)",
                    rationale: rationale,
                    atlasMove: InboxAtlasMove(
                        clientUUID: entry.uuid,
                        clientName: entry.name
                    )
                ))

            case .placeCluster:
                guard let key = move.targetKey, let entry = entriesByKey[key],
                      let thinkspaceId = entry.parentUUID else { continue }
                if thinkspaceAtoms == nil { thinkspaceAtoms = await fetchThinkspaceAtoms() }
                guard let thinkspaceAtom = thinkspaceAtoms?.first(where: { $0.uuid == thinkspaceId }),
                      let metadata = thinkspaceAtom.metadataValue(as: ThinkspaceMetadata.self),
                      let cluster = metadata.clusters.first(where: { $0.id == entry.uuid }) else { continue }
                let related = cluster.blockUUIDs.filter { searchResultUUIDs.contains($0) }
                guard let plan = await SpatialPlacementPlanner.shared.planForExistingCluster(
                    title: title,
                    atomType: fallbackAtomType,
                    thinkspaceId: thinkspaceId,
                    thinkspaceName: metadata.name,
                    cluster: cluster,
                    relatedAtomUUIDs: related
                ) else { continue }
                results.append(InboxRecommendation(
                    kind: .placeInExistingCluster,
                    confidence: move.confidence,
                    suggestedAtomType: fallbackAtomType.rawValue,
                    destinationPath: "\(metadata.name) › \(cluster.name)",
                    rationale: rationale,
                    thinkspaceId: thinkspaceId,
                    thinkspaceName: metadata.name,
                    clusterId: cluster.id,
                    clusterName: cluster.name,
                    placementPlan: plan
                ))

            case .placeThinkspace:
                guard let key = move.targetKey, let entry = entriesByKey[key] else { continue }
                guard let plan = await SpatialPlacementPlanner.shared.planForThinkspacePlacement(
                    title: title,
                    atomType: fallbackAtomType,
                    thinkspaceId: entry.uuid,
                    thinkspaceName: entry.name,
                    relatedAtomUUIDs: Array(searchResultUUIDs)
                ) else { continue }
                results.append(InboxRecommendation(
                    kind: .placeInThinkspace,
                    confidence: move.confidence,
                    suggestedAtomType: fallbackAtomType.rawValue,
                    destinationPath: entry.name,
                    rationale: rationale,
                    thinkspaceId: entry.uuid,
                    thinkspaceName: entry.name,
                    placementPlan: plan
                ))

            case .feedSeedling:
                guard let key = move.targetKey, let entry = entriesByKey[key] else { continue }
                let home = conceptHome(forKey: move.homeKey, entriesByKey: entriesByKey)
                // A dive-scoped seedling names its world: "Grows "emotion" · in Presence".
                let grows = entry.parentName.map { "Grows \u{201C}\(entry.name)\u{201D} · in \($0)" }
                    ?? "Grows \u{201C}\(entry.name)\u{201D}"
                results.append(InboxRecommendation(
                    kind: .feedSeedling,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.connection.rawValue,
                    destinationPath: appendHome(grows, home: home),
                    rationale: rationale,
                    atlasMove: InboxAtlasMove(
                        seedlingUUID: entry.uuid,
                        seedlingName: entry.name,
                        homeThinkspaceId: home?.thinkspaceId,
                        homeThinkspaceName: home?.thinkspaceName,
                        homeClusterId: home?.clusterId,
                        homeClusterName: home?.clusterName
                    )
                ))

            case .startSeedling:
                guard let newTitle = move.newTitle else { continue }
                let home = conceptHome(forKey: move.homeKey, entriesByKey: entriesByKey)
                results.append(InboxRecommendation(
                    kind: .startSeedling,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.connection.rawValue,
                    destinationPath: appendHome("New concept: \(newTitle)", home: home),
                    rationale: rationale,
                    atlasMove: InboxAtlasMove(
                        germinateTitle: newTitle,
                        homeThinkspaceId: home?.thinkspaceId,
                        homeThinkspaceName: home?.thinkspaceName,
                        homeClusterId: home?.clusterId,
                        homeClusterName: home?.clusterName
                    )
                ))

            case .startInquiry:
                // The Space rides the atlas move, NEVER placeThinkspaceId —
                // an inquiry suggestion must not read as a canvas placement
                // to the offline/iOS fallbacks (the "suggestion ≠ routing" law).
                guard let key = move.targetKey, let entry = entriesByKey[key],
                      let question = move.newTitle else { continue }
                results.append(InboxRecommendation(
                    kind: .startInquiry,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.inquirySession.rawValue,
                    destinationPath: "\(entry.name) › Inquiry",
                    rationale: rationale,
                    atlasMove: InboxAtlasMove(
                        newQuestionTitle: question,
                        spaceUUID: entry.uuid,
                        spaceName: entry.name
                    )
                ))

            case .germinateDeepDive:
                guard let newTitle = move.newTitle else { continue }
                results.append(InboxRecommendation(
                    kind: .germinateDeepDive,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.inquirySession.rawValue,
                    destinationPath: "New Space: \(newTitle) › Inquiry",
                    rationale: rationale,
                    atlasMove: InboxAtlasMove(germinateTitle: newTitle)
                ))

            case .fileAsSwipe:
                // The swipe file IS the destination — there is no Atlas key to
                // resolve and no placement to plan. The KIND stays unresolved
                // here on purpose: SwipeIntakeRouter decides page vs frame vs
                // note at execution time, from the capture itself.
                results.append(InboxRecommendation(
                    kind: .fileAsSwipe,
                    confidence: move.confidence,
                    suggestedAtomType: AtomType.research.rawValue,
                    destinationPath: "Swipe File",
                    rationale: rationale
                ))
            }
        }

        return results
    }

    /// The concept's future home resolved from a validated homeKey — where the
    /// developed page will live. Tags affinity; places nothing.
    private struct ConceptHome {
        let thinkspaceId: String?
        let thinkspaceName: String?
        let clusterId: String?
        let clusterName: String?
        /// The most specific human name for pills ("Mindset", else "Philosophy").
        var displayName: String? { clusterName ?? thinkspaceName }
    }

    private func conceptHome(
        forKey key: String?,
        entriesByKey: [String: InboxAtlasEntry]
    ) -> ConceptHome? {
        guard let key, let entry = entriesByKey[key] else { return nil }
        switch entry.kind {
        case .cluster:
            return ConceptHome(
                thinkspaceId: entry.parentUUID,
                thinkspaceName: entry.parentName,
                clusterId: entry.uuid,
                clusterName: entry.name
            )
        case .thinkspace:
            return ConceptHome(
                thinkspaceId: entry.uuid,
                thinkspaceName: entry.name,
                clusterId: nil,
                clusterName: nil
            )
        default:
            return nil
        }
    }

    private func appendHome(_ path: String, home: ConceptHome?) -> String {
        guard let name = home?.displayName, !name.isEmpty else { return path }
        return "\(path) — \(name)"
    }

    // MARK: - Stage 1 — Merge (near-duplicate territory only)

    private func mergeRecommendation(
        title: String,
        suggestedAtomType: AtomType,
        searchResults: [HybridSearchEngine.SearchResult],
        atomsByUUID: [String: Atom],
        excludedUUIDs: Set<String>
    ) -> InboxRecommendation? {
        let titleTokens = normalizedTokens(from: title)

        let candidates = searchResults.compactMap { result -> (atom: Atom, confidence: Double)? in
            guard let uuid = result.entityUUID,
                  !excludedUUIDs.contains(uuid),
                  let atom = atomsByUUID[uuid],
                  AtomType.triageable.contains(atom.type),
                  !atom.isDeleted,
                  !isAgentConversation(atom),
                  // Readwise mirrors are evidence, never merge targets — the
                  // next sync would clobber anything absorbed into them.
                  !atom.isReadwiseContent else {
                return nil
            }

            let candidateTitle = atom.title ?? result.title
            let exactTitleMatch = normalizedPhrase(candidateTitle) == normalizedPhrase(title)
            let titleOverlap = textMatchScore(queryTokens: titleTokens, candidate: candidateTitle)

            // The bar: a merge should feel like the system caught a duplicate.
            guard result.combinedScore >= config.mergeMinCombinedScore else { return nil }
            guard exactTitleMatch || titleOverlap >= config.mergeMinTitleOverlap else { return nil }

            let confidence = clamp01(result.combinedScore + (exactTitleMatch ? 0.10 : 0))
            return (atom, confidence)
        }

        guard let best = candidates.max(by: { $0.confidence < $1.confidence }) else { return nil }
        let targetTitle = best.atom.title ?? "Untitled"

        return InboxRecommendation(
            kind: .mergeAtom,
            confidence: best.confidence,
            suggestedAtomType: suggestedAtomType.rawValue,
            destinationPath: targetTitle,
            rationale: "This capture is nearly identical to \(targetTitle) — merging keeps one source of truth instead of a duplicate.",
            mergeTargetUuid: best.atom.uuid,
            mergeTargetTitle: targetTitle,
            mergeTargetType: best.atom.type.rawValue,
            placementPlan: InboxPlacementPlan(
                targetThinkspaceId: nil,
                targetThinkspaceName: nil,
                targetClusterId: nil,
                targetClusterName: nil,
                clusterViewMode: nil,
                blockPositionX: nil,
                blockPositionY: nil,
                clusterRect: nil,
                operations: [
                    InboxPlacementOperation(kind: .mergeIntoAtom, description: "Merge into \(targetTitle)")
                ],
                summary: "Merge \(title) into \(targetTitle)"
            )
        )
    }

    // MARK: - Stage 2 — Placement (centroids + margins)

    private struct DestinationScore {
        let thinkspaceId: String
        let thinkspaceName: String
        let cluster: CodableCluster?   // nil = thinkspace-level destination
        let semantic: Double
        let lexical: Double
        var score: Double { clamp01Static(semantic + lexical) }
    }

    private func placementRecommendations(
        title: String,
        text: String,
        suggestedAtomType: AtomType,
        queryTokens: Set<String>,
        searchResultUUIDs: Set<String>
    ) async -> [InboxRecommendation] {
        guard let queryVector = await captureEmbedding(for: text) else { return [] }

        let thinkspaceAtoms = await fetchThinkspaceAtoms()
        guard !thinkspaceAtoms.isEmpty else { return [] }

        var clusterScores: [DestinationScore] = []
        var thinkspaceScores: [DestinationScore] = []

        for atom in thinkspaceAtoms {
            guard let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else { continue }

            for cluster in metadata.clusters {
                guard let centroid = await centroid(
                    forDestination: "cluster-\(cluster.id)",
                    memberUUIDs: cluster.blockUUIDs
                ) else { continue }

                let semantic = Double(RecallVectorMath.dot(queryVector, centroid))
                let lexical = textMatchScore(
                    queryTokens: queryTokens,
                    candidate: "\(cluster.name) \(cluster.intent ?? "") \(metadata.name)"
                ) * config.lexicalBonusWeight
                clusterScores.append(
                    DestinationScore(
                        thinkspaceId: atom.uuid,
                        thinkspaceName: metadata.name,
                        cluster: cluster,
                        semantic: semantic,
                        lexical: lexical
                    )
                )
            }

            let thinkspaceMembers = metadata.blockIds.isEmpty
                ? metadata.clusters.flatMap(\.blockUUIDs)
                : metadata.blockIds
            if let centroid = await centroid(
                forDestination: "thinkspace-\(atom.uuid)",
                memberUUIDs: thinkspaceMembers
            ) {
                let semantic = Double(RecallVectorMath.dot(queryVector, centroid))
                let lexical = textMatchScore(queryTokens: queryTokens, candidate: metadata.name)
                    * config.lexicalBonusWeight
                thinkspaceScores.append(
                    DestinationScore(
                        thinkspaceId: atom.uuid,
                        thinkspaceName: metadata.name,
                        cluster: nil,
                        semantic: semantic,
                        lexical: lexical
                    )
                )
            }
        }

        clusterScores.sort { $0.score > $1.score }
        thinkspaceScores.sort { $0.score > $1.score }

        // Confident cluster: clears the floor AND beats the runner-up by a real margin.
        if let best = clusterScores.first, let cluster = best.cluster,
           best.score >= config.placementMinScore,
           clusterScores.count < 2 || (best.score - clusterScores[1].score) >= config.placementMinMargin {
            let relatedUUIDs = cluster.blockUUIDs.filter { searchResultUUIDs.contains($0) }
            if let plan = await planExistingCluster(
                title: title,
                atomType: suggestedAtomType,
                destination: best,
                cluster: cluster,
                relatedAtomUUIDs: relatedUUIDs
            ) {
                return [
                    InboxRecommendation(
                        kind: .placeInExistingCluster,
                        confidence: best.score,
                        suggestedAtomType: suggestedAtomType.rawValue,
                        destinationPath: "\(best.thinkspaceName) › \(cluster.name)",
                        rationale: placementRationale(clusterName: cluster.name, intent: cluster.intent, thinkspaceName: best.thinkspaceName),
                        thinkspaceId: best.thinkspaceId,
                        thinkspaceName: best.thinkspaceName,
                        clusterId: cluster.id,
                        clusterName: cluster.name,
                        placementPlan: plan
                    )
                ]
            }
        }

        // Confident thinkspace, no cluster tight enough: offer the thinkspace
        // surface, with "new cluster here" as the alternate.
        if let best = thinkspaceScores.first,
           best.score >= config.placementMinScore,
           thinkspaceScores.count < 2 || (best.score - thinkspaceScores[1].score) >= config.placementMinMargin {
            var recommendations: [InboxRecommendation] = []

            if let plan = await planThinkspacePlacement(
                title: title,
                atomType: suggestedAtomType,
                destination: best,
                relatedAtomUUIDs: Array(searchResultUUIDs)
            ) {
                recommendations.append(
                    InboxRecommendation(
                        kind: .placeInThinkspace,
                        confidence: best.score,
                        suggestedAtomType: suggestedAtomType.rawValue,
                        destinationPath: best.thinkspaceName,
                        rationale: "This capture belongs with the material in \(best.thinkspaceName), but no single cluster there is a tight fit.",
                        thinkspaceId: best.thinkspaceId,
                        thinkspaceName: best.thinkspaceName,
                        placementPlan: plan
                    )
                )
            }

            return recommendations
        }

        return []
    }

    private func placementRationale(clusterName: String, intent: String?, thinkspaceName: String) -> String {
        if let intent, !intent.isEmpty {
            return "\(clusterName) already collects material around “\(intent)”, and this capture sits squarely in that thread."
        }
        return "\(clusterName) inside \(thinkspaceName) is the closest existing thread by meaning, with clear distance to the next candidate."
    }

    // MARK: - Stage 3 — The Atlas sweep (batched, for unsorted items)

    /// The recovery net for unsorted captures — ONE batched sensor call that
    /// speaks the exact same move ladder as capture-time routing (concepts,
    /// questions, material, folders). Replaced the folders-only taxonomy pass
    /// July 2026: a second, poorer vocabulary was flattening insight captures
    /// into thinkspace notes. Abstain stays honest — captures the sweep
    /// returns nothing for remain unsorted, and the next sweep re-reads them
    /// against the atlas as it has grown since.
    func atlasSweep(
        items: [(uuid: String, title: String?, text: String)]
    ) async -> [String: RoutingResult] {
        guard !items.isEmpty else { return [:] }

        // Union of every capture's own shortlist (order-preserving, dedup by
        // key) — the batch shares one DESTINATIONS block, capped so twelve
        // captures can't flood the prompt.
        var seenKeys = Set<String>()
        var candidates: [InboxDestinationAtlas.ScoredEntry] = []
        for item in items {
            guard let vector = await captureEmbedding(for: item.text) else { continue }
            let shortlist = await InboxDestinationAtlas.shared.shortlist(queryVector: vector)
            for scored in shortlist where seenKeys.insert(scored.entry.key).inserted {
                candidates.append(scored)
            }
        }
        candidates = Array(candidates.prefix(config.sweepCandidateCap))
        guard !candidates.isEmpty else { return [:] }

        let corrections = await InboxRoutingCorrectionLedger.shared
            .recentExamples(limit: config.atlasCorrectionExamples)
        let decisions = await InboxAtlasRouter.shared.sweep(
            items: items,
            candidates: candidates,
            corrections: corrections
        )
        guard !decisions.isEmpty else { return [:] }

        var results: [String: RoutingResult] = [:]
        for item in items {
            guard let decision = decisions[item.uuid] else { continue }

            let userTitled = item.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            var routedTitle = item.title ?? fallbackTitle(from: item.text)
            if !userTitled, let cleaned = decision.title {
                routedTitle = String(cleaned.prefix(80))
            }
            let atomType = Self.atomType(forCaptureType: decision.captureType)
                ?? suggestAtomType(text: item.text)

            let recommendations = await atlasRecommendations(
                fromDecision: decision,
                shortlist: candidates,
                title: routedTitle,
                fallbackAtomType: atomType,
                searchResultUUIDs: []
            )
            // No surviving moves = the sweep abstained for this capture;
            // it stays honestly unsorted (no result row at all).
            guard !recommendations.isEmpty else { continue }

            results[item.uuid] = RoutingResult(
                title: routedTitle,
                bundle: InboxRecommendationBundle(
                    title: routedTitle,
                    recommendations: recommendations
                ),
                abstained: false
            )
        }
        return results
    }

    // MARK: - Embeddings & centroids

    private func captureEmbedding(for text: String) async -> [Float]? {
        var hasher = Hasher()
        hasher.combine(text)
        let key = hasher.finalize()

        if let cached = captureEmbeddingCache[key] { return cached }
        guard let vector = try? await RecallEmbedding.embedText(text) else {
            return nil
        }
        // Bound the cache — captures are transient.
        if captureEmbeddingCache.count > 128 { captureEmbeddingCache.removeAll() }
        captureEmbeddingCache[key] = vector
        return vector
    }

    private func centroid(forDestination id: String, memberUUIDs: [String]) async -> [Float]? {
        guard !memberUUIDs.isEmpty else { return nil }
        let sample = Array(memberUUIDs.prefix(config.centroidSampleLimit))

        var hasher = Hasher()
        hasher.combine(sample)
        let fingerprint = hasher.finalize()

        if let cached = centroidCache[id], cached.fingerprint == fingerprint {
            return cached.vector
        }

        guard case let vectors = await RecallStore.shared.embeddings(forEntityUuids: sample),
              !vectors.isEmpty else {
            return nil
        }

        let dimension = vectors.values.first?.count ?? 0
        guard dimension > 0 else { return nil }

        var mean = [Float](repeating: 0, count: dimension)
        var counted = 0
        for vector in vectors.values where vector.count == dimension {
            for i in 0..<dimension { mean[i] += vector[i] }
            counted += 1
        }
        guard counted > 0 else { return nil }
        for i in 0..<dimension { mean[i] /= Float(counted) }

        centroidCache[id] = CentroidEntry(fingerprint: fingerprint, vector: mean)
        return mean
    }

    /// Drop a destination's cached centroid (called after placements mutate membership).
    func invalidateCentroids() {
        centroidCache.removeAll()
    }

    // MARK: - MainActor hops (search, repos, planner)

    private func runTriageSearch(text: String, excludedAtomUUIDs: [String]) async -> [HybridSearchEngine.SearchResult] {
        (try? await HybridSearchEngine.shared.search(
            query: text,
            limit: config.searchLimit,
            entityTypes: EntityType.inboxTriageable,
            excludedEntityUUIDs: excludedAtomUUIDs
        )) ?? []
    }

    private func fetchAtoms(uuids: [String]) async -> [Atom] {
        guard !uuids.isEmpty else { return [] }
        return (try? await AtomRepository.shared.fetchBatch(uuids: uuids)) ?? []
    }

    private func fetchThinkspaceAtoms() async -> [Atom] {
        ((try? await AtomRepository.shared.fetchAll(type: .thinkspace)) ?? []).filter { !$0.isDeleted }
    }

    private func planExistingCluster(
        title: String,
        atomType: AtomType,
        destination: DestinationScore,
        cluster: CodableCluster,
        relatedAtomUUIDs: [String]
    ) async -> InboxPlacementPlan? {
        await SpatialPlacementPlanner.shared.planForExistingCluster(
            title: title,
            atomType: atomType,
            thinkspaceId: destination.thinkspaceId,
            thinkspaceName: destination.thinkspaceName,
            cluster: cluster,
            relatedAtomUUIDs: relatedAtomUUIDs
        )
    }

    private func planThinkspacePlacement(
        title: String,
        atomType: AtomType,
        destination: DestinationScore,
        relatedAtomUUIDs: [String]
    ) async -> InboxPlacementPlan? {
        await SpatialPlacementPlanner.shared.planForThinkspacePlacement(
            title: title,
            atomType: atomType,
            thinkspaceId: destination.thinkspaceId,
            thinkspaceName: destination.thinkspaceName,
            relatedAtomUUIDs: relatedAtomUUIDs
        )
    }

    private func planNewCluster(
        title: String,
        atomType: AtomType,
        destination: DestinationScore,
        clusterName: String,
        relatedAtomUUIDs: [String]
    ) async -> InboxPlacementPlan? {
        await SpatialPlacementPlanner.shared.planForNewCluster(
            title: title,
            atomType: atomType,
            thinkspaceId: destination.thinkspaceId,
            thinkspaceName: destination.thinkspaceName,
            clusterName: clusterName,
            relatedAtomUUIDs: relatedAtomUUIDs
        )
    }

    // MARK: - Stage 0 — Intent gate (heuristic, local)

    private func isAgentConversation(_ atom: Atom) -> Bool {
        guard atom.type == .systemEvent else { return false }
        return atom.metadata?.contains("\"subtype\":\"agent_conversation\"") ?? false
    }

    private func suggestAtomType(text: String) -> AtomType {
        let lower = text.lowercased()
        if ["todo", "task", "deadline", "follow up", "schedule", "remind me"].contains(where: { lower.contains($0) }) {
            return .task
        }
        if ["article", "study", "paper", "source", "read this"].contains(where: { lower.contains($0) }) {
            return .research
        }
        if ["idea", "what if", "concept", "thesis"].contains(where: { lower.contains($0) }) {
            return .idea
        }
        if lower.count < 80 {
            return .idea
        }
        return .note
    }

    // MARK: - Title extraction

    private func extractTitle(from text: String, preferredTitle: String?) async -> String {
        if let preferredTitle, !preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferredTitle
        }

        // Cheap path first: if the text has a usable opening sentence, use it.
        // Only fall through to an LLM title extraction for long, run-on captures
        // with no natural sentence break in the first 80 chars.
        let words = text.split(whereSeparator: \.isWhitespace)
        let firstSentence = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if words.count < 60 || (!firstSentence.isEmpty && firstSentence.count <= 80) {
            let candidate = firstSentence.isEmpty ? text : firstSentence
            return String(candidate.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: """
                Extract a concise title of at most 8 words for this capture. Return only the title.

                \(String(text.prefix(1200)))
                """,
                model: flashModel,
                maxTokens: 24,
                temperature: 0.0
            )
            let cleaned = response
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return cleaned.isEmpty ? fallbackTitle(from: text) : String(cleaned.prefix(80))
        } catch {
            return fallbackTitle(from: text)
        }
    }

    private func fallbackTitle(from text: String) -> String {
        let firstSentence = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? text
        return String(firstSentence.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func suggestClusterName(from title: String, removing thinkspaceName: String?) -> String {
        var cleaned = title
        if let thinkspaceName, !thinkspaceName.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: thinkspaceName, with: "", options: [.caseInsensitive])
        }
        cleaned = cleaned
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "New Cluster"
        }
        return String(cleaned.split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ")).capitalized
    }

    // MARK: - Text scoring

    private func normalizedTokens(from text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(
            text.lowercased()
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 2 }
        )
    }

    private func textMatchScore(queryTokens: Set<String>, candidate: String) -> Double {
        let candidateTokens = normalizedTokens(from: candidate)
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }

        let overlap = queryTokens.intersection(candidateTokens)
        return clamp01(Double(overlap.count) / Double(max(queryTokens.count, candidateTokens.count)))
    }

    private func normalizedPhrase(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private func clamp01Static(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
