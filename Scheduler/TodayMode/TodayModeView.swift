// CosmoOS/Scheduler/TodayMode/TodayModeView.swift
// Action-focused task list for execution mode
//
// Design Philosophy:
// - Minimalist list optimized for rapid completion
// - Time-based grouping (Morning, Afternoon, Evening, Unscheduled)
// - One-tap completion with satisfying animations
// - Clear visual hierarchy: current action is prominent
// - Subtle overdue indicators without anxiety

import SwiftUI

// MARK: - Today Mode View

/// Action-focused task list for "execution mode"
public struct TodayModeView: View {

    // MARK: - State

    @ObservedObject var engine: SchedulerEngine
    @State private var animateIn: Bool = false
    @State private var expandedSection: TodaySection? = nil
    @State private var completionCelebration: String? = nil

    // MARK: - Grouped Blocks

    private var groupedBlocks: [(section: TodaySection, blocks: [ScheduleBlock])] {
        let periods = engine.todayBlocksByPeriod

        var groups: [(TodaySection, [ScheduleBlock])] = []

        if !periods.morning.isEmpty {
            groups.append((.morning, periods.morning))
        }
        if !periods.afternoon.isEmpty {
            groups.append((.afternoon, periods.afternoon))
        }
        if !periods.evening.isEmpty {
            groups.append((.evening, periods.evening))
        }
        if !periods.unscheduled.isEmpty {
            groups.append((.unscheduled, periods.unscheduled))
        }

        return groups
    }

    private var isEmpty: Bool {
        engine.todayBlocks.isEmpty
    }

    private var currentSection: TodaySection {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return .morning }
        if hour < 17 { return .afternoon }
        return .evening
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            SchedulerColors.background

            if isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(Array(groupedBlocks.enumerated()), id: \.element.section) { index, group in
                            Section {
                                sectionContent(blocks: group.blocks, section: group.section, sectionIndex: index)
                            } header: {
                                sectionHeader(section: group.section, count: group.blocks.count)
                            }
                        }

