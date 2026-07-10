// CosmoOS/AI/Taste/TasteEngine.swift
// The Taste engine — ONE model of what works for each client (and for the
// user's own voice), grown from real signals instead of scattered heuristic
// stacks. Replaces LessonExtractor / LessonPolicyResolver /
// ExperienceBufferService / SwipeAdaptationEngine.
//
// Signals (append-only, client-scoped): accepted/rejected assistant edits,
// recorded performance snapshots, explicit user rules. A periodic distiller
// (one strategist-tier call, teach-not-tell prompt, JSON-validated) turns
// accumulated signals into a versioned TasteProfile of BELIEFS — each with
// provenance counts and confidence. Explicit rules are PINNED and never
// auto-modified; struck beliefs never return. The profile compiles into the
// writing prompt block and feeds the deterministic validators.
// July 2026

import Foundation
import GRDB

// MARK: - Legacy Lesson Shapes (validator compatibility)
// The deterministic writing validators consume InferredLesson; the taste
// profile's pinned beliefs map into it. Moved here from the retired
// LessonExtractor.

enum LessonSource: String, Codable {
    case explicitUser = "explicit_user"
    case inferredEdit = "inferred_edit"
    case legacyModuleImport = "legacy_module_import"
}

enum LessonEnforcement: String, Codable {
    case hard = "hard"
    case advisory = "advisory"
}

struct InferredLesson: Codable, Identifiable {
    let id: UUID
    let clientUUID: String?
    let rule: String
    let evidence: String
    let category: String
    let confidence: Double
    let createdAt: Date
    var lastConfirmedAt: Date
    var optimizedInstruction: String?
    var intent: String?
    var source: LessonSource?
    var enforcement: LessonEnforcement?
    var targetModuleId: String?

    init(
        id: UUID = UUID(),
        clientUUID: String? = nil,
        rule: String,
        evidence: String,
        category: String,
        confidence: Double = 0.6,
        createdAt: Date = Date(),
        lastConfirmedAt: Date = Date(),
        optimizedInstruction: String? = nil,
        intent: String? = nil,
        source: LessonSource? = nil,
        enforcement: LessonEnforcement? = nil,
        targetModuleId: String? = nil
    ) {
        self.id = id
        self.clientUUID = clientUUID
        self.rule = rule
        self.evidence = evidence
        self.category = category
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastConfirmedAt = lastConfirmedAt
        self.optimizedInstruction = optimizedInstruction
        self.intent = intent
        self.source = source
        self.enforcement = enforcement
        self.targetModuleId = targetModuleId
    }

    var effectiveEnforcement: LessonEnforcement {
        if let enforcement { return enforcement }
        if source == .explicitUser { return .hard }
        if confidence >= 0.8 { return .hard }
        return .advisory
    }

    var effectiveSource: LessonSource {
        source ?? .inferredEdit
    }
}

// MARK: - Signals

struct TasteSignal: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "taste_signals"

    enum Kind: String, Codable, Sendable {
        case editAccepted = "edit_accepted"
        case editRejected = "edit_rejected"
        case perfEntry = "perf_entry"
        case explicitRule = "explicit_rule"
    }

    var id: Int64?
    var clientUuid: String?
    var kind: String
    var content: String
    var createdAt: String
    var distilled: Bool

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case clientUuid = "client_uuid"
        case kind, content
        case createdAt = "created_at"
        case distilled
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Beliefs & Profile

struct TasteBelief: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var text: String
    /// voice | structure | hooks | format | cta
    var category: String
    var confidence: Double
    /// User-authored — never auto-modified or dropped by the distiller.
    var pinned: Bool = false
    /// Struck by the user — tombstoned, never resurfaces.
    var struck: Bool = false
    /// How many signals support this belief (provenance count).
    var sources: Int = 0
}

struct TasteProfile: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "taste_profiles"

    var id: Int64?
    /// nil = the user's personal (cross-client) voice profile.
    var clientUuid: String?
    var version: Int
    var beliefsJson: String
    var distilledSignalCount: Int
    var updatedAt: String

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case clientUuid = "client_uuid"
        case version
        case beliefsJson = "beliefs_json"
        case distilledSignalCount = "distilled_signal_count"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var beliefs: [TasteBelief] {
        get {
            guard let data = beliefsJson.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TasteBelief].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                beliefsJson = json
            }
        }
    }
}

