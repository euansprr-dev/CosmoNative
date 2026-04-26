import Foundation

@MainActor
final class InboxRoutingEngine {
    static let shared = InboxRoutingEngine()

    private let hybridSearch = HybridSearchEngine.shared
    private let atomRepository = AtomRepository.shared
    private let planner = SpatialPlacementPlanner.shared
    private let flashModel = "google/gemini-3.1-flash-lite-preview"

    private init() {}

    struct RoutingResult: Sendable {
        let title: String
        let bundle: InboxRecommendationBundle
    }

    private struct ThinkspaceCandidate {
        let id: String
        let name: String
        let metadata: ThinkspaceMetadata
        let lastOpened: Date
        let score: Double
        let lexicalScore: Double
        let membershipScore: Double
        let recentBoost: Double
    }

    private struct ClusterCandidate {
        let thinkspaceId: String
        let thinkspaceName: String
        let thinkspaceMetadata: ThinkspaceMetadata
        let cluster: CodableCluster
        let score: Double
        let lexicalScore: Double
        let memberScore: Double
        let graphScore: Double
        let recentBoost: Double
        let relatedAtomUUIDs: [String]
    }

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

        let searchResults = (try? await hybridSearch.search(
            query: text,
            limit: 12,
            entityTypes: nil,
            excludedEntityUUIDs: excludedAtomUUIDs
        )) ?? []

        let atomUUIDs = searchResults.compactMap(\.entityUUID)
            .filter { !excludedUUIDs.contains($0) }
        let atoms = (try? await atomRepository.fetchBatch(uuids: atomUUIDs)) ?? []
        let atomsByUUID = Dictionary(uniqueKeysWithValues: atoms.map { ($0.uuid, $0) })
        let memberships = (try? await atomRepository.fetchThinkspaceMembership(for: atomUUIDs)) ?? [:]
        let graphBoosts = await buildGraphBoosts(searchResults: searchResults, excludedUUIDs: excludedUUIDs)

        let thinkspaceAtoms = ((try? await atomRepository.fetchAll(type: .thinkspace)) ?? []).filter { !$0.isDeleted }
        let thinkspaceCandidates = buildThinkspaceCandidates(
            from: thinkspaceAtoms,
            queryTokens: queryTokens,
            searchResults: searchResults,
            memberships: memberships
        )
        let clusterCandidates = buildClusterCandidates(
            from: thinkspaceAtoms,
            queryTokens: queryTokens,
            searchResults: searchResults,
            graphBoosts: graphBoosts
        )

        var recommendations: [InboxRecommendation] = []

        if let mergeRecommendation = bestMergeRecommendation(
            title: title,
            text: text,
            suggestedAtomType: suggestedAtomType,
            searchResults: searchResults,
            atomsByUUID: atomsByUUID,
            graphBoosts: graphBoosts,
            excludedUUIDs: excludedUUIDs
        ) {
            recommendations.append(mergeRecommendation)
        }

        if let bestCluster = clusterCandidates.first,
           let placementPlan = await planner.planForExistingCluster(
                title: title,
                atomType: suggestedAtomType,
                thinkspaceId: bestCluster.thinkspaceId,
                thinkspaceName: bestCluster.thinkspaceName,
                cluster: bestCluster.cluster,
                relatedAtomUUIDs: bestCluster.relatedAtomUUIDs
           ) {
            recommendations.append(
                InboxRecommendation(
                    kind: .placeInExistingCluster,
                    confidence: bestCluster.score,
                    suggestedAtomType: suggestedAtomType.rawValue,
                    destinationPath: "\(bestCluster.thinkspaceName) › \(bestCluster.cluster.name)",
                    rationale: existingClusterRationale(bestCluster),
                    thinkspaceId: bestCluster.thinkspaceId,
                    thinkspaceName: bestCluster.thinkspaceName,
                    clusterId: bestCluster.cluster.id,
                    clusterName: bestCluster.cluster.name,
                    placementPlan: placementPlan
                )
            )
        }

