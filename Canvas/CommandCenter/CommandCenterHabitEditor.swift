import SwiftUI

struct CommandCenterHabitEditorDraft: Equatable {
    var title: String = ""
    var icon: String = "repeat"
    var accentColor: String = "2D6A4F"
    var dailyTargetCount: Int = 1
    var allowManualCompletion: Bool = true
    var keywordInput: String = ""
    var mappedIntents: Set<TaskIntent> = []
    var defaultIntentUUID: String? = nil

    init() {}

    init(habit: HabitDefinition) {
        title = habit.title
        icon = habit.icon
        accentColor = habit.accentColor
        dailyTargetCount = habit.dailyTargetCount
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
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(DS.text)

                Text(previewSubtitle)
                    .font(DS.callout)
                    .foregroundStyle(DS.inkFaded)

                if let onOpenLibrary {
                    Button("Open library →", action: onOpenLibrary)
                        .buttonStyle(.plain)
                        .font(DS.dateSerif)
                        .foregroundStyle(DS.gilt.opacity(0.8))
                }
            }
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            composerSectionLabel("Identity")

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Title")
                    .dsSmallCapsLabel()

                TextField("Writing Habit", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(DS.dateSerif)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space10)
                    .background(DS.vellumDeep, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.sepiaBorder, lineWidth: 0.5)
                    )
                    .disabled(isBuiltIn)
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Icon")
                    .dsSmallCapsLabel()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                    ForEach(habitIconOptions, id: \.self) { icon in
                        iconButton(icon)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Accent")
                    .dsSmallCapsLabel()

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
            composerSectionLabel("Cadence")

            HStack(spacing: DS.space12) {
                cadenceStepButton(systemImage: "minus", enabled: draft.dailyTargetCount > 1) {
                    draft.dailyTargetCount = max(1, draft.dailyTargetCount - 1)
                }

                VStack(spacing: 2) {
                    Text("\(draft.dailyTargetCount)")
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(DS.text)
                    Text(draft.dailyTargetCount == 1 ? "per day" : "times per day")
                        .font(DS.callout)
                        .foregroundStyle(DS.inkFaded)
                }
                .frame(maxWidth: .infinity)

                cadenceStepButton(systemImage: "plus", enabled: draft.dailyTargetCount < 12) {
                    draft.dailyTargetCount = min(12, draft.dailyTargetCount + 1)
                }
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space12)
            .background(DS.vellumDeep, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DS.sepiaBorder, lineWidth: 0.5)
            )

            HStack(spacing: DS.space8) {
                ForEach([1, 2, 3, 5], id: \.self) { target in
                    cadenceChip(target)
                }
            }
        }
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            composerSectionLabel("Mapping")

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Intent bindings")
                    .dsSmallCapsLabel()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(TaskIntent.allCases.filter { $0 != .general && $0 != .custom }, id: \.self) { intent in
                        intentChip(intent)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Keyword triggers")
                    .dsSmallCapsLabel()

                TextField("write, draft, article", text: $draft.keywordInput)
                    .textFieldStyle(.plain)
                    .font(DS.dateSerif)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space10)
                    .background(DS.vellumDeep, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.sepiaBorder, lineWidth: 0.5)
                    )
                    .disabled(isBuiltIn)
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Default intent")
                    .dsSmallCapsLabel()

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
                    .background(DS.vellumDeep, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.sepiaBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            composerSectionLabel("Completion")

            Toggle(isOn: $draft.allowManualCompletion) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow manual check-ins")
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    Text("Lets the orbit card record progress even when there is no linked task.")
                        .font(DS.caption2)
                        .foregroundStyle(DS.inkFaded)
                }
            }
            .toggleStyle(.switch)
            .tint(DS.accent)
            .disabled(isBuiltIn)

            if isBuiltIn {
                Text("Built-in habits keep their core identity fixed so the command center stays coherent.")
                    .font(DS.caption2)
                    .foregroundStyle(DS.inkFaded)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            AkashicSectionDivider()
                .padding(.horizontal, 0)

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
                            .font(.system(size: 16, weight: .regular, design: .serif))
                        Image(systemName: "arrow.right")
                            .font(DS.subheadline).fontWeight(.medium)
                    }
                    .foregroundStyle(canSave ? DS.text : DS.inkFaded)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space10)
                    .overlay(alignment: .topLeading) { footerBracket(rotation: 0) }
                    .overlay(alignment: .topTrailing) { footerBracket(rotation: 90) }
                    .overlay(alignment: .bottomTrailing) { footerBracket(rotation: 180) }
                    .overlay(alignment: .bottomLeading) { footerBracket(rotation: 270) }
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
                .foregroundStyle(isSelected ? previewTint : DS.inkFaded)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(isSelected ? previewTint.opacity(0.10) : DS.vellumDeep, in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? previewTint.opacity(0.25) : DS.sepiaBorder, lineWidth: 0.5)
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
                        .stroke(isSelected ? DS.vellum : Color.clear, lineWidth: 2)
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
                .foregroundStyle(enabled ? DS.text : DS.inkFaded.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(DS.vellum, in: Circle())
                .overlay(Circle().stroke(DS.sepiaBorder, lineWidth: 0.5))
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
                .foregroundStyle(isSelected ? DS.text : DS.inkFaded)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .background(isSelected ? DS.giltSoft.opacity(0.9) : DS.vellumDeep, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DS.gilt.opacity(0.7) : DS.sepiaBorder, lineWidth: 0.5)
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
            .foregroundStyle(isSelected ? DS.text : DS.inkFaded)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space8)
            .background(isSelected ? intent.color.opacity(0.10) : DS.vellumDeep, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? intent.color.opacity(0.22) : DS.sepiaBorder, lineWidth: 0.5)
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
            .background(DS.vellumDeep, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(DS.sepiaBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func footerBracket(rotation: Double) -> some View {
        GiltCornerBracket()
            .stroke(DS.gilt.opacity(canSave ? 0.8 : 0.3), lineWidth: 0.8)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(rotation))
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
        CommandCenterComposerShell(title: "HABIT LIBRARY", subtitle: "Manage the orbits around your days", onClose: onClose) {
            VStack(alignment: .leading, spacing: DS.space20) {
                VStack(alignment: .leading, spacing: DS.space12) {
                    composerSectionLabel("Custom")

                    if customHabits.isEmpty {
                        Text("No custom habits yet. Start one and map it to the kinds of work you want to reinforce.")
                            .font(DS.callout)
                            .foregroundStyle(DS.inkFaded)
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
                                .font(DS.dateSerif)
                        }
                        .foregroundStyle(DS.accent)
                        .padding(.vertical, DS.space6)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: DS.space12) {
                    composerSectionLabel("Built In")

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
                        .foregroundStyle(DS.inkFaded)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(DS.caption2)
                    .foregroundStyle(DS.inkFaded)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(DS.vellumDeep, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.sepiaBorder, lineWidth: 0.5)
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
                    .foregroundStyle(item.isEnabled ? DS.text : DS.inkFaded)
                Text("Built-in")
                    .font(DS.caption2)
                    .foregroundStyle(DS.inkFaded)
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
        .background(DS.vellumDeep, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
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
