// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionDimensionView.swift
// Reflection Dimension View - "The Inner Sanctum" complete dimension experience
// Onyx Design System — premium cognitive atelier aesthetic

import SwiftUI

// MARK: - Reflection Dimension View

/// The complete Reflection Dimension view with all components
/// Layout: Emotional Landscape, Journaling Rhythm, Meditation, Themes, Grail Insights
public struct ReflectionDimensionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: ReflectionDimensionViewModel
    @StateObject private var dataProvider = ReflectionDataProvider()
    @State private var selectedTheme: ReflectionTheme?
    @State private var selectedInsight: GrailInsight?
    @State private var showThemeDetail: Bool = false
    @State private var showInsightDetail: Bool = false
    @State private var showMoodCheckIn: Bool = false
    @State private var showJournalSheet: Bool = false
    let onBack: () -> Void

    // MARK: - Initialization

    public init(
        data: ReflectionDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ReflectionDimensionViewModel(data: data))
        self.onBack = onBack
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            let useSingleColumn = geometry.size.width < Layout.twoColumnBreakpoint

            ZStack {
                // Background
                backgroundLayer

                // Main content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: OnyxLayout.metricGroupSpacing) {
                        // Header with back button
                        headerSection

                        // Emotional Landscape
                        EmotionalLandscapePanel(
                            currentState: viewModel.data.currentEmotionalState,
                            dataPoints: viewModel.data.emotionalDataPoints,
                            weekAverage: viewModel.data.weekAverageState,
                            trendDirection: viewModel.data.emotionalTrend,
                            moodTimeline: viewModel.data.todayMoodTimeline
                        )

                        journalingAndMeditationSection(useSingleColumn: useSingleColumn)

                        // Recurring Themes
                        RecurringThemesPanel(
                            themes: viewModel.data.themes,
                            topThemes: viewModel.topThemes,
                            emergingThemes: viewModel.emergingThemes,
                            fadingThemes: viewModel.fadingThemes,
                            onThemeTap: { theme in
                                selectedTheme = theme
                                showThemeDetail = true
                            }
                        )

                        // Grail Insights
                        GrailInsightsPanel(
                            insights: viewModel.data.grailInsights,
                            patterns: viewModel.data.insightPatterns,
                            predictions: viewModel.data.predictions,
                            totalInsights: viewModel.data.totalGrailInsights,
                            onInsightTap: { insight in
                                selectedInsight = insight
                                showInsightDetail = true
                            }
                        )

                        // Bottom spacer for safe area
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: Layout.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                // Detail overlays
                detailOverlays

                // Mood Check-In overlay
                if showMoodCheckIn {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { showMoodCheckIn = false }

                    MoodCheckInView(isPresented: $showMoodCheckIn) { valence, energy, note in
                        Task {
                            await dataProvider.recordMood(valence: valence, energy: energy, note: note)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // Journal Entry overlay
                if showJournalSheet {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { showJournalSheet = false }

                    JournalEntrySheet(isPresented: $showJournalSheet) { text, prompt in
                        Task {
                            await dataProvider.createJournalEntry(text: text, prompt: prompt)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .onAppear {
            Task {
                await dataProvider.refreshData()
                viewModel.data = dataProvider.data
            }
        }
        .onChange(of: dataProvider.data.journalStreak) { _ in
            viewModel.data = dataProvider.data
        }
    }

    private enum Layout {
        static let maxContentWidth: CGFloat = 1400
        static let twoColumnBreakpoint: CGFloat = 900
    }

    @ViewBuilder
    private func journalingAndMeditationSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                JournalingRhythmPanel(
                    currentStreak: viewModel.data.journalingStreak,
                    longestStreak: viewModel.data.longestJournalingStreak,
                    todayWordCount: viewModel.data.todayWordCount,
                    averageWordCount: viewModel.data.averageWordCount,
                    todayDepthScore: viewModel.data.todayDepthScore,
                    weeklyDepthData: viewModel.weeklyDepthData,
                    consistency: viewModel.data.journalingConsistency
                )
                .frame(maxWidth: .infinity)

                MeditationPanel(
                    todayMinutes: viewModel.data.todayMeditationMinutes,
                    goalMinutes: viewModel.data.meditationGoalMinutes,
                    currentStreak: viewModel.data.meditationStreak,
                    totalSessions: viewModel.data.totalMeditationSessions,
                    totalMinutes: viewModel.data.totalMeditationMinutes,
                    weeklyData: viewModel.data.weeklyMeditationData,
                    preferredTime: viewModel.data.preferredMeditationTime
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                JournalingRhythmPanel(
                    currentStreak: viewModel.data.journalingStreak,
                    longestStreak: viewModel.data.longestJournalingStreak,
                    todayWordCount: viewModel.data.todayWordCount,
                    averageWordCount: viewModel.data.averageWordCount,
                    todayDepthScore: viewModel.data.todayDepthScore,
                    weeklyDepthData: viewModel.weeklyDepthData,
                    consistency: viewModel.data.journalingConsistency
                )
                .frame(maxWidth: .infinity)

                MeditationPanel(
                    todayMinutes: viewModel.data.todayMeditationMinutes,
                    goalMinutes: viewModel.data.meditationGoalMinutes,
                    currentStreak: viewModel.data.meditationStreak,
                    totalSessions: viewModel.data.totalMeditationSessions,
                    totalMinutes: viewModel.data.totalMeditationMinutes,
                    weeklyData: viewModel.data.weeklyMeditationData,
                    preferredTime: viewModel.data.preferredMeditationTime
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Onyx base surface
            OnyxColors.Elevation.base
                .ignoresSafeArea()

            // Subtle reflection dimension tint — soft, meditative
            RadialGradient(
                colors: [
                    OnyxColors.DimensionVivid.reflection.opacity(0.06),
                    OnyxColors.DimensionVivid.reflection.opacity(0.02),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 700
            )
            .ignoresSafeArea()

            // Subtle lotus-inspired pattern
            ForEach(0..<8, id: \.self) { i in
                petalShape(index: i)
            }

            // Floating light particles (more subtle)
            ForEach(0..<15, id: \.self) { _ in
                Circle()
                    .fill(OnyxColors.Dimension.reflection.opacity(Double.random(in: 0.02...0.05)))
                    .frame(width: CGFloat.random(in: 3...8))
                    .position(
                        x: CGFloat.random(in: 0...1200),
                        y: CGFloat.random(in: 0...1000)
                    )
                    .blur(radius: 2)
            }

            // Subtle edge vignette
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.3)],
                center: .center,
                startRadius: 300,
                endRadius: 900
            )
            .ignoresSafeArea()
        }
    }

    private func petalShape(index: Int) -> some View {
        let angle = Double(index) * (360.0 / 8.0)
        let radius: CGFloat = 250

        return Ellipse()
            .fill(OnyxColors.Dimension.reflection.opacity(0.02))
            .frame(width: 100, height: 200)
            .rotationEffect(.degrees(angle))
            .offset(
                x: CGFloat(cos(angle * .pi / 180)) * radius * 0.3,
                y: CGFloat(sin(angle * .pi / 180)) * radius * 0.3
            )
            .blur(radius: 30)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center) {
            // Back button
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))

                    Text("Sanctuary")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(OnyxColors.Text.secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Title — sentence case, Onyx typography
            VStack(spacing: 2) {
                Text("Reflection")
                    .font(OnyxTypography.viewTitle)
                    .tracking(OnyxTypography.viewTitleTracking)
                    .foregroundColor(OnyxColors.Text.primary)

                HStack(spacing: 8) {
                    Text("The Inner Sanctum")
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Text.secondary)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Tier \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.reflection)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Sage")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.reflection)
                }
            }

            Spacer()

            // Quick actions
            HStack(spacing: 8) {
                quickActionButton(icon: "face.smiling", label: "Mood", action: { showMoodCheckIn = true })
                quickActionButton(icon: "book", label: "Journal", action: { showJournalSheet = true })
            }

            // Status indicator
            statusIndicator
        }
    }

    @ViewBuilder
    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(OnyxColors.Dimension.reflection)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(OnyxColors.Dimension.reflection.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private var statusIndicator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(OnyxColors.Accent.sage)
                    .frame(width: 6, height: 6)
                    .modifier(OnyxPulseModifier())

                Text("Mindful")
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.tertiary)
            }

            Text(viewModel.data.currentEmotionalState.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(OnyxColors.DimensionVivid.reflection)

            Text("\(viewModel.data.journalingStreak) day streak")
                .font(OnyxTypography.micro)
                .foregroundColor(OnyxColors.Text.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(.resting)
    }

    // MARK: - Detail Overlays

    @ViewBuilder
    private var detailOverlays: some View {
        // Theme detail
        if showThemeDetail, let theme = selectedTheme {
            overlayBackground
                .onTapGesture {
                    showThemeDetail = false
                }

            ThemeDetailPanel(
                theme: theme,
                relatedThemes: viewModel.relatedThemes(for: theme),
                journalExcerpts: [], // Would be loaded from journal entries
                onDismiss: { showThemeDetail = false }
            )
            .frame(maxWidth: 450)
            .transition(.scale.combined(with: .opacity))
        }

        // Insight detail
        if showInsightDetail, let insight = selectedInsight {
            overlayBackground
                .onTapGesture {
                    showInsightDetail = false
                }

            InsightDetailPanel(
                insight: insight,
                onDismiss: { showInsightDetail = false }
            )
            .frame(maxWidth: 500)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var overlayBackground: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .transition(.opacity)
    }
}

// MARK: - Onyx Pulse Modifier

@MainActor
private struct OnyxPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Reflection Dimension View Model

@MainActor
public final class ReflectionDimensionViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var data: ReflectionDimensionData
    @Published public var isLoading: Bool = false

    // MARK: - Computed Properties

    public var dimensionLevel: Int {
        // Would be loaded from CosmoLevelState
        18
    }

    public var topThemes: [ReflectionTheme] {
        data.themes.sorted { $0.frequency > $1.frequency }
    }

    public var emergingThemes: [ReflectionTheme] {
        data.themes.filter { $0.growthRate > 0.1 }
    }

    public var fadingThemes: [ReflectionTheme] {
        data.themes.filter { $0.growthRate < -0.1 }
    }

    public var weeklyDepthData: [DailyJournalDepth] {
        // Generate from actual data or create sample
        let calendar = Calendar.current
        let today = Date()
        let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today
            let isToday = offset == 6
            let hasEntry = Bool.random() || isToday
            return DailyJournalDepth(
                date: date,
                dayLabel: dayLabels[offset],
                depthScore: hasEntry ? Double.random(in: 4...9) : 0,
                wordCount: hasEntry ? Int.random(in: 150...600) : 0,
                hasEntry: hasEntry,
                isToday: isToday
            )
        }
    }

    // MARK: - Initialization

    public init(data: ReflectionDimensionData) {
        self.data = data
    }

    // MARK: - Actions

    public func refreshData() async {
        isLoading = true
        // Would load from SanctuaryDataProvider / reflection systems
        try? await Task.sleep(nanoseconds: 500_000_000)
        isLoading = false
    }

    public func relatedThemes(for theme: ReflectionTheme) -> [ReflectionTheme] {
        // Would calculate based on co-occurrence in journal entries
        data.themes.filter { $0.id != theme.id }.prefix(3).map { $0 }
    }

    public func logMood(emoji: String, valence: Double, energy: Double) {
        // TODO: Implement mood logging through ViewModel or DataProvider
        // This would save to the reflection tracking system
        // Currently a stub as data is immutable in the view
        print("[ReflectionDimensionView] Mood logged: \(emoji) valence=\(valence) energy=\(energy)")
    }

    private func moodLabel(valence: Double, energy: Double) -> String {
        if valence > 0.3 && energy > 0.3 { return "Excited" }
        if valence > 0.3 && energy < -0.3 { return "Content" }
        if valence < -0.3 && energy > 0.3 { return "Anxious" }
        if valence < -0.3 && energy < -0.3 { return "Melancholy" }
        return "Balanced"
    }
}

