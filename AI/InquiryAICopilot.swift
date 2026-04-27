// CosmoOS/AI/InquiryAICopilot.swift
// Lightweight wrapper around ResearchService for the Inquiry Workspace AI Copilot.
// Routes normal inquiry replies through the mid/strategist tier; cheap classifiers
// and crystallization can use sensor/writer tiers at call sites.
// Crystallization (Phase 5) escalates to Opus via InquiryCrystallizationEngine.

import Foundation

@MainActor
final class InquiryAICopilot {
    static let shared = InquiryAICopilot()
    private init() {}

    /// Send a prompt to the AI. Returns response text or a graceful offline message.
    func ask(prompt: String, tier: AgentModelTier = .strategist) async -> String {
        do {
            let systemPrompt = """
            You are Cosmo inside the Inquiry Workspace.

            Role:
            - research collaborator
            - cognitive cartographer
            - routing assistant
            - question-driven thinking partner

            Principles:
            - Answer the user directly first.
            - Use the active question as the main frame.
            - Preserve uncertainty and say when evidence is weak.
            - Never invent citations or pretend a source says something not provided.
            - Detect when the user is creating a question, branch, note, objection, principle, source critique, lexicon term, contradiction, or model update.
            - Treat one user thought as potentially containing multiple units: claim, speculative claim, evidence, counterevidence, mechanism, assumption, source-quality note, question, or open loop.
            - Claims are not facts until supported; label weak/speculative material clearly.
            - Evidence can support, weaken, merely relate, or raise a quality warning.
            - Keep suggestions concise and actionable.
            - Prefer chat-native routing suggestions over detached workflow instructions.
            - If confidence is low, ask a clarifying question or simply answer without routing.

            Routing style:
            - When a new branch is warranted, propose one crisp question.
            - When a note appears misrouted, say where it belongs and why.
            - When current understanding should change, show a short before/after.
            - Do not over-suggest; the user should feel guided, not interrupted.
            """
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: systemPrompt,
                tier: tier
            )
            return response
        } catch {
            return "[Cosmo is offline] \(error.localizedDescription). Your captures and notes are still being saved locally."
        }
    }
}
