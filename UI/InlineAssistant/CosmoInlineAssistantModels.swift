import CoreGraphics
import Foundation
import GRDB

enum CosmoInlineAssistantRoute: String, Codable, Equatable, Sendable {
    case action
    case answer
}

enum CosmoEditableSurfaceKind: String, Codable, Equatable, Sendable {
    case text
    case structured
    case canvas
}

enum CosmoInlineAssistantSkillID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case contentReview
    case critique
    case voiceVariations
    case inlineEdit
    case factFill
    case researchAnswer
    case canvasOrganize
    case ideaStrategy
    case concept
    case skillBuilder
    case synthesize
    case ideaResearch
}

enum CosmoInlineAssistantSkillContext: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case activeSurface
    case currentFocus
    case clientProfile
    case clientMemory
    case voiceLessons
    case swipes
    case bestPerformingContent
    case researchEvidence
    case workspaceMemory
    case canvasState

    var displayName: String {
        switch self {
        case .activeSurface: return "active surface"
        case .currentFocus: return "current focus"
        case .clientProfile: return "client profile"
        case .clientMemory: return "client memory"
        case .voiceLessons: return "voice lessons"
        case .swipes: return "swipes"
        case .bestPerformingContent: return "best-performing content"
        case .researchEvidence: return "research evidence"
        case .workspaceMemory: return "workspace memory"
        case .canvasState: return "canvas state"
        }
    }
}

struct CosmoInlineAssistantSkill: Codable, Equatable, Sendable {
    var id: CosmoInlineAssistantSkillID
    var name: String
    var description: String
    var route: CosmoInlineAssistantRoute
    var requiredContext: Set<CosmoInlineAssistantSkillContext>
    var toolBundles: Set<AgentToolBundle>
    var outputContract: String
    var instructions: [String]
    var tokenBudget: Int
    var requiresReviewedDiff: Bool
    var icon: String = "sparkle"
    var summary: String = ""
    var triggerPhrases: [String] = []
    var preferredModelTier: AgentModelTier? = nil
    var panePolicy: CosmoInlineSkillPanePolicy = .openForAnswer
    var examples: [CosmoInlineSkillExample]? = nil
    var verification: String? = nil
}

enum CosmoInlineSkillPanePolicy: String, Codable, Equatable, Sendable {
    case neverForAction
    case openForAnswer
    case openForResearchBackedAction
    case alwaysOpenWithResult
}

struct CosmoInlineAssistantSkillPlan: Codable, Equatable, Sendable {
    var primarySkill: CosmoInlineAssistantSkill
    var definitionID: String? = nil
    /// Multi-phase pipeline from the skill definition — when present, the
    /// bridge runs the skill step-by-step instead of as one turn.
    var pipelineSteps: [CosmoInlineSkillStep]? = nil

    var route: CosmoInlineAssistantRoute { primarySkill.route }
    var requiredContext: Set<CosmoInlineAssistantSkillContext> { primarySkill.requiredContext }
    var toolBundles: Set<AgentToolBundle> { primarySkill.toolBundles }
    var requiresReviewedDiff: Bool { primarySkill.requiresReviewedDiff }
    var preferredModelTier: AgentModelTier? { primarySkill.preferredModelTier }
    var panePolicy: CosmoInlineSkillPanePolicy { primarySkill.panePolicy }

    var promptBlock: String {
        let context = requiredContext
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: ", ")
        let bundles = toolBundles
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")
        let steps = primarySkill.instructions
            .map { "- \($0)" }
            .joined(separator: "\n")

        var block = """
        ## Inline Skill Runtime
        Active skill: \(primarySkill.name)
        Skill id: \(primarySkill.id.rawValue)
        Skill definition id: \(definitionID ?? primarySkill.id.rawValue)
        Skill route: \(route.rawValue)
        Preferred model tier: \(preferredModelTier?.rawValue ?? "auto")
        Pane policy: \(panePolicy.rawValue)
        Required context: \(context)
        Tool bundles: \(bundles)
        Output contract: \(primarySkill.outputContract)
        Token budget: about \(primarySkill.tokenBudget) tokens for this skill layer.
        Requires reviewed diff: \(requiresReviewedDiff ? "yes" : "no")

        Skill instructions:
        \(steps)
        """

        if let examples = primarySkill.examples, !examples.isEmpty {
            let exampleBlocks = examples.map(\.promptBlock).joined(separator: "\n")
            block += """


            Skill examples — match this shape and quality exactly:
            \(exampleBlocks)
            """
        }

        if let verification = primarySkill.verification,
           !verification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            block += """


            Before staging output, verify: \(verification)
            If a check fails, fix the output before calling the tool — do not stage failing output.
            """
        }

        return block
    }
}

/// Event-driven skill activation: a skill can offer itself (or run) when
/// something happens in the workspace, instead of waiting to be asked.
/// Guardrails live in the runner: per-skill+surface cooldown, never while a
/// run is in flight, and `suggest` mode costs zero tokens until tapped.
struct CosmoInlineSkillAutoTrigger: Codable, Equatable, Sendable {
    enum Event: String, Codable, Equatable, Sendable {
        /// The user opened/focused an editable surface.
        case onSurfaceActivate
        /// The user accepted a staged proposal on this surface.
        case onProposalAccepted
    }

    enum Mode: String, Codable, Equatable, Sendable {
        /// Present a one-tap chip — the skill only runs when the user taps it.
        case suggest
        /// Run the skill immediately (staging-only: its output is a reviewed
        /// proposal or one pane card, never chat spam).
        case run
    }

    var event: Event
    var mode: Mode = .suggest
    /// Restrict to surface kinds (e.g. only content drafts). Nil = any.
    var surfaceKinds: Set<CosmoEditableSurfaceKind>? = nil
    /// Minimum minutes between firings per surface.
    var cooldownMinutes: Int = 60
    /// The prompt the firing submits (or the chip label in suggest mode).
    var prompt: String = "Begin."
}

/// One phase of a multi-step skill pipeline. Steps run sequentially as scoped
/// agent turns in the same conversation — each sees the previous steps'
/// receipts, and each can carry its own tool bundles and model tier
/// (gather-on-Haiku → write-on-Sonnet → stage-edits).
struct CosmoInlineSkillStep: Codable, Equatable, Sendable {
    var name: String
    var instructions: [String]
    var toolBundles: Set<AgentToolBundle>? = nil
    var preferredModelTier: AgentModelTier? = nil
    var outputContract: String? = nil

    func promptBlock(index: Int, total: Int) -> String {
        var block = """
        ## Pipeline Step \(index + 1) of \(total): \(name)
        Complete ONLY this step now. Earlier steps' results are in the conversation history.
        \(instructions.map { "- \($0)" }.joined(separator: "\n"))
        """
        if let outputContract, !outputContract.isEmpty {
            block += "\nStep output contract: \(outputContract)"
        }
        if index + 1 < total {
            block += "\nDeliver this step's result via answer_in_assistant_pane; the next step builds on it."
        }
        return block
    }
}

/// A paired example teaching a skill what great output looks like. Examples are
/// the highest-leverage field for Haiku-tier skills — small models imitate far
/// better than they follow abstract instructions.
struct CosmoInlineSkillExample: Codable, Equatable, Sendable {
    var input: String
    var idealOutput: String

    var promptBlock: String {
        """
        <example>
        <input>\(input)</input>
        <ideal_output>\(idealOutput)</ideal_output>
        </example>
        """
    }
}

struct CosmoInlineSkillDefinition: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var baseSkillID: CosmoInlineAssistantSkillID
    var name: String
    var icon: String
    var summary: String
    var triggerPhrases: [String]
    var route: CosmoInlineAssistantRoute
    var preferredModelTier: AgentModelTier?
    var requiredContext: Set<CosmoInlineAssistantSkillContext>
    var toolBundles: Set<AgentToolBundle>
    var instructions: [String]
    var outputContract: String
    var tokenBudget: Int
    var requiresReviewedDiff: Bool
    var panePolicy: CosmoInlineSkillPanePolicy
    var isBuiltin: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    // Optional upgrades (decode as nil from older persisted definitions):
    /// One-sentence description of *when* this skill should trigger, written for
    /// embedding-based auto-routing — phrased in the user's own vocabulary.
    var triggerDescription: String?
    /// Input → ideal-output pairs injected with the skill's instructions.
    var examples: [CosmoInlineSkillExample]?
    /// Post-conditions the model must check before staging output
    /// (e.g. "every slide keeps its SLIDE N header", "no invented metrics").
    var verification: String?
    /// Event-driven activation (decodes nil from older persisted definitions).
    var autoTrigger: CosmoInlineSkillAutoTrigger?
    /// Multi-phase pipeline (decodes nil from older persisted definitions).
    /// When present, the skill runs step-by-step instead of as one turn.
    var steps: [CosmoInlineSkillStep]?

    var displayedModelLabel: String {
        if isBuiltin,
           baseSkillID == .contentReview || baseSkillID == .voiceVariations {
            return "Opus 4.8"
        }
        return preferredModelTier?.displayLabel ?? "Auto"
    }

    static func custom(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "sparkle",
        summary: String,
        triggerPhrases: [String] = [],
        route: CosmoInlineAssistantRoute,
        preferredModelTier: AgentModelTier? = nil,
        requiredContext: Set<CosmoInlineAssistantSkillContext> = [.activeSurface],
        toolBundles: Set<AgentToolBundle> = [.workspaceEditing, .writing],
        instructions: [String],
        outputContract: String,
        tokenBudget: Int = 1400,
        requiresReviewedDiff: Bool,
        panePolicy: CosmoInlineSkillPanePolicy,
        triggerDescription: String? = nil,
        examples: [CosmoInlineSkillExample]? = nil,
        verification: String? = nil,
        now: Date = Date()
    ) -> CosmoInlineSkillDefinition {
        CosmoInlineSkillDefinition(
            id: id,
            baseSkillID: route == .action ? .inlineEdit : .researchAnswer,
            name: name,
            icon: icon,
            summary: summary,
            triggerPhrases: triggerPhrases,
            route: route,
            preferredModelTier: preferredModelTier,
            requiredContext: requiredContext,
            toolBundles: toolBundles,
            instructions: instructions,
            outputContract: outputContract,
            tokenBudget: tokenBudget,
            requiresReviewedDiff: requiresReviewedDiff,
            panePolicy: panePolicy,
            isBuiltin: false,
            isEnabled: true,
            createdAt: now,
            updatedAt: now,
            triggerDescription: triggerDescription,
            examples: examples,
            verification: verification
        )
    }

    static func builtin(from skill: CosmoInlineAssistantSkill) -> CosmoInlineSkillDefinition {
        CosmoInlineSkillDefinition(
            id: skill.id.rawValue,
            baseSkillID: skill.id,
            name: skill.name,
            icon: skill.icon,
            summary: skill.summary.isEmpty ? skill.description : skill.summary,
            triggerPhrases: skill.triggerPhrases,
            route: skill.route,
            preferredModelTier: skill.preferredModelTier,
            requiredContext: skill.requiredContext,
            toolBundles: skill.toolBundles,
            instructions: skill.instructions,
            outputContract: skill.outputContract,
            tokenBudget: skill.tokenBudget,
            requiresReviewedDiff: skill.requiresReviewedDiff,
            panePolicy: skill.panePolicy,
            isBuiltin: true,
            isEnabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func assistantSkill() -> CosmoInlineAssistantSkill {
        CosmoInlineAssistantSkill(
            id: baseSkillID,
            name: name,
            description: summary,
            route: route,
            requiredContext: requiredContext,
            toolBundles: toolBundles,
            outputContract: outputContract,
            instructions: instructions,
            tokenBudget: tokenBudget,
            requiresReviewedDiff: requiresReviewedDiff,
            icon: icon,
            summary: summary,
            triggerPhrases: triggerPhrases,
            preferredModelTier: preferredModelTier,
            panePolicy: panePolicy,
            examples: examples,
            verification: verification
        )
    }
}

struct CosmoInlineSkillStore {
    private final class Box {
        var skills: [CosmoInlineSkillDefinition]

        init(skills: [CosmoInlineSkillDefinition]) {
            self.skills = skills
        }
    }

    private var load: () -> [CosmoInlineSkillDefinition]
    private var save: ([CosmoInlineSkillDefinition]) -> Void

    static func inMemory(customSkills: [CosmoInlineSkillDefinition] = []) -> CosmoInlineSkillStore {
        let box = Box(skills: customSkills)
        return CosmoInlineSkillStore(
            load: { box.skills },
            save: { box.skills = $0 }
        )
    }

    static func userDefaults(
        defaults: UserDefaults = .standard,
        key: String = "cosmo.inline.skills.custom.v1"
    ) -> CosmoInlineSkillStore {
        CosmoInlineSkillStore(
            load: {
                guard let data = defaults.data(forKey: key),
                      let decoded = try? JSONDecoder().decode([CosmoInlineSkillDefinition].self, from: data) else {
                    return []
                }
                return decoded
            },
            save: { skills in
                guard let data = try? JSONEncoder().encode(skills) else { return }
                defaults.set(data, forKey: key)
            }
        )
    }

    /// `CosmoDatabase.shared.dbPool` is main-actor state; the store's closures are
    /// nonisolated and overwhelmingly called on the main thread (registry, executor,
    /// composer). Resolve with an isolation check so a rare off-main call hops
    /// instead of crashing — GRDB queues themselves are thread-safe once obtained.
    private static func resolveDBQueue() -> DatabasePool? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { CosmoDatabase.shared.dbPool }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { CosmoDatabase.shared.dbPool }
        }
    }

    /// Durable GRDB-backed store (`inline_assistant_skills` table). Skills survive
    /// reinstalls of preferences, can carry routing embeddings, and are positioned
    /// for sync — UserDefaults was a stopgap.
    static func database() -> CosmoInlineSkillStore {
        CosmoInlineSkillStore(
            load: {
                guard let dbQueue = resolveDBQueue() else { return [] }
                let decoder = JSONDecoder()
                let rows = (try? dbQueue.read { db in
                    try Row.fetchAll(db, sql: """
                        SELECT definition FROM inline_assistant_skills
                        WHERE is_deleted = 0
                        ORDER BY updated_at DESC
                        """)
                }) ?? []
                return rows.compactMap { row in
                    guard let json = row["definition"] as? String,
                          let data = json.data(using: .utf8) else { return nil }
                    return try? decoder.decode(CosmoInlineSkillDefinition.self, from: data)
                }
            },
            save: { skills in
                guard let dbQueue = resolveDBQueue() else { return }
                let encoder = JSONEncoder()
                try? dbQueue.write { db in
                    // Full-set replace mirrors the closure contract the other
                    // backends use ("save the complete custom-skill list").
                    try db.execute(sql: "UPDATE inline_assistant_skills SET is_deleted = 1")
                    for skill in skills {
                        guard let data = try? encoder.encode(skill),
                              let json = String(data: data, encoding: .utf8) else { continue }
                        try db.execute(
                            sql: """
                            INSERT INTO inline_assistant_skills
                                (id, name, definition, is_enabled, is_builtin, created_at, updated_at, is_deleted)
                            VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                            ON CONFLICT(id) DO UPDATE SET
                                name = excluded.name,
                                definition = excluded.definition,
                                is_enabled = excluded.is_enabled,
                                updated_at = excluded.updated_at,
                                is_deleted = 0
                            """,
                            arguments: [
                                skill.id,
                                skill.name,
                                json,
                                skill.isEnabled,
                                skill.isBuiltin,
                                ISO8601DateFormatter().string(from: skill.createdAt),
                                ISO8601DateFormatter().string(from: skill.updatedAt)
                            ]
                        )
                    }
                }
            }
        )
    }

    /// One-shot migration flag. Benign under races — the migration itself is
    /// guarded by "legacy skills exist AND the table is empty".
    nonisolated(unsafe) private static var didMigrateFromUserDefaults = false

    /// The production store: GRDB-backed, with a one-time migration of any skills
    /// previously persisted in UserDefaults. Tests get the in-memory store.
    static func defaultForRuntime() -> CosmoInlineSkillStore {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return inMemory()
        }

        let store = database()
        if !didMigrateFromUserDefaults {
            didMigrateFromUserDefaults = true
            let legacy = userDefaults().customSkills()
            if !legacy.isEmpty, store.customSkills().isEmpty {
                legacy.forEach { store.save($0) }
                print("✅ Migrated \(legacy.count) inline skills from UserDefaults to GRDB")
            }
        }
        return store
    }

    func customSkills() -> [CosmoInlineSkillDefinition] {
        load()
            .filter { !$0.isBuiltin }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func save(_ skill: CosmoInlineSkillDefinition) {
        var skills = customSkills().filter { $0.id != skill.id }
        skills.append(skill)
        save(skills)
    }

    func delete(id: String) {
        save(customSkills().filter { $0.id != id })
    }
}

