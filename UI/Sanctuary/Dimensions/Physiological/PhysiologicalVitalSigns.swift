// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalVitalSigns.swift
// Vital Signs - HRV, RHR, Recovery, Readiness panels
// Phase 5: Following SANCTUARY_UI_SPEC_V2.md section 3.3

import SwiftUI

// MARK: - Vital Signs Panel

/// Panel showing all vital sign cards
public struct PhysiologicalVitalSigns: View {

    // MARK: - Properties

    let data: PhysiologicalDimensionData

    @State private var isVisible: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                Text("Vital Signs Panel")
                    .font(OnyxTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                Spacer()

                // Live indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .modifier(PulseModifier())

                    Text("Live")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("2s ago")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Vital cards
            VStack(spacing: SanctuaryLayout.Spacing.md) {
                HRVCard(
                    currentHRV: data.currentHRV,
                    trend: data.hrvTrend,
                    status: data.hrvStatus
                )

                RHRCard(
                    restingHR: data.restingHeartRate,
                    zone: data.rhrZone
                )

                RecoveryCard(
                    score: data.recoveryScore,
                    factors: data.recoveryFactors,
                    recommendation: data.workoutRecommendation
                )

                ReadinessCard(
                    score: data.readinessScore,
                    peakWindow: data.formattedPeakWindow,
                    status: data.readinessStatus
                )
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
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                isVisible = true
            }
        }
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
            .onAppear { isPulsing = true }
    }
}

// MARK: - HRV Card

/// Heart Rate Variability vital card
public struct HRVCard: View {

    let currentHRV: Double
    let trend: [HRVDataPoint]
    let status: String

    @State private var isHovered: Bool = false
    @State private var chartAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header row
            HStack {
                Text("HRV")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Text("\(Int(currentHRV))ms")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SanctuaryColors.Glass.highlight)

                    // Progress
                    RoundedRectangle(cornerRadius: 2)
                        .fill(hrvColor)
                        .frame(width: geometry.size.width * min(1, currentHRV / 60))

