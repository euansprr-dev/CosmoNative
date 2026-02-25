// CosmoOS/UI/CosmoWindow/CosmoWindowMessage.swift
// Message types for the global Cosmo chat window
// February 2026

import SwiftUI

// MARK: - Message Type

/// A quick-action button sent by the agent via `send_action_buttons`.
struct CosmoActionButton: Codable, Sendable, Equatable {
    let label: String
    let action: String
}

/// Discriminates the kind of message displayed in the Cosmo window chat.
enum CosmoWindowMessageType: Codable, Sendable {
    case user
    case assistant
    case system
    case toolResult(name: String, summary: String, isError: Bool)
    case contextTrace(lookups: Int, sections: [ContextTraceSection])
    case contextChange(from: String, to: String)
    case actionButtons(buttons: [CosmoActionButton])

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case kind, name, summary, isError, fromContext, toContext, lookups, sections, buttons
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user:
            try container.encode("user", forKey: .kind)
        case .assistant:
            try container.encode("assistant", forKey: .kind)
        case .system:
            try container.encode("system", forKey: .kind)
        case .toolResult(let name, let summary, let isError):
            try container.encode("toolResult", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(summary, forKey: .summary)
            try container.encode(isError, forKey: .isError)
        case .contextTrace(let lookups, let sections):
            try container.encode("contextTrace", forKey: .kind)
            try container.encode(lookups, forKey: .lookups)
            try container.encode(sections, forKey: .sections)
        case .contextChange(let from, let to):
            try container.encode("contextChange", forKey: .kind)
            try container.encode(from, forKey: .fromContext)
            try container.encode(to, forKey: .toContext)
        case .actionButtons(let buttons):
            try container.encode("actionButtons", forKey: .kind)
            try container.encode(buttons, forKey: .buttons)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "user": self = .user
        case "assistant": self = .assistant
        case "system": self = .system
        case "toolResult":
            let name = try container.decode(String.self, forKey: .name)
            let summary = try container.decode(String.self, forKey: .summary)
            let isError = try container.decode(Bool.self, forKey: .isError)
            self = .toolResult(name: name, summary: summary, isError: isError)
        case "contextTrace":
            let lookups = try container.decode(Int.self, forKey: .lookups)
            let sections = try container.decode([ContextTraceSection].self, forKey: .sections)
            self = .contextTrace(lookups: lookups, sections: sections)
        case "contextChange":
            let from = try container.decode(String.self, forKey: .fromContext)
            let to = try container.decode(String.self, forKey: .toContext)
            self = .contextChange(from: from, to: to)
        case "actionButtons":
            let buttons = try container.decode([CosmoActionButton].self, forKey: .buttons)
            self = .actionButtons(buttons: buttons)
        default:
            self = .system
        }
    }
}

// MARK: - Mentioned Atom Info

/// Lightweight reference to a mentioned atom, stored on user messages.
/// Codable and Sendable for persistence alongside messages.
struct MentionedAtomInfo: Codable, Sendable {
    let uuid: String?
    let type: String
    let title: String

    init(uuid: String? = nil, type: String, title: String) {
        self.uuid = uuid
        self.type = type
        self.title = title
    }
}

// MARK: - Mention Context Helper

/// Shared helper for building rich mention context blocks for the AI agent.
enum MentionContextHelper {

    /// Formats key fields from a SwipeAnalysis into a concise text summary.
    static func swipeAnalysisSummary(_ analysis: SwipeAnalysis) -> String {
        var parts: [String] = []
        if let hookType = analysis.hookType {
            parts.append("Hook: \(hookType.displayName)")
        }
        if let hookText = analysis.hookText {
            parts.append("Hook text: \"\(hookText)\"")
        }
        if let hookScore = analysis.hookScore {
            parts.append("Hook score: \(String(format: "%.1f", hookScore))/10")
        }
        if let framework = analysis.frameworkType {
            parts.append("Framework: \(framework.displayName)")
        }
        if let emotion = analysis.dominantEmotion {
            parts.append("Dominant emotion: \(emotion.rawValue)")
        }
        if let sections = analysis.sections, !sections.isEmpty {
            let labels = sections.map(\.label).joined(separator: " → ")
            parts.append("Structure (\(sections.count) sections): \(labels)")
        }
        return parts.joined(separator: " | ")
    }

    /// Builds a full `## Referenced Context` block from mentioned atoms,
    /// including UUIDs, extended body text, and swipe analysis summaries.
    static func buildMentionBlock(atoms: [Atom], bodyLimit: Int = 2000) -> String {
        var mentionBlock = "## Referenced Context\n"
        for atom in atoms {
            let typeLabel = atom.type.rawValue.uppercased()
            let title = atom.title ?? "Untitled"
            let body = String((atom.body ?? "").prefix(bodyLimit))
            mentionBlock += "[\(typeLabel): \"\(title)\"] (UUID: \(atom.uuid))\n\(body)\n"

            // Include swipe analysis summary if available
            if atom.isSwipeFileAtom, let analysis = atom.swipeAnalysis {
                let summary = swipeAnalysisSummary(analysis)
                if !summary.isEmpty {
                    mentionBlock += "Swipe Analysis: \(summary)\n"
                    mentionBlock += "(Use `get_swipe_analysis` tool with UUID \(atom.uuid) for full details)\n"
                }
            }
            mentionBlock += "\n"
        }
        return mentionBlock
    }
}

