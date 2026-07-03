import SwiftUI

struct CommandCenterHabitEditorDraft: Equatable {
    var title: String = ""
    var icon: String = "repeat"
    var accentColor: String = "2D6A4F"
    var dailyTargetCount: Int = 1
    /// "count" (N×/day) or "minutes" (N min/day of tracked focus time)
    var goalType: String = "count"
    var dailyTargetMinutes: Int = 30
    var allowManualCompletion: Bool = true
    var keywordInput: String = ""
    var mappedIntents: Set<TaskIntent> = []
    var defaultIntentUUID: String? = nil

    var isTimeBased: Bool { goalType == "minutes" }

    init() {}

    init(habit: HabitDefinition) {
        title = habit.title
        icon = habit.icon
        accentColor = habit.accentColor
        dailyTargetCount = habit.dailyTargetCount
        goalType = habit.goalType ?? "count"
        dailyTargetMinutes = habit.dailyTargetMinutes ?? 30
        allowManualCompletion = habit.allowManualCompletion
        keywordInput = habit.keywordTriggers.joined(separator: ", ")
        mappedIntents = Set(habit.taskIntents)
        defaultIntentUUID = habit.defaultIntentUUID
    }

    var keywords: [String] {
        keywordInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct CommandCenterHabitComposer: View {
    let habit: HabitDefinition?
    let onSave: (CommandCenterHabitEditorDraft) -> Void
    let onArchive: (() -> Void)?
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    let onDisable: (() -> Void)?
    let onOpenLibrary: (() -> Void)?
    let onDismiss: () -> Void
    private let availableIntents: [IntentDefinition]

    @State private var draft: CommandCenterHabitEditorDraft

    init(
        habit: HabitDefinition?,
        onSave: @escaping (CommandCenterHabitEditorDraft) -> Void,
        onArchive: (() -> Void)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onDisable: (() -> Void)? = nil,
        onOpenLibrary: (() -> Void)? = nil,
        availableIntents: [IntentDefinition] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.habit = habit
        self.onSave = onSave
        self.onArchive = onArchive
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onDisable = onDisable
        self.onOpenLibrary = onOpenLibrary
        self.availableIntents = availableIntents
        self.onDismiss = onDismiss
        _draft = State(initialValue: habit.map(CommandCenterHabitEditorDraft.init(habit:)) ?? CommandCenterHabitEditorDraft())
    }

    private var isBuiltIn: Bool { habit?.isBuiltIn == true }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBuiltIn }

    var body: some View {
        CommandCenterComposerShell(
            title: habit == nil ? "NEW HABIT" : "HABIT",
            subtitle: draft.title.isEmpty ? "Shape a fresh orbit" : draft.title,
            chrome: .glass,
            onClose: onDismiss
        ) {
            VStack(alignment: .leading, spacing: DS.space20) {
                previewHeader
                identitySection
                cadenceSection
                mappingSection
                completionSection
                footer
            }
        }
    }

    private var previewHeader: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            Circle()
                .fill(previewTint.opacity(0.14))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: draft.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(previewTint)
                )
                .overlay(
                    Circle()
                        .stroke(previewTint.opacity(0.25), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title.isEmpty ? "Untitled Habit" : draft.title)
                    .font(DS.title2)
                    .foregroundStyle(DS.text)

                Text(previewSubtitle)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)