                    // Indicator dots
                    HStack {
                        Spacer()
                        Circle()
                            .fill(SanctuaryColors.Text.primary)
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(SanctuaryColors.Text.primary)
                            .frame(width: 4, height: 4)
                    }
                    .padding(.trailing, 4)
                }
            }
            .frame(height: 8)

            // Status row
            HStack {
                Text("vs avg: +12%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Semantic.success)

                    Text(status.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? hrvColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    private var hrvColor: Color {
        if currentHRV >= 50 { return SanctuaryColors.Semantic.success }
        if currentHRV >= 40 { return SanctuaryColors.Semantic.info }
        if currentHRV >= 30 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }
}

// MARK: - RHR Card

/// Resting Heart Rate vital card
public struct RHRCard: View {

    let restingHR: Int
    let zone: RestingHRZone

    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header row
            HStack {
                Text("RHR")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                HStack(spacing: 4) {
                    Text("\(restingHR)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text("bpm")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SanctuaryColors.Glass.highlight)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: zone.color))
                        .frame(width: geometry.size.width * rhrProgress)

                    HStack {
                        Spacer()
                        Circle()
                            .fill(SanctuaryColors.Text.primary)
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(SanctuaryColors.Text.primary)
                            .frame(width: 4, height: 4)
                    }
                    .padding(.trailing, 4)
                }
            }
            .frame(height: 8)

            // Status row
            HStack {
                Text("Zone: \(zone.displayName)")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: zone.color))

                    Text(zoneRating.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: zone.color))
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? Color(hex: zone.color).opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    private var rhrProgress: Double {
        // Lower RHR = more progress (better fitness)
        // Scale: 40 bpm (excellent) to 80 bpm (poor)
        let normalized = Double(max(40, min(80, restingHR)) - 40) / 40.0
        return 1.0 - normalized
    }

    private var zoneRating: String {
        switch zone {
        case .athletic: return "Excellent"
        case .average: return "Good"
        case .elevated: return "Fair"
        case .high: return "Elevated"
        }
    }
}

// MARK: - Recovery Card

/// Recovery score vital card
public struct RecoveryCard: View {

    let score: Double
    let factors: RecoveryBreakdown
    let recommendation: DisplayWorkoutType?

    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header row
            HStack {
                Text("Recovery")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Text("\(Int(score))%")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SanctuaryColors.Glass.highlight)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(recoveryColor)
                        .frame(width: geometry.size.width * score / 100)

                    HStack {
                        Spacer()
                        Circle()
                            .fill(SanctuaryColors.Text.primary)
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(SanctuaryColors.Text.primary)
                            .frame(width: 4, height: 4)
                    }
                    .padding(.trailing, 4)
                }
            }
            .frame(height: 8)

            // Status row
            HStack {
                if let workout = recommendation {
                    Text("\(workout.displayName) OK")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                } else {
                    Text("Rest recommended")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(recoveryColor)

                    Text(recoveryStatus.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(recoveryColor)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? recoveryColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    private var recoveryColor: Color {
        if score >= 80 { return SanctuaryColors.Semantic.success }
        if score >= 60 { return SanctuaryColors.Semantic.info }
        if score >= 40 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    private var recoveryStatus: String {
        if score >= 80 { return "Strong" }
        if score >= 60 { return "Moderate" }
        if score >= 40 { return "Recovering" }
        return "Fatigued"
    }
}

// MARK: - Readiness Card

/// Readiness score vital card
public struct ReadinessCard: View {

    let score: Double
    let peakWindow: String
    let status: String

    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header row
            HStack {
                Text("Readiness")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Text("\(Int(score))%")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SanctuaryColors.Glass.highlight)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(readinessColor)
                        .frame(width: geometry.size.width * score / 100)

                    HStack {
                        Spacer()
                        Circle()
                            .fill(SanctuaryColors.Text.primary)
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(SanctuaryColors.Text.primary)
                            .frame(width: 4, height: 4)
                    }
                    .padding(.trailing, 4)
                }
            }
            .frame(height: 8)

            // Status row
            HStack {
                Text("Peak window: \(peakWindow)")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(readinessColor)

                    Text(status.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(readinessColor)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? readinessColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    private var readinessColor: Color {
        if score >= 80 { return SanctuaryColors.Semantic.success }
        if score >= 60 { return SanctuaryColors.Semantic.info }
        if score >= 40 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }
}

// MARK: - HRV Trend Chart

/// 7-day HRV trend visualization
public struct HRVTrendChart: View {

    let trend: [HRVDataPoint]
    let currentHRV: Double

    @State private var isVisible: Bool = false
    @State private var chartAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("HRV Trend (7 Days)")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height

                ZStack {
                    // Grid lines
                    gridLines(width: width, height: height)

                    // Y-axis labels
                    yAxisLabels(height: height)

                    // Chart line
                    chartLine(width: width, height: height)

                    // Current day marker
                    if !trend.isEmpty {
                        currentDayMarker(width: width, height: height)
                    }
                }
            }
            .frame(height: 100)

            // Stats row
            HStack {
                Text("avg: \(Int(averageHRV))ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("•")
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("peak: \(Int(peakHRV))ms (\(peakDay))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Day labels
            dayLabels
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
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.4)) {
                chartAnimated = true
            }
        }
    }

    private func gridLines(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let y = height * CGFloat(i) / 3

                Path { path in
                    path.move(to: CGPoint(x: 30, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(SanctuaryColors.Glass.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    private func yAxisLabels(height: CGFloat) -> some View {
        VStack {
            Text("52")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Spacer()

            Text("48")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Spacer()

            Text("44")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Spacer()

            Text("40")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(width: 25)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartLine(width: CGFloat, height: CGFloat) -> some View {
        let graphWidth = width - 30
        let minValue: Double = 40
        let maxValue: Double = 52
        let range = maxValue - minValue

        return Path { path in
            for (index, point) in trend.enumerated() {
                let x = 30 + graphWidth * CGFloat(index) / CGFloat(max(1, trend.count - 1))
                let normalizedY = (point.value - minValue) / range
                let y = height * (1 - CGFloat(normalizedY))

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .trim(from: 0, to: chartAnimated ? 1 : 0)
        .stroke(
            SanctuaryColors.Dimensions.physiological,
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
        .animation(.easeOut(duration: 0.8), value: chartAnimated)
    }

    private func currentDayMarker(width: CGFloat, height: CGFloat) -> some View {
        let graphWidth = width - 30
        let minValue: Double = 40
        let maxValue: Double = 52
        let range = maxValue - minValue

        guard let lastPoint = trend.last else { return AnyView(EmptyView()) }

        let x = 30 + graphWidth
        let normalizedY = (lastPoint.value - minValue) / range
        let y = height * (1 - CGFloat(normalizedY))

        return AnyView(
            ZStack {
                Circle()
                    .fill(SanctuaryColors.Dimensions.physiological)
                    .frame(width: 8, height: 8)

                Text("Today")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(SanctuaryColors.Dimensions.physiological)
                    .offset(x: -20, y: 0)
            }
            .position(x: x, y: y)
            .opacity(chartAnimated ? 1 : 0)
        )
    }

    private var dayLabels: some View {
        HStack {
            ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                Text(day)
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.leading, 30)
    }

    private var averageHRV: Double {
        guard !trend.isEmpty else { return 0 }
        return trend.reduce(0.0) { $0 + $1.value } / Double(trend.count)
    }

    private var peakHRV: Double {
        trend.map { $0.value }.max() ?? 0
    }

    private var peakDay: String {
        guard let peak = trend.max(by: { $0.value < $1.value }) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: peak.timestamp)
    }
}

// MARK: - Compact Vitals Row

/// Compact row of vital metrics for embedding
public struct VitalsRowCompact: View {

    let hrv: Double
    let rhr: Int
    let recovery: Double
    let readiness: Double

    public init(hrv: Double, rhr: Int, recovery: Double, readiness: Double) {
        self.hrv = hrv
        self.rhr = rhr
        self.recovery = recovery
        self.readiness = readiness
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            compactMetric(label: "HRV", value: "\(Int(hrv))ms", color: hrvColor)
            compactMetric(label: "RHR", value: "\(rhr)bpm", color: rhrColor)
            compactMetric(label: "Recovery", value: "\(Int(recovery))%", color: recoveryColor)
            compactMetric(label: "Readiness", value: "\(Int(readiness))%", color: readinessColor)
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

    private func compactMetric(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var hrvColor: Color {
        if hrv >= 50 { return SanctuaryColors.Semantic.success }
        if hrv >= 40 { return SanctuaryColors.Semantic.info }
        return SanctuaryColors.Semantic.warning
    }

    private var rhrColor: Color {
        if rhr <= 55 { return SanctuaryColors.Semantic.success }
        if rhr <= 65 { return SanctuaryColors.Semantic.info }
        return SanctuaryColors.Semantic.warning
    }

    private var recoveryColor: Color {
        if recovery >= 80 { return SanctuaryColors.Semantic.success }
        if recovery >= 60 { return SanctuaryColors.Semantic.info }
        return SanctuaryColors.Semantic.warning
    }

    private var readinessColor: Color {
        if readiness >= 80 { return SanctuaryColors.Semantic.success }
        if readiness >= 60 { return SanctuaryColors.Semantic.info }
        return SanctuaryColors.Semantic.warning
    }
}

// MARK: - Preview

#if DEBUG
struct PhysiologicalVitalSigns_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                PhysiologicalVitalSigns(data: .preview)

                HRVTrendChart(
                    trend: PhysiologicalDimensionData.preview.hrvTrend,
                    currentHRV: 48
                )

                VitalsRowCompact(hrv: 48, rhr: 54, recovery: 78, readiness: 82)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 800)
    }
}
#endif
