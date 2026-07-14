// Canvas/CommandCenter/UpcomingBoardView.swift
// Apple Calendar-style Upcoming surface for Command Center.

import SwiftUI

enum UpcomingCalendarScope: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    static var allCases: [UpcomingCalendarScope] {
        [.week]
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

struct CalendarLayoutInterval: Identifiable, Equatable {
    let id: String
    let start: Date
    let end: Date
}

struct CalendarOverlapPlacement: Equatable {
    let lane: Int
    let laneCount: Int
}

enum CommandCenterCalendarEntrySource: Equatable {
    case task(String)
    case externalEvent(String)
    case draft
}

enum CalendarResizeEdge {
    case top
    case bottom
}

enum CalendarEntryDensity: Equatable {
    case compact
    case expanded
}

struct CalendarResizePreview: Equatable {
    let offsetY: CGFloat
    let height: CGFloat
}

struct CommandCenterCalendarEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let accent: Color
    let source: CommandCenterCalendarEntrySource
    let task: TaskViewModel?
    let event: CalendarEvent?
    var isCompletedTask: Bool = false
    var isMissedOccurrence: Bool = false

    /// A recurring series occurrence (history or live) — projected, not a freely-editable atom.
    var isRecurringOccurrence: Bool { task?.isOccurrence == true }

    /// Editable = a plain, live task atom. Recurring occurrences and completed/missed history
    /// entries are display-only on the calendar (editing them would mutate the series template).
    var isEditableTask: Bool {
        guard case .task = source else { return false }
        return !isRecurringOccurrence && !isCompletedTask && !isMissedOccurrence
    }
}

struct CalendarDragDraft: Equatable {
    let start: Date
    let end: Date
    let anchor: CGPoint
}

struct CalendarEditorDraft: Identifiable, Equatable {
    let id = UUID()
    var taskUUID: String?
    var title: String
    var body: String
    var start: Date
    var end: Date
    var anchor: CGPoint
    var isAllDay: Bool
    var isNew: Bool
}

enum CommandCenterCalendarLayout {
    static let hourHeight: CGFloat = 52
    static let timeRailWidth: CGFloat = 52
    static let allDayLaneHeight: CGFloat = 34
    static let snapMinutes = 15
    static let dayMinutes = 24 * 60

    static func visibleDates(
        anchor: Date,
        scope: UpcomingCalendarScope,
        calendar: Calendar = .current
    ) -> [Date] {
        let anchorDay = calendar.startOfDay(for: anchor)

        switch scope {
        case .day, .week:
            let weekStart = mondayStartingWeek(containing: anchorDay, calendar: calendar)
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        case .month:
            guard let monthInterval = calendar.dateInterval(of: .month, for: anchorDay) else { return [anchorDay] }
            let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
            let leadingOffset = (firstWeekday + 5) % 7
            let gridStart = calendar.date(byAdding: .day, value: -leadingOffset, to: monthInterval.start) ?? monthInterval.start
            let lastMonthDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.start
            let lastWeekday = calendar.component(.weekday, from: lastMonthDay)
            let trailingOffset = 6 - ((lastWeekday + 5) % 7)
            let gridEnd = calendar.date(byAdding: .day, value: trailingOffset, to: lastMonthDay) ?? lastMonthDay

            var dates: [Date] = []
            var cursor = gridStart
            while cursor <= gridEnd {
                dates.append(calendar.startOfDay(for: cursor))
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd.addingTimeInterval(86_400)
            }
            return dates
        }
    }

    static func mondayStartingWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    static func visibleInterval(
        anchor: Date,
        scope: UpcomingCalendarScope,
        calendar: Calendar = .current
    ) -> DateInterval {
        let dates = visibleDates(anchor: anchor, scope: scope, calendar: calendar)
        let start = dates.first ?? calendar.startOfDay(for: anchor)
        let last = dates.last ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    static func yOffset(for date: Date, dayStart: Date, hourHeight: CGFloat = hourHeight, calendar: Calendar = .current) -> CGFloat {
        let minutes = calendar.dateComponents([.minute], from: calendar.startOfDay(for: dayStart), to: date).minute ?? 0
        return CGFloat(max(0, min(dayMinutes, minutes))) / 60 * hourHeight
    }

    static func blockHeight(from start: Date, to end: Date, hourHeight: CGFloat = hourHeight) -> CGFloat {
        max(18, CGFloat(max(0, end.timeIntervalSince(start))) / 3_600 * hourHeight)
    }

    static func resizePreview(
        edge: CalendarResizeEdge,
        translationHeight: CGFloat,
        originalHeight: CGFloat
    ) -> CalendarResizePreview {
        let minimumHeight: CGFloat = 18

        switch edge {
        case .top:
            let clampedTranslation = min(translationHeight, originalHeight - minimumHeight)
            return CalendarResizePreview(
                offsetY: clampedTranslation,
                height: originalHeight - clampedTranslation
            )
        case .bottom:
            return CalendarResizePreview(
                offsetY: 0,
                height: max(minimumHeight, originalHeight + translationHeight)
            )
        }
    }

    static func snappedDate(forY y: CGFloat, on day: Date, hourHeight: CGFloat = hourHeight, calendar: Calendar = .current) -> Date {
        let rawMinutes = Int(round(Double(y / hourHeight * 60) / Double(snapMinutes))) * snapMinutes
        let clamped = max(0, min(dayMinutes, rawMinutes))
        return calendar.date(byAdding: .minute, value: clamped, to: calendar.startOfDay(for: day)) ?? day
    }

    static func snappedDate(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let minutes = calendar.dateComponents([.minute], from: day, to: date).minute ?? 0
        let snapped = Int(round(Double(minutes) / Double(snapMinutes))) * snapMinutes
        return calendar.date(byAdding: .minute, value: max(0, min(dayMinutes, snapped)), to: day) ?? date
    }

    static func isAllDay(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: start)
        let duration = end.timeIntervalSince(start)
        return abs(start.timeIntervalSince(dayStart)) < 1 && duration >= 23 * 3_600
    }

