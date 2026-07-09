// CosmoOS/SwipeFile/Patterns/SwipePatternStore.swift
// The persistent pattern library: recurring, idiosyncratic moves the
// PatternWeaver has noticed across saved swipes. Memberships live HERE, not
// on atoms — pattern churn never touches sync. Persisted as one JSON file in
// Application Support (same grammar as BeatPatternService's vocabulary).
// July 2026

import Foundation
import Observation

// MARK: - Models

enum SwipePatternLevel: String, Codable, Sendable, CaseIterable {
    case hook       // a recurring opening move
    case structure  // a recurring beat sequence
    case voice      // a recurring prose voice
    case topic      // a recurring subject/angle pairing

    var displayName: String {
        switch self {
        case .hook: return "Hook move"
        case .structure: return "Structure"
        case .voice: return "Voice"
        case .topic: return "Angle"
        }
    }
}

struct SwipePatternMember: Codable, Sendable, Equatable, Identifiable {
    var swipeUUID: String
    /// Short quote/paraphrase of how this swipe expresses the move.
    var evidence: String

    var id: String { swipeUUID }
}

struct SwipePattern: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    /// Human name, e.g. "Receipts-first myth bust".
    var name: String
    /// 1–2 sentences: what the move is and why it works.
    var definition: String
    var level: SwipePatternLevel
    /// Canonical beats characterizing the move (structure-level patterns).
    var beatSignature: [String]
    var members: [SwipePatternMember]
    var createdAt: Date
    var lastReinforcedAt: Date

    /// Emerging = the weaver has 2–3 examples; confirmed = 4+.
    var isConfirmed: Bool { members.count >= 4 }

    init(
        id: UUID = UUID(),
        name: String,
        definition: String,
        level: SwipePatternLevel,
        beatSignature: [String] = [],
        members: [SwipePatternMember] = [],
        createdAt: Date = Date(),
        lastReinforcedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.definition = definition
        self.level = level
        self.beatSignature = beatSignature
        self.members = members
        self.createdAt = createdAt
        self.lastReinforcedAt = lastReinforcedAt
    }
}

// MARK: - Store

@MainActor
@Observable
final class SwipePatternStore {
    static let shared = SwipePatternStore()

    private(set) var patterns: [SwipePattern] = []
    /// Swipes analyzed since the last weave — the weaver's work queue.
    private(set) var pendingWeave: [String] = []
    private(set) var lastWeaveAt: Date?
    /// One-time migration over the pre-existing library ran to completion.
    var migrationComplete: Bool = false
    /// Migration ledger: swipes already woven once during migration — a swipe
    /// that matched nothing must never re-enter the migration queue.
    private(set) var migrationSeen: Set<String> = []
    private(set) var isLoaded = false

    private init() {
        load()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var patterns: [SwipePattern]
        var pendingWeave: [String]
        var lastWeaveAt: Date?
        var migrationComplete: Bool
        var migrationSeen: [String]?
    }

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cosmoDir = appSupport.appendingPathComponent("CosmoOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: cosmoDir, withIntermediateDirectories: true)
        return cosmoDir.appendingPathComponent("swipe_patterns.json")
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            patterns = snapshot.patterns
            pendingWeave = snapshot.pendingWeave
            lastWeaveAt = snapshot.lastWeaveAt
            migrationComplete = snapshot.migrationComplete
            migrationSeen = Set(snapshot.migrationSeen ?? [])
        }
        isLoaded = true
    }

    func save() {
        let snapshot = Snapshot(
            patterns: patterns,
            pendingWeave: pendingWeave,
            lastWeaveAt: lastWeaveAt,
            migrationComplete: migrationComplete,
            migrationSeen: Array(migrationSeen)
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Queries

    func patterns(containing swipeUUID: String) -> [SwipePattern] {
        patterns
            .filter { $0.members.contains(where: { $0.swipeUUID == swipeUUID }) }
            .sorted { $0.members.count > $1.members.count }
    }

    func pattern(id: UUID) -> SwipePattern? {
        patterns.first { $0.id == id }
    }

    /// Stage A candidate hints: patterns whose beat signature overlaps a
    /// swipe's normalized beats. Free (no LLM) — the weaver uses these as
    /// starting hypotheses, never as truth.
    func candidatePatterns(forBeats beats: [String], limit: Int = 3) -> [SwipePattern] {
        guard !beats.isEmpty else { return [] }
        let beatSet = Set(beats)
        return patterns
            .compactMap { pattern -> (SwipePattern, Double)? in
                guard !pattern.beatSignature.isEmpty else { return nil }
                let signature = Set(pattern.beatSignature)
                let overlap = Double(beatSet.intersection(signature).count)
                let score = overlap / Double(signature.union(beatSet).count)
                return score >= 0.5 ? (pattern, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Pending queue

    /// Called when a swipe finishes its insight pass. Idempotent.
    func markPendingWeave(_ swipeUUID: String) {
        guard !pendingWeave.contains(swipeUUID) else { return }
        pendingWeave.append(swipeUUID)
        save()
    }

    func consumePending(_ uuids: [String]) {
        pendingWeave.removeAll { uuids.contains($0) }
        save()
    }

    func markMigrationSeen(_ uuids: [String]) {
        migrationSeen.formUnion(uuids)
        save()
    }

    /// A deleted swipe leaves every pattern; patterns that drop below 2
    /// members dissolve.
    func removeSwipe(_ swipeUUID: String) {
        var changed = false
        for index in patterns.indices {
            let before = patterns[index].members.count
            patterns[index].members.removeAll { $0.swipeUUID == swipeUUID }
            if patterns[index].members.count != before { changed = true }
        }
        let beforeCount = patterns.count
        patterns.removeAll { $0.members.count < 2 }
        if pendingWeave.contains(swipeUUID) {
            pendingWeave.removeAll { $0 == swipeUUID }
            changed = true
        }
        if changed || patterns.count != beforeCount { save() }
    }

    // MARK: - Weaver application

    /// Apply one weaver response atomically: assignments reinforce existing
    /// patterns, refinements rename/redefine them, new patterns join with
    /// their founding members. Every referenced swipe UUID must come from the
    /// woven batch (the weaver validates before calling).
    func apply(
        assignments: [(patternID: UUID, member: SwipePatternMember)],
        refinements: [(patternID: UUID, name: String?, definition: String?)],
        newPatterns: [SwipePattern],
        wovenUUIDs: [String]
    ) {
        let now = Date()

        for assignment in assignments {
            guard let index = patterns.firstIndex(where: { $0.id == assignment.patternID }) else { continue }
            if !patterns[index].members.contains(where: { $0.swipeUUID == assignment.member.swipeUUID }) {
                patterns[index].members.append(assignment.member)
                patterns[index].lastReinforcedAt = now
            }
        }

        for refinement in refinements {
            guard let index = patterns.firstIndex(where: { $0.id == refinement.patternID }) else { continue }
            if let name = refinement.name, !name.isEmpty {
                patterns[index].name = name
            }
            if let definition = refinement.definition, !definition.isEmpty {
                patterns[index].definition = definition
            }
        }

        // A pattern needs ≥2 members to exist — singletons aren't patterns.
        patterns.append(contentsOf: newPatterns.filter { $0.members.count >= 2 })

        lastWeaveAt = now
        consumePending(wovenUUIDs)   // saves
    }
}
