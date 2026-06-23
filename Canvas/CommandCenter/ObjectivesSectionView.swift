import SwiftUI

struct ObjectivesSectionView: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    @State private var showingEditor = false
    @State private var editingObjective: ObjectiveState?
    @State private var isAddHovered = false

    var body: some View {
        CommandCenterPlanningPageScaffold(
            title: "Objectives",
            icon: "scope",
            subtitle: subtitle,
            accent: DS.accent,
            actions: { addButton },
            content: { content }
        )
        .sheet(isPresented: $showingEditor) {
            ObjectiveEditorSheet(viewModel: viewModel, objective: editingObjective)
        }
    }

    private var subtitle: String {
        let active = viewModel.objectives.filter { $0.progress < 1 }.count
        return "Q\(currentQuarter) · \(active) active · pacing from real work"
    }

    private var addButton: some View {
        Button {
            editingObjective = nil
            showingEditor = true
        } label: {
            Image(systemName: "plus")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.textOnAccent)
                .frame(width: 44, height: 44)
                .background(DS.accent, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isAddHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isAddHovered)
        .onHover { isAddHovered = $0 }
        .keyboardShortcut("n", modifiers: [.command])
        .help("Add objective (Command-N)")
        .accessibilityLabel("Add objective")
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DS.space16) {
                ObjectiveQuarterHero(objectives: viewModel.objectives)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DS.space16) {
                        ObjectivePacingGrid(objectives: viewModel.objectives) { objective in
                            editingObjective = objective
                            showingEditor = true
                        }
                        .frame(maxWidth: .infinity)

                        objectiveSupportColumn
                            .frame(width: 320)
                    }

                    VStack(alignment: .leading, spacing: DS.space16) {
                        ObjectivePacingGrid(objectives: viewModel.objectives) { objective in
                            editingObjective = objective
                            showingEditor = true
                        }
                        objectiveSupportColumn
                    }
                }
            }
            .padding(.bottom, DS.space24)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var objectiveSupportColumn: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            ObjectiveReviewPane(objectives: viewModel.objectives)
            ObjectiveDataSourcesPane()
        }
    }

    private var currentQuarter: Int {
        let month = Calendar.current.component(.month, from: Date())
        return (month - 1) / 3 + 1
    }
}

private struct ObjectiveQuarterHero: View {
    let objectives: [ObjectiveState]

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space16) {
            HStack(alignment: .center, spacing: DS.space18) {
                VStack(alignment: .leading, spacing: DS.space8) {
                    Text("Quarter pacing")
                        .font(DS.title2)
                        .foregroundStyle(DS.commandCenterTitleText)

                    Text(healthLine)
                        .font(DS.callout)
                        .foregroundStyle(DS.commandCenterSecondaryText)
                        .lineLimit(2)

                    ObjectiveProgressTrack(progress: averageProgress, tint: heroTint)
                        .frame(maxWidth: 520)
                }

                Spacer(minLength: DS.space16)

                ObjectiveMetric(title: "Active", value: "\(activeCount)", tint: DS.accent)
                ObjectiveMetric(title: "Complete", value: "\(completedCount)", tint: DS.green)
                ObjectiveMetric(title: "Average", value: "\(Int(averageProgress * 100))%", tint: heroTint)
            }
        }
    }

    private var activeCount: Int {
        objectives.filter { $0.progress < 1 }.count
    }

    private var completedCount: Int {
        objectives.filter { $0.progress >= 1 }.count
    }

    private var averageProgress: Double {
        guard !objectives.isEmpty else { return 0 }
        return objectives.map(\.progress).reduce(0, +) / Double(objectives.count)
    }

    private var heroTint: Color {
        let riskCount = objectives.filter { $0.paceStatus == .behind || $0.paceStatus == .atRisk }.count
        if objectives.isEmpty { return DS.info }
        if riskCount == 0 { return DS.green }
        if riskCount <= 1 { return DS.orange }
        return DS.red
    }

    private var healthLine: String {
        guard !objectives.isEmpty else {
            return "Create one objective tied to work the app can already measure."
        }

        let behind = objectives.filter { $0.paceStatus == .behind }.count
        let atRisk = objectives.filter { $0.paceStatus == .atRisk }.count
        if behind > 0 {
            return "\(behind) objective\(behind == 1 ? "" : "s") need scheduled work before the next review."
        }
        if atRisk > 0 {
            return "\(atRisk) objective\(atRisk == 1 ? "" : "s") need a target check or steadier cadence."
        }
        return "The quarter is moving with the current cadence."
    }
}

