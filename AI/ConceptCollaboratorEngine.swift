// CosmoOS/AI/ConceptCollaboratorEngine.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// A dedicated AI partner scoped to a single framework. NOT shared Cosmo — this
// engine's entire purpose is to help the user crystallize one concept into a
// rigorous framework. Socratic by default, framework-shape aware, and capable
// of returning tool-use actions that crystallize content directly into a named
// station.
//
// Model: Sonnet (strategist tier) — we want thoughtful reasoning, not speed.

import Foundation
import Observation

@MainActor
@Observable
final class ConceptCollaboratorEngine {

    // MARK: - State

    private(set) var isThinking: Bool = false
    private(set) var lastError: String?

    // MARK: - Public API

    /// Ask the collaborator a question about the current framework.
    ///
    /// The returned message may include a `crystallizeTarget` + `crystallizeContent`
    /// pair — those fields drive the in-chat "Crystallize into [SECTION]" button.
    func ask(
        prompt: String,
        frameworkTitle: String,
        conceptType: ConceptFrameworkType,
        state: ConnectionFocusModeState,
        history: [CollaboratorMessage]
    ) async -> CollaboratorMessage {
        isThinking = true
        defer { isThinking = false }

        let systemBlocks = buildSystemBlocks(
            frameworkTitle: frameworkTitle,
            conceptType: conceptType,
            state: state
        )

        var messages: [[String: Any]] = []
        for msg in history.suffix(20) {
            messages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.text
            ])
        }
        messages.append(["role": "user", "content": prompt])

        let tools: [[String: Any]] = [crystallizeToolDefinition]

        do {
            let response = try await ResearchService.shared.generateWithTools(
                systemBlocks: systemBlocks,
                messages: messages,
                tools: tools,
                model: ContentModelTier.strategist.rawValue,
                maxTokens: 2048,
                temperature: 0.6
            )
            return parseResponse(response)
        } catch {
            lastError = error.localizedDescription
            return CollaboratorMessage(
                role: .assistant,
                text: "I couldn't reach the concept collaborator. \(error.localizedDescription)"
            )
        }
    }

    // MARK: - System prompt

    private func buildSystemBlocks(
        frameworkTitle: String,
        conceptType: ConceptFrameworkType,
        state: ConnectionFocusModeState
    ) -> [PromptCacheBlock] {
        let identity = """
        You are the Concept Collaborator — a Socratic thinking partner helping the \
        user crystallize one concept into a rigorous framework. You are scoped to \
        a single framework: "\(frameworkTitle)" (\(conceptType.displayName)).

        Your tonal register: \(conceptType.collaboratorTone)

        Your job is NOT to summarize what the user has written. Your job is to ask \
        the one question they haven't asked themselves yet — or to point out a tension, \
        gap, or echo they will want to resolve.

        Rules:
        • Favor one sharp question over three safe ones.
        • Name tensions explicitly: "Your Process assumes X, but Beliefs lists not-X".
        • When a known framework echoes this one, name it and specify what makes this \
          version distinct.
        • When you have concrete content that belongs in a specific station, emit the \
          `crystallize_into_section` tool call. Otherwise, stay conversational.
        • Never hedge with "it depends" alone. Take a position; the user will push back.
        • 2-6 sentences of prose max. No bullet lists unless the user asked for one.
        """

        let contextSummary = buildContextSummary(state: state)

        return [
            PromptCacheBlock(content: identity, cacheControl: true),
            PromptCacheBlock(content: contextSummary, cacheControl: false)
        ]
    }

    private func buildContextSummary(state: ConnectionFocusModeState) -> String {
        var lines: [String] = []
        lines.append("## Current framework state\n")
        for section in state.sections {
            let items = section.items.map { "  • \($0.plainText ?? $0.content)" }.joined(separator: "\n")
            if items.isEmpty {
                lines.append("### \(section.type.displayName)\n  (empty — prompt: \(section.type.promptQuestion))")
            } else {
                lines.append("### \(section.type.displayName)\n\(items)")
            }
        }
        lines.append("")
        lines.append("Maturity: \(state.completedSectionCount)/8 stations populated.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Tool definition

    private var crystallizeToolDefinition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "crystallize_into_section",
                "description": "Propose specific content that the user should insert into one of the 8 stations. Use only when you have a concrete, atomic insight — not a paraphrase.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "section": [
                            "type": "string",
                            "enum": ConnectionSectionType.allCases.map { $0.rawValue },
                            "description": "The station to insert into."
                        ],
                        "content": [
                            "type": "string",
                            "description": "The exact text to be inserted as a new item in that station. One tight sentence, no preamble."
                        ],
                        "reasoning": [
                            "type": "string",
                            "description": "One sentence on why this belongs in this specific station."
                        ]
                    ],
                    "required": ["section", "content"]
                ]
            ]
        ]
    }

    // MARK: - Response parsing

    private func parseResponse(_ response: ClaudeToolUseResponse) -> CollaboratorMessage {
        // If a crystallize tool call came back, prefer that.
        if let call = response.toolCalls.first(where: { $0.name == "crystallize_into_section" }),
           let sectionRaw = call.input["section"] as? String,
           let section = ConnectionSectionType(rawValue: sectionRaw),
           let content = call.input["content"] as? String, !content.isEmpty {
            let reasoning = (call.input["reasoning"] as? String) ?? ""
            let body: String
            if !response.textContent.isEmpty {
                body = response.textContent
            } else if !reasoning.isEmpty {
                body = reasoning
            } else {
                body = "This belongs in \(section.displayName)."
            }
            return CollaboratorMessage(
                role: .assistant,
                text: body,
                crystallizeTarget: section,
                crystallizeContent: content
            )
        }

        let text = response.textContent.isEmpty
            ? "Tell me more about what you're holding in your head — I'll help you name the tension."
            : response.textContent
        return CollaboratorMessage(role: .assistant, text: text)
    }
}
