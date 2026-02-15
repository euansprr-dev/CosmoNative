// CosmoOS/UI/Plannerum/PlannerumView.swift
// Plannerum View - The Time Realm for temporal mastery
// Redesigned to match Sanctuary's immersive aesthetic

import SwiftUI
import Combine

// MARK: - Plannerum View

/// The Plannerum is the "Time Realm" - an immersive space matching Sanctuary's quality.
/// Users enter this cosmic command center where they are the master of their time.
public struct PlannerumView: View {

    // MARK: - State

    @State private var viewMode: PlannerumViewMode = .now
    @State private var selectedDate: Date = Date()
    @State private var selectedTimeBlock: ScheduleBlockViewModel?
    @State private var selectedInboxItem: UncommittedItemViewModel?

    // Animation state
    @State private var animationPhase: Double = 0
    @State private var isEntering = true
    @State private var animationTimerCancellable: AnyCancellable?
    @State private var xpBarAnimationProgress: CGFloat = 0
    @State private var livePulse: Bool = false

    // Staggered entry animation states (per plan: Animation Specifications)
    @State private var backgroundOpacity: Double = 0      // Background fades in (0.3s)
    @State private var headerOffset: CGFloat = -60        // Header slides from top (0.4s spring)
    @State private var headerOpacity: Double = 0
    @State private var sidebarOffset: CGFloat = -50       // Sidebar floats from left (0.5s spring, 0.1s delay)
    @State private var sidebarOpacity: Double = 0
    @State private var timelineOpacity: Double = 0        // Timeline fades up (0.4s, 0.2s delay)
    @State private var constellationOpacity: Double = 0   // Bottom constellation fades up

    // XP State
    @StateObject private var xpViewModel = PlannerumXPViewModel()

    // Plannerum ViewModel (for Now mode)
    @StateObject private var plannerumViewModel = PlannerumViewModel.shared

    // Deep Work Session Engine (used by SessionTimerBar overlay)
    @StateObject private var sessionEngine = DeepWorkSessionEngine()

    // Active Session Timer Manager (used by Now view hero — this is the real session source)
    @ObservedObject private var sessionManager = ActiveSessionTimerManager.shared

    // Keyboard shortcut state
    @State private var showNewTaskSheet = false

    // Callbacks
    let onDismiss: () -> Void

    // MARK: - Layout Constants

    private enum Layout {
        static let headerHeight: CGFloat = 120
        static let inboxRailWidth: CGFloat = PlannerumLayout.inboxRailWidth
        static let focusBarHeight: CGFloat = PlannerumLayout.focusBarHeight
        static let contentPadding: CGFloat = PlannerumLayout.contentPadding
        static let maxXPBarWidth: CGFloat = 400
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // LAYER 1: Base void background (always visible)
                PlannerumColors.voidPrimary
                    .ignoresSafeArea()

