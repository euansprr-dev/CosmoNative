// CosmoOS/UI/Plannerum/TimeBlockCard.swift
// Plannerium Time Block Card - Glass morphism scheduled blocks
// Apple-level polish with dimension colors and XP integration

import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - SCHEDULE BLOCK VIEW MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// View model for a scheduled time block
public struct ScheduleBlockViewModel: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let startTime: Date
    public var endTime: Date  // var to allow extending focus sessions
    public let blockType: TimeBlockType
    public let status: BlockStatus
    public let isCompleted: Bool
    public let projectUuid: String?
    public let projectName: String?
    public let linkedAtomIds: [String]
    public let linkedTaskTitles: [String]
    public let difficulty: Double
    public let isCoreObjective: Bool
    public let isRecurring: Bool
    public let recurrenceText: String?

    public init(
        id: String,
        title: String,
        startTime: Date,
        endTime: Date,
        blockType: TimeBlockType,
        status: BlockStatus = .scheduled,
        isCompleted: Bool = false,
        projectUuid: String? = nil,
        projectName: String? = nil,
        linkedAtomIds: [String] = [],
        linkedTaskTitles: [String] = [],
        difficulty: Double = 1.0,
        isCoreObjective: Bool = false,
        isRecurring: Bool = false,
        recurrenceText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.blockType = blockType
        self.status = status
        self.isCompleted = isCompleted
        self.projectUuid = projectUuid
        self.projectName = projectName
        self.linkedAtomIds = linkedAtomIds
        self.linkedTaskTitles = linkedTaskTitles
        self.difficulty = difficulty
        self.isCoreObjective = isCoreObjective
        self.isRecurring = isRecurring
        self.recurrenceText = recurrenceText
    }

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    public var durationMinutes: Int {
        Int(duration / 60)
    }

    public var durationString: String {
        PlannerumTimeUtils.formatDuration(duration)
    }

    public var timeRange: String {
        "\(PlannerumFormatters.time.string(from: startTime)) – \(PlannerumFormatters.time.string(from: endTime))"
    }

    public var estimatedXP: Int {
        PlannerumXP.estimateXP(
            blockType: blockType,
            durationMinutes: durationMinutes,
            difficulty: difficulty,
            isStreakActive: false,
            isCoreObjective: isCoreObjective
        )
    }

    public var isActive: Bool {
        let now = Date()
        return now >= startTime && now <= endTime && !isCompleted
    }

    public var isPast: Bool {
        endTime < Date() && !isCompleted
    }
}

/// Block status states
public enum BlockStatus: String, Codable {
    case scheduled
    case inProgress = "in_progress"
    case paused
    case completed
    case skipped
    case overdue
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - TIME BLOCK CARD
// ═══════════════════════════════════════════════════════════════════════════════

/// A glass morphism card representing a scheduled time block.
///
/// Visual Identity:
/// ```
/// ┌────────────────────────────────────────────────────┐
/// │█ DEEP WORK                          09:00 – 11:30  │
/// │                                                     │
/// │  Draft Planerium specification                     │
/// │  ┊ Project: CosmoOS                                │
/// │                                                     │
/// │  2h 30m  ◆ Core Objective   ✨ +125 XP             │
/// │                                                     │
/// │  Tasks: Fix auth bug, Review PR #42                │
/// └────────────────────────────────────────────────────┘
/// ```
public struct TimeBlockCard: View {

    // MARK: - Properties

    let block: ScheduleBlockViewModel
    let width: CGFloat
    let isHovered: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onComplete: (() -> Void)?

    // MARK: - Initialization

    public init(
        block: ScheduleBlockViewModel,
        width: CGFloat,
        isHovered: Bool = false,
        isSelected: Bool = false,
        onTap: @escaping () -> Void = {},
        onComplete: (() -> Void)? = nil
    ) {
        self.block = block
        self.width = width
        self.isHovered = isHovered
        self.isSelected = isSelected
        self.onTap = onTap
        self.onComplete = onComplete
    }

    // MARK: - Computed

    private var accentColor: Color {
        block.blockType.color
    }

    private var cardOpacity: Double {
        if block.isCompleted { return 0.6 }
        if block.isPast { return 0.7 }
        return 1.0
    }

    private var showActiveIndicator: Bool {
        block.isActive && !block.isCompleted
    }

    // MARK: - Body

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left accent bar
                accentBar

                // Content
                VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
                    // Header row
                    headerRow

                    // Title
                    titleSection

                    // Project (if any)
                    if let projectName = block.projectName {
                        projectLabel(projectName)
                    }

                    // Bottom row: Duration, badges, XP
                    bottomRow