    static func entryDensity(width: CGFloat, height: CGFloat) -> CalendarEntryDensity {
        width < 72 || height < 34 ? .compact : .expanded
    }

    static func overlapPlacements(for intervals: [CalendarLayoutInterval]) -> [String: CalendarOverlapPlacement] {
        let sorted = intervals.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.id < $1.id
        }

        var result: [String: CalendarOverlapPlacement] = [:]
        var group: [CalendarLayoutInterval] = []
        var groupEnd: Date?

        func flushGroup() {
            guard !group.isEmpty else { return }
            var active: [(id: String, end: Date, lane: Int)] = []
            var lanes: [String: Int] = [:]
            var maxLane = 0

            for interval in group {
                active.removeAll { $0.end <= interval.start }
                let used = Set(active.map(\.lane))
                var lane = 0
                while used.contains(lane) { lane += 1 }
                active.append((id: interval.id, end: interval.end, lane: lane))
                lanes[interval.id] = lane
                maxLane = max(maxLane, lane)
            }

            for interval in group {
                result[interval.id] = CalendarOverlapPlacement(
                    lane: lanes[interval.id] ?? 0,
                    laneCount: maxLane + 1
                )
            }

            group.removeAll()
            groupEnd = nil
        }

        for interval in sorted {
            guard interval.end > interval.start else { continue }
            if let end = groupEnd, interval.start >= end {
                flushGroup()
            }
            group.append(interval)
            groupEnd = max(groupEnd ?? interval.end, interval.end)
        }

        flushGroup()
        return result
    }
}

struct UpcomingBoardView: View {
    var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController

    @State private var selectedEntryID: String?
    @State private var hoveredEntryID: String?
    @State private var dragDraft: CalendarDragDraft?
    @State private var editorDraft: CalendarEditorDraft?

    private static let coordinateSpaceName = "upcoming-calendar-surface"

    var body: some View {
        ZStack(alignment: .topLeading) {
            calendarContent
                .coordinateSpace(name: Self.coordinateSpaceName)

            if let editorDraft {
                CalendarEditorPopover(
                    draft: editorDraft,
                    onSave: saveEditorDraft,
                    onDelete: deleteEditorDraft,
                    onDismiss: dismissEditorDraft
                )
                .id(editorDraft.id)
                .frame(width: 360)
                .position(editorDraft.anchor)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                .zIndex(20)
            }
        }
    }

    private var calendarContent: some View {
        Group {
            switch viewModel.upcomingCalendarScope {
            case .day, .week:
                UpcomingTimelineCalendarView(
                    dates: timelineDates,
                    entries: calendarEntries,
                    dragDraft: $dragDraft,
                    selectedEntryID: $selectedEntryID,
                    hoveredEntryID: $hoveredEntryID,
                    coordinateSpaceName: Self.coordinateSpaceName,
                    onOpenEditor: openEditor,
                    onCreateDraft: openCreationEditor,
                    onMoveEntry: moveEntry,
                    onResizeEntry: resizeEntry
                )
            case .month:
                UpcomingMonthCalendarView(
                    anchorDate: viewModel.upcomingAnchorDate,
                    dates: viewModel.upcomingVisibleDates,
                    entries: calendarEntries,
                    onOpenDay: { date in
                        withAnimation(ProMotionSprings.snappy) {
                            viewModel.upcomingCalendarScope = .day
                            viewModel.setUpcomingAnchorDate(date)
                        }
                    },
                    onCreateAllDay: { date in
                        Task {
                            _ = await viewModel.createAllDayTask(title: "New Event", date: date)
                        }
                    }
                )
            }
        }
        .animation(ProMotionSprings.snappy, value: viewModel.upcomingCalendarScope)
    }

    private var timelineDates: [Date] {
        viewModel.upcomingVisibleDates
    }