                        // Bottom padding for comfortable scrolling
                        Color.clear.frame(height: 100)
                    }
                    .padding(.top, 8)
                }
            }

            // Completion celebration overlay
            if let blockTitle = completionCelebration {
                CompletionCelebration(title: blockTitle)
                    .transition(.opacity.combined(with: .scale))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(SchedulerSprings.standard) {
                                completionCelebration = nil
                            }
                        }
                    }
            }
        }
        .onAppear {
            withAnimation(SchedulerSprings.gentle.delay(0.1)) {
                animateIn = true
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(section: TodaySection, count: Int) -> some View {
        HStack(spacing: 8) {
            // Section icon
            Image(systemName: section.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(section == currentSection ? CosmoColors.coral : CosmoColors.textTertiary)

            // Section name
            Text(section.displayName)
                .font(CosmoTypography.label)
                .foregroundColor(section == currentSection ? CosmoColors.textPrimary : CosmoColors.textSecondary)

            // Count badge
            Text("\(count)")
                .font(CosmoTypography.labelSmall)
                .foregroundColor(CosmoColors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(CosmoColors.glassGrey.opacity(0.3))
                )

            Spacer()

            // Current section indicator
            if section == currentSection {
                Text("Now")
                    .font(CosmoTypography.labelSmall)
                    .foregroundColor(CosmoColors.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(CosmoColors.coral.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(height: SchedulerDimensions.groupHeaderHeight)
        .background(
            SchedulerColors.headerBackground
                .opacity(0.95)
        )
    }

    // MARK: - Section Content

    private func sectionContent(blocks: [ScheduleBlock], section: TodaySection, sectionIndex: Int) -> some View {
        ForEach(Array(blocks.enumerated()), id: \.element.uuid) { index, block in
            TodayBlockRow(
                block: block,
                engine: engine,
                isCurrentSection: section == currentSection,
                onComplete: { completed in
                    if completed {
                        withAnimation(SchedulerSprings.blockComplete) {
                            completionCelebration = block.title
                        }
                    }
                }
            )
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 10)
            .animation(
                SchedulerSprings.staggered(index: sectionIndex * 10 + index),
                value: animateIn
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            // Illustration
            ZStack {
                Circle()
                    .fill(CosmoColors.emerald.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(CosmoColors.emerald.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("All Clear")
                    .font(CosmoTypography.title)
                    .foregroundColor(CosmoColors.textPrimary)

                Text("No tasks for today. Enjoy your time or add something new.")
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            // Add task button
            Button {
                engine.openEditor(proposedStart: Date())
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add Task")
                        .font(CosmoTypography.label)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(CosmoColors.lavender)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(animateIn ? 1 : 0)
        .animation(SchedulerSprings.gentle.delay(0.2), value: animateIn)
    }
}

// MARK: - Today Section

enum TodaySection: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case unscheduled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .unscheduled: return "Unscheduled"
        }
    }

    var systemImage: String {
        switch self {
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "sunset"
        case .unscheduled: return "tray"
        }
    }
}

// MARK: - Today Block Row

/// Single row in the today list
struct TodayBlockRow: View {

    let block: ScheduleBlock
    @ObservedObject var engine: SchedulerEngine
    let isCurrentSection: Bool
    let onComplete: (Bool) -> Void

    @State private var isHovered: Bool = false
    @State private var checkboxScale: CGFloat = 1.0

    private var isSelected: Bool {
        engine.selectedBlock?.uuid == block.uuid
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox / completion indicator
            if block.blockType.supportsCompletion {
                CompletionCheckbox(
                    isCompleted: block.isCompleted,
                    blockType: block.blockType,
                    scale: $checkboxScale,
                    action: {
                        Task {
                            try? await engine.toggleCompletion(for: block)
                            onComplete(!block.isCompleted)
                        }
                    }
                )
            } else {
                // Type indicator for non-completable
                BlockTypeIndicator(blockType: block.blockType)
            }

            // Main content
            VStack(alignment: .leading, spacing: 2) {
                // Title
                Text(block.title)
                    .font(CosmoTypography.body)
                    .fontWeight(.medium)
                    .foregroundColor(block.isCompleted ? CosmoColors.textTertiary : CosmoColors.textPrimary)
                    .strikethrough(block.isCompleted, color: CosmoColors.textTertiary)
                    .lineLimit(1)

                // Subtitle (time or project)
                HStack(spacing: 8) {
                    if block.isScheduled {
                        Label(block.formattedStartTime, systemImage: "clock")
                            .font(CosmoTypography.caption)
                            .foregroundColor(block.isOverdue ? CosmoColors.softRed : CosmoColors.textTertiary)
                    }

                    if let duration = block.durationMinutes, duration > 0 {
                        Text(block.formattedDuration)
                            .font(CosmoTypography.caption)
                            .foregroundColor(CosmoColors.textTertiary)
                    }

                    // Semantic link count
                    if let links = block.semanticLinks, !links.isEmpty {
                        Label("\(links.totalLinkCount)", systemImage: "link")
                            .font(CosmoTypography.caption)
                            .foregroundColor(CosmoColors.lavender)
                    }
                }
            }

            Spacer()

            // Priority indicator
            if block.priority == .urgent || block.priority == .high {
                TodayPriorityIndicator(priority: block.priority)
            }

            // Chevron (for opening detail drawer)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(CosmoColors.textTertiary.opacity(isHovered ? 1 : 0.5))
        }
        .todayRowStyle(
            isCompleted: block.isCompleted,
            isOverdue: block.isOverdue,
            isHovered: isHovered
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            engine.selectBlock(block)
        }
        .contextMenu {
            rowContextMenu
        }
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        Button {
            engine.openEditor(for: block)
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        if block.blockType.supportsCompletion {
            Button {
                Task {
                    try? await engine.toggleCompletion(for: block)
                    onComplete(!block.isCompleted)
                }
            } label: {
                Label(
                    block.isCompleted ? "Mark Incomplete" : "Mark Complete",
                    systemImage: block.isCompleted ? "circle" : "checkmark.circle"
                )
            }
        }

        Divider()

        if !block.isScheduled {
            Button {
                // Schedule for now
                Task {
                    try? await engine.rescheduleBlock(block, to: Date())
                }
            } label: {
                Label("Schedule Now", systemImage: "clock")
            }
        }

        Button {
            // Move to tomorrow
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let scheduledTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
            Task {
                try? await engine.rescheduleBlock(block, to: scheduledTime)
            }
        } label: {
            Label("Move to Tomorrow", systemImage: "arrow.right.circle")
        }

        Divider()

        Button(role: .destructive) {
            Task { try? await engine.deleteBlock(block) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Completion Checkbox

private struct CompletionCheckbox: View {
    let isCompleted: Bool
    let blockType: ScheduleBlockType
    @Binding var scale: CGFloat
    let action: () -> Void

    @State private var isHovered: Bool = false

    private var accentColor: Color {
        SchedulerColors.color(for: blockType)
    }

    var body: some View {
        Button(action: {
            // Animate checkbox
            withAnimation(SchedulerSprings.instant) {
                scale = 0.8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(SchedulerSprings.blockComplete) {
                    scale = 1.0
                }
            }
            action()
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        isCompleted ? CosmoColors.emerald : accentColor.opacity(isHovered ? 0.6 : 0.4),
                        lineWidth: 2
                    )
                    .frame(width: SchedulerDimensions.checkboxSize, height: SchedulerDimensions.checkboxSize)

                // Fill on completion
                if isCompleted {
                    Circle()
                        .fill(CosmoColors.emerald)
                        .frame(width: SchedulerDimensions.checkboxSize, height: SchedulerDimensions.checkboxSize)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(scale)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
        .animation(SchedulerSprings.blockComplete, value: isCompleted)
    }
}

// MARK: - Block Type Indicator

private struct BlockTypeIndicator: View {
    let blockType: ScheduleBlockType

    var body: some View {
        ZStack {
            Circle()
                .fill(SchedulerColors.color(for: blockType).opacity(0.15))
                .frame(width: SchedulerDimensions.checkboxSize, height: SchedulerDimensions.checkboxSize)

            Image(systemName: blockType.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SchedulerColors.color(for: blockType))
        }
    }
}

// MARK: - Priority Indicator

private struct TodayPriorityIndicator: View {
    let priority: ScheduleBlockPriority

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<priorityLevel, id: \.self) { _ in
                Image(systemName: "exclamationmark")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundColor(SchedulerColors.color(for: priority))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(SchedulerColors.color(for: priority).opacity(0.1))
        )
    }

    private var priorityLevel: Int {
        switch priority {
        case .urgent: return 3
        case .high: return 2
        case .medium: return 1
        case .low: return 0
        }
    }
}

// MARK: - Completion Celebration

private struct CompletionCelebration: View {
    let title: String

    @State private var showCheck: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CosmoColors.emerald.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .scaleEffect(showCheck ? 1 : 0.5)

                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(CosmoColors.emerald)
                    .scaleEffect(showCheck ? 1 : 0)
            }

            Text("Done!")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)
                .opacity(showCheck ? 1 : 0)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .onAppear {
            withAnimation(SchedulerSprings.blockComplete) {
                showCheck = true
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TodayModeView_Previews: PreviewProvider {
    static var previews: some View {
        TodayModeView(engine: SchedulerEngine())
            .frame(width: 400, height: 700)
    }
}
#endif
