// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativeRecentPosts.swift
// Recent Posts - Post carousel with detail overlay
// Phase 4: Following SANCTUARY_UI_SPEC_V2.md section 3.2

import SwiftUI

// MARK: - Recent Posts Carousel

/// Horizontal carousel of recent content posts with performance metrics
public struct CreativeRecentPosts: View {

    // MARK: - Properties

    let posts: [ContentPost]
    let onPostTap: ((ContentPost) -> Void)?

    @State private var isVisible: Bool = false
    @State private var selectedFilter: ContentPlatform?

    // MARK: - Initialization

    public init(
        posts: [ContentPost],
        onPostTap: ((ContentPost) -> Void)? = nil
    ) {
        self.posts = posts
        self.onPostTap = onPostTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header with filter
            header

            // Posts carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SanctuaryLayout.Spacing.md) {
                    ForEach(Array(filteredPosts.enumerated()), id: \.element.id) { index, post in
                        RecentPostCard(
                            post: post,
                            animationDelay: Double(index) * 0.05,
                            onTap: { onPostTap?(post) }
                        )
                    }
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.lg)
                .padding(.vertical, SanctuaryLayout.Spacing.sm)
            }
        }
        .padding(.vertical, SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Recent Posts")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            Spacer()

            // Platform filter
            HStack(spacing: 2) {
                filterButton(nil, label: "All")

                ForEach(availablePlatforms, id: \.self) { platform in
                    filterButton(platform, label: platform.displayName)
                }
            }
            .padding(2)
            .background(SanctuaryColors.Glass.highlight)
            .clipShape(Capsule())
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.lg)
    }

    private func filterButton(_ platform: ContentPlatform?, label: String) -> some View {
        let isSelected = selectedFilter == platform

        return Button(action: {
            withAnimation(SanctuarySprings.snappy) {
                selectedFilter = platform
            }
        }) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? SanctuaryColors.Text.primary : SanctuaryColors.Text.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? SanctuaryColors.Dimensions.creative.opacity(0.2) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Computed Properties

    private var filteredPosts: [ContentPost] {
        guard let filter = selectedFilter else {
            return posts
        }
        return posts.filter { $0.platform == filter }
    }

    private var availablePlatforms: [ContentPlatform] {
        Array(Set(posts.map { $0.platform })).sorted { $0.rawValue < $1.rawValue }
    }
}

// MARK: - Recent Post Card

/// Individual post card showing thumbnail and metrics
public struct RecentPostCard: View {

    // MARK: - Properties

    let post: ContentPost
    let animationDelay: Double
    let onTap: () -> Void

    @State private var isVisible: Bool = false
    @State private var isHovered: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            // Thumbnail area
            thumbnailView

            // Content
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                // Title
                Text(post.title ?? "Untitled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .lineLimit(2)

                // Date
                Text(post.formattedDate)
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer(minLength: 4)

                // Metrics row
                metricsRow
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.bottom, SanctuaryLayout.Spacing.sm)
        }
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(
                            isHovered ? SanctuaryColors.Dimensions.creative.opacity(0.5) : SanctuaryColors.Glass.border,
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: isHovered ? SanctuaryColors.Dimensions.creative.opacity(0.2) : Color.clear, radius: 12)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onTap)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 15)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.1 + animationDelay)) {
                isVisible = true
            }
        }
    }

    // MARK: - Thumbnail

    private var thumbnailView: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder/thumbnail
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(
                    LinearGradient(
                        colors: [
                            post.platform.color.opacity(0.3),
                            post.platform.color.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 100)
                .overlay(
                    // Content type icon
                    Image(systemName: post.contentType.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(post.platform.color.opacity(0.6))
                )

            // Platform badge
            HStack(spacing: 4) {
                Image(systemName: post.platform.iconName)
                    .font(.system(size: 10))

                Text(post.platform.shortName)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(post.platform.color)
            )
            .padding(6)

            // Trending indicator
            if post.isTrending {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))

                    Text("Trending")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(SanctuaryColors.XP.primary)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(6)
            }
        }
    }

    // MARK: - Metrics Row

    private var metricsRow: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Reach
            HStack(spacing: 2) {
                Image(systemName: "eye")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(post.formattedReach)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Engagement
            HStack(spacing: 2) {
                Image(systemName: "hand.thumbsup")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(String(format: "%.1f%%", post.engagement))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Semantic.success)
            }

            Spacer()

            // Performance indicator
            performanceIndicator
        }
    }

    private var performanceIndicator: some View {
        let performance = post.performanceVsAverage

        return HStack(spacing: 2) {
            Image(systemName: performance >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .bold))

            Text("\(abs(Int(performance)))%")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(performance >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)
    }
}

