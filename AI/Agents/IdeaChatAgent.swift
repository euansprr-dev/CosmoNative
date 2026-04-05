// CosmoOS/AI/Agents/IdeaChatAgent.swift
// Tier 2 agent: conversational brainstorm with idea context awareness.

import Foundation

@MainActor
final class IdeaChatAgent {
    static let shared = IdeaChatAgent()
    private init() {}

    private let model = "google/gemini-3-flash-preview"
    private let maxHistoryMessages = 10

    func chat(
        message: String,
        ideaContext: String,
        history: [IdeaChatMessage]
    ) async throws -> IdeaChatMessage {
        let systemPrompt = """
        You help brainstorm content ideas. You are a creative collaborator embedded in a content \
        creation workspace. You can help with:
        - Refining the core idea angle
        - Suggesting hooks and opening lines
        - Identifying the best proof types and evidence
        - Recommending structural approaches (arc shapes)
        - Exploring audience psychology and reader deltas
        - Finding connections to existing swipe file posts

        Be concise, creative, and actionable. Respond in 2-4 sentences unless the user asks for \
        more detail. Use plain text — no markdown headers or bullet points unless listing options.
        """

        // Build conversation messages from recent history
        let recentHistory = history.suffix(maxHistoryMessages)

        var conversationParts: [String] = []
        conversationParts.append("CURRENT IDEA CONTEXT:\n\(ideaContext)\n")

        for msg in recentHistory {
            let prefix = msg.role == "user" ? "User" : "Assistant"
            conversationParts.append("\(prefix): \(msg.content)")
        }
        conversationParts.append("User: \(message)")

        let fullPrompt = conversationParts.joined(separator: "\n\n")

        let response = try await ResearchService.shared.analyze(
            prompt: fullPrompt,
            systemPrompt: systemPrompt,
            model: model,
            maxTokens: 1000,
            temperature: 0.7
        )

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        return IdeaChatMessage(
            id: UUID(),
            role: "assistant",
            content: trimmed,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            actionCards: nil
        )
    }
}
