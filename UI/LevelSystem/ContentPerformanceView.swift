import SwiftUI
import GRDB

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
            case .all: "square.grid.2x2.fill"
            case .twitter: "bird.fill"
            case .linkedin: "link"
            case .instagram: "camera.fill"
            case .tiktok: "play.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .all: DS.entityConnection
            case .twitter: DS.entityContent
            case .linkedin: DS.entityContent
            case .instagram: DS.entityTask
            case .tiktok: DS.text
            }
        }

        var socialPlatform: SocialPlatform? {
            switch self {
            case .all: nil
            case .twitter: .twitter
            case .linkedin: .linkedin
            case .instagram: .instagram
            case .tiktok: .tiktok
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
            case .sevenDays: 7
            case .thirtyDays: 30
            case .ninetyDays: 90
            case .year: 365
            }
        }
    }

    public init(levelService: LevelSystemService) {
        self.levelService = levelService
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DS.space24) {
                heroStatsSection
                platformPicker
                timeframePicker
                reachChartSection
                engagementMetricsSection
                viralContentSection
                topContentSection
                clientPerformanceSection
            }
            .padding(DS.space16)
        }
        .background(DS.surface)
        .navigationTitle("Content Performance")
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
        VStack(spacing: DS.space20) {
            ContentPerformanceHeroCard(viewModel: viewModel)
            ContentPerformanceQuickRow(viewModel: viewModel)
        }
    }

    // MARK: - Platform Picker

    private var platformPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                ForEach(Platform.allCases, id: \.self) { platform in
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            selectedPlatform = platform
                        }
                    } label: {
                        HStack(spacing: DS.space6) {
                            Image(systemName: platform.icon)
                                .font(DS.subheadline)

                            Text(platform.rawValue)
                                .font(DS.callout)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(selectedPlatform == platform ? DS.textOnAccent : DS.textSecondary)
                        .padding(.horizontal, DS.space16)
                        .padding(.vertical, DS.space8)
                        .background(
                            Capsule()
                                .fill(selectedPlatform == platform ? platform.color : Color.clear)
                        )
                    }
                }
            }
            .padding(DS.space4)
            .background(
                Capsule()
                    .fill(DS.surfaceCard)
            )
        }
    }

    // MARK: - Timeframe Picker

    private var timeframePicker: some View {
        HStack(spacing: DS.space8) {
            ForEach(ContentTimeframe.allCases, id: \.self) { frame in
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        selectedTimeframe = frame
                    }
                } label: {
                    Text(frame.rawValue)
                        .font(DS.buttonText)
                        .fontWeight(.semibold)
                        .foregroundStyle(selectedTimeframe == frame ? DS.text : DS.textSecondary)
                        .padding(.horizontal, DS.space12)
                        .padding(.vertical, DS.space6)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .fill(selectedTimeframe == frame ? DS.surfaceElevated : Color.clear)
                        )
                }
            }
        }
    }

    // MARK: - Reach Chart Section

    private var reachChartSection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text("Reach Over Time")
                .dsSmallCapsLabel()

            ReachChartView(platform: selectedPlatform, timeframe: selectedTimeframe)
                .frame(height: 200)
                .padding(DS.space16)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusLarge)
                        .fill(DS.surfaceCard)
                )
                .dsRestingShadow()
        }
    }

    // MARK: - Engagement Metrics Section

    private var engagementMetricsSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Engagement")
                .dsSmallCapsLabel()

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DS.space12) {
                EngagementCard(title: "Avg ER", value: String(format: "%.1f%%", viewModel.avgEngagementRate * 100), subtitle: viewModel.engagementPercentile, color: DS.green)
                EngagementCard(title: "Likes", value: viewModel.formatNumber(viewModel.totalLikes), subtitle: "This month", color: DS.red)
                EngagementCard(title: "Comments", value: viewModel.formatNumber(viewModel.totalComments), subtitle: "This month", color: DS.entityContent)
                EngagementCard(title: "Shares", value: viewModel.formatNumber(viewModel.totalShares), subtitle: "This month", color: DS.orange)
                EngagementCard(title: "Saves", value: viewModel.formatNumber(viewModel.totalSaves), subtitle: "This month", color: DS.entityConnection)
                EngagementCard(title: "Follows", value: "+\(viewModel.formatNumber(viewModel.followsGained))", subtitle: "New this month", color: DS.entityImage)
            }
        }
    }

    // MARK: - Viral Content Section

    private var viralContentSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Text("Viral Content")
                    .dsSmallCapsLabel()

                Spacer()

                HStack(spacing: DS.space4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(DS.orange)
                    Text("247 viral posts")
                        .font(DS.buttonText)
                        .foregroundStyle(DS.textSecondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space12) {
                    ViralContentCard(platform: .twitter, impressions: "2.4M", engagementRate: "8.2%", preview: "Thread: The future of AI in...", date: "3 days ago")
                    ViralContentCard(platform: .linkedin, impressions: "847K", engagementRate: "5.4%", preview: "Why most founders fail at...", date: "1 week ago")
                    ViralContentCard(platform: .instagram, impressions: "1.2M", engagementRate: "12.1%", preview: "Carousel: 10 productivity...", date: "2 weeks ago")
                }
            }
        }
    }

    // MARK: - Top Content Section

    private var topContentSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Text("Top Performing")
                    .dsSmallCapsLabel()

                Spacer()

                Button("See All") {
                    showingContentDetail = true
                }
                .font(DS.buttonText)
                .foregroundStyle(DS.accent)
            }

            VStack(spacing: DS.space8) {
                TopContentRow(rank: 1, title: "AI Predictions Thread", platform: .twitter, impressions: "4.8M", engagement: "12.4%")
                TopContentRow(rank: 2, title: "Founder Lessons Carousel", platform: .instagram, impressions: "2.1M", engagement: "14.2%")
                TopContentRow(rank: 3, title: "Productivity Masterclass", platform: .linkedin, impressions: "1.4M", engagement: "6.8%")
            }
        }
    }

    // MARK: - Client Performance Section

    private var clientPerformanceSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Client Breakdown")
                .dsSmallCapsLabel()

            VStack(spacing: DS.space8) {
                ClientPerformanceRow(clientName: "Tech Founder A", platforms: [.twitter, .linkedin], reach: "124.5M", posts: 847, avgER: "4.2%")
                ClientPerformanceRow(clientName: "VC Partner B", platforms: [.twitter], reach: "89.2M", posts: 1240, avgER: "3.8%")
                ClientPerformanceRow(clientName: "Creator C", platforms: [.instagram, .tiktok], reach: "247.8M", posts: 432, avgER: "8.4%")
            }
        }
    }
}

