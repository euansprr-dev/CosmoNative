// CosmoOS/UI/Plannerum/DayTimelineView.swift
// Plannerium Day Timeline - Vertical time ribbon with flowing hours
// WP3: Enhanced with drag interactions, calendar sync, Plan Your Day

import SwiftUI
import Combine

// MARK: - DAY TIMELINE VIEW

/// The Day view in Plannerium - a vertical time ribbon showing scheduled blocks.
///
/// WP3 Enhancements:
/// - Drag-to-create: Drag on empty timeline to create a new time block
/// - Drag-to-move: Drag existing blocks to reschedule
/// - Drag-to-resize: Drag bottom edge of blocks to change duration
/// - External calendar events displayed as semi-transparent overlays
/// - Plan Your Day prompt when no blocks exist for the day
public struct DayTimelineView: View {

    // MARK: - Properties

    let date: Date
    let onDateChange: (Date) -> Void
    let onBlockSelect: ((ScheduleBlockViewModel) -> Void)?

    // MARK: - State

    @StateObject private var viewModel = DayTimelineViewModel()
    @StateObject private var calendarSync = CalendarSyncService.shared
    @State private var hoveredBlockId: String?
    @State private var selectedBlockId: String?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var currentTime = Date()
    @State private var timerCancellable: AnyCancellable?

    // Staggered block entry animation state (40ms between each per plan)
    @State private var visibleBlockIds: Set<String> = []

    // Drag-to-create state
    @State private var dragCreateStart: CGFloat?
    @State private var dragCreateEnd: CGFloat?
    @State private var showCreatePopover: Bool = false
    @State private var pendingCreateStart: Date?
    @State private var pendingCreateEnd: Date?

    // Drag-to-move state
    @State private var dragMoveBlockId: String?
    @State private var dragMoveOffset: CGFloat = 0

    // Drag-to-resize state
    @State private var dragResizeBlockId: String?
    @State private var dragResizeOffset: CGFloat = 0

    // Block interaction state
    @State private var showDeleteAlert: Bool = false
    @State private var pendingDeleteBlockId: String?
    @State private var pendingDeleteBlockTitle: String = ""
    @State private var showEditPopover: Bool = false
    @State private var editingBlock: ScheduleBlockViewModel?

    // MARK: - Layout

    private enum Layout {
        static let startHour: Int = 5   // 5 AM
        static let endHour: Int = 24    // Midnight
        static let scrollAnchorId = "now-anchor"
        static let snapIntervalMinutes: Int = 15  // Snap to 15-minute increments
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

    private var isDayEmpty: Bool {
        viewModel.blocks.isEmpty
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
            HStack(spacing: 0) {
                // Main timeline area
                VStack(spacing: 0) {
                    // Floating date header
                    floatingDateHeader

                    // Timeline content
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            ZStack(alignment: .topLeading) {
                                // Hour grid background
                                hourGrid

                                // External calendar events layer (semi-transparent, non-interactive)
                                externalEventsLayer(in: outerGeometry)

                                // Drag-to-create preview layer
                                dragCreatePreviewLayer(in: outerGeometry)

                                // Scheduled blocks layer
                                blocksLayer(in: outerGeometry)

                                // Now bar (only if today)
                                if isToday {
                                    nowBarLayer(in: outerGeometry)
                                }
                            }
                            .frame(minHeight: timelineHeight)
                            .padding(.bottom, 40)
                            .coordinateSpace(name: "timeline")
                            .contentShape(Rectangle())
                            .gesture(dragToCreateGesture)
                        }
                        .onAppear {
                            scrollProxy = proxy
                            if isToday {
                                scrollToCurrentTime(proxy: proxy)
                            }
                        }
                    }

                    // Plan Your Day prompt (if day is empty)
                    if isDayEmpty && !viewModel.isLoading {
                        planYourDayPrompt
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.clear)
        .onAppear {
            Task {
                await viewModel.loadBlocks(for: date)
                await calendarSync.fetchExternalEvents(for: date)
            }
            startTimeUpdates()
            calendarSync.startPeriodicRefresh()
        }
        .onDisappear {
            timerCancellable?.cancel()
            calendarSync.stopPeriodicRefresh()
        }
        .onChange(of: date) { _, newDate in
            Task {
                await viewModel.loadBlocks(for: newDate)
                await calendarSync.fetchExternalEvents(for: newDate)
            }
        }
        .popover(isPresented: $showCreatePopover) {
            if let start = pendingCreateStart, let end = pendingCreateEnd {
                TimeBlockCreationPopover(
                    startTime: start,
                    endTime: end,
                    onCreateBlock: { title, blockType, intent, linkedIdeaUUID, linkedContentUUID, linkedAtomUUID, recurrenceJSON in
                        Task {
                            await createTimeBlock(
                                title: title, start: start, end: end, blockType: blockType,
                                intent: intent, linkedIdeaUUID: linkedIdeaUUID,
                                linkedContentUUID: linkedContentUUID, linkedAtomUUID: linkedAtomUUID,
                                recurrenceJSON: recurrenceJSON
                            )
                        }
                    },
                    onCancel: {
                        showCreatePopover = false
                        clearDragCreate()
                    }
                )
            }
        }
        // FIX: Clear ghost/placeholder when popover dismisses by any means (click-outside, Escape)
        .onChange(of: showCreatePopover) {
            if !showCreatePopover {
                clearDragCreate()
                pendingCreateStart = nil
                pendingCreateEnd = nil
            }
        }
        .alert("Delete Block", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {
                pendingDeleteBlockId = nil
            }
            Button("Delete", role: .destructive) {
                if let blockId = pendingDeleteBlockId {
                    Task { await deleteBlock(blockId: blockId) }
                }
                pendingDeleteBlockId = nil
            }
        } message: {
            Text("Delete \"\(pendingDeleteBlockTitle)\"? This cannot be undone.")
        }
        .popover(isPresented: $showEditPopover) {
            if let block = editingBlock {
                TimeBlockCreationPopover(
                    startTime: block.startTime,
                    endTime: block.endTime,
                    onCreateBlock: { title, blockType, intent, linkedIdeaUUID, linkedContentUUID, linkedAtomUUID, _ in
                        Task {
                            await updateBlock(
                                blockId: block.id, title: title,
                                start: block.startTime, end: block.endTime,
                                blockType: blockType
                            )
                        }
                        showEditPopover = false
                    },
                    onCancel: { showEditPopover = false }
                )
            }
        }
    }

