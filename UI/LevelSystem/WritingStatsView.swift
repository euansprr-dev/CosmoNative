import SwiftUI

// MARK: - Cross-Platform Colors

private extension Color {
    static var writingBackground: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    static var writingSecondaryBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
}

// MARK: - Writing Stats View

/// Detailed view for writing performance metrics
/// Tracks words written, sessions, streaks, and trends
public struct WritingStatsView: View {
    @ObservedObject var levelService: LevelSystemService
    @State private var selectedTimeframe: TimeFrame = .week
    @State private var showingSessionHistory = false

    public enum TimeFrame: String, CaseIterable {
        case day = "Today"
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    public init(levelService: LevelSystemService) {
        self.levelService = levelService
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Stats
                heroStatsSection

                // Timeframe Picker
                timeframePicker

                // Word Count Chart
                wordCountChartSection

                // Session Stats
                sessionStatsSection

                // Writing Streaks
                writingStreakSection

                // Recent Sessions
                recentSessionsSection

                // Milestones
                milestonesSection
            }
            .padding()
        }
        .background(Color.writingBackground)
        .navigationTitle("Writing Stats")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Hero Stats Section

    private var heroStatsSection: some View {
        VStack(spacing: 20) {
            // Lifetime Words
            VStack(spacing: 8) {
                Text("LIFETIME WORDS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Text("1,247,832")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Prolific Writer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                    )
            }
            .padding(.vertical, 8)

            // Quick Stats Row
            HStack(spacing: 0) {
                quickStatItem(
                    value: "2,450",
                    label: "Today",
                    trend: .up,
                    trendValue: "+15%"
                )

                Divider()
                    .frame(height: 40)

                quickStatItem(
                    value: "12,847",
                    label: "This Week",
                    trend: .up,
                    trendValue: "+8%"
                )

                Divider()
                    .frame(height: 40)

                quickStatItem(
                    value: "48,291",
                    label: "This Month",
                    trend: .stable,
                    trendValue: ""
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.writingSecondaryBackground)
            )
        }
    }

    private func quickStatItem(
        value: String,
        label: String,
        trend: WritingTrend,
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

    // MARK: - Timeframe Picker

    private var timeframePicker: some View {
        HStack(spacing: 8) {
            ForEach(TimeFrame.allCases, id: \.self) { frame in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimeframe = frame
                    }
                } label: {
                    Text(frame.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selectedTimeframe == frame ? .white : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedTimeframe == frame ? Color.blue : Color.clear)
                        )
                }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.writingSecondaryBackground)
        )
    }

    // MARK: - Word Count Chart Section

    private var wordCountChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WORD COUNT")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            // Chart
            WordCountChartView(timeframe: selectedTimeframe)
                .frame(height: 200)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.writingSecondaryBackground)
                )
        }
    }

    // MARK: - Session Stats Section

    private var sessionStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SESSION STATS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                sessionStatCard(
                    title: "Avg Words/Session",
                    value: "847",
                    icon: "doc.text.fill",
                    color: .blue
                )

                sessionStatCard(
                    title: "Avg WPM",
                    value: "52",
                    icon: "speedometer",
                    color: .green
                )

                sessionStatCard(
                    title: "Peak WPM",
                    value: "78",
                    icon: "flame.fill",
                    color: .orange
                )

                sessionStatCard(
                    title: "Total Sessions",
                    value: "1,423",
                    icon: "square.stack.3d.up.fill",
                    color: .purple
                )
            }
        }
    }

    private func sessionStatCard(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Spacer()

            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.writingSecondaryBackground)
        )
    }

    // MARK: - Writing Streak Section

    private var writingStreakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WRITING STREAK")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            HStack(spacing: 16) {
                // Current Streak
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.orange)

                        Text("47")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    Text("Current Streak")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.writingSecondaryBackground)
                )

                // Best Streak
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.yellow)

                        Text("124")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    Text("Best Streak")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.writingSecondaryBackground)
                )
            }

            // Weekly writing heatmap
            WeeklyHeatmapView()
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.writingSecondaryBackground)
                )
        }
    }

    // MARK: - Recent Sessions Section

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT SESSIONS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Spacer()

                Button("See All") {
                    showingSessionHistory = true
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                WritingSessionRowView(
                    project: "Blog Post: AI Trends",
                    words: 1247,
                    duration: "45 min",
                    time: "2 hours ago"
                )

                WritingSessionRowView(
                    project: "Newsletter Draft",
                    words: 892,
                    duration: "32 min",
                    time: "Yesterday"
                )

                WritingSessionRowView(
                    project: "Client Article",
                    words: 2103,
                    duration: "1h 12min",
                    time: "Yesterday"
                )
            }
        }
    }

    // MARK: - Milestones Section

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MILESTONES")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            VStack(spacing: 8) {
                MilestoneRowView(
                    title: "500K Words",
                    progress: 1.0,
                    isComplete: true,
                    date: "Achieved Dec 2024"
                )

                MilestoneRowView(
                    title: "1M Words",
                    progress: 1.0,
                    isComplete: true,
                    date: "Achieved Nov 2025"
                )

                MilestoneRowView(
                    title: "2M Words",
                    progress: 0.62,
                    isComplete: false,
                    date: "752,168 to go"
                )

                MilestoneRowView(
                    title: "5M Words",
                    progress: 0.25,
                    isComplete: false,
                    date: "3,752,168 to go"
                )
            }
        }
    }
}

