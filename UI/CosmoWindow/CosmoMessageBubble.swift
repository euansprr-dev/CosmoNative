// CosmoOS/UI/CosmoWindow/CosmoMessageBubble.swift
// Individual message rendering for the global Cosmo chat window
// Native macOS chat aesthetic — iMessage/Telegram Desktop feel
// February 2026

import SwiftUI

// MARK: - Message Bubble

/// Renders a single message in the Cosmo window conversation.
/// Dispatches to the appropriate layout based on `CosmoWindowMessageType`.
struct CosmoMessageBubble: View {
    let message: CosmoWindowMessage

    var body: some View {
        switch message.type {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system:
            systemBubble
        case .toolResult(let name, let summary, let isError):
            toolResultRow(name: name, summary: summary, isError: isError)
        case .contextTrace(let lookups, let sections):
            ContextTraceCard(lookups: lookups, sections: sections)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
        case .contextChange(_, let to):
            contextChangeDivider(to: to)
        case .actionButtons(let buttons):
            actionButtonsBubble(buttons: buttons)
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 4) {
                // Mentioned atoms (if any)
                if let mentions = message.mentionedAtomInfo, !mentions.isEmpty {
                    userMentionChips(mentions)
                }

                Text(message.content)
                    .font(DS.body)
                    .foregroundColor(DS.text)
                    .textSelection(.enabled)
                    .lineSpacing(4)

                Text(formattedTime)
                    .font(DS.timestamp)
                    .foregroundColor(DS.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DS.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // MARK: - User Mention Chips

    @ViewBuilder
    private func userMentionChips(_ mentions: [MentionedAtomInfo]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(mentions, id: \.title) { mention in
                    userMentionChip(mention)
                }
            }
        }
    }

    private func userMentionChip(_ mention: MentionedAtomInfo) -> some View {
        let entityType = EntityType(rawValue: mention.type) ?? .idea
        return HStack(spacing: 3) {
            Circle()
                .fill(CosmoMentionColors.color(for: entityType))
                .frame(width: 5, height: 5)
            Text(mention.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(CosmoMentionColors.color(for: entityType))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(CosmoMentionColors.pillBackground(for: entityType))
        .clipShape(Capsule())
    }

    // MARK: - Assistant Bubble

    private var assistantBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if message.isStreaming {
                    HStack(spacing: 0) {
                        Text(message.content)
                            .font(DS.body)
                            .foregroundColor(DS.text)
                            .textSelection(.enabled)
                            .lineSpacing(4)

                        StreamingIndicator()
                    }
                } else {
                    Text(message.content)
                        .font(DS.body)
                        .foregroundColor(DS.text)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }

                Text(formattedTime)
                    .font(DS.timestamp)
                    .foregroundColor(DS.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.accent)
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // MARK: - Action Buttons Bubble

    private func actionButtonsBubble(buttons: [CosmoActionButton]) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                // Message text (same style as assistant)
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(DS.body)
                        .foregroundColor(DS.text)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }

                // Button pills — rows of max 3
                actionButtonRows(buttons)

                Text(formattedTime)
                    .font(DS.timestamp)
                    .foregroundColor(DS.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.accent)
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func actionButtonRows(_ buttons: [CosmoActionButton]) -> some View {
        let rows = stride(from: 0, to: buttons.count, by: 3).map { start in
            Array(buttons[start..<min(start + 3, buttons.count)])
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, button in
                        actionPillButton(button)
                    }
                }
            }
        }
    }

    private func actionPillButton(_ button: CosmoActionButton) -> some View {
        Button {
            Task {
                await CosmoWindowViewModel.shared.sendMessage(button.action)
            }
        } label: {
            Text(button.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DS.accent.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - System Bubble

    private var systemBubble: some View {
        HStack {
            Spacer()

            Text(message.content)
                .font(DS.cardMeta)
                .italic()
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Tool Result

    private func toolResultRow(name: String, summary: String, isError: Bool) -> some View {
        ToolResultBubble(name: name, summary: summary, isError: isError, timestamp: formattedTime)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
    }

    // MARK: - Context Change

    private func contextChangeDivider(to: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 1)

            Text("Context: \(to)")
                .font(DS.timestamp)
                .foregroundColor(DS.textMuted)
                .lineLimit(1)

            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }
}

// MARK: - Tool Result Bubble (Collapsible)

/// A collapsible row showing a tool execution result.
private struct ToolResultBubble: View {
    let name: String
    let summary: String
    let isError: Bool
    let timestamp: String

    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 12)

                    // Tool name badge
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isError ? DS.red : DS.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (isError ? DS.red : DS.accent).opacity(0.1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if !isExpanded {
                        Text(summary)
                            .font(DS.cardMeta)
                            .foregroundColor(DS.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(timestamp)
                        .font(DS.timestamp)
                        .foregroundColor(DS.textMuted)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }

        if isExpanded {
            Text(summary)
                .font(DS.cardMeta)
                .foregroundColor(DS.textSecondary)
                .padding(.leading, 20)
                .padding(.top, 4)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Context Trace Card (Collapsible)

/// A collapsible card showing what context the AI looked at during a response.
private struct ContextTraceCard: View {
    let lookups: Int
    let sections: [ContextTraceSection]

    @State private var isExpanded = false

    private let iconMap: [String: String] = [
        "person.fill": "person.fill",
        "doc.text": "doc.text",
        "waveform": "waveform",
        "pencil.line": "pencil.line",
        "chart.bar": "chart.bar"
    ]

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        isExpanded.toggle()
                    }
                } label: {
                    collapsedHeader
                }
                .buttonStyle(.plain)

                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.accent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.accent.opacity(0.12), lineWidth: 1)
            )

            Spacer(minLength: 80)
        }
    }

    private var collapsedHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.textMuted)
                .frame(width: 12)

            Image(systemName: "eye")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.accent)

            Text("Context Used")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.accent)

            Text("\(lookups) lookup\(lookups == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Spacer()
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                HStack(spacing: 8) {
                    Image(systemName: section.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.accent.opacity(0.7))
                        .frame(width: 16)

                    Text(section.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 80, alignment: .leading)

                    Text(section.detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(DS.text)
                        .lineLimit(2)
                }
            }
        }
        .padding(.top, 8)
        .padding(.leading, 20)
    }
}

