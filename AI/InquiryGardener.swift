// CosmoOS/AI/InquiryGardener.swift
// The Gardener: the missing lifecycle mechanic for the question tree. Nesting
// is a CLAIM — "answering this child materially advances its parent" — and
// claims drift as research grows. The Gardener re-evaluates the whole topic's
// structure at natural seams (crystallization, opening the dossier) from
// measurable signals, and PROPOSES — never acts:
//   · promote  — a child has outgrown its parent (mass + drift, or gravity)
//   · merge    — two questions have converged on the same territory
//   · graduate — a root question has reached topic scale; offer its own Deep Dive
// Every decision is remembered (InquiryGardenerDecisionStore) so nothing is
// ever re-proposed. Signals are pure and unit-tested; thresholds are
// deliberately conservative — a quiet gardener is trusted, a chatty one is
// muted.

import Foundation

// MARK: - Proposal

struct InquiryGardenerProposal: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case promote
        case merge
        case graduate
    }

    /// Stable fingerprint: one ruling per (kind, subject, target) forever.
    var key: String
    var kind: Kind
    var questionUUID: String
    var questionTitle: String
    /// merge: the surviving question. promote: the current parent (context only).
    var targetUUID: String?
    var targetTitle: String?
    /// One calm human sentence: why the garden wants tending here.
    var reason: String

    var id: String { key }

    var actionLabel: String {
        switch kind {
        case .promote: return "Make top-level"
        case .merge: return "Merge"
        case .graduate: return "Grow into a topic"
        }
    }
}

// MARK: - Pure signals (unit-tested, no database, no model)

enum InquiryGardenerSignals {

    struct QuestionFacts: Sendable {
        var uuid: String
        var title: String
        var parentUUID: String?
        /// Extracts routed directly to this question.
        var directExtracts: Int
        /// Concept names tagged on its direct extracts.
        var concepts: Set<String>
        var isArchived: Bool = false
    }

    /// Tunables — one place, so taste changes don't hunt through logic.
    enum Thresholds {
        static let promoteMinSubtree = 8
        static let promoteSparseConceptsMinSubtree = 12
        static let promoteDriftOverlapMax = 0.34
        static let gravityMinChildren = 2
        static let gravityMinSubtree = 10
        static let mergeTitleOverlapMin = 0.75
        static let graduateMinChildren = 3
        static let graduateMinSubtree = 40
        static let maxProposalsPerPass = 3
    }

    static func proposals(facts: [QuestionFacts]) -> [InquiryGardenerProposal] {
        let live = facts.filter { !$0.isArchived }
        let byUUID = Dictionary(uniqueKeysWithValues: live.map { ($0.uuid, $0) })
        var childrenOf: [String: [QuestionFacts]] = [:]
        for fact in live {
            if let parent = fact.parentUUID {
                childrenOf[parent, default: []].append(fact)
            }
        }

        var subtreeCache: [String: Int] = [:]
        func subtreeTotal(_ uuid: String) -> Int {
            if let cached = subtreeCache[uuid] { return cached }
            let own = byUUID[uuid]?.directExtracts ?? 0
            let total = own + (childrenOf[uuid] ?? []).reduce(0) { $0 + subtreeTotal($1.uuid) }
            subtreeCache[uuid] = total
            return total
        }

        // Graduation outranks promotion: a topic-scale subtree moves TOGETHER
        // into its own Deep Dive — promoting its children out first would
        // shred the very structure that earned graduation.
        let graduationProposals = graduations(live: live, childrenOf: childrenOf, subtreeTotal: subtreeTotal)
        let graduatingRoots = Set(graduationProposals.map(\.questionUUID))

        var out: [InquiryGardenerProposal] = graduationProposals
        out += promotions(live: live, byUUID: byUUID, childrenOf: childrenOf, subtreeTotal: subtreeTotal)
            .filter { proposal in
                !hasAncestor(proposal.questionUUID, in: graduatingRoots, byUUID: byUUID)
            }
        out += merges(live: live, byUUID: byUUID, subtreeTotal: subtreeTotal)
        return Array(out.prefix(Thresholds.maxProposalsPerPass))
    }

    /// True when any ancestor of `uuid` (or itself) is in `roots`.
    private static func hasAncestor(_ uuid: String, in roots: Set<String>, byUUID: [String: QuestionFacts]) -> Bool {
        guard !roots.isEmpty else { return false }
        var cursor: String? = uuid
        var hops = 0
        while let current = cursor, hops < 32 {
            if roots.contains(current) { return true }
            cursor = byUUID[current]?.parentUUID
            hops += 1
        }
        return false
    }

    // MARK: Promotion — mass + drift, or gravity