    // MARK: - Floating Date Header

    private var floatingDateHeader: some View {
        HStack(spacing: PlannerumLayout.spacingMD) {
            // Date info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: PlannerumLayout.spacingSM) {
                    if isToday {
                        Text("Today")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(PlannerumColors.nowMarker)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(PlannerumColors.nowMarker.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Text(PlannerumFormatters.dayFull.string(from: date))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(OnyxColors.Text.primary)
                        .tracking(0.5)
                }

                if !viewModel.blocks.isEmpty {
                    Text("\(viewModel.blocks.count) blocks · \(viewModel.totalDuration)")
                        .font(.system(size: 11))
                        .foregroundColor(PlannerumColors.textMuted)
                }
            }

            Spacer()

            // Calendar sync indicator
            if calendarSync.hasCalendarAccess {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 11))
                    .foregroundColor(PlannerumColors.textMuted)
            }

            // Navigation controls
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

    // MARK: - Hour Grid

    private func scrollAnchorId(for hour: Int) -> String? {
        hour == Calendar.current.component(.hour, from: currentTime) ? Layout.scrollAnchorId : nil
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(Layout.startHour..<Layout.endHour, id: \.self) { hour in
                HourGridRow(
                    hour: hour,
                    isPast: isHourPast(hour),
                    isCurrentHour: isCurrentHour(hour)
                )
                .id(scrollAnchorId(for: hour))
            }
        }
        .padding(.horizontal, PlannerumLayout.contentPadding)
    }

    // MARK: - External Calendar Events Layer

    @ViewBuilder
    private func externalEventsLayer(in geometry: GeometryProxy) -> some View {
        let blockWidth = geometry.size.width
            - PlannerumLayout.contentPadding * 2
            - PlannerumLayout.timeLabelWidth
            - PlannerumLayout.spacingMD

        ForEach(calendarSync.externalEvents) { event in
            ExternalEventCard(
                event: event,
                width: blockWidth,
                hasConflict: blockOverlapsExternal(event)
            )
            .position(
                x: PlannerumLayout.contentPadding
                    + PlannerumLayout.timeLabelWidth
                    + PlannerumLayout.spacingMD
                    + blockWidth / 2,
                y: yPosition(for: event.startDate) + externalEventHeight(event) / 2
            )
            .allowsHitTesting(false)
        }
    }

    private func externalEventHeight(_ event: CalendarEvent) -> CGFloat {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let hours = duration / 3600.0
        return max(CGFloat(hours) * PlannerumLayout.hourRowHeight, 24)
    }

    private func blockOverlapsExternal(_ event: CalendarEvent) -> Bool {
        viewModel.blocks.contains { block in
            block.startTime < event.endDate && block.endTime > event.startDate
        }
    }

    // MARK: - Drag-to-Create Preview Layer

    @ViewBuilder
    private func dragCreatePreviewLayer(in geometry: GeometryProxy) -> some View {
        if let start = dragCreateStart, let end = dragCreateEnd {
            let topY = min(start, end)
            let height = abs(end - start)
            let blockWidth = geometry.size.width
                - PlannerumLayout.contentPadding * 2
                - PlannerumLayout.timeLabelWidth
                - PlannerumLayout.spacingMD

            if height > 10 {
                let startTime = timeFromY(topY)
                let endTime = timeFromY(topY + height)

                DragCreatePreview(
                    startTime: startTime,
                    endTime: endTime,
                    width: blockWidth,
                    height: height
                )
                .position(
                    x: PlannerumLayout.contentPadding
                        + PlannerumLayout.timeLabelWidth
                        + PlannerumLayout.spacingMD
                        + blockWidth / 2,
                    y: topY + height / 2
                )
            }
        }
    }

    // MARK: - Blocks Layer

