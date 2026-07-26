// CosmoOS/UI/Ideas/IdeasDeskEngine.swift
// The Desk's curation engine (July 2026 Ideas reinvention).
// Turns the flat idea corpus into the three desk lanes — committed work,
// ranked proposals per client, and the unassigned sparks tray — with a
// deterministic score and a template why-line per proposal. Zero LLM, no
// randomness, total ordering (the Material-rail doctrine): the same library
// always deals the same hand, and a card only moves when the user moves it.

import Foundation

struct IdeasDeskEngine {

    // MARK: - Output shapes

    /// A ranked candidate with the one-line reason it surfaced.
    struct Proposal: Identifiable, Sendable {
        let item: IdeaGalleryItem
        let score: Double
        let whyLine: String
        var id: String { item.atomUUID }
    }

    /// A client's state of play — the digest that rides their block header.
    struct ClientDigest: Sendable, Equatable {
        var ready = 0
        var developing = 0
        var total = 0
    }

    /// The dealt desk. Lanes are mutually exclusive: an idea is committed,
    /// unassigned, or a proposal — never two at once.
    struct Desk: Sendable {
        /// Committed work: pinned or carrying an open development session.
        /// Scheduled first (soonest day leads), then pins by recency.
        var upNext: [IdeaGalleryItem] = []
        /// Unassigned captures awaiting triage, newest first.
        var sparks: [IdeaGalleryItem] = []
        /// clientUUID → ranked candidates (uncapped — the view cuts to fit).
        var proposalsByClient: [String: [Proposal]] = [:]
        /// clientUUID → live pipeline counts (up-next members included).
        var digests: [String: ClientDigest] = [:]

        static let empty = Desk()
    }

    // MARK: - Scoring weights (the plan's table — change tests when changed)

    private enum Weight {
        static let ready = 3.0
        static let developing = 1.5
        static let hooks = 1.0
        static let outline = 1.0
        static let inspiration = 0.5
        static let substance = 0.5
        static let touchedTwoDays = 1.0
        static let touchedWeek = 0.5
        static let staleDecay = -0.5
    }

    private static let staleAfterDays = 60.0
    private static let quietAfterDays = 21.0

    // MARK: - Deal

    /// Deal the desk from the live (non-activated) idea set.
    /// - Parameters:
    ///   - inspiration: uuids whose linked swipe thumb actually resolves.
    ///   - knownClientIds: real client profiles — orphaned clientUUIDs fall
    ///     into the sparks tray, mirroring the boards' Unassigned rule.
    ///   - now: injected for tests; scoring is pure in it.
    static func makeDesk(
        ideas: [IdeaGalleryItem],
        scheduledDays: [String: Date],
        inspiration: Set<String>,
        knownClientIds: Set<String>,
        now: Date = .now
    ) -> Desk {
        var desk = Desk()
        var scheduled: [IdeaGalleryItem] = []
        var pinnedOnly: [IdeaGalleryItem] = []
        var candidates: [IdeaGalleryItem] = []

        for idea in ideas {
            let assignedClient = idea.clientUUID.flatMap { knownClientIds.contains($0) ? $0 : nil }
            if scheduledDays[idea.atomUUID] != nil {
                scheduled.append(idea)
            } else if idea.isPinned {
                pinnedOnly.append(idea)
            } else if assignedClient == nil {
                desk.sparks.append(idea)
            } else {
                candidates.append(idea)
            }
            if let assignedClient {
                var digest = desk.digests[assignedClient] ?? ClientDigest()
                digest.total += 1
                if idea.status == .ready { digest.ready += 1 }
                if idea.status == .developing { digest.developing += 1 }
                desk.digests[assignedClient] = digest
            }
        }

        scheduled.sort {
            let a = scheduledDays[$0.atomUUID] ?? .distantFuture
            let b = scheduledDays[$1.atomUUID] ?? .distantFuture
            if a != b { return a < b }
            return laterFirst($0, $1)
        }
        pinnedOnly.sort {
            let a = $0.pinnedAt ?? $0.updatedAt
            let b = $1.pinnedAt ?? $1.updatedAt
            if a != b { return a > b }
            return $0.atomUUID < $1.atomUUID
        }
        desk.upNext = scheduled + pinnedOnly

        desk.sparks.sort(by: laterFirst)

        let proposals = candidates
            .map { Proposal(item: $0, score: score(for: $0, inspiration: inspiration, now: now), whyLine: whyLine(for: $0, inspiration: inspiration, now: now)) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.item.updatedAt != $1.item.updatedAt { return $0.item.updatedAt > $1.item.updatedAt }
                return $0.item.atomUUID < $1.item.atomUUID
            }
        desk.proposalsByClient = Dictionary(grouping: proposals) { $0.item.clientUUID ?? "" }

        return desk
    }

