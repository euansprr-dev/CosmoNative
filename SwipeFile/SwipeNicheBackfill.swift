// CosmoOS/SwipeFile/SwipeNicheBackfill.swift
// One-time (self-healing) consolidation of the pre-canonical niche library:
// 330 swipes accumulated ~140 free-text niche fragments ("Real Estate
// Investing" / "Real Estate Investment" / "Airbnb Real Estate Investing"…)
// before NicheRegistry existed. This pass clusters the raw labels into core
// niches with ONE Sonnet call, seeds the registry (raw labels become
// aliases), and rewrites every swipe to its canonical value. The gate is
// data-derived — a swipe whose niche resolves deterministically needs no
// model call, so once the library is canonical the pass is a cheap no-op.
// Same launch-drain grammar as SwipeTitleBackfill.
// July 2026

import Foundation
import GRDB

@MainActor
enum SwipeNicheBackfill {

    /// One premium clustering call is the budget — same tier as the insight
    /// pass, because the seed taxonomy shapes every future classification.
    static let consolidationTier: AgentModelTier = .sonnet5

    /// Below this many novel labels, skip the clustering call and let the
    /// registry resolve them one by one (create-on-miss) — a model call to
    /// cluster three labels is waste.
    static let clusteringMinimum = 8

    private static var hasRunThisLaunch = false

    static func runBackfillPassIfNeeded() async {
        guard !hasRunThisLaunch else { return }
        hasRunThisLaunch = true

        // Raw niche labels with usage counts across the swipe library.
        let labelCounts = await collectNicheLabelCounts()
        guard !labelCounts.isEmpty else { return }

        let registry = NicheRegistry.shared
        let niches = await registry.currentNiches()
        let canonicalKeys = Set(niches.map { NicheMatcher.normalizeKey($0.value) })

        // Partition: already-canonical labels need nothing; labels the matcher
        // resolves deterministically need only a rewrite; novel labels need
        // the clustering call (or individual creation when there are few).
        var mapping: [String: String] = [:]   // normalized raw key → canonical value
        var novel: [(label: String, count: Int)] = []

        for (label, count) in labelCounts.sorted(by: { $0.value > $1.value }) {
            let key = NicheMatcher.normalizeKey(label)
            if canonicalKeys.contains(key) { continue }
            switch NicheMatcher.bestMatch(raw: label, in: niches) {
            case .exact(let i), .alias(let i), .fuzzy(let i, _):
                mapping[key] = niches[i].value
            case .none:
                novel.append((label, count))
            }
        }

        if novel.count >= clusteringMinimum {
            let clusters = await clusterLabels(novel, existingCanonicals: niches.map(\.value))
            if clusters.isEmpty {
                // Model call failed — novel labels stay untouched and retry
                // on a future launch (the gate is data-derived); the
                // deterministic mapping below still applies.
                print("SwipeNicheBackfill: Clustering call failed; novel labels deferred to next launch")
            } else {
                var assigned = Set<String>()
                for cluster in clusters {
                    let usage = cluster.rawLabels.reduce(0) { $0 + (labelCounts[$1] ?? 0) }
                    guard let canonical = await registry.seed(
                        value: cluster.canonical,
                        aliases: cluster.rawLabels,
                        usageCount: usage
                    ) else { continue }
                    for raw in cluster.rawLabels {
                        mapping[NicheMatcher.normalizeKey(raw)] = canonical
                        assigned.insert(NicheMatcher.normalizeKey(raw))
                    }
                }
                // Labels the model dropped fall back to individual resolution.
                for (label, _) in novel where !assigned.contains(NicheMatcher.normalizeKey(label)) {
                    let canonical = await registry.resolve(label)
                    mapping[NicheMatcher.normalizeKey(label)] = canonical
                }
            }
        } else {
            for (label, _) in novel {
                let canonical = await registry.resolve(label)
                mapping[NicheMatcher.normalizeKey(label)] = canonical
            }
        }

        guard !mapping.isEmpty else { return }
        await registry.rewriteSwipes(mapping: mapping)
        print("SwipeNicheBackfill: Consolidated \(mapping.count) raw niche label(s)")
    }

    // MARK: - Label collection

