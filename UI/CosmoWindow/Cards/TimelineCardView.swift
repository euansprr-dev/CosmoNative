// CosmoOS/UI/CosmoWindow/Cards/TimelineCardView.swift
// Activity timeline card for inline chat results

import SwiftUI

struct TimelineCardView: View {
    let data: TimelineViewData

    private var visibleEntries: [TimelineEntryData] {
        Array(data.entries.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            timelineHeader
            timelineList
        }
        .padding(16)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: DS.text.opacity(0.06), radius: 8, y: 4)
    }

    // MARK: - Subviews

    private var timelineHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Activity timeline")
            Text("Activity Timeline")
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var timelineList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleEntries.enumerated()), id: \.element.uuid) { index, entry in
                timelineRow(entry: entry, isLast: index == visibleEntries.count - 1)
            }
        }
    }

    private func timelineRow(entry: TimelineEntryData, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            timelineDot(type: entry.type, isLast: isLast)
            entryContent(entry)
            Spacer(minLength: 0)
            timestampLabel(entry.timestamp)
        }
        .padding(.vertical, 6)
    }

    private func timelineDot(type: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(dotColor(for: type))
                .frame(width: 8, height: 8)
            if !isLast {
                Rectangle()
                    .fill(DS.border)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 8)
    }

    private func entryContent(_ entry: TimelineEntryData) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entryIcon(for: entry.type))
                .font(.caption2)
                .foregroundStyle(dotColor(for: entry.type))
                .accessibilityLabel("\(entry.type) entry")
            Text(entry.title)
                .font(.caption)
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
    }

    private func timestampLabel(_ timestamp: String) -> some View {
        Text(timestamp)
            .font(.system(size: 10))
            .foregroundStyle(DS.textMuted)
    }

    // MARK: - Helpers

    private func dotColor(for type: String) -> Color {
        switch type.lowercased() {
        case "idea": return DS.entityIdea
        case "research": return DS.entityResearch
        case "content": return DS.entityContent
        case "note": return DS.entityNote
        case "connection": return DS.entityConnection
        case "swipe": return DS.entitySwipe
        case "task": return DS.entityTask
        default: return DS.textMuted
        }
    }

    private func entryIcon(for type: String) -> String {
        switch type.lowercased() {
        case "idea": return "lightbulb.fill"
        case "research": return "magnifyingglass"
        case "content": return "doc.text.fill"
        case "note": return "note.text"
        case "connection": return "person.fill"
        case "swipe": return "rectangle.stack.fill"
        case "task": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
}
