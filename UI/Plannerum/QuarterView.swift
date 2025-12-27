// CosmoOS/UI/Plannerum/QuarterView.swift
// Quarter View - Core Objectives and XP Trajectory visualization
// Strategic planning view matching Sanctuary's immersive realm aesthetic

import SwiftUI

// MARK: - Quarter View

/// The Quarter View displays core objectives and XP trajectory for strategic planning.
/// Matches Sanctuary's immersive feel with floating glass containers.
///
/// Visual Layout:
/// ```
/// ╔═══════════════════════════════════════════════════════════════╗
/// ║                    Q 4   2 0 2 4                              ║
/// ║     ╭─────────────────────────────────────────────────╮       ║
/// ║     │            CORE OBJECTIVES                      │       ║
/// ║     │  ╭────────────────────────────────────────╮     │       ║
/// ║     │  │  ◈  Launch CosmoOS Beta       58%     │     │       ║
/// ║     │  ╰────────────────────────────────────────╯     │       ║
/// ║     ╰─────────────────────────────────────────────────╯       ║
/// ║                                                               ║
/// ║     QUARTER TRAJECTORY                                        ║
/// ║     ──────────────────                                        ║
/// ║         Oct        Nov        Dec        Jan                  ║
/// ║          ●──────────●──────────●                              ║
/// ╚═══════════════════════════════════════════════════════════════╝
/// ```
public struct QuarterView: View {

    // MARK: - State

    @StateObject private var viewModel = QuarterViewModel()
    @State private var selectedQuarter: Quarter = .current
    @State private var hoveredObjective: String?
    @State private var chartAnimationProgress: CGFloat = 0

    // MARK: - Layout

    private enum Layout {
        static let maxContentWidth: CGFloat = 680
        static let objectiveCardHeight: CGFloat = 88
        static let trajectoryHeight: CGFloat = 160
        static let quarterPillWidth: CGFloat = 60
    }

    // MARK: - Quarter Enum

    private enum Quarter: Int, CaseIterable {
        case q1 = 1, q2 = 2, q3 = 3, q4 = 4

        var label: String {
            "Q\(rawValue)"
        }

        static var current: Quarter {
            let month = Calendar.current.component(.month, from: Date())
            switch month {
            case 1...3: return .q1
            case 4...6: return .q2
            case 7...9: return .q3
            default: return .q4
            }
        }

        var months: [String] {
            switch self {
            case .q1: return ["Jan", "Feb", "Mar", "Apr"]
            case .q2: return ["Apr", "May", "Jun", "Jul"]
            case .q3: return ["Jul", "Aug", "Sep", "Oct"]
            case .q4: return ["Oct", "Nov", "Dec", "Jan"]
            }
        }
    }