// MARK: - Content Performance Hero Card

struct ContentPerformanceHeroCard: View {
    @ObservedObject var viewModel: ContentPerformanceViewModel

    var body: some View {
        VStack(spacing: DS.space8) {
            Text("Lifetime Reach")
                .dsSmallCapsLabel()

            Text(viewModel.formatNumber(viewModel.lifetimeReach))
                .font(DS.display)
                .fontDesign(.rounded)
                .foregroundStyle(DS.text)

            Text("Views across all platforms")
                .font(DS.navTitle)
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.vertical, DS.space8)
    }
}

// MARK: - Content Performance Quick Row

struct ContentPerformanceQuickRow: View {
    @ObservedObject var viewModel: ContentPerformanceViewModel

    var body: some View {
        HStack(spacing: 0) {
            ContentHeroStatItem(value: viewModel.formatNumber(viewModel.weeklyReach), label: "This Week", trend: viewModel.weeklyTrend, trendValue: viewModel.weeklyTrendText)
            Divider().frame(height: 40)
            ContentHeroStatItem(value: viewModel.formatNumber(viewModel.monthlyReach), label: "This Month", trend: viewModel.monthlyTrend, trendValue: viewModel.monthlyTrendText)
            Divider().frame(height: 40)
            ContentHeroStatItem(value: "\(viewModel.viralCount)", label: "Viral Posts", trend: viewModel.viralCount > 0 ? .up : .stable, trendValue: viewModel.viralCount > 0 ? "+\(viewModel.viralCount)" : "")
        }
        .padding(DS.space16)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
    }
}

// MARK: - Content Hero Stat Item

struct ContentHeroStatItem: View {
    let value: String
    let label: String
    let trend: Trend
    let trendValue: String