// MARK: - Message

/// A single message in the Cosmo window conversation.
struct CosmoWindowMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let type: CosmoWindowMessageType
    let content: String
    let timestamp: Date
    var isStreaming: Bool

    /// Frozen tool activity groups captured from live activity when the message completes.
    /// Excluded from Codable encoding/decoding (transient UI state only).
    var toolActivityGroups: [ToolActivityGroup]?

    /// Atoms that were @-mentioned as context for this user message.
    var mentionedAtomInfo: [MentionedAtomInfo]?

    init(
        id: UUID = UUID(),
        type: CosmoWindowMessageType,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        toolActivityGroups: [ToolActivityGroup]? = nil,
        mentionedAtomInfo: [MentionedAtomInfo]? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.toolActivityGroups = toolActivityGroups
        self.mentionedAtomInfo = mentionedAtomInfo
    }

    // MARK: - Codable (exclude toolActivityGroups)

    enum CodingKeys: String, CodingKey {
        case id, type, content, timestamp, isStreaming, mentionedAtomInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(CosmoWindowMessageType.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isStreaming = try container.decode(Bool.self, forKey: .isStreaming)
        mentionedAtomInfo = try container.decodeIfPresent([MentionedAtomInfo].self, forKey: .mentionedAtomInfo)
        toolActivityGroups = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encodeIfPresent(mentionedAtomInfo, forKey: .mentionedAtomInfo)
    }

    // MARK: - Factory Methods

    static func user(_ content: String, mentionedAtoms: [MentionedAtomInfo]? = nil) -> CosmoWindowMessage {
        CosmoWindowMessage(type: .user, content: content, mentionedAtomInfo: mentionedAtoms)
    }

    static func assistant(_ content: String, isStreaming: Bool = false) -> CosmoWindowMessage {
        CosmoWindowMessage(type: .assistant, content: content, isStreaming: isStreaming)
    }

    static func system(_ content: String) -> CosmoWindowMessage {
        CosmoWindowMessage(type: .system, content: content)
    }

    static func toolResult(name: String, summary: String, isError: Bool = false) -> CosmoWindowMessage {
        CosmoWindowMessage(
            type: .toolResult(name: name, summary: summary, isError: isError),
            content: summary
        )
    }

    static func contextChange(from: String, to: String) -> CosmoWindowMessage {
        CosmoWindowMessage(
            type: .contextChange(from: from, to: to),
            content: "Context switched to \(to)"
        )
    }

    static func actionButtons(_ content: String, buttons: [CosmoActionButton]) -> CosmoWindowMessage {
        CosmoWindowMessage(
            type: .actionButtons(buttons: buttons),
            content: content
        )
    }

    /// Build a context trace message from an AgentContextTrace
    static func contextTrace(from trace: AgentContextTrace) -> CosmoWindowMessage {
        var sections: [ContextTraceSection] = []

        if let client = trace.clientProfileName {
            sections.append(ContextTraceSection(icon: "person.fill", label: "Client", detail: client))
        }

        // Merge swipes from direct tool calls (search_swipes, etc.) and writing engine internals
        let directSwipes = trace.swipesReferenced
        let engineSwipes = trace.writingEngineSwipes
        let allSwipes = Array(Set(directSwipes + engineSwipes)).filter { !$0.isEmpty && !$0.hasPrefix("0 ") }
        if !allSwipes.isEmpty {
            sections.append(ContextTraceSection(icon: "doc.text", label: "Swipes", detail: allSwipes.prefix(4).joined(separator: ", ")))
        }

        let beats = trace.beatPatternsUsed.filter { !$0.isEmpty }
        if !beats.isEmpty {
            sections.append(ContextTraceSection(icon: "waveform", label: "Beat Patterns", detail: beats.prefix(3).joined(separator: ", ")))
        }

        let writing = trace.writingToolsUsed
        if !writing.isEmpty {
            let names = writing.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
            sections.append(ContextTraceSection(icon: "pencil.line", label: "Writing Engine", detail: names.joined(separator: ", ")))
        }

        let scorecards = trace.toolCalls.filter { $0.name.contains("score") }
        for call in scorecards {
            if let summary = call.resultSummary {
                sections.append(ContextTraceSection(icon: "chart.bar", label: "Scorecard", detail: summary))
            }
        }

        return CosmoWindowMessage(
            type: .contextTrace(lookups: trace.lookupCount, sections: sections),
            content: "Context Used"
        )
    }
}

// MARK: - Context Trace Section

/// A single row in a context trace card (icon + label + detail)
struct ContextTraceSection: Codable, Sendable {
    let icon: String
    let label: String
    let detail: String
}
