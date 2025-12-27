// CosmoOS/UI/Plannerum/DayTimelineView.swift
// Plannerium Day Timeline - Vertical time ribbon with flowing hours
// Apple-level polish with NowBar integration and glass block cards

import SwiftUI
import Combine

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DAY TIMELINE VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// The Day view in Plannerium - a vertical time ribbon showing scheduled blocks.
///
/// Visual Layout:
/// ```
/// ┌──────────────────────────────────────────────────────────────────────────┐
/// │  SUNDAY, DECEMBER 22                                                      │
/// │  [TODAY] ◀ ▶                                    5 blocks · 6h 30m        │
/// ├──────────────────────────────────────────────────────────────────────────┤
/// │                                                                           │
/// │  05 ─────────────────────────────────────────────────────────────────    │
/// │                                                                           │
/// │  06 ─────────────────────────────────────────────────────────────────    │
/// │                                                                           │
/// │  09 ──┬────────────────────────────────────────────────────────────────  │
/// │       │ ┌───────────────────────────────────────────────────────────┐   │
/// │       │ │  ◆ DEEP WORK                             09:00 – 11:30    │   │
/// │       │ │  Cosmo Development                                        │   │
/// │  10 ──┤ │  ┊ Project: CosmoOS                                       │   │
/// │       │ │  2h 30m  ⭐ Core                          ✨ +125 XP      │   │
/// │  11 ──┤ └───────────────────────────────────────────────────────────┘   │
/// │       │                                                                  │
/// │  13 ═══════════════════════════════════════════════════════════════════  │
/// │       ● NOW 13:24                                                        │
/// │       ════════════════════════════════════════════►                      │
/// │                                                                           │
/// │  14 ──┬────────────────────────────────────────────────────────────────  │
/// │       │ ┌───────────────────────────────────────────────────────────┐   │
/// │       │ │  ◆ CREATIVE                              14:00 – 16:00    │   │
/// │       │ │  Content Writing                                          │   │
/// │       │ │  2h  ✨ +95 XP                                            │   │
/// │  15 ──┤ └───────────────────────────────────────────────────────────┘   │
/// │                                                                           │
/// └──────────────────────────────────────────────────────────────────────────┘
/// ```
public struct DayTimelineView: View {

    // MARK: - Properties

    let date: Date
    let onDateChange: (Date) -> Void
    let onBlockSelect: ((ScheduleBlockViewModel) -> Void)?

    // MARK: - State

    @StateObject private var viewModel = DayTimelineViewModel()
    @State private var hoveredBlockId: String?
    @State private var selectedBlockId: String?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var currentTime = Date()
    @State private var timerCancellable: AnyCancellable?

    // Staggered block entry animation state (40ms between each per plan)
    @State private var visibleBlockIds: Set<String> = []

    // MARK: - Layout

    private enum Layout {
        static let startHour: Int = 5   // 5 AM
        static let endHour: Int = 24    // Midnight
        static let scrollAnchorId = "now-anchor"
    }

    // MARK: - Computed

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var totalHours: Int {
        Layout.endHour - Layout.startHour
    }

    private var timelineHeight: CGFloat {
        CGFloat(totalHours) * PlannerumLayout.hourRowHeight
    }

    // MARK: - Initialization

    public init(
        date: Date,
        onDateChange: @escaping (Date) -> Void,
        onBlockSelect: ((ScheduleBlockViewModel) -> Void)? = nil
    ) {
        self.date = date
        self.onDateChange = onDateChange
        self.onBlockSelect = onBlockSelect
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { outerGeometry in
            VStack(spacing: 0) {
                // Floating date header (no background container)
                floatingDateHeader

                // Timeline content - expands to fill available space
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            // Hour grid background
                            hourGrid

                            // Scheduled blocks layer
                            blocksLayer(in: outerGeometry)

                            // Now bar (only if today)
                            if isToday {
                                nowBarLayer(in: outerGeometry)
                            }
                        }
                        .frame(minHeight: timelineHeight)
                        .padding(.bottom, 40)
                    }
                    .onAppear {
                        scrollProxy = proxy
                        if isToday {
                            scrollToCurrentTime(proxy: proxy)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity) // Fill all available horizontal space
        }
        .background(Color.clear) // Transparent - realm background shows through
        .onAppear {
            Task { await viewModel.loadBlocks(for: date) }
            startTimeUpdates()
        }
        .onDisappear {
            timerCancellable?.cancel()
        }
        .onChange(of: date) { _, newDate in
            Task { await viewModel.loadBlocks(for: newDate) }
        }
    }

    // MARK: - Floating Date Header (no container background)