// MARK: - Compact Reflection View

/// Compact version for embedding in other views — Onyx design
public struct ReflectionDimensionCompact: View {

    let data: ReflectionDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: ReflectionDimensionData, onExpand: @escaping () -> Void) {
        self.data = data
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 16))
                        .foregroundColor(OnyxColors.Dimension.reflection)

                    Text("Reflection")
                        .font(OnyxTypography.cardTitle)
                        .tracking(OnyxTypography.cardTitleTracking)
                        .foregroundColor(OnyxColors.Text.primary)
                }

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 4) {
                        Text("Expand")
                            .font(.system(size: 11))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(OnyxColors.Dimension.reflection)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Current emotional state
            EmotionalLandscapeCompact(
                currentState: data.currentEmotionalState,
                trendDirection: data.emotionalTrend,
                onExpand: {}
            )

            // Journaling compact
            JournalingRhythmCompact(
                currentStreak: data.journalingStreak,
                todayWordCount: data.todayWordCount,
                consistency: data.journalingConsistency,
                onExpand: {}
            )

            // Meditation compact
            MeditationCompact(
                todayMinutes: data.todayMeditationMinutes,
                goalMinutes: data.meditationGoalMinutes,
                currentStreak: data.meditationStreak,
                onExpand: {}
            )
        }
        .padding(OnyxLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(isHovered ? .hovered : .resting)
        .animation(OnyxSpring.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ReflectionDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        ReflectionDimensionView(
            data: .preview,
            onBack: {}
        )
        .frame(minWidth: 1200, minHeight: 1000)
    }
}
#endif
