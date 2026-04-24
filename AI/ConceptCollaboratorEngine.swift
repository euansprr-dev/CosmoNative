// CosmoOS/AI/ConceptCollaboratorEngine.swift
// April 2026 — connection-native collaborator
//
// Dedicated AI partner for one Connection artifact. The personality and
// questioning strategy come from the shared collaborator source prompt; this
// engine adds connection-specific context, section-aware draft staging, and
// prompt-faithful guardrails.

import Foundation
import Observation

@MainActor
@Observable
final class ConceptCollaboratorEngine {

    // MARK: - State

    private(set) var isThinking: Bool = false
    private(set) var lastError: String?

    // MARK: - Public API

    func ask(
        prompt: String,
        frameworkTitle: String,
        conceptType: ConceptFrameworkType,
        state: ConnectionFocusModeState,
        linkedSources: [Atom],
        history: [CollaboratorMessage],
        isBootstrap: Bool = false
    ) async -> CollaboratorMessage {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallbackMessage(for: state, linkedSources: linkedSources)
        }

        isThinking = true
        defer { isThinking = false }

        let systemBlocks = buildSystemBlocks(
            frameworkTitle: frameworkTitle,
            conceptType: conceptType,
            state: state,
            linkedSources: linkedSources,
            isBootstrap: isBootstrap
        )

        var messages = history.suffix(16).map(historyMessagePayload)
        messages.append(["role": "user", "content": trimmed])