                if let onOpenLibrary {
                    Button("Open library →", action: onOpenLibrary)
                        .buttonStyle(.plain)
                        .font(DS.callout)
                        .foregroundStyle(DS.accent)
                }
            }
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            glassComposerSectionLabel("Identity")

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Title")
                    .font(DS.smallCaps).foregroundStyle(DS.textSecondary)

                TextField("Writing Habit", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space10)
                    .background(DS.glassInputFill, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.glassBorder, lineWidth: 0.5)
                    )
                    .disabled(isBuiltIn)
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Icon")
                    .font(DS.smallCaps).foregroundStyle(DS.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                    ForEach(habitIconOptions, id: \.self) { icon in
                        iconButton(icon)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Accent")
                    .font(DS.smallCaps).foregroundStyle(DS.textSecondary)

                HStack(spacing: DS.space10) {
                    ForEach(habitColorOptions, id: \.self) { color in
                        colorSwatch(color)
                    }
                }
            }
        }
    }

    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            glassComposerSectionLabel("Cadence")

            goalTypeSwitcher

            if draft.isTimeBased {
                minutesCadenceControls
            } else {
                countCadenceControls
            }
        }
    }

    private var goalTypeSwitcher: some View {
        HStack(spacing: DS.space8) {
            goalTypeChip(title: "Count", subtitle: "times per day", type: "count", icon: "checkmark.circle")
            goalTypeChip(title: "Time", subtitle: "minutes per day", type: "minutes", icon: "timer")
        }
    }

    private func goalTypeChip(title: String, subtitle: String, type: String, icon: String) -> some View {
        let isSelected = draft.goalType == type
        return Button {
            draft.goalType = type
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: icon)
                    .font(DS.caption)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(DS.caption.weight(.semibold))
                    Text(subtitle)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(isSelected ? DS.accentSoft : DS.glassInputFill, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBuiltIn)
        .help(type == "minutes" ? "Ring fills from tracked focus time on linked tasks" : "Ring fills from completions")
    }

    private var countCadenceControls: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space12) {
                cadenceStepButton(systemImage: "minus", enabled: draft.dailyTargetCount > 1) {
                    draft.dailyTargetCount = max(1, draft.dailyTargetCount - 1)
                }

                VStack(spacing: 2) {
                    Text("\(draft.dailyTargetCount)")
                        .font(DS.title1).monospacedDigit()
                        .foregroundStyle(DS.text)
                    Text(draft.dailyTargetCount == 1 ? "per day" : "times per day")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                }
                .frame(maxWidth: .infinity)

                cadenceStepButton(systemImage: "plus", enabled: draft.dailyTargetCount < 12) {
                    draft.dailyTargetCount = min(12, draft.dailyTargetCount + 1)
                }
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space12)
            .background(DS.glassInputFill, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )

            HStack(spacing: DS.space8) {
                ForEach([1, 2, 3, 5], id: \.self) { target in
                    cadenceChip(target)
                }
            }
        }
    }

    private var minutesCadenceControls: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space12) {
                cadenceStepButton(systemImage: "minus", enabled: draft.dailyTargetMinutes > 5) {
                    draft.dailyTargetMinutes = max(5, draft.dailyTargetMinutes - 5)
                }

                VStack(spacing: 2) {
                    Text("\(draft.dailyTargetMinutes)")
                        .font(DS.title1).monospacedDigit()
                        .foregroundStyle(DS.text)
                    Text("minutes per day")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                }
                .frame(maxWidth: .infinity)

                cadenceStepButton(systemImage: "plus", enabled: draft.dailyTargetMinutes < 480) {
                    draft.dailyTargetMinutes = min(480, draft.dailyTargetMinutes + 5)
                }
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space12)
            .background(DS.glassInputFill, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )

            HStack(spacing: DS.space8) {
                ForEach([15, 30, 60, 90], id: \.self) { target in
                    minutesCadenceChip(target)
                }
            }
        }
    }

    private func minutesCadenceChip(_ target: Int) -> some View {
        let isSelected = draft.dailyTargetMinutes == target
        return Button {
            draft.dailyTargetMinutes = target
        } label: {
            Text("\(target)m")
                .font(DS.callout)
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .background(isSelected ? DS.accentSoft : DS.glassInputFill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isBuiltIn)
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            glassComposerSectionLabel("Mapping")

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Intent bindings")
                    .font(DS.smallCaps).foregroundStyle(DS.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(TaskIntent.allCases.filter { $0 != .general && $0 != .custom }, id: \.self) { intent in
                        intentChip(intent)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Keyword triggers")
                    .font(DS.smallCaps).foregroundStyle(DS.textSecondary)

                TextField("write, draft, article", text: $draft.keywordInput)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space10)
                    .background(DS.glassInputFill, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.glassBorder, lineWidth: 0.5)
                    )
                    .disabled(isBuiltIn)
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Default intent")
                    .font(DS.smallCaps).foregroundStyle(DS.textSecondary)

                Menu {
                    Button("Unassigned") {
                        draft.defaultIntentUUID = nil
                    }

                    ForEach(availableIntents, id: \.id) { intent in
                        Button(intent.title) {
                            draft.defaultIntentUUID = intent.id
                        }
                    }
                } label: {
                    HStack(spacing: DS.space6) {
                        let selectedIntent = availableIntents.first(where: { $0.id == draft.defaultIntentUUID })
                        Image(systemName: selectedIntent?.icon ?? "questionmark.circle")
                            .font(DS.caption)
                        Text(selectedIntent?.title ?? "Unassigned")
                            .font(DS.callout)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(DS.caption2)
                    }
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space10)
                    .background(DS.glassInputFill, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.glassBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            glassComposerSectionLabel("Completion")

            Toggle(isOn: $draft.allowManualCompletion) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow manual check-ins")
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    Text("Lets the orbit card record progress even when there is no linked task.")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(DS.accent)
            .disabled(isBuiltIn)

            if isBuiltIn {
                Text("Built-in habits keep their core identity fixed so the command center stays coherent.")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 1)
                .opacity(0.7)

            HStack(spacing: DS.space10) {
                if !isBuiltIn, habit != nil {
                    utilityButton(title: "Up", icon: "arrow.up", action: { onMoveUp?() })
                    utilityButton(title: "Down", icon: "arrow.down", action: { onMoveDown?() })
                    utilityButton(title: "Archive", icon: "archivebox", tint: DS.red, action: { onArchive?() })
                }

                Spacer()

                if isBuiltIn, let onDisable {
                    utilityButton(title: "Disable", icon: "eye.slash", tint: DS.textMuted, action: onDisable)
                }

                Button("Close", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)

                Button(action: { onSave(draft) }) {
                    HStack(spacing: DS.space6) {
                        Text(habit == nil ? "Create" : "Save")
                            .font(DS.callout.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(DS.caption.weight(.semibold))
                    }
                    .foregroundStyle(canSave ? DS.textOnAccent : DS.textMuted)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space10)
                    .background(canSave ? DS.accent : DS.glassInputFill, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(canSave ? Color.clear : DS.glassBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
    }

    private var previewTint: Color {
        Color(hex: draft.accentColor)
    }

    private var previewSubtitle: String {
        if isBuiltIn { return "Built-in orbit" }
        if draft.isTimeBased { return "\(draft.dailyTargetMinutes) minutes per day" }
        if draft.dailyTargetCount == 1 { return "1 completion per day" }
        return "\(draft.dailyTargetCount) completions per day"
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = draft.icon == icon
        return Button {
            draft.icon = icon
        } label: {
            Image(systemName: icon)
                .font(DS.body).fontWeight(.medium)
                .foregroundStyle(isSelected ? previewTint : DS.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(isSelected ? previewTint.opacity(0.10) : DS.glassInputFill, in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? previewTint.opacity(0.25) : DS.glassBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isBuiltIn)
    }

    private func colorSwatch(_ color: String) -> some View {
        let tint = Color(hex: color)
        let isSelected = draft.accentColor == color
        return Button {
            draft.accentColor = color
        } label: {
            Circle()
                .fill(tint)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .stroke(isSelected ? DS.surface : Color.clear, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .stroke(tint.opacity(isSelected ? 0.9 : 0), lineWidth: 1)
                        .padding(-4)
                )
        }
        .buttonStyle(.plain)
        .disabled(isBuiltIn)
    }

    private func cadenceStepButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DS.subheadline).fontWeight(.semibold)
                .foregroundStyle(enabled ? DS.text : DS.textSecondary.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isBuiltIn)
    }

    private func cadenceChip(_ target: Int) -> some View {
        let isSelected = draft.dailyTargetCount == target
        return Button {
            draft.dailyTargetCount = target
        } label: {
            Text("\(target)")
                .font(DS.callout)
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .background(isSelected ? DS.accentSoft : DS.glassInputFill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isBuiltIn)
    }

    private func intentChip(_ intent: TaskIntent) -> some View {
        let isSelected = draft.mappedIntents.contains(intent)
        return Button {
            if isSelected {
                draft.mappedIntents.remove(intent)
            } else {
                draft.mappedIntents.insert(intent)
            }
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: intent.iconName)
                    .font(DS.caption2).fontWeight(.medium)
                Text(intent.displayName)
                    .font(DS.caption)
            }
            .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space8)
            .background(isSelected ? intent.color.opacity(0.10) : DS.glassInputFill, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? intent.color.opacity(0.22) : DS.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBuiltIn)
    }

    private func utilityButton(
        title: String,
        icon: String,
        tint: Color = DS.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Image(systemName: icon)
                    .font(DS.caption2).fontWeight(.medium)
                Text(title)
                    .font(DS.caption)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(DS.glassInputFill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private let habitIconOptions = [
        "repeat",
        "brain.head.profile",
        "book.fill",
        "paintbrush.fill",
        "heart.fill",
        "pencil.line",
        "waveform.path.ecg",
        "figure.walk",
        "sparkles",
        "bolt.fill",
        "leaf.fill",
        "figure.mind.and.body",
    ]

    private let habitColorOptions = [
        "2D6A4F",
        "5B84B0",
        "7B7EC0",
        "C4A870",
        "DC3545",
        "38B764",
        "D97706",
        "8B6BAB",
    ]
}

struct CommandCenterHabitLibraryComposer: View {
    let customHabits: [HabitDefinition]
    let builtInHabits: [(definition: HabitDefinition, isEnabled: Bool)]
    let onToggleBuiltIn: (String, Bool) -> Void
    let onCreate: () -> Void
    let onEdit: (HabitDefinition) -> Void
    let onClose: () -> Void

    var body: some View {
        CommandCenterComposerShell(title: "HABIT LIBRARY", subtitle: "Manage the orbits around your days", chrome: .glass, onClose: onClose) {
            VStack(alignment: .leading, spacing: DS.space20) {
                VStack(alignment: .leading, spacing: DS.space12) {
                    glassComposerSectionLabel("Custom")

                    if customHabits.isEmpty {
                        Text("No custom habits yet. Start one and map it to the kinds of work you want to reinforce.")
                            .font(DS.callout)
                            .foregroundStyle(DS.textSecondary)
                    } else {
                        ForEach(customHabits, id: \.id) { habit in
                            customHabitRow(habit)
                        }
                    }

                    Button(action: onCreate) {
                        HStack(spacing: DS.space6) {
                            Image(systemName: "plus")
                                .font(DS.caption2)
                            Text("New habit")
                                .font(DS.callout)
                        }
                        .foregroundStyle(DS.accent)
                        .padding(.vertical, DS.space6)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: DS.space12) {
                    glassComposerSectionLabel("Built In")

                    ForEach(builtInHabits, id: \.definition.id) { item in
                        builtInHabitRow(item)
                    }
                }
            }
        }
    }

    private func customHabitRow(_ habit: HabitDefinition) -> some View {
        Button {
            onEdit(habit)
        } label: {
            HStack(spacing: DS.space10) {
                Circle()
                    .fill(habit.accent.opacity(0.14))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: habit.icon)
                            .font(DS.callout).fontWeight(.medium)
                            .foregroundStyle(habit.accent)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.title)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    Text("\(habit.dailyTargetCount) per day")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(DS.glassInputFill, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func builtInHabitRow(_ item: (definition: HabitDefinition, isEnabled: Bool)) -> some View {
        HStack(spacing: DS.space10) {
            Circle()
                .fill(item.definition.accent.opacity(item.isEnabled ? 0.14 : 0.08))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: item.definition.icon)
                        .font(DS.callout).fontWeight(.medium)
                        .foregroundStyle(item.definition.accent.opacity(item.isEnabled ? 1 : 0.5))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.definition.title)
                    .font(DS.callout)
                    .foregroundStyle(item.isEnabled ? DS.text : DS.textSecondary)
                Text("Built-in")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { item.isEnabled },
                    set: { onToggleBuiltIn(item.definition.id, $0) }
                )
            )
            .toggleStyle(.switch)
            .tint(item.definition.accent)
            .labelsHidden()
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
        .background(DS.glassInputFill, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.glassBorder, lineWidth: 0.5)
        )
    }
}

#Preview("Habit Composer") {
    CommandCenterHabitComposer(
        habit: HabitDefinition.previewHabit(),
        onSave: { _ in },
        onOpenLibrary: {},
        onDismiss: {}
    )
    .frame(width: 440, height: 680)
    .padding()
    .background(DS.bg)
}

#Preview("Habit Library") {
    CommandCenterHabitLibraryComposer(
        customHabits: [HabitDefinition.previewHabit()],
        builtInHabits: [(HabitDefinition.previewHabit(), true)],
        onToggleBuiltIn: { _, _ in },
        onCreate: {},
        onEdit: { _ in },
        onClose: {}
    )
    .frame(width: 400, height: 560)
    .padding()
    .background(DS.bg)
}
