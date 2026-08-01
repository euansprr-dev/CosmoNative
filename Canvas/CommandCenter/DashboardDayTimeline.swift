// Canvas/CommandCenter/DashboardDayTimeline.swift
// The day, drawn: a real calendar column for the viewed day riding beside
// the Today ledger. Built on the SAME calendar system as the Upcoming board
// (CommandCenterCalendarLayout: hour metrics, snapping, overlap lanes, the
// accent now-marker voice) — one geometry, two surfaces. Direct manipulation
// in the block grammar: drag empty time to draw a block (15-minute grain,
// iOS planner parity), drag a one-off block to move it, pull its foot to
// resize, drop a task onto a block to nest it (the scheduleBlockUUID
// contract), drop a task onto empty time to time-box it into a fresh block.
// July 2026

import SwiftUI
import EventKit

struct DashboardDayTimeline: View {

    var viewModel: CommandCenterDashboardViewModel
    var onSelectTask: ((TaskViewModel) -> Void)? = nil

    @ObservedObject private var calendarService = CalendarSyncService.shared
    @State private var dragCreate: DragCreateGhost?
    @State private var renameBlockID: String?
    /// Minute clock for the live-block wash (plain state, never a
    /// TimelineView around scroll content — that produced phantom geometry).
    @State private var now = Date()
    @State private var scrolledFromTop = false
    @State private var moreBelowFold = true
    /// Content-space y of the viewport's bottom edge (20px-bucketed) —
    /// drives the "N later" count.
    @State private var visibleBottom: CGFloat = 0
    /// The drawn day's bounds (right-click the Schedule header to change).
    /// Both are preferences, not walls — the lane auto-extends whenever a
    /// block, an event, or the now-line needs an earlier or later hour.
    @AppStorage("schedule.dayStartHour") private var dayStartHour = 7
    @AppStorage("schedule.dayEndHour") private var dayEndHour = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // spacing 0 + 6pt canvas headroom (below): the canvas origin lands at
    // y=30 from the column top — EXACTLY the ledger's first row top (12
    // header pad + 12 label + 6 bottom pad). The page's two 40pt ladders
    // (row minHeight in DashboardTaskRow, hourHeight below) are phase-locked
    // — change either origin and re-derive the other.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CosmoSectionHeader(
                label: "Schedule",
                detail: itemCount > 0 ? "\(itemCount)" : nil
            )
            .padding(.top, DS.space12)
            .contextMenu { hourBoundsMenu }
            .help("Schedule · right-click to choose the day's hours")

            timelineScroll
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
    }

    private var itemCount: Int {
        viewModel.todayEvents.filter { !$0.isAllDay }.count + viewModel.todayScheduleBlocks.count
    }

    /// The visible lane: preference-bounded, extended by reality.
    private var metrics: DayLaneMetrics {
        let calendar = Calendar.current
        var start = min(max(dayStartHour, 0), 12)
        var end = min(max(dayEndHour, start + 4), 24)

        let timedEvents = viewModel.todayEvents.filter { !$0.isAllDay }
        let spans = timedEvents.map { ($0.startDate, $0.endDate) }
            + viewModel.todayScheduleBlocks.map { ($0.start, $0.end) }
        if let earliest = spans.map(\.0).min() {
            start = min(start, calendar.component(.hour, from: earliest))
        }
        if let latest = spans.map(\.1).max() {
            let dayStart = calendar.startOfDay(for: latest)
            let endHour = Int(ceil(latest.timeIntervalSince(dayStart) / 3600))
            end = max(end, min(endHour, 24))
        }
        if viewModel.isViewingToday {
            let nowHour = calendar.component(.hour, from: now)
            start = min(start, nowHour)
            end = max(end, min(nowHour + 1, 24))
        }
        return DayLaneMetrics(startHour: max(0, start), endHour: end)
    }

    @ViewBuilder
    private var hourBoundsMenu: some View {
        Menu("Starts at") {
            ForEach([0, 5, 6, 7, 8, 9], id: \.self) { hour in
                boundButton(hour: hour, selected: dayStartHour) { dayStartHour = hour }
            }
        }
        Menu("Ends at") {
            ForEach([18, 19, 20, 21, 22, 23, 24], id: \.self) { hour in
                boundButton(hour: hour, selected: dayEndHour) { dayEndHour = hour }
            }
        }
    }

    private func boundButton(hour: Int, selected: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected == hour {
                Label(boundLabel(hour), systemImage: "checkmark")
            } else {
                Text(boundLabel(hour))
            }
        }
    }

    private func boundLabel(_ hour: Int) -> String {
        if hour == 0 || hour == 24 { return "Midnight" }
        return String(format: "%02d:00", hour)
    }

    // MARK: - Scroll + canvas (the Upcoming board's proven structure)

    /// The bounded viewport (the iOS "5 rows + more" principle spoken in
    /// timeline): the column shows ~a workday's window of hours and ends —
    /// it never towers to the window bottom beside a short list. The rest of
    /// the day lives one scroll (or one "N later" click) away.
    private var viewportHeight: CGFloat {
        min(DayLaneMetrics.hourHeight * 8.5, metrics.height)
    }

    private var timelineScroll: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                VStack(alignment: .trailing, spacing: DS.space4) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: DS.space8) {
                            canvas(width: proxy.size.width)
                                // 6 = exactly the first hour label's −6
                                // optical offset, so it cannot clip — and the
                                // canvas origin phase-locks to the ledger's
                                // first row top (see header comment).
                                .padding(.top, DS.space6)
                            // The connect affordance lives at the day's end —
                            // a quiet footnote, never a banner above the morning.
                            accessAffordanceIfNeeded
                        }
                    }
                    .frame(height: viewportHeight)
                    .scrollIndicators(.never)
                    // Edges are events: content passing under the column's
                    // bounds fades softly, so a cut reads composed, never sliced.
                    .onScrollGeometryChange(for: DayScrollEdges.self, of: { geo in
                        DayScrollEdges(
                            scrolledFromTop: geo.contentOffset.y > 4,
                            moreBelow: geo.contentOffset.y + geo.containerSize.height < geo.contentSize.height - 4,
                            // 20px buckets: stable Equatable, no per-frame churn.
                            visibleBottomBucket: Int((geo.contentOffset.y + geo.containerSize.height) / 20)
                        )
                    }) { _, edges in
                        withAnimation(ProMotionSprings.gentle) {
                            scrolledFromTop = edges.scrolledFromTop
                            moreBelowFold = edges.moreBelow
                            visibleBottom = CGFloat(edges.visibleBottomBucket) * 20
                        }
                    }
                    .overlay(alignment: .top) {
                        edgeFade(.top)
                            .opacity(scrolledFromTop ? 1 : 0)
                    }
                    .overlay(alignment: .bottom) {
                        edgeFade(.bottom)
                            .opacity(moreBelowFold ? 1 : 0)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollProxy.scrollTo(initialScrollHourID, anchor: .top)
                        }
                    }

                    laterFooter(scrollProxy: scrollProxy)
                }
            }
        }
        .frame(height: viewportHeight + 22)
    }

    /// The iOS "tap for more" made native: what's below the fold, one click
    /// away, zero visual weight. Reserved height so its arrival never shifts
    /// the layout.
    private func laterFooter(scrollProxy: ScrollViewProxy) -> some View {
        let count = laterCount
        return Button {
            withAnimation(ProMotionSprings.gentle) {
                scrollProxy.scrollTo("day-timeline-hour-\(metrics.endHour)", anchor: .bottom)
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text("\(count) later")
                    .font(DS.caption2)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.semibold))
            }
            .foregroundStyle(DS.textMuted)
            .padding(.trailing, DS.space4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 18)
        .opacity(count > 0 ? 1 : 0)
        .allowsHitTesting(count > 0)
        .help("Scroll to the rest of the day")
        .accessibilityLabel("\(count) more schedule items later. Scrolls down.")
        .animation(ProMotionSprings.gentle, value: count)
    }

    /// Items whose card top sits below the visible fold.
    private var laterCount: Int {
        let metrics = self.metrics
        let starts = viewModel.todayEvents.filter { !$0.isAllDay }.map(\.startDate)
            + viewModel.todayScheduleBlocks.map(\.start)
        return starts.count { metrics.y(for: $0) > visibleBottom - 8 }
    }

    // Eased, not linear: most of the dissolve happens in the fade's final
    // third, so a live card stays legible longer and the fold reads composed
    // rather than mechanically ramped.
    private func edgeFade(_ edge: VerticalAlignment) -> some View {
        LinearGradient(
            stops: edge == .top
                ? [.init(color: DS.bg, location: 0), .init(color: DS.bg.opacity(0.55), location: 0.35), .init(color: DS.bg.opacity(0), location: 1)]
                : [.init(color: DS.bg.opacity(0), location: 0), .init(color: DS.bg.opacity(0.55), location: 0.65), .init(color: DS.bg, location: 1)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: edge == .top ? 16 : 28)
        .allowsHitTesting(false)
    }

    private var initialScrollHourID: String {
        if viewModel.isViewingToday {
            let hour = max(Calendar.current.component(.hour, from: Date()) - 1, metrics.startHour)
            return "day-timeline-hour-\(hour)"
        }
        return "day-timeline-hour-\(max(7, metrics.startHour))"
    }

    private func canvas(width: CGFloat) -> some View {
        let metrics = self.metrics
        return ZStack(alignment: .topLeading) {
            DayTimelineHourGrid(metrics: metrics, contentWidth: width)

            dragCreateLayer(width: width, metrics: metrics)

            cardLayer(width: width, metrics: metrics)

            if let ghost = dragCreate {
                DayTimelineCreateGhost(ghost: ghost, metrics: metrics, contentWidth: width)
            }

            if viewModel.isViewingToday {
                // zIndex must live HERE, on the ZStack child — inside the
                // marker it only ranks against itself, and the cards'
                // zIndex(1) would draw over the line.
                DayTimelineNowMarker(metrics: metrics, contentWidth: width)
                    .zIndex(10)
                    .allowsHitTesting(false)
            }

            if itemCount == 0, dragCreate == nil {
                emptyWhisper(metrics: metrics)
            }
        }
        .frame(width: width, height: metrics.height, alignment: .topLeading)
        .animation(ProMotionSprings.gentle, value: viewModel.isTaskDragInFlight)
    }

    // MARK: - Positioned cards (shared overlap lanes with the Upcoming board)

    @ViewBuilder
    private func cardLayer(width: CGFloat, metrics: DayLaneMetrics) -> some View {
        let timedEvents = viewModel.todayEvents.filter { !$0.isAllDay }
        let blocks = viewModel.todayScheduleBlocks
        let intervals = timedEvents.map { CalendarLayoutInterval(id: "event-\($0.id)", start: $0.startDate, end: $0.endDate) }
            + blocks.map { CalendarLayoutInterval(id: "block-\($0.id)", start: $0.start, end: $0.end) }
        let placements = CommandCenterCalendarLayout.overlapPlacements(for: intervals)
        let day = viewModel.selectedDate

        ForEach(timedEvents) { event in
            DayTimelineEventCard(
                event: event,
                now: now,
                geometry: cardGeometry(
                    id: "event-\(event.id)", start: event.startDate, end: event.endDate,
                    placements: placements, metrics: metrics, contentWidth: width
                )
            )
        }

        ForEach(blocks) { block in
            DayTimelineBlockCard(
                block: block,
                viewModel: viewModel,
                day: day,
                now: now,
                metrics: metrics,
                geometry: cardGeometry(
                    id: "block-\(block.id)", start: block.start, end: block.end,
                    placements: placements, metrics: metrics, contentWidth: width
                ),
                isRenaming: Binding(
                    get: { renameBlockID == block.id },
                    set: { renameBlockID = $0 ? block.id : nil }
                ),
                onSelectTask: onSelectTask
            )
        }
    }

    /// Lane-share geometry: overlapping items split the column side by side
    /// (never layered — layered titles read as garbage).
    private func cardGeometry(
        id: String, start: Date, end: Date,
        placements: [String: CalendarOverlapPlacement], metrics: DayLaneMetrics, contentWidth: CGFloat
    ) -> DayTimelineCardGeometry {
        let placement = placements[id] ?? CalendarOverlapPlacement(lane: 0, laneCount: 1)
        let gutter: CGFloat = 4
        // Flush to the rules' own terminus: cards, hour rules, and the
        // now-line all end at ONE right edge (they ended at W−8, W, and W−4).
        let usable = contentWidth - CommandCenterCalendarLayout.timeRailWidth
        let laneWidth = (usable - gutter * CGFloat(max(0, placement.laneCount - 1))) / CGFloat(placement.laneCount)
        let x = CommandCenterCalendarLayout.timeRailWidth
            + CGFloat(placement.lane) * (laneWidth + gutter)
        return DayTimelineCardGeometry(
            x: x,
            y: metrics.y(for: start),
            width: max(laneWidth, 40),
            height: metrics.height(from: start, to: end)
        )
    }

    // MARK: - Drag-create + empty-time drop (under the cards — cards win hits)

    private func dragCreateLayer(width: CGFloat, metrics: DayLaneMetrics) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.001))
            .frame(
                width: width - CommandCenterCalendarLayout.timeRailWidth,
                height: metrics.height
            )
            .offset(x: CommandCenterCalendarLayout.timeRailWidth)
            .contentShape(Rectangle())
            .gesture(dragCreateGesture(metrics: metrics))
            .dropDestination(for: String.self) { items, location in
                timeBoxDroppedTask(items.first, atY: location.y, metrics: metrics)
            }
            // The same empty-time landing for a row lifted out of the ledger.
            // Registered as the widest zone in the Spine, so the block cards
            // sitting on it win the drop where they overlap.
            .taskDropZone(id: "cc-spine-canvas") { uuid, point in
                timeBoxDroppedTask(uuid, atY: point.y, metrics: metrics)
            }
    }

    private func dragCreateGesture(metrics: DayLaneMetrics) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if dragCreate == nil { Sound.dragPickup() }
                let day = viewModel.selectedDate
                let topY = min(value.startLocation.y, value.location.y)
                let bottomY = max(value.startLocation.y, value.location.y)
                let start = metrics.snappedDate(forLaneY: topY, on: day)
                let rawEnd = metrics.snappedDate(forLaneY: bottomY, on: day)
                let floor = start.addingTimeInterval(TimeInterval(CommandCenterCalendarLayout.snapMinutes * 60))
                dragCreate = DragCreateGhost(start: start, end: max(rawEnd, floor))
            }
            .onEnded { _ in
                guard let ghost = dragCreate else { return }
                dragCreate = nil
                Sound.dragDrop()
                Task {
                    if let blockID = await viewModel.createScheduleBlock(title: "New block", start: ghost.start, end: ghost.end) {
                        // Name it while the ink is wet — the popover anchors
                        // on the fresh block.
                        renameBlockID = blockID
                    }
                }
            }
    }

    private func timeBoxDroppedTask(_ taskUUID: String?, atY y: CGFloat, metrics: DayLaneMetrics) -> Bool {
        guard let taskUUID else { return false }
        viewModel.isTaskDragInFlight = false
        let start = metrics.snappedDate(forLaneY: y, on: viewModel.selectedDate)
        let end = start.addingTimeInterval(3600)
        let title = viewModel.currentVisibleTasks.first(where: { $0.uuid == taskUUID })?.title ?? "Focus block"
        Sound.dragDrop()
        Task {
            if let blockID = await viewModel.createScheduleBlock(title: title, start: start, end: end) {
                await viewModel.setScheduleBlock(taskUUID: taskUUID, blockUUID: blockID)
            }
        }
        return true
    }

    // MARK: - Teaching states

    private func emptyWhisper(metrics: DayLaneMetrics) -> some View {
        Text("Drag to block out time")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity)
            .offset(y: max(metrics.y(for: whisperAnchor) - 30, DS.space16))
            .allowsHitTesting(false)
    }

    private var whisperAnchor: Date {
        if viewModel.isViewingToday { return Date() }
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: viewModel.selectedDate) ?? viewModel.selectedDate
    }

    @ViewBuilder
    private var accessAffordanceIfNeeded: some View {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            DayTimelineAffordanceRow(
                icon: "calendar.badge.plus",
                iconTint: DS.accent,
                text: "Show your calendar here",
                help: "Connect the system calendar"
            ) {
                Task { await calendarService.requestAccess() }
            }
        case .fullAccess:
            EmptyView()
        default:
            DayTimelineAffordanceRow(
                icon: "calendar.badge.exclamationmark",
                iconTint: DS.textMuted,
                text: "Calendar access is off — open Settings",
                help: "Open System Settings → Privacy → Calendars"
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Lane metrics (the hour window over the shared day geometry)

/// Maps dates ↔ lane pixels for a day drawn from `startHour` to `endHour`.
/// All math delegates to CommandCenterCalendarLayout at this column's own
/// scale — a side column wants the whole workday at a glance, denser than
/// the full-width board (40/hr vs 52/hr; the 15-minute grain is still 10px).
struct DayLaneMetrics: Equatable {
    let startHour: Int
    let endHour: Int

    static let hourHeight: CGFloat = 40

    var offsetY: CGFloat { CGFloat(startHour) * Self.hourHeight }

    var height: CGFloat {
        CGFloat(max(endHour - startHour, 1)) * Self.hourHeight
    }

    func y(for date: Date, calendar: Calendar = .current) -> CGFloat {
        CommandCenterCalendarLayout.yOffset(
            for: date,
            dayStart: calendar.startOfDay(for: date),
            hourHeight: Self.hourHeight
        ) - offsetY
    }

    func snappedDate(forLaneY y: CGFloat, on day: Date) -> Date {
        CommandCenterCalendarLayout.snappedDate(forY: y + offsetY, on: day, hourHeight: Self.hourHeight)
    }

    func height(from start: Date, to end: Date) -> CGFloat {
        CommandCenterCalendarLayout.blockHeight(from: start, to: end, hourHeight: Self.hourHeight)
    }
}

/// Scroll-edge truth for the fades and the "N later" count.
struct DayScrollEdges: Equatable {
    let scrolledFromTop: Bool
    let moreBelow: Bool
    let visibleBottomBucket: Int
}

// MARK: - Card geometry

struct DayTimelineCardGeometry {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

/// The in-flight drag-create ghost (snapped dates).
struct DragCreateGhost: Equatable {
    var start: Date
    var end: Date
}

// MARK: - Hour grid (intrinsic rows, the board's pattern)

private struct DayTimelineHourGrid: View {
    let metrics: DayLaneMetrics
    let contentWidth: CGFloat

    var body: some View {
        ForEach(metrics.startHour...metrics.endHour, id: \.self) { hour in
            // A grid you feel, not read (Things' spacing law applied to a
            // calendar): the ladder of full-strength hairlines beside the
            // line-free task list was the texture clash — whisper it.
            //
            // REGISTRATION: the rule is drawn at EXACTLY the hour's y (the
            // same origin the cards and now-line compute from) — the old
            // centered HStack floated the rule ~6.5pt below its own hour, so
            // every card read as starting before its label. The label is then
            // optically centered on the rule, never the reverse.
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DS.commandCenterSeparator.opacity(hour == metrics.startHour ? 0.25 : 0.5))
                    .frame(width: contentWidth - CommandCenterCalendarLayout.timeRailWidth, height: 0.5)
                    .offset(x: CommandCenterCalendarLayout.timeRailWidth)

                // The rail speaks the same clock as the cards: locale-aware
                // bare hour (never a hardcoded 24h "07:00" beside a locale
                // "7:00 – 8:00" range on the card one gutter away).
                Text(hourLabel(hour))
                    .font(DS.caption2).monospacedDigit()
                    .foregroundStyle(DS.textMuted)
                    .frame(width: CommandCenterCalendarLayout.timeRailWidth - DS.space8, alignment: .trailing)
                    .offset(y: -6)
            }
            .offset(y: CGFloat(hour - metrics.startHour) * DayLaneMetrics.hourHeight)
            .id("day-timeline-hour-\(hour)")
            .accessibilityHidden(true)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: hour % 24, minute: 0, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

// MARK: - Now marker (accent, never red — red is reserved for overdue)

private struct DayTimelineNowMarker: View {
    let metrics: DayLaneMetrics
    let contentWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let y = metrics.y(for: context.date)
            HStack(spacing: 0) {
                Circle()
                    .fill(DS.accent)
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(DS.accent.opacity(0.9))
                    .frame(width: contentWidth - CommandCenterCalendarLayout.timeRailWidth, height: 1.5)
            }
            .offset(x: CommandCenterCalendarLayout.timeRailWidth - 3, y: y - 3)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Drag-create ghost

private struct DayTimelineCreateGhost: View {
    let ghost: DragCreateGhost
    let metrics: DayLaneMetrics
    let contentWidth: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: DS.radiusXSmall, style: .continuous)
            .fill(DS.accentSoft.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusXSmall, style: .continuous)
                    .strokeBorder(DS.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .overlay(alignment: .topLeading) {
                Text("\(ghost.start.formatted(.dateTime.hour().minute())) – \(ghost.end.formatted(.dateTime.hour().minute()))")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.accent)
                    .monospacedDigit()
                    .padding(.horizontal, DS.space6)
                    .padding(.top, DS.space4)
            }
            .frame(
                width: contentWidth - CommandCenterCalendarLayout.timeRailWidth,
                height: metrics.height(from: ghost.start, to: ghost.end)
            )
            .offset(
                x: CommandCenterCalendarLayout.timeRailWidth,
                y: metrics.y(for: ghost.start)
            )
            .zIndex(4)
            .allowsHitTesting(false)
    }
}

// MARK: - Event card (the calendar's givens — read-only here)

private struct DayTimelineEventCard: View {
    let event: CalendarEvent
    let now: Date
    let geometry: DayTimelineCardGeometry

    @State private var isHovered = false

    // Tamed, never raw: EventKit hands us whatever hex the user picked in
    // macOS Calendar — unfiltered, it was the most saturated element in an
    // otherwise whisper-quiet column. Block cards keep their app-owned hex.
    private var tint: Color { DS.mutedCalendarTint(event.calendarColor) }

    private var isNow: Bool {
        (event.startDate...event.endDate).contains(now)
    }

    var body: some View {
        Button {
            let interval = event.startDate.timeIntervalSinceReferenceDate
            if let url = URL(string: "calshow:\(interval)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            DayTimelineCardBody(
                tint: tint,
                title: event.title,
                start: event.startDate,
                end: event.endDate,
                height: geometry.height,
                isHovered: isHovered,
                washOpacity: isNow ? 0.12 : nil
            )
        }
        .buttonStyle(.plain)
        .frame(width: geometry.width, height: geometry.height)
        .offset(x: geometry.x, y: geometry.y)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("\(event.calendarName) · opens Calendar")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.startDate.formatted(date: .omitted, time: .shortened)). Opens Calendar.")
    }
}

// MARK: - Block card (drop target, movable, resizable, renamable)

private struct DayTimelineBlockCard: View {
    let block: ScheduleBlockEntry
    var viewModel: CommandCenterDashboardViewModel
    let day: Date
    let now: Date
    let metrics: DayLaneMetrics
    let geometry: DayTimelineCardGeometry
    @Binding var isRenaming: Bool
    let onSelectTask: ((TaskViewModel) -> Void)?

    @State private var isHovered = false
    @State private var isSystemDropTargeted = false
    private var dragPilot: TaskDragPilot { .shared }

    /// Aimed at by either kind of drag — a system drag's `isTargeted`, or a row
    /// lifted out of the ledger by the pilot. One highlight for both.
    private var isDropTargeted: Bool {
        isSystemDropTargeted || dragPilot.hoveredZoneID == "cc-spine-block-\(block.id)"
    }

    /// Live move/resize proposal (snapped) — nil when at rest.
    @State private var proposedSpan: (start: Date, end: Date)?
    @State private var renameDraft = ""
    @FocusState private var renameFieldFocused: Bool

    private var tint: Color {
        block.colorHex.map { Color(hex: $0) } ?? DS.accent
    }

    private var span: (start: Date, end: Date) {
        proposedSpan ?? (block.start, block.end)
    }

    private var liveHeight: CGFloat {
        metrics.height(from: span.start, to: span.end)
    }

    private var liveY: CGFloat {
        metrics.y(for: span.start)
    }

    private var linkedTasks: [TaskViewModel] {
        viewModel.tasksLinked(toBlock: block.id)
    }

    private var openCount: Int {
        linkedTasks.count(where: { !$0.isCompleted })
    }

    /// The block happening right now — the ONE place color pours in.
    private var isLive: Bool {
        !block.isCompleted && (span.start...span.end).contains(now)
    }

    /// The paper→wash ladder: drop-target > live > paper. A drag in flight
    /// warms every block a breath (the invitation).
    private var washOpacity: Double? {
        if isDropTargeted { return 0.26 }
        if isLive { return 0.14 }
        return nil
    }

    var body: some View {
        DayTimelineCardBody(
            tint: tint,
            title: block.title,
            start: span.start,
            end: span.end,
            height: liveHeight,
            isHovered: isHovered || isDropTargeted,
            washOpacity: washOpacity,
            invited: viewModel.isTaskDragInFlight && !isDropTargeted,
            struck: block.isCompleted,
            showsSeal: block.isCompleted,
            detail: openCount > 0 ? "\(openCount)" : nil
        )
        .overlay(alignment: .bottom) { resizeHandle }
        .frame(width: geometry.width, height: liveHeight)
        .offset(x: geometry.x, y: liveY)
        .zIndex(proposedSpan != nil ? 5 : 1)
        .shadow(color: .black.opacity(proposedSpan != nil ? 0.14 : 0), radius: 8, y: 3)
        .gesture(moveGesture)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let taskUUID = items.first else { return false }
            viewModel.isTaskDragInFlight = false
            Sound.dragDrop()
            Task { await viewModel.setScheduleBlock(taskUUID: taskUUID, blockUUID: block.id) }
            return true
        } isTargeted: { targeted in
            withAnimation(ProMotionSprings.snappy) { isSystemDropTargeted = targeted }
        }
        // The ledger's own lift lands here too — the block is a smaller zone
        // than the Spine canvas beneath it, so it wins the overlap.
        .taskDropZone(id: "cc-spine-block-\(block.id)") { taskUUID, _ in
            Task { await viewModel.setScheduleBlock(taskUUID: taskUUID, blockUUID: block.id) }
            return true
        }
        .animation(ProMotionSprings.snappy, value: isDropTargeted)
        .contextMenu { menuItems }
        .popover(isPresented: $isRenaming, arrowEdge: .trailing) { renamePopover }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Move (one-offs only — a series' time belongs to the series)

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !block.isRecurring else { return }
                if proposedSpan == nil { Sound.dragPickup() }
                let duration = block.end.timeIntervalSince(block.start)
                let anchorY = metrics.y(for: block.start) + value.translation.height
                let newStart = metrics.snappedDate(forLaneY: anchorY, on: day)
                proposedSpan = (newStart, newStart.addingTimeInterval(duration))
            }
            .onEnded { _ in
                commitProposal()
            }
    }

    /// The bottom edge pulls to resize (its own grab zone — no fight with
    /// the move gesture on the body).
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard !block.isRecurring else { return }
                        let endY = metrics.y(for: block.end) + value.translation.height
                        var newEnd = metrics.snappedDate(forLaneY: endY, on: day)
                        let floor = block.start.addingTimeInterval(TimeInterval(CommandCenterCalendarLayout.snapMinutes * 60))
                        if newEnd < floor { newEnd = floor }
                        proposedSpan = (block.start, newEnd)
                    }
                    .onEnded { _ in
                        commitProposal()
                    }
            )
    }

    private func commitProposal() {
        guard let proposal = proposedSpan else { return }
        Sound.dragDrop()
        Task {
            await viewModel.updateScheduleBlockTimes(uuid: block.id, start: proposal.start, end: proposal.end)
            proposedSpan = nil
        }
    }

    // MARK: Menu / rename

    @ViewBuilder
    private var menuItems: some View {
        if !linkedTasks.isEmpty {
            ForEach(linkedTasks, id: \.uuid) { task in
                Button {
                    onSelectTask?(task)
                } label: {
                    Label(task.title, systemImage: task.isCompleted ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
        }
        Button {
            renameDraft = block.title
            isRenaming = true
        } label: {
            Label("Rename…", systemImage: "pencil")
        }
        Button {
            viewModel.convertScheduleBlockToTask(block)
        } label: {
            Label("Convert to Task", systemImage: "checkmark.circle")
        }
        Divider()
        Button(role: .destructive) {
            Sound.deleteTuck()
            viewModel.deleteScheduleBlock(block)
        } label: {
            Label(block.isRecurring ? "Delete Series" : "Delete Block", systemImage: "trash")
        }
    }

    private var renamePopover: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Name this block")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
            TextField("Block name", text: $renameDraft)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .frame(width: 180)
                .focused($renameFieldFocused)
                .onSubmit { commitRename() }
        }
        .padding(DS.space12)
        .onAppear {
            if renameDraft.isEmpty { renameDraft = block.title }
            renameFieldFocused = true
        }
        .onDisappear { commitRename() }
    }

    private func commitRename() {
        isRenaming = false
        let draft = renameDraft
        guard !draft.isEmpty, draft != block.title else { return }
        Task { await viewModel.renameScheduleBlock(uuid: block.id, title: draft) }
    }

    private var helpText: String {
        var parts = [block.title]
        if let recurrence = block.recurrenceText { parts.append(recurrence) }
        if openCount > 0 { parts.append("\(openCount) open task\(openCount == 1 ? "" : "s") inside") }
        parts.append(block.isRecurring ? "Drop a task here to nest it" : "Drag to move · drop a task to nest it")
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var text = "\(block.title), \(block.start.formatted(date: .omitted, time: .shortened)) to \(block.end.formatted(date: .omitted, time: .shortened))"
        if openCount > 0 { text += ", \(openCount) open tasks inside" }
        if block.isCompleted { text += ", completed" }
        return text
    }
}