// MARK: - Streaming Indicator

/// Animated three-dot indicator for messages currently being streamed.
/// Uses TimelineView for ProMotion-friendly rendering.
struct StreamingIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 4, height: 4)
                        .opacity(phase == index ? 1.0 : 0.3)
                }
            }
            .padding(.leading, 4)
            .animation(ProMotionSprings.snappy, value: phase)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CosmoMessageBubble_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 0) {
                CosmoMessageBubble(message: .user("How could I adapt this swipe for Ben's brand?"))
                CosmoMessageBubble(message: .assistant("Based on the swipe analysis, here's how I'd adapt this for Ben's casual tone..."))
                CosmoMessageBubble(message: .assistant("Still thinking...", isStreaming: true))
                CosmoMessageBubble(message: .system("Cosmo connected"))
                CosmoMessageBubble(message: .toolResult(name: "search_swipes", summary: "Found 3 matching swipes for 'trust building'"))
                CosmoMessageBubble(message: CosmoWindowMessage(
                    type: .contextTrace(lookups: 4, sections: [
                        ContextTraceSection(icon: "person.fill", label: "Client", detail: "Michael"),
                        ContextTraceSection(icon: "doc.text", label: "Swipes", detail: "Tax tips thread, Trust carousel"),
                        ContextTraceSection(icon: "waveform", label: "Beat Patterns", detail: "Problem-Solution"),
                    ]),
                    content: "Context Used"
                ))
                CosmoMessageBubble(message: .contextChange(from: "Thinkspace", to: "Content Focus Mode"))
            }
            .padding(.vertical, 16)
        }
        .frame(width: 400, height: 600)
        .background(DS.surface)
    }
}
#endif
