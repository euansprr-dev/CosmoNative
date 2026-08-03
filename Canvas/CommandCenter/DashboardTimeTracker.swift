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
    @Environment(\.isPaneExpanded) private var isPaneExpanded

    @State private var goalMinutes = FocusStreakEngine.defaultGoalMinutes
    @State private var week: [FocusDay] = []
    @State private var streak: (current: Int, best: Int) = (0, 0)
    @State private var startHovered = false

    /// Books' arc: exactly a half circle — the ends land AT the horizontal
    /// diameter, never curling back in at the bottom (0.56 read amateur next
    /// to Books; matched against the iPhone gauge, recipes §15).
    private static let arcSpan = 0.5
    private static let arcDiameter: CGFloat = 208
    private static let arcStroke: CGFloat = 9
    /// The visible band: the top half of the circle plus the round caps that
    /// straddle the horizontal (stroke centers on the path).
    private static var arcBandHeight: CGFloat { arcDiameter / 2 + arcStroke }

    // Left anchor (gauge) → quiet middle (label, dots, streak) → terminal
    // right anchor (the one primary action): the same left/right tension the
    // masthead above already uses. The action at the group's trailing edge
    // turns the hero row's dead right half into structure — an interval
    // between two anchors, not a leak.
    var body: some View {
        HStack(alignment: .center, spacing: DS.space24) {
            gauge
            rightColumn
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: DS.space24)
            actionRow
        }
        .padding(.horizontal, DS.space12)
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
        // Collapsed Command Center panes stay mounted — a running session
        // must not tick an off-screen gauge at 1Hz. Re-expanding re-evaluates
        // with live values immediately.
        TimelineView(.periodic(from: .now, by: sessionEngine.isTimerRunning && isPaneExpanded ? 1 : 60)) { _ in
            ZStack {
                // DS.border, not borderSubtle: this gauge sits directly on the
                // page (the iPhone's sits in a white container) — the subtle
                // rung disappears against DS.bg.
                // Warm track (sepia, the page's own neutral family), vivid
                // sweep: at a 9pt stroke the base accent crushes toward ink —
                // the hero arc is where the brand hue must actually read.
                gaugeCircle(trim: Self.arcSpan)
                    .stroke(DS.sepiaBorder, style: StrokeStyle(lineWidth: Self.arcStroke, lineCap: .round))
                gaugeCircle(trim: Self.arcSpan * arcProgress)
                    .stroke(DS.accentVivid, style: StrokeStyle(lineWidth: Self.arcStroke, lineCap: .round))
                    .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: arcProgress)

                centerContent
            }
            .frame(width: Self.arcDiameter, height: Self.arcDiameter)
            .frame(height: Self.arcBandHeight, alignment: .top)
            // Inside the TimelineView so each tick re-evaluates it: the felt
            // bell the moment the goal lands mid-session (never on page load —
            // onChange only fires on a transition, and only while working).
            .onChange(of: liveGoalMet) { _, met in
                if met, sessionEngine.activeSession != nil {
                    Sound.goalBell()
                }
            }
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
                // Hidden mirror (the iPhone gauge's optical-balance trick):
                // the goal-met check gets a phantom twin on the leading side
                // so the numerals stay optically centered when it appears.
                if liveGoalMet {
                    Image(systemName: "checkmark")
                        .font(DS.caption.weight(.semibold))
                        .hidden()
                        .accessibilityHidden(true)
                }
                // At zero the numeral recedes to muted — the morning must
                // greet as an invitation, not a deficit scoreboard.
                // Quantity-unit typesetting: digits carry the mass, the "h"/
                // "m" step down to unit scale. Tabular figures only while the
                // clock ticks — on a static "2h 5m" they just loosen the fit.
                gaugeFigure
                    .foregroundStyle(liveTotalSeconds == 0 ? DS.textMuted : DS.text)
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
                    // Anticipation, not deficit: an untouched day reads as
                    // open road ("ahead"), never as zero progress.
                    Text(liveTotalSeconds == 0 ? "your \(goalLabel) day ahead" : "of your \(goalLabel) goal")
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(DS.caption2.weight(.semibold))
                }
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Open reports")
        }
        // Optical center rides low (Books' placement): the text column's
        // bottom lands at the arc-cap level, where the chord is widest —
        // lifted off the frame's geometric center, which now sits ON the
        // half-circle's chord.
        .minimumScaleFactor(0.7)
        .allowsTightening(true)
        .frame(maxWidth: Self.arcDiameter - 68)
        .offset(y: -Self.arcDiameter * 0.15)
    }

    /// The gauge figure as ranked runs: digit clusters at display scale,
    /// unit letters ("h", "m") at unit scale, joined by thin spaces. While a
    /// session runs the string is pure digits+colons and stays one run with
    /// tabular figures (the Books / Timer convention).
    private var gaugeFigure: Text {
        if sessionEngine.isTimerRunning {
            return Text(formattedLiveTotal)
                .font(DS.gaugeTitleSerif)
                .monospacedDigit()
        }
        var result: Text? = nil
        for cluster in formattedLiveTotal.split(separator: " ") {
            let digits = cluster.prefix { $0.isNumber || $0 == ":" }
            let unit = cluster.dropFirst(digits.count)
            let digitsText = Text(String(digits)).font(DS.gaugeTitleSerif)
            let piece: Text = unit.isEmpty
                ? digitsText
                : Text("\(digitsText)\(Text(String(unit)).font(DS.gaugeUnitSerif))")
            result = result.map { prev in Text("\(prev)\u{2009}\(piece)") } ?? piece
        }
        return result ?? Text(verbatim: "")
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
            // "Deep work", not "Deep Work": small caps leave capitals at full
            // height, so a second cap mid-label breaks the run's rhythm. And
            // never "Today's deep work" — a label must not echo the page title.
            Text("Deep work")
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
                .foregroundStyle(DS.giltInk)

            HStack(spacing: DS.space8) {
                weekDots
                Text(streakLine)
                    .font(DS.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
        }
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
                        Circle().strokeBorder(DS.text.opacity(0.5), lineWidth: 1)
                    } else if !met {
                        // Warm ring from the page's own ink family — the cool
                        // borderSubtle is a UI-kit grey on a parchment hero.
                        Circle().strokeBorder(DS.giltMuted.opacity(0.35), lineWidth: 0.5)
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
        // "Best streak 1 day" is a scoreboard of failure; a single past day
        // earns the same forward-facing line as none.
        if streak.best > 1 {
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
            // The page's primary CTA speaks ABOVE the metadata band, never
            // below it (it was 11pt — smaller than a task title). The soft
            // color-matched glow is how a dark accent still reads as a hue
            // instead of ink on a flat page.
            HStack(spacing: DS.space6) {
                Image(systemName: "play.fill")
                    .font(DS.caption)
                // The page's primary action speaks at the TITLE rung (13),
                // never below a task's own name.
                Text(focusCandidate == nil ? "Select a task" : "Start focus")
                    .font(DS.callout.weight(.semibold))
            }
            .foregroundStyle(focusCandidate == nil ? DS.textSecondary : DS.textOnAccent)
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
            .background(focusCandidate == nil ? DS.glassInputFill : DS.accentVivid, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    focusCandidate == nil ? DS.glassBorder : DS.accentVivid.opacity(0.25),
                    lineWidth: 0.5
                )
            )
            .shadow(
                color: focusCandidate == nil ? .clear : DS.accentGlow,
                radius: 10, x: 0, y: 4
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
                        .monospacedDigit()
                        .foregroundStyle(DS.textSecondary)
                }
            }

            Spacer(minLength: DS.space12)

            HStack(spacing: DS.space6) {
                if sessionEngine.isTimerRunning {
                    iconControlButton(icon: "pause.fill", color: DS.text, bg: DS.glassInputFill, help: "Pause (Space)") {
                        Sound.focusPause()
                        sessionEngine.pauseSession()
                    }
                } else {
                    iconControlButton(icon: "play.fill", color: DS.textOnAccent, bg: DS.accent, help: "Resume (Space)") {
                        Sound.focusResume()
                        sessionEngine.resumeSession()
                    }
                }
                iconControlButton(icon: "stop.fill", color: DS.red, bg: DS.redSoft.opacity(0.7), help: "End session") {
                    Sound.focusEnd()
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

