// Canvas/CommandCenter/DashboardScheduleStrip.swift
// Visual vertical timeline showing tracked sessions + calendar events as colored blocks
// Timery-style day view
// March 2026

import SwiftUI

struct DashboardScheduleStrip: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var nowPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let hourHeight: CGFloat = 50
    private let startHour: Int = 7
    private let endHour: Int = 23

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Hour grid lines
                        hourGrid

                        // Calendar events
                        ForEach(viewModel.todayEvents) { event in
                            calendarEventBlock(event)
                        }

                        // Schedule blocks — pure time blocking (iOS planner
                        // parity); recurring templates arrive pre-projected.
                        ForEach(viewModel.todayScheduleBlocks) { block in
                            scheduleBlockView(block)
                        }

                        // Deep work sessions
                        ForEach(viewModel.todaySessions) { session in
                            sessionBlock(session)
                        }

                        // Now marker
                        if viewModel.isViewingToday {
                            nowMarker
                                .id("nowMarker")
                        }
                    }
                    .frame(height: CGFloat(endHour - startHour) * hourHeight)
                }
                .frame(maxHeight: 400)
                .onAppear {
                    if viewModel.isViewingToday {
                        proxy.scrollTo("nowMarker", anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(DS.caption2).fontWeight(.semibold)
                .foregroundColor(DS.textMuted)

            Text("TIMELINE")
                .dsSectionLabel()

            Spacer()

            if !viewModel.todaySessions.isEmpty {
                Text("\(viewModel.todaySessions.count) sessions")
                    .font(DS.caption2)
                    .foregroundColor(DS.textMuted)
            }
        }
    }

    // MARK: - Hour Grid

    private var hourGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    // Hour label
                    Text(hourLabel(hour))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 32, alignment: .trailing)

                    // Grid line
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(DS.borderSubtle)
                            .frame(height: 0.5)
                        Spacer()
                    }
                }
                .frame(height: hourHeight)
            }
        }
    }

    // MARK: - Calendar Event Block

    @ViewBuilder
    private func calendarEventBlock(_ event: CalendarEvent) -> some View {
        let yOffset = yPosition(for: event.startDate)
        let height = max(blockHeight(from: event.startDate, to: event.endDate), 16)
        let isPast = event.endDate < Date()

        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendarColor))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundColor(isPast ? DS.textMuted : DS.text)
                    .lineLimit(1)

                if height > 24 {
                    Text(timeRange(event.startDate, event.endDate))
                        .font(.system(size: 8))
                        .foregroundColor(DS.textMuted)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
        }
        .padding(.vertical, 2)
        .frame(height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: event.calendarColor).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(nsColor: event.calendarColor).opacity(0.2), lineWidth: 0.5)
        )
        .opacity(isPast ? 0.6 : 1.0)
        .offset(x: 40, y: yOffset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
    }

    // MARK: - Schedule Block (time blocking — the iOS planner's objects)

    @ViewBuilder
    private func scheduleBlockView(_ block: ScheduleBlockEntry) -> some View {
        let yOffset = yPosition(for: block.start)
        let height = max(blockHeight(from: block.start, to: block.end), 16)
        let tint = block.colorHex.map(Color.init(hex:)) ?? DS.accent
        let isPast = block.end < Date()
        let linkedTasks = viewModel.tasksLinked(toBlock: block.id)

        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(block.title)
                        .font(DS.caption2).fontWeight(.medium)
                        .foregroundColor(block.isCompleted || isPast ? DS.textMuted : DS.text)
                        .strikethrough(block.isCompleted, color: DS.textMuted)
                        .lineLimit(1)
                    if block.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(tint)
                    }
                    if block.location != nil {
                        Image(systemName: "link")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(tint)
                    }
                }

                if height > 24 {
                    Text(timeRange(block.start, block.end))
                        .font(.system(size: 8))
                        .foregroundColor(DS.textMuted)
                }

                nestedTaskLines(linkedTasks, tint: tint, cardHeight: height)
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
        }
        .padding(.vertical, 2)
        .frame(height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(tint.opacity(0.25), lineWidth: 0.5)
        )
        .opacity(isPast ? 0.6 : 1.0)
        .offset(x: 40, y: yOffset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
        .contextMenu {
            blockTaskMenu(block, linkedTasks: linkedTasks)
            Divider()
            Button {
                viewModel.convertScheduleBlockToTask(block)
            } label: {
                Label("Turn into Task", systemImage: "checkmark.circle")
            }
            if let location = block.location,
               let url = URL(string: location),
               url.scheme == "http" || url.scheme == "https" {
                Link(destination: url) {
                    Label("Open Link", systemImage: "arrow.up.right.square")
                }
            }
            Divider()
            Button(role: .destructive) {
                viewModel.deleteScheduleBlock(block)
            } label: {
                Label(block.isRecurring ? "Delete Series" : "Delete Block", systemImage: "trash")
            }
        }
        .help(blockHelp(block, linkedTasks: linkedTasks))
    }

    // MARK: - Nested tasks (iOS planner parity)

    /// Tasks nested in the block, drawn as quiet lines under the title —
    /// display-only; assignment lives in the context menu. Everything shows
    /// when it fits; a half-fit shows some plus "N more"; one spare line
    /// collapses to "N tasks"; no room leaves it to the tooltip.
    @ViewBuilder
    private func nestedTaskLines(_ tasks: [TaskViewModel], tint: Color, cardHeight: CGFloat) -> some View {
        let budget = max(0, Int((cardHeight - 30) / 12))
        if budget > 0, !tasks.isEmpty {
            let rows = tasks.count <= budget ? tasks : Array(tasks.prefix(max(0, budget - 1)))
            let overflow = tasks.count - rows.count
            VStack(alignment: .leading, spacing: 1) {
                ForEach(rows, id: \.id) { task in
                    HStack(spacing: 3) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 7))
                            .foregroundColor(task.isCompleted ? tint : DS.textMuted)
                        Text(task.title)
                            .font(.system(size: 8))
                            .foregroundColor(task.isCompleted ? DS.textMuted : DS.textSecondary)
                            .strikethrough(task.isCompleted, color: DS.textMuted)
                            .lineLimit(1)
                    }
                }
                if overflow > 0 {
                    Text(rows.isEmpty ? "\(overflow) task\(overflow == 1 ? "" : "s")" : "\(overflow) more")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(tint)
                }
            }
            .padding(.top, 1)
            .accessibilityHidden(true)
        }
    }

    /// Link/unlink tasks without leaving the timeline: the day's open,
    /// unassigned tasks nest in one click; a nested task pops back out. The
    /// block owns the time — nesting never retimes the task.
    @ViewBuilder
    private func blockTaskMenu(_ block: ScheduleBlockEntry, linkedTasks: [TaskViewModel]) -> some View {
        let candidates = viewModel.blockLinkCandidates
        Menu {
            if candidates.isEmpty {
                Text("No open tasks to add")
            } else {
                ForEach(candidates, id: \.id) { task in
                    Button(task.title) {
                        Task { await viewModel.setScheduleBlock(taskUUID: task.uuid, blockUUID: block.id) }
                    }
                }
            }
        } label: {
            Label("Add Task to Block", systemImage: "plus.circle")
        }
        if !linkedTasks.isEmpty {
            Menu {
                ForEach(linkedTasks, id: \.id) { task in
                    Button(task.title) {
                        Task { await viewModel.setScheduleBlock(taskUUID: task.uuid, blockUUID: nil) }
                    }
                }
            } label: {
                Label("Remove Task from Block", systemImage: "minus.circle")
            }
        }
    }

    private func blockHelp(_ block: ScheduleBlockEntry, linkedTasks: [TaskViewModel]) -> String {
        var line = block.isRecurring
            ? "\(block.title) — \(block.recurrenceText ?? "repeats"). Edits apply to every occurrence."
            : block.title
        if !linkedTasks.isEmpty {
            line += "\nTasks: " + linkedTasks.map(\.title).joined(separator: ", ")
        }
        return line
    }

    // MARK: - Session Block

    @ViewBuilder
    private func sessionBlock(_ session: SessionTimelineEntry) -> some View {
        let yOffset = yPosition(for: session.startTime)
        let height = max(blockHeight(from: session.startTime, to: session.endTime), 20)

        HStack(spacing: 6) {
            Image(systemName: session.intent.icon)
                .font(.system(size: 8))
                .foregroundStyle(DS.textOnAccent)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.intent.title)
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(DS.textOnAccent)
                    .lineLimit(1)

                if let habitTitle = session.habitTitle {
                    Text(habitTitle)
                        .font(.system(size: 8))
                        .foregroundStyle(DS.textOnAccent.opacity(0.85))
                        .lineLimit(1)
                } else {
                    Text(session.title)
                        .font(.system(size: 8))
                        .foregroundStyle(DS.textOnAccent.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            // Duration
            Text(sessionDuration(session))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(DS.textOnAccent.opacity(0.8))

            // Focus score dot
            Circle()
                .fill(focusColor(session.focusScore))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(height: height, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(session.intent.accent.opacity(0.85))
        )
        .offset(x: 40, y: yOffset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
    }

    // MARK: - Now Marker

    private var nowMarker: some View {
        let yOffset = yPosition(for: Date())

        return HStack(spacing: 0) {
            ZStack {
                // Pulse ring — fades outward
                if !reduceMotion {
                    Circle()
                        .stroke(DS.accent.opacity(nowPulse ? 0 : 0.4), lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                        .scaleEffect(nowPulse ? 2.2 : 1.0)
                        .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: nowPulse)
                }

                Circle()
                    .fill(DS.accent)
                    .frame(width: 8, height: 8)
            }

            Rectangle()
                .fill(DS.accent)
                .frame(height: 1.5)
        }
        .offset(x: 28, y: yOffset)
        .onAppear {
            if !reduceMotion {
                nowPulse = true
            }
        }
    }

    // MARK: - Positioning Helpers

    private func yPosition(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let fractionalHour = Double(hour - startHour) + Double(minute) / 60.0
        return max(0, CGFloat(fractionalHour) * hourHeight)
    }

    private func blockHeight(from start: Date, to end: Date) -> CGFloat {
        let duration = end.timeIntervalSince(start) / 3600.0
        return CGFloat(duration) * hourHeight
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 || hour == 12 { return hour == 0 ? "12a" : "12p" }
        if hour < 12 { return "\(hour)a" }
        return "\(hour - 12)p"
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm"
        return "\(fmt.string(from: start))-\(fmt.string(from: end))"
    }

    private func sessionDuration(_ session: SessionTimelineEntry) -> String {
        let mins = Int(session.endTime.timeIntervalSince(session.startTime) / 60)
        if mins >= 60 {
            return "\(mins / 60)h\(mins % 60)m"
        }
        return "\(mins)m"
    }

    private func focusColor(_ score: Double) -> Color {
        if score >= 80 { return .white }
        if score >= 50 { return .yellow }
        return .red
    }
}