    private static func promotions(
        live: [QuestionFacts],
        byUUID: [String: QuestionFacts],
        childrenOf: [String: [QuestionFacts]],
        subtreeTotal: (String) -> Int
    ) -> [InquiryGardenerProposal] {
        var out: [InquiryGardenerProposal] = []
        for fact in live {
            guard let parentUUID = fact.parentUUID,
                  let parent = byUUID[parentUUID] else { continue }
            let mass = subtreeTotal(fact.uuid)
            let childCount = (childrenOf[fact.uuid] ?? []).count

            // Gravity: it has become a frame of its own.
            let gravity = childCount >= Thresholds.gravityMinChildren
                && mass >= Thresholds.gravityMinSubtree

            // Mass + drift: big enough to rival the parent's own work, and
            // its concepts no longer feed the parent's territory.
            var massAndDrift = false
            if mass >= Thresholds.promoteMinSubtree && mass >= max(6, parent.directExtracts) {
                if fact.concepts.count >= 2 && parent.concepts.count >= 2 {
                    massAndDrift = conceptOverlap(fact.concepts, parent.concepts) < Thresholds.promoteDriftOverlapMax
                } else {
                    // Concept data too sparse to judge drift — demand more mass.
                    massAndDrift = mass >= Thresholds.promoteSparseConceptsMinSubtree
                }
            }

            guard gravity || massAndDrift else { continue }
            let noteWord = mass == 1 ? "note" : "notes"
            let reason: String
            if gravity {
                reason = "“\(fact.title)” has grown \(childCount) branches and \(mass) \(noteWord) of its own — it reads as its own line of inquiry now."
            } else {
                reason = "“\(fact.title)” has \(mass) \(noteWord) and has drifted from “\(parent.title)” — its findings no longer feed that answer."
            }
            out.append(InquiryGardenerProposal(
                key: "promote:\(fact.uuid)",
                kind: .promote,
                questionUUID: fact.uuid,
                questionTitle: fact.title,
                targetUUID: parentUUID,
                targetTitle: parent.title,
                reason: reason
            ))
        }
        return out.sorted { subtreeTotal($0.questionUUID) > subtreeTotal($1.questionUUID) }
    }

    // MARK: Merge — two questions on the same territory

    private static func merges(
        live: [QuestionFacts],
        byUUID: [String: QuestionFacts],
        subtreeTotal: (String) -> Int
    ) -> [InquiryGardenerProposal] {
        var out: [InquiryGardenerProposal] = []
        var claimed: Set<String> = []
        for i in live.indices {
            for j in live.indices where j > i {
                let a = live[i], b = live[j]
                guard !claimed.contains(a.uuid), !claimed.contains(b.uuid) else { continue }
                guard !isAncestor(a.uuid, of: b.uuid, byUUID: byUUID),
                      !isAncestor(b.uuid, of: a.uuid, byUUID: byUUID) else { continue }
                guard titleOverlap(a.title, b.title) >= Thresholds.mergeTitleOverlapMin else { continue }
                let survivor = subtreeTotal(a.uuid) >= subtreeTotal(b.uuid) ? a : b
                let folded = survivor.uuid == a.uuid ? b : a
                claimed.insert(a.uuid); claimed.insert(b.uuid)
                out.append(InquiryGardenerProposal(
                    key: "merge:\(min(a.uuid, b.uuid)):\(max(a.uuid, b.uuid))",
                    kind: .merge,
                    questionUUID: folded.uuid,
                    questionTitle: folded.title,
                    targetUUID: survivor.uuid,
                    targetTitle: survivor.title,
                    reason: "“\(folded.title)” and “\(survivor.title)” cover the same ground — fold them into one thread?"
                ))
            }
        }
        return out
    }

    // MARK: Graduation — topic scale

    private static func graduations(
        live: [QuestionFacts],
        childrenOf: [String: [QuestionFacts]],
        subtreeTotal: (String) -> Int
    ) -> [InquiryGardenerProposal] {
        live.compactMap { fact in
            guard fact.parentUUID == nil,
                  (childrenOf[fact.uuid] ?? []).count >= Thresholds.graduateMinChildren,
                  subtreeTotal(fact.uuid) >= Thresholds.graduateMinSubtree else { return nil }
            return InquiryGardenerProposal(
                key: "graduate:\(fact.uuid)",
                kind: .graduate,
                questionUUID: fact.uuid,
                questionTitle: fact.title,
                targetUUID: nil,
                targetTitle: nil,
                reason: "“\(fact.title)” now carries \(subtreeTotal(fact.uuid)) notes across \((childrenOf[fact.uuid] ?? []).count) branches — a whole topic living inside this one. Give it its own Deep Dive?"
            )
        }
    }

    // MARK: Helpers (pure)

