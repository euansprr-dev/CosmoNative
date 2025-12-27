// CosmoOS/UI/Sanctuary/DimensionDetailView.swift
// Dimension Detail View - Expanded view for a single dimension
// Shows metrics, insights, trends, and actionable recommendations

import SwiftUI
import Charts

// MARK: - Dimension Detail View

public struct DimensionDetailView: View {

    let dimension: LevelDimension
    let state: SanctuaryDimensionState?
    let insights: [CorrelationInsight]
    var onDismiss: (() -> Void)?  // Optional closure for custom dismiss

    @Environment(\.dismiss) private var environmentDismiss
    @State private var selectedTimeRange: UITimeRange = .week

    /// Handles dismissal - uses custom closure if provided, otherwise falls back to environment
    private func dismiss() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            environmentDismiss()
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Desktop-style header bar
            HStack {
                // Dimension icon and title
                HStack(spacing: 12) {
                    Image(systemName: dimension.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(dimensionColor)

                    Text(dimension.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                // Close button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.03))

            // Scrollable content
            ScrollView {
                VStack(spacing: 20) {
                    // Header orb
                    headerSection

                    // Stats grid
                    statsGrid

                    // XP Progress
                    xpProgressSection

                    // Trend chart
                    trendChartSection

                    // Related insights
                    if !insights.isEmpty {
                        insightsSection
                    }

                    // Recent activity
                    recentActivitySection
                }
                .padding(20)
            }
        }
        .background(Color(hex: "#0A0A0F"))
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Large orb
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                dimensionColor.opacity(0.8),
                                dimensionColor.opacity(0.4),
                                dimensionColor.opacity(0.1)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: dimensionColor.opacity(0.5), radius: 30, x: 0, y: 0)

                VStack(spacing: 4) {
                    Image(systemName: dimension.iconName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)

                    if let state = state {
                        Text("Lvl \(state.level)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }

            // NELO score
            if let state = state {
                HStack(spacing: 8) {
                    Text("NELO")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    Text("\(state.nelo)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    trendArrow(for: state.trend)
                }
            }
        }
        .padding(.vertical, 24)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            if let state = state {
                StatCard(
                    title: "Current Streak",
                    value: "\(state.streak)",
                    icon: "flame.fill",
                    color: .orange,
                    subtitle: state.streak > 0 ? "days" : "inactive"
                )

                StatCard(
                    title: "XP Today",
                    value: "+0",  // Would come from live metrics
                    icon: "sparkles",
                    color: .yellow,
                    subtitle: "earned"
                )

                StatCard(
                    title: "Level Progress",
                    value: "\(Int(state.xpProgress * 100))%",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .green,
                    subtitle: "\(state.currentXP)/\(state.xpToNextLevel) XP"
                )

                StatCard(
                    title: "Status",
                    value: state.isActive ? "Active" : "Inactive",
                    icon: state.isActive ? "checkmark.circle.fill" : "moon.fill",
                    color: state.isActive ? .green : .gray,
                    subtitle: state.isActive ? "Today" : "No activity"
                )
            }
        }
    }

    // MARK: - XP Progress Section

    private var xpProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Level Progress")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            if let state = state {
                VStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))

                            // Progress
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [dimensionColor, dimensionColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(state.xpProgress))
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text("\(state.currentXP) XP")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))

                        Spacer()

                        Text("\(state.xpToNextLevel) XP to Level \(state.level + 1)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Trend Chart Section

    private var trendChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trend")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(UITimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            // Placeholder chart
            Chart {
                ForEach(sampleTrendData, id: \.day) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("NELO", point.value)
                    )
                    .foregroundStyle(dimensionColor)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Day", point.day),
                        y: .value("NELO", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [dimensionColor.opacity(0.3), dimensionColor.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let stringValue = value.as(String.self) {
                            Text(stringValue)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Insights Section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related Insights")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            ForEach(insights.prefix(3), id: \.uuid) { insight in
                InsightRowView(insight: insight)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            // Placeholder for activity list
            ForEach(0..<3, id: \.self) { _ in
                HStack {
                    Circle()
                        .fill(dimensionColor.opacity(0.3))
                        .frame(width: 8, height: 8)

                    Text("Activity placeholder")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    Text("2h ago")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var dimensionColor: Color {
        Color(hex: dimension.colorHex)
    }

    @ViewBuilder
    private func trendArrow(for trend: Trend) -> some View {
        switch trend {
        case .up, .improving:
            Image(systemName: "arrow.up")
                .foregroundColor(.green)
        case .down, .declining:
            Image(systemName: "arrow.down")
                .foregroundColor(.red)
        case .stable:
            Image(systemName: "arrow.right")
                .foregroundColor(.gray)
        }
    }

    private var sampleTrendData: [TrendPoint] {
        [
            TrendPoint(day: "Mon", value: state?.nelo ?? 1000 - 50),
            TrendPoint(day: "Tue", value: state?.nelo ?? 1000 - 30),
            TrendPoint(day: "Wed", value: state?.nelo ?? 1000 - 20),
            TrendPoint(day: "Thu", value: state?.nelo ?? 1000 + 10),
            TrendPoint(day: "Fri", value: state?.nelo ?? 1000 + 30),
            TrendPoint(day: "Sat", value: state?.nelo ?? 1000 - 10),
            TrendPoint(day: "Sun", value: state?.nelo ?? 1000)
        ]
    }
}

// MARK: - Supporting Types

private struct TrendPoint {
    let day: String
    let value: Int
}

private enum UITimeRange: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14))

                Spacer()
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Insight Row View

struct InsightRowView: View {
    let insight: CorrelationInsight

    var body: some View {
        HStack(spacing: 12) {
            // Indicator
            Circle()
                .fill(insight.coefficient > 0 ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.humanDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text("\(insight.confidence.rawValue.capitalized) • \(insight.strength.rawValue.capitalized)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // Effect size
            Text(String(format: "%.0f%%", abs(insight.effectSize * 100)))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(insight.coefficient > 0 ? .green : .red)
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    DimensionDetailView(
        dimension: .cognitive,
        state: SanctuaryDimensionState(
            dimension: .cognitive,
            level: 15,
            nelo: 1450,
            currentXP: 200,
            xpToNextLevel: 300,
            xpProgress: 0.66,
            streak: 7,
            lastActivity: Date(),
            trend: .up,
            isActive: true
        ),
        insights: []
    )
}
