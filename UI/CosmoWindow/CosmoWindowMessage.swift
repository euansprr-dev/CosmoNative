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

/// Data for an inline atom card rendered in chat
struct AtomCardData: Codable, Sendable {
    let uuid: String
    let type: String
    let title: String
    let snippet: String
    let score: Double?
}

/// Data for an inline atom list rendered in chat
struct AtomListData: Codable, Sendable {
    let query: String
    let atoms: [AtomCardData]
    let totalCount: Int
}

/// A node in the inline graph view
struct GraphNodeData: Codable, Sendable {
    let uuid: String
    let type: String
    let title: String
}

/// An edge in the inline graph view
struct GraphEdgeData: Codable, Sendable {
    let sourceUuid: String
    let targetUuid: String
    let linkType: String?
}

/// Data for the inline graph view
struct GraphViewData: Codable, Sendable {
    let centerUuid: String
    let nodes: [GraphNodeData]
    let edges: [GraphEdgeData]
}

/// Data for an automation preview card
struct AutomationPreviewData: Codable, Sendable {
    let name: String
    let triggerDescription: String
    let actionDescriptions: [String]
    let isEnabled: Bool
    let uuid: String?
}

/// Data for a multi-step workflow plan
struct WorkflowPlanData: Codable, Sendable {
    let description: String
    let steps: [WorkflowStepData]
}

/// A single step in a workflow plan
struct WorkflowStepData: Codable, Sendable {
    let index: Int
    let tool: String
    let description: String
    let status: String  // pending, running, done, failed
}

/// Data for a timeline view
struct TimelineViewData: Codable, Sendable {
    let entries: [TimelineEntryData]
}

/// A single entry in the timeline
struct TimelineEntryData: Codable, Sendable {
    let uuid: String
    let type: String
    let title: String
    let timestamp: String
}

/// Data for a knowledge synthesis card
struct SynthesisCardData: Codable, Sendable {
    let query: String
    let synthesis: String
    let sources: [AtomCardData]
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
    // Rich inline cards
    case atomCard(AtomCardData)
    case atomList(AtomListData)
    case graphView(GraphViewData)
    case automationPreview(AutomationPreviewData)
    case workflowPlan(WorkflowPlanData)
    case timelineView(TimelineViewData)
    case synthesisCard(SynthesisCardData)

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case kind, name, summary, isError, fromContext, toContext, lookups, sections, buttons
        case atomCardData, atomListData, graphViewData, automationPreviewData
        case workflowPlanData, timelineViewData, synthesisCardData
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
        case .atomCard(let data):
            try container.encode("atomCard", forKey: .kind)
            try container.encode(data, forKey: .atomCardData)
        case .atomList(let data):
            try container.encode("atomList", forKey: .kind)
            try container.encode(data, forKey: .atomListData)
        case .graphView(let data):
            try container.encode("graphView", forKey: .kind)
            try container.encode(data, forKey: .graphViewData)
        case .automationPreview(let data):
            try container.encode("automationPreview", forKey: .kind)
            try container.encode(data, forKey: .automationPreviewData)
        case .workflowPlan(let data):
            try container.encode("workflowPlan", forKey: .kind)
            try container.encode(data, forKey: .workflowPlanData)
        case .timelineView(let data):
            try container.encode("timelineView", forKey: .kind)
            try container.encode(data, forKey: .timelineViewData)
        case .synthesisCard(let data):
            try container.encode("synthesisCard", forKey: .kind)
            try container.encode(data, forKey: .synthesisCardData)
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
        case "atomCard":
            let data = try container.decode(AtomCardData.self, forKey: .atomCardData)
            self = .atomCard(data)
        case "atomList":
            let data = try container.decode(AtomListData.self, forKey: .atomListData)
            self = .atomList(data)
        case "graphView":
            let data = try container.decode(GraphViewData.self, forKey: .graphViewData)
            self = .graphView(data)
        case "automationPreview":
            let data = try container.decode(AutomationPreviewData.self, forKey: .automationPreviewData)
            self = .automationPreview(data)
        case "workflowPlan":
            let data = try container.decode(WorkflowPlanData.self, forKey: .workflowPlanData)
            self = .workflowPlan(data)
        case "timelineView":
            let data = try container.decode(TimelineViewData.self, forKey: .timelineViewData)
            self = .timelineView(data)
        case "synthesisCard":
            let data = try container.decode(SynthesisCardData.self, forKey: .synthesisCardData)
            self = .synthesisCard(data)
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

