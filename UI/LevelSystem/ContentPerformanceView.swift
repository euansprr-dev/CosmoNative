import SwiftUI
import GRDB

// MARK: - Cross-Platform Colors

private extension Color {
    static var contentBackground: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    static var contentSecondaryBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    static var contentTertiaryBackground: Color {
        #if os(iOS)
        return Color(UIColor.tertiarySystemBackground)
        #else
        return Color(NSColor.underPageBackgroundColor)
        #endif
    }
}

// MARK: - Content Performance View

/// Detailed view for content performance metrics
/// Tracks reach, engagement, virality across platforms
/// **Atom-First:** All data flows from ContentPipelineService and Atom queries
public struct ContentPerformanceView: View {
    @ObservedObject var levelService: LevelSystemService
    @StateObject private var viewModel = ContentPerformanceViewModel()
    @State private var selectedPlatform: Platform = .all
    @State private var selectedTimeframe: ContentTimeframe = .thirtyDays
    @State private var showingContentDetail = false

    public enum Platform: String, CaseIterable {
        case all = "All"
        case twitter = "Twitter"
        case linkedin = "LinkedIn"
        case instagram = "Instagram"
        case tiktok = "TikTok"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .twitter: return "bird.fill"
            case .linkedin: return "link"
            case .instagram: return "camera.fill"
            case .tiktok: return "play.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .all: return .purple
            case .twitter: return .blue
            case .linkedin: return .blue
            case .instagram: return .pink
            case .tiktok: return .black
            }
        }

        var socialPlatform: SocialPlatform? {
            switch self {
            case .all: return nil
            case .twitter: return .twitter
            case .linkedin: return .linkedin
            case .instagram: return .instagram
            case .tiktok: return .tiktok
            }
        }
    }

    public enum ContentTimeframe: String, CaseIterable {
        case sevenDays = "7 Days"
        case thirtyDays = "30 Days"
        case ninetyDays = "90 Days"
        case year = "Year"

        var days: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .year: return 365
            }
        }
    }

    public init(levelService: LevelSystemService) {
        self.levelService = levelService
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Stats
                heroStatsSection

                // Platform Picker
                platformPicker

                // Timeframe Picker
                timeframePicker

                // Reach Chart
                reachChartSection

                // Engagement Metrics
                engagementMetricsSection

                // Viral Content
                viralContentSection

                // Top Performing Content
                topContentSection

                // Client Performance (if applicable)
                clientPerformanceSection
            }
            .padding()
        }
        .background(Color.contentBackground)
        .navigationTitle("Content Performance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await viewModel.loadData()
        }
        .onChange(of: selectedTimeframe) { _, newTimeframe in
            Task { await viewModel.loadData(days: newTimeframe.days) }
        }
        .onChange(of: selectedPlatform) { _, newPlatform in
            Task { await viewModel.loadData(platform: newPlatform.socialPlatform) }
        }
    }

    // MARK: - Hero Stats Section

    private var heroStatsSection: some View {
        VStack(spacing: 20) {
            // Total Reach
            VStack(spacing: 8) {
                Text("LIFETIME REACH")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Text(viewModel.formatNumber(viewModel.lifetimeReach))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Views across all platforms")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)

            // Quick Stats Row
            HStack(spacing: 0) {
                heroStatItem(
                    value: viewModel.formatNumber(viewModel.weeklyReach),
                    label: "This Week",
                    trend: viewModel.weeklyTrend,
                    trendValue: viewModel.weeklyTrendText
                )

                Divider()
                    .frame(height: 40)

                heroStatItem(
                    value: viewModel.formatNumber(viewModel.monthlyReach),
                    label: "This Month",
                    trend: viewModel.monthlyTrend,
                    trendValue: viewModel.monthlyTrendText
                )

                Divider()
                    .frame(height: 40)

                heroStatItem(
                    value: "\(viewModel.viralCount)",
                    label: "Viral Posts",
                    trend: viewModel.viralCount > 0 ? .up : .stable,
                    trendValue: viewModel.viralCount > 0 ? "+\(viewModel.viralCount)" : ""
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.contentSecondaryBackground)
            )
        }
    }

    private func heroStatItem(
        value: String,
        label: String,
        trend: Trend,
        trendValue: String
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if !trendValue.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(trendValue)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(trend == .up ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Platform Picker

    private var platformPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Platform.allCases, id: \.self) { platform in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPlatform = platform
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: platform.icon)
                                .font(.system(size: 12))

                            Text(platform.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(selectedPlatform == platform ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedPlatform == platform ? platform.color : Color.clear)
                        )
                    }
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color.contentSecondaryBackground)
            )
        }
    }

    // MARK: - Timeframe Picker

    private var timeframePicker: some View {
        HStack(spacing: 8) {
            ForEach(ContentTimeframe.allCases, id: \.self) { frame in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimeframe = frame
                    }
                } label: {
                    Text(frame.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selectedTimeframe == frame ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTimeframe == frame ? Color.contentTertiaryBackground : Color.clear)
                        )
                }
            }
        }
    }

    // MARK: - Reach Chart Section

    private var reachChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("REACH OVER TIME")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            ReachChartView(platform: selectedPlatform, timeframe: selectedTimeframe)
                .frame(height: 200)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.contentSecondaryBackground)
                )
        }
    }

    // MARK: - Engagement Metrics Section

    private var engagementMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ENGAGEMENT")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                engagementCard(
                    title: "Avg ER",
                    value: String(format: "%.1f%%", viewModel.avgEngagementRate * 100),
                    subtitle: viewModel.engagementPercentile,
                    color: .green
                )

                engagementCard(
                    title: "Likes",
                    value: viewModel.formatNumber(viewModel.totalLikes),
                    subtitle: "This month",
                    color: .red
                )

                engagementCard(
                    title: "Comments",
                    value: viewModel.formatNumber(viewModel.totalComments),
                    subtitle: "This month",
                    color: .blue
                )

                engagementCard(
                    title: "Shares",
                    value: viewModel.formatNumber(viewModel.totalShares),
                    subtitle: "This month",
                    color: .orange
                )

                engagementCard(
                    title: "Saves",
                    value: viewModel.formatNumber(viewModel.totalSaves),
                    subtitle: "This month",
                    color: .purple
                )

                engagementCard(
                    title: "Follows",
                    value: "+\(viewModel.formatNumber(viewModel.followsGained))",
                    subtitle: "New this month",
                    color: .cyan
                )
            }
        }
    }

    private func engagementCard(
        title: String,
        value: String,
        subtitle: String,
        color: Color
    ) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.contentSecondaryBackground)
        )
    }

    // MARK: - Viral Content Section

    private var viralContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VIRAL CONTENT")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("247 viral posts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ViralContentCard(
                        platform: .twitter,
                        impressions: "2.4M",
                        engagementRate: "8.2%",
                        preview: "Thread: The future of AI in...",
                        date: "3 days ago"
                    )

                    ViralContentCard(
                        platform: .linkedin,
                        impressions: "847K",
                        engagementRate: "5.4%",
                        preview: "Why most founders fail at...",
                        date: "1 week ago"
                    )

                    ViralContentCard(
                        platform: .instagram,
                        impressions: "1.2M",
                        engagementRate: "12.1%",
                        preview: "Carousel: 10 productivity...",
                        date: "2 weeks ago"
                    )
                }
            }
        }
    }

    // MARK: - Top Content Section

    private var topContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TOP PERFORMING")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Spacer()

                Button("See All") {
                    showingContentDetail = true
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                TopContentRow(
                    rank: 1,
                    title: "AI Predictions Thread",
                    platform: .twitter,
                    impressions: "4.8M",
                    engagement: "12.4%"
                )

                TopContentRow(
                    rank: 2,
                    title: "Founder Lessons Carousel",
                    platform: .instagram,
                    impressions: "2.1M",
                    engagement: "14.2%"
                )

                TopContentRow(
                    rank: 3,
                    title: "Productivity Masterclass",
                    platform: .linkedin,
                    impressions: "1.4M",
                    engagement: "6.8%"
                )
            }
        }
    }

    // MARK: - Client Performance Section

    private var clientPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT BREAKDOWN")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            VStack(spacing: 8) {
                ClientPerformanceRow(
                    clientName: "Tech Founder A",
                    platforms: [.twitter, .linkedin],
                    reach: "124.5M",
                    posts: 847,
                    avgER: "4.2%"
                )

                ClientPerformanceRow(
                    clientName: "VC Partner B",
                    platforms: [.twitter],
                    reach: "89.2M",
                    posts: 1240,
                    avgER: "3.8%"
                )

                ClientPerformanceRow(
                    clientName: "Creator C",
                    platforms: [.instagram, .tiktok],
                    reach: "247.8M",
                    posts: 432,
                    avgER: "8.4%"
                )
            }
        }
    }
}

