// CosmoOS/AI/InboxRoutingConfig.swift
// Every threshold the inbox routing engine uses, in one place.
// The engine abstains by default: a capture only gets a suggestion when the
// evidence clears these bars — otherwise it stays honestly "unsorted".
// June 2026 — Inbox Revamp (INBOX_REVAMP_PLAN.md §2)

import Foundation

struct InboxRoutingConfig: Sendable {
    static let shared = InboxRoutingConfig()

    // MARK: - Stage 1 — Merge (near-duplicate territory only)

    /// Hybrid combined score floor for a merge candidate. A merge should feel
    /// like the system caught a duplicate, not like it invented a relationship.
    let mergeMinCombinedScore: Double = 0.80
    /// Title-token overlap required alongside the score floor (waived on exact match).
    let mergeMinTitleOverlap: Double = 0.45

    // MARK: - Stage 2 — Placement (centroid similarity + margin)

    /// Top-1 cluster/thinkspace centroid similarity floor.
    let placementMinScore: Double = 0.55
    /// Required gap between top-1 and top-2 before we commit to a suggestion.
    /// Ambiguity is a reason to abstain, not to guess.
    let placementMinMargin: Double = 0.08
    /// Lexical title overlap is a bonus on top of semantic evidence — never a substitute.
    let lexicalBonusWeight: Double = 0.15
    /// Max member atoms sampled per cluster when computing its centroid.
    let centroidSampleLimit: Int = 24

    // MARK: - Search

    let searchLimit: Int = 12

    // MARK: - Confidence tiers (drive UI tint only — no percentages anywhere)

    /// At or above this, the suggestion pill renders in the confident (accent) tint.
    let confidentTier: Double = 0.70

    // MARK: - Stage 3 — Lazy LLM taxonomy pass

    /// Max unsorted items sent through one batched taxonomy call when the inbox opens.
    let taxonomyPassBatchLimit: Int = 12
    /// Confidence assigned to taxonomy-pass placements (tentative tier by design).
    let taxonomyPassConfidence: Double = 0.62
    /// Example member titles included per cluster when teaching the taxonomy.
    let taxonomyExampleTitles: Int = 3
}

// MARK: - Triageable types

extension AtomType {
    /// Types a capture may merge into or be filed alongside. Everything else —
    /// `.systemEvent` (agent conversation transcripts), `.thinkspace`,
    /// `.clientProfile`, tasks, health/XP telemetry — is never a triage target.
    /// Agent conversations were the worst offender: their bodies contain entire
    /// chat transcripts, which semantically match every capture ever written.
    static let triageable: Set<AtomType> = [.note, .idea, .research, .content, .connection]
}

extension EntityType {
    /// Hybrid-search filter equivalent of `AtomType.triageable`, applied at the
    /// query so system atoms never even reach the candidate pool.
    static let inboxTriageable: [EntityType] = [.note, .idea, .research, .content, .connection]
}