    var stableID: String {
        [uuid ?? "no-uuid", type, title].joined(separator: "::")
    }
}

// MARK: - Response Meta

struct CosmoToolRecapItem: Codable, Sendable, Identifiable, Hashable {
    enum Status: String, Codable, Sendable {
        case active
        case done
    }

    let id: UUID
    let icon: String
    let label: String
    let detail: String?
    let status: Status

    init(
        id: UUID = UUID(),
        icon: String,
        label: String,
        detail: String? = nil,
        status: Status
    ) {
        self.id = id
        self.icon = icon
        self.label = label
        self.detail = detail
        self.status = status
    }

    init(_ item: ToolActivityItem) {
        self.init(
            id: item.id,
            icon: item.icon,
            label: item.label,
            detail: item.detail,
            status: item.status == .done ? .done : .active
        )
    }
}

struct CosmoToolRecapGroup: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let category: String
    let items: [CosmoToolRecapItem]
    let isComplete: Bool

    init(
        id: UUID = UUID(),
        category: String,
        items: [CosmoToolRecapItem],
        isComplete: Bool
    ) {
        self.id = id
        self.category = category
        self.items = items
        self.isComplete = isComplete
    }

    init(_ group: ToolActivityGroup) {
        self.init(
            id: group.id,
            category: group.category,
            items: group.items.map(CosmoToolRecapItem.init),
            isComplete: group.isComplete
        )
    }
}

struct CosmoResponseMeta: Codable, Sendable {
    let elapsedSeconds: Int?
    let toolRecapGroups: [CosmoToolRecapGroup]
    let contextTraceSections: [ContextTraceSection]
    let modelLabel: String?

    init(
        elapsedSeconds: Int? = nil,
        toolRecapGroups: [CosmoToolRecapGroup] = [],
        contextTraceSections: [ContextTraceSection] = [],
        modelLabel: String? = nil
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.toolRecapGroups = toolRecapGroups
        self.contextTraceSections = contextTraceSections
        self.modelLabel = modelLabel
    }

    init(
        elapsedSeconds: Int? = nil,
        toolGroups: [ToolActivityGroup]?,
        contextTraceSections: [ContextTraceSection] = [],
        modelLabel: String? = nil
    ) {
        self.init(
            elapsedSeconds: elapsedSeconds,
            toolRecapGroups: (toolGroups ?? []).map(CosmoToolRecapGroup.init),
            contextTraceSections: contextTraceSections,
            modelLabel: modelLabel
        )
    }