// MARK: - Reach Chart View

struct ReachChartView: View {
    let platform: ContentPerformanceView.Platform
    let timeframe: ContentPerformanceView.ContentTimeframe

    var body: some View {
        GeometryReader { geometry in
            let data = generateData()
            let maxValue = data.max() ?? 1

            VStack(spacing: 0) {
                // Chart area
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(data.indices, id: \.self) { index in
                        let height = (data[index] / maxValue) * (geometry.size.height - 30)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [platform.color.opacity(0.6), platform.color],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: max(height, 2))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)

                // X-axis labels
                HStack {
                    Text(startLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(endLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    private var startLabel: String {
        switch timeframe {
        case .sevenDays: return "7 days ago"
        case .thirtyDays: return "30 days ago"
        case .ninetyDays: return "90 days ago"
        case .year: return "Jan"
        }
    }

    private var endLabel: String {
        switch timeframe {
        case .sevenDays, .thirtyDays, .ninetyDays: return "Today"
        case .year: return "Dec"
        }
    }

    private func generateData() -> [Double] {
        let count: Int
        switch timeframe {
        case .sevenDays: count = 7
        case .thirtyDays: count = 30
        case .ninetyDays: count = 90
        case .year: count = 12
        }

        return (0..<count).map { index in
            // Generate trending upward data with some variance
            let base = Double(index) / Double(count) * 100
            let variance = Double.random(in: -20...30)
            return max(10, base + variance)
        }
    }
}

// MARK: - Viral Content Card

struct ViralContentCard: View {
    let platform: ContentPerformanceView.Platform
    let impressions: String
    let engagementRate: String
    let preview: String
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Platform badge
            HStack {
                Image(systemName: platform.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(platform.color)
                    .cornerRadius(6)

                Spacer()

                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                    Text("Viral")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(6)
            }

            Text(preview)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(impressions)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("impressions")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(engagementRate)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Text("engagement")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Text(date)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.contentSecondaryBackground)
        )
    }
}

// MARK: - Top Content Row

struct TopContentRow: View {
    let rank: Int
    let title: String
    let platform: ContentPerformanceView.Platform
    let impressions: String
    let engagement: String

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 28)

            // Platform icon
            Image(systemName: platform.icon)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(platform.color)
                .cornerRadius(6)

            // Content info
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(impressions) impressions")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Engagement
            Text(engagement)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.green)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.contentSecondaryBackground)
        )
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .secondary
        }
    }
}

