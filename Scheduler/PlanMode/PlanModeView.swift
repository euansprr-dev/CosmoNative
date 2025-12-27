// CosmoOS/Scheduler/PlanMode/PlanModeView.swift
// Weekly visual planner grid with drag-and-drop block manipulation
//
// Design Philosophy:
// - Week at a glance with dense but readable information
// - Draggable, resizable blocks with premium spring physics
// - Current time indicator with subtle pulsing glow
// - Click-to-create for rapid block creation
// - Apple-grade scrolling and gesture handling

import SwiftUI

// MARK: - Plan Mode View

/// Visual weekly planner with time grid and draggable blocks
public struct PlanModeView: View {

    // MARK: - State

    @ObservedObject var engine: SchedulerEngine
    @State private var scrollOffset: CGFloat = 0
    @State private var targetScrollOffset: CGFloat? = nil
    @State private var hoveredTimeSlot: TimeSlot? = nil
    @State private var isCreatingBlock: Bool = false
    @State private var createStartSlot: TimeSlot? = nil
    @State private var createEndSlot: TimeSlot? = nil
    @State private var currentTimeOffset: CGFloat = 0
    @State private var animateIn: Bool = false

    // Timer for current time indicator
    let currentTimeTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // MARK: - Layout Constants

    private let startHour: Int = 0
    private let endHour: Int = 24
    private var totalHours: Int { endHour - startHour }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        // Time column (scrolls with grid)
                        VStack(spacing: 0) {
                            ForEach(startHour..<endHour, id: \.self) { hour in
                                HStack {
                                    Spacer()
                                    Text(SchedulerTimeFormat.hourLabel(hour))
                                        .font(CosmoTypography.labelSmall)
                                        .foregroundColor(CosmoColors.textTertiary)
                                        .padding(.trailing, 8)
                                }
                                .frame(width: SchedulerDimensions.timeColumnWidth, height: SchedulerDimensions.hourHeight)
                            }
                        }

                        // Grid and blocks
                        ZStack(alignment: .topLeading) {
                            // Grid lines background
                            TimeGridBackground(
                                startHour: startHour,
                                endHour: endHour,
                                dayCount: 7
                            )

                            // Day columns with blocks
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { dayIndex in
                                    DayColumnView(
                                        engine: engine,
                                        dayIndex: dayIndex,
                                        date: engine.weekDates[safe: dayIndex] ?? Date(),
                                        blocks: engine.blocksByDayOfWeek[dayIndex + 1] ?? [],
                                        hoveredTimeSlot: $hoveredTimeSlot,
                                        isCreatingBlock: $isCreatingBlock,
                                        createStartSlot: $createStartSlot,
                                        createEndSlot: $createEndSlot,
                                        geometry: geometry
                                    )
                                }
                            }

                            // Current time indicator
                            CurrentTimeIndicator(
                                weekStartDate: engine.weekStartDate,
                                hourHeight: SchedulerDimensions.hourHeight
                            )
                        }
                        .frame(height: CGFloat(totalHours) * SchedulerDimensions.hourHeight)
                    }
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: scrollGeometry.frame(in: .named("planScroll")).origin.y
                            )
                        }
                    )
                    .id("planGrid")
                }
                .coordinateSpace(name: "planScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = -value
                }
                .onAppear {
                    scrollToCurrentTime(proxy: scrollProxy, geometry: geometry)
                }
                .onChange(of: engine.selectedDate) { _, _ in
                    scrollToCurrentTime(proxy: scrollProxy, geometry: geometry)
                }
            }
            .background(SchedulerColors.background)
            .overlay(alignment: .top) {
                // Day headers (pinned top) - includes time column spacer
                HStack(spacing: 0) {
                    // Empty space for time column
                    Color.clear
                        .frame(width: SchedulerDimensions.timeColumnWidth, height: SchedulerDimensions.dayHeaderHeight)
                        .background(SchedulerColors.headerBackground)

                    // Day headers
                    WeekHeaderView(
                        weekDates: engine.weekDates,
                        selectedDate: engine.selectedDate
                    )
                    .frame(height: SchedulerDimensions.dayHeaderHeight)
                }
            }
        }
        .onReceive(currentTimeTimer) { _ in
            updateCurrentTimeOffset()
        }
        .onAppear {
            updateCurrentTimeOffset()
            withAnimation(SchedulerSprings.gentle.delay(0.15)) {
                animateIn = true
            }
        }
    }

    // MARK: - Helpers

    private func scrollToCurrentTime(proxy: ScrollViewProxy, geometry: GeometryProxy) {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let targetOffset = CGFloat(hour - 1) * SchedulerDimensions.hourHeight

        // Only scroll if current time would be off-screen
        let visibleHeight = geometry.size.height - SchedulerDimensions.dayHeaderHeight
        if targetOffset < scrollOffset || targetOffset > scrollOffset + visibleHeight - 100 {
            withAnimation(SchedulerSprings.gentle) {
                proxy.scrollTo("planGrid", anchor: .init(x: 0, y: max(0, targetOffset / (CGFloat(totalHours) * SchedulerDimensions.hourHeight))))
            }
        }
    }

    private func updateCurrentTimeOffset() {
        let now = Date()
        currentTimeOffset = SchedulerGridCalculator.yPosition(for: now)
    }
}