// MARK: - Post Detail View

/// Detail overlay for a content post
public struct ContentPostDetailView: View {

    // MARK: - Properties

    let post: ContentPost
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SanctuaryLayout.Spacing.xl) {
                    // Hero metrics
                    heroMetrics

                    // Performance timeline
                    performanceTimeline

                    // Engagement breakdown
                    engagementBreakdown

                    // Insights
                    insightsSection

                    // Causal factors
                    if !post.causalFactors.isEmpty {
                        causalFactorsSection
                    }
                }
                .padding(SanctuaryLayout.Spacing.xl)
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

    // MARK: - Header

    private var header: some View {
        HStack {
            // Platform badge
            HStack(spacing: 6) {
                Image(systemName: post.platform.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(post.platform.color)

                Text(post.platform.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            Spacer()

            // Close button
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
    }

    // MARK: - Hero Metrics

    private var heroMetrics: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Title
            Text(post.title ?? "Untitled")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.primary)

            // Date
            Text("Posted \(post.formattedDate)")
                .font(.system(size: 12))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            // Metrics grid
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                metricBlock(
                    label: "Reach",
                    value: post.formattedReach,
                    icon: "eye",
                    color: SanctuaryColors.Dimensions.creative
                )

                metricBlock(
                    label: "Engagement",
                    value: String(format: "%.2f%%", post.engagement),
                    icon: "hand.thumbsup",
                    color: SanctuaryColors.Semantic.success
                )

                metricBlock(
                    label: "Likes",
                    value: formatNumber(post.likes),
                    icon: "heart.fill",
                    color: Color.red
                )

                metricBlock(
                    label: "Comments",
                    value: formatNumber(post.comments),
                    icon: "bubble.left.fill",
                    color: SanctuaryColors.Semantic.info
                )

                metricBlock(
                    label: "Shares",
                    value: formatNumber(post.shares),
                    icon: "arrow.turn.up.right",
                    color: SanctuaryColors.XP.primary
                )
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private func metricBlock(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: SanctuaryLayout.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Performance Timeline

    private var performanceTimeline: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Performance Over Time")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Placeholder for performance chart
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
                .frame(height: 120)
                .overlay(
                    Text("Performance chart")
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                )
        }
    }

    // MARK: - Engagement Breakdown

    private var engagementBreakdown: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Engagement Breakdown")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            HStack(spacing: SanctuaryLayout.Spacing.md) {
                engagementBar(label: "Likes", value: Double(post.likes), color: Color.red)
                engagementBar(label: "Comments", value: Double(post.comments), color: SanctuaryColors.Semantic.info)
                engagementBar(label: "Shares", value: Double(post.shares), color: SanctuaryColors.XP.primary)
                engagementBar(label: "Saves", value: Double(post.shares / 3), color: SanctuaryColors.Semantic.success)
            }
        }
    }

    private func engagementBar(label: String, value: Double, color: Color) -> some View {
        let maxValue = Double(max(post.likes, max(post.comments, post.shares)))
        let height = maxValue > 0 ? (value / maxValue) * 60 : 0

        return VStack(spacing: SanctuaryLayout.Spacing.xs) {
            Spacer()

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 24, height: height)

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Insights")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Performance vs average
            HStack {
                Image(systemName: post.performanceVsAverage >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(post.performanceVsAverage >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)

                Text("Performing \(abs(Int(post.performanceVsAverage)))% \(post.performanceVsAverage >= 0 ? "above" : "below") your average")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                Spacer()
            }
            .padding(SanctuaryLayout.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Glass.highlight)
            )

            // Trending status
            if post.isTrending {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("This post is currently trending!")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    Spacer()
                }
                .padding(SanctuaryLayout.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.XP.primary.opacity(0.15))
                )
            }
        }
    }

    // MARK: - Causal Factors

    private var causalFactorsSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Why It Worked")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            VStack(spacing: SanctuaryLayout.Spacing.sm) {
                ForEach(post.causalFactors) { factor in
                    CausalFactorRow(factor: factor)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// MARK: - Causal Factor Row

/// Row showing a causal factor for post performance
public struct CausalFactorRow: View {

    let factor: CausalFactor

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Category icon
            Image(systemName: factor.category.iconName)
                .font(.system(size: 12))
                .foregroundColor(factor.category.color)
                .frame(width: 24)

            // Factor name
            Text(factor.name)
                .font(.system(size: 12))
                .foregroundColor(SanctuaryColors.Text.primary)

            Spacer()

            // Impact
            HStack(spacing: 4) {
                Text(factor.impact > 0 ? "+" : "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(factor.impact >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)

                Text("\(Int(factor.impact))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(factor.impact >= 0 ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.error)

                Text("impact")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Confidence bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SanctuaryColors.Glass.highlight)
                    .frame(width: 40, height: 4)

                Capsule()
                    .fill(factor.category.color)
                    .frame(width: 40 * factor.confidence, height: 4)
            }
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }
}

// MARK: - Top Posts Grid

/// Grid layout for top performing posts
public struct CreativeTopPostsGrid: View {

    let posts: [ContentPost]
    let title: String
    let onPostTap: ((ContentPost) -> Void)?

    @State private var isVisible: Bool = false

    public init(
        posts: [ContentPost],
        title: String = "TOP PERFORMERS",
        onPostTap: ((ContentPost) -> Void)? = nil
    ) {
        self.posts = posts
        self.title = title
        self.onPostTap = onPostTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text(title)
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md),
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md),
                    GridItem(.flexible(), spacing: SanctuaryLayout.Spacing.md)
                ],
                spacing: SanctuaryLayout.Spacing.md
            ) {
                ForEach(Array(posts.prefix(6).enumerated()), id: \.element.id) { index, post in
                    TopPostCell(
                        post: post,
                        rank: index + 1,
                        onTap: { onPostTap?(post) }
                    )
                }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Top Post Cell

private struct TopPostCell: View {

    let post: ContentPost
    let rank: Int
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Rank badge
            Text("#\(rank)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 28)

            // Post info
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title ?? "Untitled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .lineLimit(1)

                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: post.platform.iconName)
                        .font(.system(size: 9))
                        .foregroundColor(post.platform.color)

                    Text(post.formattedReach)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            Spacer()

            // Engagement
            Text(String(format: "%.1f%%", post.engagement))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Semantic.success)
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .stroke(isHovered ? rankColor.opacity(0.5) : SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onTap)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(hex: "#FFD700") // Gold
        case 2: return Color(hex: "#C0C0C0") // Silver
        case 3: return Color(hex: "#CD7F32") // Bronze
        default: return SanctuaryColors.Text.tertiary
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CreativeRecentPosts_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                CreativeRecentPosts(
                    posts: CreativeDimensionData.preview.recentPosts
                )

                CreativeTopPostsGrid(
                    posts: CreativeDimensionData.preview.recentPosts
                )
                .padding()
            }
            .padding()
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}
#endif