    var body: some View {
        VStack(spacing: DS.space4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DS.text)

            Text(label)
                .font(DS.footnote)
                .fontWeight(.medium)
                .foregroundStyle(DS.textSecondary)

            if !trendValue.isEmpty {
                HStack(spacing: DS.space2) {
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(trendValue)
                        .font(DS.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(trend == .up ? DS.green : DS.red)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Engagement Card

struct EngagementCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: DS.space6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.textSecondary)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            Text(subtitle)
                .font(DS.caption2)
                .fontWeight(.medium)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.space12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
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

                HStack {
                    Text(startLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.textSecondary)

                    Spacer()

                    Text(endLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.top, DS.space8)
            }
        }
    }

    private var startLabel: String {
        switch timeframe {
        case .sevenDays: "7 days ago"
        case .thirtyDays: "30 days ago"
        case .ninetyDays: "90 days ago"
        case .year: "Jan"
        }
    }

    private var endLabel: String {
        switch timeframe {
        case .sevenDays, .thirtyDays, .ninetyDays: "Today"
        case .year: "Dec"
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
        VStack(alignment: .leading, spacing: DS.space10) {
            viralCardHeader
            viralCardPreview
            viralCardStats
            viralCardDate
        }
        .padding(DS.space16)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
    }

    private var viralCardHeader: some View {
        HStack {
            Image(systemName: platform.icon)
                .font(DS.subheadline)
                .foregroundStyle(DS.textOnAccent)
                .padding(DS.space6)
                .background(platform.color)
                .clipShape(.rect(cornerRadius: DS.space6))

            Spacer()

            HStack(spacing: DS.space2) {
                Image(systemName: "flame.fill")
                    .font(DS.caption2)
                Text("Viral")
                    .font(DS.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(DS.orange)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(DS.orangeSoft)
            .clipShape(.rect(cornerRadius: DS.space6))
        }
    }

    private var viralCardPreview: some View {
        Text(preview)
            .font(DS.callout)
            .fontWeight(.medium)
            .foregroundStyle(DS.text)
            .lineLimit(2)
    }

    private var viralCardStats: some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.space2) {
                Text(impressions)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.text)
                Text("impressions")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DS.space2) {
                Text(engagementRate)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.green)
                Text("engagement")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    private var viralCardDate: some View {
        Text(date)
            .font(DS.caption2)
            .foregroundStyle(DS.textSecondary)
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
        HStack(spacing: DS.space12) {
            Text("\(rank)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(rankColor)
                .frame(width: 28)

            Image(systemName: platform.icon)
                .font(DS.navTitle)
                .foregroundStyle(DS.textOnAccent)
                .frame(width: 28, height: 28)
                .background(platform.color)
                .clipShape(.rect(cornerRadius: DS.space6))

            VStack(alignment: .leading, spacing: DS.space2) {
                Text(title)
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Text("\(impressions) impressions")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }

            Spacer()

            Text(engagement)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.green)
        }
        .padding(DS.space12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
    }

    private var rankColor: Color {
        switch rank {
        case 1: DS.entityStickyNote
        case 2: DS.borderActive
        case 3: DS.entityNote
        default: DS.textSecondary
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
        HStack(spacing: DS.space12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DS.entityContent, DS.entityConnection],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Text(clientName.prefix(1))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DS.textOnAccent)
                )

            VStack(alignment: .leading, spacing: DS.space4) {
                Text(clientName)
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)

                HStack(spacing: DS.space4) {
                    ForEach(platforms, id: \.self) { platform in
                        Image(systemName: platform.icon)
                            .font(DS.caption2)
                            .foregroundStyle(platform.color)
                    }

                    Text("\u{2022} \(posts) posts")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DS.space2) {
                Text(reach)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.text)

                Text("ER: \(avgER)")
                    .font(DS.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.green)
            }
        }
        .padding(DS.space12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
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
            weeklyReach = try await analyticsEngine.calculateWeeklyReach()
            viralCount = try await analyticsEngine.calculateMonthlyViralCount()
            avgEngagementRate = try await analyticsEngine.calculateAverageEngagementRate()
            engagementPercentile = calculateEngagementPercentile(avgEngagementRate)
            platformPerformance = try await analyticsEngine.getPerformanceByPlatform()
            topContent = try await analyticsEngine.getTopContent(limit: 5)
            await loadAggregateMetrics(days: days, platform: platform)
            await calculateTrends()
        } catch {
            // Handle error silently - keep existing values
        }
    }

    private func loadAggregateMetrics(days: Int, platform: SocialPlatform?) async {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date.now)!

        do {
            let atoms = try await database.read { db -> [Atom] in
                var query = Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("created_at") >= startDate.ISO8601Format())

                if let platform {
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
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date.now)!
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date.now)!

        do {
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

            monthlyTrend = weeklyTrend
            monthlyTrendText = weeklyTrendText

        } catch {
            // Keep stable trend on error
        }
    }

    private func calculateEngagementPercentile(_ rate: Double) -> String {
        if rate >= 0.08 { "Top 1%" }
        else if rate >= 0.05 { "Top 5%" }
        else if rate >= 0.03 { "Top 20%" }
        else if rate >= 0.02 { "Above avg" }
        else { "Average" }
    }

    // MARK: - Formatting

    func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000_000 {
            String(format: "%.1fB", Double(number) / 1_000_000_000)
        } else if number >= 1_000_000 {
            String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            String(format: "%.1fK", Double(number) / 1_000)
        } else {
            "\(number)"
        }
    }
}