    private var calendarEntries: [CommandCenterCalendarEntry] {
        var entries: [CommandCenterCalendarEntry] = []

        for task in viewModel.upcomingDayGroups.flatMap(\.tasks) {
            entries.append(entry(for: task))
        }

        var seenEventIDs = Set<String>()
        for event in viewModel.upcomingCalendarEvents.values.flatMap({ $0 }) where seenEventIDs.insert(event.id).inserted {
            entries.append(entry(for: event))
        }

        if let dragDraft {
            entries.append(
                CommandCenterCalendarEntry(
                    id: "draft",
                    title: "New Event",
                    subtitle: timeRangeText(dragDraft.start, dragDraft.end),
                    start: dragDraft.start,
                    end: dragDraft.end,
                    isAllDay: false,
                    accent: DS.accent,
                    source: .draft,
                    task: nil,
                    event: nil
                )
            )
        }

        return entries.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay && !$1.isAllDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func entry(for task: TaskViewModel) -> CommandCenterCalendarEntry {
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: task.calendarDisplayDate ?? Date())
        let start = task.calendarStart ?? date
        let isAllDay = task.scheduledStart == nil && task.scheduledTime == nil
        let end = task.calendarEnd
            ?? (!isAllDay ? start.addingTimeInterval(TimeInterval(max(15, task.estimatedMinutes) * 60)) : nil)
            ?? calendar.date(byAdding: .day, value: 1, to: date)
            ?? date.addingTimeInterval(86_400)
        let habit = viewModel.resolvedHabit(for: task)
        let intent = viewModel.resolvedIntentPresentation(for: task)
        let baseAccent = habit?.accent ?? (intent.isUnassigned ? DS.info : intent.accent)
        let isCompleted = task.isCompleted || task.occurrenceStatus == .completed
        let isMissed = task.occurrenceStatus == .missed

        return CommandCenterCalendarEntry(
            // Occurrence-unique id (task.id == "<template>#<day>" for occurrences) so repeats
            // across days never collide on a single template uuid.
            id: "task-\(task.id)",
            title: task.title,
            subtitle: isAllDay ? nil : timeRangeText(start, end),
            start: start,
            end: end,
            isAllDay: isAllDay,
            accent: isMissed ? DS.textMuted : baseAccent,
            source: .task(task.uuid),
            task: task,
            event: nil,
            isCompletedTask: isCompleted,
            isMissedOccurrence: isMissed
        )
    }

    private func entry(for event: CalendarEvent) -> CommandCenterCalendarEntry {
        CommandCenterCalendarEntry(
            id: "event-\(event.id)",
            title: event.title,
            subtitle: event.isAllDay ? event.calendarName : timeRangeText(event.startDate, event.endDate),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay || CommandCenterCalendarLayout.isAllDay(start: event.startDate, end: event.endDate),
            accent: Color(nsColor: event.calendarColor),
            source: .externalEvent(event.id),
            task: nil,
            event: event
        )
    }

    private func openCreationEditor(_ draft: CalendarDragDraft) {
        withAnimation(ProMotionSprings.snappy) {
            dragDraft = draft
            editorDraft = CalendarEditorDraft(
                title: "New Event",
                body: "",
                start: draft.start,
                end: draft.end,
                anchor: draft.anchor,
                isAllDay: false,
                isNew: true
            )
            selectedEntryID = "draft"
        }
    }

    private func openEditor(_ entry: CommandCenterCalendarEntry, frame: CGRect) {
        guard let task = entry.task, !entry.isRecurringOccurrence else { return }
        let anchor = CGPoint(
            x: min(frame.maxX + 190, frame.maxX + 210),
            y: max(160, frame.midY)
        )
        withAnimation(ProMotionSprings.snappy) {
            selectedEntryID = entry.id
            editorDraft = CalendarEditorDraft(
                taskUUID: task.uuid,
                title: task.title,
                body: task.body ?? "",
                start: entry.start,
                end: entry.end,
                anchor: anchor,
                isAllDay: entry.isAllDay,
                isNew: false
            )
        }
    }

    private func saveEditorDraft(_ draft: CalendarEditorDraft) {
        Task {
            if let taskUUID = draft.taskUUID {
                if draft.isAllDay {
                    await viewModel.updateAllDayTask(uuid: taskUUID, title: draft.title, body: draft.body, date: draft.start)
                } else {
                    await viewModel.updateCalendarTimeBlock(
                        uuid: taskUUID,
                        title: draft.title,
                        body: draft.body,
                        start: draft.start,
                        end: draft.end
                    )
                }
                selectedEntryID = "task-\(taskUUID)"
            } else if draft.isAllDay {
                if let task = await viewModel.createAllDayTask(title: draft.title, date: draft.start, body: draft.body) {
                    selectedEntryID = "task-\(task.uuid)"
                }
            } else if let task = await viewModel.createCalendarTimeBlock(title: draft.title, start: draft.start, end: draft.end, body: draft.body) {
                selectedEntryID = "task-\(task.uuid)"
            }

            dismissEditorDraft()
        }
    }

    private func deleteEditorDraft(_ draft: CalendarEditorDraft) {
        Task {
            if let taskUUID = draft.taskUUID {
                await viewModel.deleteTask(uuid: taskUUID)
            }
            dismissEditorDraft()
        }
    }

    private func dismissEditorDraft() {
        withAnimation(ProMotionSprings.snappy) {
            editorDraft = nil
            dragDraft = nil
            if selectedEntryID == "draft" {
                selectedEntryID = nil
            }
        }
    }

    private func moveEntry(_ entry: CommandCenterCalendarEntry, dayDelta: Int, minuteDelta: Int) {
        guard case let .task(uuid) = entry.source, !entry.isAllDay, !entry.isRecurringOccurrence else { return }
        let calendar = Calendar.current
        let movedStart = calendar.date(byAdding: .day, value: dayDelta, to: entry.start) ?? entry.start
        let movedEnd = calendar.date(byAdding: .day, value: dayDelta, to: entry.end) ?? entry.end
        let newStart = calendar.date(byAdding: .minute, value: minuteDelta, to: movedStart) ?? movedStart
        let newEnd = calendar.date(byAdding: .minute, value: minuteDelta, to: movedEnd) ?? movedEnd

        Task {
            await viewModel.updateCalendarTimeBlock(uuid: uuid, start: newStart, end: newEnd)
        }
    }

    private func resizeEntry(_ entry: CommandCenterCalendarEntry, edge: CalendarResizeEdge, minuteDelta: Int) {
        guard case let .task(uuid) = entry.source, !entry.isAllDay, !entry.isRecurringOccurrence else { return }
        let calendar = Calendar.current
        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: entry.start) ?? entry.end
        let minimumStart = calendar.date(byAdding: .minute, value: -15, to: entry.end) ?? entry.start
        let newStart: Date
        let newEnd: Date

