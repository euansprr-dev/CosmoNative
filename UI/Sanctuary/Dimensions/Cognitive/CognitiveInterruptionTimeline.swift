// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveInterruptionTimeline.swift
// Interruption Timeline - Visual tracking of cognitive interruptions
// Phase 3: Following SANCTUARY_UI_SPEC_V2.md section 3.1

import SwiftUI

// MARK: - Interruption Timeline

/// Horizontal timeline showing interruption events throughout the day
public struct CognitiveInterruptionTimeline: View {

    // MARK: - Properties

    let data: CognitiveDimensionData
    let onInterruptionTap: ((CognitiveInterruption) -> Void)?

    @State private var isVisible: Bool = false
    @State private var hoveredInterruption: UUID?

    // MARK: - Layout Constants

    private enum Layout {
        static let timelineHeight: CGFloat = 60
        static let hourWidth: CGFloat = 50
        static let markerSize: CGFloat = 8
        static let startHour: Int = 6
        static let endHour: Int = 22
    }

    // MARK: - Initialization

    public init(
        data: CognitiveDimensionData,
        onInterruptionTap: ((CognitiveInterruption) -> Void)? = nil
    ) {
        self.data = data
        self.onInterruptionTap = onInterruptionTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            header

            // Timeline - fills available width
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    timelineContent(availableWidth: geometry.size.width)
                }
            }
            .frame(height: Layout.timelineHeight)

            // Footer stats
            footer

            // Top disruptors
            topDisruptors
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
            withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Interruption Timeline")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            Spacer()

            // Count badge
            if data.totalInterruptionsToday > 0 {
                Text("\(data.totalInterruptionsToday) today")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(interruptionCountColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(interruptionCountColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private var interruptionCountColor: Color {
        switch data.totalInterruptionsToday {
        case 0...3: return SanctuaryColors.Semantic.success
        case 4...7: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.error
        }
    }

    // MARK: - Timeline Content

    private func timelineContent(availableWidth: CGFloat) -> some View {
        let dynamicHourWidth = max(Layout.hourWidth, availableWidth / CGFloat(Layout.endHour - Layout.startHour + 1))

        return ZStack(alignment: .topLeading) {
            // Hour grid
            hourGrid(hourWidth: dynamicHourWidth)

            // Interruption markers
            interruptionMarkers(hourWidth: dynamicHourWidth)
        }
        .frame(width: max(totalTimelineWidth, availableWidth), height: Layout.timelineHeight)
    }

    private func hourGrid(hourWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Layout.startHour...Layout.endHour, id: \.self) { hour in
                VStack(spacing: 0) {
                    // Hour label
                    Text(formatHour(hour))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .frame(height: 16)

                    // Grid line
                    Rectangle()
                        .fill(SanctuaryColors.Glass.border)
                        .frame(width: 1, height: Layout.timelineHeight - 16)
                }
                .frame(width: hourWidth)
            }
        }
    }

    private func interruptionMarkers(hourWidth: CGFloat) -> some View {
        ForEach(data.interruptions) { interruption in
            interruptionMarker(interruption, hourWidth: hourWidth)
        }
    }

    private func interruptionMarker(_ interruption: CognitiveInterruption, hourWidth: CGFloat) -> some View {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: interruption.timestamp)
        let minute = calendar.component(.minute, from: interruption.timestamp)

        guard hour >= Layout.startHour && hour <= Layout.endHour else {
            return AnyView(EmptyView())
        }

        let offset = CGFloat(hour - Layout.startHour) * hourWidth +
                     CGFloat(minute) / 60 * hourWidth

        let isHovered = hoveredInterruption == interruption.id
        let markerSize = Layout.markerSize + CGFloat(interruption.severityScore * 4)

        return AnyView(
            VStack(spacing: 2) {
                // Marker
                Circle()
                    .fill(Color(hex: interruption.source.colorHex))
                    .frame(width: markerSize, height: markerSize)
                    .shadow(color: Color(hex: interruption.source.colorHex).opacity(0.4), radius: 4)

                // Label on hover
                if isHovered {
                    VStack(spacing: 2) {
                        Text(interruption.source.displayName)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(SanctuaryColors.Text.primary)

                        Text(String(format: "%.1fm recovery", interruption.recoveryMinutes))
                            .font(.system(size: 7))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(SanctuaryColors.Glass.background)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .offset(x: offset - markerSize / 2, y: 20)
            .scaleEffect(isHovered ? 1.2 : 1.0)
            .animation(SanctuarySprings.hover, value: isHovered)
            .onHover { hovering in
                hoveredInterruption = hovering ? interruption.id : nil
            }
            .onTapGesture {
                onInterruptionTap?(interruption)
            }
        )
    }

    // MARK: - Footer Stats

    private var footer: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xl) {
            statPill(
                label: "Total",
                value: "\(data.totalInterruptionsToday)",
                color: interruptionCountColor
            )

            statPill(
                label: "Avg recovery",
                value: String(format: "%.1fmin", data.averageRecoveryTime / 60),
                color: recoveryColor
            )

            statPill(
                label: "Focus cost",
                value: "~\(data.focusCostMinutes)min lost",
                color: SanctuaryColors.Semantic.error
            )

            Spacer()
        }
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.xs) {
            Text(label + ":")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private var recoveryColor: Color {
        let avgMinutes = data.averageRecoveryTime / 60
        switch avgMinutes {
        case 0..<3: return SanctuaryColors.Semantic.success
        case 3..<6: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.error
        }
    }

    // MARK: - Top Disruptors

    private var topDisruptors: some View {
        HStack(spacing: SanctuaryLayout.Spacing.sm) {
            Text("Top disruptors:")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            ForEach(data.topDisruptors.prefix(4), id: \.source) { disruptor in
                HStack(spacing: 4) {
                    Image(systemName: disruptor.source.iconName)
                        .font(.system(size: 9))

                    Text("\(disruptor.source.displayName) (\(disruptor.count))")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Color(hex: disruptor.source.colorHex))

                if disruptor.source != data.topDisruptors.last?.source {
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private var totalTimelineWidth: CGFloat {
        CGFloat(Layout.endHour - Layout.startHour + 1) * Layout.hourWidth
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        let suffix = hour >= 12 ? "pm" : "am"
        return "\(h)\(suffix)"
    }
}

// MARK: - Interruption Summary Card

/// Compact card summarizing interruption stats
public struct InterruptionSummaryCard: View {

    let totalCount: Int
    let averageRecovery: TimeInterval
    let focusCost: Int
    let topSource: InterruptionSource?

    @State private var isHovered: Bool = false

    public init(
        totalCount: Int,
        averageRecovery: TimeInterval,
        focusCost: Int,
        topSource: InterruptionSource?
    ) {
        self.totalCount = totalCount
        self.averageRecovery = averageRecovery
        self.focusCost = focusCost
        self.topSource = topSource
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(countColor)

                Text("Interruptions")
                    .font(OnyxTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                Text("\(totalCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(countColor)
            }

            // Metrics row
            HStack(spacing: SanctuaryLayout.Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avg Recovery")
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(String(format: "%.1fm", averageRecovery / 60))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus Cost")
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("~\(focusCost)m")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Semantic.error)
                }
            }

            // Top source
            if let source = topSource {
                HStack(spacing: SanctuaryLayout.Spacing.xs) {
                    Text("Top:")
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Image(systemName: source.iconName)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: source.colorHex))

                    Text(source.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: source.colorHex))
                }
            }
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
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var countColor: Color {
        switch totalCount {
        case 0...3: return SanctuaryColors.Semantic.success
        case 4...7: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Interruption Detail View

/// Detailed view for a single interruption
public struct InterruptionDetailView: View {

    let interruption: CognitiveInterruption
    let onDismiss: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: interruption.source.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: interruption.source.colorHex))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(interruption.source.displayName)
                            .font(OnyxTypography.cardTitle)
                            .foregroundColor(SanctuaryColors.Text.primary)

                        if let app = interruption.app {
                            Text(app)
                                .font(.system(size: 12))
                                .foregroundColor(SanctuaryColors.Text.secondary)
                        }
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Timestamp
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(interruption.formattedTime)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            Divider()
                .background(SanctuaryColors.Glass.border)

            // Metrics
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                metricColumn(
                    label: "Recovery Time",
                    value: String(format: "%.1f min", interruption.recoveryMinutes),
                    color: recoveryColor
                )

                metricColumn(
                    label: "Severity",
                    value: severityLabel,
                    color: Color(hex: interruption.severityColor)
                )

                metricColumn(
                    label: "Focus Cost",
                    value: "~\(estimatedFocusCost) min",
                    color: SanctuaryColors.Semantic.error
                )
            }

            // Severity visualization
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                Text("Severity")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SanctuaryColors.Glass.border)

                        // Fill
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        SanctuaryColors.Semantic.success,
                                        SanctuaryColors.Semantic.warning,
                                        SanctuaryColors.Semantic.error
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(interruption.severityScore))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(Color(hex: interruption.source.colorHex).opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
    }

    private func metricColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
        }
    }

    private var recoveryColor: Color {
        switch interruption.recoveryMinutes {
        case 0..<3: return SanctuaryColors.Semantic.success
        case 3..<6: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.error
        }
    }

    private var severityLabel: String {
        switch interruption.severityScore {
        case 0..<0.3: return "Minor"
        case 0.3..<0.7: return "Moderate"
        default: return "Severe"
        }
    }

    private var estimatedFocusCost: Int {
        // Estimate: recovery time + 2x severity multiplier
        Int(interruption.recoveryMinutes * (1 + interruption.severityScore))
    }
}

