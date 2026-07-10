// Tests/CosmoOSTests/CritiqueSkillTests.swift
// The /critique skill contract: it resolves unambiguously from the slash
// grammar, routes as an action through the reviewed-diff (NEVER-BLOCK apply)
// pipeline, and carries the taste-grounding contexts.

import Testing
@testable import CosmoOS

struct CritiqueSkillTests {

    private var registry: CosmoInlineSkillRegistry {
        CosmoInlineSkillRegistry(store: .inMemory())
    }

    @Test func slashCritiqueResolvesTheSkill() {
        let command = CosmoInlineSlashSkillParser.extractCommand(
            from: "/critique the hook feels soft",
            registry: registry
        )
        #expect(command != nil)
        let resolved = command.flatMap { registry.skill(id: $0.skillID) }
        #expect(resolved?.baseSkillID == .critique)
        #expect(command?.remainingPrompt == "the hook feels soft")
    }

    @Test func slashCritDoesNotCollideWithContentReview() {
        // "critique" must never resolve to contentReview (which used to carry
        // the same trigger phrase).
        let command = CosmoInlineSlashSkillParser.extractCommand(
            from: "/critique",
            registry: registry
        )
        let resolved = command.flatMap { registry.skill(id: $0.skillID) }
        #expect(resolved?.baseSkillID == .critique)
    }

    @Test func critiqueIsAnActionWithReviewedDiff() {
        let skill = CosmoInlineAssistantSkillRuntime.builtInSkill(.critique)
        #expect(skill.route == .action)
        #expect(skill.requiresReviewedDiff)
        #expect(skill.outputContract == "reviewed_diff")
        // No auto-trigger: critique runs only when the user asks.
        #expect(skill.requiredContext.contains(.voiceLessons))
        #expect(skill.requiredContext.contains(.clientProfile))
        #expect(skill.toolBundles.contains(.workspaceEditing))
    }

    @Test func critiqueInstructionsCarryTheSilenceLaw() {
        let skill = CosmoInlineAssistantSkillRuntime.builtInSkill(.critique)
        #expect(skill.instructions.contains { $0.contains("stage NOTHING") })
        #expect(skill.instructions.contains { $0.contains("LEARNED TASTE") })
    }
}