                // LAYER 2: Green/teal mist atmosphere (like Sanctuary but subtle green tint)
                ZStack {
                    // Primary teal/green mist - bottom-center glow
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.1, green: 0.8, blue: 0.6).opacity(0.08),
                            Color(red: 0.1, green: 0.6, blue: 0.5).opacity(0.04),
                            Color.clear
                        ]),
                        center: UnitPoint(x: 0.5, y: 0.7),
                        startRadius: 0,
                        endRadius: geometry.size.height * 0.6
                    )

                    // Secondary violet accent - top area (matches header)
                    RadialGradient(
                        gradient: Gradient(colors: [
                            PlannerumColors.primary.opacity(0.05),
                            Color.clear
                        ]),
                        center: UnitPoint(x: 0.3, y: 0.1),
                        startRadius: 0,
                        endRadius: geometry.size.width * 0.4
                    )

                    // Subtle teal mist drift - animated
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.15, green: 0.7, blue: 0.55).opacity(0.06),
                            Color.clear
                        ]),
                        center: UnitPoint(
                            x: 0.6 + sin(animationPhase * 0.1) * 0.1,
                            y: 0.5 + cos(animationPhase * 0.08) * 0.1
                        ),
                        startRadius: 50,
                        endRadius: geometry.size.width * 0.5
                    )
                }
                .ignoresSafeArea()
                .opacity(backgroundOpacity)

                // LAYER 3: Subtle ambient flow lines (fades with background)
                TimeFlowBackground(animationPhase: animationPhase)
                    .ignoresSafeArea()
                    .opacity(0.3 * backgroundOpacity)

                // Main content
                VStack(spacing: 0) {
                    // HEADER - slides from top (0.4s spring per plan)
                    sanctuaryStyleHeader
                        .offset(y: headerOffset)
                        .opacity(headerOpacity)

                    // View Mode Switcher (centered below header)
                    viewModeSwitcherBar
                        .offset(y: headerOffset * 0.5)
                        .opacity(headerOpacity)

                    // CONTENT AREA (Inbox Rail + Temporal Canvas) - minimal spacing
                    HStack(alignment: .top, spacing: 16) {
                        // LEFT: Floating Inbox Cards (no container, just cards)
                        InboxRailView(selectedItem: $selectedInboxItem)
                            .frame(width: 188) // Slightly wider to fit text
                            .offset(x: sidebarOffset)
                            .opacity(sidebarOpacity)

                        // MAIN: Temporal Canvas - expands to fill space
                        temporalCanvasView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(timelineOpacity)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)

                    // BOTTOM: Horizontal Focus Strip (full width, compact)
                    HorizontalFocusStrip()
                        .opacity(constellationOpacity)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }

                // SESSION TIMER BAR OVERLAY (floats above content)
                SessionTimerBar(engine: sessionEngine)

                // SESSION SUMMARY CARD OVERLAY (modal after session ends)
                if let result = sessionEngine.sessionResult {
                    SessionSummaryCard(result: result) { notes in
                        sessionEngine.dismissResult()
                    }
                    .transition(.opacity)
                    .animation(PlannerumSprings.expand, value: sessionEngine.sessionResult != nil)
                }
            }
        }
        .onAppear {
            // Staggered entry animation sequence per plan Animation Specifications
            performStaggeredEntryAnimation()
            startAnimationTimer()

            Task {
                await xpViewModel.loadXPData()
                // Load Plannerum data for Now mode
                await plannerumViewModel.refresh()
                plannerumViewModel.startLiveUpdates()
            }
        }
        .onDisappear {
            animationTimerCancellable?.cancel()
            animationTimerCancellable = nil
            plannerumViewModel.stopLiveUpdates()
        }
        .preferredColorScheme(.dark)
        // MARK: - Keyboard Shortcuts
        .background {
            // N = New task
            Button("") { showNewTaskSheet = true }
                .keyboardShortcut("n", modifiers: [])
                .hidden()

            // S = Start session on focus task
            Button("") {
                if let task = plannerumViewModel.focusNowTask?.task {
                    let sessionType = sessionTypeForIntent(task.intent)
                    sessionManager.startSession(
                        taskId: task.id,
                        taskTitle: task.title,
                        sessionType: sessionType,
                        targetMinutes: task.estimatedMinutes
                    )
                    plannerumViewModel.startSession(for: task)
                }
            }
            .keyboardShortcut("s", modifiers: [])
            .hidden()

            // Space = Toggle completion on first today task
            Button("") {
                if let firstTask = plannerumViewModel.todayTasks.first {
                    Task {
                        await plannerumViewModel.completeTask(taskId: firstTask.id)
                    }
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .hidden()

            // Cmd+Shift+D = Day view
            Button("") {
                withAnimation(PlannerumSprings.viewMode) { viewMode = .day }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .hidden()

            // Cmd+Shift+W = Week view
            Button("") {
                withAnimation(PlannerumSprings.viewMode) { viewMode = .week }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .hidden()

            // Cmd+Shift+Q = Quarter view
            Button("") {
                withAnimation(PlannerumSprings.viewMode) { viewMode = .quarter }
            }
            .keyboardShortcut("q", modifiers: [.command, .shift])
            .hidden()
        }
        .sheet(isPresented: $showNewTaskSheet) {
            QuickTaskSheet(onAdd: { title, intent, linkedIdeaUUID, linkedContentUUID, linkedAtomUUID, recurrenceJSON in
                Task {
                    await plannerumViewModel.quickAddTask(
                        title: title,
                        intent: intent,
                        linkedIdeaUUID: linkedIdeaUUID,
                        linkedContentUUID: linkedContentUUID,
                        linkedAtomUUID: linkedAtomUUID,
                        recurrenceJSON: recurrenceJSON
                    )
                }
                showNewTaskSheet = false
            }, onCancel: {
                showNewTaskSheet = false
            })
        }
    }

    // MARK: - Sanctuary-Style Header

    private var sanctuaryStyleHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left side - Title and level info
            VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
                // Title - matches Sanctuary exactly
                Text("PLANNERUM")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .tracking(4)

                // Level badge
                levelBadge

                // XP progress bar
                xpProgressBar
            }

            Spacer()

            // Right side - Live metrics panel
            liveMetricsPanel
        }
        .padding(.horizontal, PlannerumLayout.spacingXXL)
        .padding(.top, PlannerumLayout.spacingXL)
        .padding(.bottom, PlannerumLayout.spacingLG)
    }

    // MARK: - Level Badge

    private var levelBadge: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            Text("Level \(xpViewModel.level)")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(PlannerumColors.textPrimary)

            Text("•")
                .foregroundColor(PlannerumColors.textTertiary)

            Text(xpViewModel.rank)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(rankColor(for: xpViewModel.rank))
        }
    }

    // MARK: - XP Progress Bar

    private var xpProgressBar: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingXS) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PlannerumColors.glassBorder)
                        .frame(height: 8)

                    // Fill with shimmer
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [PlannerumColors.primary, PlannerumColors.primaryLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * min(xpBarAnimationProgress * CGFloat(xpViewModel.progressToNextLevel), 1.0),
                            height: 8
                        )
                        .shadow(color: PlannerumColors.primary.opacity(0.5), radius: 4, x: 0, y: 0)

                    // Shimmer effect
                    if xpViewModel.progressToNextLevel > 0 {
                        shimmerEffect(width: geometry.size.width, progress: xpViewModel.progressToNextLevel)
                    }
                }
            }
            .frame(height: 8)
            .frame(maxWidth: Layout.maxXPBarWidth)

            // XP text
            HStack {
                Text("XP: \(formatNumber(xpViewModel.xpForCurrentLevel)) / \(formatNumber(xpViewModel.xpRequiredForNextLevel)) to Level \(xpViewModel.level + 1)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(PlannerumColors.textTertiary)

                Spacer()

                Text("\(Int(xpViewModel.progressToNextLevel * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(PlannerumColors.primary)
            }
            .frame(maxWidth: Layout.maxXPBarWidth)
        }
    }

    // MARK: - Shimmer Effect

    private func shimmerEffect(width: CGFloat, progress: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0) / 2.0

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.3),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 60, height: 8)
                .offset(x: -30 + (width * CGFloat(progress) + 60) * CGFloat(phase))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .mask(
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: width * CGFloat(progress), height: 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                )
        }
    }

    // MARK: - Live Metrics Panel

    private var liveMetricsPanel: some View {
        VStack(alignment: .trailing, spacing: PlannerumLayout.spacingSM) {
            // Live indicator
            HStack(spacing: PlannerumLayout.spacingSM) {
                // Pulsing live dot
                Circle()
                    .fill(PlannerumColors.nowMarker)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(PlannerumColors.nowMarker.opacity(0.5), lineWidth: 2)
                            .scaleEffect(livePulse ? 2.0 : 1.0)
                            .opacity(livePulse ? 0 : 0.5)
                    )

                Text("LIVE")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(PlannerumColors.nowMarker)
            }

            // Metrics
            VStack(alignment: .trailing, spacing: PlannerumLayout.spacingXS) {
                metricRow(label: "Focus", value: "\(xpViewModel.focusScore)%", color: focusColor(xpViewModel.focusScore))
                metricRow(label: "Energy", value: "\(xpViewModel.energyLevel)%", color: energyColor(xpViewModel.energyLevel))
            }
        }
        .padding(PlannerumLayout.spacingLG)
        .background(PlannerumColors.glassPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PlannerumColors.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metricRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: PlannerumLayout.spacingMD) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PlannerumColors.textTertiary)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    // MARK: - View Mode Switcher Bar

    private var viewModeSwitcherBar: some View {
        HStack(spacing: 2) {
            ForEach(PlannerumViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(PlannerumSprings.viewMode) {
                        viewMode = mode
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11))
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(
                        viewMode == mode
                            ? PlannerumColors.textPrimary
                            : PlannerumColors.textMuted
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        viewMode == mode
                            ? PlannerumColors.primary.opacity(0.2)
                            : Color.clear
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(PlannerumColors.glassPrimary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
        .padding(.bottom, PlannerumLayout.spacingMD)
    }

    // MARK: - Temporal Canvas View

    @ViewBuilder
    private var temporalCanvasView: some View {
        switch viewMode {
        case .now:
            nowFocusLayout
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

        case .day:
            DayTimelineView(
                date: selectedDate,
                onDateChange: { newDate in
                    selectedDate = newDate
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

        case .week:
            WeekArcView(
                centerDate: selectedDate,
                onDaySelect: { date in
                    selectedDate = date
                    withAnimation(PlannerumSprings.viewMode) {
                        viewMode = .day
                    }
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

        case .month:
            MonthDensityView(
                centerDate: selectedDate,
                onDaySelect: { date in
                    selectedDate = date
                    withAnimation(PlannerumSprings.viewMode) {
                        viewMode = .day
                    }
                },
                onNavigateMonth: { offset in
                    if let newDate = Calendar.current.date(byAdding: .month, value: offset, to: selectedDate) {
                        withAnimation(PlannerumSprings.viewMode) {
                            selectedDate = newDate
                        }
                    }
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

        case .quarter:
            quarterView
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
    }

    // MARK: - Quarter View (Core Objectives)

    private var quarterView: some View {
        QuarterView()
    }

    // MARK: - Now Focus Layout (Session-Centric View)

    /// The Now view: active session hero + intent-based resources + right sidebar
    private var nowFocusLayout: some View {
        HStack(alignment: .top, spacing: PlannerumLayout.spacingXL) {
            // LEFT MAIN AREA: Active Session + Relevant Resources
            VStack(spacing: PlannerumLayout.spacingLG) {
                // TOP: Active Session Card or FocusNowCard
                nowHeroSection

                // MIDDLE: Relevant Resources Panel
                nowResourcesSection

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            // RIGHT SIDEBAR: Quests + Upcoming (fixed width)
            VStack(spacing: PlannerumLayout.spacingLG) {
                DailyQuestsPanel(
                    questEngine: plannerumViewModel.liveQuestEngine,
                    currentStreak: plannerumViewModel.xpProgress.streak
                )

                UpcomingSection(
                    upcomingDays: plannerumViewModel.upcomingDays,
                    onDayTap: { date in
                        selectedDate = date
                        withAnimation(PlannerumSprings.viewMode) {
                            viewMode = .day
                        }
                    },
                    onTaskTap: { _ in }
                )

                Spacer(minLength: 0)
            }
            .frame(width: DailyQuestsTokens.panelWidth)
        }
    }

    // MARK: - Now Hero Section (Active Session or Focus Now)

    @ViewBuilder
    private var nowHeroSection: some View {
        if let session = sessionManager.currentSession, sessionManager.state != .idle {
            activeSessionCard(session)
        } else {
            FocusNowCard(
                recommendation: plannerumViewModel.focusNowTask,
                contextMessage: plannerumViewModel.contextMessage,
                currentEnergy: plannerumViewModel.currentEnergy,
                currentFocus: plannerumViewModel.currentFocus,
                onStartSession: {
                    if let task = plannerumViewModel.focusNowTask?.task {
                        // Start the actual timer via ActiveSessionTimerManager
                        let sessionType = sessionTypeForIntent(task.intent)
                        sessionManager.startSession(
                            taskId: task.id,
                            taskTitle: task.title,
                            sessionType: sessionType,
                            targetMinutes: task.estimatedMinutes
                        )

                        // Route to the intent-specific workspace
                        plannerumViewModel.startSession(for: task)
                    }
                },
                onSkip: {
                    Task { await plannerumViewModel.skipFocusNow() }
                },
                onTaskTap: { _ in
                    selectedInboxItem = nil
                }
            )
        }
    }

    // MARK: - Active Session Card

    private func activeSessionCard(_ session: ActiveSession) -> some View {
        let sessionType = session.sessionType
        let accentColor = sessionTypeColor(sessionType)

        return VStack(spacing: 0) {
            HStack(spacing: PlannerumLayout.spacingLG) {
                // Left: Task info + timer
                VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
                    // Session type badge
                    sessionTypeBadge(sessionType)

                    // Task name — the REAL block title from the active session
                    Text(session.taskTitle)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(PlannerumColors.textPrimary)
                        .lineLimit(2)

                    // Live dimension routing label
                    activeSessionDimensionLabel(session)

                    // Elapsed timer — reads from the shared manager's live elapsed seconds
                    activeSessionTimerLabel
                }

                Spacer()

                // Right: Progress ring + controls
                VStack(spacing: PlannerumLayout.spacingMD) {
                    activeSessionProgressRing(session)
                    activeSessionControls(session)
                }
            }
            .padding(PlannerumLayout.spacingXL)
        }
        .background(activeSessionBackground(accentColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(0.15), radius: 20, y: 4)
    }

    @ViewBuilder
    private func intentBadgeLabel(_ intent: TaskIntent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: intent.iconName)
                .font(.system(size: 9, weight: .semibold))
            Text(intent.displayName)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(intent.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(intent.color.opacity(0.15))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func sessionTypeBadge(_ type: SessionType) -> some View {
        HStack(spacing: 6) {
            Image(systemName: type.iconName)
                .font(.system(size: 11, weight: .semibold))
            Text(type.displayName)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(sessionTypeColor(type))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(sessionTypeColor(type).opacity(0.15))
        .clipShape(Capsule())
    }

    private func sessionTypeColor(_ type: SessionType) -> Color {
        switch type {
        case .deepWork: return PlannerumColors.primary
        case .writing: return Color(red: 99/255, green: 102/255, blue: 241/255)
        case .creative: return Color(red: 245/255, green: 158/255, blue: 11/255)
        case .exercise: return PlannerumColors.nowMarker
        case .meditation: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .training: return Color(red: 236/255, green: 72/255, blue: 153/255)
        }
    }

    @ViewBuilder
    private func activeSessionDimensionLabel(_ session: ActiveSession) -> some View {
        let intent: TaskIntent = {
            if let taskId = session.taskId,
               let task = plannerumViewModel.todayTasks.first(where: { $0.id == taskId }) {
                return task.intent
            }
            return .general
        }()

        let allocations = DimensionXPRouter.routeXP(intent: intent, baseXP: 1)
        let dims = allocations.map { DimensionXPRouter.dimensionDisplayName($0.dimension) }
        let label = "XP \u{2192} " + dims.joined(separator: " & ")
        let rgb = DimensionXPRouter.dimensionColor(intent.dimension)
        let dimColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)

        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(dimColor)
    }

    private var activeSessionTimerLabel: some View {
        let elapsed = Int(sessionManager.elapsedSeconds)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let timeString = String(format: "%02d:%02d", minutes, seconds)

        return Text(timeString)
            .font(.system(size: 36, weight: .bold, design: .monospaced))
            .foregroundColor(PlannerumColors.textPrimary)
            .monospacedDigit()
    }

    @ViewBuilder
    private func activeSessionProgressRing(_ session: ActiveSession) -> some View {
        let progress = min(session.progress, 1.0)
        let progressColor: Color = progress >= 0.8
            ? PlannerumColors.nowMarker
            : progress >= 0.5
                ? Color(red: 234/255, green: 179/255, blue: 8/255)
                : sessionTypeColor(session.sessionType)

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 4)
                .frame(width: 56, height: 56)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 56, height: 56)

            VStack(spacing: 0) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(progressColor)
                Text("done")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)
            }
        }
    }

    @ViewBuilder
    private func activeSessionControls(_ session: ActiveSession) -> some View {
        HStack(spacing: 8) {
            // Pause / Resume
            Button(action: {
                if sessionManager.state == .running {
                    sessionManager.pauseSession()
                } else if sessionManager.state == .paused {
                    sessionManager.resumeSession()
                }
            }) {
                activeSessionPauseResumeLabel
            }
            .buttonStyle(.plain)

            // End
            Button(action: {
                sessionManager.endSession(completed: true)
            }) {
                activeSessionEndLabel
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var activeSessionPauseResumeLabel: some View {
        let isPaused = sessionManager.state == .paused
        Image(systemName: isPaused ? "play.fill" : "pause.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isPaused ? PlannerumColors.nowMarker : Color(red: 245/255, green: 158/255, blue: 11/255))
            .frame(width: 32, height: 32)
            .background(
                (isPaused ? PlannerumColors.nowMarker : Color(red: 245/255, green: 158/255, blue: 11/255)).opacity(0.15)
            )
            .clipShape(Circle())
    }

    @ViewBuilder
    private var activeSessionEndLabel: some View {
        Image(systemName: "stop.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(PlannerumColors.overdue)
            .frame(width: 32, height: 32)
            .background(PlannerumColors.overdue.opacity(0.15))
            .clipShape(Circle())
    }

    private func activeSessionBackground(_ accentColor: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 24/255, green: 24/255, blue: 42/255).opacity(0.95),
                            Color(red: 18/255, green: 18/255, blue: 32/255).opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Session type color glow
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(0.08), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
        }
    }

    // MARK: - Now Resources Section

    @ViewBuilder
    private var nowResourcesSection: some View {
        if let session = sessionManager.currentSession, sessionManager.state != .idle {
            // Active session: show context panel if the task has linked context
            if sessionHasLinkedContext(session) {
                NowViewContextPanel(session: session)
            } else {
                nowResourcesForSessionType(session.sessionType)
            }
        } else if let recommendation = plannerumViewModel.focusNowTask {
            // Pre-session: show context panel for the recommended task
            let task = recommendation.task
            if recommendedTaskHasContext(task) {
                NowViewContextPanel(task: task)
            } else if !scheduledUpNextTasks.isEmpty {
                nowUpNextSection
            } else {
                EmptyView() // Don't show "Your day is clear" when a recommendation is visible
            }
        } else if !scheduledUpNextTasks.isEmpty {
            nowUpNextSection
        } else {
            nowEmptyState
        }
    }

    /// Check whether the active session's task has linked idea/content/atom context
    private func sessionHasLinkedContext(_ session: ActiveSession) -> Bool {
        guard let taskId = session.taskId else { return false }
        if let task = plannerumViewModel.todayTasks.first(where: { $0.id == taskId }) {
            return recommendedTaskHasContext(task)
        }
        return false
    }

    /// Check whether a task view model has linked context worth showing
    private func recommendedTaskHasContext(_ task: TaskViewModel) -> Bool {
        let hasWrite = task.intent == .writeContent && (task.linkedIdeaUUID != nil || task.linkedContentUUID != nil)
        let hasResearch = task.intent == .research && task.linkedAtomUUID != nil
        let hasSwipes = task.intent == .studySwipes
        return hasWrite || hasResearch || hasSwipes
    }

    /// Tasks scheduled for today that haven't started yet, sorted by scheduled time
    private var scheduledUpNextTasks: [TaskViewModel] {
        Array(
            plannerumViewModel.todayTasks
                .filter { $0.scheduledStart != nil || $0.scheduledTime != nil }
                .sorted { ($0.scheduledStart ?? $0.scheduledTime ?? .distantFuture) < ($1.scheduledStart ?? $1.scheduledTime ?? .distantFuture) }
                .prefix(3)
        )
    }

    // MARK: - Resources for Intent

    @ViewBuilder
    private func nowResourcesForSessionType(_ type: SessionType) -> some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingMD) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(sessionTypeColor(type))
                Text("RELEVANT RESOURCES")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(PlannerumColors.textMuted)
                    .tracking(2)
                Spacer()
            }
            .padding(.horizontal, 4)

            nowResourceContent(type)
        }
    }

    @ViewBuilder
    private func nowResourceContent(_ type: SessionType) -> some View {
        switch type {
        case .writing:
            nowWriteContentResources
        case .training:
            nowResearchResources
        case .creative:
            nowSwipeResources
        default:
            nowUpNextSection
        }
    }

    @ViewBuilder
    private var nowWriteContentResources: some View {
        nowResourceCard(
            icon: "pencil.line",
            iconColor: TaskIntent.writeContent.color,
            title: "Writing Session Active",
            subtitle: "Open your linked idea or content draft in the Content workspace.",
            actionLabel: "Open Content",
            actionIcon: "arrow.right"
        )
    }

    @ViewBuilder
    private var nowResearchResources: some View {
        nowResourceCard(
            icon: "magnifyingglass",
            iconColor: TaskIntent.research.color,
            title: "Research Mode",
            subtitle: "Capture findings and build connections in the Research workspace.",
            actionLabel: "Open Research",
            actionIcon: "arrow.right"
        )
    }

    @ViewBuilder
    private var nowSwipeResources: some View {
        nowResourceCard(
            icon: "bolt.fill",
            iconColor: TaskIntent.studySwipes.color,
            title: "Swipe Study",
            subtitle: "Browse and analyze swipe files in the Swipe Gallery.",
            actionLabel: "Open Gallery",
            actionIcon: "arrow.right"
        )
    }

    @ViewBuilder
    private func nowResourceCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        actionLabel: String,
        actionIcon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingMD) {
            HStack(spacing: PlannerumLayout.spacingSM) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PlannerumColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(PlannerumColors.textTertiary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
        .padding(PlannerumLayout.spacingLG)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PlannerumColors.glassPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Up Next Section

    @ViewBuilder
    private var nowUpNextSection: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingMD) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PlannerumColors.textTertiary)
                Text("UP NEXT")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(PlannerumColors.textMuted)
                    .tracking(2)
                Spacer()
            }
            .padding(.horizontal, 4)

            if scheduledUpNextTasks.isEmpty {
                nowEmptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(scheduledUpNextTasks) { task in
                        nowUpNextRow(task)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nowUpNextRow(_ task: TaskViewModel) -> some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            // Time
            if let time = task.scheduledStart ?? task.scheduledTime {
                Text(PlannerumFormatters.time.string(from: time))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(PlannerumColors.textTertiary)
                    .frame(width: 44, alignment: .leading)
            }

            // Intent color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(task.intent.color)
                .frame(width: 3, height: 32)

            // Task info
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    intentBadgeLabel(task.intent)

                    if task.estimatedMinutes > 0 {
                        Text("\(task.estimatedMinutes)m")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(PlannerumColors.textMuted)
                    }
                }
            }

            Spacer()

            // Start button
            Button(action: {
                let sessionType = sessionTypeForIntent(task.intent)
                sessionManager.startSession(
                    taskId: task.id,
                    taskTitle: task.title,
                    sessionType: sessionType,
                    targetMinutes: task.estimatedMinutes
                )
                plannerumViewModel.startSession(for: task)
            }) {
                nowUpNextStartLabel
            }
            .buttonStyle(.plain)
        }
        .padding(PlannerumLayout.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var nowUpNextStartLabel: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(PlannerumColors.nowMarker)
            .frame(width: 28, height: 28)
            .background(PlannerumColors.nowMarker.opacity(0.15))
            .clipShape(Circle())
    }

    // MARK: - Empty State

    @ViewBuilder
    private var nowEmptyState: some View {
        VStack(spacing: PlannerumLayout.spacingMD) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(PlannerumColors.textMuted.opacity(0.5))

            Text("Your day is clear")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PlannerumColors.textSecondary)

            Text("Plan your day in the Day view, or start a quick session.")
                .font(.system(size: 12))
                .foregroundColor(PlannerumColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PlannerumLayout.spacingXXL)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(PlannerumColors.glassBorder.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Color Helpers

    private func rankColor(for rank: String) -> Color {
        switch rank.lowercased() {
        case "transcendent": return Color(red: 167/255, green: 139/255, blue: 250/255)
        case "pathfinder": return Color(red: 245/255, green: 158/255, blue: 11/255)
        case "architect": return Color(red: 99/255, green: 102/255, blue: 241/255)
        case "seeker": return Color(red: 34/255, green: 197/255, blue: 94/255)
        default: return PlannerumColors.textSecondary
        }
    }

    private func focusColor(_ score: Int) -> Color {
        switch score {
        case 0..<40: return Color(red: 239/255, green: 68/255, blue: 68/255)
        case 40..<70: return Color(red: 245/255, green: 158/255, blue: 11/255)
        default: return PlannerumColors.nowMarker
        }
    }

    private func energyColor(_ level: Int) -> Color {
        switch level {
        case 0..<30: return Color(red: 239/255, green: 68/255, blue: 68/255)
        case 30..<60: return Color(red: 245/255, green: 158/255, blue: 11/255)
        default: return PlannerumColors.nowMarker
        }
    }

    // MARK: - Intent to Session Type Mapping

    /// Maps a TaskIntent to a SessionType for the ActiveSessionTimerManager
    private func sessionTypeForIntent(_ intent: TaskIntent) -> SessionType {
        switch intent {
        case .writeContent: return .writing
        case .research: return .training
        case .studySwipes: return .creative
        case .deepThink: return .deepWork
        case .review: return .deepWork
        case .general, .custom: return .deepWork
        }
    }

    // MARK: - Formatting Helpers

    private func formatXP(_ xp: Int) -> String {
        if xp >= 10000 {
            return String(format: "%.1fk", Double(xp) / 1000.0)
        } else if xp >= 1000 {
            return String(format: "%.2fk", Double(xp) / 1000.0)
        }
        return "\(xp)"
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    // MARK: - Animation Helpers

    /// Performs the staggered entry animation per plan Animation Specifications:
    /// 1. Background gradient fades in (0.3s)
    /// 2. Header slides down from top (0.4s spring)
    /// 3. Sidebar floats in from left (0.5s spring, 0.1s delay)
    /// 4. Timeline fades up (0.4s, 0.2s delay)
    /// 5. Now bar draws in (0.3s, 0.4s delay) - handled by NowBarView
    /// 6. Blocks stagger in from now position (40ms between each) - handled by DayTimelineView
    private func performStaggeredEntryAnimation() {
        // 1. Background gradient fades in (0.3s)
        withAnimation(.easeOut(duration: 0.3)) {
            backgroundOpacity = 1.0
        }

        // 2. Header slides down from top (0.4s spring, slight delay)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.05)) {
            headerOffset = 0
            headerOpacity = 1.0
        }

        // 3. Sidebar floats in from left (0.5s spring, 0.1s delay)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
            sidebarOffset = 0
            sidebarOpacity = 1.0
        }

        // 4. Timeline fades up (0.4s, 0.2s delay)
        withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
            timelineOpacity = 1.0
        }

        // 5. Constellation fades up (0.3s, 0.35s delay)
        withAnimation(.easeOut(duration: 0.3).delay(0.35)) {
            constellationOpacity = 1.0
        }

        // XP bar animation (after header appears)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            animateXPBar()
            startLivePulse()
        }

        // Mark entering as complete
        isEntering = false
    }

    private func animateXPBar() {
        withAnimation(.easeOut(duration: 0.5)) {
            xpBarAnimationProgress = 1.0
        }
    }

    private func startLivePulse() {
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            livePulse = true
        }
    }

    private func startAnimationTimer() {
        animationTimerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                animationPhase += 0.05
            }
    }
}