// MARK: - Client Performance Row

struct ClientPerformanceRow: View {
    let clientName: String
    let platforms: [ContentPerformanceView.Platform]
    let reach: String
    let posts: Int
    let avgER: String

    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Text(clientName.prefix(1))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    ForEach(platforms, id: \.self) { platform in
                        Image(systemName: platform.icon)
                            .font(.system(size: 10))
                            .foregroundColor(platform.color)
                    }

                    Text("• \(posts) posts")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(reach)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("ER: \(avgER)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.contentSecondaryBackground)
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ContentPerformanceView(levelService: LevelSystemService(database: CosmoDatabase.shared.dbQueue!))
    }
}

// MARK: - Content Performance ViewModel

/// ViewModel for ContentPerformanceView
/// Fetches all data from Atoms via ContentAnalyticsEngine
@MainActor
final class ContentPerformanceViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var lifetimeReach: Int = 0
    @Published var weeklyReach: Int = 0
    @Published var monthlyReach: Int = 0
    @Published var viralCount: Int = 0

    @Published var weeklyTrend: Trend = .stable
    @Published var monthlyTrend: Trend = .stable
    @Published var weeklyTrendText: String = ""
    @Published var monthlyTrendText: String = ""

    @Published var avgEngagementRate: Double = 0
    @Published var engagementPercentile: String = "Calculating..."

    @Published var totalLikes: Int = 0
    @Published var totalComments: Int = 0
    @Published var totalShares: Int = 0
    @Published var totalSaves: Int = 0
    @Published var followsGained: Int = 0

    @Published var topContent: [TopContentItem] = []
    @Published var viralContent: [ContentPerformanceMetadata] = []
    @Published var platformPerformance: [PlatformPerformance] = []

    @Published var isLoading: Bool = false

    // MARK: - Private

    private let analyticsEngine: ContentAnalyticsEngine
    private let database: any DatabaseWriter

    // MARK: - Initialization

    init(database: (any DatabaseWriter)? = nil) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
        self.analyticsEngine = ContentAnalyticsEngine(database: self.database)
    }

    // MARK: - Data Loading

    func loadData(days: Int = 30, platform: SocialPlatform? = nil) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load weekly reach
            weeklyReach = try await analyticsEngine.calculateWeeklyReach()

            // Load monthly viral count
            viralCount = try await analyticsEngine.calculateMonthlyViralCount()

            // Load average engagement
            avgEngagementRate = try await analyticsEngine.calculateAverageEngagementRate()

            // Calculate percentile
            engagementPercentile = calculateEngagementPercentile(avgEngagementRate)

            // Load platform breakdown
            platformPerformance = try await analyticsEngine.getPerformanceByPlatform()

            // Load top content
            topContent = try await analyticsEngine.getTopContent(limit: 5)

            // Calculate aggregates from performance atoms
            await loadAggregateMetrics(days: days, platform: platform)

            // Calculate trends
            await calculateTrends()

        } catch {
            // Handle error silently - keep existing values
        }
    }

    private func loadAggregateMetrics(days: Int, platform: SocialPlatform?) async {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        do {
            let atoms = try await database.read { db -> [Atom] in
                var query = Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("created_at") >= startDate.ISO8601Format())

                if let platform = platform {
                    query = query.filter(sql: "json_extract(metadata, '$.platform') = ?", arguments: [platform.rawValue])
                }

                return try query.fetchAll(db)
            }

            var likes = 0, comments = 0, shares = 0, saves = 0, follows = 0, totalReach = 0

            for atom in atoms {
                guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else { continue }

                likes += metadata.likes
                comments += metadata.comments
                shares += metadata.shares
                saves += metadata.saves
                follows += metadata.followsGained ?? 0
                totalReach += metadata.impressions
            }

            totalLikes = likes
            totalComments = comments
            totalShares = shares
            totalSaves = saves
            followsGained = follows
            monthlyReach = totalReach
            lifetimeReach = try await calculateLifetimeReach()

        } catch {
            // Keep existing values on error
        }
    }

    private func calculateLifetimeReach() async throws -> Int {
        try await database.read { db in
            let atoms = try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .fetchAll(db)

            return atoms.reduce(0) { total, atom in
                guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                    return total
                }
                return total + metadata.impressions
            }
        }
    }

    private func calculateTrends() async {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        do {
            // Get last week's reach
            let lastWeekReach = try await database.read { db -> Int in
                let atoms = try Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("created_at") >= twoWeeksAgo.ISO8601Format())
                    .filter(Column("created_at") < oneWeekAgo.ISO8601Format())
                    .fetchAll(db)

                return atoms.reduce(0) { total, atom in
                    guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                        return total
                    }
                    return total + metadata.impressions
                }
            }

            // Calculate trend
            if lastWeekReach > 0 {
                let ratio = Double(weeklyReach) / Double(lastWeekReach)
                if ratio > 1.1 {
                    weeklyTrend = .up
                    weeklyTrendText = "+\(Int((ratio - 1) * 100))%"
                } else if ratio < 0.9 {
                    weeklyTrend = .down
                    weeklyTrendText = "\(Int((ratio - 1) * 100))%"
                } else {
                    weeklyTrend = .stable
                    weeklyTrendText = ""
                }
            }

            // Similar for monthly
            monthlyTrend = weeklyTrend
            monthlyTrendText = weeklyTrendText

        } catch {
            // Keep stable trend on error
        }
    }

    private func calculateEngagementPercentile(_ rate: Double) -> String {
        if rate >= 0.08 { return "Top 1%" }
        if rate >= 0.05 { return "Top 5%" }
        if rate >= 0.03 { return "Top 20%" }
        if rate >= 0.02 { return "Above avg" }
        return "Average"
    }

    // MARK: - Formatting

    func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000_000 {
            return String(format: "%.1fB", Double(number) / 1_000_000_000)
        } else if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

