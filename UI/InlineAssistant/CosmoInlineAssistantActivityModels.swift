// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantActivityModels.swift
// The assistant's working thread made durable: each tool call becomes a step the
// pane can narrate live and replay later as a per-answer receipt.
// June 2026

import Foundation

/// One tool call in a run, narrated with the same verb-first grammar as the
/// status line. Persisted on the answer it produced so every message keeps an
/// auditable record of the work behind it.
struct CosmoInlineAssistantActivityStep: Identifiable, Codable, Equatable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case running
        case done
    }

    var id = UUID()
    var toolName: String
    /// Verb-first narration ("Pulling swipes on curiosity hooks").
    var label: String
    /// The key argument the narration was built from (search query, client name).
    var subject: String? = nil
    var state: State = .running
    var startedAt = Date()
    var finishedAt: Date? = nil
}

/// Buckets tool names into visual categories so the timeline can speak in a
/// small, consistent icon vocabulary instead of one glyph per tool.
enum CosmoInlineAssistantToolTaxonomy {
    enum Category: String, Codable, Equatable, Sendable {
        case search
        case read
        case profile
        case web
        case edit
        case write
        case canvas
        case memory
        case other
    }

    static func category(forToolName toolName: String) -> Category {
        switch toolName {
        case "search_swipes", "find_similar_swipes", "filter_swipes_by_taxonomy",
             "list_all_swipes", "search_ideas", "search_by_client", "recall":
            return .search
        case "retrieve_context", "search_memory", "remember_context",
             "save_analysis", "get_saved_analyses":
            return .memory
        case "read_draft", "get_content", "get_idea", "get_swipe_analysis",
             "inspect_pinned_sources", "get_lessons":
            return .read
        case "get_client_profile", "lookup_client_facts", "get_creator_profile",
             "get_audience_insights":
            return .profile
        case "web_search", "search_web":
            return .web
        case "propose_workspace_edit", "revise_draft":
            return .edit
        case "answer_in_assistant_pane", "generate_draft", "generate_outline",
             "generate_hooks", "create_inline_skill":
            return .write
        case "inspect_current_thinkspace", "propose_canvas_plan":
            return .canvas
        default:
            if toolName.hasPrefix("search_") { return .search }
            if toolName.hasPrefix("get_") || toolName.hasPrefix("read_") { return .read }
            if toolName.hasPrefix("create_") || toolName.hasPrefix("update_") { return .write }
            return .other
        }
    }

    static func icon(for category: Category) -> String {
        switch category {
        case .search: return "magnifyingglass"
        case .read: return "doc.text"
        case .profile: return "person.crop.rectangle"
        case .web: return "globe"
        case .edit: return "pencil.line"
        case .write: return "pencil.and.outline"
        case .canvas: return "rectangle.3.group"
        case .memory: return "brain.head.profile"
        case .other: return "circle.dotted"
        }
    }

    static func icon(forToolName toolName: String) -> String {
        icon(for: category(forToolName: toolName))
    }
}

/// Renders a finished run as a single quiet line — "Worked for 8s · 2 searches ·
/// 4 sources read" — the receipt a collapsed timeline shows above its answer.
enum CosmoInlineAssistantRunReceiptFormatter {
    static func summary(steps: [CosmoInlineAssistantActivityStep], sourceCount: Int = 0) -> String {
        var parts: [String] = []

        if let duration = duration(of: steps) {
            parts.append("Worked for \(durationLabel(duration))")
        }

        let searchCount = steps.filter {
            let category = CosmoInlineAssistantToolTaxonomy.category(forToolName: $0.toolName)
            return category == .search || category == .web || category == .memory
        }.count
        if searchCount > 0 {
            parts.append(searchCount == 1 ? "1 search" : "\(searchCount) searches")
        }

        if sourceCount > 0 {
            parts.append(sourceCount == 1 ? "1 source read" : "\(sourceCount) sources read")
        }

        // A bare duration says nothing about the work — fall back to step count.
        if searchCount == 0, sourceCount == 0, !steps.isEmpty {
            parts.append(steps.count == 1 ? "1 step" : "\(steps.count) steps")
        }

        return parts.joined(separator: " · ")
    }

    static func duration(of steps: [CosmoInlineAssistantActivityStep]) -> TimeInterval? {
        guard let start = steps.map(\.startedAt).min() else { return nil }
        let end = steps.compactMap(\.finishedAt).max() ?? start
        let interval = end.timeIntervalSince(start)
        return interval >= 0 ? interval : nil
    }

    static func durationLabel(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 1 { return "under a second" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }
}
