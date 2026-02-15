// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativeDimensionView.swift
// Creative Dimension View - "The Creator's Console" complete dimension experience
// Onyx Design System — premium cognitive atelier aesthetic

import SwiftUI

// MARK: - Creative Dimension View

/// The complete Creative Dimension view with all components
/// Layout: Hero Metrics, Performance Graph, Posting Calendar, Recent Posts, Platform Breakdown
public struct CreativeDimensionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: CreativeDimensionViewModel
    @StateObject private var dataProvider = CreativeDimensionDataProvider()
    @State private var selectedPost: ContentPost?
    @State private var selectedPostingDay: PostingDay?
    @State private var selectedPlatform: PlatformMetrics?
    @State private var showPostDetail: Bool = false
    @State private var showDayDetail: Bool = false
    @State private var showPlatformDetail: Bool = false
    @State private var showSettings: Bool = false

    let onBack: () -> Void

    // MARK: - Initialization

    public init(
        data: CreativeDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CreativeDimensionViewModel(data: data))
        self.onBack = onBack
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            let useSingleColumn = geometry.size.width < Layout.twoColumnBreakpoint

            ZStack {
                // Background
                backgroundLayer

                if viewModel.data.isEmpty {
                    // Empty state
                    VStack {
                        headerSection
                            .padding(.horizontal, SanctuaryLayout.Spacing.xl)
                            .padding(.top, SanctuaryLayout.Spacing.lg)
                        Spacer()
                        PlaceholderCard(
                            state: .notConnected(
                                source: "Social Accounts",
                                description: "Social platform integration (Instagram, YouTube, TikTok, X) is coming soon. This will track your creative output and audience growth.",
                                connectAction: { }
                            ),
                            accentColor: SanctuaryColors.Dimensions.creative
                        )
                        .padding(.horizontal, 40)
                        Spacer()
                    }
                    .frame(maxWidth: Layout.maxContentWidth)
                    .frame(maxWidth: .infinity)
                } else {
                    // Main content
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: OnyxLayout.metricGroupSpacing) {
                            // Header with back button
                            headerSection

                            // Profile selector (if profiles exist)
                            if !dataProvider.clientProfiles.isEmpty {
                                profileSelector
                            }

                            // Hero Metrics (full width)
                            CreativeHeroMetrics(data: viewModel.data)

                            // Performance Graph (full width)
                            CreativePerformanceGraph(
                                data: viewModel.data.performanceTimeSeries,
                                selectedRange: $viewModel.selectedTimeRange,
                                onPointTap: { _ in }
                            )

                            // Pipeline Funnel
                            if !dataProvider.funnelData.isEmpty {
                                PipelineFunnelView(funnelData: dataProvider.funnelData)
                            }

                            calendarAndStreakSection(useSingleColumn: useSingleColumn)

                            // Recent Posts carousel (full width)
                            CreativeRecentPosts(
                                posts: viewModel.data.recentPosts,
                                onPostTap: { post in
                                    selectedPost = post
                                    showPostDetail = true
                                }
                            )

                            platformAndTopPostsSection(useSingleColumn: useSingleColumn)

                            // Bottom spacer for safe area
                            Spacer(minLength: 40)
                        }
                        .frame(maxWidth: Layout.maxContentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                    }
                }

                // Detail overlays
                detailOverlays
            }
        }
        .sheet(isPresented: $showSettings) {
            SanctuarySettingsView()
        }
        .onAppear {
            Task {
                await dataProvider.loadClientProfiles()
                await dataProvider.refreshData()
                if dataProvider.data.totalReach > 0 || !dataProvider.data.recentPosts.isEmpty {
                    viewModel.data = dataProvider.data
                }
            }
        }
        .onChange(of: dataProvider.selectedProfileUUID) { _, _ in
            Task {
                await dataProvider.refreshData()
                if dataProvider.data.totalReach > 0 || !dataProvider.data.recentPosts.isEmpty {
                    viewModel.data = dataProvider.data
                }
            }
        }
    }

    private enum Layout {
        static let maxContentWidth: CGFloat = 1400
        static let twoColumnBreakpoint: CGFloat = 900
    }

    @ViewBuilder
    private func calendarAndStreakSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                CreativePostingCalendar(
                    postingDays: Array(viewModel.data.postingHistory.values),
                    currentStreak: viewModel.data.currentStreak,
                    bestPostingTime: viewModel.data.formattedBestTime,
                    mostActiveDay: viewModel.data.mostActiveDay,
                    averagePostsPerWeek: viewModel.data.averagePostsPerWeek,
                    postsForDate: { date in
                        viewModel.data.recentPosts.filter {
                            Calendar.current.isDate($0.postedAt, inSameDayAs: date)
                        }
                    }
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    CreativeStreakIndicator(
                        currentStreak: viewModel.data.currentStreak,
                        longestStreak: viewModel.data.longestStreak,
                        isActive: true
                    )
                    .frame(maxWidth: .infinity)
                    scheduledPostsCard
                        .frame(maxWidth: .infinity)
                    optimalWindowsCard
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                CreativePostingCalendar(
                    postingDays: Array(viewModel.data.postingHistory.values),
                    currentStreak: viewModel.data.currentStreak,
                    bestPostingTime: viewModel.data.formattedBestTime,
                    mostActiveDay: viewModel.data.mostActiveDay,
                    averagePostsPerWeek: viewModel.data.averagePostsPerWeek,
                    postsForDate: { date in
                        viewModel.data.recentPosts.filter {
                            Calendar.current.isDate($0.postedAt, inSameDayAs: date)
                        }
                    }
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    CreativeStreakIndicator(
                        currentStreak: viewModel.data.currentStreak,
                        longestStreak: viewModel.data.longestStreak,
                        isActive: true
                    )
                    .frame(maxWidth: .infinity)
                    scheduledPostsCard
                        .frame(maxWidth: .infinity)
                    optimalWindowsCard
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func platformAndTopPostsSection(useSingleColumn: Bool) -> some View {
        if useSingleColumn {
            VStack(spacing: 16) {
                CreativePlatformBreakdown(
                    platforms: viewModel.data.platformMetrics,
                    onPlatformTap: { platform in
                        selectedPlatform = platform
                        showPlatformDetail = true
                    }
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    CreativeTopPostsGrid(
                        posts: viewModel.data.topPerformers,
                        onPostTap: { post in
                            selectedPost = post
                            showPostDetail = true
                        }
                    )
                    .padding(OnyxLayout.cardPadding)
                    .background(
                        RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                            .fill(OnyxColors.Elevation.raised)
                    )
                    .onyxShadow(.resting)
                    .frame(maxWidth: .infinity)

                    PlatformGrowthTimeline(platforms: viewModel.data.platformMetrics)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                CreativePlatformBreakdown(
                    platforms: viewModel.data.platformMetrics,
                    onPlatformTap: { platform in
                        selectedPlatform = platform
                        showPlatformDetail = true
                    }
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    CreativeTopPostsGrid(
                        posts: viewModel.data.topPerformers,
                        onPostTap: { post in
                            selectedPost = post
                            showPostDetail = true
                        }
                    )
                    .padding(OnyxLayout.cardPadding)
                    .background(
                        RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                            .fill(OnyxColors.Elevation.raised)
                    )
                    .onyxShadow(.resting)
                    .frame(maxWidth: .infinity)

                    PlatformGrowthTimeline(platforms: viewModel.data.platformMetrics)
                        .frame(maxWidth: .infinity)
                }
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

            // Subtle creative dimension tint
            RadialGradient(
                colors: [
                    OnyxColors.DimensionVivid.creative.opacity(0.08),
                    OnyxColors.DimensionVivid.creative.opacity(0.03),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()

            // Subtle edge vignette
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.3)],
                center: .center,
                startRadius: 300,
                endRadius: 800
            )
            .ignoresSafeArea()
        }
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
                Text("Creative")
                    .font(OnyxTypography.viewTitle)
                    .tracking(OnyxTypography.viewTitleTracking)
                    .foregroundColor(OnyxColors.Text.primary)

                HStack(spacing: 8) {
                    Text("Creator's Console")
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Text.secondary)

                    Text("·")
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("Tier \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OnyxColors.Dimension.creative)
                }
            }

            Spacer()

            // Live indicator
            liveIndicator
        }
    }

    private var liveIndicator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(OnyxColors.Accent.sage)
                    .frame(width: 6, height: 6)
                    .modifier(OnyxPulseModifier())

                Text("Live")
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.tertiary)
            }

            Text("Growth: \(String(format: "%.1f%%", viewModel.data.growthRate))/wk")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: viewModel.data.growthStatus.color))

            Text(viewModel.data.growthStatus.displayName)
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

    // MARK: - Profile Selector

    private var profileSelector: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 14))
                .foregroundColor(OnyxColors.Text.tertiary)

            Menu {
                Button(action: { dataProvider.selectedProfileUUID = nil }) {
                    Label("All Profiles", systemImage: dataProvider.selectedProfileUUID == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(dataProvider.clientProfiles, id: \.uuid) { profile in
                    Button(action: { dataProvider.selectedProfileUUID = profile.uuid }) {
                        Label(profile.name, systemImage: dataProvider.selectedProfileUUID == profile.uuid ? "checkmark" : "")
                    }
                }
            } label: {
                profileSelectorLabel
            }
            .menuStyle(BorderlessButtonMenuStyle())

            Spacer()
        }
    }

    @ViewBuilder
    private var profileSelectorLabel: some View {
        HStack(spacing: 6) {
            Text(selectedProfileName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OnyxColors.Text.primary)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(OnyxColors.Text.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OnyxColors.Elevation.raised)
        )
    }

    private var selectedProfileName: String {
        if let uuid = dataProvider.selectedProfileUUID,
           let profile = dataProvider.clientProfiles.first(where: { $0.uuid == uuid }) {
            return profile.name
        }
        return "All Profiles"
    }

    // MARK: - Scheduled Posts Card

    private var scheduledPostsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnyxSectionHeader("Scheduled")

            if viewModel.data.scheduledPosts.isEmpty {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 16))
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("No posts scheduled")
                        .font(.system(size: 12))
                        .foregroundColor(OnyxColors.Text.tertiary)
                }
                .padding(12)
            } else {
                ForEach(viewModel.data.scheduledPosts.prefix(3)) { post in
                    scheduledPostRow(post)
                }
            }
        }
        .padding(OnyxLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(.resting)
    }

    private func scheduledPostRow(_ post: ScheduledPost) -> some View {
        HStack(spacing: 12) {
            // Platform icon
            Image(systemName: post.platform.iconName)
                .font(.system(size: 12))
                .foregroundColor(post.platform.color)
                .frame(width: 24)

            // Title and time
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OnyxColors.Text.primary)
                    .lineLimit(1)

                Text(post.formattedScheduledTime)
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.tertiary)
            }

            Spacer()

            // Predicted performance
            if let prediction = post.predictedReach {
                Text("~\(formatNumber(prediction))")
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Accent.iris)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OnyxColors.Elevation.elevated)
        )
    }

    // MARK: - Optimal Windows Card

    private var optimalWindowsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnyxSectionHeader("Optimal Windows")

            ForEach(viewModel.data.optimalWindows.prefix(3)) { window in
                optimalWindowRow(window)
            }
        }
        .padding(OnyxLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(.resting)
    }

    private func optimalWindowRow(_ window: ContentWindow) -> some View {
        HStack(spacing: 12) {
            // Platform icon
            Image(systemName: window.platform.iconName)
                .font(.system(size: 12))
                .foregroundColor(window.platform.color)
                .frame(width: 24)

            // Time range
            Text(window.formattedTimeRange)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(OnyxColors.Text.primary)

            Spacer()

            // Predicted boost
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))

                Text("+\(Int(window.predictedBoost))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(OnyxColors.Accent.sage)

            // Confidence
            Text("(\(Int(window.confidence))%)")
                .font(OnyxTypography.micro)
                .foregroundColor(OnyxColors.Text.tertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OnyxColors.Elevation.elevated)
        )
    }

    // MARK: - Detail Overlays

    @ViewBuilder
    private var detailOverlays: some View {
        // Post detail
        if showPostDetail, let post = selectedPost {
            overlayBackground
                .onTapGesture {
                    showPostDetail = false
                }

            ContentPostDetailView(
                post: post,
                onDismiss: { showPostDetail = false }
            )
            .frame(maxWidth: 500)
            .transition(.scale.combined(with: .opacity))
        }

        // Day detail
        if showDayDetail, let day = selectedPostingDay {
            overlayBackground
                .onTapGesture {
                    showDayDetail = false
                }

            PostingDayDetailView(
                day: day,
                posts: viewModel.data.recentPosts.filter {
                    Calendar.current.isDate($0.postedAt, inSameDayAs: day.date)
                },
                onDismiss: { showDayDetail = false }
            )
            .frame(maxWidth: 400)
            .transition(.scale.combined(with: .opacity))
        }

        // Platform detail
        if showPlatformDetail, let platform = selectedPlatform {
            overlayBackground
                .onTapGesture {
                    showPlatformDetail = false
                }

            PlatformDetailView(
                metrics: platform,
                posts: viewModel.data.recentPosts.filter { $0.platform == platform.platform },
                onDismiss: { showPlatformDetail = false }
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

    // MARK: - Helpers

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return "\(value)"
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
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Creative Dimension View Model

@MainActor
public final class CreativeDimensionViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var data: CreativeDimensionData
    @Published public var isLoading: Bool = false
    @Published public var selectedTimeRange: CreativeTimeRange = .month

    // MARK: - Computed Properties

    public var dimensionLevel: Int {
        // Would be loaded from CosmoLevelState
        12
    }

    // MARK: - Initialization

    public init(data: CreativeDimensionData) {
        self.data = data
    }

    // MARK: - Actions

    public func refreshData() async {
        isLoading = true
        // Would load from SanctuaryDataProvider
        try? await Task.sleep(nanoseconds: 500_000_000)
        isLoading = false
    }
}

// MARK: - Posting Day Detail View

/// Detail view for a specific posting day — Onyx design
public struct PostingDayDetailView: View {

    let day: PostingDay
    let posts: [ContentPost]
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate)
                        .font(OnyxTypography.cardTitle)
                        .tracking(OnyxTypography.cardTitleTracking)
                        .foregroundColor(OnyxColors.Text.primary)

                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundColor(statusColor)
                }

                Spacer()

                Button(action: {
                    withAnimation(OnyxSpring.standard) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(OnyxColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(OnyxLayout.cardPadding)
            .background(OnyxColors.Elevation.elevated)

            // Content
            if posts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(OnyxColors.Text.tertiary)

                    Text("No posts on this day")
                        .font(OnyxTypography.body)
                        .foregroundColor(OnyxColors.Text.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(posts) { post in
                            postSummaryRow(post)
                        }
                    }
                    .padding(OnyxLayout.cardPadding)
                }
            }
        }
        .frame(minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(.floating)
        .scaleEffect(isVisible ? 1 : 0.9)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(OnyxSpring.cardEntrance) {
                isVisible = true
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: day.date)
    }

    private var statusText: String {
        switch day.status {
        case .posted: return "Posted"
        case .viral: return "Viral day!"
        case .skipped: return "Skipped"
        case .scheduled: return "Scheduled"
        case .rest: return "Rest day"
        case .future: return "Upcoming"
        }
    }

    private var statusColor: Color {
        switch day.status {
        case .posted: return OnyxColors.DimensionVivid.creative
        case .viral: return OnyxColors.Accent.amber
        case .skipped: return OnyxColors.Accent.rose
        case .scheduled: return OnyxColors.Accent.iris
        case .rest: return OnyxColors.Text.tertiary
        case .future: return OnyxColors.Text.secondary
        }
    }

    private func postSummaryRow(_ post: ContentPost) -> some View {
        HStack(spacing: 12) {
            Image(systemName: post.platform.iconName)
                .font(.system(size: 14))
                .foregroundColor(post.platform.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.title ?? "Untitled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OnyxColors.Text.primary)
                    .lineLimit(1)

                Text(post.formattedReach + " reach")
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.tertiary)
            }

            Spacer()

            Text(String(format: "%.1f%%", post.engagement))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(OnyxColors.Accent.sage)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OnyxColors.Elevation.elevated)
        )
    }
}