    @ViewBuilder
    private func blocksLayer(in geometry: GeometryProxy) -> some View {
        let blockWidth = geometry.size.width
            - PlannerumLayout.contentPadding * 2
            - PlannerumLayout.timeLabelWidth
            - PlannerumLayout.spacingMD

        ForEach(Array(viewModel.blocks.enumerated()), id: \.element.id) { index, block in
            blockView(block: block, index: index, blockWidth: blockWidth)
        }
    }

    @ViewBuilder
    private func blockView(block: ScheduleBlockViewModel, index: Int, blockWidth: CGFloat) -> some View {
        let isVisible = visibleBlockIds.contains(block.id)
        let isDragging = dragMoveBlockId == block.id
        let isResizing = dragResizeBlockId == block.id

        let effectiveHeight = isResizing
            ? blockHeight(for: block) + dragResizeOffset
            : blockHeight(for: block)

        let effectiveY = isDragging
            ? yPosition(for: block.startTime) + effectiveHeight / 2 + dragMoveOffset
            : yPosition(for: block.startTime) + effectiveHeight / 2

        blockContent(block: block, blockWidth: blockWidth)
            .frame(height: max(effectiveHeight, PlannerumLayout.blockMinHeight))
            .position(
                x: PlannerumLayout.contentPadding
                    + PlannerumLayout.timeLabelWidth
                    + PlannerumLayout.spacingMD
                    + blockWidth / 2,
                y: effectiveY
            )
            .opacity(isVisible ? (isDragging ? 0.8 : 1.0) : 0.0)
            .scaleEffect(isVisible ? (isDragging ? 1.03 : 1.0) : 0.95)
            .offset(y: isVisible ? 0 : 10)
            .shadow(
                color: isDragging ? PlannerumColors.primary.opacity(0.3) : .clear,
                radius: isDragging ? 12 : 0
            )
            .zIndex(isDragging ? 100 : 0)
            .gesture(dragMoveGesture(for: block))
            .onHover { hovering in
                withAnimation(PlannerumSprings.hover) {
                    hoveredBlockId = hovering ? block.id : nil
                }
            }
            .contextMenu {
                blockContextMenuItems(block: block)
            }
            .onAppear {
                let staggerDelay = 0.04 * Double(index) + 0.3
                DispatchQueue.main.asyncAfter(deadline: .now() + staggerDelay) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        _ = visibleBlockIds.insert(block.id)
                    }
                }
            }
    }

    // MARK: - Block Context Menu

    @ViewBuilder
    private func blockContextMenuItems(block: ScheduleBlockViewModel) -> some View {
        if !block.isCompleted {
            Button {
                Task { await completeBlock(block: block) }
            } label: {
                Label("Complete Block", systemImage: "checkmark.circle.fill")
            }

            Divider()
        }

        Button {
            editingBlock = block
            showEditPopover = true
        } label: {
            Label("Edit Block", systemImage: "pencil")
        }

        Button {
            Task { await duplicateBlock(block: block) }
        } label: {
            Label("Duplicate Block", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            pendingDeleteBlockId = block.id
            pendingDeleteBlockTitle = block.title
            // Show confirmation if block has linked atoms
            if !block.linkedAtomIds.isEmpty {
                showDeleteAlert = true
            } else {
                Task { await deleteBlock(blockId: block.id) }
            }
        } label: {
            Label("Delete Block", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func blockContent(block: ScheduleBlockViewModel, blockWidth: CGFloat) -> some View {
        let hasConflict = calendarSync.hasConflict(start: block.startTime, end: block.endTime)
        let isBlockHovered = hoveredBlockId == block.id

        ZStack(alignment: .bottom) {
            TimeBlockCard(
                block: block,
                width: blockWidth,
                isHovered: isBlockHovered,
                isSelected: selectedBlockId == block.id,
                onTap: {
                    selectedBlockId = block.id
                    onBlockSelect?(block)
                }
            )
            .overlay(
                Group {
                    if hasConflict {
                        RoundedRectangle(cornerRadius: PlannerumLayout.blockCornerRadius)
                            .strokeBorder(Color.yellow.opacity(0.6), lineWidth: 2)
                    }
                }
            )
            .overlay(alignment: .topTrailing) {
                // Complete button: shown on hover for non-completed, non-active-session blocks
                if !block.isCompleted && block.status != .inProgress {
                    completeButton(for: block, isHovered: isBlockHovered)
                }
            }

            resizeHandle(for: block)
        }
    }

    // MARK: - Complete Button

    @ViewBuilder
    private func completeButton(for block: ScheduleBlockViewModel, isHovered: Bool) -> some View {
        Button(action: {
            Task { await completeBlock(block: block) }
        }) {
            completeButtonLabel(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .padding(8)
    }

    @ViewBuilder
    private func completeButtonLabel(isHovered: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isHovered ? PlannerumColors.nowMarker.opacity(0.15) : Color.white.opacity(0.06))
                .frame(width: 26, height: 26)

            Circle()
                .strokeBorder(
                    isHovered ? PlannerumColors.nowMarker.opacity(0.6) : Color.white.opacity(0.15),
                    lineWidth: 1.5
                )
                .frame(width: 26, height: 26)

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? PlannerumColors.nowMarker : PlannerumColors.textMuted)
        }
        .opacity(isHovered ? 1.0 : 0.0)
        .animation(PlannerumSprings.hover, value: isHovered)
    }

    // MARK: - Resize Handle

    private func resizeHandle(for block: ScheduleBlockViewModel) -> some View {
        ZStack {
            // Hit target area
            Rectangle()
                .fill(Color.clear)
                .frame(height: 8)
                .contentShape(Rectangle())

            // Visual indicator: thin line with 3 dots
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(hoveredBlockId == block.id ? 0.4 : 0.2))
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(height: 4)
                .padding(.bottom, 2)
            }
            .frame(height: 8)
            .allowsHitTesting(false)
        }
        .cursor(.resizeUpDown)
        .highPriorityGesture(dragResizeGesture(for: block))
    }

    // MARK: - Now Bar Layer

    private func nowBarLayer(in geometry: GeometryProxy) -> some View {
        let yPos = yPosition(for: currentTime)
        let barWidth = geometry.size.width
            - PlannerumLayout.contentPadding * 2
            - PlannerumLayout.timeLabelWidth

        return Group {
            NowBarView(
                timelineWidth: barWidth,
                yPosition: yPos,
                leftOffset: PlannerumLayout.timeLabelWidth + PlannerumLayout.spacingMD
            )
            .offset(x: PlannerumLayout.contentPadding)
        }
    }

    // MARK: - Plan Your Day Prompt

    private var planYourDayPrompt: some View {
        VStack(spacing: PlannerumLayout.spacingLG) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(PlannerumColors.primary.opacity(0.6))

            VStack(spacing: 4) {
                Text("Plan Your Day")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PlannerumColors.textPrimary)

                Text("Drag on the timeline to create a block, or use Cmd+K to quick-add tasks.")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if calendarSync.externalEvents.count > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text("\(calendarSync.externalEvents.count) external events loaded")
                        .font(.system(size: 11))
                }
                .foregroundColor(PlannerumColors.textTertiary)
            }
        }
        .padding(.vertical, PlannerumLayout.spacingXL)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Drag Gestures

    /// Check if a Y position falls within any existing block
    private func isYOnBlock(_ y: CGFloat) -> Bool {
        viewModel.blocks.contains { block in
            let blockTop = yPosition(for: block.startTime)
            let blockBottom = blockTop + blockHeight(for: block)
            return y >= blockTop && y <= blockBottom
        }
    }

    /// Drag on empty timeline space to create a new block
    private var dragToCreateGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("timeline"))
            .onChanged { value in
                // Only create if not dragging on an existing block
                if dragMoveBlockId == nil && dragResizeBlockId == nil {
                    // Don't start drag-to-create if the drag began on a block
                    if dragCreateStart == nil {
                        guard !isYOnBlock(value.startLocation.y) else { return }
                        dragCreateStart = value.startLocation.y
                    }
                    dragCreateEnd = value.location.y
                }
            }
            .onEnded { value in
                guard dragMoveBlockId == nil && dragResizeBlockId == nil else { return }
                guard let start = dragCreateStart, let end = dragCreateEnd else {
                    clearDragCreate()
                    return
                }

                let topY = min(start, end)
                let bottomY = max(start, end)
                let height = bottomY - topY

                // Only trigger if dragged at least 15 minutes worth
                let minDragHeight = PlannerumLayout.hourRowHeight / 4.0
                guard height >= minDragHeight else {
                    clearDragCreate()
                    return
                }

                let rawStart = snapTime(timeFromY(topY))
                let rawEnd = snapTime(timeFromY(bottomY))

                // Snap to avoid overlapping existing CosmoOS blocks
                let (adjustedStart, adjustedEnd) = snapToAvoidOverlap(start: rawStart, end: rawEnd)
                pendingCreateStart = adjustedStart
                pendingCreateEnd = adjustedEnd
                showCreatePopover = true
            }
    }

    /// Drag an existing block to move it
    private func dragMoveGesture(for block: ScheduleBlockViewModel) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("timeline"))
            .onChanged { value in
                dragMoveBlockId = block.id
                dragMoveOffset = value.translation.height
            }
            .onEnded { value in
                guard dragMoveBlockId == block.id else { return }

                let newY = yPosition(for: block.startTime) + value.translation.height
                let rawStart = snapTime(timeFromY(newY))
                let duration = block.endTime.timeIntervalSince(block.startTime)
                let rawEnd = rawStart.addingTimeInterval(duration)

                // Snap to avoid overlapping other CosmoOS blocks
                let (newStart, newEnd) = snapToAvoidOverlap(
                    start: rawStart,
                    end: rawEnd,
                    excludingBlockId: block.id
                )

                Task {
                    await moveBlock(blockId: block.id, newStart: newStart, newEnd: newEnd)
                }

                withAnimation(PlannerumSprings.drop) {
                    dragMoveBlockId = nil
                    dragMoveOffset = 0
                }
            }
    }

    /// Drag the bottom edge to resize
    private func dragResizeGesture(for block: ScheduleBlockViewModel) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("timeline"))
            .onChanged { value in
                dragResizeBlockId = block.id
                dragResizeOffset = value.translation.height
            }
            .onEnded { value in
                guard dragResizeBlockId == block.id else { return }

                let currentHeight = blockHeight(for: block)
                let newHeight = max(currentHeight + value.translation.height, PlannerumLayout.blockMinHeight)
                let newEndY = yPosition(for: block.startTime) + newHeight
                let rawEnd = snapTime(timeFromY(newEndY))

                // Ensure minimum 15 minutes
                let minEnd = block.startTime.addingTimeInterval(15 * 60)
                var finalEnd = max(rawEnd, minEnd)

                // Clamp resize to not overlap the next CosmoOS block
                let nextBlock = viewModel.blocks
                    .filter { $0.id != block.id && $0.startTime >= block.startTime }
                    .sorted { $0.startTime < $1.startTime }
                    .first
                if let next = nextBlock, finalEnd > next.startTime {
                    finalEnd = next.startTime
                }

                Task {
                    await resizeBlock(blockId: block.id, newEnd: finalEnd)
                }

                withAnimation(PlannerumSprings.drop) {
                    dragResizeBlockId = nil
                    dragResizeOffset = 0
                }
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

    /// Convert a Y position back to a Date on the current day
    private func timeFromY(_ y: CGFloat) -> Date {
        let hoursFromStart = y / PlannerumLayout.hourRowHeight
        let totalMinutes = Int(hoursFromStart * 60)
        let hour = Layout.startHour + totalMinutes / 60
        let minute = totalMinutes % 60

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: min(hour, 23), minute: max(minute, 0), second: 0, of: dayStart)
            ?? dayStart
    }

    /// Snap a time to the nearest 15-minute interval
    private func snapTime(_ time: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: time)
        let snappedMinute = (minute / Layout.snapIntervalMinutes) * Layout.snapIntervalMinutes
        return calendar.date(bySetting: .minute, value: snappedMinute, of: time) ?? time
    }

    private func clearDragCreate() {
        dragCreateStart = nil
        dragCreateEnd = nil
    }

    // MARK: - Overlap Prevention

    /// Check if a proposed time range overlaps with any existing CosmoOS blocks (excluding the block being moved)
    private func hasBlockOverlap(start: Date, end: Date, excludingBlockId: String? = nil) -> Bool {
        viewModel.blocks.contains { block in
            if block.id == excludingBlockId { return false }
            return block.startTime < end && block.endTime > start
        }
    }

    /// Snap a proposed time range to avoid overlapping existing CosmoOS blocks.
    /// Returns adjusted (start, end) that doesn't overlap, or the original if no overlap.
    private func snapToAvoidOverlap(start: Date, end: Date, excludingBlockId: String? = nil) -> (Date, Date) {
        let duration = end.timeIntervalSince(start)

        // Find all blocks that overlap with the proposed range (excluding the one being moved)
        let conflicting = viewModel.blocks
            .filter { $0.id != excludingBlockId }
            .filter { $0.startTime < end && $0.endTime > start }
            .sorted { $0.startTime < $1.startTime }

        guard let firstConflict = conflicting.first else {
            return (start, end)
        }

        // Determine snap direction: which edge is closer to the conflict?
        let _ = start.timeIntervalSince(firstConflict.endTime)   // negative if start is before conflict end
        let _ = firstConflict.startTime.timeIntervalSince(end)    // negative if end is after conflict start

        // Try snapping to just before the first conflicting block
        let snappedBeforeEnd = firstConflict.startTime
        let snappedBeforeStart = snappedBeforeEnd.addingTimeInterval(-duration)

        // Try snapping to just after the last conflicting block
        let lastConflict = conflicting.last!
        let snappedAfterStart = lastConflict.endTime
        let snappedAfterEnd = snappedAfterStart.addingTimeInterval(duration)

        // Check which snap direction doesn't cause further overlap
        let beforeClear = !hasBlockOverlap(start: snappedBeforeStart, end: snappedBeforeEnd, excludingBlockId: excludingBlockId)
        let afterClear = !hasBlockOverlap(start: snappedAfterStart, end: snappedAfterEnd, excludingBlockId: excludingBlockId)

        if beforeClear && afterClear {
            // Both directions are clear — pick the closer snap
            let beforeDistance = abs(start.timeIntervalSince(snappedBeforeStart))
            let afterDistance = abs(start.timeIntervalSince(snappedAfterStart))
            if beforeDistance <= afterDistance {
                return (snapTime(snappedBeforeStart), snapTime(snappedBeforeEnd))
            } else {
                return (snapTime(snappedAfterStart), snapTime(snappedAfterEnd))
            }
        } else if beforeClear {
            return (snapTime(snappedBeforeStart), snapTime(snappedBeforeEnd))
        } else if afterClear {
            return (snapTime(snappedAfterStart), snapTime(snappedAfterEnd))
        }

        // Both directions still conflict — return original (rare edge case)
        return (start, end)
    }

    private func isHourPast(_ hour: Int) -> Bool {
        guard isToday else { return date < Date() }
        return hour < Calendar.current.component(.hour, from: currentTime)
    }

    private func isCurrentHour(_ hour: Int) -> Bool {
        guard isToday else { return false }
        return hour == Calendar.current.component(.hour, from: currentTime)
    }

    // MARK: - Data Operations

    private func createTimeBlock(
        title: String, start: Date, end: Date, blockType: TimeBlockType,
        intent: TaskIntent? = nil, linkedIdeaUUID: String? = nil,
        linkedContentUUID: String? = nil, linkedAtomUUID: String? = nil,
        recurrenceJSON: String? = nil
    ) async {
        // Build schedule block metadata
        let metadata = ScheduleBlockMetadata(
            blockType: blockType.rawValue.lowercased(),
            status: "scheduled",
            startTime: PlannerumFormatters.iso8601.string(from: start),
            endTime: PlannerumFormatters.iso8601.string(from: end),
            recurrence: recurrenceJSON
        )

        // Create a companion task atom with intent + linked UUIDs for session routing
        // Also create when recurrence is set (task serves as the recurring template)
        let hasIntent = intent != nil && intent != .general
        let hasRecurrence = recurrenceJSON != nil
        if hasIntent || hasRecurrence {
            var taskMeta = TaskMetadata()
            taskMeta.intent = intent?.rawValue
            taskMeta.linkedIdeaUUID = linkedIdeaUUID
            taskMeta.linkedContentUUID = linkedContentUUID
            taskMeta.linkedAtomUUID = linkedAtomUUID
            taskMeta.scheduledStart = PlannerumFormatters.iso8601.string(from: start)
            taskMeta.scheduledEnd = PlannerumFormatters.iso8601.string(from: end)
            taskMeta.recurrence = recurrenceJSON
            taskMeta.focusDate = ISO8601DateFormatter().string(from: start)

            if let data = try? JSONEncoder().encode(taskMeta),
               let json = String(data: data, encoding: .utf8) {
                let taskAtom = Atom.new(
                    type: .task,
                    title: title,
                    body: nil,
                    metadata: json
                )
                let _ = try? await AtomRepository.shared.create(taskAtom)
            }
        }

        var metadataString: String?
        if let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataString = json
        }

        let atom = Atom.new(
            type: .scheduleBlock,
            title: title,
            body: nil,
            metadata: metadataString
        )

        do {
            try await AtomRepository.shared.create(atom)

            // Sync to Apple Calendar
            if calendarSync.hasCalendarAccess {
                let _ = try? await calendarSync.createCosmoEvent(title: title, start: start, end: end)
            }

            await viewModel.loadBlocks(for: date)
        } catch {
            // Block creation failed
        }

        showCreatePopover = false
        clearDragCreate()
    }

    private func moveBlock(blockId: String, newStart: Date, newEnd: Date) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: blockId) else { return }

            var metadata = atom.metadataValue(as: ScheduleBlockMetadata.self) ?? ScheduleBlockMetadata()
            let oldStartStr = metadata.startTime
            metadata.startTime = PlannerumFormatters.iso8601.string(from: newStart)
            metadata.endTime = PlannerumFormatters.iso8601.string(from: newEnd)

            if let data = try? JSONEncoder().encode(metadata),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }

            try await AtomRepository.shared.update(atom)

            // Update calendar event if synced
            if calendarSync.hasCalendarAccess,
               oldStartStr != nil { // Use presence of startTime as proxy
                // Calendar sync for moved blocks
                let taskMeta = atom.metadataValue(as: TaskMetadata.self)
                if let eventId = taskMeta?.calendarEventId {
                    try? await calendarSync.updateCosmoEvent(eventId: eventId, start: newStart, end: newEnd)
                }
            }

            await viewModel.loadBlocks(for: date)
        } catch {
            // Move failed
        }
    }

    private func resizeBlock(blockId: String, newEnd: Date) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: blockId) else { return }

            var metadata = atom.metadataValue(as: ScheduleBlockMetadata.self) ?? ScheduleBlockMetadata()
            metadata.endTime = PlannerumFormatters.iso8601.string(from: newEnd)

            if let data = try? JSONEncoder().encode(metadata),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }

            try await AtomRepository.shared.update(atom)
            await viewModel.loadBlocks(for: date)
        } catch {
            // Resize failed
        }
    }

    /// Complete a block without requiring a timed session
    private func completeBlock(block: ScheduleBlockViewModel) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: block.id) else { return }

            // Update metadata to completed
            var metadata = atom.metadataValue(as: ScheduleBlockMetadata.self) ?? ScheduleBlockMetadata()
            metadata.isCompleted = true
            metadata.completedAt = ISO8601DateFormatter().string(from: Date())
            metadata.status = "completed"

            if let data = try? JSONEncoder().encode(metadata),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }

            try await AtomRepository.shared.update(atom)

            // Award base XP (10 flat, no focus score bonus)
            let baseXP = 10
            let dimension = block.blockType.dimension

            let xpMetadata: [String: Any] = [
                "xpAmount": baseXP,
                "source": "manualBlockComplete",
                "blockId": block.id,
                "dimension": dimension
            ]

            let xpMetadataString: String
            if let data = try? JSONSerialization.data(withJSONObject: xpMetadata),
               let json = String(data: data, encoding: .utf8) {
                xpMetadataString = json
            } else {
                xpMetadataString = "{}"
            }

            let xpAtom = Atom.new(
                type: .xpEvent,
                title: "+\(baseXP) XP",
                body: "Completed block: \(block.title)",
                metadata: xpMetadataString
            )

            try await AtomRepository.shared.create(xpAtom)

            // Post XP notification
            NotificationCenter.default.post(
                name: .xpAwarded,
                object: nil,
                userInfo: [
                    "amount": baseXP,
                    "source": "manualBlockComplete",
                    "dimension": dimension
                ]
            )

            // Post task completed notification for quest progress
            NotificationCenter.default.post(
                name: .taskCompleted,
                object: nil,
                userInfo: [
                    "blockId": block.id,
                    "title": block.title,
                    "blockType": block.blockType.rawValue
                ]
            )

            // Reload timeline
            await viewModel.loadBlocks(for: date)

        } catch {
            print("DayTimelineView: Failed to complete block - \(error)")
        }
    }

    private func deleteBlock(blockId: String) async {
        do {
            try await AtomRepository.shared.delete(uuid: blockId)
            await viewModel.loadBlocks(for: date)
        } catch {
            // Delete failed
        }
    }

    private func duplicateBlock(block: ScheduleBlockViewModel) async {
        let duration = block.endTime.timeIntervalSince(block.startTime)
        let durationMinutes = Int(duration / 60)
        let newStart = findNextOpenSlot(durationMinutes: durationMinutes)
        let newEnd = newStart.addingTimeInterval(duration)

        let metadata = ScheduleBlockMetadata(
            blockType: block.blockType.rawValue.lowercased(),
            status: "scheduled",
            startTime: PlannerumFormatters.iso8601.string(from: newStart),
            endTime: PlannerumFormatters.iso8601.string(from: newEnd)
        )

        var metadataString: String?
        if let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataString = json
        }

        let atom = Atom.new(
            type: .scheduleBlock,
            title: block.title,
            body: nil,
            metadata: metadataString
        )

        do {
            try await AtomRepository.shared.create(atom)
            await viewModel.loadBlocks(for: date)
        } catch {
            // Duplicate failed
        }
    }

    private func updateBlock(blockId: String, title: String, start: Date, end: Date, blockType: TimeBlockType) async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: blockId) else { return }

            atom.title = title

            var metadata = atom.metadataValue(as: ScheduleBlockMetadata.self) ?? ScheduleBlockMetadata()
            metadata.blockType = blockType.rawValue.lowercased()
            metadata.startTime = PlannerumFormatters.iso8601.string(from: start)
            metadata.endTime = PlannerumFormatters.iso8601.string(from: end)

            if let data = try? JSONEncoder().encode(metadata),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }

            try await AtomRepository.shared.update(atom)
            await viewModel.loadBlocks(for: date)
        } catch {
            // Update failed
        }
    }

    /// Find the next open time slot that doesn't overlap with existing blocks or external events
    private func findNextOpenSlot(durationMinutes: Int) -> Date {
        let calendar = Calendar.current
        var candidate: Date

        if isToday {
            // Start from now, snapped to next 15-min
            candidate = snapTime(Date().addingTimeInterval(15 * 60))
        } else {
            // Start from 9 AM on the selected date
            candidate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }

        let duration = TimeInterval(durationMinutes * 60)
        let endOfDay = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: date) ?? date

        // Simple greedy search for an open slot
        while candidate.addingTimeInterval(duration) <= endOfDay {
            let candidateEnd = candidate.addingTimeInterval(duration)
            let hasBlockConflict = viewModel.blocks.contains { block in
                block.startTime < candidateEnd && block.endTime > candidate
            }
            let hasExternalConflict = calendarSync.externalEvents.contains { event in
                event.startDate < candidateEnd && event.endDate > candidate
            }

            if !hasBlockConflict && !hasExternalConflict {
                return candidate
            }

            // Move forward by 15 minutes
            candidate = candidate.addingTimeInterval(15 * 60)
        }

        return candidate
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

