// Canvas/CommandCenter/DashboardTimeTracker.swift
// The Today hero: the Books-grammar deep-work gauge, laid out for a wide
// desktop column — arc left, week/streak/actions right. Same semantics as the
// iPhone's FocusGaugeCard (same synced goal atom, same streak math via
// FocusStreakEngine), Mac manners: hover lift, tooltips, Space to start.

import SwiftUI

struct DashboardTimeTracker: View {

    var viewModel: CommandCenterDashboardViewModel
    @ObservedObject private var sessionEngine = DeepWorkSessionEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var goalMinutes = FocusStreakEngine.defaultGoalMinutes
    @State private var week: [FocusDay] = []
    @State private var streak: (current: Int, best: Int) = (0, 0)
    @State private var startHovered = false

    /// Books' arc: just past a half circle, open at the bottom — desktop scale.
    private static let arcSpan = 0.56
    private static let arcDiameter: CGFloat = 208
    private static let arcStroke: CGFloat = 9

    var body: some View {
        HStack(alignment: .center, spacing: DS.space24) {
            gauge
            rightColumn
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(ProMotionSprings.focusTransition, value: sessionEngine.activeSession != nil)
        .task { await loadStreaks() }
        .onChange(of: viewModel.todayTrackedMinutes) { _, _ in
            Task { await loadStreaks() }
        }
    }

    // MARK: - Live math

    /// Today's total in seconds — persisted history plus the running sitting.
    private var liveTotalSeconds: Int {
        var total = viewModel.todayTrackedMinutes * 60
        if let session = sessionEngine.activeSession {
            total += Int(session.elapsedActiveSeconds)
        }
        return total
    }

    private var liveGoalMet: Bool {
        goalMinutes > 0 && liveTotalSeconds >= goalMinutes * 60
    }

    private var arcProgress: Double {
        guard goalMinutes > 0 else { return 0 }
        let raw = min(1, Double(liveTotalSeconds) / Double(goalMinutes * 60))
        // Once any time is tracked, the sweep never reads as a stray dot —
        // a 2% floor makes minute one look begun, not smudged.
        return liveTotalSeconds > 0 ? max(raw, 0.02) : 0
    }

    // MARK: - Gauge (arc + numerals)

    /// Geometry rule (learned the hard way): the circle draws in a TRUE
    /// square frame — a Circle shape inscribes in the smallest dimension, so
    /// a rectangular frame silently shrinks the arc. The empty open-bottom
    /// quarter is then cropped off, giving the cluster an honest height.
    private var gauge: some View {
        TimelineView(.periodic(from: .now, by: sessionEngine.isTimerRunning ? 1 : 60)) { _ in
            ZStack {
                gaugeCircle(trim: Self.arcSpan)
                    .stroke(DS.borderSubtle, style: StrokeStyle(lineWidth: Self.arcStroke, lineCap: .round))
                gaugeCircle(trim: Self.arcSpan * arcProgress)
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: Self.arcStroke, lineCap: .round))
                    .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: arcProgress)

                centerContent
            }
            .frame(width: Self.arcDiameter, height: Self.arcDiameter)
            .frame(height: Self.arcDiameter * 0.70, alignment: .top)
        }
    }

    /// An arc of `trim` of the circle, centered on 12 o'clock.
    private func gaugeCircle(trim: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: trim)
            .rotation(.degrees(-90 - Self.arcSpan * 360 / 2))
    }

    private var centerContent: some View {
        VStack(spacing: DS.space2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space4) {
                Text(formattedLiveTotal)
                    .font(.system(size: 36, weight: .medium, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
                    .contentTransition(.numericText())
                if liveGoalMet {
                    Image(systemName: "checkmark")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.gilt)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }

            Button {
                withAnimation(ProMotionSprings.snappy) { viewModel.showReports = true }
            } label: {
                HStack(spacing: DS.space2) {
                    Text("of your \(goalLabel) goal")
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(DS.caption2.weight(.semibold))
                }
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Open reports")
        }
        // Optical centering: the band only spans the top ~60% of the circle,
        // so its perceived center sits ABOVE the geometric one — lift the
        // block to the band's visual midpoint so the arc crowns the numerals
        // instead of floating far over them.
        .minimumScaleFactor(0.7)
        .allowsTightening(true)
        .frame(maxWidth: Self.arcDiameter - 68)
        .offset(y: -Self.arcDiameter * 0.12)
    }

    private var goalLabel: String {
        if goalMinutes % 60 == 0 {
            return goalMinutes == 60 ? "1-hour" : "\(goalMinutes / 60)-hour"
        }
        return "\(goalMinutes)-minute"
    }

    private var formattedLiveTotal: String {
        let total = liveTotalSeconds
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if sessionEngine.isTimerRunning {
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, mins, secs)
                : String(format: "%d:%02d", mins, secs)
        }
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    // MARK: - Right column (label, week, streak, actions)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("Today's Deep Work")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)

            HStack(spacing: DS.space8) {
                weekDots
                Text(streakLine)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }

            actionRow

            if !viewModel.todayIntentSummaries.isEmpty {
                intentBreakdownBar
                    .frame(width: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekDots: some View {
        HStack(spacing: DS.space6) {
            ForEach(week) { day in
                weekDot(day)
            }
        }
    }

    private func weekDot(_ day: FocusDay) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        let met = day.met || (isToday && liveGoalMet)
        return Button {
            withAnimation(ProMotionSprings.snappy) { viewModel.showReports = true }
        } label: {
            Text(weekdayInitial(day.date))
                .font(DS.caption2.weight(isToday ? .bold : .medium))
                .foregroundStyle(met ? DS.textOnAccent : (isToday ? DS.text : DS.textMuted))
                .frame(width: 22, height: 22)
                .background(met ? AnyShapeStyle(DS.accent) : AnyShapeStyle(DS.glassSectionFill))
                .clipShape(.circle)
                .overlay {
                    if isToday && !met {
                        Circle().stroke(DS.text.opacity(0.5), lineWidth: 1)
                    } else if !met {
                        Circle().stroke(DS.borderSubtle, lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("\(day.date.formatted(.dateTime.weekday(.wide))) — \(day.minutes)m focused")
        .animation(ProMotionSprings.snappy, value: met)
    }

    private func weekdayInitial(_ date: Date) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let index = Calendar.current.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private var streakLine: String {
        if streak.current > 0 {
            let days = streak.current == 1 ? "day" : "days"
            return streak.best > streak.current
                ? "\(streak.current)-day streak · best \(streak.best)"
                : "\(streak.current) \(days) and counting"
        }
        if streak.best > 0 {
            return "Best streak \(streak.best) days"
        }
        return "Meet your goal to start a streak"
    }

    // MARK: - Action row

    @ViewBuilder
    private var actionRow: some View {
        if let session = sessionEngine.activeSession {
            activeSessionRow(session)
        } else {
            startFocusButton
        }
    }

    private var startFocusButton: some View {
        Button {
            guard let task = focusCandidate else { return }
            viewModel.startFocusSession(for: task)
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: "play.fill")
                    .font(DS.caption2)
                Text(focusCandidate == nil ? "Select a task" : "Start focus")
                    .font(DS.caption.weight(.semibold))
            }
            .foregroundStyle(focusCandidate == nil ? DS.textSecondary : DS.textOnAccent)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(focusCandidate == nil ? DS.glassInputFill : DS.accent, in: Capsule())
            .overlay(
                Capsule().stroke(
                    focusCandidate == nil ? DS.glassBorder : DS.accent.opacity(0.25),
                    lineWidth: 0.5
                )
            )
            .scaleEffect(startHovered && focusCandidate != nil ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .disabled(focusCandidate == nil)
        .opacity(focusCandidate == nil ? 0.6 : 1)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { startHovered = hovering }
        }
        .help("Start a focus session on the selected task (Space)")
    }

    @ViewBuilder
    private func activeSessionRow(_ session: ActiveDeepWorkSession) -> some View {
        let intentPresentation = viewModel.resolvedIntentPresentation(
            intentUUID: session.intentUUID,
            legacyIntentRaw: session.intent.rawValue
        )
        // Habit is the primary attribution axis; intent (when distinct) is the muted secondary.
        let habit = session.habitUUID.flatMap { viewModel.habitDefinition(for: $0) }
        let categoryIcon = habit?.icon ?? intentPresentation.icon
        let categoryAccent = habit?.accent ?? intentPresentation.accent
        let categoryTitle = habit?.title ?? intentPresentation.title

        HStack(spacing: DS.space10) {
            Image(systemName: categoryIcon)
                .font(DS.caption)
                .foregroundStyle(categoryAccent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.taskTitle)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                HStack(spacing: DS.space6) {
                    Text(categoryTitle)
                        .font(DS.caption2)
                        .foregroundStyle(categoryAccent)
                    Circle()
                        .fill(focusScoreColor)
                        .frame(width: 5, height: 5)
                    Text("\(Int(sessionEngine.focusScore))%")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }

            Spacer(minLength: DS.space12)

            HStack(spacing: DS.space6) {
                if sessionEngine.isTimerRunning {
                    iconControlButton(icon: "pause.fill", color: DS.text, bg: DS.glassInputFill, help: "Pause (Space)") {
                        sessionEngine.pauseSession()
                    }
                } else {
                    iconControlButton(icon: "play.fill", color: DS.textOnAccent, bg: DS.accent, help: "Resume (Space)") {
                        sessionEngine.resumeSession()
                    }
                }
                iconControlButton(icon: "stop.fill", color: DS.red, bg: DS.redSoft.opacity(0.7), help: "End session") {
                    Task { await sessionEngine.endSession() }
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private func iconControlButton(
        icon: String,
        color: Color,
        bg: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.caption)
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Intent breakdown

    private var intentBreakdownBar: some View {
        GeometryReader { geo in
            let total = max(viewModel.todayTrackedMinutes, 1)
            HStack(spacing: 1) {
                ForEach(sortedIntentEntries, id: \.key.id) { entry in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.key.accent.opacity(0.75))
                        .frame(width: max(CGFloat(entry.value) / CGFloat(total) * geo.size.width - 1, 3))
                }
            }
        }
        .frame(height: 4)
        .clipShape(.rect(cornerRadius: 2))
    }

    private var sortedIntentEntries: [(key: IntentSummary, value: Int)] {
        viewModel.todayIntentSummaries
            .map { (key: $0, value: $0.minutes) }
            .sorted { $0.value > $1.value }
    }

    private var focusCandidate: TaskViewModel? {
        if let index = viewModel.selectedTaskIndex,
           viewModel.currentVisibleTasks.indices.contains(index) {
            let selected = viewModel.currentVisibleTasks[index]
            if !selected.isCompleted {
                return selected
            }
        }
        return viewModel.currentVisibleTasks.first { !$0.isCompleted }
    }

    private var focusScoreColor: Color {
        let score = sessionEngine.focusScore
        if score >= 80 { return DS.green }
        if score >= 50 { return DS.orange }
        return DS.red
    }

    // MARK: - Data

    private func loadStreaks() async {
        let engine = FocusStreakEngine()
        goalMinutes = ((try? await engine.dailyFocusGoalMinutes()) ?? nil) ?? FocusStreakEngine.defaultGoalMinutes
        week = (try? await engine.focusWeek(goal: goalMinutes)) ?? []
        streak = (try? await engine.focusStreaks(goal: goalMinutes)) ?? (0, 0)
    }
}