        if let bestThinkspace = thinkspaceCandidates.first {
            let clusterName = suggestClusterName(from: title, removing: bestThinkspace.name)

            if let clusterRecommendationPlan = await planner.planForNewCluster(
                title: title,
                atomType: suggestedAtomType,
                thinkspaceId: bestThinkspace.id,
                thinkspaceName: bestThinkspace.name,
                clusterName: clusterName,
                relatedAtomUUIDs: atomUUIDs
            ) {
                let clusterConfidence = newClusterConfidence(bestThinkspace: bestThinkspace, bestExistingCluster: clusterCandidates.first)
                recommendations.append(
                    InboxRecommendation(
                        kind: .createClusterAndPlace,
                        confidence: clusterConfidence,
                        suggestedAtomType: suggestedAtomType.rawValue,
                        destinationPath: "\(bestThinkspace.name) › \(clusterName)",
                        rationale: "The capture aligns with \(bestThinkspace.name), but no current cluster is tight enough. Creating \(clusterName) keeps it distinct from nearby material.",
                        thinkspaceId: bestThinkspace.id,
                        thinkspaceName: bestThinkspace.name,
                        clusterId: clusterRecommendationPlan.targetClusterId,
                        clusterName: clusterName,
                        placementPlan: clusterRecommendationPlan
                    )
                )
            }

            if let thinkspacePlan = await planner.planForThinkspacePlacement(
                title: title,
                atomType: suggestedAtomType,
                thinkspaceId: bestThinkspace.id,
                thinkspaceName: bestThinkspace.name,
                relatedAtomUUIDs: atomUUIDs
            ) {
                recommendations.append(
                    InboxRecommendation(
                        kind: .placeInThinkspace,
                        confidence: max(0.30, bestThinkspace.score - 0.06),
                        suggestedAtomType: suggestedAtomType.rawValue,
                        destinationPath: bestThinkspace.name,
                        rationale: "The strongest structural match is the \(bestThinkspace.name) thinkspace, but the topic looks more like a fresh block than a direct merge.",
                        thinkspaceId: bestThinkspace.id,
                        thinkspaceName: bestThinkspace.name,
                        placementPlan: thinkspacePlan
                    )
                )
            }
        }

        let broadTopic = shouldCreateThinkspace(
            title: title,
            text: text,
            bestMergeScore: recommendations.first(where: { $0.kind == .mergeAtom })?.confidence ?? 0,
            bestThinkspaceScore: thinkspaceCandidates.first?.score ?? 0
        )

        if broadTopic {
            let thinkspaceName = suggestedThinkspaceName(from: title)
            let thinkspacePlan = planner.planForNewThinkspace(
                title: title,
                atomType: suggestedAtomType,
                thinkspaceName: thinkspaceName
            )

            recommendations.append(
                InboxRecommendation(
                    kind: .createThinkspaceAndPlace,
                    confidence: max(0.40, 0.55 - (thinkspaceCandidates.first?.score ?? 0) * 0.2),
                    suggestedAtomType: suggestedAtomType.rawValue,
                    destinationPath: thinkspaceName,
                    rationale: "This looks broader than a one-off note and doesn’t cleanly fit an existing thinkspace. Spinning up \(thinkspaceName) gives it room to grow.",
                    thinkspaceId: nil,
                    thinkspaceName: thinkspaceName,
                    clusterId: thinkspacePlan.targetClusterId,
                    clusterName: thinkspacePlan.targetClusterName,
                    placementPlan: thinkspacePlan
                )
            )
        }

        recommendations.append(
            InboxRecommendation(
                kind: .createStandaloneAtom,
                confidence: 0.26,
                suggestedAtomType: suggestedAtomType.rawValue,
                destinationPath: "\(suggestedAtomType.displayName)",
                rationale: "No existing atom, cluster, or thinkspace has enough evidence yet. Creating a standalone \(suggestedAtomType.displayName.lowercased()) keeps the capture available without forcing a weak placement."
            )
        )

        let deduped = dedupeRecommendations(recommendations)
        let reranked = await rerankIfNeeded(text: text, title: title, recommendations: deduped)