    /// Overlap coefficient — |A ∩ B| / min(|A|, |B|). Robust when one side is small.
    static func conceptOverlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        let lowerA = Set(a.map { $0.lowercased() })
        let lowerB = Set(b.map { $0.lowercased() })
        let denominator = min(lowerA.count, lowerB.count)
        guard denominator > 0 else { return 0 }
        return Double(lowerA.intersection(lowerB).count) / Double(denominator)
    }

    /// Jaccard over significant title tokens.
    static func titleOverlap(_ a: String, _ b: String) -> Double {
        let tokensA = significantTokens(a)
        let tokensB = significantTokens(b)
        guard tokensA.count >= 2, tokensB.count >= 2 else { return 0 }
        let union = tokensA.union(tokensB)
        guard !union.isEmpty else { return 0 }
        return Double(tokensA.intersection(tokensB).count) / Double(union.count)
    }

    private static func significantTokens(_ text: String) -> Set<String> {
        let stop: Set<String> = [
            "what", "how", "does", "do", "why", "when", "the", "a", "an", "is", "are",
            "can", "could", "should", "would", "your", "you", "my", "i", "to", "of",
            "in", "for", "and", "or", "with", "become", "becoming", "make", "making"
        ]
        return Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stop.contains($0) }
        )
    }

    private static func isAncestor(_ candidate: String, of uuid: String, byUUID: [String: QuestionFacts]) -> Bool {
        var cursor = byUUID[uuid]?.parentUUID
        var hops = 0
        while let current = cursor, hops < 32 {
            if current == candidate { return true }
            cursor = byUUID[current]?.parentUUID
            hops += 1
        }
        return false
    }
}

// MARK: - The Gardener (orchestrates: facts → signals → memory filter)

@MainActor
final class InquiryGardener {
    static let shared = InquiryGardener()
    private init() {}

    /// Throttle: one pass per topic per interval unless forced (crystallize forces).
    private var lastRunByTopic: [String: Date] = [:]
    private let minimumInterval: TimeInterval = 30 * 60

    /// `preloadedQuestions`/`preloadedExtracts` let a caller that already
    /// fetched the topic's atoms (DeepDiveOverviewViewModel.load) share them
    /// instead of re-running the same queries; nil falls back to self-fetch.
    func review(
        deepDiveUUID: String,
        force: Bool = false,
        preloadedQuestions: [Atom]? = nil,
        preloadedExtracts: [Atom]? = nil
    ) async -> [InquiryGardenerProposal] {
        if !force,
           let last = lastRunByTopic[deepDiveUUID],
           Date().timeIntervalSince(last) < minimumInterval {
            return []
        }
        lastRunByTopic[deepDiveUUID] = Date()

        let questions: [Atom]
        if let preloadedQuestions {
            questions = preloadedQuestions
        } else {
            questions = (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: deepDiveUUID)) ?? []
        }
        let extracts: [Atom]
        if let preloadedExtracts {
            extracts = preloadedExtracts
        } else {
            extracts = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: deepDiveUUID)) ?? []
        }
        guard questions.count >= 2 else { return [] }

        var conceptsByQuestion: [String: Set<String>] = [:]
        var countByQuestion: [String: Int] = [:]
        for extract in extracts {
            guard let meta = extract.extractMetadata,
                  meta.status != .ignored,
                  let questionUUID = meta.parentQuestionUUID else { continue }
            countByQuestion[questionUUID, default: 0] += 1
            for concept in meta.conceptNames ?? [] {
                conceptsByQuestion[questionUUID, default: []].insert(concept)
            }
        }

        let facts = questions.map { question in
            InquiryGardenerSignals.QuestionFacts(
                uuid: question.uuid,
                title: question.title ?? "Untitled question",
                parentUUID: question.questionMetadata?.parentQuestionUUID,
                directExtracts: countByQuestion[question.uuid] ?? 0,
                concepts: conceptsByQuestion[question.uuid] ?? [],
                isArchived: (question.questionMetadata?.status ?? .open) == .archived
            )
        }

        let decided = await InquiryGardenerDecisionStore.shared.decidedKeys(deepDiveUUID: deepDiveUUID)
        return InquiryGardenerSignals.proposals(facts: facts)
            .filter { !decided.contains($0.key) }
    }

    // MARK: - Accepting proposals (shared by dossier + workspace)

    func accept(_ proposal: InquiryGardenerProposal, deepDiveUUID: String) async {
        switch proposal.kind {
        case .promote:
            await InquiryRepository.shared.promoteQuestionToRoot(uuid: proposal.questionUUID)
        case .merge:
            if let survivor = proposal.targetUUID {
                await InquiryRepository.shared.mergeQuestion(
                    proposal.questionUUID,
                    into: survivor,
                    deepDiveUUID: deepDiveUUID
                )
            }
        case .graduate:
            _ = await InquiryRepository.shared.graduateQuestionToDeepDive(
                uuid: proposal.questionUUID,
                fromDeepDiveUUID: deepDiveUUID
            )
        }
        await InquiryGardenerDecisionStore.shared.record(
            key: proposal.key,
            decision: .accepted,
            deepDiveUUID: deepDiveUUID
        )
    }

    func dismiss(_ proposal: InquiryGardenerProposal, deepDiveUUID: String) async {
        await InquiryGardenerDecisionStore.shared.record(
            key: proposal.key,
            decision: .dismissed,
            deepDiveUUID: deepDiveUUID
        )
    }
}