// MARK: - Shared card anatomy (events and blocks read as one calendar)

/// Paper-first cards (the iOS CalendarStrip law brought to the timeline):
/// the 3pt color bar carries identity, the surface stays paper — the tinted
/// wash arrives ONLY on the live state and the drag states. Seven saturated
/// fills at once read as a candy wall; one wash reads as "you are here".
private struct DayTimelineCardBody: View {
    let tint: Color
    let title: String
    let start: Date
    let end: Date
    let height: CGFloat
    let isHovered: Bool
    /// nil = paper (the resting state); a value = that tint wash (live /
    /// drop-targeted).
    var washOpacity: Double? = nil
    /// A task drag is in flight — every block warms a breath as invitation.
    var invited = false
    var struck = false
    var showsSeal = false
    var detail: String? = nil

    private var showsMetaLine: Bool { height >= 30 }

    private var fill: Color {
        if let washOpacity { return tint.opacity(isHovered ? washOpacity + 0.04 : washOpacity) }
        if invited { return tint.opacity(0.06) }
        return isHovered ? DS.glassCardFill : DS.glassSectionFill
    }

    private var border: Color {
        if washOpacity != nil { return tint.opacity(0.38) }
        if invited { return tint.opacity(0.30) }
        return isHovered ? DS.border : DS.borderSubtle
    }

