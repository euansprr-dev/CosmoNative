// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativeDimensionView.swift
// Creative Dimension View - "The Creator's Console" complete dimension experience
// Phase 4: Following SANCTUARY_UI_SPEC_V2.md section 3.2

import SwiftUI

// MARK: - Creative Dimension View

/// The complete Creative Dimension view with all components
/// Layout: Hero Metrics, Performance Graph, Posting Calendar, Recent Posts, Platform Breakdown
public struct CreativeDimensionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: CreativeDimensionViewModel
    @State private var selectedPost: ContentPost?
    @State private var selectedPostingDay: PostingDay?
    @State private var selectedPlatform: PlatformMetrics?
    @State private var showPostDetail: Bool = false
    @State private var showDayDetail: Bool = false
    @State private var showPlatformDetail: Bool = false

    let onBack: () -> Void

    // MARK: - Initialization

    public init(
        data: CreativeDimensionData = .preview,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CreativeDimensionViewModel(data: data))
        self.onBack = onBack
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Background
            backgroundLayer

            // Main content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SanctuaryLayout.Spacing.xxl) {
                    // Header with back button
                    headerSection

                    // Hero Metrics (full width)
                    CreativeHeroMetrics(data: viewModel.data)

                    // Performance Graph (full width)
                    CreativePerformanceGraph(
                        data: viewModel.data.performanceTimeSeries,
                        selectedRange: $viewModel.selectedTimeRange,
                        onPointTap: { point in
                            // Handle point tap - could show detail
                        }
                    )

                    // Middle section: Calendar + Streak
                    HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.xl) {
                        // Posting Calendar
                        CreativePostingCalendar(
                            postingDays: Array(viewModel.data.postingHistory.values),
                            currentStreak: viewModel.data.currentStreak,
                            bestPostingTime: viewModel.data.formattedBestTime,
                            mostActiveDay: viewModel.data.mostActiveDay,
                            averagePostsPerWeek: viewModel.data.averagePostsPerWeek,
                            onDayTap: { day in
                                selectedPostingDay = day
                                showDayDetail = true
                            }
                        )
                        .frame(maxWidth: .infinity)

                        // Streak and scheduling
                        VStack(spacing: SanctuaryLayout.Spacing.lg) {
                            CreativeStreakIndicator(
                                currentStreak: viewModel.data.currentStreak,
                                longestStreak: viewModel.data.longestStreak,
                                isActive: true
                            )

                            // Next scheduled posts
                            scheduledPostsCard

                            // Optimal windows
                            optimalWindowsCard
                        }
                        .frame(maxWidth: 320)
                    }

                    // Recent Posts carousel (full width)
                    CreativeRecentPosts(
                        posts: viewModel.data.recentPosts,
                        onPostTap: { post in
                            selectedPost = post
                            showPostDetail = true
                        }
                    )

                    // Bottom section: Platform Breakdown + Top Posts
                    HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.xl) {
                        // Platform Breakdown
                        CreativePlatformBreakdown(
                            platforms: viewModel.data.platformMetrics,
                            onPlatformTap: { platform in
                                selectedPlatform = platform
                                showPlatformDetail = true
                            }
                        )
                        .frame(maxWidth: .infinity)

                        // Top performers
                        VStack(spacing: SanctuaryLayout.Spacing.lg) {
                            CreativeTopPostsGrid(
                                posts: viewModel.data.topPerformers,
                                onPostTap: { post in
                                    selectedPost = post
                                    showPostDetail = true
                                }
                            )
                            .padding(SanctuaryLayout.Spacing.lg)
                            .background(
                                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                                    .fill(SanctuaryColors.Glass.background)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                                            .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                                    )
                            )

                            // Growth timeline
                            PlatformGrowthTimeline(
                                platforms: viewModel.data.platformMetrics
                            )
                        }
                        .frame(maxWidth: 400)
                    }

                    // Bottom spacer for safe area
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.xl)
                .padding(.top, SanctuaryLayout.Spacing.lg)
            }

            // Detail overlays
            detailOverlays
        }
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Base void
            SanctuaryColors.Background.void
                .ignoresSafeArea()

            // Creative dimension tint
            RadialGradient(
                colors: [
                    SanctuaryColors.Dimensions.creative.opacity(0.15),
                    SanctuaryColors.Dimensions.creative.opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()

            // Edge vignette
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.4)],
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
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Sanctuary")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(SanctuaryColors.Text.secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Title
            VStack(spacing: 2) {
                Text("CREATIVE")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .tracking(4)

                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Text("Creator's Console")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    Text("•")
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("Level \(viewModel.dimensionLevel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Dimensions.creative)
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
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .modifier(PulseModifier())

                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Text("Growth: \(String(format: "%.1f%%", viewModel.data.growthRate))/wk")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: viewModel.data.growthStatus.color))

            Text(viewModel.data.growthStatus.displayName)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Scheduled Posts Card

    private var scheduledPostsCard: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("SCHEDULED")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            if viewModel.data.scheduledPosts.isEmpty {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 16))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("No posts scheduled")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .padding(SanctuaryLayout.Spacing.md)
            } else {
                ForEach(viewModel.data.scheduledPosts.prefix(3)) { post in
                    scheduledPostRow(post)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
    }

    private func scheduledPostRow(_ post: ScheduledPost) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Platform icon
            Image(systemName: post.platform.iconName)
                .font(.system(size: 12))
                .foregroundColor(post.platform.color)
                .frame(width: 24)

            // Title and time
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .lineLimit(1)

                Text(post.formattedScheduledTime)
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()

            // Predicted performance
            if let prediction = post.predictedReach {
                Text("~\(formatNumber(prediction))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Semantic.info)
            }
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    // MARK: - Optimal Windows Card

    private var optimalWindowsCard: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("OPTIMAL WINDOWS")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            ForEach(viewModel.data.optimalWindows.prefix(3)) { window in
                optimalWindowRow(window)
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
    }

    private func optimalWindowRow(_ window: ContentWindow) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Platform icon
            Image(systemName: window.platform.iconName)
                .font(.system(size: 12))
                .foregroundColor(window.platform.color)
                .frame(width: 24)

            // Time range
            Text(window.formattedTimeRange)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)

            Spacer()

            // Predicted boost
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))

                Text("+\(Int(window.predictedBoost))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(SanctuaryColors.Semantic.success)

            // Confidence
            Text("(\(Int(window.confidence))%)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
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

// MARK: - Pulse Modifier

@MainActor
private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 1)
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

/// Detail view for a specific posting day
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundColor(statusColor)
                }

                Spacer()

                Button(action: {
                    withAnimation(SanctuarySprings.snappy) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(SanctuaryLayout.Spacing.lg)
            .background(SanctuaryColors.Glass.highlight)

            // Content
            if posts.isEmpty {
                VStack(spacing: SanctuaryLayout.Spacing.md) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("No posts on this day")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(SanctuaryLayout.Spacing.xl)
            } else {
                ScrollView {
                    VStack(spacing: SanctuaryLayout.Spacing.md) {
                        ForEach(posts) { post in
                            postSummaryRow(post)
                        }
                    }
                    .padding(SanctuaryLayout.Spacing.lg)
                }
            }
        }
        .frame(minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xl)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xl)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 30)
        .scaleEffect(isVisible ? 1 : 0.9)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SanctuarySprings.gentle) {
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
        case .posted: return SanctuaryColors.Dimensions.creative
        case .viral: return SanctuaryColors.XP.primary
        case .skipped: return SanctuaryColors.Semantic.error
        case .scheduled: return SanctuaryColors.Semantic.info
        case .rest: return SanctuaryColors.Text.tertiary
        case .future: return SanctuaryColors.Text.secondary
        }
    }

    private func postSummaryRow(_ post: ContentPost) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            Image(systemName: post.platform.iconName)
                .font(.system(size: 14))
                .foregroundColor(post.platform.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.title ?? "Untitled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .lineLimit(1)

                Text(post.formattedReach + " reach")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()

            Text(String(format: "%.1f%%", post.engagement))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Semantic.success)
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }
}