        do {
            let response = try await ResearchService.shared.generateWithTools(
                systemBlocks: systemBlocks,
                messages: messages,
                tools: [stageTurnToolDefinition],
                model: ContentModelTier.strategist.rawValue,
                maxTokens: 2200,
                temperature: 0.55
            )
            return parseResponse(
                response,
                state: state,
                linkedSources: linkedSources
            )
        } catch {
            lastError = error.localizedDescription
            return CollaboratorMessage(
                role: .assistant,
                text: "I couldn't reach the collaborator just now. Try again in a moment."
            )
        }
    }

    // MARK: - Prompt Construction

    private func buildSystemBlocks(
        frameworkTitle: String,
        conceptType: ConceptFrameworkType,
        state: ConnectionFocusModeState,
        linkedSources: [Atom],
        isBootstrap: Bool
    ) -> [PromptCacheBlock] {
        let runtimePrompt = CollaboratorPreset.deepenConnection.runtimePrompt

        let operatingRules = """
        ### Connection Collaborator Operating Rules
        You are collaborating inside one Connection artifact: "\(frameworkTitle)" (\(conceptType.displayName)).

        Context status:
        - populated sections: \(state.completedSectionCount)/8
        - linked sources: \(linkedSources.count)
        - bootstrap turn: \(isBootstrap ? "yes" : "no")

        Connection-specific rules:
        - The current connection is the working surface. Additive drafts belong in one section at a time.
        - If the connection is blank or barely started, invite the user to send the core idea even if it is messy.
        - If the connection already has material, begin from what is already written and any linked sources.
        - Ask one question at a time or stage one section-targeted draft. Do not do both aggressively.
        - Never use canned filler like "What's the tension?" unless the user uses that language first.
        - Observation kind, if any, must be one of: pattern, paradox, name, contrast, sourceLink.
        - Use linked sources only when they materially sharpen the question, observation, or draft.
        - Keep prose to 2-5 sentences.
        - Use the `stage_connection_turn` tool for every reply.
        """

        return [
            PromptCacheBlock(
                content: runtimePrompt,
                cacheControl: true,
                ttl: "1h",
                label: "collaborator-source-prompt"
            ),
            PromptCacheBlock(
                content: operatingRules,
                cacheControl: true,
                ttl: "1h",
                label: "connection-operating-rules"
            ),
            PromptCacheBlock(
                content: buildContextSummary(
                    frameworkTitle: frameworkTitle,
                    conceptType: conceptType,
                    state: state,
                    linkedSources: linkedSources
                ),
                cacheControl: false,
                label: "connection-context"
            )
        ]
    }

    private func buildContextSummary(
        frameworkTitle: String,
        conceptType: ConceptFrameworkType,
        state: ConnectionFocusModeState,
        linkedSources: [Atom]
    ) -> String {
        var lines: [String] = []
        let resolvedTitle = frameworkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Connection"
            : frameworkTitle

        lines.append("## Connection")
        lines.append("Title: \(resolvedTitle)")
        lines.append("Type: \(conceptType.displayName)")
        lines.append("Completed sections: \(state.completedSectionCount)/8")
        lines.append("")
        lines.append("## Sections")

        for section in state.sections {
            let items = section.items.prefix(5).map { $0.resolvedPlainText }
            if items.isEmpty {
                lines.append("### \(section.type.rawValue)")
                lines.append("(empty)")
            } else {
                lines.append("### \(section.type.rawValue)")
                for item in items {
                    lines.append("- \(item)")
                }
            }
        }

        if linkedSources.isEmpty {
            lines.append("")
            lines.append("## Linked sources")
            lines.append("(none)")
        } else {
            lines.append("")
            lines.append("## Linked sources")
            for source in linkedSources.prefix(6) {
                let resolvedTitle: String
                if let sourceTitle = source.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !sourceTitle.isEmpty {
                    resolvedTitle = sourceTitle
                } else {
                    resolvedTitle = "Untitled"
                }
                let snippet = String(source.body?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .joined(separator: " ")
                    .prefix(220) ?? "")
                lines.append("- id: \(source.uuid)")
                lines.append("  title: \(resolvedTitle)")
                if !snippet.isEmpty {
                    lines.append("  snippet: \(snippet)")
                }
            }
        }

        if let draft = state.activeDraftProposal {
            lines.append("")
            lines.append("## Active draft proposal")
            lines.append("Section: \(draft.targetSection.rawValue)")
            lines.append("Status: \(draft.status.rawValue)")
            lines.append("Draft: \(draft.draftText)")
        }

        return lines.joined(separator: "\n")
    }

    private func historyMessagePayload(_ message: CollaboratorMessage) -> [String: Any] {
        var content = message.text
        if let draft = message.draftProposal {
            content += "\n\n[Draft proposal for \(draft.targetSection.displayName)]: \(draft.draftText)"
        }
        if let observationKind = message.observationKind {
            content += "\n[Observation: \(observationKind.rawValue)]"
        }
        if let question = message.questionSuggestion {
            content += "\n[Question suggestion]: \(question)"
        }
        return [
            "role": message.role == .user ? "user" : "assistant",
            "content": content
        ]
    }

    // MARK: - Tool Definition

    private var stageTurnToolDefinition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "stage_connection_turn",
                "description": "Return the next collaborator turn for this connection. Include assistant_text every time. Optionally include one observation kind, one question suggestion, and one additive section-targeted draft proposal.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "assistant_text": [
                            "type": "string",
                            "description": "The assistant's visible reply in 2-5 sentences."
                        ],
                        "observation_kind": [
                            "type": "string",
                            "enum": CollaboratorObservationKind.allCases.map(\.rawValue),
                            "description": "Optional observation label when the reply is primarily a pattern, paradox, name, contrast, or source link."
                        ],
                        "question_suggestion": [
                            "type": "string",
                            "description": "Optional single follow-up question grounded in the source prompt's question patterns."
                        ],
                        "recommended_action": [
                            "type": "string",
                            "description": "Optional short next move, such as using linked sources or revising a draft."
                        ],
                        "draft": [
                            "type": "object",
                            "properties": [
                                "section": [
                                    "type": "string",
                                    "enum": ConnectionSectionType.allCases.map(\.rawValue),
                                    "description": "The section that should receive the draft."
                                ],
                                "draft_text": [
                                    "type": "string",
                                    "description": "The exact additive draft text for the target section."
                                ],
                                "rationale": [
                                    "type": "string",
                                    "description": "One sentence on why this belongs in that section."
                                ],
                                "source_ids": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "Optional array of linked source UUIDs used for the draft."
                                ]
                            ],
                            "required": ["section", "draft_text"]
                        ]
                    ],
                    "required": ["assistant_text"]
                ]
            ]
        ]
    }

    // MARK: - Response Parsing

    private func parseResponse(
        _ response: ClaudeToolUseResponse,
        state: ConnectionFocusModeState,
        linkedSources: [Atom]
    ) -> CollaboratorMessage {
        let linkedSourceIDs = Set(linkedSources.map(\.uuid))

        if let call = response.toolCalls.first(where: { $0.name == "stage_connection_turn" }) {
            let input = call.input
            let assistantText = sanitizeAssistantText(
                (input["assistant_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? response.textContent.trimmingCharacters(in: .whitespacesAndNewlines),
                state: state
            )
            let observationKind = (input["observation_kind"] as? String)
                .flatMap(CollaboratorObservationKind.init(rawValue:))
            let questionSuggestion = sanitizeQuestionSuggestion(
                (input["question_suggestion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let recommendedAction = (input["recommended_action"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var draftProposal: ConnectionDraftProposal?
            if let draftInput = input["draft"] as? [String: Any],
               let sectionRaw = draftInput["section"] as? String,
               let section = ConnectionSectionType(rawValue: sectionRaw),
               let draftText = (draftInput["draft_text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !draftText.isEmpty {
                let rationale = (draftInput["rationale"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let sourceIDs = (draftInput["source_ids"] as? [String] ?? [])
                    .filter { linkedSourceIDs.contains($0) }
                draftProposal = ConnectionDraftProposal(
                    targetSection: section,
                    draftText: draftText,
                    visibleText: "",
                    rationale: rationale,
                    sourceIDs: sourceIDs,
                    status: .streaming
                )
            }

            return CollaboratorMessage(
                role: .assistant,
                text: assistantText,
                observationKind: observationKind,
                questionSuggestion: questionSuggestion,
                recommendedAction: recommendedAction,
                draftProposal: draftProposal
            )
        }

        let text = sanitizeAssistantText(
            response.textContent.trimmingCharacters(in: .whitespacesAndNewlines),
            state: state
        )
        return CollaboratorMessage(
            role: .assistant,
            text: text.isEmpty ? fallbackText(for: state, linkedSources: linkedSources) : text
        )
    }

    private func sanitizeAssistantText(_ text: String, state: ConnectionFocusModeState) -> String {
        guard !text.isEmpty else {
            return fallbackText(for: state, linkedSources: [])
        }

        return text
            .replacingOccurrences(of: "What's the tension?", with: "What specifically about this is interesting to you?")
            .replacingOccurrences(of: "what's the tension?", with: "what specifically about this is interesting to you?")
            .replacingOccurrences(of: "name the tension", with: "name the idea")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeQuestionSuggestion(_ question: String?) -> String? {
        guard let question, !question.isEmpty else { return nil }
        let cleaned = question
            .replacingOccurrences(of: "What's the tension?", with: "What specifically about this is interesting to you?")
            .replacingOccurrences(of: "what's the tension?", with: "what specifically about this is interesting to you?")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func fallbackText(
        for state: ConnectionFocusModeState,
        linkedSources: [Atom]
    ) -> String {
        if state.completedSectionCount == 0 {
            if linkedSources.isEmpty {
                return "It can be messy. One sentence, a link, a half-formed question. Doesn't matter."
            }
            return "It can be messy. One sentence, a link, a half-formed question. Doesn't matter. If you want, I can also use the linked sources."
        }
        return "What specifically about this is interesting to you?"
    }

    private func fallbackMessage(
        for state: ConnectionFocusModeState,
        linkedSources: [Atom]
    ) -> CollaboratorMessage {
        CollaboratorMessage(
            role: .assistant,
            text: fallbackText(for: state, linkedSources: linkedSources)
        )
    }
}
