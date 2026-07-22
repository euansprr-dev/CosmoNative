// Canvas/CommandCenter/TaskCaptureWash.swift
// The ⌥C wash treatment for task-CREATION fields: composes mention spans,
// the habit keyword, and every capture-grammar token
// (TaskInputParser.captureWashTokens) into TextWashSegments — one color
// voice shared by the Today quick-add row and the ⌘K task composer.
// July 2026

import SwiftUI
import AppKit

@MainActor
enum TaskCaptureWash {

    static func segments(for text: String, mentions: [RichMention] = []) -> [TextWashSegment] {
        guard !text.isEmpty else { return [] }
        var segments: [TextWashSegment] = []
        let ns = text as NSString

        // Mentions read as links — each in its entity's tint.
        for mention in mentions {
            let range = ns.range(of: "@\(mention.titleSnapshot)")
            guard range.location != NSNotFound else { continue }
            segments.append(TextWashSegment(
                utf16Range: range.location..<(range.location + range.length),
                ink: NSColor(CosmoMentionColors.color(for: mention.entityType))
            ))
        }

        // Habit keyword ("meditate") in that habit's tint.
        if let match = CommandCenterHabitEngine.shared.keywordTriggerMatch(in: text),
           !segments.contains(where: { $0.utf16Range.overlaps(match.utf16Range) }) {
            segments.append(TextWashSegment(
                utf16Range: match.utf16Range,
                ink: NSColor(match.definition.accent)
            ))
        }

        for token in TaskInputParser.captureWashTokens(text, mentions: mentions) {
            guard !segments.contains(where: { $0.utf16Range.overlaps(token.utf16Range) }) else { continue }
            segments.append(TextWashSegment(
                utf16Range: token.utf16Range,
                ink: NSColor(ink(for: token.kind))
            ))
        }
        return segments
    }

    /// Chip-language tints: each token washes in the color its metadata chip
    /// already speaks, so the inline highlight and the chip row agree.
    private static func ink(for kind: CaptureWashToken.Kind) -> Color {
        switch kind {
        case .schedulingState:
            return DS.entityIdea
        case .timeOfDay(let timeOfDay):
            return timeOfDay == "morning" ? DS.orange : DS.entityIdea
        case .projectTag, .headingTag, .deadline, .recurrence, .date:
            return DS.accent
        case .priority(let priority):
            return priority.color
        case .intent(let intent):
            return CommandCenterIntentEngine.shared.resolvedPresentation(
                intentUUID: CommandCenterIntentEngine.shared.seedID(for: intent),
                legacyIntentRaw: intent.rawValue
            ).accent
        case .duration, .time:
            return DS.info
        }
    }
}
