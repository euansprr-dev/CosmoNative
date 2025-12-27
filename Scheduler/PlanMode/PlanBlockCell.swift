// CosmoOS/Scheduler/PlanMode/PlanBlockCell.swift
// Draggable, resizable schedule block cell for the Plan Mode grid
//
// Design Philosophy:
// - Premium spring physics for all interactions
// - Lift shadow on drag for spatial hierarchy
// - Resize handles appear on hover/selection
// - Color-coded by block type with accent seam
// - Completion state with strikethrough and fade

import SwiftUI

// MARK: - Plan Block Cell

/// A single draggable block in the weekly grid
public struct PlanBlockCell: View {

    // MARK: - Properties

    let block: ScheduleBlock
    @ObservedObject var engine: SchedulerEngine
    let columnWidth: CGFloat
    let dayDate: Date

    // MARK: - State

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false
    @State private var isResizing: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGFloat = 0
    @State private var showResizeHandles: Bool = false

    // MARK: - Computed Properties

    private var yPosition: CGFloat {
        guard let startTime = block.startTime else { return 0 }
        return SchedulerGridCalculator.yPosition(for: startTime)
    }

    private var blockHeight: CGFloat {
        let duration = block.effectiveDurationMinutes
        return SchedulerGridCalculator.blockHeight(durationMinutes: duration)
    }

    private var accentColor: Color {
        if let customColor = block.color {
            return colorFromString(customColor)
        }
        return SchedulerColors.color(for: block.blockType)
    }

    private var isSelected: Bool {
        engine.selectedBlock?.uuid == block.uuid
    }

    // MARK: - Body

    public var body: some View {
        // Only render if block is scheduled
        if block.isScheduled {
            blockContent
                .frame(height: max(SchedulerDimensions.minBlockHeight, blockHeight + resizeDelta))
                .offset(y: yPosition + (isDragging ? dragOffset.height : 0))
                .offset(x: isDragging ? dragOffset.width : 0)
                .padding(.horizontal, SchedulerDimensions.blockHorizontalPadding)
                .padding(.vertical, SchedulerDimensions.blockVerticalMargin)
                .zIndex(isDragging ? 100 : (isSelected ? 10 : 1))
                .transition(.blockAppear)
        }
    }

    // MARK: - Block Content

    private var blockContent: some View {
        ZStack(alignment: .topLeading) {
            // Background card
            blockBackground

            // Content
            VStack(alignment: .leading, spacing: 2) {
                // Title row
                HStack(spacing: 6) {
                    // Completion indicator (for completable types)
                    if block.blockType.supportsCompletion {
                        CompletionIndicator(
                            isCompleted: block.isCompleted,
                            accentColor: accentColor,
                            action: {
                                Task {
                                    try? await engine.toggleCompletion(for: block)
                                }
                            }
                        )
                    }

                    // Title
                    Text(block.title)
                        .font(blockHeight > 40 ? CosmoTypography.body : CosmoTypography.bodySmall)
                        .fontWeight(.medium)
                        .foregroundColor(block.isCompleted ? CosmoColors.textTertiary : CosmoColors.textPrimary)
                        .strikethrough(block.isCompleted, color: CosmoColors.textTertiary)
                        .lineLimit(blockHeight > 80 ? 2 : 1)

                    Spacer()

                    // Priority indicator
                    if block.priority == .urgent || block.priority == .high {
                        PriorityBadge(priority: block.priority)
                    }
                }

                // Time label (if enough space)
                if blockHeight > 50 {
                    Text(block.formattedTimeRange)
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                }

                // Checklist preview (if enough space)
                if blockHeight > 80, let checklist = block.checklist, !checklist.isEmpty {
                    PlanBlockChecklistPreview(items: checklist)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, SchedulerDimensions.blockAccentWidth + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 6)

            // Resize handles (bottom)
            if showResizeHandles || isResizing {
                PlanBlockResizeHandle(position: .bottom)
                    .gesture(resizeGesture)
                    .transition(.opacity)
            }
        }
        .schedulerBlockStyle(
            blockType: block.blockType,
            isSelected: isSelected,
            isHovered: isHovered,
            isDragging: isDragging
        )
        .opacity(block.isCompleted ? 0.7 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            withAnimation(SchedulerSprings.instant) {
                showResizeHandles = hovering || isSelected
            }
        }
        .onTapGesture {
            engine.selectBlock(block)
        }
        .gesture(dragGesture)
        .contextMenu {
            blockContextMenu
        }
        .animation(SchedulerSprings.standard, value: block.isCompleted)
        .animation(SchedulerSprings.blockMove, value: isDragging)
    }

    // MARK: - Background

    private var blockBackground: some View {
        RoundedRectangle(cornerRadius: SchedulerDimensions.blockCornerRadius)
            .fill(SchedulerColors.cardBackground)
            .overlay(alignment: .leading) {
                // Accent seam
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor.opacity(block.isCompleted ? 0.5 : 1.0))
                    .frame(width: SchedulerDimensions.blockAccentWidth)
                    .padding(.leading, 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: SchedulerDimensions.blockCornerRadius))
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    SchedulerHaptics.medium()
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                handleDragEnd(translation: value.translation)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                    SchedulerHaptics.light()
                }

                // Snap to 15-minute intervals
                let rawDelta = value.translation.height
                let intervalHeight = SchedulerDimensions.hourHeight / 4
                let snappedDelta = round(rawDelta / intervalHeight) * intervalHeight

