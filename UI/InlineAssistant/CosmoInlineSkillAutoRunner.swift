// CosmoOS/UI/InlineAssistant/CosmoInlineSkillAutoRunner.swift
// Event-driven skill activation: skills with an `autoTrigger` offer themselves
// (suggest mode: a one-tap chip, zero tokens until tapped) or run immediately
// (run mode: staging-only) when their event fires. Guardrails: never while a
// run is in flight, per-skill+surface cooldown, only enabled skills, and the
// chip is always dismissible.

import Foundation

@MainActor
final class CosmoInlineSkillAutoRunner {
    static let shared = CosmoInlineSkillAutoRunner()

    struct Suggestion: Equatable {
        let skillID: String
        let skillName: String
        let icon: String
        let prompt: String
        let surfaceID: String
    }

    /// "skillID|surfaceID" → last firing, for cooldown.
    private var lastFired: [String: Date] = [:]

    private init() {}

    func surfaceActivated(
        snapshot: CosmoEditableSourceSnapshot,
        store: CosmoInlineAssistantStore = .shared,
        registry: CosmoInlineSkillRegistry = CosmoInlineSkillRegistry()
    ) {
        fire(event: .onSurfaceActivate, snapshot: snapshot, store: store, registry: registry)
    }

    func proposalAccepted(
        surfaceID: String,
        store: CosmoInlineAssistantStore = .shared,
        registry: CosmoInlineSkillRegistry = CosmoInlineSkillRegistry()
    ) {
        guard let snapshot = CosmoEditableSurfaceRegistry.shared
            .provider(surfaceID: surfaceID)?
            .editableSnapshot() else { return }
        fire(event: .onProposalAccepted, snapshot: snapshot, store: store, registry: registry)
    }

    private func fire(
        event: CosmoInlineSkillAutoTrigger.Event,
        snapshot: CosmoEditableSourceSnapshot,
        store: CosmoInlineAssistantStore,
        registry: CosmoInlineSkillRegistry
    ) {
        guard !store.isProcessing else { return }

        let now = Date()
        for definition in registry.enabledSkills {
            guard let trigger = definition.autoTrigger,
                  trigger.event == event else { continue }
            if let kinds = trigger.surfaceKinds, !kinds.contains(snapshot.kind) { continue }
            // A resident-skill surface (concept board) only ever auto-fires its
            // own skill — other skills need an explicit slash/picker choice.
            if let resident = snapshot.residentSkillID, definition.id != resident { continue }

            let cooldownKey = "\(definition.id)|\(snapshot.surfaceID)"
            if let last = lastFired[cooldownKey],
               now.timeIntervalSince(last) < TimeInterval(trigger.cooldownMinutes * 60) {
                continue
            }
            lastFired[cooldownKey] = now

            switch trigger.mode {
            case .suggest:
                store.presentAutoSkillSuggestion(Suggestion(
                    skillID: definition.id,
                    skillName: definition.name,
                    icon: definition.icon,
                    prompt: trigger.prompt,
                    surfaceID: snapshot.surfaceID
                ))
            case .run:
                store.runAutoSkill(
                    skillID: definition.id,
                    prompt: trigger.prompt,
                    surfaceID: snapshot.surfaceID
                )
            }
            // One firing per event — the highest-priority (first) match wins;
            // stacking several auto-skills on one activation is noise.
            break
        }
    }
}