        switch edge {
        case .top:
            newStart = min(calendar.date(byAdding: .minute, value: minuteDelta, to: entry.start) ?? entry.start, minimumStart)
            newEnd = entry.end
        case .bottom:
            newStart = entry.start
            newEnd = max(calendar.date(byAdding: .minute, value: minuteDelta, to: entry.end) ?? entry.end, minimumEnd)
        }

        Task {
            await viewModel.updateCalendarTimeBlock(uuid: uuid, start: newStart, end: newEnd)
        }
    }

    private func timeRangeText(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}

private struct UpcomingTimelineCalendarView: View {
    let dates: [Date]
    let entries: [CommandCenterCalendarEntry]
    @Binding var dragDraft: CalendarDragDraft?
    @Binding var selectedEntryID: String?
    @Binding var hoveredEntryID: String?
    let coordinateSpaceName: String
    let onOpenEditor: (CommandCenterCalendarEntry, CGRect) -> Void
    let onCreateDraft: (CalendarDragDraft) -> Void
    let onMoveEntry: (CommandCenterCalendarEntry, Int, Int) -> Void
    let onResizeEntry: (CommandCenterCalendarEntry, CalendarResizeEdge, Int) -> Void

    private let timelineHeight = CGFloat(CommandCenterCalendarLayout.dayMinutes) / 60 * CommandCenterCalendarLayout.hourHeight