    private var floatingDateHeader: some View {
        HStack(spacing: PlannerumLayout.spacingMD) {
            // Date info - floating text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: PlannerumLayout.spacingSM) {
                    // Today badge
                    if isToday {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(PlannerumColors.nowMarker)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(PlannerumColors.nowMarker.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    // Full date - floating text
                    Text(PlannerumFormatters.dayFull.string(from: date).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(PlannerumColors.textPrimary)
                        .tracking(1.5)
                }

                // Block summary - subtle
                if !viewModel.blocks.isEmpty {
                    Text("\(viewModel.blocks.count) blocks · \(viewModel.totalDuration)")
                        .font(.system(size: 11))
                        .foregroundColor(PlannerumColors.textMuted)
                }
            }

            Spacer()

            // Navigation controls - minimal glass
            HStack(spacing: 12) {
                navButton(icon: "chevron.left") { navigateDay(-1) }

                Button(action: jumpToToday) {
                    Text("Today")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isToday ? PlannerumColors.textMuted : PlannerumColors.nowMarker)
                }
                .buttonStyle(.plain)
                .disabled(isToday)

                navButton(icon: "chevron.right") { navigateDay(1) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // NO background - floats on realm
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PlannerumColors.textSecondary)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        HStack(spacing: PlannerumLayout.spacingMD) {
            // Date info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PlannerumLayout.spacingSM) {
                    // Today badge
                    if isToday {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(PlannerumColors.nowMarker)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(PlannerumColors.nowMarker.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    // Full date
                    Text(PlannerumFormatters.dayFull.string(from: date).uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(PlannerumColors.textSecondary)
                        .tracking(1.5)
                }

                // Block summary
                if !viewModel.blocks.isEmpty {
                    Text("\(viewModel.blocks.count) blocks · \(viewModel.totalDuration) scheduled")
                        .font(.system(size: 11))
                        .foregroundColor(PlannerumColors.textMuted)
                }
            }

            Spacer()

            // Navigation controls
            HStack(spacing: PlannerumLayout.spacingMD) {
                // Previous day
                Button(action: { navigateDay(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(PlannerumColors.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(PlannerumColors.glassPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Today button
                Button(action: jumpToToday) {
                    Text("Today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(
                            isToday ? PlannerumColors.textMuted : PlannerumColors.primary
                        )
                }
                .buttonStyle(.plain)
                .disabled(isToday)

                // Next day
                Button(action: { navigateDay(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(PlannerumColors.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(PlannerumColors.glassPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PlannerumLayout.contentPadding)
        .padding(.vertical, PlannerumLayout.spacingMD)
        .background(
            PlannerumColors.glassSecondary.opacity(0.5)
        )
    }

    // MARK: - Hour Grid

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(Layout.startHour..<Layout.endHour, id: \.self) { hour in
                HourGridRow(
                    hour: hour,
                    isPast: isHourPast(hour),
                    isCurrentHour: isCurrentHour(hour)
                )
                .id(hour == Calendar.current.component(.hour, from: currentTime) ? Layout.scrollAnchorId : nil)
            }
        }
        .padding(.horizontal, PlannerumLayout.contentPadding)
    }

    // MARK: - Blocks Layer (with staggered entry animation per plan: 40ms between each)

    private func blocksLayer(in geometry: GeometryProxy) -> some View {
        let blockWidth = geometry.size.width
            - PlannerumLayout.contentPadding * 2
            - PlannerumLayout.timeLabelWidth
            - PlannerumLayout.spacingMD

        return ForEach(viewModel.blocks.indices, id: \.self) { index in
            let block = viewModel.blocks[index]
            let isVisible = visibleBlockIds.contains(block.id)

            TimeBlockCard(
                block: block,
                width: blockWidth,
                isHovered: hoveredBlockId == block.id,
                isSelected: selectedBlockId == block.id,
                onTap: {
                    selectedBlockId = block.id
                    onBlockSelect?(block)
                }
            )
            .position(
                x: PlannerumLayout.contentPadding
                    + PlannerumLayout.timeLabelWidth
                    + PlannerumLayout.spacingMD
                    + blockWidth / 2,
                y: yPosition(for: block.startTime) + blockHeight(for: block) / 2
            )
            // Staggered entry animation: opacity and scale
            .opacity(isVisible ? 1.0 : 0.0)
            .scaleEffect(isVisible ? 1.0 : 0.95)
            .offset(y: isVisible ? 0 : 10)
            .onHover { hovering in
                withAnimation(PlannerumSprings.hover) {
                    hoveredBlockId = hovering ? block.id : nil
                }
            }
            .onAppear {
                // Stagger block appearance: 40ms delay between each (plan spec)
                let staggerDelay = 0.04 * Double(index) + 0.3 // 0.3s base delay for timeline fade
                DispatchQueue.main.asyncAfter(deadline: .now() + staggerDelay) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        _ = visibleBlockIds.insert(block.id)
                    }
                }
            }
        }
    }

    // MARK: - Now Bar Layer

    private func nowBarLayer(in geometry: GeometryProxy) -> some View {
        let yPos = yPosition(for: currentTime)
        let barWidth = geometry.size.width
            - PlannerumLayout.contentPadding * 2
            - PlannerumLayout.timeLabelWidth

        return Group {
            // The now bar with particles
            NowBarView(
                timelineWidth: barWidth,
                yPosition: yPos,
                leftOffset: PlannerumLayout.timeLabelWidth + PlannerumLayout.spacingMD
            )
            .offset(x: PlannerumLayout.contentPadding)
        }
    }

    // MARK: - Calculations

    private func yPosition(for time: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        let adjustedHour = max(hour - Layout.startHour, 0)
        return CGFloat(adjustedHour) * PlannerumLayout.hourRowHeight
            + CGFloat(minute) / 60.0 * PlannerumLayout.hourRowHeight
    }

    private func blockHeight(for block: ScheduleBlockViewModel) -> CGFloat {
        let duration = block.endTime.timeIntervalSince(block.startTime)
        let hours = duration / 3600.0
        return max(CGFloat(hours) * PlannerumLayout.hourRowHeight, PlannerumLayout.blockMinHeight)
    }

    private func isHourPast(_ hour: Int) -> Bool {
        guard isToday else { return date < Date() }
        return hour < Calendar.current.component(.hour, from: currentTime)
    }

    private func isCurrentHour(_ hour: Int) -> Bool {
        guard isToday else { return false }
        return hour == Calendar.current.component(.hour, from: currentTime)
    }

    // MARK: - Navigation

    private func navigateDay(_ offset: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: offset, to: date) {
            onDateChange(newDate)
        }
    }

    private func jumpToToday() {
        onDateChange(Date())
        if let proxy = scrollProxy {
            scrollToCurrentTime(proxy: proxy)
        }
    }

    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.5)) {
                proxy.scrollTo(Layout.scrollAnchorId, anchor: .center)
            }
        }
    }

    private func startTimeUpdates() {
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                currentTime = Date()
            }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - HOUR GRID ROW
// ═══════════════════════════════════════════════════════════════════════════════

/// A single hour row in the timeline grid
/// Redesigned with dotted hour dividers for the Time Realm aesthetic
struct HourGridRow: View {

    let hour: Int
    let isPast: Bool
    let isCurrentHour: Bool

    private var hourLabel: String {
        String(format: "%02d", hour)
    }

    var body: some View {
        HStack(alignment: .top, spacing: PlannerumLayout.spacingMD) {
            // Time label with subtle spine
            HStack(spacing: 4) {
                Text(hourLabel)
                    .font(PlannerumTypography.hourLabel)
                    .foregroundColor(
                        isCurrentHour
                            ? PlannerumColors.nowMarker
                            : (isPast ? PlannerumColors.hourLabel.opacity(0.4) : PlannerumColors.hourLabel)
                    )
                    .frame(width: PlannerumLayout.timeLabelWidth - 8, alignment: .trailing)

                // Time spine (vertical indicator)
                Rectangle()
                    .fill(
                        isCurrentHour
                            ? PlannerumColors.nowMarker.opacity(0.4)
                            : PlannerumColors.glassBorder.opacity(isPast ? 0.3 : 0.6)
                    )
                    .frame(width: 1, height: PlannerumLayout.hourRowHeight)
            }
            .frame(width: PlannerumLayout.timeLabelWidth, alignment: .trailing)

            // Timeline zone with dotted hour divider
            VStack(spacing: 0) {
                // Dotted hour divider line
                HourDividerLine(
                    isCurrentHour: isCurrentHour,
                    isPast: isPast
                )
                .frame(height: 1)

                // Open space (droppable zone)
                Rectangle()
                    .fill(isPast ? PlannerumColors.pastTime : PlannerumColors.openTime)
                    .frame(height: PlannerumLayout.hourRowHeight - 1)
            }
        }
    }
}

// MARK: - Hour Divider Line (Dotted)

/// Dotted divider line between hours - creates rhythm without harshness
struct HourDividerLine: View {
    let isCurrentHour: Bool
    let isPast: Bool

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let dotSize: CGFloat = 2
                let spacing: CGFloat = 8
                let totalDots = Int(size.width / (dotSize + spacing))

                let color = isCurrentHour
                    ? PlannerumColors.nowMarker.opacity(0.4)
                    : (isPast ? Color.white.opacity(0.04) : Color.white.opacity(0.08))

                for i in 0..<totalDots {
                    let x = CGFloat(i) * (dotSize + spacing) + dotSize / 2
                    let rect = CGRect(
                        x: x,
                        y: (size.height - dotSize) / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(color)
                    )
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DAY TIMELINE VIEW MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// View model for the day timeline
@MainActor
public class DayTimelineViewModel: ObservableObject {

    @Published public var blocks: [ScheduleBlockViewModel] = []
    @Published public var isLoading = false
    @Published public var error: String?

    public var totalDuration: String {
        let total = blocks.reduce(0) { $0 + $1.duration }
        return PlannerumTimeUtils.formatDuration(total)
    }

    private var cancellables = Set<AnyCancellable>()

    public func loadBlocks(for date: Date) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            // Fetch all schedule blocks
            let atoms = try await AtomRepository.shared.fetchAll(type: .scheduleBlock)
                .filter { !$0.isDeleted }

            // Fetch projects for mapping
            let projects = try await AtomRepository.shared.projects()
            let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.uuid, $0.title ?? "Untitled") })

            blocks = atoms.compactMap { atom -> ScheduleBlockViewModel? in
                guard let metadata = atom.metadataValue(as: ScheduleBlockMetadata.self),
                      let startTimeStr = metadata.startTime,
                      let endTimeStr = metadata.endTime,
                      let startTime = PlannerumFormatters.iso8601.date(from: startTimeStr),
                      let endTime = PlannerumFormatters.iso8601.date(from: endTimeStr),
                      startTime >= dayStart && startTime < dayEnd
                else {
                    return nil
                }

                // Determine block type
                let blockType: TimeBlockType = {
                    switch metadata.blockType?.lowercased() {
                    case "deepwork", "deep_work": return .deepWork
                    case "creative": return .creative
                    case "output": return .output
                    case "planning": return .planning
                    case "training": return .training
                    case "rest": return .rest
                    case "admin", "administrative": return .administrative
                    case "meeting": return .meeting
                    case "review": return .review
                    default: return .deepWork
                    }
                }()

                // Determine status
                let status: BlockStatus = {
                    switch metadata.status?.lowercased() {
                    case "in_progress", "inprogress": return .inProgress
                    case "paused": return .paused
                    case "completed": return .completed
                    case "skipped": return .skipped
                    default: return .scheduled
                    }
                }()

                let projectUuid = atom.link(ofType: "project")?.uuid

                return ScheduleBlockViewModel(
                    id: atom.uuid,
                    title: atom.title ?? "Untitled Block",
                    startTime: startTime,
                    endTime: endTime,
                    blockType: blockType,
                    status: status,
                    isCompleted: metadata.isCompleted ?? false,
                    projectUuid: projectUuid,
                    projectName: projectUuid.flatMap { projectMap[$0] },
                    linkedAtomIds: atom.linksList.map { $0.uuid },
                    linkedTaskTitles: [],  // TODO: Fetch linked task titles
                    difficulty: 1.0,
                    isCoreObjective: false
                )
            }
            .sorted { $0.startTime < $1.startTime }

        } catch {
            self.error = error.localizedDescription
            print("❌ DayTimelineViewModel: Failed to load - \(error)")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DAY DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Aggregated data for a single day (used by Month view)
public struct DayData {
    public let blockCount: Int
    public let totalHours: Double
    public let completedCount: Int
    public let blockTypes: [TimeBlockType]

    public var completionRate: Double {
        guard blockCount > 0 else { return 0 }
        return Double(completedCount) / Double(blockCount)
    }

    public static let empty = DayData(
        blockCount: 0,
        totalHours: 0,
        completedCount: 0,
        blockTypes: []
    )

    public init(
        blockCount: Int,
        totalHours: Double,
        completedCount: Int,
        blockTypes: [TimeBlockType]
    ) {
        self.blockCount = blockCount
        self.totalHours = totalHours
        self.completedCount = completedCount
        self.blockTypes = blockTypes
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PREVIEW
// ═══════════════════════════════════════════════════════════════════════════════
// Note: ScheduleBlockMetadata and UncommittedItemMetadata are defined in Data/Models/Atom.swift

#if DEBUG
struct DayTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        DayTimelineView(
            date: Date(),
            onDateChange: { _ in }
        )
        .frame(width: 600, height: 800)
        .preferredColorScheme(.dark)
    }
}
#endif
