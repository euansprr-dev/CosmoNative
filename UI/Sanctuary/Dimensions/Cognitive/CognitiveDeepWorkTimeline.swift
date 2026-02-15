// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveDeepWorkTimeline.swift
// Deep Work Timeline - Visual timeline of focused work sessions
// Phase 3: Following SANCTUARY_UI_SPEC_V2.md section 3.1

import SwiftUI

// MARK: - Deep Work Timeline

/// Horizontal timeline showing deep work sessions throughout the day
public struct CognitiveDeepWorkTimeline: View {

    // MARK: - Properties

    let data: CognitiveDimensionData
    let onSessionTap: ((DeepWorkSession) -> Void)?

    @State private var isVisible: Bool = false
    @State private var hoveredSession: UUID?

    // MARK: - Layout Constants

    private enum Layout {
        static let timelineHeight: CGFloat = 120
        static let hourWidth: CGFloat = 60
        static let sessionMinHeight: CGFloat = 60
        static let hourLabelHeight: CGFloat = 20
        static let startHour: Int = 6    // 6am
        static let endHour: Int = 22     // 10pm
    }

    // MARK: - Initialization

    public init(
        data: CognitiveDimensionData,
        onSessionTap: ((DeepWorkSession) -> Void)? = nil
    ) {
        self.data = data
        self.onSessionTap = onSessionTap
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
                        .frame(height: Layout.timelineHeight)
                }
            }
            .frame(height: Layout.timelineHeight)

            // Footer stats
            footer
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
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Deep Work Timeline")
                    .font(OnyxTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                if let activeSession = data.activeSession {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .pulseAnimation()

                        Text("ACTIVE: \(activeSession.taskType.displayName)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(SanctuaryColors.Semantic.success)
                    }
                }
            }

            Spacer()

            // Current time indicator
            Text(currentTimeString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.secondary)
        }
    }

    // MARK: - Timeline Content

    private func timelineContent(availableWidth: CGFloat) -> some View {
        let dynamicHourWidth = max(Layout.hourWidth, availableWidth / CGFloat(Layout.endHour - Layout.startHour + 1))

        return ZStack(alignment: .topLeading) {
            // Hour grid
            hourGrid(hourWidth: dynamicHourWidth)

            // Sessions overlay
            sessionsOverlay(hourWidth: dynamicHourWidth)

            // Current time indicator
            currentTimeIndicator(hourWidth: dynamicHourWidth)

            // Predicted windows
            predictedWindowsOverlay(hourWidth: dynamicHourWidth)
        }
        .frame(width: max(totalTimelineWidth, availableWidth))
    }

    private func hourGrid(hourWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Layout.startHour...Layout.endHour, id: \.self) { hour in
                VStack(spacing: 0) {
                    // Hour label
                    Text(formatHour(hour))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .frame(height: Layout.hourLabelHeight)

                    // Grid line
                    Rectangle()
                        .fill(SanctuaryColors.Glass.border)
                        .frame(width: 1, height: Layout.timelineHeight - Layout.hourLabelHeight)

                    Spacer()
                }
                .frame(width: hourWidth)
            }
        }
    }

    private func sessionsOverlay(hourWidth: CGFloat) -> some View {
        ForEach(data.deepWorkSessions) { session in
            sessionBlock(session, hourWidth: hourWidth)
        }
    }

    private func sessionBlock(_ session: DeepWorkSession, hourWidth: CGFloat) -> some View {
        let calendar = Calendar.current
        let startHour = calendar.component(.hour, from: session.startTime)
        let startMinute = calendar.component(.minute, from: session.startTime)
        let durationMinutes = session.durationMinutes

        // Calculate position using dynamic hourWidth
        let startOffset = CGFloat(startHour - Layout.startHour) * hourWidth +
                          CGFloat(startMinute) / 60 * hourWidth
        let width = CGFloat(durationMinutes) / 60 * hourWidth

        let isHovered = hoveredSession == session.id

        return VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
            // Task type badge
            HStack(spacing: 4) {
                Image(systemName: session.taskType.iconName)
                    .font(.system(size: 10))

                Text(session.taskType.displayName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(Color(hex: session.taskType.colorHex))

            // Duration
            Text("\(session.durationMinutes)m")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)

            // Quality score
            HStack(spacing: 2) {
                Text("Q:")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("\(Int(session.qualityScore))%")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(qualityColor(session.qualityScore))
            }

            // Active indicator
            if session.isActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .pulseAnimation()

                    Text("Active")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SanctuaryColors.Semantic.success)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .frame(width: max(80, width), height: Layout.sessionMinHeight)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(Color(hex: session.taskType.colorHex).opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .stroke(Color(hex: session.taskType.colorHex).opacity(0.5), lineWidth: 1.5)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? Color(hex: session.taskType.colorHex).opacity(0.3) : .clear, radius: 8)
        .offset(x: startOffset, y: Layout.hourLabelHeight + 8)
        .onHover { hovering in
            withAnimation(SanctuarySprings.hover) {
                hoveredSession = hovering ? session.id : nil
            }
        }
        .onTapGesture {
            onSessionTap?(session)
        }
    }

    private func currentTimeIndicator(hourWidth: CGFloat) -> some View {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        guard hour >= Layout.startHour && hour <= Layout.endHour else {
            return AnyView(EmptyView())
        }

        let offset = CGFloat(hour - Layout.startHour) * hourWidth +
                     CGFloat(minute) / 60 * hourWidth

        return AnyView(
            VStack(spacing: 0) {
                // Triangle marker
                Triangle()
                    .fill(SanctuaryColors.XP.primary)
                    .frame(width: 10, height: 6)

                // Line
                Rectangle()
                    .fill(SanctuaryColors.XP.primary)
                    .frame(width: 2, height: Layout.timelineHeight - Layout.hourLabelHeight)
            }
            .offset(x: offset - 1, y: Layout.hourLabelHeight - 6)
        )
    }

    private func predictedWindowsOverlay(hourWidth: CGFloat) -> some View {
        ForEach(data.predictedOptimalWindows) { window in
            predictedWindowBlock(window, hourWidth: hourWidth)
        }
    }

    private func predictedWindowBlock(_ window: CognitiveWindow, hourWidth: CGFloat) -> some View {
        guard let startHour = window.startTime.hour,
              let startMinute = window.startTime.minute,
              let _ = window.endTime.hour,
              let _ = window.endTime.minute else {
            return AnyView(EmptyView())
        }

        let startOffset = CGFloat(startHour - Layout.startHour) * hourWidth +
                          CGFloat(startMinute) / 60 * hourWidth
        let durationMinutes = window.durationMinutes
        let width = CGFloat(durationMinutes) / 60 * hourWidth

        return AnyView(
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))

                    Text("Pred")
                        .font(.system(size: 8, weight: .bold))

                    Text("\(Int(window.confidence))%")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                }
                .foregroundColor(SanctuaryColors.XP.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(SanctuaryColors.XP.primary.opacity(0.2))
                        .overlay(
                            Capsule()
                                .strokeBorder(SanctuaryColors.XP.primary.opacity(0.5), lineWidth: 1)
                        )
                )
            }
            .offset(x: startOffset + width / 2 - 30, y: Layout.hourLabelHeight + Layout.sessionMinHeight + 16)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xl) {
            statPill(
                label: "Today",
                value: data.formattedDeepWork,
                icon: "clock.fill"
            )

            statPill(
                label: "Quality avg",
                value: "\(Int(data.averageQualityToday))%",
                icon: "chart.bar.fill"
            )

            statPill(
                label: "Remaining",
                value: data.formattedCapacityRemaining,
                icon: "battery.75"
            )

            Spacer()
        }
    }

    private func statPill(label: String, value: String, icon: String) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(label + ":")
                .font(.system(size: 11))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)
        }
    }

    // MARK: - Helpers

    private var totalTimelineWidth: CGFloat {
        CGFloat(Layout.endHour - Layout.startHour + 1) * Layout.hourWidth
    }

    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: Date()).lowercased()
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        let suffix = hour >= 12 ? "pm" : "am"
        return "\(h)\(suffix)"
    }

    private func qualityColor(_ quality: Double) -> Color {
        switch quality {
        case 80...: return SanctuaryColors.Semantic.success
        case 60..<80: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Pulse Animation Modifier

@MainActor
private struct PulseAnimationModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

private extension View {
    func pulseAnimation() -> some View {
        modifier(PulseAnimationModifier())
    }
}

// MARK: - Session Detail Overlay

/// Detailed view for a deep work session
public struct DeepWorkSessionDetail: View {

    let session: DeepWorkSession
    let onDismiss: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: session.taskType.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: session.taskType.colorHex))

                    Text(session.taskType.displayName)
                        .font(OnyxTypography.cardTitle)
                        .foregroundColor(SanctuaryColors.Text.primary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }

            // Time range
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                VStack(alignment: .leading) {
                    Text("Start")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(formatTime(session.startTime))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                VStack(alignment: .leading) {
                    Text("End")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(session.endTime.map { formatTime($0) } ?? "Active")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(session.isActive ? SanctuaryColors.Semantic.success : SanctuaryColors.Text.primary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Duration")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text("\(session.durationMinutes)m")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }
            }

            Divider()
                .background(SanctuaryColors.Glass.border)

            // Metrics
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                metricColumn(
                    label: "Quality",
                    value: "\(Int(session.qualityScore))%",
                    color: qualityColor(session.qualityScore)
                )

                metricColumn(
                    label: "Flow Time",
                    value: "\(session.flowMinutes)m",
                    color: SanctuaryColors.Dimensions.cognitive
                )

                metricColumn(
                    label: "Interruptions",
                    value: "\(session.interruptionCount)",
                    color: session.interruptionCount > 3 ?
                        SanctuaryColors.Semantic.error :
                        SanctuaryColors.Text.primary
                )

                metricColumn(
                    label: "Flow %",
                    value: "\(Int(session.flowPercentage))%",
                    color: flowColor(session.flowPercentage)
                )
            }

            // Notes
            if let notes = session.notes, !notes.isEmpty {
                Divider()
                    .background(SanctuaryColors.Glass.border)

                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("Notes")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(notes)
                        .font(OnyxTypography.body)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
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
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }

    private func qualityColor(_ quality: Double) -> Color {
        switch quality {
        case 80...: return SanctuaryColors.Semantic.success
        case 60..<80: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.error
        }
    }

    private func flowColor(_ flow: Double) -> Color {
        switch flow {
        case 70...: return SanctuaryColors.Semantic.success
        case 40..<70: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CognitiveDeepWorkTimeline_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                CognitiveDeepWorkTimeline(
                    data: .preview
                ) { session in
                    print("Tapped session: \(session.taskType)")
                }

                DeepWorkSessionDetail(
                    session: CognitiveDimensionData.preview.deepWorkSessions.first!,
                    onDismiss: {}
                )
                .frame(maxWidth: 400)
            }
            .padding()
        }
    }
}
#endif