// MARK: - Time Flow Background (Ambient Effect)

/// Subtle flowing lines that give the sense of time flowing through the space
struct TimeFlowBackground: View {
    let animationPhase: Double

    var body: some View {
        Canvas { context, size in
            // Draw subtle horizontal flow lines
            let lineCount = 8
            let lineSpacing = size.height / CGFloat(lineCount + 1)

            for i in 1...lineCount {
                let y = lineSpacing * CGFloat(i)
                let offset = sin(animationPhase * 0.5 + Double(i) * 0.3) * 20

                var path = Path()
                path.move(to: CGPoint(x: -50 + offset, y: y))

                // Create a gentle wave
                for x in stride(from: 0, to: size.width + 100, by: 50) {
                    let waveY = y + sin(Double(x) * 0.01 + animationPhase * 0.2 + Double(i)) * 5
                    path.addLine(to: CGPoint(x: x + offset, y: waveY))
                }

                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.02)),
                    lineWidth: 1
                )
            }
        }
    }
}

// MARK: - Plannerum View Mode

public enum PlannerumViewMode: String, CaseIterable {
    case now = "Now"
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"

    var icon: String {
        switch self {
        case .now: return "target"
        case .day: return "sun.max"
        case .week: return "calendar.day.timeline.leading"
        case .month: return "calendar"
        case .quarter: return "star.circle"
        }
    }
}

