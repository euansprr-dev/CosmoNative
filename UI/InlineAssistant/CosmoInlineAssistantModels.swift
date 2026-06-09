import CoreGraphics
import Foundation

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
    case voiceVariations
    case inlineEdit
    case factFill
    case researchAnswer
    case canvasOrganize
    case ideaStrategy
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

        return """
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
            updatedAt: now
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
            panePolicy: panePolicy
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

    init(store: CosmoInlineSkillStore = .userDefaults()) {
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

struct CosmoInlineAssistantWorkingContextFrame: Codable, Equatable, Sendable {
    var conversationID: String
    var surfaceID: String?
    var targetID: String?
    var surfaceKind: CosmoEditableSurfaceKind?
    var surfaceTitle: String?
    var surfaceSourceHash: String?
    var activeAtomUUID: String?
    var effectiveClientUUID: String?
    var clientReference: String?
    var skillID: CosmoInlineAssistantSkillID
    var route: CosmoInlineAssistantRoute
    var sourcePrompt: String = ""
    var previousPrompt: String?
    var previousSkillID: CosmoInlineAssistantSkillID?
    var previousTargetHint: String?
    var currentTargetHint: String?
    var operationHint: String?
    var contextAtomUUIDs: [String] = []
    var contextAtomTitles: [String] = []
    var isFollowUp: Bool
    var reusedContext: Bool
    var stableContextKey: String
    var updatedAt: Date

    var promptBlock: String {
        let cacheStatus = reusedContext ? "hit" : "miss"
        let surface = surfaceID ?? activeAtomUUID ?? "none"
        let title = surfaceTitle ?? "untitled"
        let clientUUID = effectiveClientUUID ?? "none"
        let clientName = clientReference ?? "none"
        let previousTarget = previousTargetHint ?? "none"
        let currentTarget = currentTargetHint ?? "none"
        let previousSkill = previousSkillID?.rawValue ?? "none"
        let operation = operationHint ?? "none"
        let sourceHash = surfaceSourceHash ?? "none"
        let selectedContext = contextAtomTitles.isEmpty ? "none" : contextAtomTitles.joined(separator: ", ")
        let selectedContextIDs = contextAtomUUIDs.isEmpty ? "none" : contextAtomUUIDs.joined(separator: ", ")

        return """
        ## Inline Working Context Cache
        Cache status: \(cacheStatus)
        Stable context key: \(stableContextKey)
        Surface scope: \(surface)
        Surface title: \(title)
        Surface source hash: \(sourceHash)
        Active atom UUID: \(activeAtomUUID ?? "none")
        Active client UUID: \(clientUUID)
        Client reference: \(clientName)
        Current skill: \(skillID.rawValue)
        Previous skill: \(previousSkill)
        Previous target: \(previousTarget)
        Current target: \(currentTarget)
        Operation hint: \(operation)
        Selected context: \(selectedContext)
        Selected context UUIDs: \(selectedContextIDs)
        Follow-up prompt: \(isFollowUp ? "yes" : "no")

        Cache policy:
        - Reuse the prior client/profile context when the current prompt is a follow-up and no new client is named.
        - Reuse the prior operation intent for phrases like "do the same" or "same thing" unless the user changes the task.
        - Keep selected @ context active for the inline assistant session until the user removes it.
        - Refresh the active surface text whenever the source hash changes; do not rely on cached text for reviewed diffs.
        - If client/profile evidence is stale or missing, call the profile/search tools again instead of guessing.
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
        prompt: String,
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
        let isFollowUp = Self.isFollowUpPrompt(prompt)
        let currentTarget = Self.targetHint(in: prompt)
        let explicitClient = Self.clientReference(in: prompt)
        let effectiveClientUUID = activeClientUUID ?? (isFollowUp ? previous?.effectiveClientUUID : nil)
        let clientReference = explicitClient ?? (isFollowUp ? previous?.clientReference : nil)
        let effectiveSkillID = isFollowUp ? (previous?.skillID ?? skillPlan.primarySkill.id) : skillPlan.primarySkill.id
        let contextAtomUUIDs = contextAtoms.map(\.uuid)
        let contextAtomTitles = contextAtoms.map { $0.title ?? "Untitled" }
        let reusedContext = previous != nil && (
            isFollowUp ||
            previous?.effectiveClientUUID == effectiveClientUUID ||
            previous?.clientReference == clientReference ||
            previous?.contextAtomUUIDs == contextAtomUUIDs
        )

        let frame = CosmoInlineAssistantWorkingContextFrame(
            conversationID: conversationID,
            surfaceID: snapshot?.surfaceID,
            targetID: snapshot?.targetID,
            surfaceKind: snapshot?.kind,
            surfaceTitle: snapshot?.title,
            surfaceSourceHash: snapshot?.sourceHash,
            activeAtomUUID: activeAtomUUID,
            effectiveClientUUID: effectiveClientUUID,
            clientReference: clientReference,
            skillID: effectiveSkillID,
            route: route,
            sourcePrompt: prompt,
            previousPrompt: previous?.sourcePrompt,
            previousSkillID: previous?.skillID,
            previousTargetHint: previous?.currentTargetHint,
            currentTargetHint: currentTarget,
            operationHint: Self.operationHint(
                in: prompt,
                isFollowUp: isFollowUp,
                previous: previous,
                skillPlan: skillPlan
            ),
            contextAtomUUIDs: contextAtomUUIDs,
            contextAtomTitles: contextAtomTitles,
            isFollowUp: isFollowUp,
            reusedContext: reusedContext,
            stableContextKey: stableContextKey(
                conversationID: conversationID,
                snapshot: snapshot,
                activeAtomUUID: activeAtomUUID,
                clientUUID: effectiveClientUUID,
                clientReference: clientReference,
                skillID: effectiveSkillID,
                contextAtomUUIDs: contextAtomUUIDs
            ),
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

    nonisolated static func isFollowUp(_ prompt: String) -> Bool {
        isFollowUpPrompt(prompt)
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

    private func stableContextKey(
        conversationID: String,
        snapshot: CosmoEditableSourceSnapshot?,
        activeAtomUUID: String?,
        clientUUID: String?,
        clientReference: String?,
        skillID: CosmoInlineAssistantSkillID,
        contextAtomUUIDs: [String]
    ) -> String {
        [
            conversationID,
            snapshot?.surfaceID ?? activeAtomUUID ?? "global",
            clientUUID ?? clientReference ?? "no-client",
            skillID.rawValue,
            contextAtomUUIDs.sorted().joined(separator: "-")
        ].joined(separator: "|")
    }

    private nonisolated static func isFollowUpPrompt(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return containsAny(lower, [
            "do the same", "same thing", "same for", "same but", "like that",
            "again", "also do", "now do", "do that", "repeat that"
        ])
    }

    private nonisolated static func targetHint(in prompt: String) -> String? {
        let words = prompt
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        for index in words.indices where words[index] == "slide" {
            let nextIndex = words.index(after: index)
            guard nextIndex < words.endIndex else { continue }
            return "slide \(words[nextIndex])"
        }

        return nil
    }

    nonisolated static func clientReference(in prompt: String) -> String? {
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

    private nonisolated static func operationHint(
        in prompt: String,
        isFollowUp: Bool,
        previous: CosmoInlineAssistantWorkingContextFrame?,
        skillPlan: CosmoInlineAssistantSkillPlan
    ) -> String {
        if isFollowUp, previous != nil {
            return "reuse previous operation"
        }

        switch skillPlan.primarySkill.id {
        case .factFill:
            return "fill facts with source-backed context"
        case .inlineEdit:
            return "stage reviewed inline edit"
        case .canvasOrganize:
            return "stage canvas organization"
        case .voiceVariations:
            return "generate voice variations"
        case .contentReview:
            return "review active content"
        case .ideaStrategy:
            return "shape flow and story structure"
        case .researchAnswer:
            return "answer with retrieved context"
        }
    }

    private nonisolated static func clean(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private nonisolated static func cleanClientCandidate(_ word: String) -> String {
        var cleaned = word
            .replacingOccurrences(of: "’s", with: "")
            .replacingOccurrences(of: "'s", with: "")
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.hasSuffix("s"), word.contains("'") || word.contains("’") {
            cleaned.removeLast()
        }
        return cleaned
    }

    private nonisolated static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
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
        return String(value.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
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

        // TODO: Resolve .clientMemory compactly from client memory service when available.
        // TODO: Resolve .voiceLessons compactly from lesson/voice stores.
        // TODO: Resolve .swipes and .bestPerformingContent from selected @ context and swipe search.
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

        if let clientReference = CosmoInlineAssistantWorkingContextCache.clientReference(in: prompt),
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
            body += "..."
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
            "information", "details", "data"
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
            return CosmoInlineAssistantSkillPlan(primarySkill: skill, definitionID: definition.id)
        } else if isFollowUpLike(lower), let previousSkillID {
            skill = builtInSkill(previousSkillID)
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
                "Because the user asked for research-backed facts, use web_search when local/profile context does not already answer the request, then call both propose_workspace_edit and answer_in_assistant_pane in the same tool turn."
            )
        }

        return CosmoInlineAssistantSkillPlan(primarySkill: skill, definitionID: skill.id.rawValue)
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
                summary: "Reviews the current draft against client voice, strategy, swipes, and performance patterns.",
                triggerPhrases: ["review", "feedback", "critique", "content feedback"],
                preferredModelTier: .strategist,
                panePolicy: .openForAnswer
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
                summary: "Creates multiple options in a selected client or creator voice.",
                triggerPhrases: ["variations", "voice", "rewrite options", "versions"],
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
                    "If evidence is missing, leave a clear placeholder and say what data is missing instead of guessing."
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
                name: "Research Answer",
                description: "Answers questions with workspace, memory, profile, or external research context.",
                route: .answer,
                requiredContext: [.activeSurface, .currentFocus, .workspaceMemory, .researchEvidence],
                toolBundles: [.workspaceEditing, .contentSearch, .clientProfiles, .clientMemory, .swipes, .strategy, .webResearch],
                outputContract: "pane_answer_card",
                instructions: [
                    "Use workspace/profile/search tools when the answer depends on Cosmo data or current facts.",
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
                name: "Canvas Organizer",
                description: "Plans and stages canvas organization work using the active canvas state.",
                route: .action,
                requiredContext: [.canvasState, .currentFocus, .workspaceMemory],
                toolBundles: [.workspaceEditing, .canvasSpatial, .contentSearch, .strategy],
                outputContract: "canvas_reviewed_plan",
                instructions: [
                    "Inspect the current canvas state before proposing spatial changes.",
                    "Cluster by conceptual relationship, not just visual neatness.",
                    "Stage reviewable canvas operations or a canvas plan instead of silently moving objects.",
                    "Keep a pane history summary, but do not force the pane open for edit-only canvas work."
                ],
                tokenBudget: 1800,
                requiresReviewedDiff: true,
                icon: "square.grid.3x3",
                summary: "Stages reviewable organization changes for the active canvas or thinkspace.",
                triggerPhrases: ["organize canvas", "reorganize", "arrange canvas"],
                preferredModelTier: .strategist,
                panePolicy: .neverForAction
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

struct CosmoEditableSourceSnapshot: Codable, Equatable, Sendable {
    var surfaceID: String
    var targetID: String
    var kind: CosmoEditableSurfaceKind
    var title: String
    var text: String
    var sourceHash: String
    var anchors: [CosmoEditableAnchor]

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
        canvasPayload: [String: String] = [:]
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

    init(
        id: UUID = UUID(),
        prompt: String,
        surfaceID: String,
        title: String,
        summary: String,
        operations: [CosmoAssistantProposalOperation],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.surfaceID = surfaceID
        self.title = title
        self.summary = summary
        self.operations = operations
        self.createdAt = createdAt
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

enum CosmoInlineAssistantInstructionPrompt {
    static func make(
        route: CosmoInlineAssistantRoute,
        snapshot: CosmoEditableSourceSnapshot?,
        skillPlan: CosmoInlineAssistantSkillPlan? = nil,
        workingContextFrame: CosmoInlineAssistantWorkingContextFrame? = nil
    ) -> String {
        [
            header,
            personality,
            skillPlan?.promptBlock,
            workingContextFrame?.promptBlock,
            routeInstructions(for: route, skillPlan: skillPlan),
            surfaceInstructions(for: snapshot)
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private static let header = """
    ## Inline Workspace Assistant
    Never replace the normal Cosmo command context. This is an additional inline workspace layer on top of the same profile, retrieval, memory, swipe, strategy, and active-context prompt that Command A uses.

    If a Resolved Inline Skill Context section is present, treat those facts as already loaded from Cosmo. Use them directly. Call lookup_client_facts only for a specific missing client detail. Do not call get_client_profile when the compact profile block has the needed facts.
    Keep using source/profile/search tools until the user request is actually answered or a reviewed edit proposal is staged. Do not silently stop after reading context.
    For any user-visible workspace edit, call propose_workspace_edit. Never mutate the workspace directly.
    If the user confirms a finalized inline skill spec or asks to "make", "create", "save", or "add" a skill, call create_inline_skill with the skill definition. Do not say skill creation is outside your tool access.
    For substantive answers, explanations, analysis, or non-edit results, call answer_in_assistant_pane with the full response.
    """

    private static let personality = """
    ## Cosmo Personality Layer
    Sound like a sharp, chill creative friend who knows the user's work. Be direct, specific, and casual without becoming fluffy.

    Do:
    - Start from the user's actual ask and the active workspace.
    - Give concrete judgments, examples, and rewrites before abstract advice.
    - Push back plainly when evidence is thin or an idea is weak.
    - Keep the final response tight unless the task genuinely needs depth.

    Avoid:
    - AI disclaimers, generic praise, corporate framing, and filler.
    - Inventing client facts, metrics, examples, or voice traits.
    - Saying you analyzed context if you did not actually use the available tools or active surface.
    """

    private static func routeInstructions(
        for route: CosmoInlineAssistantRoute,
        skillPlan: CosmoInlineAssistantSkillPlan?
    ) -> String {
        switch route {
        case .action:
            let paneExplanation = CosmoInlineAssistantResearchIntent.shouldRequirePaneExplanation(skillPlan)
                ? """

                For research-backed or source-backed edits, call both propose_workspace_edit and answer_in_assistant_pane in the same assistant/tool turn. The diff is the deliverable, but the pane explanation should briefly say what you used and why, in Cosmo's normal sharp/chill voice. Keep it short: source/fact, confidence, and what changed. Do not expose hidden chain-of-thought.
                """
                : ""

            return """
            ## Inline Edit Route
            The user likely wants a reviewed edit. Prefer propose_workspace_edit with exact source hashes and operations. Do not rely on prose alone when edits are possible.

            Stage ALL the edits in a SINGLE propose_workspace_edit call with one operation per change — do not split changes across multiple tool calls or multiple turns; that is slower and worse.

            For each change to existing text, set originalText to the ENTIRE line or sentence that contains the target, copied verbatim from the active surface text, and set proposedText to that same line with ONLY the requested change applied. This guarantees the edit is located and woven in exactly where it lives, and shows a clean before/after. Never use a short fragment (like just a number) as originalText — it may not match or may be ambiguous, which dumps the change at the bottom and flags it as outdated. Use textInsertion only for brand-new content, anchored via originalText to the existing line it should follow.

            When inserting outline points into existing slide bodies, anchor each insertion to the existing SLIDE N heading but do not include another SLIDE N heading in proposedText. Insert only the body text that should live under that already-existing slide header. Do not create new slide headers unless the requested destination slide does not already exist.

            If this is edit-only work, do not force the assistant pane open. The proposal summary will still be recorded in pane history. Use answer_in_assistant_pane only when the user also asked for an explanation, the edit cannot be staged, or there is a substantive non-edit result.
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

        return """
        Active editable surface:
        surfaceID: \(snapshot.surfaceID)
        targetID: \(snapshot.targetID)
        title: \(snapshot.title)
        kind: \(snapshot.kind.rawValue)
        sourceHash: \(snapshot.sourceHash)
        anchors: \(anchors)
        text:
        \(snapshot.text)
        """
    }
}