    var body: some View {
        GeometryReader { proxy in
            let dayWidth = resolvedDayWidth(totalWidth: proxy.size.width)
            let contentWidth = proxy.size.width

            ScrollViewReader { scrollProxy in
                VStack(spacing: 0) {
                    headerRows(dayWidth: dayWidth, contentWidth: contentWidth)

                    ScrollView(.vertical, showsIndicators: false) {
                        timelineCanvas(dayWidth: dayWidth, contentWidth: contentWidth)
                            .frame(width: contentWidth, alignment: .leading)
                    }
                    .scrollIndicators(.never)
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollProxy.scrollTo(initialScrollHourID, anchor: .top)
                        }
                    }
                }
                .background(Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DS.borderSubtle.opacity(0.55))
                        .frame(height: 0.5)
                }
            }
        }
        .frame(minHeight: 620)
    }

    private func headerRows(dayWidth: CGFloat, contentWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: CommandCenterCalendarLayout.timeRailWidth, height: 42)

                ForEach(dates, id: \.self) { date in
                    CalendarDayHeaderCell(date: date)
                        .frame(width: dayWidth, height: 42)
                }
            }

            HStack(spacing: 0) {
                Text("all-day")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: CommandCenterCalendarLayout.timeRailWidth, height: CommandCenterCalendarLayout.allDayLaneHeight, alignment: .trailing)
                    .padding(.trailing, DS.space8)

                ForEach(dates, id: \.self) { date in
                    AllDayLaneCell(
                        date: date,
                        entries: allDayEntries(for: date),
                        onOpenEditor: onOpenEditor
                    )
                    .frame(width: dayWidth, height: CommandCenterCalendarLayout.allDayLaneHeight)
                }
            }
            .background(Color.clear)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(width: contentWidth, alignment: .leading)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private func timelineCanvas(dayWidth: CGFloat, contentWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            hourGrid(dayWidth: dayWidth, contentWidth: contentWidth)
            draftGestureLayer(dayWidth: dayWidth)
            timedEntryLayer(dayWidth: dayWidth)

            if containsToday {
                nowMarker(dayWidth: dayWidth)
            }
        }
        .frame(width: contentWidth, height: timelineHeight, alignment: .topLeading)
    }

    private func hourGrid(dayWidth: CGFloat, contentWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...24, id: \.self) { hour in
                HStack(spacing: 0) {
                    Text(hourLabel(hour))
                        .font(DS.caption2.weight(.medium)).monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                        .frame(width: CommandCenterCalendarLayout.timeRailWidth - DS.space8, alignment: .trailing)
                        .padding(.trailing, DS.space8)

                    Rectangle()
                        .fill(hour == 0 ? DS.borderSubtle.opacity(0.4) : DS.borderSubtle)
                        .frame(width: contentWidth - CommandCenterCalendarLayout.timeRailWidth, height: 0.5)
                }
                .offset(y: CGFloat(hour) * CommandCenterCalendarLayout.hourHeight)
                .id("calendar-hour-\(hour)")
            }

            ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                Rectangle()
                    .fill(Calendar.current.isDateInToday(date) ? DS.accent.opacity(0.022) : Color.clear)
                    .frame(width: dayWidth, height: timelineHeight)
                    .offset(x: CommandCenterCalendarLayout.timeRailWidth + CGFloat(index) * dayWidth)

                Rectangle()
                    .fill(DS.borderSubtle.opacity(0.78))
                    .frame(width: 0.5, height: timelineHeight)
                    .offset(x: CommandCenterCalendarLayout.timeRailWidth + CGFloat(index) * dayWidth)
            }
        }
    }

    private func draftGestureLayer(dayWidth: CGFloat) -> some View {
        ForEach(Array(dates.enumerated()), id: \.element) { index, date in
            GeometryReader { columnProxy in
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .local)
                            .onChanged { value in
                                dragDraft = draft(from: value, on: date, frame: columnProxy.frame(in: .named(coordinateSpaceName)))
                            }
                            .onEnded { value in
                                onCreateDraft(draft(from: value, on: date, frame: columnProxy.frame(in: .named(coordinateSpaceName))))
                            }
                    )
            }
            .frame(width: dayWidth, height: timelineHeight)
            .offset(x: CommandCenterCalendarLayout.timeRailWidth + CGFloat(index) * dayWidth)
        }
    }

    private func timedEntryLayer(dayWidth: CGFloat) -> some View {
        ForEach(Array(dates.enumerated()), id: \.element) { index, date in
            let dayEntries = timedEntries(for: date)
            let placements = CommandCenterCalendarLayout.overlapPlacements(
                for: dayEntries.map { CalendarLayoutInterval(id: $0.id, start: $0.start, end: $0.end) }
            )

            ForEach(dayEntries) { entry in
                let placement = placements[entry.id] ?? CalendarOverlapPlacement(lane: 0, laneCount: 1)
                let gutter: CGFloat = 4
                let usableWidth = dayWidth - DS.space8
                let laneWidth = (usableWidth - gutter * CGFloat(max(0, placement.laneCount - 1))) / CGFloat(placement.laneCount)
                let x = CommandCenterCalendarLayout.timeRailWidth
                    + CGFloat(index) * dayWidth
                    + DS.space4
                    + CGFloat(placement.lane) * (laneWidth + gutter)
                let y = CommandCenterCalendarLayout.yOffset(for: entry.start, dayStart: date)
                let height = CommandCenterCalendarLayout.blockHeight(from: entry.start, to: entry.end)

                CalendarEntryPositionReader(
                    entry: entry,
                    isSelected: selectedEntryID == entry.id,
                    isHovered: hoveredEntryID == entry.id,
                    frameWidth: laneWidth,
                    frameHeight: height,
                    coordinateSpaceName: coordinateSpaceName,
                    onOpenEditor: onOpenEditor,
                    onHover: { hovering in hoveredEntryID = hovering ? entry.id : nil },
                    onMove: { translation in
                        let dayDelta = Int((translation.width / dayWidth).rounded())
                        let minuteDelta = snappedMinuteDelta(from: translation.height)
                        onMoveEntry(entry, dayDelta, minuteDelta)
                    },
                    onResize: { edge, translation in
                        onResizeEntry(entry, edge, snappedMinuteDelta(from: translation.height))
                    }
                )
                .offset(x: x, y: y)
            }
        }
    }

    private func nowMarker(dayWidth: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let todayIndex = dates.firstIndex(where: { Calendar.current.isDateInToday($0) }) {
                let today = Calendar.current.startOfDay(for: context.date)
                let y = CommandCenterCalendarLayout.yOffset(for: context.date, dayStart: today)
                // Accent, not red — red is reserved for overdue. The now line
                // is the same voice as the iPhone planner's.
                HStack(spacing: 0) {
                    Text(nowLabel(context.date))
                        .font(DS.caption2).fontWeight(.bold).monospacedDigit()
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, DS.space4)
                        .frame(height: 18)
                        .background(DS.accent, in: Capsule())

                    Circle()
                        .fill(DS.accent)
                        .frame(width: 7, height: 7)

                    Rectangle()
                        .fill(DS.accent.opacity(0.9))
                        .frame(width: dayWidth - DS.space8, height: 1.5)
                }
                .offset(
                    x: CommandCenterCalendarLayout.timeRailWidth - 38 + CGFloat(todayIndex) * dayWidth,
                    y: y - 9
                )
            }
        }
    }

    private func draft(from value: DragGesture.Value, on date: Date, frame: CGRect) -> CalendarDragDraft {
        let topY = min(value.startLocation.y, value.location.y)
        let bottomY = max(value.startLocation.y, value.location.y)
        let start = CommandCenterCalendarLayout.snappedDate(forY: topY, on: date)
        let rawEnd = CommandCenterCalendarLayout.snappedDate(forY: bottomY, on: date)
        let end = max(rawEnd, Calendar.current.date(byAdding: .minute, value: 15, to: start) ?? start.addingTimeInterval(900))
        let anchor = CGPoint(x: frame.maxX + 190, y: max(150, frame.minY + topY + 100))
        return CalendarDragDraft(start: start, end: end, anchor: anchor)
    }

    private func timedEntries(for date: Date) -> [CommandCenterCalendarEntry] {
        entriesForDay(date).filter { !$0.isAllDay }
    }

    private func allDayEntries(for date: Date) -> [CommandCenterCalendarEntry] {
        entriesForDay(date).filter(\.isAllDay)
    }

    private func entriesForDay(_ date: Date) -> [CommandCenterCalendarEntry] {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return entries.filter { $0.start < dayEnd && $0.end > dayStart }
    }

    private var containsToday: Bool {
        dates.contains { Calendar.current.isDateInToday($0) }
    }

    private var initialScrollHourID: String {
        if containsToday {
            let hour = max(Calendar.current.component(.hour, from: Date()) - 2, 0)
            return "calendar-hour-\(hour)"
        }
        return "calendar-hour-8"
    }

    private func resolvedDayWidth(totalWidth: CGFloat) -> CGFloat {
        let available = max(0, totalWidth - CommandCenterCalendarLayout.timeRailWidth)
        let ideal = available / CGFloat(max(dates.count, 1))
        return max(ideal, 1)
    }

    private func snappedMinuteDelta(from height: CGFloat) -> Int {
        Int(round(Double(height / CommandCenterCalendarLayout.hourHeight * 60) / Double(CommandCenterCalendarLayout.snapMinutes))) * CommandCenterCalendarLayout.snapMinutes
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func nowLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct CalendarDayHeaderCell: View {
    let date: Date

    @State private var isHovered = false
    @State private var showsLedger = false

    var body: some View {
        VStack(spacing: DS.space2) {
            // The iPhone week-strip voice: quiet weekday above the numeral.
            Text(weekdayText)
                .font(DS.caption2).fontWeight(.medium)
                .foregroundStyle(isToday ? DS.accent : DS.textMuted)

            Text(dayText)
                .font(DS.headline)
                .foregroundStyle(isToday ? DS.textOnAccent : DS.text)
                .frame(width: 28, height: 24)
                .background(isToday ? DS.accent : Color.clear, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isToday ? DS.glassBorderFocused.opacity(0.52) : Color.clear, lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { ledgerAffordance }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .popover(isPresented: $showsLedger, arrowEdge: .bottom) {
            ContentDayLedgerPanel(day: date)
        }
        .accessibilityElement(children: .combine)
    }

    /// Past days answer for themselves: hover reveals the ledger — what
    /// shipped that day, and the one-click path to log its numbers.
    @ViewBuilder
    private var ledgerAffordance: some View {
        if isPast && (isHovered || showsLedger) {
            Button {
                showsLedger = true
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(DS.caption2).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(DS.glassCardFill, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, DS.space4)
            .help("Log how this day's content performed")
            .accessibilityLabel("Log content performance for \(date.formatted(.dateTime.month().day()))")
            .transition(.opacity)
        }
    }

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var dayText: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var isPast: Bool {
        date < Calendar.current.startOfDay(for: Date())
    }
}

private struct AllDayLaneCell: View {
    let date: Date
    let entries: [CommandCenterCalendarEntry]
    let onOpenEditor: (CommandCenterCalendarEntry, CGRect) -> Void

    var body: some View {
        HStack(spacing: DS.space4) {
            ForEach(entries.prefix(2)) { entry in
                GeometryReader { proxy in
                    Button {
                        onOpenEditor(entry, proxy.frame(in: .named("upcoming-calendar-surface")))
                    } label: {
                        HStack(spacing: DS.space4) {
                            Circle()
                                .fill(entry.accent)
                                .frame(width: 5, height: 5)
                            Text(entry.title)
                                .font(DS.caption2).fontWeight(.semibold)
                                .strikethrough(entry.isCompletedTask, color: DS.textMuted)
                                .lineLimit(1)
                        }
                        .foregroundStyle(entry.isCompletedTask || entry.isMissedOccurrence ? DS.textMuted : (entry.isEditableTask ? entry.accent : DS.textSecondary))
                        .opacity(entry.isCompletedTask ? 0.7 : (entry.isMissedOccurrence ? 0.6 : 1))
                        .padding(.horizontal, DS.space6)
                        .frame(height: 20)
                        .background(DS.glassCardFill, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(entry.accent.opacity(0.22), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!entry.isEditableTask)
                }
                .frame(height: 22)
            }

            if entries.count > 2 {
                Text("+\(entries.count - 2)")
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space4)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(width: 0.5)
        }
    }
}

private struct CalendarEntryPositionReader: View {
    let entry: CommandCenterCalendarEntry
    let isSelected: Bool
    let isHovered: Bool
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let coordinateSpaceName: String
    let onOpenEditor: (CommandCenterCalendarEntry, CGRect) -> Void
    let onHover: (Bool) -> Void
    let onMove: (CGSize) -> Void
    let onResize: (CalendarResizeEdge, CGSize) -> Void

    @State private var resizeEdge: CalendarResizeEdge?
    @State private var resizeTranslation: CGSize = .zero
    @State private var moveTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            CalendarEntryBlock(
                entry: entry,
                isSelected: isSelected,
                isHovered: isHovered,
                density: CommandCenterCalendarLayout.entryDensity(width: frameWidth, height: preview.height)
            )
                .frame(width: frameWidth, height: preview.height)
                .offset(x: moveTranslation.width, y: preview.offsetY + moveTranslation.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenEditor(entry, proxy.frame(in: .named(coordinateSpaceName)))
                }
                .onHover(perform: onHover)
                .gesture(moveGesture)
                .overlay(alignment: .top) {
                    CalendarResizeHandle(isActive: resizeEdge == .top, isVisible: showsResizeHandles)
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    resizeEdge = .top
                                    resizeTranslation = value.translation
                                }
                                .onEnded { value in
                                    onResize(.top, value.translation)
                                    resizeEdge = nil
                                    resizeTranslation = .zero
                                }
                        )
                        .allowsHitTesting(entry.isEditableTask)
                }
                .overlay(alignment: .bottom) {
                    CalendarResizeHandle(isActive: resizeEdge == .bottom, isVisible: showsResizeHandles)
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    resizeEdge = .bottom
                                    resizeTranslation = value.translation
                                }
                                .onEnded { value in
                                    onResize(.bottom, value.translation)
                                    resizeEdge = nil
                                    resizeTranslation = .zero
                                }
                        )
                        .allowsHitTesting(entry.isEditableTask)
                }
        }
        .frame(width: frameWidth, height: frameHeight)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard entry.isEditableTask, resizeEdge == nil else { return }
                moveTranslation = value.translation
            }
            .onEnded { value in
                guard entry.isEditableTask, resizeEdge == nil else {
                    moveTranslation = .zero
                    return
                }
                onMove(value.translation)
                moveTranslation = .zero
            }
    }

    private var preview: CalendarResizePreview {
        guard let resizeEdge else {
            return CalendarResizePreview(offsetY: 0, height: frameHeight)
        }
        return CommandCenterCalendarLayout.resizePreview(
            edge: resizeEdge,
            translationHeight: resizeTranslation.height,
            originalHeight: frameHeight
        )
    }

    private var showsResizeHandles: Bool {
        entry.isEditableTask && (isSelected || isHovered || resizeEdge != nil)
    }
}