// MARK: - Plannerum XP View Model

@MainActor
public class PlannerumXPViewModel: ObservableObject {

    @Published public var level: Int = 1
    @Published public var totalXP: Int = 0
    @Published public var xpForCurrentLevel: Int = 0
    @Published public var xpRequiredForNextLevel: Int = 1000
    @Published public var rank: String = "Seeker"
    @Published public var focusScore: Int = 50
    @Published public var energyLevel: Int = 50

    public var progressToNextLevel: Double {
        guard xpRequiredForNextLevel > 0 else { return 0 }
        return min(Double(xpForCurrentLevel) / Double(xpRequiredForNextLevel), 1.0)
    }

    public func loadXPData() async {
        do {
            // Fetch level data from LevelStateStore or similar
            let xpEvents = try await AtomRepository.shared.fetchAll(type: .xpEvent)
                .filter { !$0.isDeleted }

            var total = 0
            for atom in xpEvents {
                if let metadata = atom.metadataValue(as: XPEventMetadataSimple.self) {
                    total += metadata.xpAmount ?? 0
                }
            }

            totalXP = total

            // Calculate level (simple formula: level = sqrt(totalXP / 100) + 1)
            level = max(1, Int(sqrt(Double(totalXP) / 100.0)) + 1)

            // XP thresholds
            let xpForThisLevel = (level - 1) * (level - 1) * 100
            let xpForNext = level * level * 100

            xpForCurrentLevel = totalXP - xpForThisLevel
            xpRequiredForNextLevel = xpForNext - xpForThisLevel

            // Calculate rank based on level
            rank = calculateRank(for: level)

            // Calculate focus and energy (placeholder - integrate with HealthKit later)
            focusScore = min(100, 40 + (level * 2))
            energyLevel = min(100, 50 + (level * 2))

        } catch {
            print("PlannerumXPViewModel: Failed to load XP data - \(error)")
        }
    }

