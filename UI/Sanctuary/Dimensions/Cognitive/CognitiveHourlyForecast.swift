// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveHourlyForecast.swift
// Hourly Forecast Panel - Predicted optimal performance windows
// Phase 3: Following SANCTUARY_UI_SPEC_V2.md section 3.1

import SwiftUI

// MARK: - Hourly Forecast Panel

/// Panel showing predicted optimal cognitive performance windows
public struct CognitiveHourlyForecast: View {

    // MARK: - Properties

    let windows: [CognitiveWindow]
    let currentStatus: CognitiveWindowStatus
    let onWindowTap: ((CognitiveWindow) -> Void)?

    @State private var isVisible: Bool = false
    @State private var hoveredWindow: UUID?

    // MARK: - Initialization

    public init(
        windows: [CognitiveWindow],
        currentStatus: CognitiveWindowStatus,
        onWindowTap: ((CognitiveWindow) -> Void)? = nil
    ) {
        self.windows = windows
        self.currentStatus = currentStatus
        self.onWindowTap = onWindowTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            header

            // Window list
            VStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(windows.prefix(4)) { window in
                    windowRow(window)
                }
            }

            Divider()
                .background(SanctuaryColors.Glass.border)

            // Basis footer
            basisFooter
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
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
            Text("HOURLY FORECAST")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            Text("PREDICTED PERFORMANCE WINDOWS")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.secondary)
        }
    }

    // MARK: - Window Row

    private func windowRow(_ window: CognitiveWindow) -> some View {
        let isHovered = hoveredWindow == window.id

        return HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Priority indicator
            priorityIndicator(window)

            // Time range and details
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xxs) {
                // Time with confidence
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Text(window.formattedTimeRange)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text("\(Int(window.confidence))% conf")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(confidenceColor(window.confidence))
                }

                // Window type label
                Text(window.isPrimary ? "Primary window" : "Secondary window")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                // Recommended tasks
                HStack(spacing: 4) {
                    Text("Recommended:")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(window.recommendedTaskTypes.map { $0.displayName }.joined(separator: ", "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }

            Spacer()

            // Action chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .opacity(isHovered ? 1 : 0.5)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(isHovered ? SanctuaryColors.Glass.highlight : Color.clear)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            hoveredWindow = hovering ? window.id : nil
        }
        .onTapGesture {
            onWindowTap?(window)
        }
    }

    private func priorityIndicator(_ window: CognitiveWindow) -> some View {
        ZStack {
            if window.isPrimary {
                // Star for primary window
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(SanctuaryColors.XP.primary)
            } else if window.confidence < 50 {
                // X for low confidence
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Semantic.error)
            } else {
                // Circle for secondary
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }
        }
        .frame(width: 20)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 80...: return SanctuaryColors.Semantic.success
        case 60..<80: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Text.tertiary
        }
    }

    // MARK: - Basis Footer

    private var basisFooter: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
            Text("Based on:")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            // Collect all unique factors from windows
            let allFactors = Array(Set(windows.flatMap { $0.basedOn })).prefix(4)

            Text(allFactors.joined(separator: ", "))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .lineLimit(2)
        }
    }
}

// MARK: - Compact Window Card

/// Compact card for displaying a single optimal window
public struct CognitiveWindowCard: View {

    let window: CognitiveWindow
    let isActive: Bool
    let onTap: (() -> Void)?

    @State private var isHovered: Bool = false

    public init(
        window: CognitiveWindow,
        isActive: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.window = window
        self.isActive = isActive
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            // Header with priority
            HStack {
                if window.isPrimary {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.XP.primary)
                }

                Text(window.formattedTimeRange)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Spacer()

                // Confidence badge
                Text("\(Int(window.confidence))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceColor)
                    .clipShape(Capsule())
            }

            // Window type
            Text(window.isPrimary ? "Primary window" : "Secondary window")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            // Recommended tasks
            if !window.recommendedTaskTypes.isEmpty {
                HStack(spacing: 4) {
                    ForEach(window.recommendedTaskTypes.prefix(2), id: \.rawValue) { taskType in
                        HStack(spacing: 2) {
                            Image(systemName: taskType.iconName)
                                .font(.system(size: 8))

                            Text(taskType.displayName)
                                .font(.system(size: 9))
                        }
                        .foregroundColor(Color(hex: taskType.colorHex))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: taskType.colorHex).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }

            // Active indicator
            if isActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(SanctuaryColors.Semantic.success)
                        .frame(width: 6, height: 6)

                    Text("NOW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(
                            isActive ? SanctuaryColors.XP.primary.opacity(0.5) : SanctuaryColors.Glass.border,
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(
            color: isActive ? SanctuaryColors.XP.primary.opacity(0.2) : Color.clear,
            radius: 8
        )
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap?()
        }
    }

    private var confidenceColor: Color {
        switch window.confidence {
        case 80...: return SanctuaryColors.Semantic.success
        case 60..<80: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Text.tertiary
        }
    }
}

// MARK: - Journal Density Panel

/// Panel showing journal integration metrics
public struct CognitiveJournalDensity: View {