// MARK: - Disruptor Breakdown

/// Breakdown chart of interruption sources
public struct DisruptorBreakdown: View {

    let disruptors: [(source: InterruptionSource, count: Int)]

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            Text("Disruptor Breakdown")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            ForEach(disruptors.prefix(5), id: \.source) { disruptor in
                disruptorRow(disruptor.source, count: disruptor.count)
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

    private func disruptorRow(_ source: InterruptionSource, count: Int) -> some View {
        let maxCount = disruptors.map { $0.count }.max() ?? 1
        let percentage = Double(count) / Double(maxCount)

        return HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Icon
            Image(systemName: source.iconName)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: source.colorHex))
                .frame(width: 20)

            // Label
            Text(source.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)
                .frame(width: 80, alignment: .leading)

            // Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SanctuaryColors.Glass.border)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: source.colorHex))
                        .frame(width: geometry.size.width * CGFloat(percentage))
                }
            }
            .frame(height: 8)

            // Count
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CognitiveInterruptionTimeline_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    CognitiveInterruptionTimeline(
                        data: .preview
                    ) { interruption in
                        print("Tapped: \(interruption.source)")
                    }

                    HStack(spacing: 16) {
                        InterruptionSummaryCard(
                            totalCount: 8,
                            averageRecovery: 4.2 * 60,
                            focusCost: 34,
                            topSource: .slack
                        )
                        .frame(width: 200)

                        DisruptorBreakdown(
                            disruptors: [
                                (.slack, 5),
                                (.meeting, 2),
                                (.notification, 1)
                            ]
                        )
                        .frame(width: 250)
                    }

                    InterruptionDetailView(
                        interruption: CognitiveDimensionData.preview.interruptions.first!,
                        onDismiss: {}
                    )
                    .frame(maxWidth: 350)
                }
                .padding()
            }
        }
    }
}
#endif