private struct ObjectivePacingGrid: View {
    let objectives: [ObjectiveState]
    let onEdit: (ObjectiveState) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 260), spacing: DS.space12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            ObjectiveSectionHeader(title: "Pacing", count: "\(objectives.count)", tint: DS.accent)

            if objectives.isEmpty {
                CommandCenterEmptyPane(
                    icon: "scope",
                    title: "Choose one measurable aim",
                    subtitle: "Objectives work best when they are tied to sessions, completed tasks, or published output."
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: DS.space12) {
                    ForEach(objectives) { objective in
                        ObjectivePacingCard(objective: objective) {
                            onEdit(objective)
                        }
                    }
                }
            }
        }
    }
}

private struct ObjectivePacingCard: View {
    let objective: ObjectiveState
    let onEdit: () -> Void

    @State private var isHovered = false
    @State private var isEditHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack(alignment: .top, spacing: DS.space8) {
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(objective.title)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)

                    Text("Q\(objective.quarter) \(objective.year)")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }

                Spacer(minLength: DS.space8)
                editButton
            }

            ObjectiveProgressTrack(progress: objective.progress, tint: objective.paceStatus.color)

            HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                Text(formatObjectiveValue(objective.currentValue))
                    .font(DS.title2)
                    .monospacedDigit()
                    .foregroundStyle(objective.paceStatus.color)

                Text("/ \(formatObjectiveValue(objective.targetValue)) \(objective.unit)")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }

            HStack(spacing: DS.space8) {
                paceChip
                Spacer(minLength: 0)
                Text(nextMove)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .lineLimit(1)
            }
        }
        .padding(DS.space12)
        .background(DS.commandChromePanelFill, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovered ? objective.paceStatus.color.opacity(0.24) : DS.commandChromeBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0.035), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 3 : 1)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "slider.horizontal.3")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(isEditHovered ? DS.textSecondary : DS.textMuted)
                .frame(width: 44, height: 44)
                .background(isEditHovered ? DS.glassInputFill : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isEditHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isEditHovered)
        .onHover { isEditHovered = $0 }
        .help("Edit \(objective.title)")
        .accessibilityLabel("Edit \(objective.title)")
    }

    private var paceChip: some View {
        Label(objective.paceStatus.displayName, systemImage: objective.paceStatus.iconName)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(objective.paceStatus.color)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(objective.paceStatus.color.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(objective.paceStatus.color.opacity(0.22), lineWidth: 0.5))
    }

    private var nextMove: String {
        switch objective.paceStatus {
        case .behind:
            return "schedule a focus block"
        case .atRisk:
            return "review target"
        case .onTrack:
            return "keep cadence"
        case .completed:
            return "close or archive"
        case .justStarted:
            return "choose first session"
        }
    }
}

private struct ObjectiveReviewPane: View {
    let objectives: [ObjectiveState]

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space10) {
                ObjectiveSectionHeader(title: "Review", count: nil, tint: reviewTint)

                if reviewObjectives.isEmpty {
                    Text("Nothing urgent is pulling against the quarter. Use the next planning review to protect cadence.")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        ForEach(reviewObjectives) { objective in
                            ObjectiveReviewRow(objective: objective)
                        }
                    }
                }
            }
        }
    }

    private var reviewObjectives: [ObjectiveState] {
        Array(objectives.filter { $0.paceStatus == .behind || $0.paceStatus == .atRisk || $0.paceStatus == .justStarted }.prefix(4))
    }

    private var reviewTint: Color {
        reviewObjectives.contains { $0.paceStatus == .behind } ? DS.orange : DS.accent
    }
}

private struct ObjectiveReviewRow: View {
    let objective: ObjectiveState

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: objective.paceStatus.iconName)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(objective.paceStatus.color)
                .frame(width: 24, height: 24)
                .background(objective.paceStatus.color.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(objective.title)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Text(nextMove)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nextMove: String {
        switch objective.paceStatus {
        case .behind:
            return "Schedule work before changing the target."
        case .atRisk:
            return "Review the target and protect a repeatable block."
        case .justStarted:
            return "Choose the first session that proves motion."
        case .onTrack:
            return "Keep the current cadence."
        case .completed:
            return "Close it during review."
        }
    }
}

private struct ObjectiveDataSourcesPane: View {
    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space10) {
                ObjectiveSectionHeader(title: "Sources", count: nil, tint: DS.info)

                VStack(alignment: .leading, spacing: DS.space8) {
                    sourceRow(icon: "timer", title: "Deep work", subtitle: "sessions completed")
                    sourceRow(icon: "checkmark.circle", title: "Tasks", subtitle: "completed tasks")
                    sourceRow(icon: "sparkles", title: "XP and levels", subtitle: "Plannerum progress")
                    sourceRow(icon: "square.and.pencil", title: "Published work", subtitle: "content output")
                }
            }
        }
    }

    private func sourceRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.info)
                .frame(width: 24, height: 24)
                .background(DS.info.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.text)
                Text(subtitle)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }
}