    let insightMarkersToday: Int
    let reflectionDepthScore: Double
    let detectedThemes: [String]
    let journalExcerpt: String?

    @State private var isVisible: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("JOURNAL DENSITY")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Metrics row
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                metricItem(
                    label: "Insight markers today",
                    value: "\(insightMarkersToday)"
                )

                metricItem(
                    label: "Reflection depth",
                    value: String(format: "%.1f/10", reflectionDepthScore)
                )

                metricItem(
                    label: "Themes detected",
                    value: "\(detectedThemes.count)"
                )
            }

            Divider()
                .background(SanctuaryColors.Glass.border)

            // Themes
            if !detectedThemes.isEmpty {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    ForEach(detectedThemes.prefix(3), id: \.self) { theme in
                        Text(theme)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(SanctuaryColors.Dimensions.reflection)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SanctuaryColors.Dimensions.reflection.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            // Excerpt
            if let excerpt = journalExcerpt, !excerpt.isEmpty {
                Text("\"\(excerpt)\"")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundColor(SanctuaryColors.Text.secondary)
                    .lineLimit(2)
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
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                isVisible = true
            }
        }
    }

    private func metricItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)
        }
    }
}

// MARK: - Cognitive Prediction Card

/// Card showing AI predictions with action recommendations
public struct CognitivePredictionCard: View {

    let prediction: CognitivePrediction
    let onActionTap: (() -> Void)?

    @State private var isVisible: Bool = false
    @State private var isHovered: Bool = false

    public init(
        prediction: CognitivePrediction,
        onActionTap: (() -> Void)? = nil
    ) {
        self.prediction = prediction
        self.onActionTap = onActionTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header with confidence
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("PREDICTION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                Spacer()

                Text("\(Int(prediction.confidence))% conf")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(confidenceColor)
            }

            // Message
            Text(prediction.message)
                .font(SanctuaryTypography.body)
                .foregroundColor(SanctuaryColors.Text.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Impact highlight
            if let impact = prediction.impact {
                Text(impact)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Semantic.success)
            }

            Divider()
                .background(SanctuaryColors.Glass.border)

            // Footer with basis and action
            HStack {
                // Based on
                VStack(alignment: .leading, spacing: 2) {
                    Text("Based on:")
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(prediction.basedOn.joined(separator: ", "))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Action button
                if let actionLabel = prediction.recommendedAction {
                    Button(action: { onActionTap?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 10))

                            Text(actionLabel)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(SanctuaryColors.XP.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(SanctuaryColors.XP.primary.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.XP.primary.opacity(0.3), lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .shadow(color: SanctuaryColors.XP.primary.opacity(isHovered ? 0.2 : 0.1), radius: 12)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
                isVisible = true
            }
        }
    }

    private var confidenceColor: Color {
        switch prediction.confidence {
        case 80...: return SanctuaryColors.Semantic.success
        case 60..<80: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Text.tertiary
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CognitiveHourlyForecast_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    CognitiveHourlyForecast(
                        windows: CognitiveDimensionData.preview.predictedOptimalWindows,
                        currentStatus: .inWindow
                    )

                    HStack(spacing: 16) {
                        CognitiveWindowCard(
                            window: CognitiveDimensionData.preview.predictedOptimalWindows.first!,
                            isActive: true
                        )

                        CognitiveWindowCard(
                            window: CognitiveDimensionData.preview.predictedOptimalWindows.last!,
                            isActive: false
                        )
                    }

                    CognitiveJournalDensity(
                        insightMarkersToday: 7,
                        reflectionDepthScore: 8.2,
                        detectedThemes: ["delegation", "focus blocks", "morning routine"],
                        journalExcerpt: "Recurring focus on delegation patterns..."
                    )

                    CognitivePredictionCard(
                        prediction: CognitivePrediction(
                            message: "If you take a 15-minute break now, your 2pm-4pm deep work session is predicted to be 23% more productive. Current cognitive load is elevated.",
                            confidence: 87,
                            basedOn: ["NELO score", "time since last break", "historical patterns"],
                            recommendedAction: "Remind",
                            impact: "+23% productivity"
                        )
                    )
                }
                .padding()
            }
        }
    }
}
#endif
