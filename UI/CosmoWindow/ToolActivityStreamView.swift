// CosmoOS/UI/CosmoWindow/ToolActivityStreamView.swift
// Live tool activity visualization — Claude Code style
// Shows shimmer on active tool, collapsible groups, connection lines, done checkmarks
// February 2026

import SwiftUI

// MARK: - Tool Activity Stream View

/// Renders live tool execution activity inline in the Cosmo chat window.
/// Shows a shimmer animation on the active tool, expandable "Viewed N files"
/// groups, vertical connection lines, and "Done" checkmarks.
struct ToolActivityStreamView: View {

    let groups: [ToolActivityGroup]
    var activeLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Active tool shimmer label
            if let label = activeLabel {
                ActiveToolLabel(label: label)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Grouped tool activity
            ForEach(groups) { group in
                ToolActivityGroupView(group: group)
            }
        }
    }
}

// MARK: - Active Tool Label (Shimmer)

/// Shows the currently executing tool with a sliding shimmer gradient animation.
/// Uses onAppear/onDisappear to stop the TimelineView when not visible,
/// preventing render load when scrolled offscreen.
private struct ActiveToolLabel: View {

    let label: String
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                    let offset = CGFloat(phase.truncatingRemainder(dividingBy: 2.0)) / 2.0
                    shimmerContent(offset: offset)
                }
            } else {
                shimmerContent(offset: 0)
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private func shimmerContent(offset: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.accent)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textSecondary)
                .lineLimit(1)

            ShimmerChevrons(phase: offset)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(shimmerBackground(offset: offset))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func shimmerBackground(offset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        DS.accent.opacity(0.03),
                        DS.accent.opacity(0.08),
                        DS.accent.opacity(0.03)
                    ],
                    startPoint: UnitPoint(x: offset - 0.3, y: 0.5),
                    endPoint: UnitPoint(x: offset + 0.3, y: 0.5)
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DS.accent.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - Shimmer Chevrons

/// Animated ">>>" chevrons that pulse to indicate active processing.
private struct ShimmerChevrons: View {

    let phase: CGFloat

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(DS.accent.opacity(chevronOpacity(index: index)))
            }
        }
    }

    private func chevronOpacity(index: Int) -> Double {
        let normalizedPhase = phase * 3.0
        let distance = abs(normalizedPhase - Double(index))
        return max(0.2, 1.0 - distance * 0.4)
    }
}

// MARK: - Tool Activity Group View

/// A collapsible group of related tool calls (e.g. "Viewed 7 files").
private struct ToolActivityGroupView: View {

    let group: ToolActivityGroup
    @State private var isExpanded: Bool = true

    private let maxVisibleItems = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header
            groupHeader

            // Expanded items with connection line
            if isExpanded {
                expandedItems
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Done indicator
            if group.isComplete {
                doneIndicator
            }
        }
        .animation(ProMotionSprings.snappy, value: isExpanded)
        .animation(ProMotionSprings.snappy, value: group.isComplete)
    }

    // MARK: - Group Header

    private var groupHeader: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 10)

                Text("\(group.category) \(group.items.count) file\(group.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textSecondary)

                Spacer()

                // Active count badge
                let activeCount = group.items.filter { $0.status == .active }.count
                if activeCount > 0 {
                    Text("\(activeCount) active")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Items

    private var expandedItems: some View {
        let visibleItems = Array(group.items.prefix(maxVisibleItems))
        let overflowCount = max(0, group.items.count - maxVisibleItems)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                ToolActivityItemRow(
                    item: item,
                    isLast: index == visibleItems.count - 1 && overflowCount == 0
                )
            }

            if overflowCount > 0 {
                overflowRow(count: overflowCount)
            }
        }
    }

    // MARK: - Overflow Row

    private func overflowRow(count: Int) -> some View {
        HStack(spacing: 0) {
            // Connection line segment
            connectionLineSegment(isLast: true)

            Text("and \(count) more...")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(DS.textMuted)
                .italic()
                .padding(.leading, 4)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Done Indicator

    private var doneIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.green)

            Text("Done")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.green)
        }
        .padding(.top, 4)
        .padding(.leading, 2)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

// MARK: - Tool Activity Item Row

/// A single tool call item with a vertical dotted connection line.
private struct ToolActivityItemRow: View {

    let item: ToolActivityItem
    let isLast: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Vertical connection line
            connectionLineSegment(isLast: isLast)

            // Item icon
            Group {
                if item.status == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.green)
                } else {
                    Image(systemName: item.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                }
            }
            .frame(width: 14)

            // Item label
            Text(truncatedLabel)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(item.status == .done ? DS.textMuted : DS.textSecondary)
                .lineLimit(1)
                .padding(.leading, 4)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var truncatedLabel: String {
        if item.label.count > 40 {
            return String(item.label.prefix(37)) + "..."
        }
        return item.label
    }
}

// MARK: - Connection Line Segment

/// Vertical dashed connection line used between grouped tool activity items.
private func connectionLineSegment(isLast: Bool) -> some View {
    VStack(spacing: 0) {
        if isLast {
            // Short end segment with dot
            DashedVerticalLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundColor(DS.border)
                .frame(width: 1, height: 10)
        } else {
            // Full-height segment
            DashedVerticalLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundColor(DS.border)
                .frame(width: 1)
        }
    }
    .frame(width: 20, alignment: .center)
}

// MARK: - Dashed Vertical Line Shape

/// A vertical line shape used for connection lines between tool activity items.
private struct DashedVerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Preview

#if DEBUG
struct ToolActivityStreamView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var groups: [ToolActivityGroup] = [
            ToolActivityGroup(
                category: "Viewed",
                items: [
                    ToolActivityItem(icon: "doc.text", label: "Reading burnt out reel", status: .done),
                    ToolActivityItem(icon: "doc.text", label: "Reading Act broke post", status: .done),
                    ToolActivityItem(icon: "doc.text", label: "Reading buying home at 25", status: .done),
                    ToolActivityItem(icon: "doc.text", label: "Loading client profile \"Michael\"", status: .active),
                ],
                isComplete: false
            ),
            ToolActivityGroup(
                category: "Generated",
                items: [
                    ToolActivityItem(icon: "sparkles", label: "Generating outline", status: .active),
                ],
                isComplete: false
            ),
        ]
        @State private var activeLabel: String? = "Searching swipes for \"trust\""

        var body: some View {
            VStack(alignment: .leading) {
                ToolActivityStreamView(
                    groups: groups,
                    activeLabel: activeLabel
                )
                .padding(16)
            }
            .frame(width: 380, height: 400)
            .background(DS.surface)
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
#endif