// MARK: - Platform Detail View

/// Detail view for platform-specific metrics — Onyx design
public struct PlatformDetailView: View {

    let metrics: PlatformMetrics
    let posts: [ContentPost]
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: metrics.platform.iconName)
                        .font(.system(size: 18))
                        .foregroundColor(metrics.platform.color)

                    Text(metrics.platform.displayName)
                        .font(OnyxTypography.cardTitle)
                        .tracking(OnyxTypography.cardTitleTracking)
                        .foregroundColor(OnyxColors.Text.primary)
                }

                Spacer()

                Button(action: {
                    withAnimation(OnyxSpring.standard) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(OnyxColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(OnyxLayout.cardPadding)
            .background(OnyxColors.Elevation.elevated)

            ScrollView {
                VStack(spacing: 24) {
                    // Metrics grid
                    metricsGrid

                    // Recent posts on this platform
                    if !posts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            OnyxSectionHeader("Recent Posts")

                            ForEach(posts.prefix(5)) { post in
                                platformPostRow(post)
                            }
                        }
                    }
                }
                .padding(OnyxLayout.cardPadding)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                .fill(OnyxColors.Elevation.raised)
        )
        .onyxShadow(.floating)
        .scaleEffect(isVisible ? 1 : 0.9)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(OnyxSpring.cardEntrance) {
                isVisible = true
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 12
        ) {
            metricCell(label: "Followers", value: formatNumber(metrics.followers))
            metricCell(label: "Avg Reach", value: formatNumber(metrics.averageReach))
            metricCell(label: "Engagement", value: String(format: "%.1f%%", metrics.engagementRate))
            metricCell(label: "Growth", value: String(format: "%+.1f%%", metrics.growth))
            metricCell(label: "Retention", value: String(format: "%.0f%%", metrics.retentionRate))
            metricCell(label: "Best Day", value: metrics.bestPostingDay.shortName)
        }
    }

    private func metricCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .light))
                .foregroundColor(OnyxColors.Text.primary)

            Text(label)
                .font(OnyxTypography.micro)
                .foregroundColor(OnyxColors.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OnyxColors.Elevation.elevated)
        )
    }

    private func platformPostRow(_ post: ContentPost) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title ?? "Untitled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OnyxColors.Text.primary)
                    .lineLimit(1)

                Text(post.formattedDate)
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Text.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(post.formattedReach)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(OnyxColors.Text.primary)

                Text(String(format: "%.1f%%", post.engagement))
                    .font(OnyxTypography.micro)
                    .foregroundColor(OnyxColors.Accent.sage)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OnyxColors.Elevation.elevated)
        )
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// MARK: - Compact Creative View