// MARK: - Store

enum TasteStore {
    static func record(
        kind: TasteSignal.Kind,
        clientUuid: String?,
        content: String
    ) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(TasteSignal.databaseTableName)) ?? false else { return }
            var signal = TasteSignal(
                id: nil,
                clientUuid: clientUuid,
                kind: kind.rawValue,
                content: String(trimmed.prefix(600)),
                createdAt: ISO8601.string(from: Date()),
                distilled: false
            )
            try signal.insert(db)
        }
    }

    static func profile(clientUuid: String?) async -> TasteProfile? {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(TasteProfile.databaseTableName)) ?? false else { return nil }
            if let clientUuid {
                return try TasteProfile
                    .filter(TasteProfile.CodingKeys.clientUuid == clientUuid)
                    .fetchOne(db)
            }
            return try TasteProfile
                .filter(sql: "client_uuid IS NULL")
                .fetchOne(db)
        }) ?? nil
    }

    static func save(_ profile: TasteProfile) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            var row = profile
            row.updatedAt = ISO8601.string(from: Date())
            try row.save(db)
        }
    }

    static func undistilledSignals(clientUuid: String?, limit: Int = 60) async -> [TasteSignal] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(TasteSignal.databaseTableName)) ?? false else { return [] }
            var request = TasteSignal.filter(Column("distilled") == false)
            if let clientUuid {
                request = request.filter(TasteSignal.CodingKeys.clientUuid == clientUuid)
            } else {
                request = request.filter(sql: "client_uuid IS NULL")
            }
            return try request.order(Column("id")).limit(limit).fetchAll(db)
        }) ?? []
    }

    static func markDistilled(_ signalIds: [Int64]) async {
        guard !signalIds.isEmpty else { return }
        try? await CosmoDatabase.shared.asyncWrite { db in
            let placeholders = signalIds.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE taste_signals SET distilled = 1 WHERE id IN (\(placeholders))",
                arguments: StatementArguments(signalIds)
            )
        }
    }
}

// MARK: - Distiller

enum TasteDistiller {
    /// Distill when this many new signals accumulate for a scope.
    static let signalThreshold = 8
    static let maxBeliefs = 18

    /// Called opportunistically (after signal writes, at startup). Cheap
    /// no-op below the threshold; one strategist call above it.
    static func distillIfDue(clientUuid: String?) async {
        let signals = await TasteStore.undistilledSignals(clientUuid: clientUuid)
        guard signals.count >= signalThreshold else { return }
        await distill(clientUuid: clientUuid, signals: signals)
    }

    static func distill(clientUuid: String?, signals: [TasteSignal]) async {
        guard !signals.isEmpty else { return }
        var profile = await TasteStore.profile(clientUuid: clientUuid) ?? TasteProfile(
            id: nil, clientUuid: clientUuid, version: 0,
            beliefsJson: "[]", distilledSignalCount: 0,
            updatedAt: ISO8601.string(from: Date())
        )
        let existing = profile.beliefs

        let signalLines = signals.map { "- [\($0.kind)] \($0.content)" }.joined(separator: "\n")
        let existingLines = existing
            .filter { !$0.struck && !$0.pinned }
            .map { "- (\($0.category), \($0.sources) signals) \($0.text)" }
            .joined(separator: "\n")

        let prompt = """
        You maintain a creator's TASTE PROFILE: short, testable beliefs about what works in their \
        content, grounded ONLY in the signals below.

        HOW TO WRITE A BELIEF (follow exactly):
        - One sentence, imperative or declarative, specific enough to check against a draft.
          GOOD: "Open reels with a concrete claim, not a question."
          BAD: "Write better hooks." (untestable)  BAD: "The user likes quality." (vacuous)
        - category is one of: voice, structure, hooks, format, cta.
        - confidence 0.3–0.9 based on how many signals support it. Never invent a belief no signal supports.
        - Merge with the existing beliefs: strengthen ones the new signals confirm (raise confidence,
          increment sources), keep unconfirmed ones unchanged, only drop one if signals contradict it.

        EXISTING BELIEFS:
        \(existingLines.isEmpty ? "(none yet)" : existingLines)

        NEW SIGNALS (\(signals.count)):
        \(signalLines)

        Respond ONLY with a JSON array (max \(maxBeliefs)):
        [{"text": "...", "category": "voice", "confidence": 0.6, "sources": 3}]
        """

        guard let response = try? await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: "You distill creator taste signals into testable beliefs. Respond only with valid JSON.",
            tier: .strategist,
            maxTokens: 1_500
        ) else { return }

