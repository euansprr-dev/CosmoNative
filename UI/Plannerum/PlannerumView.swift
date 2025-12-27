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

    @State private var viewMode: PlannerumViewMode = .day
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
            }
        }
        .onAppear {
            // Staggered entry animation sequence per plan Animation Specifications
            performStaggeredEntryAnimation()
            startAnimationTimer()

            Task {
                await xpViewModel.loadXPData()
            }
        }
        .onDisappear {
            animationTimerCancellable?.cancel()
            animationTimerCancellable = nil
        }
        .preferredColorScheme(.dark)
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
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"

    var icon: String {
        switch self {
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

// MARK: - Preview

#if DEBUG
struct PlannerumView_Previews: PreviewProvider {
    static var previews: some View {
        PlannerumView(onDismiss: {})
    }
}
#endif