/// Compact version for embedding in other views — Onyx design
public struct CreativeDimensionCompact: View {

    let data: CreativeDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: CreativeDimensionData, onExpand: @escaping () -> Void) {
        self.data = data
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(OnyxColors.Dimension.creative)

                    Text("Creative")
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
                    .foregroundColor(OnyxColors.Dimension.creative)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Key metrics row
            HStack(spacing: 24) {
                compactMetric(
                    label: "Reach",
                    value: data.formattedReach,
                    trend: data.reachTrend
                )

                compactMetric(
                    label: "Engagement",
                    value: String(format: "%.1f%%", data.engagementRate),
                    trend: data.engagementTrend
                )

                compactMetric(
                    label: "Followers",
                    value: data.formattedFollowers,
                    trend: nil
                )

                compactMetric(
                    label: "Streak",
                    value: "\(data.currentStreak)d",
                    trend: nil
                )
            }

            // Mini calendar
            CreativeCalendarCompact(
                postingDays: Array(data.postingHistory.values),
                weeksToShow: 4
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

    private func compactMetric(label: String, value: String, trend: Double?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(OnyxTypography.micro)
                .foregroundColor(OnyxColors.Text.tertiary)

            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(OnyxColors.Text.primary)

                if let trend = trend, trend != 0 {
                    Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(trend > 0 ? OnyxColors.Accent.sage : OnyxColors.Accent.rose)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CreativeDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        CreativeDimensionView(
            data: .preview,
            onBack: {}
        )
        .frame(minWidth: 1200, minHeight: 900)
    }
}
#endif
