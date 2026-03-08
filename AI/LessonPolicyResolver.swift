// CosmoOS/AI/LessonPolicyResolver.swift
// Centralized lesson resolution for writing engine and agent contexts.
// Single source of truth: reads from canonical .agentLearning atoms via LessonExtractor.
// Replaces dual-path lesson loading (loadLearnedPreferences + formatLessonsForPrompt).
// March 2026

import Foundation

// MARK: - Resolved Lesson Policy

/// Output of LessonPolicyResolver — pre-formatted lesson blocks ready for prompt injection.
struct ResolvedLessonPolicy {
    let hardRules: [InferredLesson]
    let advisoryRules: [InferredLesson]
    /// Pre-formatted text block for injection into UnifiedWritingEngine Block 2
    let formattedBlock: String
    /// Total lesson count
    var totalCount: Int { hardRules.count + advisoryRules.count }
}

// MARK: - Lesson Policy Resolver

@MainActor
enum LessonPolicyResolver {

    /// Maximum lessons to include in any prompt (respects token budget)
    private static let maxLessons = 15

    // MARK: - Writing Engine Resolution

    /// Resolve lessons for UnifiedWritingEngine Block 2 injection.
    /// Returns hard rules first (with violation warnings), then advisory rules.
    /// Also loads .userPreference atoms for the client.
    static func resolveForWritingEngine(
        clientUUID: String?,
        intent: String? = "draft",
        format: String? = nil
    ) async -> ResolvedLessonPolicy {
        let lessons = await loadAndCategorize(clientUUID: clientUUID, intent: intent)

        // Cap total lessons
        let hardCapped = Array(lessons.hard.prefix(maxLessons))
        let advisoryBudget = max(0, maxLessons - hardCapped.count)
        let advisoryCapped = Array(lessons.advisory.prefix(advisoryBudget))

        let block = formatWritingEngineBlock(
            hard: hardCapped,
            advisory: advisoryCapped,
            clientUUID: clientUUID
        )

        return ResolvedLessonPolicy(
            hardRules: hardCapped,
            advisoryRules: advisoryCapped,
            formattedBlock: block
        )
    }

    // MARK: - Agent Context Resolution

    /// Resolve lessons for agent-level context injection (AgentContextAssembler).
    /// Returns formatted prompt block matching the existing LEARNED SKILLS format.
    static func resolveForAgent(
        clientUUID: UUID? = nil,
        intent: String? = nil
    ) async -> (formatted: String, lessons: [(rule: String, category: String, intent: String?)]) {
        let clientStr = clientUUID?.uuidString
        let lessons = await loadAndCategorize(clientUUID: clientStr, intent: intent)

        let allLessons = (lessons.hard + lessons.advisory).prefix(maxLessons)
        guard !allLessons.isEmpty else { return ("", []) }

        var lines: [String] = []
        lines.append("=== LEARNED SKILLS ===")
        lines.append("These rules were learned from the user's past patterns and explicit instructions.")
        lines.append("Follow them strictly — violating these is a guaranteed rejection.")
        lines.append("")

        for (i, lesson) in allLessons.enumerated() {
            let scope = lesson.clientUUID != nil ? "[client-specific]" : "[universal]"
            let intentLabel = lesson.intent != nil ? " [\(lesson.intent!)]" : ""
            let enforcementBadge = lesson.effectiveEnforcement == .hard ? " [HARD]" : ""

            if let optimized = lesson.optimizedInstruction, !optimized.isEmpty {
                lines.append("\(i + 1). \(scope)\(intentLabel)\(enforcementBadge) \(optimized)")
            } else {
                lines.append("\(i + 1). \(scope)\(intentLabel)\(enforcementBadge) RULE: \(lesson.rule)")
                lines.append("   EVIDENCE: \(lesson.evidence)")
            }
            lines.append("")
        }

        let trackedLessons = allLessons.map { (rule: $0.rule, category: $0.category, intent: $0.intent) }
        return (lines.joined(separator: "\n"), Array(trackedLessons))
    }

    // MARK: - Private Helpers

    private struct CategorizedLessons {
        let hard: [InferredLesson]
        let advisory: [InferredLesson]
    }

    /// Load lessons from LessonExtractor and split into hard vs advisory.
    private static func loadAndCategorize(
        clientUUID: String?,
        intent: String?
    ) async -> CategorizedLessons {
        let uuid = clientUUID.flatMap { UUID(uuidString: $0) }
        // Use lower confidence threshold (0.3) to include unconfirmed lessons as advisory
        let allLessons = await LessonExtractor.shared.loadLessons(
            clientUUID: uuid,
            intent: intent,
            minConfidence: 0.3
        )

        var hard: [InferredLesson] = []
        var advisory: [InferredLesson] = []

        for lesson in allLessons {
            switch lesson.effectiveEnforcement {
            case .hard:
                hard.append(lesson)
            case .advisory:
                advisory.append(lesson)
            }
        }

        // Sort: higher confidence first within each tier
        hard.sort { $0.confidence > $1.confidence }
        advisory.sort { $0.confidence > $1.confidence }

        return CategorizedLessons(hard: hard, advisory: advisory)
    }

    /// Format lessons as a Block 2 section for UnifiedWritingEngine.
    /// Hard rules get prominent "MANDATORY" framing; advisory rules are softer.
    private static func formatWritingEngineBlock(
        hard: [InferredLesson],
        advisory: [InferredLesson],
        clientUUID: String?
    ) -> String {
        guard !hard.isEmpty || !advisory.isEmpty else { return "" }

        var block = ""

        // Hard rules — mandatory, violation = forced rewrite
        if !hard.isEmpty {
            block += "\n\n## LEARNED WRITING RULES — MANDATORY (HARD)\n"
            block += "These rules were learned from the user's past edits and explicit instructions.\n"
            block += "Violating ANY of these will trigger an automatic rewrite. Follow them exactly.\n\n"

            for (i, lesson) in hard.enumerated() {
                let scope = (lesson.clientUUID == nil || lesson.clientUUID?.isEmpty == true) ? "[universal]" : "[client-specific]"
                if let optimized = lesson.optimizedInstruction, !optimized.isEmpty {
                    block += "\(i + 1). \(scope) \(optimized)\n\n"
                } else {
                    block += "\(i + 1). \(scope) RULE: \(lesson.rule)\n"
                    block += "   EVIDENCE: \(lesson.evidence)\n"
                    block += "   CATEGORY: \(lesson.category)\n\n"
                }
            }
        }

        // Advisory rules — should follow but won't force rewrite
        if !advisory.isEmpty {
            block += "\n## LEARNED WRITING PREFERENCES — ADVISORY\n"
            block += "These patterns were observed from the user's edits. Follow when possible.\n\n"

            for (i, lesson) in advisory.enumerated() {
                let scope = (lesson.clientUUID == nil || lesson.clientUUID?.isEmpty == true) ? "[universal]" : "[client-specific]"
                if let optimized = lesson.optimizedInstruction, !optimized.isEmpty {
                    block += "\(i + 1). \(scope) \(optimized)\n\n"
                } else {
                    block += "\(i + 1). \(scope) RULE: \(lesson.rule)\n\n"
                }
            }
        }

        return block
    }
}