    var hasVisibleContent: Bool {
        elapsedSeconds != nil || modelLabel != nil || !toolRecapGroups.isEmpty || !contextTraceSections.isEmpty
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

    /// Expands `@Title` mentions inline in the message text with the atom's full context.
    /// Each mention is expanded with XML-style tags so the AI sees context at the mention's position.
    /// Any atoms whose `@Title` was not found inline are appended as a trailing context block.
    static func expandMentionsInline(text: String, atoms: [Atom], bodyLimit: Int? = nil) -> String {
        var result = text
        var usedUUIDs: Set<String> = []

        for atom in atoms {
            let title = atom.title ?? "Untitled"
            let pattern = "@\(title)"

            if let range = result.range(of: pattern) {
                let typeLabel = atom.type.rawValue.lowercased()
                let body = contextBody(for: atom, limit: bodyLimit)

                var contextBlock = "@\(title)\n<referenced_\(typeLabel) title=\"\(title)\" uuid=\"\(atom.uuid)\">\n\(body)"

                let imageBlock = referencedImagesBlock(for: atom)
                if !imageBlock.isEmpty {
                    contextBlock += "\n\(imageBlock)"
                }

                if atom.isSwipeFileAtom, let analysis = atom.swipeAnalysis {
                    let summary = swipeAnalysisSummary(analysis)
                    if !summary.isEmpty {
                        contextBlock += "\nSwipe Analysis: \(summary)"
                    }
                }
                contextBlock += "\n</referenced_\(typeLabel)>"

                result = result.replacingCharacters(in: range, with: contextBlock)
                usedUUIDs.insert(atom.uuid)
            }
        }

        // Append any atoms whose @Title was not found inline
        let unusedAtoms = atoms.filter { !usedUUIDs.contains($0.uuid) }
        if !unusedAtoms.isEmpty {
            result += "\n\n" + buildMentionBlock(atoms: unusedAtoms, bodyLimit: bodyLimit)
        }

        return result
    }

    /// Builds a full `## Referenced Context` block from mentioned atoms,
    /// including UUIDs, extended body text, and swipe analysis summaries.
    static func buildMentionBlock(atoms: [Atom], bodyLimit: Int? = nil) -> String {
        var mentionBlock = "## Referenced Context\n"
        for atom in atoms {
            let typeLabel = atom.type.rawValue.uppercased()
            let title = atom.title ?? "Untitled"
            let body = contextBody(for: atom, limit: bodyLimit)
            mentionBlock += "[\(typeLabel): \"\(title)\"] (UUID: \(atom.uuid))\n\(body)\n"

            let imageBlock = referencedImagesBlock(for: atom)
            if !imageBlock.isEmpty {
                mentionBlock += "\(imageBlock)\n"
            }

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

    // MARK: - Writing Engine Expansion

    /// Expands @-mentioned atoms for the writing engine with richer context.
    /// Connections include their full structured section data (Goal, Problems, Examples, etc.)
    /// so the writer can map sections to blueprint physics.
    static func expandMentionsForWritingEngine(text: String, atoms: [Atom], bodyLimit: Int? = nil) -> String {
        var result = text
        var usedUUIDs: Set<String> = []

        for atom in atoms {
            let title = atom.title ?? "Untitled"
            let pattern = "@\(title)"
            let typeLabel = atom.type.rawValue.lowercased()

            var contextBlock = "@\(title)\n<referenced_\(typeLabel) title=\"\(title)\" uuid=\"\(atom.uuid)\">"

            // Body content
            let body = contextBody(for: atom, limit: bodyLimit)
            if !body.isEmpty {
                contextBlock += "\n\(body)"
            }

            let imageBlock = referencedImagesBlock(for: atom)
            if !imageBlock.isEmpty {
                contextBlock += "\n\(imageBlock)"
            }

            // Connection-specific: include all structured sections
            if atom.type == .connection,
               let structured = atom.structured,
               let data = ConnectionStructuredData.fromJSON(structured) {
                let filledSections = data.sections.filter { !$0.items.isEmpty }
                if !filledSections.isEmpty {
                    contextBlock += "\n\nStructured Sections:"
                    for section in filledSections {
                        contextBlock += "\n  \(section.type.displayName):"
                        for item in section.items {
                            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !content.isEmpty {
                                contextBlock += "\n    - \(content)"
                            }
                        }
                    }
                }
            }

            // Swipe analysis (same as chat expansion)
            if atom.isSwipeFileAtom, let analysis = atom.swipeAnalysis {
                let summary = swipeAnalysisSummary(analysis)
                if !summary.isEmpty {
                    contextBlock += "\nSwipe Analysis: \(summary)"
                }
            }

            contextBlock += "\n</referenced_\(typeLabel)>"

            if let range = result.range(of: pattern) {
                result = result.replacingCharacters(in: range, with: contextBlock)
                usedUUIDs.insert(atom.uuid)
            }
        }

        // Append atoms not found inline as a trailing block
        let unusedAtoms = atoms.filter { !usedUUIDs.contains($0.uuid) }
        if !unusedAtoms.isEmpty {
            result += "\n\n" + buildWritingEngineBlock(atoms: unusedAtoms, bodyLimit: bodyLimit)
        }

        return result
    }

    /// Builds a full referenced context block for the writing engine, with rich connection data.
    private static func buildWritingEngineBlock(atoms: [Atom], bodyLimit: Int? = nil) -> String {
        var block = "## Referenced Context\n"
        for atom in atoms {
            let typeLabel = atom.type.rawValue.uppercased()
            let title = atom.title ?? "Untitled"
            let body = contextBody(for: atom, limit: bodyLimit)
            block += "[\(typeLabel): \"\(title)\"] (UUID: \(atom.uuid))\n"
            if !body.isEmpty { block += "\(body)\n" }

            let imageBlock = referencedImagesBlock(for: atom)
            if !imageBlock.isEmpty {
                block += "\(imageBlock)\n"
            }

            // Connection structured sections
            if atom.type == .connection,
               let structured = atom.structured,
               let data = ConnectionStructuredData.fromJSON(structured) {
                let filledSections = data.sections.filter { !$0.items.isEmpty }
                if !filledSections.isEmpty {
                    block += "Structured Sections:\n"
                    for section in filledSections {
                        block += "  \(section.type.displayName):\n"
                        for item in section.items {
                            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !content.isEmpty {
                                block += "    - \(content)\n"
                            }
                        }
                    }
                }
            }

            // Swipe analysis
            if atom.isSwipeFileAtom, let analysis = atom.swipeAnalysis {
                let summary = swipeAnalysisSummary(analysis)
                if !summary.isEmpty {
                    block += "Swipe Analysis: \(summary)\n"
                }
            }
            block += "\n"
        }
        return block
    }

    private static func contextBody(for atom: Atom, limit: Int?) -> String {
        let body = DocumentElementContextFormatter.contextBody(for: atom)
        guard let limit, body.count > limit else {
            return body
        }
        return String(body.prefix(limit))
    }

    private static func referencedImagesBlock(for atom: Atom) -> String {
        let references = referencedImageReferences(for: atom)
        guard !references.isEmpty else { return "" }

        var lines = ["Referenced Images:"]
        for reference in references {
            let details = reference.details.map { " (\($0))" } ?? ""
            lines.append("- \(reference.label): \(reference.value)\(details)")
        }
        return lines.joined(separator: "\n")
    }

    private static func referencedImageReferences(for atom: Atom) -> [MentionContextImageReference] {
        var references: [MentionContextImageReference] = []
        var seenValues: Set<String> = []

        if let imageMetadata = atom.imageMetadata {
            appendImageReference(
                label: "Image path",
                value: imageMetadata.imagePath,
                details: imageMetadataDetails(imageMetadata),
                references: &references,
                seenValues: &seenValues
            )
        }

        if let body = atom.body {
            collectImageReferences(
                fromText: body,
                label: "Body image",
                references: &references,
                seenValues: &seenValues
            )
        }

        collectImageReferences(
            fromJSONText: atom.metadata,
            label: "Metadata",
            references: &references,
            seenValues: &seenValues
        )
        collectImageReferences(
            fromJSONText: atom.structured,
            label: "Structured content",
            references: &references,
            seenValues: &seenValues
        )
        collectImageReferences(
            fromJSONText: atom.links,
            label: "Linked content",
            references: &references,
            seenValues: &seenValues
        )

        return references
    }

    private static func collectImageReferences(
        fromJSONText text: String?,
        label: String,
        references: inout [MentionContextImageReference],
        seenValues: inout Set<String>
    ) {
        guard let text, let data = text.data(using: .utf8) else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) {
            collectImageReferences(
                fromJSON: json,
                label: label,
                references: &references,
                seenValues: &seenValues
            )
        } else {
            collectImageReferences(
                fromText: text,
                label: label,
                references: &references,
                seenValues: &seenValues
            )
        }
    }

    private static func collectImageReferences(
        fromJSON value: Any,
        label: String,
        references: inout [MentionContextImageReference],
        seenValues: inout Set<String>
    ) {
        switch value {
        case let dict as [String: Any]:
            for (key, nestedValue) in dict {
                let nestedLabel = "\(label).\(key)"
                if shouldSkipImageReferenceKey(key) { continue }
                collectImageReferences(
                    fromJSON: nestedValue,
                    label: nestedLabel,
                    references: &references,
                    seenValues: &seenValues
                )
            }

        case let array as [Any]:
            for (index, nestedValue) in array.enumerated() {
                collectImageReferences(
                    fromJSON: nestedValue,
                    label: "\(label)[\(index)]",
                    references: &references,
                    seenValues: &seenValues
                )
            }

        case let string as String:
            collectImageReferences(
                fromText: string,
                label: label,
                references: &references,
                seenValues: &seenValues
            )

        default:
            break
        }
    }

    private static func collectImageReferences(
        fromText text: String,
        label: String,
        references: inout [MentionContextImageReference],
        seenValues: inout Set<String>
    ) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            appendImageReferenceIfNeeded(
                label: label,
                value: line,
                references: &references,
                seenValues: &seenValues
            )
        }

        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        for token in tokens {
            appendImageReferenceIfNeeded(
                label: label,
                value: token,
                references: &references,
                seenValues: &seenValues
            )
        }
    }