                // Enforce minimum height
                let newHeight = blockHeight + snappedDelta
                if newHeight >= SchedulerDimensions.minBlockHeight {
                    resizeDelta = snappedDelta
                }
            }
            .onEnded { value in
                handleResizeEnd()
            }
    }

    // MARK: - Gesture Handlers

    private func handleDragEnd(translation: CGSize) {
        isDragging = false

        // Calculate new time based on vertical offset
        guard let currentStart = block.startTime else {
            dragOffset = .zero
            return
        }

        // Convert pixel offset to time offset
        let minutesDelta = Int(translation.height / SchedulerDimensions.hourHeight * 60)
        let snappedMinutes = (minutesDelta / 15) * 15

        // Calculate day offset from horizontal movement
        let dayOffset = Int(round(translation.width / columnWidth))

        // Calculate new start time
        var newStart = currentStart.addingTimeInterval(TimeInterval(snappedMinutes * 60))
        if dayOffset != 0 {
            newStart = Calendar.current.date(byAdding: .day, value: dayOffset, to: newStart) ?? newStart
        }

        // Snap to 15-minute intervals
        newStart = SchedulerGridCalculator.snapToInterval(newStart, intervalMinutes: 15)

        // Only update if actually moved
        if snappedMinutes != 0 || dayOffset != 0 {
            Task {
                try? await engine.rescheduleBlock(block, to: newStart)
            }
        }

        withAnimation(SchedulerSprings.blockMove) {
            dragOffset = .zero
        }
    }

    private func handleResizeEnd() {
        isResizing = false

        // Calculate new duration
        let minutesDelta = Int(resizeDelta / SchedulerDimensions.hourHeight * 60)
        let snappedMinutes = (minutesDelta / 15) * 15
        let newDuration = block.effectiveDurationMinutes + snappedMinutes

        // Update if changed
        if snappedMinutes != 0 && newDuration >= 15 {
            Task {
                try? await engine.resizeBlock(block, newDurationMinutes: newDuration)
            }
        }

        withAnimation(SchedulerSprings.blockResize) {
            resizeDelta = 0
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var blockContextMenu: some View {
        Button {
            engine.openEditor(for: block)
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        if block.blockType.supportsCompletion {
            Button {
                Task { try? await engine.toggleCompletion(for: block) }
            } label: {
                Label(
                    block.isCompleted ? "Mark Incomplete" : "Mark Complete",
                    systemImage: block.isCompleted ? "circle" : "checkmark.circle"
                )
            }
        }

        Divider()

        Button {
            engine.selectBlock(block)
        } label: {
            Label("Show Details", systemImage: "sidebar.right")
        }

        Divider()

        Button(role: .destructive) {
            Task { try? await engine.deleteBlock(block) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func colorFromString(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "coral": return CosmoColors.coral
        case "lavender": return CosmoColors.lavender
        case "skyblue", "sky_blue", "blue": return CosmoColors.skyBlue
        case "emerald", "green": return CosmoColors.emerald
        case "note", "yellow": return CosmoColors.note
        default: return CosmoColors.lavender
        }
    }
}

// MARK: - Completion Indicator

private struct CompletionIndicator: View {
    let isCompleted: Bool
    let accentColor: Color
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(isCompleted ? CosmoColors.emerald : accentColor.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 16, height: 16)

                if isCompleted {
                    Circle()
                        .fill(CosmoColors.emerald)
                        .frame(width: 16, height: 16)

                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
        .animation(SchedulerSprings.blockComplete, value: isCompleted)
    }
}

// MARK: - Priority Badge

private struct PriorityBadge: View {
    let priority: ScheduleBlockPriority

    var body: some View {
        Circle()
            .fill(SchedulerColors.color(for: priority))
            .frame(width: 6, height: 6)
    }
}

// MARK: - Checklist Preview

private struct PlanBlockChecklistPreview: View {
    let items: [ScheduleChecklistItem]

    private var displayItems: [ScheduleChecklistItem] {
        Array(items.prefix(3))
    }

    private var completedCount: Int {
        items.filter { $0.isCompleted }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(displayItems) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 8))
                        .foregroundColor(item.isCompleted ? CosmoColors.emerald : CosmoColors.textTertiary)

                    Text(item.title)
                        .font(CosmoTypography.caption)
                        .foregroundColor(item.isCompleted ? CosmoColors.textTertiary : CosmoColors.textSecondary)
                        .lineLimit(1)
                }
            }

            if items.count > 3 {
                Text("+\(items.count - 3) more")
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
            }
        }
    }
}

// MARK: - Resize Handle

private struct PlanBlockResizeHandle: View {
    enum Position {
        case top, bottom
    }

    let position: Position

    @State private var isHovered: Bool = false

    var body: some View {
        VStack {
            if position == .bottom {
                Spacer()
            }

            HStack {
                Spacer()

                Capsule()
                    .fill(CosmoColors.glassGrey.opacity(isHovered ? 0.8 : 0.5))
                    .frame(width: 32, height: 4)

                Spacer()
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }

            if position == .top {
                Spacer()
            }
        }
        .animation(SchedulerSprings.instant, value: isHovered)
    }
}

// MARK: - Preview

#if DEBUG
struct PlanBlockCell_Previews: PreviewProvider {
    static var previews: some View {
        let engine = SchedulerEngine()
        let block = ScheduleBlock.task(
            title: "Review design specs",
            startTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()),
            durationMinutes: 60
        )

        ZStack {
            SchedulerColors.background.ignoresSafeArea()

            PlanBlockCell(
                block: block,
                engine: engine,
                columnWidth: 150,
                dayDate: Date()
            )
            .frame(width: 150, height: 300)
        }
    }
}
#endif