                    // Linked tasks (if any)
                    if !block.linkedTaskTitles.isEmpty {
                        linkedTasksSection
                    }
                }
                .padding(PlannerumLayout.spacingMD)
            }
            .frame(width: width)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.blockCornerRadius))
            .overlay(cardBorder)
            .shadow(
                color: isHovered ? accentColor.opacity(0.30) : Color.black.opacity(0.15),
                radius: isHovered ? 20 : 8,
                x: 0,
                y: isHovered ? 8 : 4
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .opacity(cardOpacity)
        }
        .buttonStyle(.plain)
        .animation(PlannerumSprings.hover, value: isHovered)
    }

    // MARK: - Accent Bar

    private var accentBar: some View {
        ZStack(alignment: .top) {
            // Solid accent
            Rectangle()
                .fill(accentColor)
                .frame(width: PlannerumLayout.blockAccentWidth)

            // Active pulse indicator
            if showActiveIndicator {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: PlannerumLayout.blockAccentWidth)
                    .mask(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            // Block type badge
            HStack(spacing: 4) {
                Image(systemName: block.blockType.icon)
                    .font(.system(size: 10, weight: .semibold))

                Text(block.blockType.shortLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.3)
            }
            .foregroundColor(accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accentColor.opacity(0.15))
            .clipShape(Capsule())

            // Status indicator
            if showActiveIndicator {
                statusBadge(text: "Active", color: PlannerumColors.nowMarker)
            } else if block.isCompleted {
                statusBadge(text: "Done", color: PlannerumColors.nowMarker)
            } else if block.status == .paused {
                statusBadge(text: "Paused", color: PlannerumColors.textMuted)
            }

            Spacer()

            // Time range
            Text(block.timeRange)
                .font(PlannerumTypography.blockTime)
                .foregroundColor(PlannerumColors.textMuted)
        }
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Title Section

    private var titleSection: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            Text(block.title)
                .font(PlannerumTypography.blockTitle)
                .foregroundColor(
                    block.isCompleted
                        ? PlannerumColors.textMuted
                        : PlannerumColors.textPrimary
                )
                .strikethrough(block.isCompleted, color: PlannerumColors.textMuted)
                .lineLimit(2)

            Spacer()

            // Completed checkmark
            if block.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(PlannerumColors.nowMarker)
            }
        }
    }

    // MARK: - Project Label

    private func projectLabel(_ name: String) -> some View {
        HStack(spacing: 4) {
            Text("┊")
                .foregroundColor(PlannerumColors.textMuted)

            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundColor(PlannerumColors.projectInbox.opacity(0.7))

            Text(name)
                .font(PlannerumTypography.blockSubtitle)
                .foregroundColor(PlannerumColors.textTertiary)
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: PlannerumLayout.spacingMD) {
            // Duration badge
            Text(block.durationString)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.1))
                .clipShape(Capsule())

            // Recurring badge
            if block.isRecurring {
                recurringBadge
            }

            // Core objective badge
            if block.isCoreObjective {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                    Text("Core")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(OnyxColors.Accent.amber)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(OnyxColors.Accent.amber.opacity(0.15))
                .clipShape(Capsule())
            }

            // Difficulty indicator (if not default)
            if block.difficulty != 1.0 {
                difficultyIndicator
            }

            Spacer()

            // XP preview
            xpPreview
        }
    }

    private var recurringBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9))
            Text(block.recurrenceText ?? "Recurring")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(PlannerumColors.textTertiary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }

    private var difficultyIndicator: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(
                        i < Int(block.difficulty.rounded())
                            ? accentColor
                            : accentColor.opacity(0.2)
                    )
                    .frame(width: 4, height: 4)
            }
        }
    }

    private var xpPreview: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))

            Text("+\(block.estimatedXP)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .foregroundColor(OnyxColors.Accent.amber)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(OnyxColors.Accent.amber.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Linked Tasks Section

    private var linkedTasksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Soft gradient divider (no hard cuts per plan)
            LinearGradient(
                colors: [PlannerumColors.glassBorder.opacity(0.4), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.vertical, 4)

            // Tasks list
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 9))
                    .foregroundColor(PlannerumColors.textMuted)

                Text(block.linkedTaskTitles.prefix(2).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundColor(PlannerumColors.textTertiary)
                    .lineLimit(1)

                if block.linkedTaskTitles.count > 2 {
                    Text("+\(block.linkedTaskTitles.count - 2)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PlannerumColors.textMuted)
                }
            }
        }
    }

    // MARK: - Card Background (Enhanced Glass Morphism)

    private var cardBackground: some View {
        ZStack {
            // Base glass layer - white @ 6% as per plan
            Color.white.opacity(0.06)

            // Ultra thin material for blur effect
            RoundedRectangle(cornerRadius: PlannerumLayout.blockCornerRadius)
                .fill(.ultraThinMaterial.opacity(0.2))

            // Accent gradient overlay - block color tint
            LinearGradient(
                colors: [
                    accentColor.opacity(isHovered ? 0.12 : (isSelected ? 0.10 : 0.05)),
                    accentColor.opacity(0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Top highlight (glass light reflection)
            VStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                Spacer()
            }

            // Active glow - pulsing green when in progress
            if showActiveIndicator {
                LinearGradient(
                    colors: [
                        PlannerumColors.nowMarker.opacity(0.10),
                        PlannerumColors.nowMarker.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Card Border (Enhanced - brightens on hover as per plan)

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: PlannerumLayout.blockCornerRadius)
            .strokeBorder(
                isSelected
                    ? accentColor.opacity(0.5)
                    : (isHovered ? accentColor.opacity(0.40) : accentColor.opacity(0.20)),
                lineWidth: isSelected ? 2 : 1
            )
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - COMPACT TIME BLOCK CARD
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact card for week/month views
public struct CompactTimeBlockCard: View {

    let block: ScheduleBlockViewModel
    let size: CGFloat

    public init(block: ScheduleBlockViewModel, size: CGFloat = PlannerumLayout.satelliteSize) {
        self.block = block
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Background
            Circle()
                .fill(block.blockType.color.opacity(0.2))

            // Border
            Circle()
                .strokeBorder(block.blockType.color.opacity(0.5), lineWidth: 1)

            // Icon
            Image(systemName: block.blockType.icon)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundColor(block.blockType.color)

            // Completed overlay
            if block.isCompleted {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.4))

                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - TIME BLOCK PLACEHOLDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Empty slot placeholder for drag targets
public struct TimeBlockPlaceholder: View {

    let height: CGFloat
    let isDropTarget: Bool
    let onTap: () -> Void

    public init(
        height: CGFloat,
        isDropTarget: Bool = false,
        onTap: @escaping () -> Void = {}
    ) {
        self.height = height
        self.isDropTarget = isDropTarget
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: PlannerumLayout.radiusMD)
                .strokeBorder(
                    isDropTarget
                        ? PlannerumColors.primary
                        : PlannerumColors.glassBorder.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: PlannerumLayout.radiusMD)
                        .fill(
                            isDropTarget
                                ? PlannerumColors.primary.opacity(0.1)
                                : Color.clear
                        )
                )
                .overlay(
                    isDropTarget
                        ? AnyView(dropTargetOverlay)
                        : AnyView(EmptyView())
                )
        }
        .buttonStyle(.plain)
        .frame(height: height)
    }

    private var dropTargetOverlay: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
            Text("Drop to schedule")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(PlannerumColors.primary)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - BLOCK DRAG PREVIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// Preview shown while dragging a block
public struct BlockDragPreview: View {

    let block: ScheduleBlockViewModel

    public var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: block.blockType.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(block.blockType.color)

            // Title
            Text(block.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(PlannerumColors.textPrimary)
                .lineLimit(1)

            // Duration
            Text(block.durationString)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PlannerumColors.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: PlannerumLayout.radiusMD)
                .fill(PlannerumGlass.Block.background)
                .overlay(
                    RoundedRectangle(cornerRadius: PlannerumLayout.radiusMD)
                        .strokeBorder(block.blockType.color.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PREVIEW
// ═══════════════════════════════════════════════════════════════════════════════

#if DEBUG
struct TimeBlockCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Active block
                TimeBlockCard(
                    block: ScheduleBlockViewModel(
                        id: "1",
                        title: "Draft Planerium specification document",
                        startTime: Date(),
                        endTime: Date().addingTimeInterval(9000),
                        blockType: .deepWork,
                        status: .inProgress,
                        projectUuid: "proj-1",
                        projectName: "CosmoOS",
                        linkedTaskTitles: ["Fix auth bug", "Review PR #42"],
                        isCoreObjective: true
                    ),
                    width: 380,
                    isHovered: false
                )

                // Completed block
                TimeBlockCard(
                    block: ScheduleBlockViewModel(
                        id: "2",
                        title: "Review client call notes",
                        startTime: Date().addingTimeInterval(-7200),
                        endTime: Date().addingTimeInterval(-3600),
                        blockType: .review,
                        status: .completed,
                        isCompleted: true
                    ),
                    width: 380,
                    isHovered: true
                )

                // Creative block
                TimeBlockCard(
                    block: ScheduleBlockViewModel(
                        id: "3",
                        title: "Write newsletter issue #24",
                        startTime: Date().addingTimeInterval(3600),
                        endTime: Date().addingTimeInterval(7200),
                        blockType: .creative,
                        projectName: "Content"
                    ),
                    width: 380
                )

                // Compact cards
                HStack(spacing: 12) {
                    ForEach(TimeBlockType.allCases.prefix(5), id: \.self) { type in
                        CompactTimeBlockCard(
                            block: ScheduleBlockViewModel(
                                id: type.rawValue,
                                title: type.rawValue,
                                startTime: Date(),
                                endTime: Date().addingTimeInterval(3600),
                                blockType: type
                            ),
                            size: 28
                        )
                    }
                }

                // Placeholder
                TimeBlockPlaceholder(height: 60, isDropTarget: true)
                    .frame(width: 380)
            }
            .padding(40)
        }
        .background(PlannerumColors.background)
        .preferredColorScheme(.dark)
    }
}
#endif