private struct ObjectiveEditorSheet: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    let objective: ObjectiveState?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var targetValue: String
    @State private var unit: String
    @State private var dataSource: ObjectiveDataSource

    init(viewModel: CommandCenterDashboardViewModel, objective: ObjectiveState?) {
        self.viewModel = viewModel
        self.objective = objective
        _title = State(initialValue: objective?.title ?? "")
        _targetValue = State(initialValue: objective.map { formatObjectiveValue($0.targetValue) } ?? "")
        _unit = State(initialValue: objective?.unit ?? "sessions")
        _dataSource = State(initialValue: objective?.dataSource ?? .deepWorkSessionCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space18) {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text(objective == nil ? "New Objective" : "Edit Objective")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)

                Text("Tie the target to work Cosmo can already measure.")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
            }

            VStack(alignment: .leading, spacing: DS.space12) {
                labeledField("Title") {
                    TextField("Publish 12 essays", text: $title)
                        .textFieldStyle(.plain)
                }

                HStack(spacing: DS.space12) {
                    labeledField("Target") {
                        TextField("12", text: $targetValue)
                            .textFieldStyle(.plain)
                    }

                    labeledField("Unit") {
                        TextField("sessions", text: $unit)
                            .textFieldStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: DS.space6) {
                    Text("Source")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textMuted)

                    Picker("Source", selection: $dataSource) {
                        ForEach(ObjectiveDataSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack(spacing: DS.space8) {
                if let objective {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteObjective(id: objective.id)
                            dismiss()
                        }
                    } label: {
                        Text("Delete")
                            .font(DS.buttonText)
                            .foregroundStyle(DS.red)
                            .frame(height: 36)
                            .padding(.horizontal, DS.space12)
                    }
                    .buttonStyle(.plain)
                    .help("Delete objective")
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .font(DS.buttonText)
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        await save()
                        dismiss()
                    }
                } label: {
                    Text(objective == nil ? "Create Objective" : "Save Objective")
                        .font(DS.buttonText)
                        .foregroundStyle(canSave ? DS.textOnAccent : DS.textMuted)
                        .frame(height: 36)
                        .padding(.horizontal, DS.space16)
                        .background(canSave ? DS.accent : DS.glassInputFill, in: .rect(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .help(objective == nil ? "Create objective" : "Save objective")
            }
        }
        .padding(DS.space24)
        .frame(width: 440)
        .background(DS.bg)
    }

    private func labeledField<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(label)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)

            field()
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .padding(.horizontal, DS.space10)
                .frame(height: 38)
                .background(DS.glassInputFill, in: .rect(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.glassBorder, lineWidth: 0.5)
                )
        }
    }

    @MainActor
    private func save() async {
        guard let target = Double(targetValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)

        if let objective {
            await viewModel.updateObjective(
                id: objective.id,
                title: cleanTitle,
                targetValue: target,
                unit: cleanUnit,
                dataSource: dataSource
            )
        } else {
            await viewModel.createObjective(
                title: cleanTitle,
                targetValue: target,
                unit: cleanUnit,
                dataSource: dataSource
            )
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Double(targetValue.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }
}

private struct ObjectiveProgressTrack: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let width = max(proxy.size.width * CGFloat(clampedProgress), clampedProgress > 0 ? 8 : 0)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DS.glassInputFill)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint)
                    .frame(width: width)

                Circle()
                    .fill(tint)
                    .frame(width: 12, height: 12)
                    .offset(x: max(width - 6, 0))
                    .opacity(clampedProgress > 0 ? 1 : 0)
            }
        }
        .frame(height: 8)
    }
}

private struct ObjectiveMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.space4) {
            Text(value)
                .font(DS.title2)
                .monospacedDigit()
                .foregroundStyle(tint)

            Text(title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
        }
    }
}

private struct ObjectiveSectionHeader: View {
    let title: String
    let count: String?
    let tint: Color

    var body: some View {
        HStack(spacing: DS.space6) {
            Text(title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(tint)

            if let count {
                Text(count)
                    .font(DS.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(0.66))
            }

            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
        }
    }
}

private func formatObjectiveValue(_ value: Double) -> String {
    if value.rounded() == value {
        return "\(Int(value))"
    }
    return String(format: "%.1f", value)
}