// MARK: - Week Header View

/// Horizontal header showing day names and dates
struct WeekHeaderView: View {
    let weekDates: [Date]
    let selectedDate: Date

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                DayHeaderCell(
                    date: date,
                    isToday: Calendar.current.isDateInToday(date),
                    isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                )
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            SchedulerColors.headerBackground
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        )
    }
}

/// Individual day header cell
private struct DayHeaderCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(weekdayString)
                .font(CosmoTypography.labelSmall)
                .foregroundColor(isToday ? CosmoColors.coral : CosmoColors.textTertiary)

            ZStack {
                if isToday {
                    Circle()
                        .fill(CosmoColors.coral)
                        .frame(width: 28, height: 28)
                }

                Text(dayString)
                    .font(CosmoTypography.titleSmall)
                    .foregroundColor(isToday ? .white : CosmoColors.textPrimary)
            }
        }
        .frame(height: SchedulerDimensions.dayHeaderHeight)
        .background(
            isSelected && !isToday ?
                CosmoColors.skyBlue.opacity(0.1) : Color.clear
        )
    }

    private var weekdayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

// MARK: - Time Grid Background

/// Grid lines for the time grid
struct TimeGridBackground: View {
    let startHour: Int
    let endHour: Int
    let dayCount: Int

    var body: some View {
        Canvas { context, size in
            let hourHeight = SchedulerDimensions.hourHeight
            let dayWidth = size.width / CGFloat(dayCount)

            // Hour lines
            for hour in startHour...endHour {
                let y = CGFloat(hour - startHour) * hourHeight
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(SchedulerColors.hourLine), lineWidth: 1)
            }

            // Half-hour lines
            for hour in startHour..<endHour {
                let y = CGFloat(hour - startHour) * hourHeight + hourHeight / 2
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(SchedulerColors.halfHourLine), lineWidth: 0.5)
            }

            // Day separators
            for day in 1..<dayCount {
                let x = CGFloat(day) * dayWidth
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(SchedulerColors.hourLine), lineWidth: 1)
            }
        }
    }
}

// MARK: - Day Column View

/// Single day column containing blocks
struct DayColumnView: View {
    @ObservedObject var engine: SchedulerEngine
    let dayIndex: Int
    let date: Date
    let blocks: [ScheduleBlock]
    @Binding var hoveredTimeSlot: TimeSlot?
    @Binding var isCreatingBlock: Bool
    @Binding var createStartSlot: TimeSlot?
    @Binding var createEndSlot: TimeSlot?
    let geometry: GeometryProxy

    @State private var isDraggingOver: Bool = false

    private let isToday: Bool