private struct CalendarEntryBlock: View {
    let entry: CommandCenterCalendarEntry
    let isSelected: Bool
    let isHovered: Bool
    let density: CalendarEntryDensity

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(entry.accent)
                .frame(width: 3)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: density == .compact ? 0 : DS.space2) {
                HStack(spacing: DS.space4) {
                    if entry.isCompletedTask {
                        // The seal — the day's small win, same stamp as the phone.
                        Image(systemName: "checkmark.seal.fill")
                            .font(DS.caption2)
                            .foregroundStyle(entry.accent.opacity(0.8))
                            .accessibilityLabel("Completed")
                    }

                    Text(entry.title)
                        .font(density == .compact ? DS.caption2 : DS.caption).fontWeight(.semibold)
                        .strikethrough(entry.isCompletedTask, color: DS.textMuted)
                        .foregroundStyle(entryTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    if density == .expanded, entry.isMissedOccurrence {
                        Text("missed")
                            .font(DS.caption2).fontWeight(.medium)
                            .foregroundStyle(DS.textMuted)
                    } else if density == .expanded, entry.event?.isExternal == true {
                        Image(systemName: "calendar")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(entry.accent.opacity(0.85))
                    }
                }

                if density == .expanded, let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(DS.caption2).fontWeight(.medium)
                        .foregroundStyle(entry.accent.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.space6)
            .padding(.vertical, density == .compact ? 2 : DS.space4)
            .frame(maxHeight: .infinity, alignment: density == .compact ? .center : .top)
        }
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(blockFill)

            // Vellum wash: external events carry their calendar's color a
            // touch stronger (the iPhone planner's event fill); Cosmo blocks
            // stay quieter — the accent hairline carries their identity.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(entry.accent.opacity(washOpacity))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1 : 0.5)
        )
        .shadow(color: .black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 5 : 1, x: 0, y: isSelected ? 3 : 1)
        .opacity(historyOpacity)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var blockFill: Color {
        if entry.source == .draft { return DS.glassSectionFill }
        return DS.glassCardFill
    }

    private var washOpacity: Double {
        if entry.source == .draft { return 0.10 }
        return entry.event?.isExternal == true ? 0.10 : 0.06
    }

    private var borderColor: Color {
        if isSelected { return entry.accent.opacity(0.55) }
        if isHovered { return entry.accent.opacity(0.24) }
        return entry.accent.opacity(0.16)
    }

    private var entryTextColor: Color {
        if entry.isCompletedTask || entry.isMissedOccurrence { return DS.textMuted }
        return entry.event?.isExternal == true ? DS.textSecondary : DS.text
    }

    private var historyOpacity: Double {
        if entry.source == .draft { return 0.78 }
        if entry.isCompletedTask { return 0.6 }
        if entry.isMissedOccurrence { return 0.5 }
        return 1
    }
}