    /// A 15-minute slot is 10pt tall — its padding collapses and its title
    /// steps down a rung so the text never escapes the card's silhouette.
    private var isCompactSlot: Bool { height < 18 }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space6) {
            // A TICK, not a stripe — but one that breathes with duration: a
            // 3-hour block and a 20-minute one are visibly different marks
            // (capped at ~25% of a tall card, never Notion's full-height bar).
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint)
                .frame(width: 3, height: min(28, max(height * 0.25, 8)))
                .padding(.top, isCompactSlot ? 1 : 3)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.space4) {
                    Text(title)
                        .font(isCompactSlot ? DS.caption2.weight(.medium) : DS.rowTitleCompact)
                        .foregroundStyle(struck ? DS.textMuted : DS.text)
                        .strikethrough(struck, color: DS.textMuted)
                        .lineLimit(1)
                    if showsSeal {
                        Image(systemName: "checkmark.seal.fill")
                            .font(DS.caption2)
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                }
                if showsMetaLine {
                    metaLine
                }
            }
            .padding(.vertical, isCompactSlot ? 0 : DS.space2)
        }
        .padding(.horizontal, DS.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusXSmall, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXSmall, style: .continuous)
                .strokeBorder(border, lineWidth: 0.5)
        )
        // Overflow truncates inside the card's own silhouette — a short
        // event's title must never bleed into the row below.
        .clipShape(.rect(cornerRadius: DS.radiusXSmall))
        // The page's most document-like objects get a whisper of resting
        // elevation (Craft's law: cards are objects, not table cells).
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .contentShape(Rectangle())
    }

    // No repeat glyph here on purpose: when every block repeats, the mark
    // says nothing — recurrence lives in the tooltip and the context menu.
    // DS.rowMeta: the ONE second-line voice — the card's range spoke 10pt
    // beside the ledger's 11pt one gutter away.
    private var metaLine: some View {
        HStack(spacing: DS.space4) {
            Text("\(start.formatted(.dateTime.hour().minute())) – \(end.formatted(.dateTime.hour().minute()))")
                .font(DS.rowMeta)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let detail {
                // A glyph names what's counted — a bare "· 1" is never
                // legible cold. checkmark.circle is the app's own task mark.
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle")
                        .font(DS.microBadge)
                    Text(detail)
                        .font(DS.rowMeta)
                        .monospacedDigit()
                }
                .foregroundStyle(DS.textMuted)
            }
        }
        .lineLimit(1)
    }
}

// MARK: - Access affordance row

private struct DayTimelineAffordanceRow: View {
    let icon: String
    let iconTint: Color
    let text: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space8) {
                Image(systemName: icon)
                    .font(DS.caption)
                    .foregroundStyle(iconTint)
                    .accessibilityHidden(true)
                Text(text)
                    .font(DS.caption)
                    .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space8)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                    .fill(isHovered ? DS.glassCardFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(help)
    }
}