        guard let distilled = parseBeliefs(response) else {
            print("TasteDistiller: unparseable response, keeping existing profile")
            return
        }

        // Merge contract: pinned and struck beliefs are the user's — untouchable.
        let pinned = existing.filter(\.pinned)
        let struckTexts = Set(existing.filter(\.struck).map { $0.text.lowercased() })
        let merged = pinned + distilled.filter { belief in
            !struckTexts.contains(belief.text.lowercased())
                && !pinned.contains { $0.text.lowercased() == belief.text.lowercased() }
        }

        profile.beliefs = Array(merged.prefix(maxBeliefs))
        profile.version += 1
        profile.distilledSignalCount += signals.count
        await TasteStore.save(profile)
        await TasteStore.markDistilled(signals.compactMap(\.id))
        print("TasteDistiller: profile v\(profile.version) — \(profile.beliefs.count) beliefs from \(signals.count) signals")
    }

    static func parseBeliefs(_ response: String) -> [TasteBelief]? {
        // Tolerate fences / prose around the array.
        guard let start = response.firstIndex(of: "["),
              let end = response.lastIndex(of: "]") else { return nil }
        let json = String(response[start...end])

        struct RawBelief: Decodable {
            let text: String
            let category: String?
            let confidence: Double?
            let sources: Int?
        }
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([RawBelief].self, from: data) else { return nil }

        let validCategories: Set<String> = ["voice", "structure", "hooks", "format", "cta"]
        return raw.compactMap { belief in
            let text = belief.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count > 8 else { return nil }
            return TasteBelief(
                text: text,
                category: validCategories.contains(belief.category ?? "") ? belief.category! : "voice",
                confidence: min(max(belief.confidence ?? 0.4, 0), 0.95),
                pinned: false,
                struck: false,
                sources: max(belief.sources ?? 1, 1)
            )
        }
    }
}

// MARK: - Convenience Writers

extension TasteStore {
    /// The richest implicit signal: the user edited an AI-generated draft.
    /// Records a compact before/after digest; the distiller infers the belief.
    static func recordDraftEdit(
        generated: String,
        edited: String,
        clientUuid: String?,
        format: String
    ) async {
        guard generated != edited, !generated.isEmpty, !edited.isEmpty else { return }
        let generatedLines = generated.components(separatedBy: "\n")
        let editedLines = edited.components(separatedBy: "\n")
        var changes: [String] = []
        for (before, after) in zip(generatedLines, editedLines)
        where before != after && changes.count < 3 {
            changes.append("BEFORE: \(before.prefix(120))\nAFTER: \(after.prefix(120))")
        }
        guard !changes.isEmpty else { return }
        await record(
            kind: .editRejected,
            clientUuid: clientUuid,
            content: "User edited an AI draft (\(format)):\n" + changes.joined(separator: "\n")
        )
        await TasteDistiller.distillIfDue(clientUuid: clientUuid)
    }