private struct CalendarResizeHandle: View {
    let isActive: Bool
    let isVisible: Bool

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(height: 12)
            .overlay {
                Capsule()
                    .fill(DS.textMuted.opacity(isActive ? 0.55 : 0.30))
                    .frame(width: 28, height: 3)
                    .opacity(isVisible ? 1 : 0)
            }
            .contentShape(Rectangle())
    }
}

private struct UpcomingMonthCalendarView: View {
    let anchorDate: Date
    let dates: [Date]
    let entries: [CommandCenterCalendarEntry]
    let onOpenDay: (Date) -> Void
    let onCreateAllDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 92), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    MonthDayCell(
                        date: date,
                        isInDisplayedMonth: Calendar.current.isDate(date, equalTo: anchorDate, toGranularity: .month),
                        entries: entriesForDay(date),
                        onOpenDay: onOpenDay,
                        onCreateAllDay: onCreateAllDay
                    )
                    .frame(minHeight: 104)
                }
            }
        }
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle.opacity(0.55))
                .frame(height: 0.5)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                Text(day)
                    .font(DS.caption).fontWeight(.semibold)
                    .foregroundStyle(DS.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private func entriesForDay(_ date: Date) -> [CommandCenterCalendarEntry] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return entries
            .filter { $0.start < end && $0.end > start }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay && !$1.isAllDay }
                return $0.start < $1.start
            }
    }
}

private struct MonthDayCell: View {
    let date: Date
    let isInDisplayedMonth: Bool
    let entries: [CommandCenterCalendarEntry]
    let onOpenDay: (Date) -> Void
    let onCreateAllDay: (Date) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            header
            entryList