    private static func appendImageReferenceIfNeeded(
        label: String,
        value: String,
        references: inout [MentionContextImageReference],
        seenValues: inout Set<String>
    ) {
        guard let normalized = normalizedImageReference(value) else { return }
        appendImageReference(
            label: label,
            value: normalized,
            details: nil,
            references: &references,
            seenValues: &seenValues
        )
    }

    private static func appendImageReference(
        label: String,
        value: String,
        details: String?,
        references: inout [MentionContextImageReference],
        seenValues: inout Set<String>
    ) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, seenValues.insert(normalized).inserted else { return }
        references.append(MentionContextImageReference(label: label, value: normalized, details: details))
    }

    private static func normalizedImageReference(_ value: String) -> String? {
        let trimCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`“”‘’()[]{}<>.,;"))
        let candidate = value.trimmingCharacters(in: trimCharacters)
        guard !candidate.isEmpty else { return nil }

        let lowercased = candidate.lowercased()
        let imageExtensions = [".png", ".jpg", ".jpeg", ".heic", ".heif", ".gif", ".tif", ".tiff", ".webp"]
        guard imageExtensions.contains(where: { imageExtension in
            lowercased.hasSuffix(imageExtension)
                || lowercased.contains("\(imageExtension)?")
                || lowercased.contains("\(imageExtension)#")
        }) else {
            return nil
        }

        return candidate
    }

    private static func shouldSkipImageReferenceKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return lowercased.contains("filename") || lowercased == "alt" || lowercased == "caption"
    }

    private static func imageMetadataDetails(_ metadata: ImageMetadata) -> String? {
        var details: [String] = []

        if let originalFilename = metadata.originalFilename, !originalFilename.isEmpty {
            details.append("filename: \(originalFilename)")
        }
        if let width = metadata.width, let height = metadata.height {
            details.append("\(dimensionString(width))x\(dimensionString(height))")
        }
        if let fileSize = metadata.fileSize {
            details.append("file size: \(fileSize) bytes")
        }

        return details.isEmpty ? nil : details.joined(separator: ", ")
    }

    private static func dimensionString(_ value: CGFloat) -> String {
        let double = Double(value)
        if double.rounded() == double {
            return String(Int(double))
        }
        return String(format: "%.1f", double)
    }
}

private struct MentionContextImageReference {
    let label: String
    let value: String
    let details: String?
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

    /// Persisted presentation metadata for completed assistant responses.
    var responseMeta: CosmoResponseMeta?

    var shouldRenderInCosmoWindowTimeline: Bool {
        if case .assistant = type {
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || responseMeta?.hasVisibleContent == true
                || !isStreaming
        }
        return true
    }

    init(
        id: UUID = UUID(),
        type: CosmoWindowMessageType,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        toolActivityGroups: [ToolActivityGroup]? = nil,
        mentionedAtomInfo: [MentionedAtomInfo]? = nil,
        responseMeta: CosmoResponseMeta? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.toolActivityGroups = toolActivityGroups
        self.mentionedAtomInfo = mentionedAtomInfo
        self.responseMeta = responseMeta
    }

    // MARK: - Codable (exclude toolActivityGroups)

    enum CodingKeys: String, CodingKey {
        case id, type, content, timestamp, isStreaming, mentionedAtomInfo, responseMeta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(CosmoWindowMessageType.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isStreaming = try container.decode(Bool.self, forKey: .isStreaming)
        mentionedAtomInfo = try container.decodeIfPresent([MentionedAtomInfo].self, forKey: .mentionedAtomInfo)
        responseMeta = try container.decodeIfPresent(CosmoResponseMeta.self, forKey: .responseMeta)
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
        try container.encodeIfPresent(responseMeta, forKey: .responseMeta)
    }

    // MARK: - Factory Methods

    static func user(_ content: String, mentionedAtoms: [MentionedAtomInfo]? = nil) -> CosmoWindowMessage {
        CosmoWindowMessage(type: .user, content: content, mentionedAtomInfo: mentionedAtoms)
    }

    static func assistant(
        _ content: String,
        isStreaming: Bool = false,
        responseMeta: CosmoResponseMeta? = nil
    ) -> CosmoWindowMessage {
        CosmoWindowMessage(
            type: .assistant,
            content: content,
            isStreaming: isStreaming,
            responseMeta: responseMeta
        )
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
        let sections = contextTraceSections(from: trace)

        return CosmoWindowMessage(
            type: .contextTrace(lookups: trace.lookupCount, sections: sections),
            content: "Context Used"
        )
    }

    static func contextTraceSections(from trace: AgentContextTrace) -> [ContextTraceSection] {
        var sections: [ContextTraceSection] = []

        if let client = trace.clientProfileName {
            sections.append(ContextTraceSection(icon: "person.fill", label: "Client", detail: client))
        }

        let swipes = trace.swipesReferenced.filter { !$0.isEmpty && !$0.hasPrefix("0 ") }
        if !swipes.isEmpty {
            sections.append(
                ContextTraceSection(
                    icon: "doc.text",
                    label: "Swipes",
                    detail: swipes.prefix(4).joined(separator: ", ")
                )
            )
        }

        let knowledge = trace.knowledgeToolsUsed
        if !knowledge.isEmpty {
            let names = knowledge.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
            sections.append(
                ContextTraceSection(
                    icon: "brain",
                    label: "Knowledge",
                    detail: names.joined(separator: ", ")
                )
            )
        }

        let atoms = trace.atomsReferenced.filter { !$0.isEmpty }
        if !atoms.isEmpty {
            sections.append(
                ContextTraceSection(
                    icon: "atom",
                    label: "Atoms Referenced",
                    detail: "\(atoms.count) sources"
                )
            )
        }

        return sections
    }

    static func contextTraceSections(from contextPack: AgentContextPack) -> [ContextTraceSection] {
        var sections: [ContextTraceSection] = []

        if !contextPack.request.pinnedSourceIDs.isEmpty {
            sections.append(
                ContextTraceSection(
                    icon: "magnifyingglass",
                    label: "Context Search",
                    detail: "\(contextPack.request.pinnedSourceIDs.count) pinned source(s)"
                )
            )
        }

        if !contextPack.retrievedResults.isEmpty {
            let details = contextPack.retrievedResults
                .prefix(4)
                .map { result in
                    result.chunk.anchor.map { "\(result.source.title):\($0)" } ?? result.source.title
                }
                .joined(separator: ", ")
            sections.append(ContextTraceSection(icon: "doc.text.magnifyingglass", label: "Evidence", detail: details))
        }

        let memoryCount = contextPack.coreMemory.count + contextPack.workingMemory.count + contextPack.recallMemory.count
        if memoryCount > 0 {
            sections.append(ContextTraceSection(icon: "brain", label: "Memory", detail: "\(memoryCount) relevant item(s)"))
        }

        return sections
    }
}

// MARK: - Context Trace Section

/// A single row in a context trace card (icon + label + detail)
struct ContextTraceSection: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let icon: String
    let label: String
    let detail: String

    init(id: UUID = UUID(), icon: String, label: String, detail: String) {
        self.id = id
        self.icon = icon
        self.label = label
        self.detail = detail
    }
}