    // MARK: - Score

    static func score(for idea: IdeaGalleryItem, inspiration: Set<String>, now: Date = .now) -> Double {
        var score = 0.0
        switch idea.status {
        case .ready: score += Weight.ready
        case .developing: score += Weight.developing
        default: break
        }
        if !idea.hooks.isEmpty { score += Weight.hooks }
        if !idea.outline.isEmpty { score += Weight.outline }
        if inspiration.contains(idea.atomUUID) { score += Weight.inspiration }
        if hasSubstance(idea) { score += Weight.substance }

        if let touched = daysSince(idea.updatedAt, now: now) {
            if touched <= 2 {
                score += Weight.touchedTwoDays
            } else if touched <= 7 {
                score += Weight.touchedWeek
            }
            if touched > staleAfterDays { score += Weight.staleDecay }
        }
        return score
    }

    // MARK: - Why-line

    /// The one-line reason a card surfaced — deterministic template prose:
    /// `[stage] · [up to 2 substance signals] · [quiet note when room]`.
    static func whyLine(for idea: IdeaGalleryItem, inspiration: Set<String>, now: Date = .now) -> String {
        var segments = [stageSegment(for: idea, now: now)]

        var substance: [String] = []
        if !idea.hooks.isEmpty {
            substance.append(idea.hooks.count == 1 ? "1 hook" : "\(idea.hooks.count) hooks")
        }
        if !idea.outline.isEmpty { substance.append("outline set") }
        if idea.hasResearch { substance.append("researched") }
        if inspiration.contains(idea.atomUUID) { substance.append("from a saved swipe") }
        segments.append(contentsOf: substance.prefix(2))

        // Sparks admit their staleness too ("Spark · quiet for 8w") — the
        // fresh-capture stages can never trip this (updated ≥ created), so
        // no status gate is needed.
        if substance.count < 2,
           let quiet = daysSince(idea.updatedAt, now: now),
           quiet > quietAfterDays {
            segments.append("quiet for \(max(1, Int(quiet / 7)))w")
        }
        return segments.joined(separator: " · ")
    }

    private static func stageSegment(for idea: IdeaGalleryItem, now: Date) -> String {
        switch idea.status {
        case .ready: return "Ready to write"
        case .developing: return "In development"
        default:
            guard let age = daysSince(idea.createdAt, now: now) else { return "Spark" }
            if age < 1 { return "Captured today" }
            if age < 2 { return "Captured yesterday" }
            if age <= 7 { return "New this week" }
            return "Spark"
        }
    }

    // MARK: - Helpers

    private static func hasSubstance(_ idea: IdeaGalleryItem) -> Bool {
        let context = idea.context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = idea.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !context.isEmpty || !body.isEmpty
    }

    private static func daysSince(_ iso: String, now: Date) -> Double? {
        guard let date = ISO8601.date(from: iso) else { return nil }
        return now.timeIntervalSince(date) / 86_400
    }

    /// Newest-first by updatedAt with a uuid tie-break — the engine's one
    /// recency comparator, total so the deal is reproducible.
    private static func laterFirst(_ a: IdeaGalleryItem, _ b: IdeaGalleryItem) -> Bool {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.atomUUID < b.atomUUID
    }
}