            Spacer(minLength: 0)
        }
        .padding(DS.space8)
        .background(cellBackground)
        .overlay(
            Rectangle()
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
        .opacity(isInDisplayedMonth ? 1 : 0.42)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDay(date)
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                onOpenDay(date)
            } label: {
                Text(dayNumber)
                    .font(DS.subheadline).fontWeight(isToday ? .bold : .semibold)
                    .foregroundStyle(dayForeground)
                    .frame(width: 26, height: 22)
                    .background(isToday ? DS.accent : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            if isHovered {
                Button {
                    onCreateAllDay(date)
                } label: {
                    Image(systemName: "plus")
                        .font(DS.caption2).fontWeight(.bold)
                        .foregroundStyle(DS.accent)
                        .frame(width: 22, height: 22)
                        .background(DS.accentSoft.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create all-day task")
            }
        }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: DS.space2 + 1) {
            ForEach(visibleEntries) { entry in
                monthEntryChip(entry)
            }

            if overflowCount > 0 {
                Text("+\(overflowCount) more")
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private func monthEntryChip(_ entry: CommandCenterCalendarEntry) -> some View {
        HStack(spacing: DS.space4) {
            Rectangle()
                .fill(entry.accent)
                .frame(width: 2, height: 12)
                .clipShape(.rect(cornerRadius: 1))

            Text(entry.title)
                .font(DS.caption2).fontWeight(.medium)
                .foregroundStyle(entryTextColor)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.space4)
        .frame(height: 18)
        .background(entry.accent.opacity(0.09), in: .rect(cornerRadius: 4))
    }

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var dayForeground: Color {
        if isToday { return DS.textOnAccent }
        return isInDisplayedMonth ? DS.text : DS.textMuted
    }

    private var entryTextColor: Color {
        isInDisplayedMonth ? DS.textSecondary : DS.textMuted
    }

    private var cellBackground: Color {
        isToday ? DS.accent.opacity(0.035) : Color.clear
    }

    private var visibleEntries: [CommandCenterCalendarEntry] {
        Array(entries.prefix(4))
    }

    private var overflowCount: Int {
        max(entries.count - 4, 0)
    }
}

private struct CalendarEditorPopover: View {
    let draft: CalendarEditorDraft
    let onSave: (CalendarEditorDraft) -> Void
    let onDelete: (CalendarEditorDraft) -> Void
    let onDismiss: () -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var start: Date
    @State private var end: Date
    @FocusState private var titleFocused: Bool

    init(
        draft: CalendarEditorDraft,
        onSave: @escaping (CalendarEditorDraft) -> Void,
        onDelete: @escaping (CalendarEditorDraft) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        _title = State(initialValue: draft.title)
        _bodyText = State(initialValue: draft.body)
        _start = State(initialValue: draft.start)
        _end = State(initialValue: draft.end)
    }

    var body: some View {
        VStack(spacing: DS.space10) {
            segmentedHeader
            titleField
            mutedField("Add Location or Video Call", trailingIcon: "video.fill")
            dateField
            mutedField("Add Alert, Repeat, or Travel Time")
            notesField
            actionRow
        }
        .padding(DS.space12)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 18)
        .onAppear { titleFocused = true }
        .onExitCommand(perform: onDismiss)
    }

    private var segmentedHeader: some View {
        HStack(spacing: 0) {
            Text("Event")
                .font(DS.subheadline).fontWeight(.semibold)
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(DS.accent, in: Capsule())

            Text("Reminder")
                .font(DS.subheadline).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
        }
        .padding(2)
        .background(DS.glassSectionFill, in: Capsule())
    }

    private var titleField: some View {
        TextField("New Event", text: $title)
            .textFieldStyle(.plain)
            .font(DS.title2)
            .foregroundStyle(DS.text)
            .focused($titleFocused)
            .padding(.horizontal, DS.space10)
            .frame(height: 42)
            .dsGlassInput(isFocused: titleFocused, cornerRadius: 10)
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(dateRangeText)
                .font(DS.callout).fontWeight(.semibold)
                .foregroundStyle(DS.text)

            HStack(spacing: DS.space8) {
                DatePicker("", selection: $start, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden()
                if !draft.isAllDay {
                    DatePicker("", selection: $end, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                }
            }
        }
        .padding(DS.space10)
        .dsGlassCard(cornerRadius: 10)
    }

    private var notesField: some View {
        TextField("Add Notes or URL", text: $bodyText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .lineLimit(2...4)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .dsGlassInput(cornerRadius: 10)
    }

    private var actionRow: some View {
        HStack(spacing: DS.space8) {
            if !draft.isNew {
                Button {
                    onDelete(currentDraft)
                } label: {
                    Image(systemName: "trash")
                        .font(DS.subheadline).fontWeight(.semibold)
                        .foregroundStyle(DS.red)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete event")
            }

            Spacer()

            Button("Cancel") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(DS.subheadline).fontWeight(.medium)
            .foregroundStyle(DS.textSecondary)

            Button {
                onSave(currentDraft)
            } label: {
                Text("Save")
                    .font(DS.subheadline).fontWeight(.semibold)
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space12)
                    .frame(height: 30)
                    .background(DS.accent, in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private func mutedField(_ text: String, trailingIcon: String? = nil) -> some View {
        HStack {
            Text(text)
                .font(DS.callout).fontWeight(.medium)
                .foregroundStyle(DS.textMuted)
            Spacer()
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(DS.caption).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 36)
        .dsGlassCard(cornerRadius: 10)
    }

    private var currentDraft: CalendarEditorDraft {
        var updated = draft
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Event" : title
        updated.body = bodyText
        updated.start = start
        updated.end = max(end, Calendar.current.date(byAdding: .minute, value: 15, to: start) ?? start.addingTimeInterval(900))
        return updated
    }

    private var dateRangeText: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        if draft.isAllDay {
            return "\(dateFormatter.string(from: start)) · all day"
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        return "\(dateFormatter.string(from: start))  \(timeFormatter.string(from: start)) – \(timeFormatter.string(from: end))"
    }
}
