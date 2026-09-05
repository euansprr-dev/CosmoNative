// Today's focus garden. Same botanical language as iPhone, composed around
// a desktop's task selection, keyboard controls, and live session context.
import SwiftUI

struct DashboardTimeTracker: View {
    var viewModel: CommandCenterDashboardViewModel
    let contentWidth: CGFloat
    @ObservedObject private var sessionEngine = DeepWorkSessionEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isPaneExpanded) private var isPaneExpanded
    @State private var goalMinutes = FocusStreakEngine.defaultGoalMinutes
    @State private var week: [FocusDay] = []
    @State private var streak: (current: Int, best: Int) = (0, 0)
    @State private var startHovered = false
    @State private var historyHovered = false
    @State private var isSavingGoal = false
    @State private var goalSaveFailed = false
    @State private var controlHovered: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: sessionEngine.isTimerRunning && isPaneExpanded ? 1 : 60)) { _ in
            Group {
                // The wide composition needs 190 + 180 + 220pt for its
                // columns and two 24pt gaps. Use the parent’s current
                // geometry; avoid probing
                // multiple live session layouts on every timer tick.
                if contentWidth >= 638 { wideGarden }
                else { compactGarden }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.space24)
            .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                    .strokeBorder(DS.sepiaBorder, lineWidth: 0.5)
            }
            .onChange(of: liveGoalMet) { _, met in
                if met && sessionEngine.activeSession != nil { Sound.goalBell() }
            }
        }
        .padding(.horizontal, DS.space12)
        .alert("Couldn’t save the daily goal", isPresented: $goalSaveFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your previous goal is unchanged. Please try again.")
        }
        .animation(reduceMotion ? nil : ProMotionSprings.focusTransition, value: sessionEngine.activeSession != nil)
        .task { await loadStreaks() }
        .onChange(of: viewModel.todayTrackedMinutes) { _, _ in Task { await loadStreaks() } }
    }

    private var wideGarden: some View {
        HStack(alignment: .center, spacing: DS.space24) {
            focusSummary.frame(width: 190, alignment: .leading)
            FocusTreeArtwork(progress: (progress * 100).rounded() / 100)
                .equatable()
                .frame(width: 180, height: 180)
                .frame(maxWidth: .infinity)
            practiceColumn.frame(minWidth: 220, maxWidth: 320, alignment: .leading)
        }
    }

    private var compactGarden: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            HStack(spacing: DS.space12) {
                focusSummary.frame(maxWidth: .infinity, alignment: .leading)
                if contentWidth >= 302 { tree }
            }
            practiceColumn
        }
    }

    private var tree: some View {
        FocusTreeArtwork(progress: (progress * 100).rounded() / 100)
            .equatable()
            .frame(width: 140, height: 154)
    }

    private var focusSummary: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Deep work")
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
                .foregroundStyle(DS.giltInk)
            Text(liveTotalSeconds == 0 && sessionEngine.activeSession == nil ? "Room to think." : formattedLiveTotal)
                .font(DS.displaySerif.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DS.text)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
            Text(liveGoalMet ? "Daily goal reached" : (liveTotalSeconds == 0 ? "Let your focus grow." : "focused today"))
                .font(DS.subheadline)
                .foregroundStyle(liveGoalMet ? DS.accent : DS.textSecondary)
            ProgressView(value: progress)
                .tint(DS.accent)
                .accessibilityLabel("Daily focus goal")
                .accessibilityValue("\(Int(progress * 100)) percent")
            goalMenu
        }
    }

    private var goalMenu: some View {
        Menu {
            ForEach([30, 60, 90, 120, 180, 240, 300, 360, 480], id: \.self) { minutes in
                Button {
                    Task { await saveGoal(minutes) }
                } label: {
                    if minutes == goalMinutes {
                        Label("\(minutes) minutes", systemImage: "checkmark")
                    } else {
                        Text("\(minutes) minutes")
                    }
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text("\(goalDuration) daily goal")
                Image(systemName: "chevron.up.chevron.down").font(DS.caption2)
            }
            .font(DS.caption)
            .foregroundStyle(historyHovered ? DS.accent : DS.textSecondary)
            .frame(minHeight: 32, alignment: .leading)
            .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isSavingGoal)
        .onHover { historyHovered = $0 }
        .help("Change the daily focus goal")
        .accessibilityLabel("Daily focus goal, \(goalDuration)")
    }

    private func saveGoal(_ minutes: Int) async {
        guard !isSavingGoal else { return }
        isSavingGoal = true
        defer { isSavingGoal = false }
        do {
            try await FocusStreakEngine().setDailyFocusGoal(minutes: minutes)
            await loadStreaks()
        } catch {
            goalSaveFailed = true
        }
    }

    private var practiceColumn: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            weekRow
            if sessionEngine.activeSession == nil, let candidate = focusCandidate {
                Text(candidate.title)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                    .help("Start focus on \(candidate.title)")
            }
            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekRow: some View {
        Button { openReports() } label: {
            VStack(alignment: .leading, spacing: DS.space8) {
                HStack {
                    Text("This week")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.space8)
                    if streak.current > 0 {
                        Text("\(streak.current)-day streak")
                            .font(DS.caption.monospacedDigit())
                            .foregroundStyle(DS.textMuted)
                    }
                }
                HStack(spacing: DS.space16) {
                    ForEach(week) { day in
                        let today = Calendar.current.isDateInToday(day.date)
                        let met = day.met || (today && liveGoalMet)
                        VStack(spacing: DS.space6) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(DS.caption2.weight(today ? .semibold : .regular))
                                .foregroundStyle(today ? DS.text : DS.textMuted)
                            Image(systemName: met ? "checkmark.circle.fill" : "circle.fill")
                                .font(DS.caption2)
                                .foregroundStyle(met ? DS.accent : DS.border)
                                .overlay {
                                    if today && !met { Circle().strokeBorder(DS.accent, lineWidth: 1) }
                                }
                        }
                        .frame(minWidth: 16)
                    }
                }
            }
            .padding(.vertical, DS.space4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in controlHovered = hovering ? "week" : nil }
        .opacity(controlHovered == "week" ? 0.75 : 1)
        .help("Open focus history and streaks")
        .accessibilityLabel("This week's focus. \(week.filter { $0.met || (Calendar.current.isDateInToday($0.date) && liveGoalMet) }.count) daily goals reached.")
    }

    private var goalDuration: String {
        let hours = goalMinutes / 60
        let minutes = goalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    private func openReports() {
        withAnimation(reduceMotion ? nil : ProMotionSprings.snappy) { viewModel.viewMode = .reports }
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

    private var progress: Double {
        guard goalMinutes > 0 else { return 0 }
        return min(1, max(0, Double(liveTotalSeconds) / Double(goalMinutes * 60)))
    }

    private var formattedLiveTotal: String {
        let total = liveTotalSeconds
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if sessionEngine.activeSession != nil {
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, mins, secs)
                : String(format: "%d:%02d", mins, secs)
        }
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
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
            Label(focusCandidate == nil ? "Choose a task to focus" : "Start focus", systemImage: "play.fill")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(focusCandidate == nil ? DS.textSecondary : DS.textOnAccent)
                .padding(.horizontal, DS.space24)
                .frame(minHeight: 44)
                .background(focusCandidate == nil ? DS.glassInputFill : DS.accent, in: .capsule)
                .scaleEffect(startHovered && focusCandidate != nil && !reduceMotion ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .disabled(focusCandidate == nil)
        .opacity(focusCandidate == nil ? 0.6 : 1)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { startHovered = hovering }
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
                .frame(width: 44, height: 44)
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .onHover { hovering in controlHovered = hovering ? icon : nil }
        .opacity(controlHovered == icon ? 0.75 : 1)
        .accessibilityLabel(help)
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


// Paired native artwork in the iOS and macOS Today heroes.
// A deterministic botanical drawing: no bitmap, network, timer, or random
// changes at render time. The canopy fills as the real daily goal advances.
private struct FocusTreeArtwork: View, Equatable {
    let progress: Double
    // Resolve colors at construction so Equatable also invalidates on a
    // theme change, even when the day's progress has not moved.
    private let accent = DS.accent
    private let accentVivid = DS.accentVivid
    private let gilt = DS.gilt
    private let giltInk = DS.giltInk
    private let secondaryInk = DS.textSecondary
    private let paper = DS.surfaceElevated

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 200, size.height / 220)
            context.translateBy(x: (size.width - 200 * scale) / 2, y: (size.height - 220 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            drawTree(in: context)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func drawTree(in context: GraphicsContext) {
        let growth = min(1, max(0, progress))
        // A grounded, quiet shadow; no decorative animation while working.
        context.fill(Path(ellipseIn: CGRect(x: 57, y: 200, width: 90, height: 8)), with: .color(accent.opacity(0.07)))
        var trunk = Path()
        trunk.move(to: CGPoint(x: 91, y: 203))
        trunk.addCurve(to: CGPoint(x: 106, y: 90), control1: CGPoint(x: 110, y: 158), control2: CGPoint(x: 92, y: 137))
        trunk.addCurve(to: CGPoint(x: 104, y: 201), control1: CGPoint(x: 105, y: 144), control2: CGPoint(x: 110, y: 171))
        trunk.closeSubpath()
        context.fill(trunk, with: .linearGradient(Gradient(colors: [giltInk, secondaryInk]), startPoint: CGPoint(x: 90, y: 160), endPoint: CGPoint(x: 110, y: 160)))

        for branch in Self.branches {
            var path = Path()
            path.move(to: branch.root)
            path.addQuadCurve(to: branch.tip, control: branch.bend)
            context.stroke(path, with: .color(giltInk.opacity(0.76)), style: StrokeStyle(lineWidth: branch.width, lineCap: .round))
        }

        for leaf in Self.leaves {
            var local = context
            local.translateBy(x: leaf.x, y: leaf.y)
            local.rotate(by: .radians(leaf.angle))
            // The first leaves are always present. Subsequent leaves unfurl
            // progressively; unearned foliage never reads as completed work.
            let emergence = min(1, max(0, (growth - leaf.threshold) * 5))
            let leafScale = leaf.threshold < 0 ? 1 : 0.35 + emergence * 0.65
            local.scaleBy(x: leafScale, y: leafScale)
            local.opacity = leaf.threshold < 0 ? 0.85 : 0.10 + emergence * 0.90
            var shape = Path()
            shape.move(to: .zero)
            shape.addQuadCurve(to: CGPoint(x: leaf.length, y: 0), control: CGPoint(x: leaf.length * 0.5, y: -leaf.width))
            shape.addQuadCurve(to: .zero, control: CGPoint(x: leaf.length * 0.5, y: leaf.width * 0.82))
            let color = leaf.tone < 0.32 ? accent : (leaf.tone < 0.72 ? accentVivid : gilt)
            local.fill(shape, with: .linearGradient(Gradient(colors: [color, color.opacity(0.66)]), startPoint: .zero, endPoint: CGPoint(x: leaf.length, y: -leaf.width)))
            if leaf.length > 10 {
                var vein = Path()
                vein.move(to: CGPoint(x: 1, y: 0))
                vein.addLine(to: CGPoint(x: leaf.length * 0.82, y: 0))
                local.stroke(vein, with: .color(paper.opacity(0.24)), lineWidth: 0.45)
            }
        }

        var ground = Path()
        ground.move(to: CGPoint(x: 71, y: 204))
        ground.addQuadCurve(to: CGPoint(x: 132, y: 204), control: CGPoint(x: 103, y: 200))
        context.stroke(ground, with: .color(giltInk.opacity(0.26)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
    }

    private struct Branch {
        let root: CGPoint
        let bend: CGPoint
        let tip: CGPoint
        let width: CGFloat
    }

    private static let branches: [Branch] = [
        Branch(root: CGPoint(x: 101, y: 168), bend: CGPoint(x: 76, y: 135), tip: CGPoint(x: 43, y: 112), width: 3.2),
        Branch(root: CGPoint(x: 99, y: 149), bend: CGPoint(x: 119, y: 129), tip: CGPoint(x: 162, y: 107), width: 3),
        Branch(root: CGPoint(x: 101, y: 134), bend: CGPoint(x: 77, y: 110), tip: CGPoint(x: 66, y: 69), width: 2.4),
        Branch(root: CGPoint(x: 102, y: 123), bend: CGPoint(x: 120, y: 96), tip: CGPoint(x: 135, y: 58), width: 2.4),
        Branch(root: CGPoint(x: 102, y: 120), bend: CGPoint(x: 101, y:  70), tip: CGPoint(x: 92, y:  30), width: 2),
        Branch(root: CGPoint(x: 79, y: 140), bend: CGPoint(x:  70, y: 111), tip: CGPoint(x: 77, y:  90), width: 1.3),
        Branch(root: CGPoint(x: 127, y: 129), bend: CGPoint(x: 151, y: 130), tip: CGPoint(x: 176, y: 125), width: 1.2),
        Branch(root: CGPoint(x: 82, y: 112), bend: CGPoint(x: 57, y: 106), tip: CGPoint(x: 36, y:  80), width: 1.2),
        Branch(root: CGPoint(x: 117, y:  90), bend: CGPoint(x: 143, y:  80), tip: CGPoint(x: 159, y: 73), width: 1.1)
    ]

    private struct Leaf {
        let x: Double
        let y: Double
        let length: Double
        let width: Double
        let angle: Double
        let tone: Double
        let threshold: Double
    }

    private static let leaves: [Leaf] = {
        // Overlapping, asymmetric crowns leave apertures for the branches.
        let crowns: [(Double, Double, Double, Double)] = [
            (51,  90, 29, 30), (75,  60, 30, 31),
            (106,  42, 24, 27), (132,  70, 32,  30),
            (155, 102, 27, 31), (78, 116, 31, 23), (121, 108, 33, 27)
        ]
        var seed: UInt64 = 0xC05A0
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt64(1) << 31)
        }
        var result: [Leaf] = []
        for (cx, cy, rx, ry) in crowns {
            for index in 0..<50 {
                let angle = random() * .pi * 2
                let radius = sqrt(random())
                let x = cx + cos(angle) * rx * radius
                let y = cy + sin(angle) * ry * radius
                result.append(Leaf(x: x, y: y, length: 7 + random() * 9,
                                   width: 3 + random() * 3.5,
                                   angle: angle * 0.65 - .pi / 2,
                                   tone: random(), threshold: index % 5 == 0 ? -1 : random() * 0.8))
            }
        }
        return result.sorted { $0.y < $1.y }
    }()
}
