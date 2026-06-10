// Tests for the Concept inline-assistant skill: slash resolution, plan
// routing, multi-turn stickiness, and registry surfacing.

import Testing
import Foundation
@testable import CosmoOS

struct ConceptSkillRoutingTests {

    private var registry: CosmoInlineSkillRegistry {
        CosmoInlineSkillRegistry(store: .inMemory())
    }

    @Test func slashConceptResolvesTheSkill() {
        let command = CosmoInlineSlashSkillParser.extractCommand(
            from: "/concept let's develop the trust loop idea",
            registry: registry
        )
        #expect(command != nil)
        let resolved = command.flatMap { registry.skill(id: $0.skillID) }
        #expect(resolved?.baseSkillID == .concept)
        #expect(command?.remainingPrompt == "let's develop the trust loop idea")
    }

    @Test func planWithSelectedConceptSkillUsesAnswerRouteAndPane() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "let's develop this",
            surfaceKind: nil,
            previousSkillID: nil,
            selectedSkillID: "concept",
            registry: registry
        )
        #expect(plan.primarySkill.id == .concept)
        #expect(plan.route == .answer)
        #expect(plan.panePolicy == .openForAnswer)
        #expect(plan.toolBundles.contains(.workspaceEditing))
    }

    @Test func conceptSticksAcrossTerseFollowUpTurns() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "because it compounds over time",
            surfaceKind: nil,
            previousSkillID: .concept,
            selectedSkillID: nil,
            registry: registry
        )
        #expect(plan.primarySkill.id == .concept)
    }

    @Test func conceptStickinessSurvivesEditLikeWording() {
        // "add that to claims" is edit-like, but mid-concept-session it must
        // stay with the concept partner (which stages the edit itself).
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "add that to claims",
            surfaceKind: .structured,
            previousSkillID: .concept,
            selectedSkillID: nil,
            registry: registry
        )
        #expect(plan.primarySkill.id == .concept)
    }

    @Test func otherPreviousSkillsDoNotInheritStickiness() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "what are typical airbnb cleaning costs?",
            surfaceKind: nil,
            previousSkillID: .inlineEdit,
            selectedSkillID: nil,
            registry: registry
        )
        #expect(plan.primarySkill.id == .researchAnswer)
    }

    @Test func explicitSlashSelectionOverridesConceptStickiness() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "rewrite the hook",
            surfaceKind: .text,
            previousSkillID: .concept,
            selectedSkillID: "inlineEdit",
            registry: registry
        )
        #expect(plan.primarySkill.id == .inlineEdit)
    }

    @Test func registrySurfacesConceptInSlashMenu() {
        let matches = registry.matchingSlashCommands(query: "conc", limit: 10)
        #expect(matches.contains { $0.baseSkillID == .concept })
    }

    // MARK: - Skill session behavior (store level)

    @Test @MainActor func bareSlashCommandStartsTheSkillInsteadOfNoOp() async {
        var sentPrompt: String?
        var sentRoute: CosmoInlineAssistantRoute?
        let bridge = CosmoInlineAssistantAgentBridge { prompt, route, _ in
            sentPrompt = prompt
            sentRoute = route
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "/concept"

        await store.submit()

        #expect(sentPrompt?.isEmpty == false)
        #expect(sentRoute == .answer)
    }

    @Test @MainActor func skillSessionStaysStickyAcrossTurns() async {
        var routes: [CosmoInlineAssistantRoute] = []
        var skillIDsDuringSend: [String?] = []
        let bridge = CosmoInlineAssistantAgentBridge { _, route, store in
            routes.append(route)
            skillIDsDuringSend.append(store.activeSubmissionSkillID)
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)

        store.composerText = "/concept let's develop trust loops"
        await store.submit()
        #expect(store.selectedSkillID == "concept")

        // A terse follow-up with no slash command stays in the skill session.
        store.composerText = "because it compounds over time"
        await store.submit()

        #expect(store.selectedSkillID == "concept")
        #expect(skillIDsDuringSend == ["concept", "concept"])
        #expect(routes == [.answer, .answer])
    }

    @Test @MainActor func clearCommandEndsTheSkillSession() async {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.composerText = "/concept start"
        await store.submit()
        #expect(store.selectedSkillID == "concept")

        store.composerText = "/clear"
        await store.submit()
        #expect(store.selectedSkillID == nil)
    }

    @Test @MainActor func newSlashCommandReplacesTheActiveSkillSession() async {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.composerText = "/concept start"
        await store.submit()
        #expect(store.selectedSkillID == "concept")

        store.composerText = "/inlineEdit tighten the hook"
        await store.submit()
        #expect(store.selectedSkillID == "inlineEdit")
    }

    @Test func conceptSkillDefinitionShape() {
        let skill = CosmoInlineAssistantSkillRuntime.builtInSkill(.concept)
        #expect(skill.name == "Concept")
        #expect(skill.route == .answer)
        #expect(!skill.requiresReviewedDiff)
        #expect(skill.toolBundles.contains(.workspaceEditing))
        #expect(skill.toolBundles.contains(.contentSearch))
        #expect(skill.instructions.contains { $0.contains("create_connection") })
        #expect(skill.instructions.contains { $0.contains("propose_workspace_edit") })
        #expect(skill.triggerPhrases.contains("concept"))
    }
}