    init(
        engine: SchedulerEngine,
        dayIndex: Int,
        date: Date,
        blocks: [ScheduleBlock],
        hoveredTimeSlot: Binding<TimeSlot?>,
        isCreatingBlock: Binding<Bool>,
        createStartSlot: Binding<TimeSlot?>,
        createEndSlot: Binding<TimeSlot?>,
        geometry: GeometryProxy
    ) {
        self.engine = engine
        self.dayIndex = dayIndex
        self.date = date
        self.blocks = blocks
        self._hoveredTimeSlot = hoveredTimeSlot
        self._isCreatingBlock = isCreatingBlock
        self._createStartSlot = createStartSlot
        self._createEndSlot = createEndSlot
        self.geometry = geometry
        self.isToday = Calendar.current.isDateInToday(date)
    }

    var body: some View {
        GeometryReader { columnGeometry in
            ZStack(alignment: .topLeading) {
                // Today highlight
                if isToday {
                    Rectangle()
                        .fill(SchedulerColors.todayHighlight)
                }

                // Hover preview for creation
                if let hoverSlot = hoveredTimeSlot,
                   hoverSlot.dayIndex == dayIndex,
                   !isCreatingBlock {
                    HoverPreview(slot: hoverSlot)
                }

                // Creation preview
                if isCreatingBlock,
                   let startSlot = createStartSlot,
                   let endSlot = createEndSlot,
                   startSlot.dayIndex == dayIndex {
                    CreationPreview(
                        startSlot: startSlot,
                        endSlot: endSlot
                    )
                }

                // Blocks
                ForEach(blocks, id: \.uuid) { block in
                    PlanBlockCell(
                        block: block,
                        engine: engine,
                        columnWidth: columnGeometry.size.width,
                        dayDate: date
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value, columnGeometry: columnGeometry)
                    }
                    .onEnded { value in
                        handleDragEnded(value, columnGeometry: columnGeometry)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let slot = timeSlot(for: location, in: columnGeometry)
                    hoveredTimeSlot = slot
                case .ended:
                    hoveredTimeSlot = nil
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Gesture Handlers

    private func handleDragChanged(_ value: DragGesture.Value, columnGeometry: GeometryProxy) {
        let startSlot = timeSlot(for: value.startLocation, in: columnGeometry)
        let currentSlot = timeSlot(for: value.location, in: columnGeometry)

        if !isCreatingBlock && value.translation.height.magnitude > 5 {
            isCreatingBlock = true
            createStartSlot = startSlot
        }

        if isCreatingBlock {
            createEndSlot = currentSlot
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, columnGeometry: GeometryProxy) {
        defer {
            isCreatingBlock = false
            createStartSlot = nil
            createEndSlot = nil
        }

        // If it was just a tap (minimal movement), open editor
        if value.translation.height.magnitude < 5 && value.translation.width.magnitude < 5 {
            let slot = timeSlot(for: value.location, in: columnGeometry)
            let tapTime = timeForSlot(slot)
            let anchorInWindow = CGPoint(
                x: columnGeometry.frame(in: .global).midX,
                y: value.location.y + columnGeometry.frame(in: .global).minY
            )
            engine.openEditor(
                proposedStart: tapTime,
                proposedEnd: tapTime.addingTimeInterval(3600),
                anchorPoint: anchorInWindow
            )
            return
        }

        // Create block from drag
        guard isCreatingBlock,
              let startSlot = createStartSlot,
              let endSlot = createEndSlot else { return }

        let (earlierSlot, laterSlot) = startSlot.hour < endSlot.hour ?
            (startSlot, endSlot) : (endSlot, startSlot)

        let startTime = timeForSlot(earlierSlot)
        let endTime = timeForSlot(laterSlot)
            .addingTimeInterval(15 * 60) // Add 15 min to include the end slot

        let anchorInWindow = CGPoint(
            x: columnGeometry.frame(in: .global).midX,
            y: (value.startLocation.y + value.location.y) / 2 + columnGeometry.frame(in: .global).minY
        )

        engine.openEditor(
            proposedStart: startTime,
            proposedEnd: endTime,
            anchorPoint: anchorInWindow
        )
    }

    // MARK: - Helpers

    private func timeSlot(for location: CGPoint, in geometry: GeometryProxy) -> TimeSlot {
        let hourHeight = SchedulerDimensions.hourHeight
        let totalMinutes = (location.y / hourHeight) * 60
        let hour = Int(totalMinutes / 60)
        let quarterSlot = Int(totalMinutes.truncatingRemainder(dividingBy: 60) / 15)

        return TimeSlot(
            dayIndex: dayIndex,
            hour: max(0, min(23, hour)),
            quarterSlot: max(0, min(3, quarterSlot))
        )
    }

    private func timeForSlot(_ slot: TimeSlot) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = slot.hour
        components.minute = slot.quarterSlot * 15
        return Calendar.current.date(from: components) ?? date
    }
}

// MARK: - Time Slot

struct TimeSlot: Equatable {
    let dayIndex: Int
    let hour: Int
    let quarterSlot: Int // 0-3 (0, 15, 30, 45 minutes)

    var yPosition: CGFloat {
        let hourHeight = SchedulerDimensions.hourHeight
        return CGFloat(hour) * hourHeight + CGFloat(quarterSlot) * (hourHeight / 4)
    }
}

// MARK: - Hover Preview

private struct HoverPreview: View {
    let slot: TimeSlot

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(SchedulerColors.dragPreview)
            .frame(height: SchedulerDimensions.hourHeight / 4)
            .offset(y: slot.yPosition)
            .padding(.horizontal, SchedulerDimensions.blockHorizontalPadding)
            .transition(.opacity)
    }
}

// MARK: - Creation Preview

private struct CreationPreview: View {
    let startSlot: TimeSlot
    let endSlot: TimeSlot

    var body: some View {
        let (topSlot, bottomSlot) = startSlot.yPosition < endSlot.yPosition ?
            (startSlot, endSlot) : (endSlot, startSlot)

        let height = bottomSlot.yPosition - topSlot.yPosition + SchedulerDimensions.hourHeight / 4

        RoundedRectangle(cornerRadius: SchedulerDimensions.blockCornerRadius)
            .fill(SchedulerColors.lavender.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: SchedulerDimensions.blockCornerRadius)
                    .stroke(SchedulerColors.lavender, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            )
            .frame(height: max(SchedulerDimensions.minBlockHeight, height))
            .offset(y: topSlot.yPosition)
            .padding(.horizontal, SchedulerDimensions.blockHorizontalPadding)
            .animation(SchedulerSprings.drag, value: height)
    }
}

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
    let weekStartDate: Date
    let hourHeight: CGFloat

    @State private var isPulsing: Bool = false

    var body: some View {
        let now = Date()

        // Only show if current day is in the visible week
        guard let dayIndex = dayIndexForDate(now, weekStart: weekStartDate),
              dayIndex >= 0 && dayIndex < 7 else {
            return AnyView(EmptyView())
        }

        let yPosition = SchedulerGridCalculator.yPosition(for: now, hourHeight: hourHeight)

        return AnyView(
            GeometryReader { geometry in
                let dayWidth = geometry.size.width / 7
                let xStart = CGFloat(dayIndex) * dayWidth

                // Position the indicator at the correct Y position
                HStack(spacing: 0) {
                    // Circle at the left edge of the line
                    Circle()
                        .fill(SchedulerColors.nowIndicator)
                        .frame(width: 8, height: 8)
                        .shadow(color: SchedulerColors.nowIndicator.opacity(isPulsing ? 0.7 : 0.4), radius: isPulsing ? 6 : 3)

                    // Line extending to the right
                    Rectangle()
                        .fill(SchedulerColors.nowIndicator)
                        .frame(width: dayWidth - 4, height: 2)
                }
                .position(x: xStart + dayWidth / 2, y: yPosition)
                .onAppear {
                    withAnimation(SchedulerSprings.pulseGlow) {
                        isPulsing = true
                    }
                }
            }
        )
    }

    private func dayIndexForDate(_ date: Date, weekStart: Date) -> Int? {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: weekStart, to: date).day ?? 0
        return days >= 0 && days < 7 ? days : nil
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

#if DEBUG
struct PlanModeView_Previews: PreviewProvider {
    static var previews: some View {
        PlanModeView(engine: SchedulerEngine())
            .frame(width: 1000, height: 700)
    }
}
#endif
