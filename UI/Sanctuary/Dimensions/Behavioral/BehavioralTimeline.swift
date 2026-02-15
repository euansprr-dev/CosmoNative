// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralTimeline.swift
// Behavioral Timeline - Day's behavioral events and violations
// Phase 6: Following SANCTUARY_UI_SPEC_V2.md section 3.4

import SwiftUI

// MARK: - Behavioral Timeline

/// Timeline showing today's behavioral events
public struct BehavioralTimeline: View {

    // MARK: - Properties

    let events: [BehavioralEvent]
    let violations: [BehaviorViolation]

    @State private var isVisible: Bool = false

    // MARK: - Initialization

    public init(events: [BehavioralEvent], violations: [BehaviorViolation] = []) {
        self.events = events.sorted { $0.timestamp < $1.timestamp }
        self.violations = violations
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                Text("Today's Timeline")
                    .font(OnyxTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                Spacer()

                // Event count
                Text("\(events.count) events")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Hour timeline
            hourTimeline

            // Events list
            eventsList

            // Violations section
            if !violations.isEmpty {
                violationsSection
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }

    // MARK: - Hour Timeline

    private var hourTimeline: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let hourWidth = width / 24

            ZStack(alignment: .topLeading) {
                // Hour markers
                HStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(SanctuaryColors.Glass.border)
                                .frame(width: 1, height: hour % 6 == 0 ? 8 : 4)

                            if hour % 6 == 0 {
                                Text("\(hour)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(SanctuaryColors.Text.tertiary)
                            }
                        }
                        .frame(width: hourWidth)
                    }
                }

                // Event markers
                ForEach(events) { event in
                    let xPos = hourWidth * CGFloat(event.hour) + (hourWidth * CGFloat(Calendar.current.component(.minute, from: event.timestamp)) / 60)

                    Circle()
                        .fill(event.status.color)
                        .frame(width: 8, height: 8)
                        .offset(x: xPos - 4, y: 0)
                        .opacity(isVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.2), value: isVisible)
                }

                // Current time indicator
                let now = Date()
                let currentHour = Calendar.current.component(.hour, from: now)
                let currentMinute = Calendar.current.component(.minute, from: now)
                let currentX = hourWidth * CGFloat(currentHour) + (hourWidth * CGFloat(currentMinute) / 60)