// MARK: - EXTERNAL EVENT CARD

/// Semi-transparent card for Apple Calendar events displayed on the timeline
struct ExternalEventCard: View {
    let event: CalendarEvent
    let width: CGFloat
    let hasConflict: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Calendar color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PlannerumColors.textSecondary)
                    .lineLimit(1)

                Text(event.calendarName)
                    .font(.system(size: 9))
                    .foregroundColor(PlannerumColors.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(event.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(event.color.opacity(0.12), lineWidth: 1)
                )
        )
        .opacity(0.7)
    }
}

// MARK: - DRAG CREATE PREVIEW

/// Visual preview shown while dragging to create a new block
struct DragCreatePreview: View {
    let startTime: Date
    let endTime: Date
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Text("\(PlannerumFormatters.time.string(from: startTime)) - \(PlannerumFormatters.time.string(from: endTime))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(PlannerumColors.primary)

            let minutes = Int(endTime.timeIntervalSince(startTime) / 60)
            Text("\(minutes)m")
                .font(.system(size: 10))
                .foregroundColor(PlannerumColors.textMuted)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: PlannerumLayout.blockCornerRadius)
                .fill(PlannerumColors.primary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: PlannerumLayout.blockCornerRadius)
                        .strokeBorder(
                            PlannerumColors.primary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                        )
                )
        )
    }
}