struct CosmoInlineSkillRegistry {
    var store: CosmoInlineSkillStore

    init(store: CosmoInlineSkillStore = .defaultForRuntime()) {
        self.store = store
    }

    var builtInSkills: [CosmoInlineSkillDefinition] {
        CosmoInlineAssistantSkillID.allCases.map {
            .builtin(from: CosmoInlineAssistantSkillRuntime.builtInSkill($0))
        }
    }

    var enabledSkills: [CosmoInlineSkillDefinition] {
        (builtInSkills + store.customSkills())
            .filter(\.isEnabled)
    }

    func skill(id: String) -> CosmoInlineSkillDefinition? {
        let normalizedID = Self.normalized(id)
        return enabledSkills.first { skill in
            skill.id == id ||
            skill.baseSkillID.rawValue == id ||
            Self.normalized(skill.id) == normalizedID ||
            Self.normalized(skill.name) == normalizedID ||
            Self.normalized(skill.baseSkillID.rawValue) == normalizedID
        }
    }

    func matchingSlashCommands(query: String, limit: Int = 8) -> [CosmoInlineSkillDefinition] {
        let normalizedQuery = Self.normalized(query)
        let skills = enabledSkills
        guard !normalizedQuery.isEmpty else {
            return Array(skills.prefix(limit))
        }
        return skills
            .filter { skill in
                aliases(for: skill).contains { Self.normalized($0).contains(normalizedQuery) }
            }
            .prefix(limit)
            .map { $0 }
    }

    func slashMatch(in slashBody: String) -> (skill: CosmoInlineSkillDefinition, alias: String)? {
        let body = slashBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        return enabledSkills
            .flatMap { skill in aliases(for: skill).map { (skill, $0) } }
            .filter { _, alias in Self.hasAliasPrefix(alias, in: body) }
            .sorted { lhs, rhs in
                lhs.1.count > rhs.1.count
            }
            .first
    }

    private func aliases(for skill: CosmoInlineSkillDefinition) -> [String] {
        var aliases = [
            skill.name,
            skill.id,
            skill.baseSkillID.rawValue,
            Self.humanized(skill.baseSkillID.rawValue)
        ]
        aliases.append(contentsOf: skill.triggerPhrases)
        return Array(Set(aliases))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func hasAliasPrefix(_ alias: String, in body: String) -> Bool {
        let aliasLower = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bodyLower = body.lowercased()
        guard !aliasLower.isEmpty,
              bodyLower.hasPrefix(aliasLower) else {
            return false
        }

        let index = bodyLower.index(bodyLower.startIndex, offsetBy: aliasLower.count)
        guard index < bodyLower.endIndex else { return true }
        let next = bodyLower[index]
        return next.isWhitespace || next == ":" || next == "-"
    }

    static func humanized(_ raw: String) -> String {
        raw
            .reduce(into: "") { result, character in
                if character.isUppercase, !result.isEmpty {
                    result.append(" ")
                }
                result.append(character)
            }
            .capitalized
    }

    static func normalized(_ raw: String) -> String {
        raw
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

struct CosmoInlineSlashSkillCommand: Equatable, Sendable {
    var skillID: String
    var skillName: String
    var remainingPrompt: String
}

struct CosmoInlineActiveSlashSkillCommand: Equatable, Sendable {
    var query: String
    var range: NSRange
}

enum CosmoInlineSlashSkillParser {
    static func activeCommand(
        in text: String,
        selectedRange: NSRange
    ) -> CosmoInlineActiveSlashSkillCommand? {
        guard selectedRange.length == 0 else { return nil }
        let nsText = text as NSString
        let cursor = min(max(selectedRange.location, 0), nsText.length)
        guard cursor > 0 else { return nil }

        var start = cursor
        while start > 0 {
            let previous = nsText.character(at: start - 1)
            guard let scalar = UnicodeScalar(previous) else { break }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                break
            }
            start -= 1
        }

        guard start < cursor,
              nsText.substring(with: NSRange(location: start, length: 1)) == "/" else {
            return nil
        }

        if start > 0 {
            let previous = nsText.character(at: start - 1)
            guard let scalar = UnicodeScalar(previous),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                return nil
            }
        }

        let length = cursor - start
        let token = nsText.substring(with: NSRange(location: start, length: length))
        guard !token.contains("://") else { return nil }

        let queryRange = NSRange(location: start + 1, length: max(length - 1, 0))
        return CosmoInlineActiveSlashSkillCommand(
            query: nsText.substring(with: queryRange),
            range: NSRange(location: start, length: length)
        )
    }

    static func extractCommand(
        from text: String,
        registry: CosmoInlineSkillRegistry = CosmoInlineSkillRegistry()
    ) -> CosmoInlineSlashSkillCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let bodyStart = trimmed.index(after: trimmed.startIndex)
        let body = String(trimmed[bodyStart...])
        guard let match = registry.slashMatch(in: body) else { return nil }

        let aliasLength = match.alias.trimmingCharacters(in: .whitespacesAndNewlines).count
        let remainingStart = body.index(body.startIndex, offsetBy: min(aliasLength, body.count))
        let remaining = String(body[remainingStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CosmoInlineSlashSkillCommand(
            skillID: match.skill.id,
            skillName: match.skill.name,
            remainingPrompt: remaining
        )
    }
}

/// The session's working state: which surface, client, skill, and selected
/// @ context the conversation is bound to. Pure state — cross-message
/// continuity itself lives in the session ledger ("## Session So Far"), not in
/// keyword follow-up detection.
struct CosmoInlineAssistantWorkingContextFrame: Codable, Equatable, Sendable {
    var conversationID: String
    var surfaceID: String?
    var targetID: String?
    var surfaceKind: CosmoEditableSurfaceKind?
    var surfaceTitle: String?
    var surfaceSourceHash: String?
    var activeAtomUUID: String?
    var effectiveClientUUID: String?
    var skillID: CosmoInlineAssistantSkillID
    var route: CosmoInlineAssistantRoute
    var contextAtomUUIDs: [String] = []
    var contextAtomTitles: [String] = []
    var updatedAt: Date

    var promptBlock: String {
        let surface = surfaceID ?? activeAtomUUID ?? "none"
        let title = surfaceTitle ?? "untitled"
        let clientUUID = effectiveClientUUID ?? "none"
        let sourceHash = surfaceSourceHash ?? "none"
        let selectedContext = contextAtomTitles.isEmpty ? "none" : contextAtomTitles.joined(separator: ", ")
        let selectedContextIDs = contextAtomUUIDs.isEmpty ? "none" : contextAtomUUIDs.joined(separator: ", ")

        return """
        ## Inline Working Context
        Surface scope: \(surface)
        Surface title: \(title)
        Surface source hash: \(sourceHash)
        Active atom UUID: \(activeAtomUUID ?? "none")
        Active client UUID: \(clientUUID)
        Current skill: \(skillID.rawValue)
        Selected context: \(selectedContext)
        Selected context UUIDs: \(selectedContextIDs)

        Context rules:
        - The active client and selected @ context stay bound to this session until the user changes them.
        - Refresh the active surface text whenever the source hash changes; never rely on remembered text for reviewed diffs.
        - If client/profile evidence is missing, call the profile/search tools instead of guessing.
        """
    }
}

@MainActor
final class CosmoInlineAssistantWorkingContextCache {
    static let shared = CosmoInlineAssistantWorkingContextCache()

    private let ttl: TimeInterval
    private var framesByScope: [String: CosmoInlineAssistantWorkingContextFrame] = [:]

    init(ttl: TimeInterval = 600) {
        self.ttl = ttl
    }

    func updateFrame(
        conversationID: String,
        route: CosmoInlineAssistantRoute,
        snapshot: CosmoEditableSourceSnapshot?,
        activeAtomUUID: String?,
        activeClientUUID: String?,
        contextAtoms: [Atom] = [],
        skillPlan: CosmoInlineAssistantSkillPlan,
        now: Date = Date()
    ) -> CosmoInlineAssistantWorkingContextFrame {
        let key = scopeKey(
            conversationID: conversationID,
            snapshot: snapshot,
            activeAtomUUID: activeAtomUUID
        )
        let previous = freshFrame(for: key, now: now)
        // Client continuity is state, not keyword detection: the session's
        // client sticks until app state names another (TTL-bounded by the
        // frame itself).
        let effectiveClientUUID = activeClientUUID ?? previous?.effectiveClientUUID

        let frame = CosmoInlineAssistantWorkingContextFrame(
            conversationID: conversationID,
            surfaceID: snapshot?.surfaceID,
            targetID: snapshot?.targetID,
            surfaceKind: snapshot?.kind,
            surfaceTitle: snapshot?.title,
            surfaceSourceHash: snapshot?.sourceHash,
            activeAtomUUID: activeAtomUUID,
            effectiveClientUUID: effectiveClientUUID,
            skillID: skillPlan.primarySkill.id,
            route: route,
            contextAtomUUIDs: contextAtoms.map(\.uuid),
            contextAtomTitles: contextAtoms.map { $0.title ?? "Untitled" },
            updatedAt: now
        )
        framesByScope[key] = frame
        return frame
    }

    func currentFrame(
        conversationID: String,
        snapshot: CosmoEditableSourceSnapshot?,
        activeAtomUUID: String?,
        now: Date = Date()
    ) -> CosmoInlineAssistantWorkingContextFrame? {
        freshFrame(
            for: scopeKey(
                conversationID: conversationID,
                snapshot: snapshot,
                activeAtomUUID: activeAtomUUID
            ),
            now: now
        )
    }

    func clear() {
        framesByScope.removeAll()
    }

    func clear(conversationID: String, surfaceID: String?) {
        let key = [
            conversationID,
            surfaceID ?? "global"
        ].joined(separator: "|")
        framesByScope.removeValue(forKey: key)
    }

    private func freshFrame(
        for key: String,
        now: Date
    ) -> CosmoInlineAssistantWorkingContextFrame? {
        guard let frame = framesByScope[key] else { return nil }
        if now.timeIntervalSince(frame.updatedAt) <= ttl {
            return frame
        }
        framesByScope.removeValue(forKey: key)
        return nil
    }

    private func scopeKey(
        conversationID: String,
        snapshot: CosmoEditableSourceSnapshot?,
        activeAtomUUID: String?
    ) -> String {
        [
            conversationID,
            snapshot?.surfaceID ?? activeAtomUUID ?? "global"
        ].joined(separator: "|")
    }

}

/// Parses an explicitly named client out of the CURRENT prompt ("for Marcus",
/// "Josh's profile"). Single-message entity extraction — cross-message client
/// continuity is the working frame's state, and session continuity is the
/// ledger's job.
enum CosmoExplicitClientReference {
    static func firstName(in prompt: String) -> String? {
        let words = prompt.split(separator: " ").map(String.init)
        let triggers: Set<String> = ["for", "about", "to", "of", "from"]

        for (index, rawWord) in words.enumerated() {
            let cleaned = clean(rawWord).lowercased()
            guard triggers.contains(cleaned), index + 1 < words.count else { continue }
            let candidate = cleanClientCandidate(words[index + 1])
            guard candidate.count > 1, candidate.first?.isUppercase == true else { continue }
            return candidate
        }

        for rawWord in words {
            let lower = rawWord.lowercased()
            guard lower.contains("'s") || lower.contains("’s") else { continue }
            let candidate = cleanClientCandidate(rawWord)
            guard candidate.count > 1, candidate.first?.isUppercase == true else { continue }
            return candidate
        }

        return nil
    }

    private static func clean(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private static func cleanClientCandidate(_ word: String) -> String {
        var cleaned = word
            .replacingOccurrences(of: "’s", with: "")
            .replacingOccurrences(of: "'s", with: "")
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.hasSuffix("s"), word.contains("'") || word.contains("’") {
            cleaned.removeLast()
        }
        return cleaned
    }
}

struct CosmoInlineResolvedSkillContext: Equatable, Sendable {
    var blocks: [String]
    var satisfiedContexts: Set<CosmoInlineAssistantSkillContext>

    var isEmpty: Bool {
        blocks.isEmpty
    }

    var promptBlock: String {
        guard !blocks.isEmpty else { return "" }

        return """
        ## Resolved Inline Skill Context
        The facts below were pre-resolved from Cosmo before this model call, and the active surface text is already in this prompt. Use them directly and propose the edit in your FIRST response. Do NOT call retrieve_context or get_client_profile — that context is already here. Call lookup_client_facts ONLY when the request needs a specific client fact that is genuinely missing from the block below.

        \(blocks.joined(separator: "\n\n"))
        """
    }
}

enum CosmoCompactClientProfile {
    static func format(atom: Atom? = nil, meta: ClientProfileMetadata) -> String {
        var lines: [String] = []
        append("Client", meta.clientName, to: &lines)
        append("Atom UUID", atom?.uuid, to: &lines)
        append("Handle", meta.handle, to: &lines)
        append("Niche", meta.niche ?? meta.industry, to: &lines)
        append("Primary platform", meta.primaryPlatform?.displayName, to: &lines)
        append("Platforms", joined(meta.platforms.map(\.displayName)), to: &lines)
        append("Target audience", meta.targetAudience, to: &lines)
        append("Brand story", clipped(meta.brandStory, limit: 700), to: &lines)
        append("Brand vision", clipped(meta.brandVision, limit: 450), to: &lines)
        append("Unique angle", clipped(meta.uniqueAngle, limit: 350), to: &lines)
        append("Voice notes", clipped(meta.voiceNotes, limit: 450), to: &lines)
        append("Core beliefs", joined(meta.coreBeliefs, limit: 8), to: &lines)
        append("Signature phrases", joined(meta.signaturePhrases, limit: 10), to: &lines)
        append("Best formats", joined(meta.bestFormats, limit: 8), to: &lines)
        append("Preferred beat patterns", joined(meta.preferredBeatPatterns, limit: 8), to: &lines)
        append("Posting frequency", meta.postingFrequency, to: &lines)
        append("Preferred post times", joined(meta.preferredPostTimes, limit: 6), to: &lines)

        if let documents = meta.documents, !documents.isEmpty {
            let index = documents
                .prefix(14)
                .map { document in
                    "- \(document.category.displayName): \(document.title)\(metricsSuffix(for: document))"
                }
                .joined(separator: "\n")
            append("Available deep documents (titles only)", "\n\(index)", to: &lines)
        }

        if let postCount = meta.topPerformingPosts?.count, postCount > 0 {
            append("Top-performing post transcripts", "\(postCount) available through lookup_client_facts", to: &lines)
        } else if let transcriptCount = meta.topPerformingTranscripts?.count, transcriptCount > 0 {
            append("Top-performing transcripts", "\(transcriptCount) available through lookup_client_facts", to: &lines)
        }

        return lines.joined(separator: "\n")
    }

    private static func append(_ label: String, _ value: String?, to lines: inout [String]) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }
        lines.append("\(label): \(value)")
    }

    private static func joined(_ values: [String]?, limit: Int = 10) -> String? {
        guard let values else { return nil }
        let cleanedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(limit)
        guard !cleanedValues.isEmpty else { return nil }
        return cleanedValues.joined(separator: ", ")
    }

    private static func clipped(_ value: String?, limit: Int) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        guard value.count > limit else { return value }
        return String(value.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func metricsSuffix(for document: ProfileDocument) -> String {
        let metrics = [
            document.likes.map { "\($0) likes" },
            document.shares.map { "\($0) shares" },
            document.saves.map { "\($0) saves" },
            document.comments.map { "\($0) comments" },
            document.leads.map { "\($0) leads" }
        ]
        .compactMap { $0 }

        guard !metrics.isEmpty else { return "" }
        return " (\(metrics.joined(separator: ", ")))"
    }
}

@MainActor
enum CosmoInlineSkillContextResolver {
    static func resolve(
        skillPlan: CosmoInlineAssistantSkillPlan,
        snapshot: CosmoEditableSourceSnapshot?,
        prompt: String,
        resolvedClientAtom: Atom? = nil,
        activeClientUUID: String? = nil,
        inlineContextAtoms: [Atom] = []
    ) async -> CosmoInlineResolvedSkillContext {
        var blocks: [String] = []
        var satisfied: Set<CosmoInlineAssistantSkillContext> = []

        if skillPlan.requiredContext.contains(.clientProfile),
           let clientAtom = await resolveClientAtom(
            prompt: prompt,
            resolvedClientAtom: resolvedClientAtom,
            activeClientUUID: activeClientUUID,
            inlineContextAtoms: inlineContextAtoms
           ),
           let meta = clientAtom.metadataValue(as: ClientProfileMetadata.self) {
            blocks.append("""
            <resolved_context kind="clientProfile" source="compact_profile" clientUUID="\(clientAtom.uuid)">
            \(CosmoCompactClientProfile.format(atom: clientAtom, meta: meta))
            </resolved_context>
            """)
            satisfied.insert(.clientProfile)
        }

        // Voice exemplars: for client-scoped writing/edit work, two excerpts of
        // the client's actual recent posts ride along with the compact profile.
        // Style transfer works by example, not adjectives — the model matches
        // real register and rhythm instead of interpreting "casual but sharp".
        if satisfied.contains(.clientProfile),
           skillPlan.requiresReviewedDiff
            || skillPlan.primarySkill.id == .voiceVariations
            || skillPlan.requiredContext.contains(.bestPerformingContent),
           let clientUUID = (resolvedClientAtom?.uuid
                ?? activeClientUUID
                ?? inlineContextAtoms.first(where: { $0.type == .clientProfile })?.uuid) {
            let exemplars = await voiceExemplars(clientUUID: clientUUID)
            if !exemplars.isEmpty {
                blocks.append("""
                <resolved_context kind="voiceExemplars" clientUUID="\(clientUUID)">
                Recent work in this client's actual voice — match its register, rhythm, and vocabulary when writing for them. Never copy its content or claims.
                \(exemplars.joined(separator: "\n"))
                </resolved_context>
                """)
            }
        }

        // TODO: Resolve .clientMemory compactly from client memory service when available.
        // TODO: Resolve .swipes from selected @ context and swipe search.
        // TODO: Resolve .researchEvidence only when the skill/prompt explicitly needs external facts.

        if let snapshot,
           skillPlan.requiredContext.contains(.activeSurface),
           !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            satisfied.insert(.activeSurface)
        }

        return CosmoInlineResolvedSkillContext(
            blocks: blocks,
            satisfiedContexts: satisfied
        )
    }

    /// Two compact excerpts of the client's most recent posts with real bodies.
    private static func voiceExemplars(clientUUID: String, limit: Int = 2) async -> [String] {
        let recent = (try? await AtomRepository.shared.fetchRecentContent(
            clientProfileUUID: clientUUID,
            limit: 6
        )) ?? []

        return recent
            .compactMap { atom -> String? in
                guard let body = atom.body?.trimmingCharacters(in: .whitespacesAndNewlines),
                      body.count >= 80 else { return nil }
                let flattened = body
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                let excerpt = String(flattened.prefix(400))
                return "- \"\(atom.title ?? "Untitled")\": \(excerpt)\(flattened.count > 400 ? "…" : "")"
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func resolveClientAtom(
        prompt: String,
        resolvedClientAtom: Atom?,
        activeClientUUID: String?,
        inlineContextAtoms: [Atom]
    ) async -> Atom? {
        if let resolvedClientAtom {
            return resolvedClientAtom
        }

        if let contextClient = inlineContextAtoms.first(where: { $0.type == .clientProfile }) {
            return contextClient
        }

        if let activeClientUUID,
           let atom = try? await AtomRepository.shared.fetch(uuid: activeClientUUID),
           atom.type == .clientProfile {
            return atom
        }

        if let clientReference = CosmoExplicitClientReference.firstName(in: prompt),
           let atom = try? await AtomRepository.shared.fuzzyFindClient(query: clientReference) {
            return atom
        }

        return nil
    }
}

enum CosmoClientFactLookup {
    static func snippets(
        meta: ClientProfileMetadata,
        query: String,
        maxSnippets: Int = 3,
        maxSnippetLength: Int = 600
    ) -> [String] {
        let terms = normalizedTerms(query)

        return lookupSources(meta: meta)
            .map { source in
                (
                    score: score(source.content, terms: terms),
                    snippet: snippet(from: source.content, title: source.title, terms: terms, maxLength: maxSnippetLength)
                )
            }
            .filter { $0.score > 0 || terms.isEmpty }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.snippet.count < rhs.snippet.count }
                return lhs.score > rhs.score
            }
            .prefix(maxSnippets)
            .map(\.snippet)
    }

    private static func lookupSources(meta: ClientProfileMetadata) -> [(title: String, content: String)] {
        var sources: [(title: String, content: String)] = []

        appendSource("Brand story", meta.brandStory, to: &sources)
        appendSource("Brand vision", meta.brandVision, to: &sources)
        appendSource("Unique angle", meta.uniqueAngle, to: &sources)
        appendSource("Voice notes", meta.voiceNotes, to: &sources)
        appendSource("Core beliefs", meta.coreBeliefs?.joined(separator: "\n"), to: &sources)
        appendSource("Signature phrases", meta.signaturePhrases?.joined(separator: "\n"), to: &sources)
        appendSource("Best formats", meta.bestFormats?.joined(separator: "\n"), to: &sources)
        appendSource("Posting frequency", meta.postingFrequency, to: &sources)

        for document in meta.documents ?? [] {
            appendSource("\(document.category.displayName): \(document.title)", document.content, to: &sources)
        }

        for (index, transcript) in (meta.topPerformingTranscripts ?? []).enumerated() {
            appendSource("Top transcript \(index + 1)", transcript, to: &sources)
        }

        for (index, post) in (meta.topPerformingPosts ?? []).enumerated() {
            appendSource("Top post \(index + 1)", post.transcript, to: &sources)
        }

        return sources
    }

    private static func appendSource(
        _ title: String,
        _ content: String?,
        to sources: inout [(title: String, content: String)]
    ) {
        guard let content = content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return }
        sources.append((title, content))
    }