// MARK: - Word Count Chart View

struct WordCountChartView: View {
    let timeframe: WritingStatsView.TimeFrame

    // Sample data - would be real data in production
    private var chartData: [ChartDataPoint] {
        switch timeframe {
        case .day:
            return [
                ChartDataPoint(label: "6AM", value: 0),
                ChartDataPoint(label: "9AM", value: 420),
                ChartDataPoint(label: "12PM", value: 850),
                ChartDataPoint(label: "3PM", value: 1200),
                ChartDataPoint(label: "6PM", value: 1850),
                ChartDataPoint(label: "9PM", value: 2450),
            ]
        case .week:
            return [
                ChartDataPoint(label: "Mon", value: 2100),
                ChartDataPoint(label: "Tue", value: 1850),
                ChartDataPoint(label: "Wed", value: 2400),
                ChartDataPoint(label: "Thu", value: 1200),
                ChartDataPoint(label: "Fri", value: 2800),
                ChartDataPoint(label: "Sat", value: 500),
                ChartDataPoint(label: "Sun", value: 1997),
            ]
        case .month:
            return (1...30).map { day in
                ChartDataPoint(
                    label: "\(day)",
                    value: Double.random(in: 800...3000)
                )
            }
        case .year:
            return ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].map { month in
                ChartDataPoint(
                    label: month,
                    value: Double.random(in: 30000...60000)
                )
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let maxValue = chartData.map(\.value).max() ?? 1
            let barWidth = (geometry.size.width - CGFloat(chartData.count - 1) * 4) / CGFloat(chartData.count)

            VStack(spacing: 8) {
                // Bars
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(chartData.indices, id: \.self) { index in
                        let point = chartData[index]
                        let height = (point.value / maxValue) * (geometry.size.height - 30)

                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: max(barWidth, 8), height: max(height, 4))

                            if timeframe == .week || timeframe == .day {
                                Text(point.label)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

// MARK: - Weekly Heatmap View

struct WeeklyHeatmapView: View {
    private let weeks = 12
    private let daysPerWeek = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 12 Weeks")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 3) {
                // Day labels
                VStack(spacing: 3) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14)
                    }
                }

                // Grid
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<daysPerWeek, id: \.self) { day in
                            let intensity = Double.random(in: 0...1)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(intensityColor(intensity))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(intensityColor(level))
                        .frame(width: 12, height: 12)
                }

                Text("More")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func intensityColor(_ intensity: Double) -> Color {
        if intensity < 0.1 {
            return Color.gray.opacity(0.15)
        } else if intensity < 0.3 {
            return Color.blue.opacity(0.3)
        } else if intensity < 0.6 {
            return Color.blue.opacity(0.5)
        } else if intensity < 0.8 {
            return Color.blue.opacity(0.7)
        } else {
            return Color.blue
        }
    }
}

// MARK: - Writing Session Row View

struct WritingSessionRowView: View {
    let project: String
    let words: Int
    let duration: String
    let time: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 18))
                .foregroundColor(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(project)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(time)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(words) words")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text(duration)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.writingSecondaryBackground)
        )
    }
}

// MARK: - Milestone Row View

struct MilestoneRowView: View {
    let title: String
    let progress: Double
    let isComplete: Bool
    let date: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                    .frame(width: 36, height: 36)

                if isComplete {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 36, height: 36)

                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isComplete ? .secondary : .primary)
                    .strikethrough(isComplete)

                Text(date)
                    .font(.system(size: 12))
                    .foregroundColor(isComplete ? .green : .secondary)
            }

            Spacer()

            if isComplete {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.writingSecondaryBackground)
        )
    }
}

// MARK: - Writing Trend Enum

private enum WritingTrend {
    case up
    case down
    case stable
}

// MARK: - Preview

#Preview {
    NavigationView {
        WritingStatsView(levelService: LevelSystemService(database: CosmoDatabase.shared.dbQueue!))
    }
}
