// CosmoOS/AI/BrainstormAIEngine.swift
// AI Collaborator engine for the Content Brainstorm step
// Manages conversation, context assembly, and outline action parsing
// February 2026

import SwiftUI
import Combine

// MARK: - Brainstorm Action

/// An action the AI suggests for modifying the outline or core idea.
struct BrainstormAction: Identifiable, Equatable {
    let id = UUID()
    let type: ActionType
    let description: String
    let payload: String
    let targetIndex: Int?

    enum ActionType: String, Equatable {
        case addOutlineItem = "ADD"
        case editOutlineItem = "EDIT"
        case reorderOutline = "REORDER"
        case replaceOutline = "REPLACE"
        case refineCoreIdea = "REFINE_CORE_IDEA"
    }
}

// MARK: - Brainstorm Message

struct BrainstormMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    var actions: [BrainstormAction]
    var isApplied: Bool

    enum Role: String, Equatable {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String, timestamp: Date = Date(), actions: [BrainstormAction] = [], isApplied: Bool = false) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.actions = actions
        self.isApplied = isApplied
    }
}

// MARK: - Brainstorm AI Engine

@MainActor
class BrainstormAIEngine: ObservableObject {
    @Published var messages: [BrainstormMessage] = []
    @Published var isGenerating = false
    @Published var error: String?

    // Context
    var coreIdea: String = ""
    var outlineItems: [String] = []
    var contentFormat: String = ""
    var platform: String = ""
    var framework: String = ""
    var matchedSwipePreviews: [String] = []
    var atomTitle: String = ""

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        var prompt = """
        You are a senior content strategist and brainstorm collaborator in CosmoOS. \
        Your role is to help the creator develop their content idea into a strong, \
        structured outline ready for drafting.

        """

        if !atomTitle.isEmpty {
            prompt += "Content title: \(atomTitle)\n"
        }
        if !coreIdea.isEmpty {
            prompt += "Core idea: \(coreIdea)\n"
        }
        if !contentFormat.isEmpty {
            prompt += "Format: \(contentFormat)\n"
        }
        if !platform.isEmpty {
            prompt += "Platform: \(platform)\n"
        }
        if !framework.isEmpty {
            prompt += "Framework: \(framework)\n"
        }

        if !outlineItems.isEmpty {
            prompt += "\nCurrent outline:\n"
            for (i, item) in outlineItems.enumerated() {
                prompt += "\(i + 1). \(item)\n"
            }
        }

        if !matchedSwipePreviews.isEmpty {
            prompt += "\nMatched swipe file excerpts (proven content examples):\n"
            for preview in matchedSwipePreviews.prefix(3) {
                prompt += "- \(preview)\n"
            }
        }

        prompt += """

        RESPONSE FORMAT:
        Respond conversationally. When suggesting changes to the outline or core idea, \
        include action blocks in this exact format on their own lines:

        [ACTION:ADD] New outline item text here
        [ACTION:EDIT:2] Updated text for item 2
        [ACTION:REORDER] 3,1,2,4 (new order by item numbers)
        [ACTION:REPLACE] Item 1 | Item 2 | Item 3 (full replacement, pipe-separated)
        [ACTION:REFINE_CORE_IDEA] Refined core idea text here

        Only include action blocks when you are specifically suggesting changes. \
        For general discussion, just respond normally without action blocks. \
        Keep responses focused and under 200 words unless the user asks for detail.
        """

