// CosmoOS/UI/Plannerum/QuarterView.swift
// Quarter View - Core Objectives and XP Trajectory visualization
// Strategic planning view matching Sanctuary's immersive realm aesthetic

import SwiftUI

// MARK: - Quarter View

/// The Quarter View displays core objectives and XP trajectory for strategic planning.
/// Matches Sanctuary's immersive feel with floating glass containers.
public struct QuarterView: View {

    // MARK: - State

    @StateObject private var viewModel = QuarterViewModel()
    @StateObject private var objectiveEngine = ObjectiveEngine()
    @State private var selectedQuarter: Quarter = .current
    @State private var hoveredObjective: String?
    @State private var chartAnimationProgress: CGFloat = 0
    @State private var showAddObjectiveSheet = false
    @State private var editingObjective: ObjectiveState?
    @State private var showDeleteConfirmation = false
    @State private var objectiveToDelete: ObjectiveState?

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
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            objectiveEngine.startTracking()
            Task {
                await viewModel.loadData(for: selectedQuarter.rawValue)
            }
            animateChartIn()
        }
        .onDisappear {
            objectiveEngine.stopTracking()
        }
        .onChange(of: selectedQuarter) { _, newQuarter in
            Task {
                await viewModel.loadData(for: newQuarter.rawValue)
            }
            animateChartIn()
        }
        .sheet(isPresented: $showAddObjectiveSheet) {
            AddObjectiveSheet(
                objectiveEngine: objectiveEngine,
                quarter: selectedQuarter.rawValue,
                year: Calendar.current.component(.year, from: Date())
            )
        }
        .sheet(item: $editingObjective) { objective in
            AddObjectiveSheet(
                objectiveEngine: objectiveEngine,
                quarter: objective.quarter,
                year: objective.year,
                editingObjective: objective
            )
        }
        .alert("Delete Objective", isPresented: $showDeleteConfirmation, presenting: objectiveToDelete) { objective in
            Button("Delete", role: .destructive) {
                Task {
                    try? await objectiveEngine.deleteObjective(id: objective.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { objective in
            Text("Are you sure you want to delete \"\(objective.title)\"? This cannot be undone.")
        }
    }

    // MARK: - Quarter Selector

    private var quarterSelector: some View {
        VStack(spacing: PlannerumLayout.spacingMD) {
            HStack(spacing: PlannerumLayout.spacingSM) {
                Text(selectedQuarter.label)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(PlannerumColors.textPrimary)

                Text("\(Calendar.current.component(.year, from: Date()))")
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .foregroundColor(PlannerumColors.textTertiary)
            }
            .tracking(8)

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
        let currentYear = Calendar.current.component(.year, from: Date())
        let quarterObjectives = objectiveEngine.objectives(
            for: selectedQuarter.rawValue,
            year: currentYear
        )

        return VStack(alignment: .leading, spacing: PlannerumLayout.spacingLG) {
            Text("CORE OBJECTIVES")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(3)

            VStack(spacing: PlannerumLayout.spacingMD) {
                if quarterObjectives.isEmpty {
                    emptyObjectivesState
                } else {
                    ForEach(quarterObjectives) { objective in
                        objectiveCard(objective)
                    }
                }

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

    private func objectiveCard(_ objective: ObjectiveState) -> some View {
        let isHovered = hoveredObjective == objective.id
        let accentColor = objective.paceStatus.color

        return VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            // Header: Icon + Title + Progress
            HStack(spacing: PlannerumLayout.spacingSM) {
                Image(systemName: objective.paceStatus.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(accentColor)
                    .frame(width: 32, height: 32)
                    .background(accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(objective.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PlannerumColors.textPrimary)
                        .lineLimit(1)

                    // Value label
                    Text("\(Int(objective.currentValue)) / \(Int(objective.targetValue)) \(objective.unit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PlannerumColors.textTertiary)
                }

                Spacer()

                // Progress + Pace pill
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(objective.progress * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor)

                    paceStatusPill(objective.paceStatus)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * CGFloat(objective.progress),
                            height: 8
                        )
                        .shadow(color: accentColor.opacity(0.4), radius: 4, x: 0, y: 0)
                        .animation(PlannerumSprings.expand, value: objective.progress)
                }
            }
            .frame(height: 8)

            // Stats
            HStack(spacing: PlannerumLayout.spacingMD) {
                if objective.totalHoursInvested > 0 {
                    statLabel(
                        value: formatHours(objective.totalHoursInvested),
                        label: "invested"
                    )
                }

                statLabel(
                    value: objective.dataSource.displayName,
                    label: ""
                )

                Spacer()

                if objective.paceStatus == .completed {
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
                            isHovered ? accentColor.opacity(0.3) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(PlannerumSprings.hover, value: isHovered)
        .onHover { hovering in
            hoveredObjective = hovering ? objective.id : nil
        }
        .contextMenu {
            Button {
                editingObjective = objective
            } label: {
                Label("Edit Objective", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                objectiveToDelete = objective
                showDeleteConfirmation = true
            } label: {
                Label("Delete Objective", systemImage: "trash")
            }
        }
    }

    private func paceStatusPill(_ status: PaceStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(status.color.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
                    )
            )
    }

    private func statLabel(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(PlannerumColors.textSecondary)

            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(PlannerumColors.textMuted)
            }
        }
    }

    private var emptyObjectivesState: some View {
        VStack(spacing: PlannerumLayout.spacingLG) {
            Image(systemName: "target")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(PlannerumColors.primary.opacity(0.4))

            VStack(spacing: 6) {
                Text("Set your quarterly goals to track long-term progress.")
                    .font(.system(size: 14))
                    .foregroundColor(PlannerumColors.textSecondary)
                    .multilineTextAlignment(.center)

                Text("Objectives connect to real data sources and update automatically.")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)

            Button(action: {
                showAddObjectiveSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add Objective")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(PlannerumColors.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PlannerumLayout.spacingXXL)
    }

    private var addObjectiveButton: some View {
        Button(action: {
            showAddObjectiveSheet = true
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
        let currentYear = Calendar.current.component(.year, from: Date())
        let quarterObjectives = objectiveEngine.objectives(
            for: selectedQuarter.rawValue,
            year: currentYear
        )
        let daysOfData = trajectoryDaysOfData(objectives: quarterObjectives)

        return VStack(alignment: .leading, spacing: PlannerumLayout.spacingLG) {
            Text("QUARTER TRAJECTORY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(3)

            VStack(spacing: PlannerumLayout.spacingMD) {
                if daysOfData < 7 {
                    trajectoryCountdown(daysOfData: daysOfData)
                } else {
                    trajectoryChart
                }
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

    private func trajectoryDaysOfData(objectives: [ObjectiveState]) -> Int {
        guard !objectives.isEmpty else { return 0 }
        let oldest = objectives.map(\.createdAt).min() ?? Date()
        let days = Int(Date().timeIntervalSince(oldest) / 86400)
        return max(days, 0)
    }

    private func trajectoryCountdown(daysOfData: Int) -> some View {
        let remaining = max(7 - daysOfData, 0)
        let progress = CGFloat(daysOfData) / 7.0

        return VStack(spacing: PlannerumLayout.spacingMD) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 4)
                    .frame(width: 56, height: 56)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        PlannerumColors.primary,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Text("\(daysOfData)/7")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(PlannerumColors.textSecondary)
            }

            VStack(spacing: 4) {
                Text("Collecting data...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PlannerumColors.textPrimary)

                Text("\(remaining) more day\(remaining == 1 ? "" : "s") until trajectory is available")
                    .font(.system(size: 13))
                    .foregroundColor(PlannerumColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.trajectoryHeight)
    }

    private var trajectoryChart: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                trajectoryGrid(width: width, height: height)
                trajectoryLine(width: width, height: height)
                trajectoryPoints(width: width, height: height)
            }
        }
        .frame(height: Layout.trajectoryHeight)
    }

    private func trajectoryGrid(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let horizontalLines = 4
            let verticalLines = 4

            for i in 0...horizontalLines {
                let y = CGFloat(i) * (height / CGFloat(horizontalLines))
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
                context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
            }

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

// MARK: - Add Objective Sheet

struct AddObjectiveSheet: View {
    @ObservedObject var objectiveEngine: ObjectiveEngine
    let quarter: Int
    let year: Int
    var editingObjective: ObjectiveState? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var targetValue = ""
    @State private var unit = "sessions"
    @State private var selectedDataSource: ObjectiveDataSource = .deepWorkSessionCount
    @State private var previewValue: Double = 0
    @State private var isSaving = false

    private var isEditMode: Bool { editingObjective != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditMode ? "Edit Objective" : "Add Core Objective")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(PlannerumColors.textPrimary)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(PlannerumColors.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider().opacity(0.1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    formField(label: "OBJECTIVE TITLE") {
                        TextField("e.g., Complete 100 Deep Work Sessions", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundColor(PlannerumColors.textPrimary)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                    }

                    // Data Source
                    formField(label: "DATA SOURCE") {
                        VStack(spacing: 6) {
                            ForEach(ObjectiveDataSource.allCases, id: \.rawValue) { source in
                                dataSourceOption(source)
                            }
                        }
                    }

                    // Target + Unit (side by side)
                    HStack(spacing: 12) {
                        formField(label: "TARGET VALUE") {
                            TextField("100", text: $targetValue)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(PlannerumColors.textPrimary)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                        }

                        formField(label: "UNIT") {
                            TextField("sessions", text: $unit)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundColor(PlannerumColors.textPrimary)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                        }
                    }

                    // Preview
                    previewCard
                }
                .padding(24)
            }

            Divider().opacity(0.1)

            // Save button
            HStack {
                Spacer()

                Button(action: save) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Color.white)
                        }
                        Text(isEditMode ? "Update Objective" : "Save Objective")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                canSave
                                    ? PlannerumColors.primary
                                    : PlannerumColors.primary.opacity(0.4)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving)
            }
            .padding(24)
        }
        .frame(width: 480, height: 600)
        .background(PlannerumColors.voidPrimary)
        .onChange(of: selectedDataSource) { _, newSource in
            Task {
                previewValue = await objectiveEngine.previewValue(for: newSource)
            }
            // Auto-fill unit
            switch newSource {
            case .deepWorkSessionCount: unit = "sessions"
            case .contentPublishedCount: unit = "posts"
            case .totalXP: unit = "XP"
            case .currentLevel: unit = "level"
            case .tasksCompleted: unit = "tasks"
            case .customQuery: unit = ""
            }
        }
        .task {
            if let editing = editingObjective {
                title = editing.title
                targetValue = String(Int(editing.targetValue))
                unit = editing.unit
                selectedDataSource = editing.dataSource
            }
            previewValue = await objectiveEngine.previewValue(for: selectedDataSource)
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
        && (Double(targetValue) ?? 0) > 0
        && !unit.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func dataSourceOption(_ source: ObjectiveDataSource) -> some View {
        let isSelected = selectedDataSource == source

        return Button(action: {
            withAnimation(PlannerumSprings.micro) {
                selectedDataSource = source
            }
        }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isSelected ? PlannerumColors.primary : Color.white.opacity(0.1))
                    .frame(width: 8, height: 8)

                Text(source.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(
                        isSelected ? PlannerumColors.textPrimary : PlannerumColors.textSecondary
                    )

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? PlannerumColors.primary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT PROGRESS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(2)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(previewValue))")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(PlannerumColors.primary)

                    Text("current \(unit)")
                        .font(.system(size: 12))
                        .foregroundColor(PlannerumColors.textTertiary)
                }

                Spacer()

                if let target = Double(targetValue), target > 0 {
                    let pct = min(previewValue / target, 1.0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(PlannerumColors.textSecondary)

                        Text("of target")
                            .font(.system(size: 12))
                            .foregroundColor(PlannerumColors.textTertiary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(PlannerumColors.primary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(2)

            content()
        }
    }

    private func save() {
        guard canSave, let target = Double(targetValue) else { return }
        isSaving = true

        Task {
            if let editing = editingObjective {
                try? await objectiveEngine.updateObjective(
                    id: editing.id,
                    title: title.trimmingCharacters(in: .whitespaces),
                    targetValue: target,
                    unit: unit.trimmingCharacters(in: .whitespaces),
                    dataSource: selectedDataSource
                )
            } else {
                try? await objectiveEngine.createObjective(
                    title: title.trimmingCharacters(in: .whitespaces),
                    targetValue: target,
                    unit: unit.trimmingCharacters(in: .whitespaces),
                    dataSource: selectedDataSource,
                    quarter: quarter,
                    year: year
                )
            }
            isSaving = false
            dismiss()
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
        await loadTrajectoryData(for: quarter)
    }

    private func loadTrajectoryData(for quarter: Int) async {
        do {
            let events = try await AtomRepository.shared.fetchAll(type: .xpEvent)
                .filter { !$0.isDeleted }

            var runningTotal = 0

            for event in events {
                if let metadata = event.metadata,
                   let data = metadata.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let xp = json["xpAmount"] as? Int {
                    runningTotal += xp
                }
            }

            currentXP = runningTotal

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