    private func calculateRank(for level: Int) -> String {
        switch level {
        case 1...5: return "Seeker"
        case 6...15: return "Pathfinder"
        case 16...30: return "Architect"
        case 31...50: return "Transcendent"
        default: return "Transcendent"
        }
    }
}

// MARK: - Simple XP Metadata

private struct XPEventMetadataSimple: Codable {
    var xpAmount: Int?
}

// MARK: - Quick Task Sheet

/// Minimal sheet for keyboard-shortcut task creation.
/// Uses the unified 4x2 TaskIntentPicker grid with integrated linking.
struct QuickTaskSheet: View {
    let onAdd: (String, TaskIntent, String?, String?, String?, String?) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var selectedIntent: TaskIntent = .general
    @State private var linkedIdeaUUID: String = ""
    @State private var linkedAtomUUID: String = ""
    @State private var linkedContentUUID: String = ""
    @State private var intentTag: String = ""

    // Recurrence state
    @State private var isRecurrenceEnabled: Bool = false
    @State private var recurrenceJSON: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: PlannerumLayout.spacingLG) {
            // Header
            quickTaskHeader

            // Title field
            quickTaskTitleField

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

            // Add button
            quickTaskAddButton
        }
        .padding(24)
        .frame(width: 420)
        .background(PlannerumColors.voidPrimary)
        .onAppear { isFocused = true }
    }

    // MARK: - Header

    @ViewBuilder
    private var quickTaskHeader: some View {
        HStack {
            Text("New Task")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(PlannerumColors.textPrimary)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Title Field

    @ViewBuilder
    private var quickTaskTitleField: some View {
        TextField("Task title...", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(PlannerumColors.textPrimary)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .focused($isFocused)
            .onSubmit {
                submitTask()
            }
    }

    // MARK: - Add Button

    @ViewBuilder
    private var quickTaskAddButton: some View {
        HStack {
            Spacer()
            Button(action: { submitTask() }) {
                Text("Add Task")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(PlannerumColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Submit

    private func submitTask() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onAdd(
            title.trimmingCharacters(in: .whitespaces),
            selectedIntent,
            linkedIdeaUUID.isEmpty ? nil : linkedIdeaUUID,
            linkedContentUUID.isEmpty ? nil : linkedContentUUID,
            linkedAtomUUID.isEmpty ? nil : linkedAtomUUID,
            isRecurrenceEnabled ? recurrenceJSON : nil
        )
    }
}

// MARK: - Preview

#if DEBUG
struct PlannerumView_Previews: PreviewProvider {
    static var previews: some View {
        PlannerumView(onDismiss: {})
    }
}
#endif