// MARK: - TIME BLOCK CREATION POPOVER

/// Popover for creating a new time block or assigning an existing task.
/// Simplified: single 4x2 intent grid replaces category + intent rows.
/// Linking handled by TaskIntentPicker based on selected intent.
struct TimeBlockCreationPopover: View {
    let startTime: Date
    let endTime: Date
    let onCreateBlock: (String, TimeBlockType, TaskIntent, String?, String?, String?, String?) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var selectedIntent: TaskIntent = .general
    @State private var linkedIdeaUUID: String = ""
    @State private var linkedContentUUID: String = ""
    @State private var linkedAtomUUID: String = ""
    @State private var intentTag: String = ""

    // Recurrence state
    @State private var isRecurrenceEnabled: Bool = false
    @State private var recurrenceJSON: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingMD) {
            // Time range header
            popoverHeader

            // Title input
            TextField("Block title...", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Intent picker (4x2 grid with built-in linking)
            TaskIntentPicker(
                selectedIntent: $selectedIntent,
                linkedIdeaUUID: $linkedIdeaUUID,
                linkedAtomUUID: $linkedAtomUUID,
                linkedContentUUID: $linkedContentUUID,
                intentTag: $intentTag
            )

            // Recurrence picker
            RecurrencePickerView(
                isEnabled: $isRecurrenceEnabled,
                recurrenceJSON: $recurrenceJSON
            )

            // Dynamic create button
            dynamicCreateButton
        }
        .padding(PlannerumLayout.spacingLG)
        .frame(width: 340)
        .background(PlannerumColors.glassPrimary)
    }

    // MARK: - Header

    @ViewBuilder
    private var popoverHeader: some View {
        HStack {
            Text("New Block")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PlannerumColors.textPrimary)

            Spacer()

            Text("\(PlannerumFormatters.time.string(from: startTime)) - \(PlannerumFormatters.time.string(from: endTime))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(PlannerumColors.textMuted)

            Button(action: { onCancel() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Intent-to-BlockType Mapping

    private var blockTypeForIntent: TimeBlockType {
        switch selectedIntent {
        case .writeContent: return .creative
        case .research: return .training
        case .studySwipes: return .creative
        case .deepThink: return .deepWork
        case .review: return .review
        case .general:
            if intentTag == "plan" { return .planning }
            if intentTag == "exercise" { return .rest }
            return .deepWork
        case .custom: return .deepWork
        }
    }

    /// Dynamic label for the selected intent
    private var intentDisplayLabel: String {
        switch selectedIntent {
        case .writeContent: return "Write"
        case .research: return "Research"
        case .studySwipes: return "Swipe"
        case .deepThink: return "Think"
        case .review: return "Review"
        case .general:
            if intentTag == "plan" { return "Plan" }
            if intentTag == "exercise" { return "Exercise" }
            return "General"
        case .custom: return "Custom"
        }
    }

    private var intentDisplayColor: Color {
        switch selectedIntent {
        case .general:
            if intentTag == "plan" { return Color(red: 148/255, green: 163/255, blue: 184/255) }
            if intentTag == "exercise" { return Color(red: 16/255, green: 185/255, blue: 129/255) }
            return selectedIntent.color
        default:
            return selectedIntent.color
        }
    }

    // MARK: - Dynamic Create Button

    @ViewBuilder
    private var dynamicCreateButton: some View {
        Button(action: {
            let finalTitle = title.isEmpty ? "\(intentDisplayLabel) Block" : title
            onCreateBlock(
                finalTitle,
                blockTypeForIntent,
                selectedIntent,
                linkedIdeaUUID.isEmpty ? nil : linkedIdeaUUID,
                linkedContentUUID.isEmpty ? nil : linkedContentUUID,
                linkedAtomUUID.isEmpty ? nil : linkedAtomUUID,
                isRecurrenceEnabled ? recurrenceJSON : nil
            )
        }) {
            Text("Create \(intentDisplayLabel) Block")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(intentDisplayColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

}

// MARK: - AtomPickerItem

/// Lightweight model for atom search results in linking pickers
struct AtomPickerItem: Identifiable {
    let uuid: String
    let title: String
    let typeLabel: String
    let icon: String
    let accentColor: Color

    var id: String { uuid }
}

// MARK: - HOUR GRID ROW

/// A single hour row in the timeline grid
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
                    ? PlannerumColors.nowMarker.opacity(0.3)
                    : (isPast ? Color.white.opacity(0.02) : Color.white.opacity(0.04))

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

// MARK: - NSCursor Extension

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - DAY TIMELINE VIEW MODEL

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

                // Check for recurrence
                let hasRecurrence = metadata.recurrence != nil
                let recurrenceText: String? = {
                    guard let json = metadata.recurrence,
                          let rule = RecurrenceRule.fromJSON(json) else { return nil }
                    return rule.shortDisplayText
                }()

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
                    linkedTaskTitles: [],
                    difficulty: 1.0,
                    isCoreObjective: false,
                    isRecurring: hasRecurrence,
                    recurrenceText: recurrenceText
                )
            }
            .sorted { $0.startTime < $1.startTime }

        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - DAY DATA MODEL

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

// MARK: - PREVIEW

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