    /// Explicit user rule → a pinned belief, immediately active, never
    /// auto-modified. Also logged as a signal for provenance.
    static func addPinnedRule(_ text: String, category: String, clientUuid: String?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var profile = await profile(clientUuid: clientUuid) ?? TasteProfile(
            id: nil, clientUuid: clientUuid, version: 0,
            beliefsJson: "[]", distilledSignalCount: 0,
            updatedAt: ISO8601.string(from: Date())
        )
        var beliefs = profile.beliefs
        guard !beliefs.contains(where: { $0.text.lowercased() == trimmed.lowercased() }) else { return }
        beliefs.insert(
            TasteBelief(text: trimmed, category: category, confidence: 1.0, pinned: true, sources: 1),
            at: 0
        )
        profile.beliefs = beliefs
        profile.version += 1
        await save(profile)
        await record(kind: .explicitRule, clientUuid: clientUuid, content: trimmed)
        await MainActor.run {
            NotificationCenter.default.post(name: .cosmoTasteChanged, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted when a taste profile changes — writing-engine caches invalidate.
    static let cosmoTasteChanged = Notification.Name("cosmoTasteChanged")
}

// MARK: - Writing-Engine Context

/// What the writing engine consumes — same shape the retired
/// LessonPolicyResolver produced, so the swap is one call-site change.
struct ResolvedTastePolicy {
    let hardRules: [InferredLesson]
    let advisoryRules: [InferredLesson]
    let formattedBlock: String

    var totalCount: Int { hardRules.count + advisoryRules.count }
}

enum TasteContext {
    /// Compile the client's profile (plus the personal one) into a prompt
    /// block. Pinned beliefs double as hard rules for the deterministic
    /// validators.
    static func resolveForWritingEngine(
        clientUUID: String?,
        intent: String? = "draft",
        format: String? = nil
    ) async -> ResolvedTastePolicy {
        var beliefs: [TasteBelief] = []
        if let clientUUID, let clientProfile = await TasteStore.profile(clientUuid: clientUUID) {
            beliefs.append(contentsOf: clientProfile.beliefs)
        }
        if let personal = await TasteStore.profile(clientUuid: nil) {
            beliefs.append(contentsOf: personal.beliefs)
        }

        let active = beliefs
            .filter { !$0.struck }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                return lhs.confidence > rhs.confidence
            }
            .prefix(15)

        guard !active.isEmpty else {
            return ResolvedTastePolicy(hardRules: [], advisoryRules: [], formattedBlock: "")
        }

        var lines: [String] = []
        lines.append("## LEARNED TASTE (from this creator's real signals)")
        lines.append("These beliefs come from accepted edits, rejected suggestions, and real post performance. Follow pinned rules strictly; treat the rest as strong defaults.")
        for belief in active {
            let marker = belief.pinned ? "[RULE]" : "[\(belief.category), \(belief.sources) signals]"
            lines.append("- \(marker) \(belief.text)")
        }

        let now = Date()
        func lesson(_ belief: TasteBelief, hard: Bool) -> InferredLesson {
            InferredLesson(
                id: UUID(),
                clientUUID: clientUUID,
                rule: belief.text,
                evidence: hard ? "Pinned by the user in the Taste profile" : "\(belief.sources) signals",
                category: belief.category,
                confidence: hard ? 1.0 : belief.confidence,
                createdAt: now,
                lastConfirmedAt: now,
                optimizedInstruction: nil,
                intent: intent,
                enforcement: hard ? .hard : .advisory
            )
        }
        let hardRules = active.filter(\.pinned).map { lesson($0, hard: true) }
        let advisoryRules = active.filter { !$0.pinned }.map { lesson($0, hard: false) }

        return ResolvedTastePolicy(
            hardRules: hardRules,
            advisoryRules: advisoryRules,
            formattedBlock: lines.joined(separator: "\n")
        )
    }

    /// Agent-facing shape (mirrors the retired resolver's tuple).
    static func resolveForAgent(
        clientUUID: UUID? = nil,
        intent: String? = nil
    ) async -> (formatted: String, lessons: [(rule: String, category: String, intent: String?)]) {
        let policy = await resolveForWritingEngine(
            clientUUID: clientUUID?.uuidString, intent: intent
        )
        guard !policy.formattedBlock.isEmpty else { return ("", []) }
        var beliefs: [TasteBelief] = []
        if let clientUUID, let clientProfile = await TasteStore.profile(clientUuid: clientUUID.uuidString) {
            beliefs.append(contentsOf: clientProfile.beliefs)
        }
        if let personal = await TasteStore.profile(clientUuid: nil) {
            beliefs.append(contentsOf: personal.beliefs)
        }
        let lessons = beliefs
            .filter { !$0.struck }
            .map { (rule: $0.text, category: $0.category, intent: intent) }
        return (policy.formattedBlock, lessons)
    }
}