    private static func normalizedTerms(_ query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private static func score(_ content: String, terms: [String]) -> Int {
        guard !terms.isEmpty else { return 1 }
        let lower = content.lowercased()
        return terms.reduce(0) { partial, term in
            partial + (lower.contains(term) ? 1 : 0)
        }
    }

    private static func snippet(
        from content: String,
        title: String,
        terms: [String],
        maxLength: Int
    ) -> String {
        let cleaned = content
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        let matchIndex = terms
            .compactMap { term -> String.Index? in lower.range(of: term)?.lowerBound }
            .min()
        let start = matchIndex.map { cleaned.index($0, offsetBy: -80, limitedBy: cleaned.startIndex) ?? cleaned.startIndex } ?? cleaned.startIndex
        let prefix = "\(title): "
        let bodyLimit = max(0, maxLength - prefix.count)
        var body = String(cleaned[start...].prefix(bodyLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if body.count < cleaned[start...].count {
            body += "…"
        }
        let combined = prefix + body
        return combined.count > maxLength ? String(combined.prefix(maxLength)) : combined
    }
}

enum CosmoInlineAssistantResearchIntent {
    static func isWebResearchRequest(_ text: String) -> Bool {
        let lower = text.lowercased()

        if containsAny(lower, [
            "research online", "search online", "look up", "latest", "current",
            "find stats", "statistics", "sources", "citations", "cite",
            "web search", "google", "internet", "online research"
        ]) {
            return true
        }

        return containsResearchVerb(lower) && containsResearchSubject(lower)
    }

    /// A broad, multi-angle research ask about the active piece — "do a ton of
    /// research on this topic", "think of different angles and data points".
    /// Routes to the Deep Research skill (plan → search → synthesize) instead
    /// of the generic Q&A answerer.
    static func isDeepResearchRequest(_ text: String) -> Bool {
        let lower = text.lowercased()

        if containsAny(lower, [
            "deep research", "deep-dive research", "really deep research",
            "ton of research", "lot of research", "bunch of research",
            "research this topic", "research on this topic", "research the topic",
            "research this idea", "research deeper", "research deeply",
            "angles and data points", "different angles", "research pass"
        ]) {
            return true
        }

        // "research" as a whole word plus an explicit breadth/depth cue.
        return containsWholeWord("research", in: lower) && containsAny(lower, [
            "angles", "deeper", "deeply", "thorough", "extensive",
            "everything you can find", "as much as you can"
        ])
    }

    static func shouldOpenPaneForActionExplanation(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return isWebResearchRequest(lower) || containsAny(lower, [
            "explain", "why", "reasoning", "rationale", "source", "sources",
            "citation", "citations", "cite", "show your work", "walk me through"
        ])
    }

    static func shouldRequirePaneExplanation(_ skillPlan: CosmoInlineAssistantSkillPlan?) -> Bool {
        guard let skillPlan else { return false }
        return skillPlan.route == .action && skillPlan.toolBundles.contains(.webResearch)
    }

    private static func containsResearchVerb(_ lower: String) -> Bool {
        containsWholeWord("research", in: lower) ||
        containsWholeWord("search", in: lower) ||
        containsWholeWord("find", in: lower)
    }

    private static func containsResearchSubject(_ lower: String) -> Bool {
        containsAny(lower, [
            " for slide", " for the slide", "slide ", "slides", "fill",
            "number", "numbers", "stat", "stats", "statistics", "cost",
            "costs", "rate", "rates", "market", "benchmark", "examples",
            "information", "details", "data", "angle", "angles", "topic"
        ])
    }

    private static func containsWholeWord(_ word: String, in lower: String) -> Bool {
        lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .contains(word)
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

enum CosmoInlineAssistantSkillRuntime {
    static func plan(
        for prompt: String,
        surfaceKind: CosmoEditableSurfaceKind?,
        previousSkillID: CosmoInlineAssistantSkillID? = nil,
        selectedSkillID: String? = nil,
        registry: CosmoInlineSkillRegistry = CosmoInlineSkillRegistry()
    ) -> CosmoInlineAssistantSkillPlan {
        let lower = prompt.lowercased()
        var skill: CosmoInlineAssistantSkill

        if let selectedSkillID,
           let definition = registry.skill(id: selectedSkillID) {
            skill = definition.assistantSkill()
            return CosmoInlineAssistantSkillPlan(
                primarySkill: skill,
                definitionID: definition.id,
                pipelineSteps: definition.steps?.isEmpty == false ? definition.steps : nil
            )
        } else if isFollowUpLike(lower), let previousSkillID {
            skill = builtInSkill(previousSkillID)
        } else if previousSkillID == .concept {
            // Concept is a multi-turn conversation: a terse answer like
            // "because it compounds" must stay with the concept partner
            // instead of falling through to the edit/research heuristics.
            // The session ends when the user picks another slash skill or
            // the working-context frame expires.
            skill = builtInSkill(.concept)
        } else if previousSkillID == .skillBuilder {
            // The skill builder is a multi-turn interview — short answers like
            // "reels mostly" must stay with the builder, same as Concept.
            skill = builtInSkill(.skillBuilder)
        } else if containsAny(lower, [
            "new skill", "create a skill", "make a skill", "build a skill",
            "create an inline skill", "add a skill", "skill builder"
        ]) {
            skill = builtInSkill(.skillBuilder)
        } else if previousSkillID == .synthesize {
            // Synthesis is a gather → outline → draft conversation; short
            // confirmations ("go", "use that order") must stay in the flow.
            skill = builtInSkill(.synthesize)
        } else if containsAny(lower, [
            "synthesize", "synthesis", "pull together", "draft from my research",
            "newsletter from", "chapter from", "essay from my"
        ]) {
            skill = builtInSkill(.synthesize)
        } else if isProfileBackedOutlineBodyFillLike(lower) {
            skill = profileBackedSlideExpansionSkill()
        } else if isFactFillLike(lower) {
            skill = builtInSkill(.factFill)
        } else if isProfileBackedSlideExpansionEditLike(lower) {
            skill = profileBackedSlideExpansionSkill()
        } else if containsAny(lower, ["variation", "variations", "versions", "alternatives"]) ||
                    (containsAny(lower, ["voice", "tone"]) && containsAny(lower, ["write", "rewrite", "give me", "make"])) {
            skill = builtInSkill(.voiceVariations)
        } else if containsAny(lower, ["feedback", "thoughts on", "critique", "review this", "what's working", "what is working"]) {
            skill = builtInSkill(.contentReview)
        } else if containsAny(lower, ["canvas", "thinkspace", "organize", "reorganize", "arrange", "cluster", "spatial"]) || surfaceKind == .canvas {
            skill = builtInSkill(.canvasOrganize)
        } else if CosmoInlineAssistantResearchIntent.isDeepResearchRequest(lower), !isEditLike(lower) {
            // Broad multi-angle research on the active piece runs the Deep
            // Research skill as a plan → search → synthesize pipeline, so the
            // web sweep can't collapse into a couple of searches plus local
            // recall inside one crowded turn.
            skill = builtInSkill(.ideaResearch)
            return CosmoInlineAssistantSkillPlan(
                primarySkill: skill,
                definitionID: skill.id.rawValue,
                pipelineSteps: deepResearchPipelineSteps()
            )
        } else if containsAny(lower, [
            "find stats", "find data", "supporting evidence", "proof points",
            "research this idea", "back this up", "stats for this", "evidence for this"
        ]) {
            // Evidence-gathering for the active piece routes to the ported
            // Idea-research skill, not the generic Q&A researcher.
            skill = builtInSkill(.ideaResearch)
        } else if CosmoInlineAssistantResearchIntent.isWebResearchRequest(lower), isEditLike(lower) {
            skill = isResearchFillLike(lower) ? builtInSkill(.factFill) : builtInSkill(.inlineEdit)
        } else if CosmoInlineAssistantResearchIntent.isWebResearchRequest(lower) {
            skill = builtInSkill(.researchAnswer)
        } else if isOutlineToBodyEditLike(lower) {
            skill = builtInSkill(.inlineEdit)
        } else if isEditLike(lower) {
            skill = builtInSkill(.inlineEdit)
        } else if containsAny(lower, ["flow", "outline", "storytelling", "step by step", "sequence", "structure this", "good flow"]) {
            skill = builtInSkill(.ideaStrategy)
        } else {
            skill = builtInSkill(.researchAnswer)
        }

        if skill.route == .action,
           CosmoInlineAssistantResearchIntent.isWebResearchRequest(lower) {
            skill.toolBundles.insert(.webResearch)
            skill.panePolicy = .openForResearchBackedAction
            skill.instructions.append(
                "Because the user asked for research-backed facts, use web_search when local/profile context does not already answer the request, then call BOTH propose_workspace_edit and answer_in_assistant_pane in the same tool turn: the staged edit carries your best-supported value, the pane explanation carries the evidence and any alternatives. Research that ends without the staged edit is an incomplete run."
            )
        }

        return CosmoInlineAssistantSkillPlan(primarySkill: skill, definitionID: skill.id.rawValue)
    }

    /// The Deep Research pipeline: plan the angles, execute EVERY search, then
    /// synthesize a dossier. Each step is its own scoped agent turn, so the
    /// web sweep gets a full tool budget instead of competing with local
    /// recall and synthesis inside one turn.
    static func deepResearchPipelineSteps() -> [CosmoInlineSkillStep] {
        [
            CosmoInlineSkillStep(
                name: "Map the angles",
                instructions: [
                    "Read the ACTIVE surface first — for an idea that means its title, angle/body, hooks, and outline; for a draft, the draft text. The user's own material defines the research target; never ask what to research when the surface has content.",
                    "Restate the research target in one line, then design 6-8 angle-distinct web search queries that together would surprise the user: hard statistics and data, current news and policy developments, contrarian or counter-intuitive data, historical precedents, expert commentary, and audience sentiment. Fold in the client's niche as an angle when a client profile is present.",
                    "Each query gets one line: the exact query text, the searchType you will use for it (web, news, reddit, or academic), and a half-line on what that angle could unlock for the piece.",
                    "Do NOT run any web searches in this step — the next step executes the plan. Deliver the numbered plan via answer_in_assistant_pane."
                ],
                toolBundles: [.contentSearch],
                preferredModelTier: .strategist,
                outputContract: "pane_research_plan"
            ),
            CosmoInlineSkillStep(
                name: "Run the searches",
                instructions: [
                    "Execute EVERY query from the step-1 plan with web_search — batch them by passing several angle-distinct queries in one call via the `queries` array, using the searchType each angle calls for. Never skip planned angles because early results feel sufficient; the whole point of this run is breadth.",
                    "After the web sweep, do ONE pass over the user's own corpus (synthesize_knowledge or recall) to pull saved material that connects to the findings. The knowledge base complements the web sweep — it never substitutes for it.",
                    "Deliver a compact digest via answer_in_assistant_pane: for each angle, the strongest 1-2 findings with their source names and URLs. Flag any angle that came back empty so the synthesis step knows."
                ],
                toolBundles: [.webResearch, .contentSearch],
                preferredModelTier: .strategist,
                outputContract: "per_angle_findings_digest"
            ),
            CosmoInlineSkillStep(
                name: "Synthesize the dossier",
                instructions: [
                    "Work only from the findings already in this conversation — do not run new searches unless a planned angle failed and one retry with a sharper query could fill it.",
                    "Deliver 8-12 deduplicated findings via answer_in_assistant_pane, each tagged with its proof type: Statistic, Case Study, Expert Quote, Social Proof, Analogy, Contrarian Data, Historical Precedent, or Scientific Study. Each finding: short title, a 2-3 sentence summary carrying the key data point, the source name, and the URL when known. Never invent statistics, sources, or URLs — a finding you cannot source does not ship.",
                    "Prefer contrarian and surprising data when the evidence supports it — those make hooks. Name the single strongest finding for this piece and say why in one line.",
                    "End by offering to stage any finding into the surface via propose_workspace_edit (a supporting line under the angle, or a stat-led hook); stage only after the user picks one."
                ],
                toolBundles: [.workspaceEditing, .contentSearch],
                preferredModelTier: .strategist,
                outputContract: "pane_evidence_findings_then_optional_reviewed_insertion"
            )
        ]
    }

    private static func profileBackedSlideExpansionSkill() -> CosmoInlineAssistantSkill {
        var skill = builtInSkill(.inlineEdit)
        skill.name = "Profile-backed Inline Edit"
        skill.description = "Stages slide/draft edits using client profile, voice, and best-performing content context."
        skill.requiredContext.formUnion([
            .clientProfile,
            .clientMemory,
            .voiceLessons,
            .swipes,
            .bestPerformingContent
        ])
        skill.toolBundles.formUnion([
            .clientProfiles,
            .clientMemory,
            .swipes,
            .analytics,
            .strategy,
            .writing,
            .contentSearch
        ])
        skill.instructions.append(
            "When the user asks to use a profile, best-performing posts, reels, swipes, or exact voice/structure while also asking to add/fill slides or a draft, this is still an edit task. Read the existing slide content as the lead-in, inspect the available profile/swipe context, then stage the new or changed slide content as reviewed diffs instead of asking which angle to take."
        )
        skill.instructions.append(
            "The outline is the source of truth when the user asks to put an outline into the body/slides. Preserve the outline's order, intent, and storytelling/explanation shape; use profile, swipe, and best-performing examples only to fill placeholders, facts, format cues, and light wording gaps."
        )
        skill.instructions.append(
            "Do not copy, transplant, or re-template a best-performing post unless the user explicitly asks for a 1:1 copy or structure match. Best-performing posts are reference material, not the replacement draft."
        )
        skill.instructions.append(
            "For slide-specific instructions, follow the user literally even if a best-performing example uses a different structure."
        )
        skill.instructions.append(
            "If multiple source angles are available, choose the one that best continues the current draft and mention that source in the rationale; do not ask a clarification question unless there is no editable target or no relevant context can be found."
        )
        skill.tokenBudget = max(skill.tokenBudget, 2200)
        skill.preferredModelTier = .strategist
        skill.panePolicy = .neverForAction
        return skill
    }

    static func builtInSkill(_ id: CosmoInlineAssistantSkillID) -> CosmoInlineAssistantSkill {
        switch id {
        case .contentReview:
            return CosmoInlineAssistantSkill(
                id: .contentReview,
                name: "Content Review",
                description: "Reviews the active content with client voice, swipe, strategy, and performance context.",
                route: .answer,
                requiredContext: [.activeSurface, .currentFocus, .clientProfile, .clientMemory, .voiceLessons, .swipes, .bestPerformingContent, .workspaceMemory],
                toolBundles: [.workspaceEditing, .contentSearch, .clientProfiles, .clientMemory, .swipes, .strategy, .writing, .analytics],
                outputContract: "pane_review_card",
                instructions: [
                    "Read the active draft or focus surface before judging it.",
                    "Load the relevant client profile, voice lessons, and saved memory when the prompt names or implies a client.",
                    "Check relevant swipes or best-performing examples before giving taste-level feedback.",
                    "Give a concrete diagnosis first, then specific improvements and optional rewrite snippets.",
                    "If the user asks you to change the workspace, stage reviewed edits instead of only giving advice."
                ],
                tokenBudget: 2200,
                requiresReviewedDiff: false,
                icon: "text.badge.checkmark",
                summary: "Reviews the open draft against real swipe transcripts and their engagement numbers — performance read, slide notes, top moves.",
                triggerPhrases: ["review", "feedback", "content feedback"],
                preferredModelTier: .strategist,
                panePolicy: .openForAnswer
            )
        case .critique:
            return CosmoInlineAssistantSkill(
                id: .critique,
                name: "Critique",
                description: "Judges the draft against the learned taste profile and stages surgical fixes as reviewed edits.",
                route: .action,
                requiredContext: [.activeSurface, .currentFocus, .clientProfile, .voiceLessons, .bestPerformingContent],
                toolBundles: [.workspaceEditing, .contentSearch, .clientProfiles, .writing, .strategy],
                outputContract: "reviewed_diff",
                instructions: [
                    "Judge the active draft ONLY against the LEARNED TASTE block (pinned rules and beliefs) and the draft's own intent signal (title, dek, format, client niche). No generic writing advice.",
                    "Check pinned [RULE] entries first — a violated pinned rule is always worth an edit. Beliefs are strong defaults; cite the one you are enforcing.",
                    "Stage at most 6 surgical operations in a single propose_workspace_edit call. For each change, set originalText to the ENTIRE line/sentence containing the target (copied verbatim) and proposedText to that line with only the fix — never a short fragment.",
                    "Every operation's rationale names the specific taste belief or intent mismatch it fixes (e.g. 'pinned rule: never open with a rhetorical question'). No rationale, no edit.",
                    "Silence over noise: if the draft already honors the taste profile, stage NOTHING and reply in one sentence that it holds up, naming its strongest beat. Never invent cosmetic edits to look useful.",
                    "If no taste profile exists for this scope yet, say so plainly and point at the Profile Studio Taste section — do not critique from general knowledge.",
                    "Respect slide-delimited structure; keep all unaffected lines byte-for-byte identical."
                ],
                tokenBudget: 1600,
                requiresReviewedDiff: true,
                icon: "checkmark.seal",
                summary: "Holds the draft up against your learned taste — pinned rules first — and stages at most six surgical fixes as reviewed edits.",
                triggerPhrases: ["critique", "crit", "taste check", "hold it against my taste"],
                preferredModelTier: .strategist,
                panePolicy: .neverForAction
            )
        case .voiceVariations:
            return CosmoInlineAssistantSkill(
                id: .voiceVariations,
                name: "Voice Variations",
                description: "Generates multiple rewrites in a client or creator voice using profile and voice examples.",
                route: .answer,
                requiredContext: [.activeSurface, .clientProfile, .clientMemory, .voiceLessons, .swipes, .bestPerformingContent],
                toolBundles: [.workspaceEditing, .contentSearch, .clientProfiles, .clientMemory, .swipes, .writing, .strategy],
                outputContract: "pane_variations_card",
                instructions: [
                    "Load the client voice/profile before writing variations.",
                    "Use swipes, prior posts, or saved voice lessons to infer phrasing instead of generic style labels.",
                    "Return distinct options with short labels so the user can compare direction quickly.",
                    "Keep the user's meaning intact unless they explicitly ask for a bigger rewrite.",
                    "Offer to stage one option as a reviewed inline edit when the active surface is editable."
                ],
                tokenBudget: 1800,
                requiresReviewedDiff: false,
                icon: "quote.bubble",
                summary: "Riffs 5–7 variations on one beat you're stuck on, each borrowing a pattern from a real comparable — reply `apply N` to stage one.",
                triggerPhrases: ["riff", "vary", "variations", "voice", "rewrite options", "versions"],
                preferredModelTier: .strategist,
                panePolicy: .openForAnswer
            )
        case .inlineEdit:
            return CosmoInlineAssistantSkill(
                id: .inlineEdit,
                name: "Inline Edit",
                description: "Stages reviewed edits against the active editable surface.",
                route: .action,
                requiredContext: [.activeSurface, .currentFocus, .workspaceMemory],
                toolBundles: [.workspaceEditing, .contentSearch, .writing, .strategy],
                outputContract: "reviewed_diff",
                instructions: [
                    "Use the active editable surface, target ID, anchors, and source hash.",
                    "Be decisive and act in one model/tool pass when the needed context is already provided.",
                    "Call propose_workspace_edit for visible edits; never mutate the workspace directly.",
                    "Put ALL edits in a single propose_workspace_edit call. For each change to existing text, set originalText to the ENTIRE line/sentence containing the target (copied verbatim) and proposedText to that line with only the requested change — never a short fragment, which fails to locate and dumps the change at the bottom. Use textInsertion (anchored via originalText) only for brand-new content.",
                    "Respect slide-delimited/source-delimited structure. If the user says one slide/section, only target that slide/section unless they explicitly ask for broader changes.",
                    "When inserting outline points into existing slide bodies, do not include a new SLIDE N heading in proposedText if the insertion anchor is already that SLIDE N heading. Insert only the body copy that belongs under the existing header.",
                    "If the user asks to add slides, fill a step-by-step, or make the draft match a referenced profile/swipe structure, treat it as actionable. Use the existing slides as the lead-in and stage the added slide content; do not ask the user to choose an angle unless the target surface or required context is genuinely missing.",
                    "When you insert a new item into a numbered series (a new slide between existing SLIDE N headers, or a new step in a step-by-step list), keep the numbering sequential and unique: number the new item correctly and add a textReplacement operation to bump every following item up by one (old SLIDE 7 to SLIDE 8, Step 5 to Step 6). Never use a fractional number like SLIDE 6.5 and never leave a duplicate number.",
                    "Group changes into reviewable operations with precise rationales.",
                    "Do not open the pane for edit-only work unless the user also asked for an explanation or the edit cannot be staged."
                ],
                tokenBudget: 1400,
                requiresReviewedDiff: true,
                icon: "pencil.and.scribble",
                summary: "Stages precise reviewed edits against the active workspace surface.",
                triggerPhrases: ["edit", "rewrite", "change", "update"],
                preferredModelTier: .sensor,
                panePolicy: .neverForAction
            )
        case .factFill:
            return CosmoInlineAssistantSkill(
                id: .factFill,
                name: "Fact Fill",
                description: "Replaces placeholders or numbers using profile, memory, research, and source-backed evidence.",
                route: .action,
                requiredContext: [.activeSurface, .clientProfile, .clientMemory, .researchEvidence, .workspaceMemory],
                toolBundles: [.workspaceEditing, .contentSearch, .clientProfiles, .clientMemory, .strategy, .writing],
                outputContract: "source_backed_reviewed_diff",
                instructions: [
                    "Resolve the named client or active profile before changing facts or numbers.",
                    "Use pre-resolved compact client profile facts when they are provided in the system prompt. Do not call get_client_profile when those facts answer the request.",
                    "Call lookup_client_facts only for a specific missing detail not present in the compact profile block. Use web research only if local/profile evidence is missing or the user explicitly asks for current outside research.",
                    "Be decisive and act in one model/tool pass when the needed facts are already provided.",
                    "Never invent stats, revenue, deals, performance metrics, or personal history.",
                    "Only replace placeholders, blank slots, obvious variables, and factual-number fragments the user asked you to fill.",
                    "Do not rewrite hooks, claims, slide framing, or user-written copy unless the user explicitly says rewrite, rework, change the wording, make it better, or asks for variations.",
                    "When filling one slide, keep all unaffected lines byte-for-byte the same and only change the requested slide.",
                    "Stage ALL factual replacements in a single propose_workspace_edit call. For each, set originalText to the ENTIRE line/sentence containing the placeholder/number (copied verbatim) and proposedText to that line with only the value filled in — never just the bare number, which fails to locate and dumps the change at the bottom. Include the source/evidence in the rationale.",
                    "When the evidence supports multiple candidate values, stage the best-supported one and note the alternatives briefly in the rationale or pane explanation — never end the run asking which value to use; the review diff is where the user decides.",
                    "If evidence is missing entirely, leave a clear placeholder and say what data is missing instead of guessing."
                ],
                tokenBudget: 1200,
                requiresReviewedDiff: true,
                icon: "number",
                summary: "Fills placeholders and factual details without rewriting surrounding copy.",
                triggerPhrases: ["fill facts", "numbers", "placeholders", "fact fill"],
                preferredModelTier: .sensor,
                panePolicy: .neverForAction
            )
        case .researchAnswer:
            return CosmoInlineAssistantSkill(
                id: .researchAnswer,
                name: "Answer",
                description: "Answers questions with workspace, memory, profile, or external research context.",
                route: .answer,
                requiredContext: [.activeSurface, .currentFocus, .workspaceMemory, .researchEvidence],
                toolBundles: [.workspaceEditing, .contentSearch, .clientProfiles, .clientMemory, .swipes, .strategy, .webResearch],
                outputContract: "pane_answer_card",
                instructions: [
                    "Use workspace/profile/search tools when the answer depends on Cosmo data or current facts.",
                    "When the user explicitly asks you to research, look something up, or wants current outside facts, web_search is the primary instrument: run at least two differently-angled queries (pick searchType per angle — web, news, reddit, academic; batch them via the `queries` array) before answering. Workspace knowledge complements the web on an explicit research ask — it never substitutes for it.",
                    "Show the actual answer in answer_in_assistant_pane, even if the pane is opened later.",
                    "Distinguish known facts from inference and cite retrieved titles or source names naturally.",
                    "If you cannot find enough evidence, say exactly what you checked."
                ],
                tokenBudget: 1800,
                requiresReviewedDiff: false,
                icon: "globe",
                summary: "Answers with workspace, profile, memory, and web research when needed.",
                triggerPhrases: ["research", "answer", "look up", "explain"],
                preferredModelTier: .strategist,
                panePolicy: .openForAnswer
            )
        case .canvasOrganize:
            return CosmoInlineAssistantSkill(
                id: .canvasOrganize,
                name: "Organize Workspace",
                description: "Reads the whole thinkspace and stages a reviewed plan that gathers blocks into named, intentful clusters.",
                route: .action,
                requiredContext: [.canvasState, .currentFocus, .workspaceMemory],
                toolBundles: [.workspaceEditing, .canvasSpatial, .contentSearch, .strategy],
                outputContract: "canvas_reviewed_plan",
                instructions: [
                    "The thinkspace surface digest in your context lists every block (with uuid and current cluster) and every cluster (with intent) — read it FIRST; do not call tools to rediscover what it already says.",
                    "Group by theme and working intent, never merely by type: mental-model connections that share a subject belong together, and source videos cluster with the connections they feed.",
                    "Prefer a few meaningful clusters over many thin ones; leave genuinely unrelated blocks unclustered rather than forcing them.",
                    "Stage ONE propose_canvas_plan using create_cluster (name + one-sentence intent + blockUUIDs copied exactly from the digest) and move_to_cluster for existing clusters.",
                    "Every cluster name says what it collects ('Solipsism mental models', not 'Group 1'); the intent sentence is what future organizing reads.",
                    "Explain the shape of the plan in the pane in one or two Cosmo-voice lines — the piles and why — then let the plan card do the rest."
                ],
                tokenBudget: 2400,
                requiresReviewedDiff: true,
                icon: "square.grid.2x2",
                summary: "Stages a reviewed cluster plan for the open thinkspace — themes, names, and intents.",
                triggerPhrases: ["organize canvas", "reorganize", "arrange canvas", "organize my workspace", "organize this thinkspace", "clean up this canvas"],
                preferredModelTier: .sonnet5,
                panePolicy: .alwaysOpenWithResult
            )
        case .ideaStrategy:
            return CosmoInlineAssistantSkill(
                id: .ideaStrategy,
                name: "Idea Strategy",
                description: "Shapes flow, outline, hooks, and story sequence for the active idea or content piece.",
                route: .answer,
                requiredContext: [.activeSurface, .currentFocus, .clientProfile, .clientMemory, .swipes, .bestPerformingContent, .voiceLessons],
                toolBundles: [.workspaceEditing, .contentSearch, .clientProfiles, .clientMemory, .swipes, .strategy, .writing, .analytics],
                outputContract: "pane_strategy_card",
                instructions: [
                    "Read the current idea, outline, hooks, and active content before recommending structure.",
                    "Load client profile and best-performing examples when the user names a creator/client.",
                    "Give a clear recommended flow, then explain why it fits the audience and voice.",
                    "Use concrete step-by-step beats rather than generic framework names.",
                    "If the user wants changes applied, stage reviewed edits after the explanation."
                ],
                tokenBudget: 2400,
                requiresReviewedDiff: false,
                icon: "point.3.connected.trianglepath.dotted",
                summary: "Builds flow, outline, and story strategy for an active idea or content piece.",
                triggerPhrases: ["flow", "outline", "strategy", "storytelling"],
                preferredModelTier: .strategist,
                panePolicy: .openForAnswer
            )
        case .concept:
            return CosmoInlineAssistantSkill(
                id: .concept,
                name: "Concept",
                description: "Concept-development partner: develops a Concept through one-question-at-a-time socratic dialogue, observations, and staged section drafts.",
                route: .answer,
                requiredContext: [.activeSurface, .currentFocus, .workspaceMemory],
                toolBundles: [.workspaceEditing, .contentSearch],
                outputContract: "pane_concept_turn_plus_optional_reviewed_diff",
                instructions: [
                    "You are a thought partner mining for what is uniquely the user's in an idea. If the active editable surface is a Connection (its surface text starts with a `# Title` line followed by `Type:` and `## Section` headers), that connection is the working concept. Otherwise ask one question to name the concept being developed, then call create_connection — seeding one bullet per distinct point the opening message actually contains, each into its best section (usually just one; never fan a single point across several sections) — and continue developing the connection it opens.",
                    "CAPTURE EVERYTHING THEY SAID, NOTHING THEY DIDN'T. Before replying, inventory the user's message: list every distinct substantive point they actually made (a claim, an example, a story, a belief or objection, a process step, an open question — each is one point, and two examples are TWO points even when they back the same claim). Capture ALL of them this turn — each point becomes 1-2 bullets in the single section it best belongs to, staged together in ONE propose_workspace_edit call with one operation per section touched. Points that develop a DIFFERENT concept the user brought up route through stage_on_concept instead (a point that genuinely develops both concepts is staged both places). A short message usually yields one point and one section; a rich message can legitimately fill three or four sections, and skipping a real point loses the user's thinking — they notice, and they have to tell you to go back, which defeats the partnership. The dump you must never do is the opposite failure: inventing points they didn't make to fill sections, fanning ONE point across several sections, or seeding the whole concept with your own material — the count comes from how many distinct points THEY gave, never from a desire for a full board. If they gave nothing concrete yet, stage nothing and just ask the one question. Self-check before staging: re-read their message once more; any substantive point still un-staged that belongs on the board is a miss — add it now.",
                    "NEVER MERGE DISTINCT POINTS. Two statements are distinct points when they name different scenarios, subjects, instances, or angles — even when they support the same claim. Two examples offered after one point are TWO board entries, one bullet each, never a fused summary bullet; merging them deletes the specificity that made each one worth giving. The ONLY thing you may condense is genuine redundancy: when the user circles the SAME point in several wordings (a rant restating one idea), capture it once as its clearest version. The test before turning two sentences into one bullet: could each sentence stand alone as its own useful board entry? If yes, stage them separately. WORKED EXAMPLE — the user says: 'Stressing about a future exam brings the imagined failure into the present. And replaying a past trauma as if it's happening now creates that pain again right now.' GOOD (two bullets in Examples): '- Stressing over a future exam brings the imagined experience of failing into the present.' plus '- Replaying a past trauma as if it is happening now recreates the pain in the present.' TOO FAR (one fused bullet): '- Dragging the past or future into the present manufactures pain.' The fused version is a generalization the user never wrote; it destroys both examples.",
                    "OTHER CONCEPTS ARE WITHIN REACH. When the user connects the working concept to another concept of theirs ('wait, this relates to my X concept because...') and expands on WHY, that expansion is board material for BOTH pages, not just a References link here. Inventory their message as usual, then split the routing: points about the working concept stage here via propose_workspace_edit; points that develop the OTHER concept stage onto it via stage_on_concept, resolving its uuid from the attached context, the References section, or recall (never invent one). Where the cross-link strengthens a staged bullet, write a mention token @[<working concept title>](connection:<working uuid>) inside its text so the other board keeps the thread back to this one. A point that genuinely develops both concepts is staged BOTH places, phrased for each board. Only stage onto concepts the user themselves brought into the conversation, and describe the result as material waiting on that board for review the next time they open it, never as added. WORKED EXAMPLE — while developing 'Experience & inquiry' the user says: 'Wait, this links to my Feedback Loop of Awareness concept: because of that loop, projecting a future scenario affects your ability to act right now.' You stage the References link here, stage the projection-affects-action point into Problems HERE via propose_workspace_edit, AND call stage_on_concept targeting Feedback Loop of Awareness with a Problems bullet like '- Projecting a future scenario through the loop affects your present ability to act; developed in @[Experience & inquiry](connection:<uuid>)'. Skipping the other board loses half the thought.",
                    "A turn that stages bullets is NOT finished until you have ALSO called answer_in_assistant_pane in that SAME turn: one short reaction beat plus exactly ONE deepening question. Never end a turn on a staging call alone — the user then sees a dead-end receipt and has to prompt you to continue, which defeats the whole partnership. The question is how the concept keeps developing when the user has no inspiration of their own; they can always ignore it and steer elsewhere. The only turn that ends without a question is one where the concept is genuinely complete and you say so.",
                    "SOUND LIKE A PERSON, NOT A PROCESS. You are a sharp friend who is genuinely interested, not an analyst narrating a method. Never narrate what you are about to do ('Before I go further...', 'I want a concrete case to test them against', 'Let me capture that', 'Now let's...'), and never describe the conversation itself in analyst language ('the abstract version', 'locked in', 'we've established'). React to what they said in one short, specific beat the way a person would, then ask your question as natural curiosity. WORKED EXAMPLE, after capturing two claims: ROBOTIC (never): 'Got the two claims locked in. Before I go further, I want a concrete case to test them against, not just the abstract version. Where have you actually seen this play out?' HUMAN (yes): 'That second one feels like the sharper claim. Where have you actually seen this happen, a specific stretch where the thing you were obsessing over started feeding you ideas back?' The question carries the intelligence; the reaction is one warm, specific beat, never a generic compliment.",
                    "Pick the sharpening question that pushes the idea one step further: vague idea → 'What specifically about this is interesting to you?'; observation → 'What would you do with this?'; business/product idea → 'What problem does this solve?'; question → 'What's your instinct on the answer?'; connection between things → 'What's the link you're seeing?'; reaction → 'What would the better version look like?'.",
                    "Use four development drivers (never announce them by name). Pattern: gaps between their approach and the standard one — 'I notice you emphasize X while most people focus on Y'. Paradox: counterintuitive truths — when they get better results doing the opposite of conventional wisdom, dig in immediately; paradoxes are gold. Name: when a concept they use is unnamed, test names ('Does \"[name]\" capture this?') and don't move on until it has at least a working title — stage it into the Concept Name section. Contrast: 'you do X while everyone else does Y' — help them see why the difference matters.",
                    "Match tone to the Type line of the connection: Mental Model → socratic and probing; Framework → rigorous, press for coherent parts and clear ordering; Principle → press for universality and counter-examples; Doctrine → assertive, help them state claims boldly; Heuristic → pragmatic, press for 'when does this fail?'; Law of Nature → empirical, press for mechanism and prediction.",
                    "If the connection is blank or barely started, invite the messy core idea — one sentence, a link, a half-formed question, doesn't matter. If it already has material, begin from what is written and never ask a question the surface text already answers.",
                    "ORGANIZE THEIR THINKING, DON'T AUTHOR IT. The user's thoughts are often scattered; your real value is turning them into clean, well-formed bullets they instantly recognize as THEIR idea, just sharper and better organized. So you SHOULD reword for clarity, tighten rambling into a crisp sentence, fix grammar, keep their vivid phrasing, and pick the right section. The one hard line is SUBSTANCE: capture only the point they actually made. Do NOT add a claim, mechanism, cause, contrast, or example of your own, and don't dress it up with rhetorical flourishes (the 'not X, it's Y' reframe, dramatic asides) that make it read as authored-by-AI rather than said-by-them. Polish the phrasing; never invent the content. NEVER use em dashes anywhere: not in a bullet, and not in your chat replies. Use a comma, a period, or a semicolon instead. If a section needs substance the user hasn't given, do NOT fabricate it — ask a question that pulls it out of them. WORKED EXAMPLE — the user says, scattered: 'yeah like doing one thing at a time, when I actually do that I feel way calmer, less all over the place'. GOOD (organized, their point, tightened): 'Doing one thing at a time makes me feel calmer and less scattered.' TOO FAR (invented a thesis + mechanism they never stated): 'Doing one thing at a time isn't a productivity trick — it's the mechanism behind feeling calm and present.' The GOOD version reorganizes and cleans up; the TOO FAR version adds an argument they didn't make. Self-check before staging: is this their own point, just clearer? Or did I slip in an idea, a contrast, or a flourish they didn't offer? If I added substance, cut it back to what they said.",
                    "Stage captures as a reviewed diff via ONE propose_workspace_edit call per turn: one operation per contiguous change (a turn capturing into three sections has three operations in the same call, and a call may mix textInsertion captures with textReplacement revisions). Insertions: kind textInsertion, proposedText as `- ` bullet lines (one bullet per item), originalText set to the anchor copied verbatim from the surface text. PLACEMENT MATTERS in ordered sections: anchoring the exact section header line (e.g. `## Claims`) drops the bullets at the top of that section; anchoring an exact existing bullet line inserts right after that bullet. A Process step that happens between two existing steps is anchored on the step it follows, never appended at the header. Never claim an insertion happened without staging it, never restate a whole section, and never mix two sections' bullets in one operation.",
                    "THE BOARD IS EDITABLE, CONSERVATIVELY. When a newly captured point changes how an EXISTING entry reads, you may revise that entry: one textReplacement operation per entry, originalText = the entry's exact bullet line copied verbatim from the surface text, proposedText = the minimally revised `- ` line. It renders as a ghost row showing old wording struck through above the new, so say the revision is waiting for review, never that it was made. The bar is NECESSITY, not improvement: revise only when the new material makes a neighboring entry factually wrong, strands its ordering, or breaks a reference it makes; keep every word you can. Most turns need ZERO revisions. Never restyle, never reword for taste, never touch entries the new point doesn't affect; the organize-don't-author law applies doubly to bullets the user already accepted onto their board, and revision wording must come from what the user said, not from your own improvements. When you do revise, your pane reply names which entry you adjusted and why, in one clause. WORKED EXAMPLE — Process reads '- Pick one task.' then '- Work until the timer ends.' The user adds a step between them: 'you should set a 25 minute timer before starting'. Stage ONLY the insertion anchored on '- Pick one task.'; the neighbor still reads correctly, so no revision. COUNTER-EXAMPLE where revision IS forced: the user says 'between picking the task and working, break the task into subtasks; the work step is then just working through those one by one'. The second half redefines the existing work bullet, so stage the insertion PLUS one textReplacement revising '- Work until the timer ends.' to '- Work through the subtasks one by one.', both built from their own words.",
                    "HYPERLINK OTHER PAGES WITH MENTION TOKENS. When a staged bullet references another concept, note, or idea the user named (or one you found via search), write the reference as a mention token inside the bullet text: @[Exact Title](connection:<uuid>) — the uuid comes from the attached context or your search results, and the type prefix matches the atom (connection, note, idea, research). The token renders as a tappable @Title link once accepted. To add a pure link row (e.g. the user says 'hyperlink this concept'), stage a bullet that is ONLY the token — it lands as a first-class link row in References or the section they named. Never invent a uuid: if you don't have the target's uuid, search for it first, and if it can't be found, write the plain title and say the link target wasn't found.",
                    "EVIDENCE IS A PROBE, NEVER A DUMP. The user's research corpus is available via pull_evidence: call it when the concept grew out of research, when the user makes a claim their captures could support or contradict, or when they ask what they have. Use what comes back as conversation instruments in their own words: 'you captured X from the Huberman video — does that support this claim, or complicate it?'. When the user affirms a piece belongs on the page, stage ONE bullet into the Evidence section via propose_workspace_edit, quoting the capture with its source name. Never insert evidence they did not accept, and never bulk-file the whole corpus.",
                    "OBJECTIONS HAVE A LIFECYCLE. In the surface text, a Beliefs & Objections bullet followed by an indented `↳ handled:` line is RESOLVED — the user already wrote that rebuttal (sometimes citing another board entry after 'answered by'). Treat handled objections as settled unless the user reopens them; when the resolution looks thin, say specifically what it fails to cover. Objections WITHOUT a `↳ handled:` line are live: these are the ones to probe ('the strongest version of this objection is X, how does your framework survive it?'). When the user asks you to handle one, or agrees to a rebuttal you drafted ('yes, use that'), call handle_objection quoting the objection verbatim plus the agreed response (and quote answering board entries in linked_entries when an example or evidence bullet does the work) — it stages a ghost thread under the objection for THEIR ✓, so say it's waiting for review, never that the objection is handled. Never call it unprompted: drafting in conversation first is the move.",
                    "MEDIA IS A REFERENCE, NEVER A DUMP. The board's Gallery block in the surface text lists the media already attached (read-only: you cannot insert lines there). When the user asks for visual examples ('find reels about this', 'add that Hormozi video') or a section clearly wants a real-world post, call attach_media with the concept's own vocabulary — it stages ghost tiles the user reviews per-tile, so say the media is 'waiting in your gallery for review', never that it was added. Give one line per staged tile on why it earns its place. An empty result means the library has nothing relevant: say so plainly, never invent a post.",
                    "Challenge generic claims ('I care more about quality') with follow-ups until something specific and memorable appears. Don't compliment — observe, challenge, or dig deeper. When something is genuinely original, name what makes it original.",
                    "When the user hits a genuine unknown — 'I'm not sure', 'I don't know actually', 'let's start a question around X', 'I'd have to find out' — that is a fork, not a dead end. Sharpen the unknown into ONE researchable question phrased the way they'd ask it (refine the wording with them first if it's vague), then stage it with propose_inquiry_question, passing a one-sentence rationale tying the question to this concept. A confirmation card appears in the pane; the inquiry session opens only if the user confirms — never claim it started. After staging, acknowledge the question is ready in one clause and keep the concept conversation moving.",
                    "Never use canned filler like 'What's the tension?' unless the user used that language first.",
                    "Keep prose to 2-4 sentences, conversational, not a questionnaire. Always deliver the conversational reply via answer_in_assistant_pane — even on turns that also stage drafts — and that reply ends with your one follow-up question."
                ],
                tokenBudget: 2200,
                requiresReviewedDiff: false,
                icon: "diamond",
                summary: "Develops a concept with you — socratic questions, sharp observations, drafts staged into Concept sections.",
                triggerPhrases: ["concept", "develop concept", "crystallize", "deepen"],
                preferredModelTier: .sonnet5,
                panePolicy: .openForAnswer
            )
        case .skillBuilder:
            return CosmoInlineAssistantSkill(
                id: .skillBuilder,
                name: "New Skill",
                description: "Conversational skill builder: interviews briefly, drafts a complete skill definition with examples, dry-runs it against the active surface, then saves it via create_inline_skill.",
                route: .answer,
                requiredContext: [.activeSurface, .workspaceMemory],
                toolBundles: [.workspaceEditing, .contentSearch],
                outputContract: "pane_skill_spec_then_create_inline_skill",
                instructions: [
                    "You are designing a reusable inline skill WITH the user — a contract, not a prompt snippet. A great skill declares when it triggers, what context it needs, what its output looks like, and how to verify that output before staging.",
                    "Interview with at most FOUR questions across the conversation, ONE per turn, and skip any the user already answered: (1) What should the skill do, concretely? (2) When should it trigger — in the user's own words, as they'd type it? (3) What does great output look like — ask them to paste or point at one real example they love. (4) What context does it need (client voice? swipes? research evidence? just the surface)?",
                    "From their answers draft the complete definition and show it in the pane as a compact spec: name, one-line summary, trigger description (a single sentence in the user's vocabulary — this drives automatic routing), route (action stages diffs / answer goes to pane), model tier (sensor for precise mechanical edits, strategist for judgment and voice work), required context, 2-4 concrete instructions, and one input→ideal-output example distilled from the material they shared. Examples teach more than instructions — never save a skill without at least one.",
                    "Include a one-line verification rule when the skill can fail quietly (e.g. 'no invented metrics', 'every slide keeps its SLIDE N header').",
                    "DRY-RUN before saving: when the active surface has text and the skill's route is action, apply the draft skill's instructions to the live surface yourself and stage the result with propose_workspace_edit so the user sees the actual diff this skill would produce. For answer-route skills, produce one sample answer in the pane. Skills are born tested — never save one the user hasn't seen run.",
                    "Iterate on their feedback. When the user confirms (yes / save it / create it / add it), call create_inline_skill with the full definition including the example baked into instructions, then confirm in one line how to invoke it (/Name or by just typing a matching request).",
                    "Keep every pane turn short — the spec card plus one question or one confirmation ask. No meta-lectures about what skills are."
                ],
                tokenBudget: 2400,
                requiresReviewedDiff: false,
                icon: "wand.and.stars",
                summary: "Builds a new slash-menu skill with you — interview, draft, dry-run on the live surface, save.",
                triggerPhrases: ["new skill", "create skill", "make a skill", "build a skill", "skill builder"],
                preferredModelTier: .strategist,
                panePolicy: .alwaysOpenWithResult
            )
        case .synthesize:
            return CosmoInlineAssistantSkill(
                id: .synthesize,
                name: "Synthesize",
                description: "Turns saved research into a structured, cited draft: gather sources from the second brain, propose an outline, then draft section by section as reviewed diffs.",
                route: .answer,
                requiredContext: [.activeSurface, .currentFocus, .workspaceMemory, .researchEvidence],
                toolBundles: [.workspaceEditing, .contentSearch, .strategy, .writing, .webResearch, .navigation],
                outputContract: "gather_then_outline_then_sectioned_reviewed_diffs",
                instructions: [
                    "This is the whole point of Cosmo: research → save → structure → synthesize. You are turning the user's saved atoms into a coherent output (newsletter, chapter, essay, thread) — grounded in THEIR material, in THEIR thinking, never generic filler.",
                    "GATHER first: call recall (multiple angles if needed — by topic, by source name, by adjacent concepts) to collect the relevant ideas, notes, research, and connections. Read the ambient related-work digest before searching — it is often most of the answer. Tell the user what you found as a compact source list (titles + one-line relevance) and ask only ONE question if scope is genuinely ambiguous; otherwise proceed.",
                    "STRUCTURE second: propose an outline in the pane — sections with a one-line intent each and which sources feed which section. Wait for a nod (or 'go') before drafting. If the user gave a structure, use theirs.",
                    "DRAFT third, SECTION BY SECTION: stage each section as its own propose_workspace_edit insertion into the active surface (anchored to the previous section or the matching heading). One section per proposal — small reviewable diffs, never a 5,000-token wall. After each staged section, continue to the next without waiting unless the user rejected the last one.",
                    "CITE as you go: each section's rationale names the source atoms (titles) it drew from, so every claim is traceable back to the user's own research.",
                    "Synthesis means finding the through-line ACROSS sources — tensions, patterns, the argument the user has been circling — not summarizing each source in turn. When two sources disagree, say so and use it.",
                    "Never invent facts, quotes, or numbers that aren't in the gathered sources. A gap in the research is stated as a gap (and is allowed to become an open question in the draft).",
                    "If no editable surface is active, ask whether to create a note for the draft (create_note), then stage sections into it."
                ],
                tokenBudget: 2600,
                requiresReviewedDiff: false,
                icon: "square.stack.3d.up",
                summary: "Gathers your saved research, proposes a structure, then drafts section-by-section with citations.",
                triggerPhrases: ["synthesize", "newsletter from", "chapter from", "draft from my research", "pull together"],
                preferredModelTier: .strategist,
                panePolicy: .openForResearchBackedAction
            )
        case .ideaResearch:
            // The Idea Focus research panel, ported one-to-one (July 2026):
            // same proof-type taxonomy, same finding shape — but conversational,
            // surface-aware, and able to stage findings as reviewed edits.
            return CosmoInlineAssistantSkill(
                id: .ideaResearch,
                name: "Deep Research",
                description: "Runs a multi-angle web research sweep for the active idea or draft — sourced statistics, studies, news, and contrarian data, tagged by proof type.",
                route: .answer,
                requiredContext: [.activeSurface, .currentFocus, .clientProfile],
                toolBundles: [.workspaceEditing, .contentSearch, .webResearch],
                outputContract: "pane_evidence_findings_then_optional_reviewed_insertion",
                instructions: [
                    "You are a research assistant for content creators. Read the ACTIVE surface first — for an idea that means its title, angle/body, hooks, and outline; for a draft, the draft text. The user's own material defines the research target; never ask what to research when the surface has content.",
                    "PLAN BEFORE SEARCHING: design 4-8 angle-distinct web search queries that together cover hard statistics, current news and policy developments, contrarian or counter-intuitive data, historical precedents, expert commentary, and audience sentiment. Fold in the client's niche as an angle when a client profile is present.",
                    "Execute the plan with web_search — batch several angle-distinct queries in one call via the `queries` array, and pick the searchType each angle calls for: web (default facts), news (recent developments), reddit (audience sentiment), academic (studies). A research run with fewer than 4 distinct web queries is incomplete; never stop early because the first results feel sufficient.",
                    "The user's saved research and knowledge base COMPLEMENT the web sweep — pull them in to connect findings to what the user already captured, never as a substitute for actually searching.",
                    "Tag each finding with the most appropriate proof type: Statistic (hard numbers, percentages, data), Case Study (real-world example, brand story), Expert Quote (authority figure, researcher), Social Proof (user testimonials, reviews, crowd behavior), Analogy (comparison to a known concept), Contrarian Data (surprising or counter-intuitive stat), Historical Precedent (past event that mirrors the idea), or Scientific Study (peer-reviewed research).",
                    "Deliver the findings via answer_in_assistant_pane as a compact list: short finding title, a 2-3 sentence summary carrying the key data point, the source name, and the URL when known. Never invent statistics, sources, or URLs — a finding you cannot source does not ship.",
                    "Prefer contrarian and surprising data when the evidence supports it — those make hooks. Name the single strongest finding for this piece and say why in one line.",
                    "End by offering to stage any finding into the surface via propose_workspace_edit (a supporting line under the angle, or a stat-led hook); stage only after the user picks one."
                ],
                tokenBudget: 3000,
                requiresReviewedDiff: false,
                icon: "doc.text.magnifyingglass",
                summary: "Sweeps the web across 4-8 distinct angles for the active idea — sourced stats, news, and contrarian data tagged by proof type, ready to stage.",
                triggerPhrases: [
                    "find stats", "supporting evidence", "research this idea", "back this up",
                    "find data", "proof points", "deep research", "research this topic",
                    "research angles", "ton of research", "data points"
                ],
                preferredModelTier: .strategist,
                panePolicy: .alwaysOpenWithResult
            )
        }
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func isEditLike(_ lower: String) -> Bool {
        let editWords = [
            "replace", "rewrite", "edit", "insert", "append", "move", "reorder",
            "clean up", "turn this into", "change", "fix", "apply", "update",
            "make", "set", "fill", "populate", "add", "remove", "delete",
            "format", "draft"
        ]

        return editWords.contains { phrase in
            if phrase.contains(" ") {
                return lower.contains(phrase)
            }

            let separators = CharacterSet.alphanumerics.inverted
            return lower
                .components(separatedBy: separators)
                .contains(phrase)
        }
    }

    private static func isFactFillLike(_ lower: String) -> Bool {
        containsAny(lower, [
            "placeholder", "placeholders", "real deal", "recent deal", "recent stats",
            "numbers from", "actual numbers", "fill the numbers", "replace the numbers",
            "accurate to", "fill out the information", "fill out information",
            "fill the information", "fill slide", "fill in", "fill with the details",
            "with the details of", "specific numbers"
        ])
    }

    private static func isProfileBackedSlideExpansionEditLike(_ lower: String) -> Bool {
        guard isEditLike(lower),
              containsAny(lower, [
                "slide", "slides", "draft", "post", "carousel", "script"
              ]),
              containsAny(lower, [
                "profile", "client profile", "best performing", "top performing",
                "swipe", "swipes", "reel", "reels", "same voice",
                "exact same voice", "same structure", "exact same structure",
                "1:1", "one-to-one", "step by step", "step-by-step"
              ]) else {
            return false
        }

        return containsAny(lower, [
            "add", "fill", "populate", "build", "draft", "write",
            "make", "extend", "complete", "put the full", "put full"
        ])
    }

    private static func isProfileBackedOutlineBodyFillLike(_ lower: String) -> Bool {
        isOutlineToBodyEditLike(lower) &&
        containsAny(lower, [
            "best performing", "top performing", "best-performing",
            "top-performing", "swipe", "swipes", "thread", "threads",
            "profile", "client profile", "format & data", "format and data"
        ])
    }

    private static func isResearchFillLike(_ lower: String) -> Bool {
        isFactFillLike(lower) || containsAny(lower, [
            "fill the different information", "fill the information", "fill the details",
            "fill different information", "fill details", "fill data", "fill the data",
            "fill stats", "fill numbers", "fill costs", "fill rates"
        ])
    }

    private static func isOutlineToBodyEditLike(_ lower: String) -> Bool {
        containsAny(lower, ["outline", "outlines"]) &&
        containsAny(lower, ["body", "actual body", "draft", "post"]) &&
        containsAny(lower, [
            "put", "place", "move", "insert", "merge", "transfer",
            "in between each slide", "between each slide", "into the body",
            "in the actual body"
        ]) &&
        !lower.hasPrefix("what ") &&
        !lower.hasPrefix("why ") &&
        !lower.hasPrefix("how ")
    }

    private static func isFollowUpLike(_ lower: String) -> Bool {
        containsAny(lower, [
            "do the same", "same thing", "same for", "same but", "like that",
            "again", "also do", "now do", "do that", "repeat that"
        ])
    }
}

enum CosmoProposalStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case rejected
    case conflicted
    case applied
    case reverted
}

enum CosmoInlineAssistantEditScopeGuard {
    static func shouldReject(
        operation: CosmoAssistantProposalOperation,
        prompt: String
    ) -> Bool {
        guard isConservativeFactFillPrompt(prompt),
              operation.kind == .textReplacement || operation.kind == .structuredFieldReplacement,
              let originalText = operation.originalText,
              let proposedText = operation.proposedText,
              !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let protectedWords = protectedCopyWords(in: originalText)
        guard protectedWords.count >= 5 else {
            return false
        }

        let proposedWords = Set(protectedCopyWords(in: proposedText))
        let missingCount = protectedWords.filter { !proposedWords.contains($0) }.count
        return Double(missingCount) / Double(protectedWords.count) > 0.25
    }

    static let rejectionMessage = "This looks like a rewrite, but the user asked for factual/placeholder fill only. Retry with a smaller textReplacement that preserves the user's wording byte-for-byte except the requested placeholders or factual-number fragments."

    private static func isConservativeFactFillPrompt(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        guard containsAny(lower, [
            "placeholder", "placeholders", "numbers", "specific numbers",
            "fill slide", "fill in", "fill with the details", "with the details of",
            "fill out the information", "fill out information", "accurate to"
        ]) else {
            return false
        }

        return !containsAny(lower, [
            "rewrite", "rework", "rephrase", "variation", "variations",
            "make it better", "improve", "sharpen", "punchier",
            "change the wording", "change wording"
        ])
    }

    private static func protectedCopyWords(in text: String) -> [String] {
        let placeholderStripped = text
            .lowercased()
            .replacingOccurrences(
                of: #"\$?x(?:/[a-z]+)?|\[[^\]]+\]|\{\{[^}]+\}\}|_+|\$?\d[\d,]*(?:\.\d+)?(?:/[a-z]+)?"#,
                with: " ",
                options: .regularExpression
            )

        return placeholderStripped
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { word in
                word.count >= 4 && !ignoredWords.contains(word)
            }
    }

    private static let ignoredWords: Set<String> = [
        "slide", "with", "from", "this", "that", "they", "their",
        "here", "there", "exactly", "works", "work", "only"
    ]

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

enum CosmoInlineAssistantOutlineBodyInsertionNormalizer {
    static func normalized(
        operation: CosmoAssistantProposalOperation,
        prompt: String
    ) -> CosmoAssistantProposalOperation {
        guard operation.kind == .textInsertion,
              isOutlineIntoBodyPrompt(prompt),
              let anchorSlide = slideNumber(in: operation.originalText),
              let proposedText = operation.proposedText,
              proposedTextHasLeadingSlideHeader(proposedText, slideNumber: anchorSlide) else {
            return operation
        }

        var copy = operation
        copy.proposedText = stripLeadingSlideHeader(from: proposedText, slideNumber: anchorSlide)
        return copy
    }

    private static func isOutlineIntoBodyPrompt(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return containsAny(lower, ["outline", "outlines"]) &&
        containsAny(lower, ["body", "actual body", "draft", "post"]) &&
        containsAny(lower, [
            "put", "place", "move", "insert", "merge", "transfer",
            "in between each slide", "between each slide", "into the body",
            "in the actual body"
        ])
    }

    private static func proposedTextHasLeadingSlideHeader(_ text: String, slideNumber: String) -> Bool {
        let pattern = #"^\s*(?:-{2,}\s*)?SLIDE\s+\#(slideNumber)\s*(?:\n|$)"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func stripLeadingSlideHeader(from text: String, slideNumber: String) -> String {
        let pattern = #"^\s*(?:-{2,}\s*)?SLIDE\s+\#(slideNumber)\s*(?:\n+)?"#
        let stripped = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func slideNumber(in text: String?) -> String? {
        guard let text else { return nil }
        let pattern = #"(?im)^\s*SLIDE\s+(\d+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(location: 0, length: (text as NSString).length)
              ),
              match.numberOfRanges > 1 else {
            return nil
        }

        return (text as NSString).substring(with: match.range(at: 1))
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

enum CosmoProposalHunkKind: String, Codable, Equatable, Sendable {
    case context
    case removed
    case added
}

struct CosmoProposalHunk: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: CosmoProposalHunkKind
    var text: String

    init(id: UUID = UUID(), kind: CosmoProposalHunkKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

struct CosmoEditableAnchor: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var label: String
    var utf16Start: Int
    var utf16Length: Int
}

/// The user's live text selection on an editable surface — the referent of
/// "this / it / that line" in inline requests ("shorten this", "punchier").
/// Location is conveyed by text, matching the locator's text-anchoring model.
struct CosmoEditableSelection: Codable, Equatable, Sendable {
    var text: String
    /// The full line(s) containing the selection — the anchor the edit should
    /// set as originalText so the change lands exactly where the selection lives.
    var containingLine: String?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct CosmoEditableSourceSnapshot: Codable, Equatable, Sendable {
    var surfaceID: String
    var targetID: String
    var kind: CosmoEditableSurfaceKind
    var title: String
    var text: String
    var sourceHash: String
    var anchors: [CosmoEditableAnchor]
    /// The user's current selection, when the surface tracks one — decodes nil
    /// from older payloads.
    var selection: CosmoEditableSelection? = nil
    /// The skill this surface is permanently in (e.g. concept boards live in the
    /// concept skill). While set, every non-explicit turn runs this skill:
    /// passive auto-routing and keyword skill heuristics are disabled — only a
    /// slash command or the skill picker can run something else. Decodes nil
    /// from older payloads.
    var residentSkillID: String? = nil

    func withSourceHash(_ nextHash: String) -> CosmoEditableSourceSnapshot {
        var copy = self
        copy.sourceHash = nextHash
        return copy
    }
}

enum CosmoAssistantProposalOperationKind: String, Codable, Equatable, Sendable {
    case textReplacement
    case textInsertion
    case structuredFieldReplacement
    case canvasPlan
    /// Apply rich-text formatting (bold/italic/underline/strikethrough/heading)
    /// to existing text located by `originalText` — the words don't change,
    /// how they look does.
    case formatMarks
}

/// The formatting a `formatMarks` operation applies to its located target.
enum CosmoAssistantFormatMark: String, Codable, Equatable, Sendable, CaseIterable {
    case bold
    case italic
    case underline
    case strikethrough
    case heading1
    case heading2
    case heading3

    var richTextMark: RichTextMark? {
        switch self {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        case .heading1, .heading2, .heading3: return nil
        }
    }

    var headingBlockKind: RichBlockKind? {
        switch self {
        case .heading1: return .heading1
        case .heading2: return .heading2
        case .heading3: return .heading3
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        }
    }
}

struct CosmoAssistantProposalOperation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: CosmoAssistantProposalOperationKind
    var targetID: String
    var anchorID: String?
    var originalText: String?
    var proposedText: String?
    var sourceHash: String
    var rationale: String
    var status: CosmoProposalStatus
    var canvasPayload: [String: String]
    /// Set for `.formatMarks` operations — decodes nil from older payloads.
    var formatMark: CosmoAssistantFormatMark? = nil
    /// Declares that this operation deliberately MOVES existing content because
    /// the user asked for a move/reorder. Without it, the validator rejects any
    /// operation whose net effect relocates a line — the guard against a model
    /// "improving" line order during an unrelated edit. Decodes nil from older
    /// payloads.
    var explicitMove: Bool? = nil

    init(
        id: UUID = UUID(),
        kind: CosmoAssistantProposalOperationKind,
        targetID: String,
        anchorID: String?,
        originalText: String?,
        proposedText: String?,
        sourceHash: String,
        rationale: String,
        status: CosmoProposalStatus = .pending,
        canvasPayload: [String: String] = [:],
        formatMark: CosmoAssistantFormatMark? = nil,
        explicitMove: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.anchorID = anchorID
        self.originalText = originalText
        self.proposedText = proposedText
        self.sourceHash = sourceHash
        self.rationale = rationale
        self.status = status
        self.canvasPayload = canvasPayload
        self.formatMark = formatMark
        self.explicitMove = explicitMove
    }

    static func textReplacement(
        targetID: String,
        anchorID: String,
        originalText: String,
        proposedText: String,
        sourceHash: String,
        rationale: String
    ) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: targetID,
            anchorID: anchorID,
            originalText: originalText,
            proposedText: proposedText,
            sourceHash: sourceHash,
            rationale: rationale
        )
    }

    func marked(_ nextStatus: CosmoProposalStatus) -> CosmoAssistantProposalOperation {
        var copy = self
        copy.status = nextStatus
        return copy
    }

    func canApply(against source: CosmoEditableSourceSnapshot) -> Bool {
        guard (status == .pending || status == .conflicted), targetID == source.targetID else { return false }
        if kind == .formatMarks {
            // Formatting applies when its target still exists; the apply path
            // reports an honest skip otherwise.
            guard let originalText, formatMark != nil else { return false }
            return CosmoInlineDiffLocator.range(of: originalText, in: source.text) != nil
        }
        if sourceHash == source.sourceHash { return true }
        return canApplyByMatchingOriginalText(in: source.text)
    }

    private func canApplyByMatchingOriginalText(in sourceText: String) -> Bool {
        CosmoInlineTextEditResolver.placement(for: self, in: sourceText) != nil
    }

    var isRevertable: Bool {
        status == .accepted || status == .applied
    }

    func inverseOperation(sourceHash: String) -> CosmoAssistantProposalOperation? {
        guard let proposedText else { return nil }

        return CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: targetID,
            anchorID: anchorID,
            originalText: proposedText,
            proposedText: originalText ?? "",
            sourceHash: sourceHash,
            rationale: "Revert \(rationale)"
        )
    }

    var hunks: [CosmoProposalHunk] {
        CosmoInlineAssistantDiffEngine.hunks(
            original: originalText ?? "",
            proposed: proposedText ?? ""
        )
    }
}

struct CosmoAssistantProposal: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var prompt: String
    var surfaceID: String
    var title: String
    var summary: String
    var operations: [CosmoAssistantProposalOperation]
    var createdAt: Date
    /// The skill that produced this proposal, when one was active. Drives
    /// skill-scoped learning: accept/reject outcomes accrue to the skill so it
    /// improves with use.
    var skillID: String?
    /// True while this proposal is a transient riff-direction PREVIEW: it renders
    /// the in-document woven diff like any reviewed proposal, but it never
    /// persists and never gets its own pane card — accepting a hunk promotes it
    /// to a real applied proposal, leaving the block clears it. Decodes nil from
    /// older payloads.
    var isRiffPreview: Bool? = nil

    init(
        id: UUID = UUID(),
        prompt: String,
        surfaceID: String,
        title: String,
        summary: String,
        operations: [CosmoAssistantProposalOperation],
        createdAt: Date = Date(),
        skillID: String? = nil,
        isRiffPreview: Bool? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.surfaceID = surfaceID
        self.title = title
        self.summary = summary
        self.operations = operations
        self.createdAt = createdAt
        self.skillID = skillID
        self.isRiffPreview = isRiffPreview
    }

    var addedHunkCount: Int {
        operations.flatMap(\.hunks).filter { $0.kind == .added }.count
    }

    var removedHunkCount: Int {
        operations.flatMap(\.hunks).filter { $0.kind == .removed }.count
    }

    var hasRevertableOperations: Bool {
        operations.contains { $0.isRevertable }
    }

    /// Operations still awaiting a decision (pending or stale-but-shown).
    var reviewableOperationCount: Int {
        operations.filter { $0.status == .pending || $0.status == .conflicted }.count
    }

    var hasReviewableOperations: Bool {
        reviewableOperationCount > 0
    }

    func matches(
        surfaceID expectedSurfaceID: String,
        targetID expectedTargetID: String? = nil,
        activeAtomUUID: String? = nil
    ) -> Bool {
        if surfaceID == expectedSurfaceID { return true }
        if let activeAtomUUID, surfaceID == activeAtomUUID { return true }
        if let expectedTargetID,
           operations.contains(where: { $0.targetID == expectedTargetID }) {
            return true
        }
        return false
    }

    var operationStatusSummary: String {
        let pendingCount = operations.filter { $0.status == .pending }.count
        let appliedCount = operations.filter { $0.status == .applied || $0.status == .accepted }.count
        let revertedCount = operations.filter { $0.status == .reverted }.count
        let rejectedCount = operations.filter { $0.status == .rejected }.count
        let conflictedCount = operations.filter { $0.status == .conflicted }.count

        if pendingCount == operations.count {
            return "\(operations.count) pending"
        }

        return [
            appliedCount > 0 ? "\(appliedCount) applied" : nil,
            pendingCount > 0 ? "\(pendingCount) pending" : nil,
            revertedCount > 0 ? "\(revertedCount) reverted" : nil,
            rejectedCount > 0 ? "\(rejectedCount) rejected" : nil,
            conflictedCount > 0 ? "\(conflictedCount) conflicted" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// A source the assistant actually read while producing a response — rendered
/// as a clickable chip under the answer. Anti-hallucination made visible: the
/// user can verify every claim against the atom it came from.
struct CosmoAssistantSourceRef: Identifiable, Codable, Equatable, Hashable, Sendable {
    var uuid: String
    var title: String
    var kind: String

    var id: String { uuid }

    var icon: String {
        switch kind {
        case "idea": return "lightbulb"
        case "note", "sticky_note": return "note.text"
        case "content": return "doc.text"
        case "research": return "magnifyingglass"
        case "connection": return "point.3.connected.trianglepath.dotted"
        case "swipe_file": return "rectangle.stack"
        case "clientProfile", "client_profile": return "person.crop.rectangle"
        case "thinkspace": return "rectangle.3.group"
        default: return "doc"
        }
    }
}

/// The assistant's character sheet: a single, versioned, user-editable persona
/// document. Byte-stable between edits — it renders into the cached prompt
/// prefix, so an edit costs exactly one cache rewrite and personality otherwise
/// never drifts. Thread-safe because `staticInstructions` renders from
/// nonisolated contexts.
final class CosmoInlineAssistantPersonalityStore: @unchecked Sendable {
    static let shared = CosmoInlineAssistantPersonalityStore()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let storageKey = "cosmo.inline.personality.v1"
    private var cachedText: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var currentText: String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedText { return cachedText }
        let stored = defaults.string(forKey: storageKey)
        let resolved = (stored?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? stored!
            : CosmoInlineAssistantInstructionPrompt.defaultPersonality
        cachedText = resolved
        return resolved
    }

    var isCustomized: Bool {
        currentText != CosmoInlineAssistantInstructionPrompt.defaultPersonality
    }

    func save(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == CosmoInlineAssistantInstructionPrompt.defaultPersonality {
            defaults.removeObject(forKey: storageKey)
            cachedText = CosmoInlineAssistantInstructionPrompt.defaultPersonality
        } else {
            defaults.set(trimmed, forKey: storageKey)
            cachedText = trimmed
        }
    }

    func resetToDefault() {
        save("")
    }
}

enum CosmoInlineAssistantInstructionPrompt {
    static func make(
        route: CosmoInlineAssistantRoute,
        snapshot: CosmoEditableSourceSnapshot?,
        skillPlan: CosmoInlineAssistantSkillPlan? = nil,
        workingContextFrame: CosmoInlineAssistantWorkingContextFrame? = nil
    ) -> String {
        [
            staticInstructions(
                for: route,
                requiresPaneExplanation: CosmoInlineAssistantResearchIntent.shouldRequirePaneExplanation(skillPlan)
            ),
            volatileContext(
                snapshot: snapshot,
                skillPlan: skillPlan,
                workingContextFrame: workingContextFrame
            )
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    /// The byte-stable instruction layer: identical for every request on the same
    /// route, so it can live inside the prompt-cache prefix. Anything that varies
    /// per request (surface text, skill plan, working context) belongs in
    /// `volatileContext` instead — a single changed byte here would invalidate the
    /// entire cached prefix on every call.
    static func staticInstructions(
        for route: CosmoInlineAssistantRoute,
        requiresPaneExplanation: Bool
    ) -> String {
        [
            header,
            personality,
            routeInstructions(for: route, requiresPaneExplanation: requiresPaneExplanation)
        ]
        .joined(separator: "\n\n")
    }

    /// The per-request context layer: skill plan, working-context frame, and the
    /// active surface snapshot. Rendered after the cache breakpoint.
    static func volatileContext(
        snapshot: CosmoEditableSourceSnapshot?,
        skillPlan: CosmoInlineAssistantSkillPlan? = nil,
        workingContextFrame: CosmoInlineAssistantWorkingContextFrame? = nil
    ) -> String? {
        let sections = [
            skillPlan?.promptBlock,
            workingContextFrame?.promptBlock,
            surfaceInstructions(for: snapshot)
        ]
        .compactMap { $0 }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private static let header = """
    ## Inline Workspace Assistant
    Never replace the normal Cosmo command context. This is an additional inline workspace layer on top of the same profile, retrieval, memory, swipe, strategy, and active-context prompt that Command A uses.

    If a Resolved Inline Skill Context section is present, treat those facts as already loaded from Cosmo. Use them directly. Call lookup_client_facts only for a specific missing client detail. Do not call get_client_profile when the compact profile block has the needed facts.
    Keep using source/profile/search tools until the user request is actually answered or a reviewed edit proposal is staged. Do not silently stop after reading context.
    For any user-visible workspace edit, call propose_workspace_edit. Never mutate the workspace directly.
    If the user confirms a finalized inline skill spec or asks to "make", "create", "save", or "add" a skill, call create_inline_skill with the skill definition. Do not say skill creation is outside your tool access.
    For substantive answers, explanations, analysis, or non-edit results, call answer_in_assistant_pane with the full response.

    Citing the user's documents in pane answers: when a sentence references a specific saved document you actually read this run (a note, idea, swipe, research item, connection), write its uuid wrapped as [[uuid]] exactly where the document's name would otherwise appear. The marker renders as a clickable pill carrying the document's title, so do NOT also write the title next to it. Use each document's marker at most once per answer, at its most load-bearing mention; later mentions use plain words like "that note". Only use uuids that appeared in this run's tool results — never invent or guess one; if you don't have the uuid, just write the document's name as plain text.
    Example — tool result contained {"uuid": "a1b2-c3", "title": "Pricing psychology"}:
    Wrong: "Your note Pricing psychology [[a1b2-c3]] already covers this."
    Right: "[[a1b2-c3]] already covers this — the anchoring section is the part to reuse."
    """

    /// The live persona: the user's edited character sheet when one exists,
    /// otherwise the built-in default below.
    private static var personality: String {
        CosmoInlineAssistantPersonalityStore.shared.currentText
    }

    static let defaultPersonality = """
    ## Cosmo Personality Layer
    You are the user's editor — a sharp, chill creative collaborator who knows their work cold. You speak content natively: hooks, slides, retention beats, CTAs, the difference between a stopper and a throat-clear. Direct, specific, casual without fluff. Voice is taught by example — match the register of the Cosmo replies below, not just the rules.

    Do:
    - Start from the user's actual ask and the active surface. When a selection exists, "this" means the selection — act on it without asking.
    - Edit like an editor: smallest change that wins. Keep the user's rhythm, slang, and line breaks unless they asked for a rewrite.
    - After staging edits, give a receipt — one line, what changed and the result state ("Bolded all 26 headers — numbering runs clean 1–26."). Never narrate tools or process.
    - Push back plainly when a line is weak or evidence is thin — one line on why, then the stronger move, ideally already staged.
    - Give concrete judgments, examples, and rewrites before abstract advice. Think in what stops the scroll.
    - For minor choices (a word, an ordering, a default), pick the best option and note it — don't ask.

    Avoid:
    - AI disclaimers, generic praise, corporate framing, filler, and emoji.
    - Inventing client facts, metrics, examples, or voice traits.
    - Saying you analyzed context if you did not actually use the available tools or active surface.
    - Asking questions the surface already answers ("which post?" when the draft is right there).

    Voice calibration (generic reply → Cosmo reply):
    <example>
    <generic>Great question! There are several approaches you could consider for improving this hook. Here are some options to think about...</generic>
    <cosmo>The hook buries the lead — "$4,556/mo from one duplex" is the stopper and it's in line three. Staged a version with it first.</cosmo>
    </example>
    <example>
    <generic>I've made the changes you requested! Let me know if you'd like any adjustments or have other questions.</generic>
    <cosmo>Done — tightened both lines, kept your rhythm. The second one reads faster now.</cosmo>
    </example>
    <example>
    <generic>I have applied bold formatting to all of the slide headers in your document as requested!</generic>
    <cosmo>Bolded all 9 slide headers. Slide 4's header was mid-paragraph — moved it to its own line while I was in there.</cosmo>
    </example>
    <example>
    <generic>Here is a shortened version of your selected sentence. I focused on making it more concise while preserving the meaning.</generic>
    <cosmo>Cut it from 24 words to 11 — the number does the talking now.</cosmo>
    </example>
    <example>
    <generic>That's an interesting idea! It has a lot of potential. You might want to consider developing it further by...</generic>
    <cosmo>The premise is fine but it's the same angle as your March thread. The new part is the landlord objection — lead with that instead.</cosmo>
    </example>
    """

    private static func routeInstructions(
        for route: CosmoInlineAssistantRoute,
        requiresPaneExplanation: Bool
    ) -> String {
        switch route {
        case .action:
            let paneExplanation = requiresPaneExplanation
                ? """

                For research-backed or source-backed edits, call both propose_workspace_edit and answer_in_assistant_pane in the same assistant/tool turn. The diff is the deliverable, but the pane explanation should briefly say what you used and why, in Cosmo's normal sharp/chill voice. Keep it short: source/fact, confidence, and what changed. Do not expose hidden chain-of-thought.
                """
                : ""

            return """
            ## Inline Edit Route
            The user likely wants a reviewed edit. Prefer propose_workspace_edit with exact source hashes and operations. Do not rely on prose alone when edits are possible.

            When the request contains an edit instruction — fill in, replace, add, update, rewrite, fix — the run's deliverable IS the staged edit. After any research or reading, pick the best-supported value or wording, stage it with propose_workspace_edit in THIS run, and put confidence notes or alternatives in the pane explanation. The review diff is the user's confirmation step — never end the run asking permission to stage ("Want me to fill it in?" is double-asking), and never deliver only prose when an edit was instructed. Only a pure question, or an explicit research-only ask, ends without a staged edit.

            Stage ALL the edits in a SINGLE propose_workspace_edit call with one operation per change — do not split changes across multiple tool calls or multiple turns; that is slower and worse.

            When a "## User Selection" block is present, the request targets that selection: "this", "it", or a bare instruction ("shorten", "punchier") means edit the selected text and nothing else. Anchor the operation on the full line(s) containing the selection.

            For each change to existing text, set originalText to the ENTIRE line or sentence that contains the target, copied verbatim from the active surface text, and set proposedText to that same line with ONLY the requested change applied. This guarantees the edit is located and woven in exactly where it lives, and shows a clean before/after. Never use a short fragment (like just a number) as originalText — it may not match or may be ambiguous, which dumps the change at the bottom and flags it as outdated. Use textInsertion only for brand-new content, anchored via originalText to the existing line it should follow.

            SCOPE IS ENFORCED, not advisory. One operation per changed line — never wrap untouched neighboring lines into a replacement (the app splits fused blocks back into minimal edits and audits the difference). The user's line ORDER is part of their copy: never move, reorder, or re-add existing lines as a side effect of another edit. A move is legitimate only when the user asked for one — then stage it as a removal covering the line's current position plus an operation with explicitMove: true where it lands. Re-adding a line that already exists near your edit duplicates it and the proposal is rejected with the exact line named; fix by leaving that line alone.

            Formatting requests (bold, italic, underline, strikethrough, turn into a heading) use kind formatMarks with formatMark set and originalText = the exact text to format, one operation per target. The words must stay identical — never express formatting by rewriting text or adding asterisks/markdown symbols, and never use textReplacement for a pure formatting change. To format EVERY slide header at once ("bold all the headers"), send ONE formatMarks operation with scope set to allSlideHeaders — the app expands it to every header line exactly.

            When inserting outline points into existing slide bodies, anchor each insertion to the existing SLIDE N heading but do not include another SLIDE N heading in proposedText. Insert only the body text that should live under that already-existing slide header. Do not create new slide headers unless the requested destination slide does not already exist.

            When you insert or remove an item in a sequentially numbered series — a new slide between two existing SLIDE N headers, or a step in a numbered list inside a slide — the numbering must stay sequential and unique afterwards. Give any new item its correct integer number, then add ONE renumberSequence operation (seriesKind slideHeaders or numberedSteps, fromNumber = the first number that must shift, delta = 1 to shift up or -1 to shift down, withinSlide for step lists) — the app rewrites every affected line from the live document. Never hand-copy individual header bumps, never invent a fractional number (no SLIDE 6.5, no Step 5b), and never leave two items sharing the same number. The tool result includes resultingDocumentStructure — verify it matches the user's ask before finishing, and stage a corrected proposal if it does not.

            If this is edit-only work, do not force the assistant pane open. The proposal summary will still be recorded in pane history. Use answer_in_assistant_pane only when the user also asked for an explanation, the edit cannot be staged, or there is a substantive non-edit result. Proposal summaries are receipts: one tight line in Cosmo's voice saying what changed and the resulting state ("Bolded all 9 slide headers"), never process narration.
            \(paneExplanation)
            """
        case .answer:
            return """
            ## Inline Answer Route
            The user likely wants an answer. Use answer_in_assistant_pane for the final response so it appears in the pane history even if the pane opens later. If the answer naturally includes concrete editable changes, you may also stage them with propose_workspace_edit.
            """
        }
    }

    private static func surfaceInstructions(for snapshot: CosmoEditableSourceSnapshot?) -> String? {
        guard let snapshot else {
            return "Active editable surface: none registered."
        }

        let anchors = snapshot.anchors
            .map { "\($0.id):\($0.label)" }
            .joined(separator: ", ")

        var sections = ["""
        Active editable surface:
        surfaceID: \(snapshot.surfaceID)
        targetID: \(snapshot.targetID)
        title: \(snapshot.title)
        kind: \(snapshot.kind.rawValue)
        sourceHash: \(snapshot.sourceHash)
        anchors: \(anchors)
        text:
        \(snapshot.text)
        """]

        if let outline = documentOutline(for: snapshot.text) {
            sections.append(outline)
        }

        if let selection = snapshot.selection, !selection.isEmpty {
            var selectionBlock = """
            ## User Selection
            The user currently has this text selected on the active surface. When the request is an edit and says "this", "it", or gives a bare instruction ("shorten", "punchier"), it refers to THIS selection — edit exactly this, nothing else.
            Selected text:
            \(selection.text)
            """
            if let line = selection.containingLine,
               !line.isEmpty,
               line != selection.text {
                selectionBlock += """


                The full line containing the selection (use this as originalText so the edit lands in place):
                \(line)
                """
            }
            sections.append(selectionBlock)
        }

        return sections.joined(separator: "\n\n")
    }

    /// A computed structural digest of the surface — slide headers and heading
    /// lines in document order — so structural asks ("fix the numbering",
    /// "reorder slides 4 and 5") are answerable in one shot with no tool calls.
    static func documentOutline(for text: String) -> String? {
        var entries: [String] = []
        var lineNumber = 0
        text.enumerateLines { line, stop in
            lineNumber += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isSlideHeader = trimmed.range(
                of: #"^SLIDE\s+\d+\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            let isMarkdownHeading = trimmed.hasPrefix("#")
            if isSlideHeader || isMarkdownHeading {
                entries.append("- line \(lineNumber): \(trimmed.prefix(80))")
                if entries.count >= 48 { stop = true }
            }
        }
        guard entries.count >= 2 else { return nil }
        return """
        Document structure (slide headers / headings, in order):
        \(entries.joined(separator: "\n"))
        """
    }
}

/// The deterministic request shape for inline assistant calls. Both the live
/// request path (`prepareInlineAssistantAgentRequest`) and the cache prewarmer
/// derive from this single definition so the warmed prompt prefix and the real
/// request's prefix can't drift apart.
enum CosmoInlineAssistantRequestShape {
    /// Inline requests pin their intent instead of running keyword classification:
    /// a stable intent means a stable tool set and a stable cached prompt prefix.
    /// Keyword classification would scatter identical edit requests across intents
    /// (.query returns ~all 95 tools), fragmenting the cache and degrading Haiku's
    /// tool selection.
    static func pinnedIntent(for route: CosmoInlineAssistantRoute) -> AgentIntent {
        switch route {
        case .action: return .correct  // small focused tool set for surgical edits
        case .answer: return .analyze  // analysis tools + web search, far leaner than .query
        }
    }

    /// The default skill whose tool bundles shape the common-case request for a route.
    static func defaultSkillID(for route: CosmoInlineAssistantRoute) -> CosmoInlineAssistantSkillID {
        route == .action ? .inlineEdit : .researchAnswer
    }

    /// Tool bundles for the route's common case — used to pre-warm the prompt cache
    /// with the same tool list a typical real request will carry.
    static func baselineToolBundles(for route: CosmoInlineAssistantRoute) -> Set<AgentToolBundle> {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "",
            surfaceKind: .text,
            previousSkillID: nil,
            selectedSkillID: defaultSkillID(for: route).rawValue
        )
        var bundles = plan.toolBundles
        bundles.insert(.workspaceEditing)
        if route == .answer {
            bundles.insert(.contentSearch)
        }
        return bundles
    }

    static func responseMode(for route: CosmoInlineAssistantRoute) -> AgentResponseMode {
        route == .action ? .automatic : .inlineAssistant
    }

    /// The model tier a normal inline request runs on when no skill, profile, or
    /// user override is set. The cache prewarmer MUST warm this exact tier:
    /// Anthropic prompt caches are model-scoped, so a prefix warmed on a different
    /// model can never be read back by the real request (the warm is pure waste and
    /// the first request still pays a cold write). Kept here so the request path and
    /// the prewarmer can't drift apart on model, same as pinnedIntent / toolBundles.
    static let defaultModelTier: AgentModelTier = .sonnet5
}