    private static func collectNicheLabelCounts() async -> [String: Int] {
        let atoms = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(sql: "structured LIKE ?", arguments: ["%\"niche\":%"])
                .fetchAll(db)
        }) ?? []

        var counts: [String: Int] = [:]
        for atom in atoms {
            guard atom.isSwipeFileAtom,
                  let niche = atom.swipeAnalysis?.niche?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !niche.isEmpty
            else { continue }
            counts[niche, default: 0] += 1
        }
        return counts
    }

    // MARK: - Clustering call

    struct NicheCluster: Codable {
        let canonical: String
        let rawLabels: [String]
    }

    private struct ClusterResponse: Codable {
        let niches: [NicheCluster]
    }

    /// One Sonnet call: cluster the novel raw labels into core niches. The
    /// model does the semantics; everything downstream is deterministic.
    /// Internal seam is `parseClusterResponse` — directly testable.
    private static func clusterLabels(
        _ labels: [(label: String, count: Int)],
        existingCanonicals: [String]
    ) async -> [NicheCluster] {
        let labelLines = labels
            .map { "- \"\($0.label)\" (\($0.count))" }
            .joined(separator: "\n")
        let existingLine = existingCanonicals.isEmpty
            ? ""
            : "\nEXISTING CORE NICHES (reuse these exact names whenever a cluster belongs to one): \(existingCanonicals.joined(separator: ", "))\n"

        let prompt = """
        You are consolidating a fragmented niche taxonomy for a swipe-file study tool. Below are raw niche labels from classified social-media content, with usage counts. Cluster them into CORE niches.

        Rules:
        - A core niche is a vertical someone builds an audience in ("Fitness", "Content Creation", "Real Estate Wholesaling") — never a combo ("X & Y", "X / Y"), never a hook-level sub-topic.
        - Distinct business models stay distinct: "Real Estate Wholesaling" and "Real Estate Investing" are DIFFERENT core niches; "Airbnb Real Estate Investing" and "Real Estate Investing - Airbnb" are the SAME one.
        - Prefer broad verticals; fold sub-topics and combos into the vertical the creator's audience follows them for.
        - Aim for roughly 10–20 core niches across this whole list.
        - Every raw label maps to exactly one core niche. Do not drop labels.
        \(existingLine)
        Raw labels:
        \(labelLines)

        Return ONLY valid JSON, no markdown fences:
        {"niches": [{"canonical": "Real Estate Investing", "rawLabels": ["Real Estate Investing", "Real Estate Investment"]}]}
        """

        do {
            // reasoning OFF: structured JSON extraction — Sonnet 5's default
            // adaptive thinking otherwise eats into the shared token budget.
            let raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: consolidationTier,
                maxTokens: 8000,
                disableReasoning: true
            )
            return parseClusterResponse(raw, validLabels: labels.map(\.label))
        } catch {
            print("SwipeNicheBackfill: Clustering call failed: \(error)")
            return []
        }
    }

    /// Parse + validate: canonical names are cleaned, raw labels are matched
    /// back to the submitted set (normalized), duplicates keep first assignment.
    static func parseClusterResponse(_ raw: String, validLabels: [String]) -> [NicheCluster] {
        var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonStr.hasPrefix("```") {
            if let firstNewline = jsonStr.firstIndex(of: "\n") {
                jsonStr = String(jsonStr[jsonStr.index(after: firstNewline)...])
            }
            if jsonStr.hasSuffix("```") { jsonStr = String(jsonStr.dropLast(3)) }
            jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = jsonStr.data(using: .utf8),
              let response = try? JSONDecoder().decode(ClusterResponse.self, from: data)
        else { return [] }

        let labelByKey = Dictionary(
            validLabels.map { (NicheMatcher.normalizeKey($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var assigned = Set<String>()
        var clusters: [NicheCluster] = []
        for cluster in response.niches {
            let canonical = NicheMatcher.cleanedCanonicalLabel(from: cluster.canonical)
            guard !canonical.isEmpty else { continue }
            var members: [String] = []
            for raw in cluster.rawLabels {
                let key = NicheMatcher.normalizeKey(raw)
                guard let original = labelByKey[key], !assigned.contains(key) else { continue }
                assigned.insert(key)
                members.append(original)
            }
            guard !members.isEmpty else { continue }
            clusters.append(NicheCluster(canonical: canonical, rawLabels: members))
        }
        return clusters
    }
}