        return prompt
    }

    // MARK: - Send Message

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = BrainstormMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        isGenerating = true
        error = nil

        do {
            let fullPrompt = assembleConversationPrompt(userQuery: trimmed)
            let response = try await ResearchService.shared.analyzeContent(prompt: fullPrompt)
            let (cleanText, actions) = parseActions(from: response)

            let assistantMessage = BrainstormMessage(
                role: .assistant,
                content: cleanText,
                actions: actions
            )
            messages.append(assistantMessage)
        } catch {
            self.error = error.localizedDescription
            let errorMessage = BrainstormMessage(
                role: .assistant,
                content: "I had trouble generating a response. Please try again."
            )
            messages.append(errorMessage)
        }

        isGenerating = false
    }

    // MARK: - Quick Actions

    func suggestOutline() async {
        await sendMessage("Suggest a complete outline structure for this content based on the core idea, format, and framework. Include 5-7 points.")
    }

    func improveHook() async {
        await sendMessage("Suggest 3 strong hook variants for this content that would grab attention in the first 3 seconds.")
    }

    func frameworkBreakdown() async {
        if !framework.isEmpty {
            await sendMessage("Break down how the \(framework) framework would structure this specific content. Show me each section with suggested talking points.")
        } else {
            await sendMessage("Recommend the best content framework for this idea and show how it would structure the content.")
        }
    }

    func generateHookVariants() async {
        await sendMessage("Generate 5 hook variants for this content. Include pattern interrupts, questions, bold claims, and story openers.")
    }

    func topCreatorStructure() async {
        await sendMessage("How would a top creator in this space structure this content? What patterns do the best-performing pieces follow?")
    }

    // MARK: - Conversation Assembly

    private func assembleConversationPrompt(userQuery: String) -> String {
        var prompt = buildSystemPrompt()
        prompt += "\n\n--- CONVERSATION ---\n\n"

        // Include recent message history (last 10 messages for context window)
        let recentMessages = messages.suffix(10)
        for msg in recentMessages {
            switch msg.role {
            case .user:
                prompt += "User: \(msg.content)\n\n"
            case .assistant:
                prompt += "Assistant: \(msg.content)\n\n"
            case .system:
                break
            }
        }

        prompt += "User: \(userQuery)\n\nAssistant:"
        return prompt
    }

    // MARK: - Action Parser

    private func parseActions(from response: String) -> (cleanText: String, actions: [BrainstormAction]) {
        var actions: [BrainstormAction] = []
        var cleanLines: [String] = []

        let lines = response.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[ACTION:ADD]") {
                let payload = String(trimmed.dropFirst("[ACTION:ADD]".count)).trimmingCharacters(in: .whitespaces)
                if !payload.isEmpty {
                    actions.append(BrainstormAction(
                        type: .addOutlineItem,
                        description: "Add: \(payload)",
                        payload: payload,
                        targetIndex: nil
                    ))
                }
            } else if trimmed.hasPrefix("[ACTION:EDIT:") {
                // Parse [ACTION:EDIT:N] text
                if let closeBracket = trimmed.firstIndex(of: "]") {
                    let prefix = trimmed[trimmed.index(trimmed.startIndex, offsetBy: "[ACTION:EDIT:".count)..<closeBracket]
                    let index = Int(prefix)
                    let payload = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
                    if !payload.isEmpty {
                        actions.append(BrainstormAction(
                            type: .editOutlineItem,
                            description: "Edit item \(index ?? 0): \(payload)",
                            payload: payload,
                            targetIndex: index.map { $0 - 1 }
                        ))
                    }
                }
            } else if trimmed.hasPrefix("[ACTION:REORDER]") {
                let payload = String(trimmed.dropFirst("[ACTION:REORDER]".count)).trimmingCharacters(in: .whitespaces)
                if !payload.isEmpty {
                    actions.append(BrainstormAction(
                        type: .reorderOutline,
                        description: "Reorder outline",
                        payload: payload,
                        targetIndex: nil
                    ))
                }
            } else if trimmed.hasPrefix("[ACTION:REPLACE]") {
                let payload = String(trimmed.dropFirst("[ACTION:REPLACE]".count)).trimmingCharacters(in: .whitespaces)
                if !payload.isEmpty {
                    actions.append(BrainstormAction(
                        type: .replaceOutline,
                        description: "Replace entire outline",
                        payload: payload,
                        targetIndex: nil
                    ))
                }
            } else if trimmed.hasPrefix("[ACTION:REFINE_CORE_IDEA]") {
                let payload = String(trimmed.dropFirst("[ACTION:REFINE_CORE_IDEA]".count)).trimmingCharacters(in: .whitespaces)
                if !payload.isEmpty {
                    actions.append(BrainstormAction(
                        type: .refineCoreIdea,
                        description: "Refine core idea",
                        payload: payload,
                        targetIndex: nil
                    ))
                }
            } else {
                cleanLines.append(line)
            }
        }

        let cleanText = cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanText, actions)
    }

    // MARK: - Apply Action

    func markMessageApplied(_ messageId: UUID) {
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            messages[idx].isApplied = true
        }
    }

    // MARK: - Update Context

    func updateContext(
        coreIdea: String,
        outline: [OutlineItem],
        title: String,
        contentFormat: String = "",
        platform: String = "",
        framework: String = "",
        swipePreviews: [String] = []
    ) {
        self.coreIdea = coreIdea
        self.outlineItems = outline.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.title)
        self.atomTitle = title
        self.contentFormat = contentFormat
        self.platform = platform
        self.framework = framework
        self.matchedSwipePreviews = swipePreviews
    }
}
