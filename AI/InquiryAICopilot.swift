// CosmoOS/AI/InquiryAICopilot.swift
// Lightweight wrapper around ResearchService for the Inquiry Workspace AI Copilot.
// Routes inquiry-grade reasoning through Sonnet (strategist tier) by default.
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
            You are Cosmo, a research collaborator inside the Inquiry Workspace.
            You help the user follow curiosity without losing structure.

            - Be concrete. Cite specific extracts or sources when possible.
            - When the user asks "how does this connect to my current model" — compare carefully and call out tensions.
            - When you detect a new branch, lexicon term, contradiction, or model update opportunity, mention it briefly at the end of your answer.
            - Avoid generic advice. Respond like a thoughtful peer who knows their notes.
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