        return RoutingResult(
            title: title,
            bundle: InboxRecommendationBundle(
                title: title,
                recommendations: reranked
            )
        )
    }

    private func buildThinkspaceCandidates(
        from thinkspaceAtoms: [Atom],
        queryTokens: Set<String>,
        searchResults: [HybridSearchEngine.SearchResult],
        memberships: [String: [String]]
    ) -> [ThinkspaceCandidate] {
        let resultPairs: [(String, HybridSearchEngine.SearchResult)] = searchResults.compactMap { result in
            guard let uuid = result.entityUUID else { return nil }
            return (uuid, result)
        }
        let resultsByUUID = Dictionary(uniqueKeysWithValues: resultPairs)

        return thinkspaceAtoms.compactMap { atom -> ThinkspaceCandidate? in
            guard let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else { return nil }
            let lexicalScore = textMatchScore(queryTokens: queryTokens, candidate: "\(metadata.name) \(atom.title ?? "")")
            let supportingResults = memberships
                .filter { $0.value.contains(atom.uuid) }
                .compactMap { resultsByUUID[$0.key]?.combinedScore }
            let membershipScore = supportingResults.isEmpty ? 0 : supportingResults.reduce(0, +) / Double(supportingResults.count)
            let recentBoost = recencyBoost(for: metadata.lastOpened)
            let finalScore = clamp01((membershipScore * 0.56) + (lexicalScore * 0.28) + (recentBoost * 0.16))

            return ThinkspaceCandidate(
                id: atom.uuid,
                name: metadata.name,
                metadata: metadata,
                lastOpened: metadata.lastOpened,
                score: finalScore,
                lexicalScore: lexicalScore,
                membershipScore: membershipScore,
                recentBoost: recentBoost
            )
        }
        .filter { $0.score > 0.18 }
        .sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.0001 {
                return lhs.score > rhs.score
            }
            return lhs.lastOpened > rhs.lastOpened
        }
    }

    private func buildClusterCandidates(
        from thinkspaceAtoms: [Atom],
        queryTokens: Set<String>,
        searchResults: [HybridSearchEngine.SearchResult],
        graphBoosts: [String: Double]
    ) -> [ClusterCandidate] {
        let resultPairs: [(String, HybridSearchEngine.SearchResult)] = searchResults.compactMap { result in
            guard let uuid = result.entityUUID else { return nil }
            return (uuid, result)
        }
        let searchByUUID = Dictionary(uniqueKeysWithValues: resultPairs)

        var candidates: [ClusterCandidate] = []

        for atom in thinkspaceAtoms {
            guard let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else { continue }
            let thinkspaceLexical = textMatchScore(queryTokens: queryTokens, candidate: metadata.name)
            let recentBoost = recencyBoost(for: metadata.lastOpened)

            for cluster in metadata.clusters {
                let memberUUIDs = cluster.blockUUIDs
                let clusterCandidateText = [
                    cluster.name,
                    cluster.intent ?? "",
                    metadata.name
                ].joined(separator: " ")

                let lexicalScore = textMatchScore(queryTokens: queryTokens, candidate: clusterCandidateText)
                let memberScores = memberUUIDs.compactMap { searchByUUID[$0]?.combinedScore }
                let memberScore = memberScores.isEmpty ? 0 : memberScores.reduce(0, +) / Double(memberScores.count)
                let graphScores = memberUUIDs.compactMap { graphBoosts[$0] }
                let graphScore = graphScores.isEmpty ? 0 : graphScores.reduce(0, +) / Double(graphScores.count)
                let densityBoost = min(Double(memberUUIDs.count) / 12.0, 1.0) * 0.05
                let finalScore = clamp01(
                    (memberScore * 0.40) +
                    (lexicalScore * 0.27) +
                    (thinkspaceLexical * 0.15) +
                    (graphScore * 0.13) +
                    (recentBoost * 0.05) +
                    densityBoost
                )

                let relatedAtomUUIDs = Array(
                    Set(
                        memberUUIDs.filter { searchByUUID[$0] != nil } +
                        memberUUIDs.filter { graphBoosts[$0] != nil }
                    )
                )

                candidates.append(
                    ClusterCandidate(
                        thinkspaceId: atom.uuid,
                        thinkspaceName: metadata.name,
                        thinkspaceMetadata: metadata,
                        cluster: cluster,
                        score: finalScore,
                        lexicalScore: lexicalScore,
                        memberScore: memberScore,
                        graphScore: graphScore,
                        recentBoost: recentBoost,
                        relatedAtomUUIDs: relatedAtomUUIDs
                    )
                )
            }
        }

        return candidates
            .filter { $0.score > 0.22 }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score > rhs.score
                }
                return lhs.cluster.name < rhs.cluster.name
            }
    }

    private func bestMergeRecommendation(
        title: String,
        text: String,
        suggestedAtomType: AtomType,
        searchResults: [HybridSearchEngine.SearchResult],
        atomsByUUID: [String: Atom],
        graphBoosts: [String: Double],
        excludedUUIDs: Set<String>
    ) -> InboxRecommendation? {
        let titleTokens = normalizedTokens(from: title)

        let candidates = searchResults.compactMap { result -> InboxRecommendation? in
            guard let uuid = result.entityUUID,
                  !excludedUUIDs.contains(uuid),
                  let atom = atomsByUUID[uuid],
                  atom.type != .thinkspace else {
                return nil
            }

            let titleScore = textMatchScore(queryTokens: titleTokens, candidate: atom.title ?? result.title)
            let exactBoost = normalizedPhrase(atom.title ?? result.title) == normalizedPhrase(title) ? 0.18 : 0
            let graphBoost = graphBoosts[uuid] ?? 0
            let confidence = clamp01((result.combinedScore * 0.68) + (titleScore * 0.18) + exactBoost + (graphBoost * 0.16))

            return InboxRecommendation(
                kind: .mergeAtom,
                confidence: confidence,
                suggestedAtomType: suggestedAtomType.rawValue,
                destinationPath: atom.title ?? result.title,
                rationale: "This capture is closest to \(atom.title ?? result.title) and shares enough conceptual overlap to merge without losing structure.",
                mergeTargetUuid: uuid,
                mergeTargetTitle: atom.title ?? result.title,
                mergeTargetType: atom.type.rawValue,
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
                        InboxPlacementOperation(kind: .mergeIntoAtom, description: "Merge into \(atom.title ?? result.title)")
                    ],
                    summary: "Merge \(title) into \(atom.title ?? result.title)"
                )
            )
        }

        return candidates.sorted { $0.confidence > $1.confidence }.first
    }

    private func dedupeRecommendations(_ recommendations: [InboxRecommendation]) -> [InboxRecommendation] {
        var seen = Set<String>()
        var deduped: [InboxRecommendation] = []

        for recommendation in recommendations.sorted(by: { $0.confidence > $1.confidence }) {
            let key = "\(recommendation.kind.rawValue)|\(recommendation.destinationPath)|\(recommendation.mergeTargetUuid ?? "")|\(recommendation.clusterId ?? "")"
            if seen.insert(key).inserted {
                deduped.append(recommendation)
            }
        }

        return Array(deduped.prefix(5))
    }

    private func rerankIfNeeded(
        text: String,
        title: String,
        recommendations: [InboxRecommendation]
    ) async -> [InboxRecommendation] {
        let sorted = recommendations.sorted { $0.confidence > $1.confidence }
        // Only re-rank when there's a *genuinely* ambiguous top, with at least three
        // viable options. The previous threshold (gap < 0.08, count > 1) fired on
        // nearly every classification, multiplying LLM cost by 88× during a
        // bulk inbox load.
        guard sorted.count >= 3 else { return sorted }
        guard abs(sorted[0].confidence - sorted[1].confidence) < 0.05 else { return sorted }

        let topCandidates = Array(sorted.prefix(3))
        let options = topCandidates.enumerated().map { index, recommendation in
            "\(index + 1). id=\(recommendation.id) route=\(recommendation.kind.rawValue) destination=\(recommendation.destinationPath) rationale=\(recommendation.rationale)"
        }.joined(separator: "\n")

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: """
                Choose the single best routing option for this inbox capture. Return ONLY the chosen id.

                Capture title: \(title)
                Capture text:
                \(String(text.prefix(1200)))

                Options:
                \(options)
                """,
                model: flashModel,
                maxTokens: 24,
                temperature: 0.0
            )

            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let chosen = topCandidates.first(where: { trimmed.contains($0.id) }) else {
                return sorted
            }

            let boosted = recommendations.map { recommendation -> InboxRecommendation in
                guard recommendation.id == chosen.id else { return recommendation }
                return InboxRecommendation(
                    id: recommendation.id,
                    kind: recommendation.kind,
                    confidence: clamp01(recommendation.confidence + 0.04),
                    suggestedAtomType: recommendation.suggestedAtomType,
                    destinationPath: recommendation.destinationPath,
                    rationale: recommendation.rationale,
                    mergeTargetUuid: recommendation.mergeTargetUuid,
                    mergeTargetTitle: recommendation.mergeTargetTitle,
                    mergeTargetType: recommendation.mergeTargetType,
                    thinkspaceId: recommendation.thinkspaceId,
                    thinkspaceName: recommendation.thinkspaceName,
                    clusterId: recommendation.clusterId,
                    clusterName: recommendation.clusterName,
                    placementPlan: recommendation.placementPlan
                )
            }
            return boosted.sorted { $0.confidence > $1.confidence }
        } catch {
            return sorted
        }
    }

    private func buildGraphBoosts(
        searchResults: [HybridSearchEngine.SearchResult],
        excludedUUIDs: Set<String>
    ) async -> [String: Double] {
        var boosts: [String: Double] = [:]
        let engine = GraphQueryEngine()

        for result in searchResults.prefix(3) {
            guard let uuid = result.entityUUID,
                  !excludedUUIDs.contains(uuid) else {
                continue
            }

            let neighbors = (try? await engine.getNeighbors(of: uuid, limit: 8)) ?? []
            for neighbor in neighbors {
                guard !excludedUUIDs.contains(neighbor.node.atomUUID) else { continue }
                boosts[neighbor.node.atomUUID] = max(boosts[neighbor.node.atomUUID] ?? 0, neighbor.weight * 0.18)
            }
        }

        return boosts
    }

    private func existingClusterRationale(_ candidate: ClusterCandidate) -> String {
        if let intent = candidate.cluster.intent, !intent.isEmpty {
            return "\(candidate.cluster.name) already collects material around “\(intent)”, and this capture matches that cluster better than the surrounding thinkspace."
        }
        return "\(candidate.cluster.name) is the strongest local fit inside \(candidate.thinkspaceName), with both semantic similarity and cluster structure pointing to it."
    }

    private func newClusterConfidence(bestThinkspace: ThinkspaceCandidate, bestExistingCluster: ClusterCandidate?) -> Double {
        let existingClusterPenalty = (bestExistingCluster?.score ?? 0) * 0.25
        return clamp01((bestThinkspace.score * 0.82) - existingClusterPenalty + 0.12)
    }

    private func shouldCreateThinkspace(
        title: String,
        text: String,
        bestMergeScore: Double,
        bestThinkspaceScore: Double
    ) -> Bool {
        let titleWordCount = title.split(whereSeparator: \.isWhitespace).count
        let broadSignals = [
            "philosophy", "theory", "framework", "system", "world", "vision",
            "research area", "archive", "domain", "study", "field"
        ]
        let lower = "\(title) \(text)".lowercased()
        let hasBroadSignal = broadSignals.contains { lower.contains($0) }
        let isCompactTopic = titleWordCount <= 4

        return bestMergeScore < 0.58 &&
            bestThinkspaceScore < 0.36 &&
            (hasBroadSignal || isCompactTopic || text.count > 220)
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

    private func suggestedThinkspaceName(from title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "New Thinkspace" : cleaned.capitalized
    }

    private func suggestAtomType(text: String) -> AtomType {
        let lower = text.lowercased()
        if ["article", "study", "paper", "source", "read"].contains(where: { lower.contains($0) }) {
            return .research
        }
        if ["todo", "task", "deadline", "follow up", "schedule"].contains(where: { lower.contains($0) }) {
            return .task
        }
        if ["idea", "what if", "concept", "thesis"].contains(where: { lower.contains($0) }) {
            return .idea
        }
        if lower.count < 80 {
            return .idea
        }
        return .connection
    }

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
        let overlapScore = Double(overlap.count) / Double(max(queryTokens.count, candidateTokens.count))
        let firstQueryTerm = queryTokens.sorted().first ?? ""
        let phraseBoost = !firstQueryTerm.isEmpty && normalizedPhrase(candidate).contains(firstQueryTerm) ? 0.12 : 0
        return clamp01(overlapScore + phraseBoost)
    }

    private func normalizedPhrase(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func recencyBoost(for date: Date) -> Double {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 2 { return 0.20 }
        if days <= 7 { return 0.14 }
        if days <= 30 { return 0.08 }
        return 0.02
    }

    private func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