// MARK: - Platform Detail View

/// Detail view for platform-specific metrics
public struct PlatformDetailView: View {

    let metrics: PlatformMetrics
    let posts: [ContentPost]
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: metrics.platform.iconName)
                        .font(.system(size: 18))
                        .foregroundColor(metrics.platform.color)

                    Text(metrics.platform.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }

                Spacer()

                Button(action: {
                    withAnimation(SanctuarySprings.snappy) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(SanctuaryLayout.Spacing.lg)
            .background(SanctuaryColors.Glass.highlight)

            ScrollView {
                VStack(spacing: SanctuaryLayout.Spacing.xl) {
                    // Metrics grid
                    metricsGrid

                    // Recent posts on this platform
                    if !posts.isEmpty {
                        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
                            Text("RECENT POSTS")
                                .font(SanctuaryTypography.label)
                                .foregroundColor(SanctuaryColors.Text.tertiary)
                                .tracking(2)

                            ForEach(posts.prefix(5)) { post in
                                platformPostRow(post)
                            }
                        }
                    }
                }
                .padding(SanctuaryLayout.Spacing.lg)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xl)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.xl)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 30)
        .scaleEffect(isVisible ? 1 : 0.9)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SanctuarySprings.gentle) {
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
            spacing: SanctuaryLayout.Spacing.md
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
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private func platformPostRow(_ post: ContentPost) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title ?? "Untitled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .lineLimit(1)

                Text(post.formattedDate)
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(post.formattedReach)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text(String(format: "%.1f%%", post.engagement))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Semantic.success)
            }
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
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

/// Compact version for embedding in other views
public struct CreativeDimensionCompact: View {

    let data: CreativeDimensionData
    let onExpand: () -> Void

    @State private var isHovered: Bool = false

    public init(data: CreativeDimensionData, onExpand: @escaping () -> Void) {
        self.data = data
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(SanctuaryColors.Dimensions.creative)

                    Text("CREATIVE")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .tracking(2)
                }

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 4) {
                        Text("Expand")
                            .font(.system(size: 11))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(SanctuaryColors.Dimensions.creative)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Key metrics row
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
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
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(
                            isHovered ? SanctuaryColors.Dimensions.creative.opacity(0.5) : SanctuaryColors.Glass.border,
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func compactMetric(label: String, value: String, trend: Double?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(SanctuaryColors.Text.primary)

                if let trend = trend, trend != 0 {
                    Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(trend > 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
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
