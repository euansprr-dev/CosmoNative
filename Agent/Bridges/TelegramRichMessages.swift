// CosmoOS/Agent/Bridges/TelegramRichMessages.swift
// Rich Telegram message formatting for pipeline visibility and interactive actions

import Foundation

@MainActor
class TelegramRichMessages {
    static let shared = TelegramRichMessages()

    private init() {}

    // MARK: - Pipeline Status

    /// Format the content pipeline status as a rich Telegram message
    func formatPipelineStatus(pipeline: [String: [[String: Any]]]) -> String {
        let phases = ["brainstorm", "draft", "polish", "archived"]
        let phaseEmojis = [
            "brainstorm": "💡", "draft": "✏️", "polish": "✨",
            "ideation": "🌱", "archived": "📦"
        ]

        var lines: [String] = []
        lines.append("Content Pipeline Status")
        lines.append(String(repeating: "━", count: 24))

        // Phase bar
        var barParts: [String] = []
        for phase in phases {
            let count = pipeline[phase]?.count ?? 0
            let emoji = phaseEmojis[phase] ?? "📄"
            barParts.append("\(emoji) \(phase.capitalized) [\(count)]")
        }
        lines.append(barParts.joined(separator: " → "))
        lines.append("")

        // Recent items (max 5 across all phases)
        var recentItems: [(title: String, phase: String)] = []
        for (phase, items) in pipeline {
            for item in items.prefix(3) {
                let title = item["title"] as? String ?? "Untitled"
                recentItems.append((title: title, phase: phase))
            }
        }

        if !recentItems.isEmpty {
            lines.append("Recent:")
            for item in recentItems.prefix(5) {
                let emoji = phaseEmojis[item.phase] ?? "📄"
                lines.append("  \(emoji) \"\(item.title)\" — \(item.phase.capitalized)")
            }
        } else {
            lines.append("Pipeline is empty. Start by activating an idea!")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Workflow Plan

    /// Format a workflow plan as a numbered Telegram message
    func formatWorkflowPlan(summary: String, steps: [(action: String, description: String, confirmRequired: Bool)]) -> String {
        var lines: [String] = []
        lines.append("Plan: \(summary)")
        lines.append(String(repeating: "━", count: 24))
        lines.append("")

        for (index, step) in steps.enumerated() {
            let number = index + 1
            let confirmTag = step.confirmRequired ? " [confirm]" : " [auto]"
            lines.append("\(number). \(step.description)\(confirmTag)")
        }

        lines.append("")
        lines.append("Ready to execute?")

        return lines.joined(separator: "\n")
    }

    /// Format workflow progress update
    func formatWorkflowProgress(planSummary: String, currentStep: Int, totalSteps: Int, stepDescription: String, status: String) -> String {
        let progressBar = buildProgressBar(current: currentStep, total: totalSteps)

        var lines: [String] = []
        lines.append(progressBar)
        lines.append("")
        lines.append("Step \(currentStep)/\(totalSteps): \(stepDescription)")
        lines.append("Status: \(status)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Morning Brief

    /// Format the strategic morning brief
    func formatMorningBrief(
        energyNote: String?,
        pipelineStatus: String,
        streak: Int,
        followerChange: String?,
        todayPlan: String,
        insight: String?,
        questProgress: String
    ) -> String {
        var lines: [String] = []
        lines.append("Good morning! Here's your creative brief:")
        lines.append("")

        if let energy = energyNote {
            lines.append("ENERGY: \(energy)")
            lines.append("")
        }

        lines.append("CONTENT PULSE:")
        lines.append("  \(pipelineStatus)")
        if streak > 0 {
            lines.append("  Streak: \(streak) day\(streak == 1 ? "" : "s") active")
        }
        if let followers = followerChange {
            lines.append("  \(followers)")
        }

        lines.append("")
        lines.append("TODAY'S PLAY:")
        lines.append("  \(todayPlan)")

        if let insight = insight {
            lines.append("")
            lines.append("INSIGHT: \(insight)")
        }

        if !questProgress.isEmpty {
            lines.append("")
            lines.append("QUESTS: \(questProgress)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Weekly Review

    /// Format the weekly strategy review
    func formatWeeklyReview(
        publishedCount: Int,
        bestPiece: (title: String, hookType: String, framework: String, metric: String)?,
        weakestPiece: (title: String, hookType: String, reason: String)?,
        swipesStudied: Int,
        ideasCaptured: Int,
        pattern: String?,
        recommendations: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("WEEKLY CREATIVE REVIEW")
        lines.append(String(repeating: "━", count: 24))
        lines.append("")

        lines.append("PUBLISHED: \(publishedCount) piece\(publishedCount == 1 ? "" : "s")")

        if let best = bestPiece {
            lines.append("")
            lines.append("PERFORMANCE:")
            lines.append("  Best: \"\(best.title)\"")
            lines.append("    Hook: \(best.hookType) | Framework: \(best.framework)")
            lines.append("    \(best.metric)")
        }

        if let worst = weakestPiece {
            lines.append("  Weakest: \"\(worst.title)\"")
            lines.append("    Hook: \(worst.hookType)")
            lines.append("    \(worst.reason)")
        }

        lines.append("")
        lines.append("SWIPES STUDIED: \(swipesStudied) new")
        lines.append("IDEAS CAPTURED: \(ideasCaptured) new")

        if let pattern = pattern {
            lines.append("")
            lines.append("PATTERN: \(pattern)")
        }

        if !recommendations.isEmpty {
            lines.append("")
            lines.append("NEXT WEEK:")
            for rec in recommendations {
                lines.append("  - \(rec)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Draft Preview

    /// Format a draft preview for Telegram
    func formatDraftPreview(
        title: String,
        body: String,
        wordCount: Int,
        readabilityGrade: Int,
        framework: String?,
        hookType: String?
    ) -> String {
        let preview = String(body.prefix(500))
        let truncated = body.count > 500

        var lines: [String] = []
        lines.append("DRAFT: \"\(title)\"")
        lines.append(String(repeating: "─", count: 20))
        lines.append("")
        lines.append(preview)
        if truncated {
            lines.append("... [\(wordCount) words total]")
        }
        lines.append("")
        lines.append(String(repeating: "─", count: 20))

        var meta: [String] = []
        meta.append("\(wordCount) words")
        meta.append("Grade \(readabilityGrade) readability")
        if let framework = framework { meta.append(framework) }
        if let hook = hookType { meta.append(hook) }

        lines.append(meta.joined(separator: " | "))

        return lines.joined(separator: "\n")
    }

    // MARK: - Inline Keyboards

    /// Build an inline keyboard for workflow approval
    func workflowApprovalKeyboard(planId: String) -> [[[String: String]]] {
        return [[
            ["text": "Approve", "callback_data": "workflow_approve:\(planId)"],
            ["text": "Edit Plan", "callback_data": "workflow_edit:\(planId)"],
            ["text": "Cancel", "callback_data": "workflow_cancel:\(planId)"]
        ]]
    }

    /// Build an inline keyboard for draft review
    func draftReviewKeyboard(contentUUID: String) -> [[[String: String]]] {
        return [[
            ["text": "Approve", "callback_data": "draft_approve:\(contentUUID)"],
            ["text": "Refine", "callback_data": "draft_refine:\(contentUUID)"],
            ["text": "Redo", "callback_data": "draft_redo:\(contentUUID)"]
        ]]
    }

    /// Build an inline keyboard for content suggestion
    func contentSuggestionKeyboard(ideaUUID: String?) -> [[[String: String]]] {
        var buttons: [[String: String]] = [
            ["text": "Start Now", "callback_data": "start_content:\(ideaUUID ?? "new")"],
            ["text": "Later", "callback_data": "defer_content"]
        ]
        if let uuid = ideaUUID {
            buttons.append(["text": "Show Draft", "callback_data": "show_draft:\(uuid)"])
        }
        return [buttons]
    }

    /// Build an inline keyboard for morning brief actions
    func morningBriefKeyboard() -> [[[String: String]]] {
        return [[
            ["text": "Start Day", "callback_data": "morning_start"],
            ["text": "Show Pipeline", "callback_data": "morning_pipeline"],
            ["text": "Change Plan", "callback_data": "morning_change"]
        ]]
    }

    // MARK: - Context Trace Card

    /// Format an AgentContextTrace as a compact Telegram context card.
    /// Returns nil if no tools were called (no card needed).
    func formatContextTrace(_ trace: AgentContextTrace) -> String? {
        guard trace.hasContent else { return nil }

        var sections: [String] = []

        // Client profile
        if let client = trace.clientProfileName {
            sections.append("  \u{1F464} Client: \(client)")
        }

        // Swipes referenced — merge direct tool calls and writing engine internals
        let directSwipes = trace.swipesReferenced
        let engineSwipes = trace.writingEngineSwipes
        let allSwipes = Array(Set(directSwipes + engineSwipes)).filter { !$0.isEmpty && !$0.hasPrefix("0 ") }
        if !allSwipes.isEmpty {
            let swipeList = allSwipes.prefix(4).joined(separator: ", ")
            sections.append("  \u{1F4C4} Swipes: \(swipeList)")
        }

        // Beat patterns
        let beats = trace.beatPatternsUsed.filter { !$0.isEmpty }
        if !beats.isEmpty {
            let beatList = beats.prefix(3).joined(separator: ", ")
            sections.append("  \u{1F3B5} Beat Patterns: \(beatList)")
        }

        // Writing engine tools
        let writingTools = trace.writingToolsUsed
        if !writingTools.isEmpty {
            let toolNames = writingTools.map { name in
                name.replacingOccurrences(of: "_", with: " ").capitalized
            }
            sections.append("  \u{270F}\u{FE0F} Writing Engine: \(toolNames.joined(separator: ", "))")
        }

        // Scorecard
        let scorecardCalls = trace.toolCalls.filter { $0.name.contains("score") }
        for call in scorecardCalls {
            if let summary = call.resultSummary {
                sections.append("  \u{1F4CA} Scorecard: \(summary)")
            }
        }

        // Learned skills applied
        if let summary = trace.skillsSummary {
            sections.append("  \u{1F4DA} Skills applied: \(summary)")
        }

        // Other tools not covered above
        let coveredNames: Set<String> = Set(
            trace.toolCalls.filter { call in
                call.name.contains("swipe") || call.name.contains("search") ||
                call.name.contains("beat") || call.name.contains("client") ||
                call.name.hasPrefix("generate_") || call.name.contains("draft") ||
                call.name.contains("score") || call.name.contains("write")
            }.map(\.name)
        )
        let otherTools = trace.toolCalls.filter { !coveredNames.contains($0.name) }
        if !otherTools.isEmpty {
            let otherNames = otherTools.prefix(3).map { $0.name.replacingOccurrences(of: "_", with: " ") }
            sections.append("  \u{1F527} Also used: \(otherNames.joined(separator: ", "))")
        }

        guard !sections.isEmpty else { return nil }

        var lines: [String] = []
        lines.append("\u{1F441} Context Used (\(trace.lookupCount) lookup\(trace.lookupCount == 1 ? "" : "s"))")
        lines.append(contentsOf: sections)

        // Cap at ~800 chars
        let result = lines.joined(separator: "\n")
        if result.count > 800 {
            return String(result.prefix(797)) + "..."
        }
        return result
    }

    // MARK: - Progress Bar

    /// Build a text-based progress bar
    func buildProgressBar(current: Int, total: Int) -> String {
        let filled = current
        let empty = total - current
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        return "[\(bar)] \(current)/\(total)"
    }

    // MARK: - Formatting Helpers

    /// Escape special characters for Telegram MarkdownV2
    func escapeMarkdownV2(_ text: String) -> String {
        let specialChars: [Character] = ["_", "*", "[", "]", "(", ")", "~", "`", ">", "#", "+", "-", "=", "|", "{", "}", ".", "!"]
        var escaped = ""
        for char in text {
            if specialChars.contains(char) {
                escaped.append("\\")
            }
            escaped.append(char)
        }
        return escaped
    }

    /// Format a number with K/M suffix
    func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    /// Format a time interval as human-readable
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

}