    // MARK: - Body

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: PlannerumLayout.spacingXXL) {
                // Quarter selector
                quarterSelector

                // Core objectives section
                coreObjectivesSection

                // XP trajectory chart
                trajectorySection
            }
            .frame(maxWidth: Layout.maxContentWidth)
            .padding(.horizontal, PlannerumLayout.spacingXXL)
            .padding(.top, PlannerumLayout.spacingLG)
            .padding(.bottom, 80) // Extra bottom padding to prevent cutoff
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                await viewModel.loadData(for: selectedQuarter.rawValue)
            }
            animateChartIn()
        }
        .onChange(of: selectedQuarter) { _, newQuarter in
            Task {
                await viewModel.loadData(for: newQuarter.rawValue)
            }
            animateChartIn()
        }
    }

    // MARK: - Quarter Selector

    private var quarterSelector: some View {
        VStack(spacing: PlannerumLayout.spacingMD) {
            // Year and quarter title
            HStack(spacing: PlannerumLayout.spacingSM) {
                Text(selectedQuarter.label)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(PlannerumColors.textPrimary)

                Text("\(Calendar.current.component(.year, from: Date()))")
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .foregroundColor(PlannerumColors.textTertiary)
            }
            .tracking(8)

            // Quarter pills
            HStack(spacing: 8) {
                ForEach(Quarter.allCases, id: \.rawValue) { quarter in
                    quarterPill(quarter)
                }
            }
        }
    }

    private func quarterPill(_ quarter: Quarter) -> some View {
        let isSelected = selectedQuarter == quarter
        let isCurrent = quarter == Quarter.current

        return Button(action: {
            withAnimation(PlannerumSprings.select) {
                selectedQuarter = quarter
            }
        }) {
            VStack(spacing: 2) {
                Text(quarter.label)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(
                        isSelected
                            ? PlannerumColors.textPrimary
                            : PlannerumColors.textMuted
                    )

                if isCurrent {
                    Circle()
                        .fill(PlannerumColors.nowMarker)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: Layout.quarterPillWidth, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                            ? PlannerumColors.primary.opacity(0.2)
                            : Color.white.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected
                            ? PlannerumColors.primary.opacity(0.4)
                            : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Core Objectives Section

    private var coreObjectivesSection: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingLG) {
            // Section header
            Text("CORE OBJECTIVES")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(3)

            // Objectives container (floating glass)
            VStack(spacing: PlannerumLayout.spacingMD) {
                if viewModel.objectives.isEmpty {
                    emptyObjectivesState
                } else {
                    ForEach(viewModel.objectives) { objective in
                        objectiveCard(objective)
                    }
                }

                // Add objective button
                addObjectiveButton
            }
            .padding(PlannerumLayout.spacingLG)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.04))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private func objectiveCard(_ objective: CoreObjective) -> some View {
        let isHovered = hoveredObjective == objective.id

        return VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            // Header: Icon + Title + Progress
            HStack(spacing: PlannerumLayout.spacingSM) {
                // Icon
                Image(systemName: objective.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(objective.color)
                    .frame(width: 32, height: 32)
                    .background(objective.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Title
                Text(objective.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Progress percentage
                Text("\(Int(objective.progress * 100))%")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(objective.color)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [objective.color, objective.color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(objective.progress), height: 8)
                        .shadow(color: objective.color.opacity(0.4), radius: 4, x: 0, y: 0)
                }
            }
            .frame(height: 8)

            // Stats
            HStack(spacing: PlannerumLayout.spacingMD) {
                statLabel(value: "\(objective.blocksCompleted)", label: "blocks")
                statLabel(value: formatHours(objective.hoursInvested), label: "invested")

                Spacer()

                if objective.progress >= 1.0 {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PlannerumColors.nowMarker)
                }
            }
        }
        .padding(PlannerumLayout.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isHovered ? objective.color.opacity(0.3) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(PlannerumSprings.hover, value: isHovered)
        .onHover { hovering in
            hoveredObjective = hovering ? objective.id : nil
        }
    }

    private func statLabel(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(PlannerumColors.textSecondary)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(PlannerumColors.textMuted)
        }
    }

    private var emptyObjectivesState: some View {
        VStack(spacing: PlannerumLayout.spacingMD) {
            Image(systemName: "star.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(PlannerumColors.primary.opacity(0.4))

            Text("No objectives set for this quarter")
                .font(.system(size: 14))
                .foregroundColor(PlannerumColors.textMuted)

            Text("Set strategic goals to track your progress")
                .font(.system(size: 12))
                .foregroundColor(PlannerumColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PlannerumLayout.spacingXXL)
    }

    private var addObjectiveButton: some View {
        Button(action: {
            // TODO: Open add objective sheet
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))

                Text("Add Core Objective")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(PlannerumColors.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(PlannerumColors.primary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(PlannerumColors.primary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trajectory Section

    private var trajectorySection: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingLG) {
            // Section header
            Text("QUARTER TRAJECTORY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(3)

            // Chart container
            VStack(spacing: PlannerumLayout.spacingMD) {
                trajectoryChart
                trajectoryLegend
            }
            .padding(PlannerumLayout.spacingLG)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private var trajectoryChart: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Grid lines
                trajectoryGrid(width: width, height: height)

                // XP line chart
                trajectoryLine(width: width, height: height)

                // Data points
                trajectoryPoints(width: width, height: height)
            }
        }
        .frame(height: Layout.trajectoryHeight)
    }

    private func trajectoryGrid(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let horizontalLines = 4
            let verticalLines = 4

            // Horizontal grid lines
            for i in 0...horizontalLines {
                let y = CGFloat(i) * (height / CGFloat(horizontalLines))
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
                context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
            }

            // Vertical grid lines (month markers)
            for i in 0...verticalLines {
                let x = CGFloat(i) * (width / CGFloat(verticalLines))
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
            }
        }
    }

    private func trajectoryLine(width: CGFloat, height: CGFloat) -> some View {
        let dataPoints = viewModel.trajectoryData
        guard dataPoints.count > 1 else { return AnyView(EmptyView()) }

        let maxXP = viewModel.targetXP
        let pointsCount = dataPoints.count

        return AnyView(
            Path { path in
                for (index, point) in dataPoints.enumerated() {
                    let x = CGFloat(index) / CGFloat(pointsCount - 1) * width
                    let y = height - (CGFloat(point.xp) / CGFloat(maxXP) * height)

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .trim(from: 0, to: chartAnimationProgress)
            .stroke(
                LinearGradient(
                    colors: [PlannerumColors.primary, PlannerumColors.xpGold],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: PlannerumColors.primary.opacity(0.4), radius: 8, x: 0, y: 0)
        )
    }

    private func trajectoryPoints(width: CGFloat, height: CGFloat) -> some View {
        let dataPoints = viewModel.trajectoryData
        let maxXP = viewModel.targetXP
        let pointsCount = max(dataPoints.count, 1)

        return ZStack {
            ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                let x = CGFloat(index) / CGFloat(pointsCount - 1) * width
                let y = height - (CGFloat(point.xp) / CGFloat(maxXP) * height)

                // Point
                Circle()
                    .fill(PlannerumColors.primary)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: PlannerumColors.primary.opacity(0.5), radius: 4, x: 0, y: 0)
                    .position(x: x, y: y)
                    .opacity(chartAnimationProgress > CGFloat(index) / CGFloat(pointsCount) ? 1 : 0)

                // XP label
                Text(formatXP(point.xp))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PlannerumColors.textSecondary)
                    .position(x: x, y: y - 18)
                    .opacity(chartAnimationProgress > CGFloat(index) / CGFloat(pointsCount) ? 1 : 0)
            }
        }
    }

    private var trajectoryLegend: some View {
        HStack {
            // Month labels
            ForEach(selectedQuarter.months, id: \.self) { month in
                Text(month)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func formatHours(_ hours: Double) -> String {
        if hours >= 100 {
            return String(format: "%.0fh", hours)
        } else if hours >= 10 {
            return String(format: "%.1fh", hours)
        }
        return String(format: "%.1fh", hours)
    }

    private func formatXP(_ xp: Int) -> String {
        if xp >= 1000 {
            return String(format: "%.1fK", Double(xp) / 1000)
        }
        return "\(xp)"
    }

    private func animateChartIn() {
        chartAnimationProgress = 0
        withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
            chartAnimationProgress = 1.0
        }
    }
}

// MARK: - Quarter View Model

@MainActor
public class QuarterViewModel: ObservableObject {

    @Published public var objectives: [CoreObjective] = []
    @Published public var trajectoryData: [TrajectoryPoint] = []
    @Published public var targetXP: Int = 60000
    @Published public var currentXP: Int = 0

    public func loadData(for quarter: Int) async {
        // For now, use sample objectives
        // In the future, this could load from a dedicated objectives store
        objectives = sampleObjectives

        // Load XP trajectory data
        await loadTrajectoryData(for: quarter)
    }

    private func loadTrajectoryData(for quarter: Int) async {
        // Calculate XP trajectory from xpEvents
        do {
            let events = try await AtomRepository.shared.fetchAll(type: .xpEvent)
                .filter { !$0.isDeleted }

            var runningTotal = 0

            for event in events {
                // Extract XP from metadata using generic approach
                if let metadata = event.metadata,
                   let data = metadata.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let xp = json["xpAmount"] as? Int {
                    runningTotal += xp
                }
            }

            currentXP = runningTotal

            // Build trajectory based on current XP
            let monthProgress = Double(Calendar.current.component(.month, from: Date()) % 3 + 1) / 4.0
            let projectedMonthlyRate = currentXP > 0 ? Int(Double(currentXP) / monthProgress) : 15000

            trajectoryData = [
                TrajectoryPoint(month: 0, xp: Int(Double(projectedMonthlyRate) * 0.25)),
                TrajectoryPoint(month: 1, xp: Int(Double(projectedMonthlyRate) * 0.55)),
                TrajectoryPoint(month: 2, xp: max(currentXP, Int(Double(projectedMonthlyRate) * 0.85)))
            ]

        } catch {
            print("QuarterViewModel: Failed to load trajectory - \(error)")
            trajectoryData = sampleTrajectory
        }
    }

    // MARK: - Sample Data

    private var sampleObjectives: [CoreObjective] {
        [
            CoreObjective(
                id: "sample-1",
                title: "Launch CosmoOS Beta",
                icon: "star.fill",
                color: PlannerumColors.primary,
                progress: 0.58,
                blocksCompleted: 12,
                hoursInvested: 45
            ),
            CoreObjective(
                id: "sample-2",
                title: "Complete 100 Deep Work Sessions",
                icon: "brain.head.profile",
                color: Color(red: 99/255, green: 102/255, blue: 241/255),
                progress: 0.78,
                blocksCompleted: 78,
                hoursInvested: 156
            ),
            CoreObjective(
                id: "sample-3",
                title: "Reach Level 30",
                icon: "arrow.up.circle.fill",
                color: PlannerumColors.xpGold,
                progress: 0.80,
                blocksCompleted: 0,
                hoursInvested: 0
            )
        ]
    }

    private var sampleTrajectory: [TrajectoryPoint] {
        [
            TrajectoryPoint(month: 0, xp: 12000),
            TrajectoryPoint(month: 1, xp: 24000),
            TrajectoryPoint(month: 2, xp: 42000)
        ]
    }
}

// MARK: - Models

public struct CoreObjective: Identifiable {
    public let id: String
    public let title: String
    public let icon: String
    public let color: Color
    public let progress: Double
    public let blocksCompleted: Int
    public let hoursInvested: Double
}

public struct TrajectoryPoint {
    public let month: Int
    public let xp: Int
}


// MARK: - Preview

#if DEBUG
struct QuarterView_Previews: PreviewProvider {
    static var previews: some View {
        QuarterView()
            .background(PlannerumColors.voidPrimary)
            .preferredColorScheme(.dark)
    }
}
#endif