                Rectangle()
                    .fill(SanctuaryColors.Dimensions.behavioral)
                    .frame(width: 2, height: 12)
                    .offset(x: currentX - 1, y: -2)
            }
        }
        .frame(height: 30)
    }

    // MARK: - Events List

    private var eventsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                TimelineEventRow(
                    event: event,
                    isLast: index == events.count - 1
                )
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : -10)
                .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05 + 0.15), value: isVisible)
            }
        }
    }

    // MARK: - Violations Section

    private var violationsSection: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Semantic.error)

                Text("Violations")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Semantic.error)
                    .tracking(1)
            }

            ForEach(violations) { violation in
                ViolationRow(violation: violation)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Semantic.error.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.Semantic.error.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Timeline Event Row

/// Individual event row in the timeline
public struct TimelineEventRow: View {

    let event: BehavioralEvent
    let isLast: Bool

    @State private var isHovered: Bool = false

    public var body: some View {
        HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.md) {
            // Time column
            Text(event.formattedTime)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .frame(width: 40, alignment: .trailing)

            // Timeline connector
            VStack(spacing: 0) {
                Circle()
                    .fill(event.status.color)
                    .frame(width: 10, height: 10)

                if !isLast {
                    Rectangle()
                        .fill(SanctuaryColors.Glass.border)
                        .frame(width: 2)
                        .frame(minHeight: 24)
                }
            }

            // Event content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: event.eventType.iconName)
                        .font(.system(size: 12))
                        .foregroundColor(event.status.color)

                    Text(event.eventType.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    if event.status == .violation {
                        Text("Violation")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(SanctuaryColors.Semantic.error)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(SanctuaryColors.Semantic.error.opacity(0.2))
                            )
                    }
                }

                if let details = event.details {
                    Text(details)
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, SanctuaryLayout.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(isHovered ? SanctuaryColors.Glass.highlight : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Violation Row

/// Row showing a behavioral violation
public struct ViolationRow: View {

    let violation: BehaviorViolation

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Time
            Text(formattedTime)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(SanctuaryColors.Semantic.error)
                .frame(width: 40, alignment: .trailing)

            // Icon
            Image(systemName: violation.category.iconName)
                .font(.system(size: 12))
                .foregroundColor(SanctuaryColors.Semantic.error)

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text(violation.description)
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text(violation.impact)
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: violation.timestamp)
    }
}

// MARK: - Timeline Compact

/// Compact timeline for embedding
public struct TimelineCompact: View {

    let events: [BehavioralEvent]
    let onExpand: () -> Void

    public init(events: [BehavioralEvent], onExpand: @escaping () -> Void) {
        self.events = events.sorted { $0.timestamp < $1.timestamp }
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text("Timeline")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 10))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(SanctuaryColors.Dimensions.behavioral)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Mini timeline
            HStack(spacing: 4) {
                ForEach(events.prefix(6)) { event in
                    VStack(spacing: 2) {
                        Image(systemName: event.eventType.iconName)
                            .font(.system(size: 10))
                            .foregroundColor(event.status.color)

                        Text(event.formattedTime)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if events.count > 6 {
                    Text("+\(events.count - 6)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
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
    }
}

// MARK: - Level Up Path Card

/// Card showing path to next level
public struct LevelUpPathCard: View {

    let levelUpPath: LevelUpPath

    @State private var isVisible: Bool = false
    @State private var progressAnimated: Bool = false

    public init(levelUpPath: LevelUpPath) {
        self.levelUpPath = levelUpPath
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("Level Up Path")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SanctuaryColors.XP.primary)
                        .tracking(1)
                }

                Spacer()

                Text("~\(levelUpPath.estimatedDays) days")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Level progress
            HStack(alignment: .center, spacing: SanctuaryLayout.Spacing.md) {
                // Current level
                VStack(spacing: 2) {
                    Text("Lvl")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("\(levelUpPath.currentLevel)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SanctuaryColors.Glass.border)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [SanctuaryColors.XP.primary, SanctuaryColors.XP.primary.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: progressAnimated ? geometry.size.width * CGFloat(levelUpPath.progress) : 0,
                                height: 8
                            )
                    }
                }
                .frame(height: 8)

                // Next level
                VStack(spacing: 2) {
                    Text("Lvl")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("\(levelUpPath.nextLevel)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.XP.primary)
                }
            }
            .frame(height: 40)

            // XP progress
            HStack {
                Text("\(levelUpPath.xpProgress) / \(levelUpPath.xpNeeded) XP")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.secondary)

                Spacer()

                Text("\(levelUpPath.xpRemaining) XP to go")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            // Fastest actions
            if !levelUpPath.fastestActions.isEmpty {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                    Text("Fastest Path")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .tracking(1)

                    ForEach(levelUpPath.fastestActions) { action in
                        HStack(spacing: SanctuaryLayout.Spacing.sm) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(SanctuaryColors.XP.primary)

                            Text(action.action)
                                .font(.system(size: 10))
                                .foregroundColor(SanctuaryColors.Text.secondary)
                                .lineLimit(2)

                            Spacer()

                            Text("+\(action.xpReward) XP")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctuaryColors.XP.primary)
                        }
                    }
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
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                progressAnimated = true
            }
        }
    }
}

// MARK: - Behavioral Prediction Card

/// Card showing AI-generated behavioral prediction
public struct BehavioralPredictionCard: View {

    let prediction: BehavioralPrediction

    @State private var isExpanded: Bool = false

    public init(prediction: BehavioralPrediction) {
        self.prediction = prediction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("Prediction")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SanctuaryColors.XP.primary)
                        .tracking(1)
                }

                Spacer()

                Text("CONFIDENCE: \(Int(prediction.confidence * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Condition
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                Text("IF:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(prediction.condition)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Prediction
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                Text("THEN:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(prediction.prediction)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Based on (expandable)
            if isExpanded {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("Based on:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(prediction.basedOn)
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }

            // Actions
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(prediction.actions, id: \.self) { action in
                    actionButton(action)
                }

                Spacer()

                Button(action: {
                    withAnimation(SanctuarySprings.snappy) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.XP.primary.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func actionButton(_ action: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 4) {
                Image(systemName: iconForAction(action))
                    .font(.system(size: 10))

                Text(action)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SanctuaryColors.Dimensions.behavioral)
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Dimensions.behavioral.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .stroke(SanctuaryColors.Dimensions.behavioral.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForAction(_ action: String) -> String {
        if action.lowercased().contains("remind") { return "bell" }
        if action.lowercased().contains("analytics") { return "chart.bar" }
        if action.lowercased().contains("adjust") { return "slider.horizontal.3" }
        return "arrow.right"
    }
}

// MARK: - Preview

#if DEBUG
struct BehavioralTimeline_Previews: PreviewProvider {
    static var previews: some View {
        let data = BehavioralDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    BehavioralTimeline(
                        events: data.todayEvents,
                        violations: data.violations
                    )

                    LevelUpPathCard(levelUpPath: data.levelUpPath)

                    if let prediction = data.predictions.first {
                        BehavioralPredictionCard(prediction: prediction)
                    }

                    TimelineCompact(
                        events: data.todayEvents,
                        onExpand: {}
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 900)
    }
}
#endif
